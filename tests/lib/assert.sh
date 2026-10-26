# shellcheck shell=bash
# Shared assertions for the template's behavioural tests. Sourced, not executed.
#
# Every case is "plant exactly one violation, assert the guardrails reject it for the right reason,
# revert". Asserting the reason matters: a check that fails for an unrelated reason looks identical to
# one that works, and that is how a broken check survives.

TESTS_PASSED=0
TESTS_FAILED=0

t_pass() { echo "  PASS  $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

t_fail() {
  echo "  FAIL  $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  if [ $# -gt 1 ] && [ -n "$2" ]; then printf '%s\n' "$2" | sed 's/^/        /'; fi
}

t_summary() {
  echo
  echo "$1: $TESTS_PASSED passed, $TESTS_FAILED failed"
  [ "$TESTS_FAILED" -eq 0 ]
}

# Reset the throwaway project back to its pristine baseline between cases.
reset_project() {
  git reset -q --hard base >/dev/null 2>&1
  git clean -qfd >/dev/null 2>&1
}

# In-place sed that works on both GNU and BSD (`sed -i ''` is a BSD-ism that fails on CI runners).
portable_sed() {
  local expr="$1" file="$2" tmp
  tmp="${file}.tests.tmp"
  sed -e "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}

# guardrails_out: run the installed guardrails against the `base` branch, echo output, return its rc.
guardrails_out() {
  GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1
}

# expect_reject <label> <expected substring>: guardrails must fail AND say why. Reverts afterwards.
expect_reject() {
  local label="$1" want="$2" out rc
  out=$(guardrails_out); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qF "$want"; then
    t_pass "$label"
  else
    t_fail "$label (rc=$rc, expected output containing: $want)" "$out"
  fi
  reset_project
}

# expect_accept <label> <expected substring>: guardrails must pass AND report the expected line.
expect_accept() {
  local label="$1" want="$2" out rc
  out=$(guardrails_out); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF "$want"; then
    t_pass "$label"
  else
    t_fail "$label (rc=$rc, expected output containing: $want)" "$out"
  fi
  reset_project
}

# guard_decide <block|ask|allow> <label> <raw-stdin> <PATH-value>: run the installed bash guard and
# classify its answer. block = exit 2; ask = exit 0 with a permissionDecision of "ask" on stdout;
# allow = exit 0 with no output. Anything else (another exit code, stray output) is a failure.
guard_decide() {
  local want="$1" label="$2" input="$3" path="$4" out err rc got
  err=$(mktemp)
  out=$(printf '%s' "$input" | env "PATH=$path" bash scripts/claude-bash-guard.sh 2>"$err"); rc=$?
  if [ "$rc" -eq 2 ]; then got=block
  elif [ "$rc" -eq 0 ] && [ -z "$out" ]; then got=allow
  elif [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF '"permissionDecision":"ask"'; then got=ask
  else got="unexpected(rc=$rc)"; fi
  if [ "$got" = "$want" ]; then t_pass "[$got] $label"; else t_fail "[$got want=$want] $label" "$out$(cat "$err")"; fi
  rm -f "$err"
}
