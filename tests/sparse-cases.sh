#!/usr/bin/env bash
# The sparse install (scenario B): no framework, no production, no database, no bundle. Five tokens
# are legitimately empty here, and an empty value is the dangerous case: an empty regex can turn a
# check into a no-op. These cases assert that a check turned off by configuration SAYS SO, and that
# the checks which remain still bite.
#
#   usage: tests/sparse-cases.sh <installed-project-dir>
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "usage: tests/sparse-cases.sh <installed-project-dir>" >&2
  exit 2
fi
ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
cd "$PROJ" || exit 2

echo "── a check disabled by configuration must announce itself, never pass silently"
out=$(bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then t_fail "the sparse install should be green" "$out"; fi
for want in \
  "[2] Public-env and client-secret scan: SKIPPED" \
  "[5] Additive-migration check: SKIPPED" \
  "[6] Built-bundle secret scan: SKIPPED" \
  "[7] Schema-truth check: SKIPPED" \
  "[9] Client denylist: SKIPPED" \
  "[11] Governance records: SKIPPED"
do
  if grep -qF "$want" <<<"$out"; then
    t_pass "reported: $want"
  else
    t_fail "missing skip report: $want" "$out"
  fi
done
# A skip must never be dressed up as a verified pass.
# Case-insensitive on purpose: runtime skips were once printed as "✓ skipped (...)" and an
# uppercase-only match missed them.
if grep -i 'skipped' <<<"$out" | grep -qF '✓'; then
  t_fail "a SKIPPED line was marked with a tick"
else
  t_pass "no SKIPPED line is marked as verified"
fi
# All twelve checks accounted for, so a reader of the log can audit coverage.
seen=$(grep -cE '^\[([1-9]|1[012])\]' <<<"$out")
if [ "$seen" -eq 12 ]; then
  t_pass "all twelve checks appear in the output"
else
  t_fail "only $seen of 12 checks reported themselves" "$out"
fi
# Governance off: none of its files or pointers may appear.
if [ ! -e docs/governance ] && [ ! -e .github/pull_request_template.md ] && ! grep -q 'docs/governance' CLAUDE.md; then
  t_pass "governance off installs no governance files or pointers"
else
  t_fail "governance leaked into a project that did not select it"
fi

echo "── the checks that remain active must still bite"
printf 'k\n' > signing.key; git add -f signing.key
expect_reject "a tracked .key is still caught" "confidential file(s) tracked"
printf '\nexport const bad = (t: string) => sql.raw(t)\n' >> src/core/sign.ts
expect_reject "unsafe SQL is still caught" "non-parameterised SQL"
printf '\nlocalStorage.setItem("k", "v")\n' >> src/client/index.ts
expect_reject "browser storage is still caught" "browser storage"
portable_sed 's/^min-release-age=.*/min-release-age=0/' .npmrc
expect_reject "the dependency cooldown is still enforced" ".npmrc: min-release-age is"
rm -f package.json
expect_accept "with no package.json, the dependency check announces itself" "[12] Dependency policy: SKIPPED (no package.json)"

echo "── with no prod patterns configured, the git protections must still hold"
guard() {
  local want="$1" label="$2" cmd="$3" payload
  payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$cmd")
  guard_decide "$want" "$label" "$payload" "$PATH"
}
guard block "force-push still blocked without prod patterns" 'git push --force origin main'
guard block "reset --hard still blocked"                     'git reset --hard HEAD~1'
guard block "clean -fd still blocked"                        'git clean -fd'
guard allow "ordinary work still allowed"                    'npm test'

echo "── with no production yet, consent and secret hygiene must still hold"
guard ask   "a push still asks"                              'git push origin main'
guard ask   "a deploy still asks (built-in default)"         'npx vercel deploy --prod'
guard ask   "adding a package still asks"                    'npm install left-pad'
guard block "bypassing the cooldown is still blocked"        'npm install left-pad --min-release-age=0'
guard ask   "publishing the library still asks"              'npm publish'
guard block "cat .env still blocked"                         'cat .env'
# SC2016: unexpanded on purpose; SIGNING_KEY is scenario B's configured secret var.
# shellcheck disable=SC2016
guard block "echo of the configured secret still blocked"    'echo $SIGNING_KEY'
# Documented consequence of answering "none yet" at bootstrap: the guard has no prod patterns to
# match, so prod safety rests entirely on prepare-versus-execute. Asserted so the trade-off stays
# visible rather than being discovered later.
guard allow "a prod-shaped command is NOT caught (no patterns configured)" 'psql postgres://u@db.prod.example/x'


echo "── nothing of the template survives bootstrap"
# Asserted here as well as in install.sh, so the install cannot mark its own homework.
for p in .template tests scripts/template-integrity.sh CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md \
         .github/ISSUE_TEMPLATE .claude/commands/bootstrap.md; do
  if [ -e "$p" ]; then t_fail "template file survived: $p"; else t_pass "gone: $p"; fi
done
if ! grep -qE '^  dco:' .github/workflows/ci.yml && ! grep -q '{{IF_SIGNOFF}}' .github/workflows/ci.yml README.md CLAUDE.md \
   && [ "$(git config format.signoff || true)" != "true" ] && ! grep -qF 'Signed-off-by' CLAUDE.md; then
  t_pass "sign-off off: no dco job, no git config, no markers left behind"
else
  t_fail "sign-off off: something leaked through" "$(grep -n 'dco\|SIGNOFF\|Signed-off' .github/workflows/ci.yml README.md CLAUDE.md)"
fi
if head -1 README.md | grep -qxF "# $(node -p 'require("./package.json").name')"; then
  t_pass "README.md is the project's own, titled with the project name"
else
  t_fail "README.md is not the generated project README" "$(head -3 README.md)"
fi
for p in docs/configuring-rules.md docs/five-layers.md docs/why-these-rules.md docs/choosing-a-model.md \
         docs/security-controls.md \
         scripts/claude-profile.sh scripts/claude-or.sh .claude/profiles/openrouter.settings.json.example \
         .claude/profiles/bedrock.settings.json.example .claude/profiles/vertex.settings.json.example \
         .claude/profiles/openai.settings.json.example .github/dependabot.yml; do
  if [ -f "$p" ]; then t_pass "shipped on purpose: $p"; else t_fail "missing shipped file: $p"; fi
done
if grep -qF 'One-time GitHub setup' README.md && grep -qF 'Dependabot alerts' README.md; then
  t_pass "the project README carries the one-time GitHub setup, Dependabot included"
else
  t_fail "project README is missing the GitHub setup steps"
fi
if grep -qxF '.claude/profiles/*.settings.json' .gitignore && grep -qxF '.claude/openrouter.settings.json' .gitignore \
   && ! grep -qxE 'DEVLOG.md|PROJECT-GUIDE.md' .gitignore; then
  t_pass ".gitignore keeps model-provider keys out and drops the template's own entries"
else
  t_fail ".gitignore entries wrong" "$(cat .gitignore)"
fi
if grep -qE "^Copyright \(c\) [0-9]{4} Sig Lib authors$" LICENSE && ! grep -q 'Buddhika\|Blott' LICENSE; then
  t_pass "MIT chosen: LICENSE names the project's holder, not the template's"
else
  t_fail "LICENSE holder wrong" "$(head -3 LICENSE)"
fi

t_summary "SPARSE CASES"
