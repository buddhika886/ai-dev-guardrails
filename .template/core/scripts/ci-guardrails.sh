#!/usr/bin/env bash
# Repo "clean & secure" guardrails (Layer 3/4 core). Fails closed: exit 1 on any violation, and an
# error inside a check counts as a failure.
#   bash scripts/ci-guardrails.sh              # full run (CI)
#   GUARDRAILS_FAST=1 bash scripts/ci-guardrails.sh   # fast run (pre-commit): skips bundle scan
#   GUARDRAILS_BASE=<ref>                       # ref to diff migrations against (default origin/main)
#
# Everything project-specific is in the CONFIG block below; /bootstrap fills each value. Do not edit
# a check to make it pass. Change the configuration or fix the code.
#
# SC2001: `sed 's/^/  /'` prefixes every line of multi-line output; parameter expansion cannot.
# shellcheck disable=SC2001
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

# ---- CONFIG: filled by /bootstrap ----
# Filename shapes that must NEVER be tracked. The '.csv' shape is deliberately NOT in the default:
# it is noisy in data-heavy repos. Add '|.*\.csv' to SECRET_FILE_PATTERNS if this repo should never
# carry CSVs. ALLOWED_TRACKED subtracts the known-safe example files.
SECRET_FILE_PATTERNS='{{SECRET_FILE_PATTERNS}}'
ALLOWED_TRACKED='{{ALLOWED_TRACKED}}'
CLIENT_DIR='{{CLIENT_DIR}}'                 # client code dirs (space-separated): no secret names, no browser storage
SERVER_DIRS='{{SERVER_DIRS}}'               # server/edge code: parameterised SQL only
PUBLIC_VAR_PREFIX='{{PUBLIC_VAR_PREFIX}}'   # framework public-env prefix ('' to skip check 2)
PUBLIC_VAR_ALLOWLIST='{{PUBLIC_VAR_ALLOWLIST}}'   # space-separated allowed public vars
SECRET_VAR_NAMES='{{SECRET_VAR_NAMES}}'     # names that must not appear in CLIENT_DIR or bundle
UNSAFE_SQL='{{UNSAFE_SQL}}'                 # forbidden raw-SQL escape hatches
STORAGE_PATTERNS='{{STORAGE_PATTERNS}}'     # browser storage APIs banned in CLIENT_DIR
MIGRATIONS_DIR='{{MIGRATIONS_DIR}}'         # '' to skip the additive-migration check
BUNDLE_DIR='{{BUNDLE_DIR}}'                 # build output to scan ('' to skip check 6)
BUNDLE_LEAK_PATTERNS='{{BUNDLE_LEAK_PATTERNS}}'   # secret-like strings that must not ship
SCHEMA_DUMP_CMD='{{SCHEMA_DUMP_CMD}}'       # command that prints the schema ('' to skip check 7)
SCHEMA_DUMP_FILE='{{SCHEMA_DUMP_FILE}}'     # committed dump the schema is diffed against
GOVERNANCE_ENABLED='{{GOVERNANCE_ENABLED}}' # 'on' or 'off': whether the governance tier is installed
# --------------------------------------

# ---- BUILT-IN: not filled by bootstrap ----
# Client identifiers that must never be committed (a client's real legal name, a codename's
# expansion), one extended regex per line. The file is gitignored on purpose: a committed denylist
# naming the client would itself leak the name. CI reads the same list from the GUARDRAILS_DENYLIST
# environment variable (a repository secret) instead.
DENYLIST_FILE='.guardrails/denylist.local'
# Commands an allow rule must never pre-approve: the consent, deploy and secret-disclosure cases the
# bash guard handles. An allow rule matching any of these means "Yes, and don't ask again" has
# quietly turned a consent rule back into prose. Keep in step with scripts/claude-bash-guard.sh.
CONSENT_SAMPLES='git commit -m wip
git push origin main
gh pr create --fill
gh pr merge 1
npm publish
vercel deploy --prod
npx vercel deploy --prod
netlify deploy --prod
npx wrangler deploy
fly deploy
npx supabase db push
npx prisma migrate deploy
npx drizzle-kit push
gh secret set API_KEY
npm install left-pad
pnpm add left-pad
cat .env
printenv
sed -i s/exit 2/exit 0/ scripts/claude-bash-guard.sh'
# Rules that .claude/settings.json must keep, in full. Ask rules are evaluated before allow rules, so
# they hold even when an allowlist wildcard matches the same command; deny rules stop the Read tool
# opening secret files. Keep in step with .template/core/settings.json.
REQUIRED_ASK_RULES='Bash(git commit *)
Bash(git push *)
Bash(gh pr create *)
Bash(gh pr merge *)
Bash(gh release create *)
Bash(npm publish *)
Bash(pnpm publish *)
Bash(yarn publish *)
Bash(yarn npm publish *)
Bash(bun publish *)
Edit(.npmrc)
Edit(scripts/claude-bash-guard.sh)
Edit(scripts/ci-guardrails.sh)
Edit(scripts/claude-stop-guardrails.sh)
Edit(lefthook.yml)
Edit(.github/workflows/ci.yml)
Edit(.github/CODEOWNERS)
Edit(.gitleaks.toml)
Edit(CLAUDE.md)'
REQUIRED_DENY_RULES='Read(.env)
Read(.env.*)
Read(.dev.vars)
Read(*.pem)
Read(*.key)
Read(*.p12)
Read(*.pfx)
Read(~/.npmrc)
Read(~/.netrc)
Read(~/.pgpass)
Read(~/.ssh/id_*)
Read(~/.aws/credentials)
Read(~/.docker/config.json)
Read(~/.kube/config)'
# Where the governance tier's records live, when it is installed.
GOVERNANCE_DIR='docs/governance'
# Dependency policy (check 12). A release must be at least this many days old before npm installs
# it: hijacked releases are usually caught and pulled within days, and a package name an assistant
# invented is almost always brand new. npm ignores min-release-age before 11.10.0, so an older npm
# fails the check rather than quietly skipping the cooldown. Lockfile entries must resolve to one of
# the registries below (space-separated, each ending in /); add a private registry here if you use one.
MIN_RELEASE_AGE_DAYS=7
NPM_MIN_VERSION='11.10.0'
ALLOWED_REGISTRIES='https://registry.npmjs.org/'
# --------------------------------------

fails=0; fail(){ echo "  ✗ $1"; fails=$((fails+1)); }; ok(){ echo "  ✓ $1"; }
# A check turned off by configuration still reports itself, so a reader of the CI log can tell
# "deliberately not applicable here" from "silently stopped working". Never print ✓ for a skip.
skipped(){ echo "$1: SKIPPED ($2)"; }
# The same rule for a check that is configured but cannot run THIS time (fast mode, no build output
# yet, no base ref). It prints under the check's heading with no tick, so the log never shows an
# unrun check as verified.
skip_note(){ echo "  - SKIPPED ($1)"; }
FAST="${GUARDRAILS_FAST:-0}"; BASE="${GUARDRAILS_BASE:-origin/main}"

# ---- Configuration self-check. A pattern grep cannot parse makes grep exit 2, and `|| true` or a
# `&&` chain turns that into "no match": the check prints a tick while scanning nothing. So every
# filled pattern is tried once, every configured directory must exist, and a failure here is a
# failure of the run. The same discipline applies below: a grep exit of 2 or more is reported, never
# treated as a clean result. ----
echo "[0] Configuration is valid"
cfg_ok=1
for v in SECRET_FILE_PATTERNS ALLOWED_TRACKED UNSAFE_SQL STORAGE_PATTERNS BUNDLE_LEAK_PATTERNS PUBLIC_VAR_PREFIX; do
  val="${!v}"; [ -z "$val" ] && continue
  grep -qE "$val" <<<"" 2>/dev/null; rc=$?
  if [ "$rc" -ge 2 ]; then fail "$v is not a valid extended regex (the checks it feeds would scan nothing)"; cfg_ok=0; fi
done
for v in SECRET_VAR_NAMES PUBLIC_VAR_ALLOWLIST; do
  val="${!v}"; [ -z "${val// /}" ] && continue
  if ! grep -qE '^ *[A-Za-z_][A-Za-z0-9_]*( +[A-Za-z_][A-Za-z0-9_]*)* *$' <<<"$val"; then fail "$v must be space-separated variable names (got: $val)"; cfg_ok=0; fi
done
# shellcheck disable=SC2086 # the directory lists are intentionally word-split
for d in $CLIENT_DIR $SERVER_DIRS; do
  [ -d "$d" ] || { fail "configured directory '$d' does not exist (the checks that scan it would pass without looking)"; cfg_ok=0; }
done
[ "$cfg_ok" -eq 1 ] && ok "patterns parse and configured directories exist"

echo "[1] No confidential/secret files tracked"
# PIPESTATUS does not survive a command substitution, so the grep's exit code rides along on the
# last line of the output and is split off again.
bad=$(git ls-files | grep -iE "$SECRET_FILE_PATTERNS" 2>/dev/null | grep -vE "$ALLOWED_TRACKED"; echo "__rc=${PIPESTATUS[1]}")
rc=${bad##*__rc=}; bad=${bad%__rc=*}; bad=${bad%$'\n'}
if [ "$rc" -ge 2 ]; then fail "could not apply SECRET_FILE_PATTERNS (failing closed)"
elif [ -n "$bad" ]; then fail "confidential file(s) tracked:"; echo "$bad" | sed 's/^/      /'; else ok "none tracked"; fi

if [ -n "$PUBLIC_VAR_PREFIX" ]; then
  echo "[2] Only allowlisted ${PUBLIC_VAR_PREFIX}* are public; no server secrets in $CLIENT_DIR"
  # shellcheck disable=SC2086 # allowlist is intentionally word-split into lines
  allow=$(printf '%s\n' $PUBLIC_VAR_ALLOWLIST)
  # shellcheck disable=SC2086 # CLIENT_DIR is intentionally word-split into multiple paths
  pub=$(grep -rhoE "${PUBLIC_VAR_PREFIX}[A-Z0-9_]+" $CLIENT_DIR 2>/dev/null | sort -u | grep -vxF "$allow"; echo "__rc=${PIPESTATUS[0]}")
  rc=${pub##*__rc=}; pub=${pub%__rc=*}; pub=${pub%$'\n'}
  if [ "$rc" -ge 2 ]; then fail "could not scan $CLIENT_DIR for public vars (failing closed)"
  elif [ -n "$pub" ]; then fail "disallowed public var(s) in $CLIENT_DIR:"; echo "$pub" | sed 's/^/      /'; else ok "only allowlisted public vars"; fi
  # An empty name list must not become an empty regex, which matches every line.
  if [ -z "${SECRET_VAR_NAMES// /}" ]; then
    skip_note "no SECRET_VAR_NAMES configured; the guard's name-shape patterns still apply"
  else
    names=$(printf '%s' "$SECRET_VAR_NAMES" | tr ' ' '|')
    # shellcheck disable=SC2086
    sec=$(grep -rnE "$names" $CLIENT_DIR 2>/dev/null); rc=$?
    if [ "$rc" -ge 2 ]; then fail "could not scan $CLIENT_DIR for secret names (failing closed)"
    elif [ -n "$sec" ]; then fail "server-secret name(s) in $CLIENT_DIR:"; echo "$sec" | sed 's/^/      /'; else ok "no server-secret names in $CLIENT_DIR"; fi
  fi
else
  skipped "[2] Public-env and client-secret scan" "no PUBLIC_VAR_PREFIX configured"
fi

echo "[3] Parameterised SQL only (no unsafe) in $SERVER_DIRS"
# shellcheck disable=SC2086 # SERVER_DIRS is intentionally word-split into multiple paths
unsafe=$(grep -rnE "$UNSAFE_SQL" $SERVER_DIRS 2>/dev/null); rc=$?
if [ "$rc" -ge 2 ]; then fail "could not scan $SERVER_DIRS for raw SQL (failing closed)"
elif [ -n "$unsafe" ]; then fail "non-parameterised SQL:"; echo "$unsafe" | sed 's/^/      /'; else ok "all SQL parameterised"; fi

echo "[4] No browser storage in $CLIENT_DIR"
# shellcheck disable=SC2086
store=$(grep -rnE "$STORAGE_PATTERNS" $CLIENT_DIR 2>/dev/null); rc=$?
if [ "$rc" -ge 2 ]; then fail "could not scan $CLIENT_DIR for browser storage (failing closed)"
elif [ -n "$store" ]; then fail "browser storage in $CLIENT_DIR:"; echo "$store" | sed 's/^/      /'; else ok "none"; fi

if [ -n "$MIGRATIONS_DIR" ]; then
  echo "[5] Migrations are additive (existing files unchanged)"
  if git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
    if changed=$(git diff --diff-filter=MD --name-only "$BASE"...HEAD -- "$MIGRATIONS_DIR" 2>/dev/null); then
      if [ -n "$changed" ]; then fail "existing migration(s) modified/deleted vs $BASE:"; echo "$changed" | sed 's/^/      /'; else ok "only added (vs $BASE)"; fi
    else
      fail "could not diff migrations against $BASE (failing closed)"
    fi
  else
    skip_note "base ref '$BASE' unavailable"
  fi
else
  skipped "[5] Additive-migration check" "no MIGRATIONS_DIR configured"
fi

if [ -n "$BUNDLE_DIR" ]; then
  echo "[6] No secrets in the built bundle ($BUNDLE_DIR)"
  if [ "$FAST" = "1" ]; then skip_note "fast mode"
  elif [ -d "$BUNDLE_DIR" ]; then
    leak=$(grep -rnE "$BUNDLE_LEAK_PATTERNS" "$BUNDLE_DIR" 2>/dev/null); rc=$?
    if [ "$rc" -ge 2 ]; then fail "could not scan $BUNDLE_DIR (failing closed)"
    elif [ -n "$leak" ]; then fail "secret-like string(s) in $BUNDLE_DIR:"; echo "$leak" | sed 's/^/      /'; else ok "bundle clean"; fi
  else skip_note "no $BUNDLE_DIR yet, build first"; fi
else
  skipped "[6] Built-bundle secret scan" "no BUNDLE_DIR configured"
fi

if [ -n "$SCHEMA_DUMP_CMD" ]; then
  echo "[7] Schema matches the committed dump ($SCHEMA_DUMP_FILE)"
  if [ "$FAST" = "1" ]; then skip_note "fast mode"
  elif [ ! -f "$SCHEMA_DUMP_FILE" ]; then
    fail "committed schema dump '$SCHEMA_DUMP_FILE' is missing (failing closed)"
  elif regen=$(bash -c "$SCHEMA_DUMP_CMD" 2>/dev/null); then
    if printf '%s\n' "$regen" | diff -q - "$SCHEMA_DUMP_FILE" >/dev/null 2>&1; then
      ok "schema in sync"
    else
      fail "schema drift: regenerated schema differs from $SCHEMA_DUMP_FILE (add a migration and regenerate the dump)"
    fi
  else
    fail "could not regenerate schema with SCHEMA_DUMP_CMD (failing closed)"
  fi
else
  skipped "[7] Schema-truth check" "no SCHEMA_DUMP_CMD configured"
fi

echo "[8] Agent consent controls intact (.claude/settings.json, no permission creep)"
SETTINGS='.claude/settings.json'
if [ ! -f "$SETTINGS" ]; then
  fail "$SETTINGS is missing: the agent hooks and consent rules are not wired"
elif ! command -v node >/dev/null 2>&1; then
  fail "node is not on PATH, so the agent settings cannot be checked (failing closed)"
else
  # The settings are parsed, not grepped: a hook named inside a comment, a disabled hook block or a
  # rule moved from ask to allow all look fine to a substring search. Every assertion here has a
  # mutation test in tests/guardrail-cases.sh.
  # SC2016: the single-quoted block is JavaScript; its $ characters are regex and template syntax.
  # shellcheck disable=SC2016
  if report=$(SAMPLES="$CONSENT_SAMPLES" ASK="$REQUIRED_ASK_RULES" DENY="$REQUIRED_DENY_RULES" node -e '
    const fs = require("fs")
    const lines = (s) => s.split("\n").filter(Boolean)
    const samples = lines(process.env.SAMPLES), needAsk = lines(process.env.ASK), needDeny = lines(process.env.DENY)
    const [settingsFile, localFile] = process.argv.slice(1)
    const oks = [], errs = []
    const read = (f) => JSON.parse(fs.readFileSync(f, "utf8"))
    const s = read(settingsFile)
    const perms = s.permissions || {}

    // Hooks: each guard must be wired as an exec-form command hook on a project-root path, so it is
    // found after the agent changes directory, and the bash guard must block when it cannot run.
    const hooksOf = (event, matcher) => ((s.hooks || {})[event] || [])
      .filter((g) => matcher === null || g.matcher === matcher)
      .flatMap((g) => g.hooks || [])
    const wired = (event, matcher, script, mustBlock) => {
      const label = `${script} is wired`
      const h = hooksOf(event, matcher).find((x) => x.type === "command" && Array.isArray(x.args)
        && x.args.some((a) => a === "${CLAUDE_PROJECT_DIR}/scripts/" + script))
      if (!h) { errs.push(`${script} is not wired in ${settingsFile} as a ${event} hook with args ["\${CLAUDE_PROJECT_DIR}/scripts/${script}"] (a relative path is not found after the agent changes directory)`); return }
      if (mustBlock && h.onFailure !== "block") { errs.push(`${script} must set "onFailure": "block" in ${settingsFile}: a hook that cannot start would otherwise let the command run`); return }
      oks.push(label)
    }
    wired("PreToolUse", "Bash", "claude-bash-guard.sh", true)
    wired("Stop", null, "claude-stop-guardrails.sh", false)

    // Consent and deny rules: the full lists, not a sample.
    for (const r of needAsk) {
      if ((perms.ask || []).includes(r)) oks.push("ask rule kept: " + r)
      else errs.push(`consent rule removed from ${settingsFile}: ${r}`)
    }
    for (const r of needDeny) {
      if ((perms.deny || []).includes(r)) oks.push("deny rule kept: " + r)
      else errs.push(`deny rule removed from ${settingsFile}: ${r}`)
    }

    // Modes that switch the consent layer off. bypassPermissions skips every prompt, including the
    // ask rules and the ask decisions of the guard, so the project must disable it; disableAllHooks
    // switches the guard off outright. The local file is checked too: it is per-machine, so CI sees
    // only settings.json, and the Stop hook and pre-commit run are what catch it locally.
    if (perms.disableBypassPermissionsMode === "disable") oks.push("bypass-permissions mode is disabled for this project")
    else errs.push(`${settingsFile}: permissions.disableBypassPermissionsMode must be "disable" (bypass mode skips every consent prompt)`)
    for (const file of [settingsFile, localFile]) {
      if (!fs.existsSync(file)) continue
      const j = read(file), p = j.permissions || {}
      if (j.disableAllHooks === true) errs.push(`${file}: disableAllHooks is true, which switches off the bash guard`)
      if (p.defaultMode === "bypassPermissions") errs.push(`${file}: permissions.defaultMode is bypassPermissions, which skips every consent prompt`)
    }

    // Permission creep: an allow rule in either file that matches a consent sample means a saved
    // Yes-and-do-not-ask-again has quietly turned a consent rule back into prose.
    // Claude Code Bash rule semantics: * is any text; a trailing " *" or ":*" also matches the bare
    // command. "Bash" alone, or "Bash(*)", allows everything.
    const toRegex = (glob) => {
      let g = glob, bare = null
      if (g.endsWith(":*")) g = g.slice(0, -2) + " *"
      if (g.endsWith(" *") && g.indexOf("*") === g.length - 1) bare = g.slice(0, -2)
      const esc = (x) => x.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")
      return new RegExp("^(" + esc(g) + (bare === null ? "" : "|" + esc(bare)) + ")$")
    }
    const creep = []
    for (const file of [settingsFile, localFile]) {
      if (!fs.existsSync(file)) continue
      for (const rule of (read(file).permissions || {}).allow || []) {
        let re
        if (rule === "Bash" || rule === "Bash(*)") re = /.*/
        else { const m = /^Bash\((.*)\)$/.exec(rule); if (!m) continue; re = toRegex(m[1]) }
        const hit = samples.find((x) => re.test(x))
        if (hit) creep.push(file + ": " + rule + " pre-approves \"" + hit + "\"")
      }
    }
    if (creep.length) errs.push("permission creep: allow rule(s) pre-approve outward-facing or secret-printing commands:\n" + creep.map((c) => "      " + c).join("\n"))
    else oks.push("no allow rule pre-approves a consent command")

    process.stdout.write([...oks.map((l) => "OK " + l), ...errs.map((l) => "ERR " + l)].join("\n"))
  ' "$SETTINGS" .claude/settings.local.json 2>&1); then
    while IFS= read -r line; do
      case "$line" in "OK "*) ok "${line#OK }" ;; "ERR "*) fail "${line#ERR }" ;; "      "*) echo "$line" ;; esac
    done <<< "$report"
  else
    fail "could not parse the settings files (failing closed):"; echo "$report" | sed 's/^/      /'
  fi
fi

# Assembles the denylist from the local file and the CI variable, dropping comments and blank lines.
# A blank line would otherwise be a pattern that matches every line of every file.
denylist_patterns() {
  { [ -f "$DENYLIST_FILE" ] && cat "$DENYLIST_FILE"; printf '%s\n' "${GUARDRAILS_DENYLIST:-}"; } \
    | tr -d '\r' | grep -vE '^[[:space:]]*(#|$)' || true
}
if git ls-files --error-unmatch "$DENYLIST_FILE" >/dev/null 2>&1; then
  echo "[9] Client denylist"
  fail "$DENYLIST_FILE is tracked: a committed denylist leaks the names it protects (git rm --cached it)"
elif [ -z "$(denylist_patterns)" ]; then
  skipped "[9] Client denylist" "no $DENYLIST_FILE and no GUARDRAILS_DENYLIST"
else
  echo "[9] No denylisted client identifiers in tracked or staged files"
  pat=$(mktemp) || { fail "mktemp failed (failing closed)"; pat=''; }
  if [ -n "$pat" ]; then
    denylist_patterns > "$pat"
    # Report path:line ONLY. Printing the matching line would write the client's name into the CI
    # log, which is the very leak this check exists to stop.
    hits=''; grep_failed=0
    for scope in --cached ''; do
      # shellcheck disable=SC2086 # empty scope means the working tree
      out=$(git grep $scope -n -I -i -E -f "$pat" 2>/dev/null); rc=$?
      if [ "$rc" -eq 0 ]; then hits="$hits$(printf '%s\n' "$out" | cut -d: -f1,2)"$'\n'
      elif [ "$rc" -ne 1 ]; then grep_failed=1; fi
    done
    rm -f "$pat"
    if [ "$grep_failed" -eq 1 ]; then
      fail "the denylist could not be applied, check each line is a valid extended regex (failing closed)"
    elif [ -n "${hits//$'\n'/}" ]; then
      fail "denylisted client identifier(s) found (locations only; matches are not printed):"
      printf '%s' "$hits" | sort -u | grep -v '^$' | sed 's/^/      /'
    else
      ok "none found"
    fi
  fi
fi

if [ "${CI:-}" = "true" ]; then
  skipped "[10] Local git hooks installed" "CI run; local hooks do not apply"
else
  echo "[10] Local git hooks installed (Lefthook)"
  hooks_dir=$(git config core.hooksPath 2>/dev/null || git rev-parse --git-path hooks 2>/dev/null || echo .git/hooks)
  for h in pre-commit pre-push; do
    if grep -qs lefthook "$hooks_dir/$h"; then ok "$h hook installed"
    else fail "$h hook not installed: a fresh clone has no local gate until you run npx lefthook install"; fi
  done
fi

case "$GOVERNANCE_ENABLED" in
  off) skipped "[11] Governance records" "governance tier not installed" ;;
  on)
    echo "[11] Governance records are well-formed ($GOVERNANCE_DIR)"
    # The tier is recorded as installed, so a missing file is a failure, never a skip: deleting the
    # evidence log must not look the same as never having had one.
    gov_missing=0
    for f in EVIDENCE.md DECISIONS.md briefs/BRIEF-TEMPLATE.md; do
      if [ ! -f "$GOVERNANCE_DIR/$f" ]; then fail "$GOVERNANCE_DIR/$f is missing"; gov_missing=1; fi
    done
    if [ "$gov_missing" -eq 0 ]; then
      # SC2016: the single-quoted block below is JavaScript; its $ characters are template-literal
      # and regex syntax, not shell.
      # shellcheck disable=SC2016
      if ! command -v node >/dev/null 2>&1; then
        fail "node is not on PATH, so the governance records cannot be checked (failing closed)"
      elif gov=$(node -e '
        const fs = require("fs")
        const [evFile, decFile] = process.argv.slice(1)
        const errs = []
        // HTML comments hold the format examples; they are not records.
        const read = (f) => fs.readFileSync(f, "utf8").replace(/<!--[\s\S]*?-->/g, "")
        // GitHub heading anchors: lowercase, drop punctuation, spaces to hyphens.
        const slug = (h) => h.trim().toLowerCase().replace(/[^\p{L}\p{N}\s-]/gu, "").replace(/\s/g, "-")
        const sections = (text) => {
          const out = {}; let cur = null
          for (const line of text.split(/\r?\n/)) {
            const m = /^##\s+(.*)$/.exec(line)
            if (m) { cur = slug(m[1]); out[cur] = []; continue }
            if (cur) out[cur].push(line)
          }
          return out
        }
        const cells = (row) => row.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim())

        const ev = sections(read(evFile))
        for (const need of ["status", "out-of-band-changes"]) {
          if (!ev[need]) errs.push(`${evFile}: no "${need}" section`)
        }
        if (ev.status) {
          const rows = ev.status.filter((l) => l.trim().startsWith("|"))
          const head = rows.length ? cells(rows[0]).map((c) => c.toLowerCase()) : []
          const iPhase = head.indexOf("phase"), iState = head.indexOf("state"), iEv = head.indexOf("evidence")
          if (iPhase < 0 || iState < 0 || iEv < 0) {
            errs.push(evFile + ": the status table needs Phase, State and Evidence columns")
          } else {
            const states = ["not started", "in progress", "blocked", "done"]
            for (const row of rows.slice(1)) {
              const c = cells(row)
              if (c.every((x) => /^:?-+:?$/.test(x))) continue
              const phase = c[iPhase] || "?", state = (c[iState] || "").toLowerCase()
              if (!states.includes(state)) {
                errs.push(`${evFile}: phase ${phase} has unknown state "${c[iState] || ""}" (use Not started, In progress, Blocked or Done)`)
                continue
              }
              if (state !== "done") continue
              const anchors = [...(c[iEv] || "").matchAll(/\(#([^)\s]+)\)/g)].map((m) => m[1])
              if (anchors.length === 0) { errs.push(evFile + ": phase " + phase + " is Done but has no evidence link"); continue }
              for (const a of anchors) {
                const body = ev[a]
                if (!body) errs.push(evFile + ": phase " + phase + " links to #" + a + ", which is not a section in this file")
                else if (!body.some((l) => /^\s*(```|~~~)/.test(l) || /https?:\/\//.test(l))) {
                  errs.push(evFile + ": phase " + phase + " is Done but its evidence section #" + a + " has no output block or link")
                }
              }
            }
          }
        }

        const dec = sections(read(decFile))
        for (const need of ["settled-decisions", "deviations", "open-questions"]) {
          if (!dec[need]) errs.push(`${decFile}: no "${need}" section`)
        }
        if (dec.deviations) {
          let title = null, body = []
          const entries = []
          for (const line of dec.deviations) {
            const m = /^###\s+(.*)$/.exec(line)
            if (m) { if (title) entries.push([title, body]); title = m[1].trim(); body = []; continue }
            if (title) body.push(line)
          }
          if (title) entries.push([title, body])
          const empty = /^(<.*>|tbd|todo|tba|n\/a|none|-|\.\.\.)?$/i
          for (const [t, b] of entries) {
            for (const field of ["Cost", "Exit", "Owner"]) {
              const re = new RegExp("^\\s*[-*]\\s*\\*\\*" + field + ":\\*\\*(.*)$", "i")
              const hit = b.map((l) => re.exec(l)).find(Boolean)
              if (!hit || empty.test(hit[1].trim())) errs.push(`${decFile}: deviation "${t}" has no ${field}`)
            }
          }
        }
        process.stdout.write(errs.join("\n"))
      ' "$GOVERNANCE_DIR/EVIDENCE.md" "$GOVERNANCE_DIR/DECISIONS.md" 2>&1); then
        if [ -n "$gov" ]; then
          fail "governance records are not well-formed:"; echo "$gov" | sed 's/^/      /'
        else
          ok "every Done phase has evidence; every deviation has a cost, an exit and an owner"
        fi
      else
        fail "could not parse the governance records (failing closed):"; echo "$gov" | sed 's/^/      /'
      fi
    fi
    ;;
  *)
    echo "[11] Governance records"
    fail "GOVERNANCE_ENABLED must be 'on' or 'off', got '$GOVERNANCE_ENABLED' (failing closed)"
    ;;
esac

if [ ! -f package.json ]; then
  skipped "[12] Dependency policy" "no package.json"
else
  echo "[12] Dependency policy (.npmrc, package-lock.json, npm version)"
  if ! command -v node >/dev/null 2>&1; then
    fail "node is not on PATH, so the dependency policy cannot be checked (failing closed)"
  else
    # SC2016: the single-quoted block is JavaScript; its $ characters are template-literal syntax.
    # shellcheck disable=SC2016
    if dep=$(MIN_AGE="$MIN_RELEASE_AGE_DAYS" REGISTRIES="$ALLOWED_REGISTRIES" node -e '
      const fs = require("fs")
      const minAge = Number(process.env.MIN_AGE)
      const slash = (u) => (u.endsWith("/") ? u : u + "/")
      const registries = process.env.REGISTRIES.split(/\s+/).filter(Boolean).map(slash)
      const errs = [], oks = []

      // .npmrc: key=value lines, comments start with # or ;, and the last occurrence of a key wins.
      if (!fs.existsSync(".npmrc")) {
        errs.push(".npmrc is missing: the release cooldown and install-script policy are not set")
      } else {
        const rc = {}
        for (const raw of fs.readFileSync(".npmrc", "utf8").split(/\r?\n/)) {
          const line = raw.trim()
          if (!line || line.startsWith("#") || line.startsWith(";")) continue
          const i = line.indexOf("=")
          if (i < 0) continue
          rc[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["\x27](.*)["\x27]$/, "$1")
        }
        const before = errs.length
        const age = rc["min-release-age"]
        if (age === undefined) errs.push(`.npmrc: min-release-age is not set (need at least ${minAge})`)
        else if (!/^\d+$/.test(age) || Number(age) < minAge) errs.push(`.npmrc: min-release-age is "${age}" (need a whole number of days, at least ${minAge})`)
        if (rc.before !== undefined) errs.push(".npmrc: before is set, and it overrides min-release-age")
        for (const k of ["allow-git", "allow-remote"]) {
          if (rc[k] !== "none") errs.push(`.npmrc: ${k} is "${rc[k] ?? "unset"}" (must be none: dependencies come from the registry only)`)
        }
        if (rc["strict-allow-scripts"] !== "true") errs.push(".npmrc: strict-allow-scripts must be true (an unreviewed install script fails the install)")
        if (rc["dangerously-allow-all-scripts"] === "true") errs.push(".npmrc: dangerously-allow-all-scripts is true (every install script would run)")
        for (const [k, v] of Object.entries(rc)) {
          if ((k === "registry" || /^@[^:]+:registry$/.test(k)) && !registries.includes(slash(v))) {
            errs.push(`.npmrc: ${k} points at ${v}, which is not in ALLOWED_REGISTRIES`)
          }
        }
        if (errs.length === before) oks.push(`.npmrc keeps the policy: ${age}-day release cooldown, registry-only dependencies, reviewed install scripts`)
      }

      // package-lock.json: every installed package from an allowed registry, with a sha512 hash, at
      // a URL that names the same package (a lockfile pointing one name at another tarball is the
      // classic tampering trick).
      if (!fs.existsSync("package-lock.json")) {
        errs.push("package-lock.json is missing: run npm install --package-lock-only and commit it")
      } else {
        const lock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"))
        if (!lock.packages || Number(lock.lockfileVersion) < 2) {
          errs.push("package-lock.json uses lockfile version 1, which this check cannot verify: regenerate it with a current npm")
        } else {
          const before = errs.length
          let n = 0
          for (const [path, e] of Object.entries(lock.packages)) {
            if (path === "" || e.link || e.inBundle) continue
            n++
            const name = e.name || path.slice(path.lastIndexOf("node_modules/") + "node_modules/".length)
            const url = e.resolved || ""
            const reg = registries.find((r) => url.startsWith(r))
            if (!reg) errs.push(`package-lock.json: ${path} resolves to "${url || "nowhere"}", not an allowed registry`)
            else if (!url.startsWith(reg + name + "/-/")) errs.push(`package-lock.json: ${path} resolves to a tarball for a different package (${url})`)
            if (!String(e.integrity || "").startsWith("sha512-")) errs.push(`package-lock.json: ${path} has no sha512 integrity hash`)
          }
          if (errs.length === before) oks.push(`package-lock.json: ${n} package(s), all from an allowed registry with sha512 integrity`)
        }
      }
      process.stdout.write([...oks.map((l) => "OK " + l), ...errs.map((l) => "ERR " + l)].join("\n"))
    ' 2>&1); then
      while IFS= read -r line; do
        case "$line" in "OK "*) ok "${line#OK }" ;; "ERR "*) fail "${line#ERR }" ;; esac
      done <<< "$dep"
    else
      fail "could not read .npmrc or package-lock.json (failing closed):"; echo "$dep" | sed 's/^/      /'
    fi
    # The cooldown only exists if this npm understands it; older versions ignore the key silently.
    if ! npm_v=$(npm --version 2>/dev/null) || [ -z "$npm_v" ]; then
      fail "npm is not on PATH, so its version cannot be checked (failing closed)"
    elif node -e 'const p=(v)=>v.split(".").map(Number); const [a,b]=[p(process.argv[1]),p(process.argv[2])]; for (let i=0;i<3;i++){ if((a[i]||0)!==(b[i]||0)) process.exit((a[i]||0)>(b[i]||0)?0:1) } process.exit(0)' "$npm_v" "$NPM_MIN_VERSION"; then
      ok "npm $npm_v enforces the cooldown (needs $NPM_MIN_VERSION or later)"
    else
      fail "npm $npm_v ignores min-release-age, so the cooldown is not enforced: upgrade to npm $NPM_MIN_VERSION or later (Node 24 ships it)"
    fi
  fi
fi

echo
if [ "$fails" -ne 0 ]; then echo "GUARDRAILS FAILED: $fails issue(s)."; exit 1; fi
echo "GUARDRAILS PASSED."
