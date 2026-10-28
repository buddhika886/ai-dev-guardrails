#!/usr/bin/env bash
# Claude Code PreToolUse guard for Bash (Layer 2). Reads the hook JSON on stdin and answers in one of
# three ways. Only gates the AGENT's calls, not a human's `!` commands.
#
#   BLOCK  exit 2, reason on stderr (shown to the model). For things the agent must never do: touch
#          production from local, rewrite shared history, print a secret into the transcript.
#   ASK    exit 0 with a PreToolUse `permissionDecision: "ask"` on stdout. The user is prompted every
#          time, including in auto mode. For things that need fresh consent each time: commit, push,
#          publish, deploy, change remote secrets or config. Asking is cheap; acting without consent
#          is not, so this list errs wide.
#   ALLOW  exit 0, no output. The call carries on through the normal permission flow.
#
# The ASK list is the enforcement behind CLAUDE.md's consent rule. Writing the rule down was not
# enough in practice: allowlist wildcards accumulate in `.claude/settings.local.json` (one "Yes, and
# don't ask again" at a time) until `git push *` is pre-approved and the rule is prose only. The
# matching `permissions.ask` rules in `.claude/settings.json` are the second half: Claude Code
# evaluates ask rules before allow rules, so no allowlist entry can silence them.
#
# BLIND SPOT: read this before trusting it. This guard matches command TEXT. It cannot see through
# environment-variable indirection: a command like `psql "$DB_URL"` or `deploy --env "$TARGET"`
# reaches production without any prod hostname appearing in the text, so no pattern list can catch
# it. Adding prod-bearing env-var NAMES to the patterns (below) raises the bar, but the ACTUAL
# control for production safety is process, not this script: prepare-versus-execute. The agent
# prepares the exact prod commands and stops; a human runs them. Treat this guard as a backstop that
# catches the obvious cases, never as the thing that makes prod access safe. The same holds for the
# secret-disclosure check: it knows the common ways to print a secret, not every way.
#
# FAILS CLOSED. If the guard cannot read the command it is supposed to inspect, it does not wave the
# call through: no payload at all blocks, and an unparseable payload (or no JSON parser on PATH) is
# matched raw. Over-matching is the safe direction; a guard that goes quiet when its dependencies are
# missing is worse than no guard, because you keep trusting it.
set -uo pipefail

# ---- CONFIG: filled by /bootstrap ----
# Patterns that indicate a command is touching PRODUCTION from local (hosts, deploy/link verbs).
PROD_GUARD_PATTERNS='{{PROD_GUARD_PATTERNS}}'
# Env-var NAMES that carry production credentials/targets. If a command references one of these,
# treat it as prod-touching even when no hostname is literally present.
PROD_ENV_VAR_NAMES='{{PROD_ENV_VAR_NAMES}}'
# Server secret env-var NAMES. Echoing or printenv-ing one of these prints the secret into the
# session transcript, so it is blocked.
SECRET_VAR_NAMES='{{SECRET_VAR_NAMES}}'
# --------------------------------------

# ---- BUILT-IN: not filled by bootstrap. Extend these lists for your stack; do not shorten them. ----
# A word boundary that works in both GNU and BSD grep -E (no \b): start of text or a character that
# cannot be part of a command name.
B='(^|[^[:alnum:]_./-])'

# Consent: anything outward-facing. Prompted every time, never silently allowed.
# git options before the subcommand (-C path, -c k=v, --no-pager) are skipped so `git -C . push`
# still asks.
GIT_OPTS='([[:space:]]+-[^[:space:]]*([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'
CONSENT_PATTERNS="${B}git${GIT_OPTS}[[:space:]]+(commit|push)([[:space:]]|$)"
CONSENT_PATTERNS+="|${B}gh[[:space:]]+(pr[[:space:]]+(create|merge|close|ready)|release[[:space:]]+(create|upload|edit|delete)|repo[[:space:]]+(create|edit|delete)|workflow[[:space:]]+run)"
CONSENT_PATTERNS+="|${B}gh[[:space:]]+api[^|;&]*(-X|--method)[[:space:]=]*(POST|PUT|PATCH|DELETE)"
CONSENT_PATTERNS+="|${B}(npm|pnpm|yarn|bun)([[:space:]]+npm)?[[:space:]]+(publish|unpublish|deprecate|dist-tag)"
CONSENT_PATTERNS+="|${B}changeset[[:space:]]+publish"
CONSENT_PATTERNS+="|${B}docker[[:space:]]+push"

# Deploys and remote database changes. On by default: a project with no production yet still gets
# a prompt, because the cost of a question is lower than the cost of an unintended deploy.
DEPLOY_PATTERNS="${B}vercel([[:space:]]+(deploy|promote|rollback|redeploy|alias)|[^|;&]*--prod)"
DEPLOY_PATTERNS+="|${B}netlify[[:space:]]+deploy"
DEPLOY_PATTERNS+="|${B}wrangler[[:space:]]+(deploy|publish|rollback|(pages|versions)[[:space:]]+deploy)"
DEPLOY_PATTERNS+="|${B}fly(ctl)?[[:space:]]+deploy"
DEPLOY_PATTERNS+="|${B}firebase[[:space:]]+deploy"
DEPLOY_PATTERNS+="|${B}railway[[:space:]]+(up|redeploy)"
DEPLOY_PATTERNS+="|${B}heroku[[:space:]]+releases:rollback"
DEPLOY_PATTERNS+="|${B}(serverless|sls)[[:space:]]+deploy"
DEPLOY_PATTERNS+="|${B}eas[[:space:]]+(submit|update)"
DEPLOY_PATTERNS+="|${B}supabase[[:space:]]+(db[[:space:]]+push|functions[[:space:]]+deploy)"
DEPLOY_PATTERNS+="|${B}prisma[[:space:]]+(migrate[[:space:]]+deploy|db[[:space:]]+push)"
DEPLOY_PATTERNS+="|${B}drizzle-kit[[:space:]]+(push|migrate)"

# Remote secrets and config. A change made here is invisible to the repo, which is how out-of-band
# drift starts.
REMOTE_CONFIG_PATTERNS="${B}gh[[:space:]]+(secret|variable)[[:space:]]+(set|delete|remove)"
REMOTE_CONFIG_PATTERNS+="|${B}wrangler[[:space:]]+secret[[:space:]]+(put|delete|bulk)"
REMOTE_CONFIG_PATTERNS+="|${B}vercel[[:space:]]+env[[:space:]]+(add|rm|remove)"
REMOTE_CONFIG_PATTERNS+="|${B}fly(ctl)?[[:space:]]+secrets[[:space:]]+(set|unset|import)"
REMOTE_CONFIG_PATTERNS+="|${B}supabase[[:space:]]+secrets[[:space:]]+(set|unset)"
REMOTE_CONFIG_PATTERNS+="|${B}heroku[[:space:]]+config:(set|unset)"

# Secret disclosure. These print a secret into the session transcript, where it is stored and can
# outlive any rotation. Blocked, not redacted: a home-made redaction pipe that fails open leaks the
# value it was meant to hide, and nothing downstream can take it back.
SECRET_READERS='(cat|bat|less|more|head|tail|nl|strings|xxd|od|hexdump|grep|egrep|fgrep|rg|ag|awk|sed|cut|sort|uniq|diff|base64|jq|yq)'
# SC2016: $HOME here is a literal regex alternative, matched in the command text, not expanded.
# shellcheck disable=SC2016
SECRET_FILES='(\.env(\.[A-Za-z0-9_-]+)*|\.dev\.vars|(~|\$HOME|\$\{HOME\})/\.npmrc|\.netrc|\.pgpass|credentials(\.json)?|[^[:space:]]+\.pem|[^[:space:]]+\.key|[^[:space:]]+\.p12|[^[:space:]]+\.pfx|id_(rsa|dsa|ecdsa|ed25519)|\.docker/config\.json|\.kube/config)'
SECRET_FILE_READ="${B}${SECRET_READERS}([[:space:]][^|;&]*)?[[:space:]/=<\"']${SECRET_FILES}([[:space:]\"'|;&)>]|$)"
SECRET_FILE_READ+="|<[[:space:]]*${SECRET_FILES}([[:space:]\"'|;&)>]|$)"
# A bare environment dump, at the start of a command or after a separator.
ENV_DUMP='(^|[;&|({][[:space:]]*|\$\([[:space:]]*)(env|printenv|set|export[[:space:]]+-p|declare[[:space:]]+-[px]+)[[:space:]]*($|[|;&)>])'
ENV_DUMP+='|process\.env[[:space:]]*[),]|os\.environ[[:space:]]*[),]'
# Any variable whose name says it is a secret, echoed.
SECRET_NAME_SHAPE='[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY|ACCESS_?KEY|CREDENTIALS?)[A-Za-z0-9_]*'
# Secret managers and platform CLIs whose purpose is to print a secret.
SECRET_CLIS="${B}(op[[:space:]]+(read|inject|item[[:space:]]+get)|doppler[[:space:]]+secrets|vault[[:space:]]+(kv[[:space:]]+get|read)|gh[[:space:]]+auth[[:space:]]+token|heroku[[:space:]]+config([[:space:]]|$)|aws[[:space:]]+secretsmanager[[:space:]]+get-secret-value|gcloud[[:space:]]+secrets[[:space:]]+versions[[:space:]]+access|az[[:space:]]+keyvault[[:space:]]+secret[[:space:]]+show|kubectl[[:space:]]+get[[:space:]]+secrets?[^|;&]*-o)"
# ------------------------------------------------------------------------------------------------

payload=$(cat)

# No payload means the guard was invoked outside the hook contract and cannot see what it is being
# asked to approve. Block: a loud, obvious failure beats a silent hole.
if [ -z "$payload" ]; then
  echo "BLOCKED: the bash guard received no hook payload, so it cannot inspect this command. Failing closed. Check the PreToolUse hook wiring in .claude/settings.json." >&2
  exit 2
fi

# Extract tool_input.command with whichever JSON parser is available. Both parsers exit non-zero on
# malformed input so the fallback below is reached rather than an empty command being trusted.
SUFFIX=''
cmd=''
extracted=0
if command -v node >/dev/null 2>&1; then
  if cmd=$(printf '%s' "$payload" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let j;try{j=JSON.parse(s)}catch(e){process.exit(3)}process.stdout.write(((j&&j.tool_input)||{}).command||"")})' 2>/dev/null); then
    extracted=1
  fi
fi
if [ "$extracted" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
  if cmd=$(printf '%s' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.stdout.write((d.get("tool_input") or {}).get("command") or "")' 2>/dev/null); then
    extracted=1
  fi
fi
if [ "$extracted" -eq 0 ]; then
  # Unparseable payload, or no parser on PATH. Match the patterns against the raw payload instead of
  # trusting an empty string. This can over-match; that is the direction to err in.
  cmd="$payload"
  SUFFIX=' (the guard could not parse the hook payload and matched the raw payload instead)'
fi

block() { echo "BLOCKED: $1${SUFFIX}" >&2; exit 2; }

# Every match below feeds grep from a here-string, never `printf ... | grep -q`. grep -q exits at
# the first match; under pipefail a writer still holding more than a pipe buffer (64 KiB) then dies
# of SIGPIPE, the pipeline reports failure, and the match is lost. A long multi-line command would
# fail open. tests/hook-cases.sh ("a long command must not slip past") holds this in place.

# ======== BLOCK: never from the agent ========

# 1) Production from local: by host/verb pattern.
if [ -n "$PROD_GUARD_PATTERNS" ] && grep -qiE "$PROD_GUARD_PATTERNS" <<<"$cmd"; then
  block "this targets PRODUCTION from local. Prod is off-limits from local (CLAUDE.md); prepare the steps for a human to run instead."
fi

# 1b) Production from local: by prod-bearing env-var name.
if [ -n "$PROD_ENV_VAR_NAMES" ]; then
  names=$(printf '%s' "$PROD_ENV_VAR_NAMES" | tr ' ' '|')
  if grep -qE "$names" <<<"$cmd"; then
    block "command references a production credential/target env var. Prepare the steps for a human to run against prod; do not execute from local (CLAUDE.md)."
  fi
fi

# 2a) Force-push.
if grep -qiE 'git[[:space:]]+push' <<<"$cmd" && grep -qiE '(--force|--force-with-lease|[[:space:]]-f([[:space:]]|$))' <<<"$cmd"; then
  block "force-push is not allowed on the shared repo (never force-push over others' history)."
fi

# 2b) Other destructive git.
if grep -qiE 'git[[:space:]]+reset[[:space:]].*--hard|git[[:space:]]+clean[[:space:]]+-[A-Za-z]*f' <<<"$cmd"; then
  block "destructive git (reset --hard / clean -f). Confirm with the user and run it yourself if truly intended."
fi

# 3) Secret disclosure into the transcript.
DISCLOSE="this would print a secret into the session transcript, which is stored and cannot be taken back (CLAUDE.md, Transcript hygiene). Do not try to redact it with a pipe. To check a value is set, test for presence without printing it, e.g. [ -n \"\$NAME\" ] && echo set. If a human needs to see the value, they should read it in their own terminal, outside this session: a ! command's output also lands in the transcript."
# Committed example files are safe to read; scrub them out before matching so `cat .env.example`
# is not caught by the `.env*` shape.
scrubbed=$(printf '%s' "$cmd" | sed -E 's/\.(env|dev\.vars)\.(example|sample|template|dist)([^A-Za-z0-9_-]|$)/\3/g')
if grep -qiE "$SECRET_FILE_READ" <<<"$scrubbed"; then block "$DISCLOSE"; fi
if grep -qE "$ENV_DUMP" <<<"$cmd"; then block "$DISCLOSE"; fi
if grep -qiE "$SECRET_CLIS" <<<"$cmd"; then block "$DISCLOSE"; fi
secret_names="$SECRET_NAME_SHAPE"
if [ -n "$SECRET_VAR_NAMES" ]; then
  secret_names="${secret_names}|$(printf '%s' "$SECRET_VAR_NAMES" | tr ' ' '|')"
fi
if grep -qE "${B}(echo|printf|print)[^|;&]*\\\$\\{?(${secret_names})([^A-Za-z0-9_]|$)" <<<"$cmd"; then
  block "$DISCLOSE"
fi
if grep -qE "${B}printenv[[:space:]]+([^|;&]*[[:space:]])?(${secret_names})([^A-Za-z0-9_]|$)" <<<"$cmd"; then
  block "$DISCLOSE"
fi

# ======== ASK: fresh consent every time ========

# Emits a PreToolUse "ask" decision. The reason is built from fixed strings with no quotes or
# backslashes, so it is valid JSON by construction and needs no encoder on PATH.
ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1${SUFFIX}"
  exit 0
}

if grep -qiE "$CONSENT_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this commits, pushes, publishes or changes something outside this machine. CLAUDE.md requires your explicit go-ahead each time."
fi
if grep -qiE "$DEPLOY_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this deploys or changes a remote database. Confirm the target is not production, or that you intend it."
fi
if grep -qiE "$REMOTE_CONFIG_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this changes remote secrets or config, which the repo cannot see. Record it so it is not later found as unexplained drift."
fi

exit 0
