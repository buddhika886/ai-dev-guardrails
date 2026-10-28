#!/usr/bin/env bash
# This repo's OWN secret-scanning config (.gitleaks.toml) must catch real secrets and must not fire
# on the committed placeholders. Everything else under tests/ exercises a GENERATED project; this
# file is the exception, and it is here because a config that has quietly stopped matching looks
# exactly like one that works.
#
#   usage: tests/gitleaks-config-cases.sh
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "  SKIPPED: gitleaks not installed locally. CI's secrets job runs these cases."
  exit 0
fi

CFG="$ROOT/.gitleaks.toml"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gitleaks-config-cases.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Scan a path with this repo's config. Decide on gitleaks' EXIT CODE, never on its output text:
# the clean message is "no leaks found", which contains the string "leaks found", and a grep for the
# latter reports every clean scan as a finding. --exit-code 1 makes a finding a non-zero exit.
scan() {
  SCAN_OUT=$(gitleaks detect --no-git --source "$1" --config "$CFG" --redact --verbose --exit-code 1 2>&1)
  SCAN_RC=$?
}

expect_caught() {
  local label="$1" path="$2" want_rule="$3"
  scan "$path"
  if [ "$SCAN_RC" -eq 0 ]; then
    t_fail "$label (nothing found)" "$SCAN_OUT"; return
  fi
  if ! grep -q "RuleID: *$want_rule" <<<"$SCAN_OUT"; then
    t_fail "$label (caught, but not by $want_rule)" "$SCAN_OUT"; return
  fi
  t_pass "$label"
}

expect_clean() {
  local label="$1" path="$2"
  scan "$path"
  if [ "$SCAN_RC" -ne 0 ]; then t_fail "$label" "$SCAN_OUT"; return; fi
  t_pass "$label"
}

echo "── the config must catch real secrets"
hex=$(printf 'a1b2c3d4%.0s' 1 2 3 4 5 6 7 8)
mkdir -p "$WORK/live"
printf 'ANTHROPIC_AUTH_TOKEN=sk-or-v1-%s\n' "$hex" > "$WORK/live/profile.json"
expect_caught "an OpenRouter key is caught by the project rule" "$WORK/live/profile.json" "openrouter-api-key"

mkdir -p "$WORK/aws"
# Two things about this fixture. It is not AKIAIOSFODNN7EXAMPLE, because that is AWS's published
# documentation sample and gitleaks allowlists it by default, so it would pass whether the ruleset
# was armed or not. And the key is assembled from parts at runtime, so no complete AKIA-shaped
# literal exists anywhere in this file: written whole, it trips the repo's own working-tree scan
# below, and the fix for that is a fixture that does not look like a secret at rest, never an
# allowlist entry that blinds the scanner to a directory.
akia=$(printf '%s%s' 'AKIA' '4NPZW2TQ6RJDVB5L')
printf 'aws_access_key_id = %s\n' "$akia" > "$WORK/aws/creds"
expect_caught "an AWS access key id is caught by the default ruleset" "$WORK/aws/creds" "aws-access-token"

echo "── no directory-wide allowlist may blind the scan"
# .gitleaks.toml deliberately ships no `paths` allowlist. The obvious entries (^tests/, ^docs/,
# ^.template/) were each measured as not load-bearing. If someone reinstates one, a real key under
# that directory goes invisible in BOTH layers, and these cases are what says so.
for dir in tests docs .template/core .claude; do
  mkdir -p "$WORK/blind/$dir"
  printf 'ANTHROPIC_AUTH_TOKEN=sk-or-v1-%s\n' "$hex" > "$WORK/blind/$dir/leaked.json"
done
expect_caught "a key under tests/ is still caught"         "$WORK/blind/tests"         "openrouter-api-key"
expect_caught "a key under docs/ is still caught"          "$WORK/blind/docs"          "openrouter-api-key"
expect_caught "a key under .template/core/ is still caught" "$WORK/blind/.template/core" "openrouter-api-key"
expect_caught "a key under .claude/ is still caught"       "$WORK/blind/.claude"       "openrouter-api-key"

echo "── the committed placeholders must not fire"
mkdir -p "$WORK/placeholder"
cp "$ROOT/.claude/openrouter.settings.json.example" "$WORK/placeholder/"
expect_clean "the OpenRouter profile example is not flagged" "$WORK/placeholder"

echo "── the repo itself must be clean, working tree and full history"
if gitleaks detect --source "$ROOT" --config "$CFG" --redact >/dev/null 2>&1; then
  t_pass "full history is clean"
else
  t_fail "full history is clean" "$(gitleaks detect --source "$ROOT" --config "$CFG" --redact -v 2>&1 | tail -20)"
fi
if gitleaks detect --source "$ROOT" --no-git --config "$CFG" --redact >/dev/null 2>&1; then
  t_pass "working tree is clean"
else
  t_fail "working tree is clean" "$(gitleaks detect --source "$ROOT" --no-git --config "$CFG" --redact -v 2>&1 | tail -20)"
fi

echo "── the GENERATED project's config: connection-string credentials"
# Same scan, pointed at .template/core/.gitleaks.toml. The fixture URL is assembled at runtime so no
# complete credential-shaped literal sits in this file, for the reason given at the AWS fixture.
CFG="$ROOT/.template/core/.gitleaks.toml"
mkdir -p "$WORK/core-live" "$WORK/core-clean"
pw=$(printf '%s%s' 'Vq7rT2mXk9' 'pL4sW8nB')
# The host deliberately avoids the word "example": the allowlist clears any match containing it.
printf 'DATABASE_URL=postgres://app:%s@db.internal.acmecorp.net:5432/app\n' "$pw" > "$WORK/core-live/config.ts"
expect_caught "a password inside a database URL is caught" "$WORK/core-live/config.ts" "credential-in-connection-string"
printf 'DATABASE_URL=postgres://app:<password>@db.internal.acmecorp.net:5432/app\n' > "$WORK/core-clean/runbook.md"
printf 'DATABASE_URL=postgres://app:local_dev_only@localhost:5432/acme\n' > "$WORK/core-clean/.env.example"
expect_clean "placeholders and local dev URLs are not flagged" "$WORK/core-clean"
CFG="$ROOT/.gitleaks.toml"

t_summary "GITLEAKS CONFIG CASES"
