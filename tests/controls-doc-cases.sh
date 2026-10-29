#!/usr/bin/env bash
# docs/security-controls.md must list every control the template ships. Each list below is read from
# the code itself, not typed out here, so a control added to the code without a row on the page
# fails this suite. That keeps the page an inventory rather than a summary that drifts.
#
#   usage: tests/controls-doc-cases.sh
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
cd "$ROOT" || exit 2

DOC=docs/security-controls.md
T=.template/core
[ -f "$DOC" ] || { t_fail "$DOC is missing"; t_summary "CONTROLS DOC CASES"; exit 1; }

# documented <what> <name> <pattern>: the page must contain the pattern (fixed string).
documented() {
  if grep -qF -- "$3" "$DOC"; then t_pass "$1: $2"; else t_fail "$1 not on $DOC: $2 (expected \"$3\")"; fi
}

echo "── every guard decision list"
# Variables the guard matches commands against: those passed to `grep ... "$NAME"` in a decision.
# B is the word-boundary helper the patterns are built from, not a decision in its own right.
while IFS= read -r v; do
  documented "guard list" "$v" "\`$v\`"
done < <(grep -oE 'grep -q[a-zA-Z]* "\$\{?[A-Z_]+' "$T/scripts/claude-bash-guard.sh" | grep -oE '[A-Z_]+$' | grep -vx 'B' | sort -u)
for v in $(sed -n '/^# ---- CONFIG/,/^# ------/p' "$T/scripts/claude-bash-guard.sh" | grep -oE '^[A-Z_]+=' | tr -d '='); do
  documented "guard setting" "$v" "\`$v\`"
done

echo "── every guardrail check"
for n in $(grep -oE '"\[[0-9]+\]' "$T/scripts/ci-guardrails.sh" | tr -d '"[]' | sort -un); do
  documented "check" "[$n]" "| $n |"
done

echo "── every permission rule and hook in settings.json"
while IFS= read -r rule; do
  documented "permission rule" "$rule" "\`$rule\`"
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).permissions; for (const r of [...p.ask, ...p.deny]) console.log(r)' "$T/settings.json")
for h in $(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).hooks).join(" "))' "$T/settings.json"); do
  documented "hook" "$h" "$h hook"
done

echo "── every local hook command"
for c in $(grep -oE '^    [0-9a-z-]+:' "$T/lefthook.yml" | tr -d ' :'); do
  documented "lefthook command" "$c" "\`$c\`"
done

echo "── every CI job"
for j in $(sed -n '/^jobs:/,$p' "$T/ci/verify.yml" | grep -oE '^  [a-z][a-z0-9_-]*:' | tr -d ' :'); do
  documented "CI job" "$j" "\`$j\` job"
done

echo "── every custom secret-scanner rule"
while IFS= read -r id; do
  documented "gitleaks rule" "$id" "\`$id\`"
done < <(grep -oE '^id = "[^"]+"' "$T/.gitleaks.toml" | cut -d'"' -f2)

echo "── every dependency-policy setting"
for k in $(grep -oE '^[a-z-]+=' .template/lang/ts/.npmrc | tr -d '='); do
  documented ".npmrc setting" "$k" "$k="
done

echo "── every example model profile"
for f in .claude/profiles/*.settings.json.example; do
  n=$(basename "$f" .settings.json.example)
  documented "model profile" "$n" "\`$n\`"
done

echo "── every .gitignore line bootstrap guarantees"
while IFS= read -r line; do
  documented ".gitignore entry" "$line" "\`$line\`"
done < <(grep -oE "^ensure_ignored '[^']+'" tests/install.sh | cut -d"'" -f2)

t_summary "CONTROLS DOC CASES"
