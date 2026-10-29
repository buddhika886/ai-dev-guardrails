#!/usr/bin/env bash
# Claude Code Stop hook (Layer 2): run the fast guardrails when a turn ends. Never blocks stopping;
# it warns, so a violation is noticed before anything is committed. The warning names the FIRST
# failing check (the first ✗ line) so the fix is obvious without re-running by hand.
set -uo pipefail

# Hooks run in the agent's current directory, which follows its `cd`. Resolve the project root
# first so the guardrails are found from a subdirectory too. If neither the hook variable nor git
# can name the root, the guardrails fail (ci-guardrails.sh fails closed on a bad root) and the
# warning below says so, rather than this hook going quiet.
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo .)}" || exit 0

if out=$(GUARDRAILS_FAST=1 bash scripts/ci-guardrails.sh 2>&1); then
  exit 0
fi

# Take the first ✗ line and make it safe to embed in JSON by construction: strip the marker, drop
# backslashes and double quotes, and remove control characters so the result is a single line. Doing
# it here rather than shelling out to a JSON encoder means the warning still arrives on a machine
# with no node or python installed.
first_fail=$(printf '%s\n' "$out" \
  | grep -m1 '✗' \
  | sed -e 's/^[[:space:]]*✗[[:space:]]*//' -e 's/[\\"]/ /g' \
  | tr -d '\000-\037')
[ -z "$first_fail" ] && first_fail="run npm run guardrails to see which rule"

msg="Guardrails FAILED. First failing check: ${first_fail}. Do not commit until green; run: npm run guardrails"

printf '{"systemMessage":"%s"}\n' "$msg"
exit 0
