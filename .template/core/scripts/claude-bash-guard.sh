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
# An unfilled token is not a pattern. The template repository runs this guard on itself before
# bootstrap has filled anything; a literal {{...}} fed to grep -E would be a broken regex on BSD grep
# and a meaningless one on GNU grep, so it is treated as empty instead.
for v in PROD_GUARD_PATTERNS PROD_ENV_VAR_NAMES SECRET_VAR_NAMES; do
  case "${!v}" in '{{'*'}}') printf -v "$v" '%s' '' ;; esac
done
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
# An alias defined on the command line (`git -c alias.p=push p`) moves the verb out of the position
# the patterns above look at. Any on-the-fly alias is treated as the consent command it could hide.
GIT_ALIAS="${B}git[^|;&]*[[:space:]]-c[[:space:]]*alias\\."

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

# Adding a dependency. A new package is a supply-chain decision: it may be vulnerable, malicious, or
# a name an assistant made up. `npm install` and `npm ci` with no package name only install what the
# lockfile already holds, so they stay allowed; so does `npx`, whose downloads obey the .npmrc
# cooldown and script policy. pnpm, yarn and bun do not read npm's policy, so their adds and one-shot
# runners ask too. Approving install scripts is the same decision by another route.
PKG_FLAGS='([[:space:]]+-[^[:space:]]*)*'
DEPENDENCY_PATTERNS="${B}npm[[:space:]]+(install|i|in|add|isntall)${PKG_FLAGS}[[:space:]]+[^-[:space:]|;&]"
DEPENDENCY_PATTERNS+="|${B}(pnpm|yarn|bun)[[:space:]]+add([[:space:]]|$)"
DEPENDENCY_PATTERNS+="|${B}bun[[:space:]]+(install|i)${PKG_FLAGS}[[:space:]]+[^-[:space:]|;&]"
DEPENDENCY_PATTERNS+="|${B}(pnpm|yarn)[[:space:]]+dlx([[:space:]]|$)|${B}bunx([[:space:]]|$)"
DEPENDENCY_PATTERNS+="|${B}npm[[:space:]]+approve-scripts"

# Fetching from the network from the shell: curl, wget and HTTPie (http, https, xh). Asked: a
# fetch can bring in instructions or code from anywhere, and can carry data out. Claude's own
# web-fetch tool is governed by .claude/settings.json (bootstrap question Q7); this is the shell's
# counterpart. Sending a secret file with curl or wget (`-d @.env`) is blocked, not asked, by the
# secret-file rules above.
NETWORK_FETCH="${B}(curl|wget|http|https|xh)[[:space:]]"
# This machine's own addresses. A plain curl or wget to them only is exempt (see local_fetch), so
# `curl localhost:3000` runs without asking. Add a host only if it can never mean another machine.
LOCAL_HOSTS='(localhost|127\.0\.0\.1|\[::1\])'

# Rewriting an enforcement file from the shell. The Edit and Write ask rules in .claude/settings.json
# cover the editing tools; this covers sed -i, redirects, tee, cp, mv, rm and the like on the same
# files. Asked, not blocked: maintaining the guardrails is legitimate work, but it is never work the
# agent does on its own say-so.
ENFORCEMENT_FILES='(scripts/(claude-bash-guard|ci-guardrails|claude-stop-guardrails)\.sh|lefthook\.yml|\.github/workflows/ci\.yml|\.github/CODEOWNERS|\.gitleaks\.toml|\.claude/settings\.json|CLAUDE\.md|\.npmrc|\.mcp\.json|\.guardrails/guard\.log)'
ENFORCEMENT_WRITE="${B}(sed[^|;&]*[[:space:]]-[a-zA-Z]*i|perl[^|;&]*[[:space:]]-[a-zA-Z]*i|tee|cp|mv|rm|truncate|chmod|install|ln)[[:space:]][^|;&]*${ENFORCEMENT_FILES}([[:space:]\"'|;&)]|$)"
ENFORCEMENT_WRITE+="|>>?[[:space:]]*[\"']?${ENFORCEMENT_FILES}([[:space:]\"'|;&)]|$)"

# Switching off the dependency policy in .npmrc for one command. Every key here would let a
# brand-new, unreviewed or non-registry package in. Changing the policy is a reviewed edit to .npmrc,
# never a flag or an environment variable the agent sets on the way past. Environment variables
# override the project .npmrc, so they are matched too.
DEP_POLICY_KEYS='(min-release-age|before|allow-git|allow-remote|strict-allow-scripts|dangerously-allow-all-scripts|registry)'
DEP_WEAKEN="${B}(npm|npx|pnpm|yarn|bun)[^|;&]*[[:space:]]--(no-)?${DEP_POLICY_KEYS}([=[:space:]]|$)"
DEP_WEAKEN+="|${B}npm[[:space:]]+config[[:space:]]+(edit|(set|delete|rm)[^|;&]*${DEP_POLICY_KEYS})"
DEP_WEAKEN+="|npm_config_(min_release_age|before|allow_git|allow_remote|strict_allow_scripts|dangerously_allow_all_scripts|registry)"

# Secret disclosure. These print a secret into the session transcript, where it is stored and can
# outlive any rotation. Blocked, not redacted: a home-made redaction pipe that fails open leaks the
# value it was meant to hide, and nothing downstream can take it back.
SECRET_READERS='(cat|bat|less|more|head|tail|nl|strings|xxd|od|hexdump|grep|egrep|fgrep|rg|ag|awk|sed|cut|sort|uniq|diff|base64|jq|yq|curl|wget)'
# SC2016: $HOME here is a literal regex alternative, matched in the command text, not expanded.
# shellcheck disable=SC2016
SECRET_FILES='(\.env(\.[A-Za-z0-9_-]+)*|\.dev\.vars|\.claude/profiles/[^[:space:]]*\.settings\.json|\.guardrails/[^[:space:]]*\.local|/proc/(self|[0-9]+)/environ|(~|\$HOME|\$\{HOME\})/\.npmrc|\.netrc|\.pgpass|credentials(\.json)?|[^[:space:]]+\.pem|[^[:space:]]+\.key|[^[:space:]]+\.p12|[^[:space:]]+\.pfx|id_(rsa|dsa|ecdsa|ed25519)|\.docker/config\.json|\.kube/config)'
SECRET_FILE_READ="${B}${SECRET_READERS}([[:space:]][^|;&]*)?[[:space:]/=<@\"']${SECRET_FILES}([[:space:]\"'|;&)>]|$)"
SECRET_FILE_READ+="|<[[:space:]]*${SECRET_FILES}([[:space:]\"'|;&)>]|$)"
# The shell expands globs after the guard has looked, so `cat .en*` reads .env while the text never
# says so. A secret reader given a dotfile glob, a glob ending in a key extension, or `.*` is blocked.
GLOB_READ="${B}${SECRET_READERS}([[:space:]][^|;&]*)?[[:space:]/=][\"']?((\./)?\.[A-Za-z0-9_.-]*[*?[][^[:space:]]*|[^[:space:]]*[*?[][^[:space:]]*\.(pem|key|p12|pfx)|\.\*)([[:space:]\"'|;&)>]|$)"
# A bare environment dump, at the start of a command or after a separator.
# Matched at a word boundary rather than only at the start of a command, so a prefix
# (`FOO=bar env`, `eval 'env'`) does not hide it. `env -0` is the same dump with NUL separators.
# `env FOO=1 cmd` (running a command with a variable set) stays allowed: nothing follows the dump.
ENV_DUMP="${B}(env|printenv)([[:space:]]+-0)?[[:space:]]*($|[|;&)>'\"])"
# `set` is also an ordinary word (`echo set`), so it keeps the command-position anchor.
ENV_DUMP+="|(^|[;&|({][[:space:]]*|\\$\\([[:space:]]*)(set|export[[:space:]]+-p|declare[[:space:]]+-[px]+)[[:space:]]*($|[|;&)>])"
ENV_DUMP+='|process\.env[[:space:]]*[),]|os\.environ[[:space:]]*[),]'
# Any variable whose name says it is a secret, echoed.
SECRET_NAME_SHAPE='[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY|ACCESS_?KEY|CREDENTIALS?)[A-Za-z0-9_]*'
# Secret managers and platform CLIs whose purpose is to print a secret.
SECRET_CLIS="${B}(op[[:space:]]+(read|inject|item[[:space:]]+get)|doppler[[:space:]]+secrets|vault[[:space:]]+(kv[[:space:]]+get|read)|gh[[:space:]]+auth[[:space:]]+token|heroku[[:space:]]+config([[:space:]]|$)|aws[[:space:]]+secretsmanager[[:space:]]+get-secret-value|gcloud[[:space:]]+secrets[[:space:]]+versions[[:space:]]+access|az[[:space:]]+keyvault[[:space:]]+secret[[:space:]]+show|kubectl[[:space:]]+get[[:space:]]+secrets?[^|;&]*-o)"
# ------------------------------------------------------------------------------------------------

# ---- Decision log ----
# One line per block or ask: UTC time, decision, rule name. Never the command, which can hold a
# secret. Kept on this machine in .guardrails/guard.log (gitignored), as a record of what the AI tried
# and what was stopped. Best effort by design: a failure to write is ignored, so logging can never
# change a decision. A symlinked folder or log is not written through. Past GUARD_LOG_MAX_BYTES the
# log moves to guard.log.1 and a new one starts.
GUARD_LOG_MAX_BYTES=1048576
guard_log() {
  (
    root="${CLAUDE_PROJECT_DIR:-}"
    if [ -z "$root" ]; then root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0; fi
    d="$root/.guardrails"; f="$d/guard.log"
    if [ -L "$d" ] || [ -L "$f" ] || [ -L "$f.1" ]; then exit 0; fi
    mkdir -p "$d" || exit 0
    if [ -f "$f" ] && [ "$(( $(wc -c < "$f") ))" -gt "$GUARD_LOG_MAX_BYTES" ]; then mv -f "$f" "$f.1"; fi
    printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >> "$f"
  ) >/dev/null 2>&1 || true
}

payload=$(cat)

# The filled values are matched with grep -E below. An invalid pattern makes grep exit 2, and in a
# test-then-match chain that reads as "no match": the check it feeds disappears with
# only a line on stderr. So every filled pattern is tried once here, and a bad one blocks every
# command until it is fixed. A loud, obvious failure beats a guard that has quietly gone blind.
for v in PROD_GUARD_PATTERNS PROD_ENV_VAR_NAMES SECRET_VAR_NAMES; do
  val="${!v}"
  [ -z "$val" ] && continue
  case "$v" in
    *_NAMES)
      # Space-separated identifiers only: they are joined with | into a regex, and a name is never a
      # quote, a bracket or a shell metacharacter.
      if ! grep -qE '^[A-Za-z_][A-Za-z0-9_]*( +[A-Za-z_][A-Za-z0-9_]*)* *$' <<<"$val"; then
        echo "BLOCKED: the bash guard is misconfigured: $v must be space-separated variable names (got: $val). Fix scripts/claude-bash-guard.sh; every command is blocked until it is valid." >&2
        guard_log block MISCONFIGURED; exit 2
      fi ;;
    *)
      grep -qE "$val" <<<"" 2>/dev/null; rc=$?
      if [ "$rc" -ge 2 ]; then
        echo "BLOCKED: the bash guard is misconfigured: $v is not a valid extended regex. Fix scripts/claude-bash-guard.sh; every command is blocked until it is valid." >&2
        guard_log block MISCONFIGURED; exit 2
      fi ;;
  esac
done

# No payload means the guard was invoked outside the hook contract and cannot see what it is being
# asked to approve. Block: a loud, obvious failure beats a silent hole.
if [ -z "$payload" ]; then
  echo "BLOCKED: the bash guard received no hook payload, so it cannot inspect this command. Failing closed. Check the PreToolUse hook wiring in .claude/settings.json." >&2
  guard_log block NO_PAYLOAD; exit 2
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

# block <reason> <rule>, and ask below: the rule name goes to the decision log. "(raw)" marks a
# decision made on the raw payload because it could not be parsed.
block() { guard_log "block${SUFFIX:+(raw)}" "${2:-UNNAMED}"; echo "BLOCKED: $1${SUFFIX}" >&2; exit 2; }

# Every match below feeds grep from a here-string, never `printf ... | grep -q`. grep -q exits at
# the first match; under pipefail a writer still holding more than a pipe buffer (64 KiB) then dies
# of SIGPIPE, the pipeline reports failure, and the match is lost. A long multi-line command would
# fail open. tests/hook-cases.sh ("a long command must not slip past") holds this in place.

# ======== BLOCK: never from the agent ========

# 1) Production from local: by host/verb pattern.
if [ -n "$PROD_GUARD_PATTERNS" ] && grep -qiE "$PROD_GUARD_PATTERNS" <<<"$cmd"; then
  block "this targets PRODUCTION from local. Prod is off-limits from local (CLAUDE.md); prepare the steps for a human to run instead." PROD_GUARD_PATTERNS
fi

# 1b) Production from local: by prod-bearing env-var name.
if [ -n "$PROD_ENV_VAR_NAMES" ]; then
  names=$(printf '%s' "$PROD_ENV_VAR_NAMES" | tr ' ' '|')
  if grep -qE "$names" <<<"$cmd"; then
    block "command references a production credential/target env var. Prepare the steps for a human to run against prod; do not execute from local (CLAUDE.md)." PROD_ENV_VAR_NAMES
  fi
fi

# 2a) Force-push.
# `+ref` is a force-push by refspec, `--mirror` overwrites every ref, `--delete`/`-d` removes one.
if grep -qiE 'git[[:space:]]+push|alias\.[^=[:space:]]*=push' <<<"$cmd" && grep -qiE "(--force|--force-with-lease|--mirror|--delete|[[:space:]]-[fd]([[:space:]]|$)|[[:space:]][\"']?\+[A-Za-z0-9_./-]+)" <<<"$cmd"; then
  block "force-push, mirror or remote branch delete is not allowed on the shared repo (never rewrite others' history)." FORCE_PUSH
fi

# 2b) Other destructive git.
if grep -qiE 'git[[:space:]]+reset[[:space:]].*--hard|git[[:space:]]+clean[[:space:]]+(-[A-Za-z]*f|--force)' <<<"$cmd"; then
  block "destructive git (reset --hard / clean -f). Confirm with the user and run it yourself if truly intended." DESTRUCTIVE_GIT
fi

# 3) Secret disclosure into the transcript.
DISCLOSE="this would print a secret into the session transcript, which is stored and cannot be taken back (CLAUDE.md, Transcript hygiene). Do not try to redact it with a pipe. To check a value is set, test for presence without printing it, e.g. [ -n \"\$NAME\" ] && echo set. If a human needs to see the value, they should read it in their own terminal, outside this session: a ! command's output also lands in the transcript."
# Committed example files are safe to read; scrub them out before matching so `cat .env.example`
# is not caught by the `.env*` shape.
scrubbed=$(printf '%s' "$cmd" | sed -E 's/\.(env|dev\.vars)\.(example|sample|template|dist)([^A-Za-z0-9_-]|$)/\3/g')
if grep -qiE "$SECRET_FILE_READ" <<<"$scrubbed"; then block "$DISCLOSE" SECRET_FILE_READ; fi
if grep -qiE "$GLOB_READ" <<<"$scrubbed"; then block "$DISCLOSE" GLOB_READ; fi
if grep -qE "$ENV_DUMP" <<<"$cmd"; then block "$DISCLOSE" ENV_DUMP; fi
if grep -qiE "$SECRET_CLIS" <<<"$cmd"; then block "$DISCLOSE" SECRET_CLIS; fi
secret_names="$SECRET_NAME_SHAPE"
if [ -n "$SECRET_VAR_NAMES" ]; then
  secret_names="${secret_names}|$(printf '%s' "$SECRET_VAR_NAMES" | tr ' ' '|')"
fi
if grep -qE "${B}(echo|printf|print)[^|;&]*\\\$\\{?(${secret_names})([^A-Za-z0-9_]|$)" <<<"$cmd"; then
  block "$DISCLOSE" SECRET_NAME_SHAPE
fi
if grep -qE "${B}printenv[[:space:]]+([^|;&]*[[:space:]])?(${secret_names})([^A-Za-z0-9_]|$)" <<<"$cmd"; then
  block "$DISCLOSE" SECRET_NAME_SHAPE
fi
# The same secrets reached through code or a here-string rather than echo: node -e
# 'console.log(process.env.NAME)', python's os.environ["NAME"], awk's ENVIRON["NAME"], and
# `cat <<< "$NAME"` / `tee x <<< "$NAME"`.
SECRET_VIA_CODE="process\\.env\\.(${secret_names})([^A-Za-z0-9_]|$)|(os\\.environ|ENVIRON)(\\.get)?[[(][[:space:]]*[\"'](${secret_names})[\"']|<<<[[:space:]]*[\"']?\\$\\{?(${secret_names})([^A-Za-z0-9_]|$)"
if grep -qE "$SECRET_VIA_CODE" <<<"$cmd"; then
  block "$DISCLOSE" SECRET_VIA_CODE
fi

# 4) Switching off the dependency policy.
if grep -qiE "$DEP_WEAKEN" <<<"$cmd"; then
  block "this overrides the dependency policy in .npmrc (release cooldown, install-script approval, git/URL dependencies or the registry). Change .npmrc in a reviewed pull request instead; never bypass it for one command." DEP_WEAKEN
fi

# ======== ASK: fresh consent every time ========

# local_fetch <cmd>: true only for one plain curl or wget command whose only hosts are this
# machine's own. Strict on purpose: a second command, a redirect, a variable, a proxy, resolve or
# config flag, a secret file, or any other host or IP anywhere in the text means it asks instead.
local_fetch() {
  local c="$1" rest
  grep -qE '^[[:space:]]*(curl|wget)[[:space:]]' <<<"$c" || return 1
  [ "$(printf '%s' "$c" | wc -l | tr -d ' ')" = "0" ] || return 1
  # SC2016: $ is literal here, one of the characters that rule out the exemption (a variable could
  # expand to any host).
  # shellcheck disable=SC2016
  grep -qE '[;&|`<>$()\\]' <<<"$c" && return 1
  grep -qE '(^|[[:space:]])(-K|--config|--input-file|-e|--execute|-x|--proxy|--preproxy|--resolve|--connect-to|--doh-url|--socks[0-9a-z]*)([=[:space:]]|$)' <<<"$c" && return 1
  grep -qiE "$SECRET_FILES" <<<"$c" && return 1
  grep -qiE "(^|[[:space:]/@\"'])${LOCAL_HOSTS}([:/[:space:]\"']|$)" <<<"$c" || return 1
  rest=$(tr '[:upper:]' '[:lower:]' <<<"$c" | sed -E "s#(https?://)?${LOCAL_HOSTS}##g")
  grep -qE '://|[a-z0-9-]+\.[a-z0-9-]+' <<<"$rest" && return 1
  return 0
}

# Emits a PreToolUse "ask" decision. The reason is built from fixed strings with no quotes or
# backslashes, so it is valid JSON by construction and needs no encoder on PATH.
ask() {
  guard_log "ask${SUFFIX:+(raw)}" "${2:-UNNAMED}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1${SUFFIX}"
  exit 0
}

if grep -qiE "$CONSENT_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this commits, pushes, publishes or changes something outside this machine. CLAUDE.md requires your explicit go-ahead each time." CONSENT_PATTERNS
fi
if grep -qiE "$GIT_ALIAS" <<<"$cmd"; then
  ask "Consent required: this defines a git alias on the command line, which can stand for commit, push or anything else. Run the real command instead so the guard can see it." GIT_ALIAS
fi
if grep -qiE "$DEPLOY_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this deploys or changes a remote database. Confirm the target is not production, or that you intend it." DEPLOY_PATTERNS
fi
if grep -qiE "$REMOTE_CONFIG_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this changes remote secrets or config, which the repo cannot see. Record it so it is not later found as unexplained drift." REMOTE_CONFIG_PATTERNS
fi
if grep -qiE "$DEPENDENCY_PATTERNS" <<<"$cmd"; then
  ask "Consent required: this adds a dependency or approves install scripts. Check the package name is the one you meant (assistants invent plausible names), that it is maintained, and that the project needs it." DEPENDENCY_PATTERNS
fi
if grep -qiE "$NETWORK_FETCH" <<<"$cmd" && ! local_fetch "$cmd"; then
  ask "Consent required: this fetches from the network from the shell (curl, wget or HTTPie). Check the address: a fetch can bring in instructions or code, and can carry data out. Requests to this machine only (localhost) do not ask." NETWORK_FETCH
fi
if grep -qE "$ENFORCEMENT_WRITE" <<<"$cmd"; then
  ask "Consent required: this rewrites a guardrail file (the command guard, the checks, the hooks, CI, CODEOWNERS, the secret-scanner config, CLAUDE.md or .npmrc). Changing the rules is a reviewed decision, never a side effect of a task; never weaken a check to make it pass." ENFORCEMENT_WRITE
fi

exit 0
