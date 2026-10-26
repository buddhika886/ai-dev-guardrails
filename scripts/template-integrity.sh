#!/usr/bin/env bash
# Template integrity check (the repo's own guardrail). Enforces the token contract:
#   every {{TOKEN}} used anywhere under .template/ MUST appear in the bootstrap token table,
#   and every token referenced in the bootstrap command MUST be used by at least one template file.
# Fails closed (exit 1) on any mismatch. Run locally before a PR; the repo's CI runs it too.
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

TEMPLATE_DIR=".template"
BOOTSTRAP=".claude/commands/bootstrap.md"

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "✗ $TEMPLATE_DIR not found (run from the template repo root)."; exit 1
fi
if [ ! -f "$BOOTSTRAP" ]; then
  echo "✗ $BOOTSTRAP not found."; exit 1
fi

template_tokens=$(grep -rhoE '\{\{[A-Z_]+\}\}' "$TEMPLATE_DIR" | sort -u)
bootstrap_tokens=$(grep -hoE '\{\{[A-Z_]+\}\}' "$BOOTSTRAP" | sort -u)

only_template=$(comm -23 <(printf '%s\n' "$template_tokens") <(printf '%s\n' "$bootstrap_tokens"))
only_bootstrap=$(comm -13 <(printf '%s\n' "$template_tokens") <(printf '%s\n' "$bootstrap_tokens"))

fails=0
if [ -n "$only_template" ]; then
  echo "✗ tokens used in $TEMPLATE_DIR but missing from the bootstrap token table:"
  printf '%s\n' "$only_template" | sed 's/^/      /'
  fails=1
fi
if [ -n "$only_bootstrap" ]; then
  echo "✗ tokens in $BOOTSTRAP but used by no template file (stale table entry):"
  printf '%s\n' "$only_bootstrap" | sed 's/^/      /'
  fails=1
fi

if [ "$fails" -ne 0 ]; then
  echo
  echo "TEMPLATE INTEGRITY FAILED. Update the token table in $BOOTSTRAP to match the templates."
  exit 1
fi

count=$(printf '%s\n' "$template_tokens" | grep -c .)
echo "TEMPLATE INTEGRITY PASSED ($count tokens in sync):"
printf '%s\n' "$template_tokens" | sed 's/^/  /'
