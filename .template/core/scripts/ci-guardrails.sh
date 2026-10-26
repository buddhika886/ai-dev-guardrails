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
CLIENT_DIR='{{CLIENT_DIR}}'                 # client code: no secret names, no browser storage
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
cat .env
printenv'
# Consent rules that .claude/settings.json must keep. Ask rules are evaluated before allow rules, so
# these hold even when an allowlist wildcard matches the same command.
REQUIRED_ASK_RULES='Bash(git commit *)
Bash(git push *)'
# Where the governance tier's records live, when it is installed.
GOVERNANCE_DIR='docs/governance'
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

echo "[1] No confidential/secret files tracked"
bad=$(git ls-files | grep -iE "$SECRET_FILE_PATTERNS" | grep -vE "$ALLOWED_TRACKED" || true)
if [ -n "$bad" ]; then fail "confidential file(s) tracked:"; echo "$bad" | sed 's/^/      /'; else ok "none tracked"; fi

if [ -n "$PUBLIC_VAR_PREFIX" ]; then
  echo "[2] Only allowlisted ${PUBLIC_VAR_PREFIX}* are public; no server secrets in $CLIENT_DIR"
  # shellcheck disable=SC2086 # allowlist is intentionally word-split into lines
  allow=$(printf '%s\n' $PUBLIC_VAR_ALLOWLIST)
  pub=$(grep -rhoE "${PUBLIC_VAR_PREFIX}[A-Z0-9_]+" "$CLIENT_DIR" 2>/dev/null | sort -u | grep -vxF "$allow" || true)
  if [ -n "$pub" ]; then fail "disallowed public var(s) in $CLIENT_DIR:"; echo "$pub" | sed 's/^/      /'; else ok "only allowlisted public vars"; fi
  names=$(printf '%s' "$SECRET_VAR_NAMES" | tr ' ' '|')
  sec=$(grep -rnE "$names" "$CLIENT_DIR" 2>/dev/null || true)
  if [ -n "$sec" ]; then fail "server-secret name(s) in $CLIENT_DIR:"; echo "$sec" | sed 's/^/      /'; else ok "no server-secret names in $CLIENT_DIR"; fi
else
  skipped "[2] Public-env and client-secret scan" "no PUBLIC_VAR_PREFIX configured"
fi

echo "[3] Parameterised SQL only (no unsafe) in $SERVER_DIRS"
# shellcheck disable=SC2086 # SERVER_DIRS is intentionally word-split into multiple paths
unsafe=$(grep -rnE "$UNSAFE_SQL" $SERVER_DIRS 2>/dev/null || true)
if [ -n "$unsafe" ]; then fail "non-parameterised SQL:"; echo "$unsafe" | sed 's/^/      /'; else ok "all SQL parameterised"; fi

echo "[4] No browser storage in $CLIENT_DIR"
store=$(grep -rnE "$STORAGE_PATTERNS" "$CLIENT_DIR" 2>/dev/null || true)
if [ -n "$store" ]; then fail "browser storage in $CLIENT_DIR:"; echo "$store" | sed 's/^/      /'; else ok "none"; fi

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
    leak=$(grep -rnE "$BUNDLE_LEAK_PATTERNS" "$BUNDLE_DIR" 2>/dev/null || true)
    if [ -n "$leak" ]; then fail "secret-like string(s) in $BUNDLE_DIR:"; echo "$leak" | sed 's/^/      /'; else ok "bundle clean"; fi
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
else
  for hook in claude-bash-guard.sh claude-stop-guardrails.sh; do
    if grep -qF "$hook" "$SETTINGS"; then ok "$hook is wired"; else fail "$hook is not wired in $SETTINGS"; fi
  done
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if grep -qF "\"$rule\"" "$SETTINGS"; then ok "ask rule kept: $rule"; else fail "consent rule removed from $SETTINGS: $rule"; fi
  done <<< "$REQUIRED_ASK_RULES"
  # Permission creep: an allow rule in either settings file that matches a consent sample. The
  # .local file is per-machine and gitignored, so CI sees only settings.json; the Stop hook and the
  # pre-commit run are what catch creep in the local file.
  if command -v node >/dev/null 2>&1; then
    # SC2016: the single-quoted block is JavaScript; its $ characters are regex syntax, not shell.
    # shellcheck disable=SC2016
    if creep=$(SAMPLES="$CONSENT_SAMPLES" node -e '
      const fs = require("fs")
      const samples = process.env.SAMPLES.split("\n").filter(Boolean)
      // Claude Code Bash rule semantics: * is any text, and a trailing " *" also matches the bare
      // command. "Bash" alone, or "Bash(*)", allows everything.
      const toRegex = (glob) => {
        let g = glob, bare = null
        if (g.endsWith(" *") && g.indexOf("*") === g.length - 1) bare = g.slice(0, -2)
        const esc = (s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")
        return new RegExp("^(" + esc(g) + (bare === null ? "" : "|" + esc(bare)) + ")$")
      }
      const out = []
      for (const file of process.argv.slice(1)) {
        if (!fs.existsSync(file)) continue
        const allow = ((JSON.parse(fs.readFileSync(file, "utf8")).permissions || {}).allow) || []
        for (const rule of allow) {
          let re
          if (rule === "Bash" || rule === "Bash(*)") re = /.*/
          else { const m = /^Bash\((.*)\)$/.exec(rule); if (!m) continue; re = toRegex(m[1]) }
          const hit = samples.find((s) => re.test(s))
          if (hit) out.push(file + ": " + rule + " pre-approves \"" + hit + "\"")
        }
      }
      process.stdout.write(out.join("\n"))
    ' "$SETTINGS" .claude/settings.local.json 2>&1); then
      if [ -n "$creep" ]; then
        fail "permission creep: allow rule(s) pre-approve outward-facing or secret-printing commands:"
        echo "$creep" | sed 's/^/      /'
      else
        ok "no allow rule pre-approves a consent command"
      fi
    else
      fail "could not parse the settings files (failing closed):"; echo "$creep" | sed 's/^/      /'
    fi
  else
    fail "node is not on PATH, so permission creep cannot be checked (failing closed)"
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

echo
if [ "$fails" -ne 0 ]; then echo "GUARDRAILS FAILED: $fails issue(s)."; exit 1; fi
echo "GUARDRAILS PASSED."
