#!/usr/bin/env bash
# Entry point for the template's behavioural tests: bootstrap two throwaway projects from the
# templates, then assert the installed guardrails and hooks actually behave. The last suite is the
# odd one out: it tests THIS repo's own .gitleaks.toml rather than a generated project, and it
# soft-skips when gitleaks is not installed, because CI's `secrets` job runs it with the pinned
# binary.
#
#   bash tests/run.sh            # run everything, clean up afterwards
#   bash tests/run.sh --keep     # leave the installed projects behind for inspection
#
# Work happens in a temp directory OUTSIDE this repo, because the guardrail scripts resolve their
# root with `git rev-parse --show-toplevel` and would otherwise find the template repo itself.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gov-sec-template-tests.XXXXXX")
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT

command -v node >/dev/null 2>&1 || { echo "✗ node is required to run these tests"; exit 1; }

failed=0
last_ok=1
run_suite() {
  local name="$1"; shift
  echo
  echo "════════════════════════════════════════════════════════════════"
  echo "  $name"
  echo "════════════════════════════════════════════════════════════════"
  if "$@"; then last_ok=1; else last_ok=0; failed=$((failed + 1)); fi
}
# A case suite run against a half-installed project reports dozens of misleading failures (and its
# reset-between-cases helper cleans an uncommitted tree). Skip it, loudly, when its install failed.
run_cases() {
  if [ "$install_ok" -eq 1 ]; then run_suite "$@"; else
    echo; echo "  SKIPPED: $1 (its install failed above)"; failed=$((failed + 1)); fi
}

echo "work dir: $WORK"

run_suite "install: scenario A (Next.js, regulated data, production, database, governance)" \
  bash "$ROOT/tests/install.sh" a "$WORK/acme-portal"
install_ok=$last_ok
run_cases "guardrail cases (scenario A)" \
  bash "$ROOT/tests/guardrail-cases.sh" "$WORK/acme-portal"
run_cases "hook cases (scenario A)" \
  bash "$ROOT/tests/hook-cases.sh" "$WORK/acme-portal"

run_suite "install: scenario B (plain library, no prod, no database, no bundle, no governance)" \
  bash "$ROOT/tests/install.sh" b "$WORK/sig-lib"
install_ok=$last_ok
run_cases "sparse cases (scenario B)" \
  bash "$ROOT/tests/sparse-cases.sh" "$WORK/sig-lib"

run_suite "gitleaks config cases (this repo's own .gitleaks.toml)" \
  bash "$ROOT/tests/gitleaks-config-cases.sh"

echo
if [ "$failed" -ne 0 ]; then
  echo "TEMPLATE BEHAVIOUR TESTS FAILED: $failed suite(s)."
  [ "$KEEP" -eq 1 ] && echo "installed projects left at $WORK"
  exit 1
fi
echo "TEMPLATE BEHAVIOUR TESTS PASSED."
