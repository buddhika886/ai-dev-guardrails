#!/usr/bin/env bash
# Layer 3/4: every check in scripts/ci-guardrails.sh must catch its own violation, and every
# fail-closed path must actually fail. Runs against a scenario A install (every check armed).
#
#   usage: tests/guardrail-cases.sh <installed-project-dir>
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "usage: tests/guardrail-cases.sh <installed-project-dir>" >&2
  exit 2
fi
ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
cd "$PROJ" || exit 2

echo "── [1] confidential files must not be tracked"
echo "-----BEGIN PRIVATE KEY-----" > deploy.pem; git add -f deploy.pem
expect_reject "a tracked .pem is caught" "confidential file(s) tracked"
printf 'DATABASE_URL=postgres://u:p@localhost/db\n' > .env.local; git add -f .env.local
expect_reject "a tracked .env.local is caught" "confidential file(s) tracked"
expect_accept "the allowlisted .env.example is not flagged" "none tracked"

echo "── [2] public-env allowlist and no server secrets in client code"
printf '\nconst k = process.env.NEXT_PUBLIC_STRIPE_KEY\n' >> src/app/page.tsx
expect_reject "an un-allowlisted NEXT_PUBLIC_ var is caught" "disallowed public var(s)"
printf '\nconst db = process.env.DATABASE_URL\n' >> src/app/page.tsx
expect_reject "a server-secret name in client code is caught" "server-secret name(s)"
printf '\nconst s = process.env.STRIPE_SECRET_KEY\n' >> src/app/page.tsx
expect_reject "a second server-secret name is caught" "server-secret name(s)"

echo "── [3] parameterised SQL only, across every SERVER_DIRS path"
# SC2016: the un-expanded ${id} is the point. It plants a TypeScript template-literal interpolation,
# which is precisely the string-built SQL the check exists to reject.
# shellcheck disable=SC2016
printf '\nexport const bad = (id: string) => sql.raw(`select * from app.session where id = ${id}`)\n' >> src/server/db.ts
expect_reject "sql.raw( in src/server is caught" "non-parameterised SQL"
# shellcheck disable=SC2016
printf '\nconst q = (t: string) => sql.unsafe(`select ${t}`)\n' >> src/app/api/session/route.ts
expect_reject "sql.unsafe( in the api dir is caught" "non-parameterised SQL"

echo "── [4] no browser storage in client code"
printf '\nlocalStorage.setItem("token", "abc")\n' >> src/app/page.tsx
expect_reject "localStorage is caught" "browser storage"
printf '\ndocument.cookie = "session=abc"\n' >> src/app/page.tsx
expect_reject "document.cookie is caught" "browser storage"
printf '\nsessionStorage.setItem("token", "abc")\n' >> src/app/page.tsx
expect_reject "sessionStorage is caught" "browser storage"

echo "── [5] migrations are additive"
printf '\nalter table app.session add column edited_in_place text;\n' >> migrations/0001_init.sql
git commit -qam "edit an applied migration (must be rejected)"
expect_reject "editing an applied migration is caught" "existing migration(s) modified/deleted"
git rm -q migrations/0001_init.sql
git commit -qm "delete an applied migration (must be rejected)"
expect_reject "deleting an applied migration is caught" "existing migration(s) modified/deleted"
cat > migrations/0002_add_expiry.sql <<'EOF'
alter table app.session add column expires_at timestamptz;
EOF
git add -A; git commit -qm "add a new migration (additive, must be accepted)"
expect_accept "adding a new migration is accepted" "only added (vs base)"
out=$(GUARDRAILS_BASE=no-such-ref bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -qF "  - SKIPPED (base ref 'no-such-ref' unavailable)" <<<"$out"; then
  t_pass "an unavailable base ref skips cleanly rather than crashing"
else
  t_fail "unavailable base ref (rc=$rc)" "$out"
fi
reset_project

echo "── [6] no secrets in the built bundle"
mkdir -p out; printf 'const c={DATABASE_URL:"postgres://u:p@db.prod.acme.example/app"};\n' > out/chunk.js
expect_reject "a leaked connection string in the bundle is caught" "secret-like string(s)"
mkdir -p out; printf 'const c={SESSION_SECRET:"hunter2"};\n' > out/chunk.js
expect_reject "a leaked secret name in the bundle is caught" "secret-like string(s)"
mkdir -p out; printf 'const c={appUrl:"http://localhost:3000"};\n' > out/chunk.js
expect_accept "a clean bundle is accepted" "bundle clean"

echo "── [7] schema truth, and its fail-closed paths"
printf 'table app.audit (id uuid)\n' >> db/schema.source.sql
expect_reject "schema drift is caught" "schema drift"
rm -f db/schema.sql
expect_reject "a missing committed dump fails closed" "is missing (failing closed)"
portable_sed "s|^SCHEMA_DUMP_CMD=.*|SCHEMA_DUMP_CMD='false'|" scripts/ci-guardrails.sh
expect_reject "an unrunnable dump command fails closed" "could not regenerate schema"

echo "── a runtime skip is never shown as verified"
# Every way a configured check can skip at runtime, in one run: fast mode (checks 6 and 7) and an
# unavailable base ref (check 5). None of their lines may carry a tick, in any letter case.
out=$(GUARDRAILS_FAST=1 GUARDRAILS_BASE=no-such-ref bash scripts/ci-guardrails.sh 2>&1)
if grep -i 'skipped' <<<"$out" | grep -qF '✓'; then
  t_fail "a runtime skip carries a tick" "$(printf '%s' "$out" | grep -i skipped)"
else
  t_pass "no runtime skip line carries a tick"
fi
n=$(grep -cF '  - SKIPPED (' <<<"$out")
if [ "$n" -eq 3 ]; then t_pass "all three runtime skips announce themselves"; else t_fail "expected 3 runtime skips, saw $n" "$out"; fi
rm -rf out
out=$(GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1)
if grep -qF "  - SKIPPED (no out yet, build first)" <<<"$out"; then
  t_pass "a missing build output is a skip, not a pass"
else
  t_fail "missing build output not reported as a skip" "$out"
fi
reset_project

echo "── fast mode skips only the expensive checks, and never hides a fast failure"
mkdir -p out; printf 'const c={SESSION_SECRET:"hunter2"};\n' > out/chunk.js
out=$(GUARDRAILS_FAST=1 GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -qF "  - SKIPPED (fast mode)" <<<"$out"; then
  t_pass "fast mode skips the bundle and schema checks"
else
  t_fail "fast mode skip (rc=$rc)" "$out"
fi
reset_project
printf '\nlocalStorage.setItem("token", "abc")\n' >> src/app/page.tsx
out=$(GUARDRAILS_FAST=1 GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -qF "browser storage" <<<"$out"; then
  t_pass "fast mode still enforces the cheap checks"
else
  t_fail "fast mode enforcement (rc=$rc)" "$out"
fi
reset_project

# The case scripts run the same way on a laptop and on a CI runner, so check [10] is armed here by
# clearing CI; its CI behaviour is asserted explicitly below.
export CI=false
# Ignored files survive reset_project (git clean without -x), so the local-only inputs to checks [8]
# and [9] are removed by hand after every case that plants them.
clean_local() { rm -rf .claude/settings.local.json .guardrails out; }
clean_local   # out/ is ignored too; the bundle cases above leave a chunk behind
local_allow() { mkdir -p .claude; printf '{"permissions":{"allow":%s}}\n' "$1" > .claude/settings.local.json; }

echo "── [8] agent consent controls intact, and no permission creep"
expect_accept "the installed settings pass" "no allow rule pre-approves a consent command"
portable_sed '/"Bash(git push \*)",/d' .claude/settings.json
expect_reject "removing a required ask rule is caught" "consent rule removed"
portable_sed 's|claude-bash-guard.sh|true|' .claude/settings.json
expect_reject "unwiring the bash guard is caught" "claude-bash-guard.sh is not wired"
portable_sed 's|claude-stop-guardrails.sh|true|' .claude/settings.json
expect_reject "unwiring the Stop hook is caught" "claude-stop-guardrails.sh is not wired"
# A relative path is found only while the agent sits at the project root; after `cd apps/web` the
# hook cannot start, and Claude Code treats a hook that cannot start as non-blocking.
# SC2016: ${CLAUDE_PROJECT_DIR} is literal on purpose; Claude Code expands it when it runs the hook.
# shellcheck disable=SC2016
portable_sed 's|${CLAUDE_PROJECT_DIR}/scripts/claude-bash-guard.sh|scripts/claude-bash-guard.sh|' .claude/settings.json
expect_reject "a relative hook path is caught" "claude-bash-guard.sh is not wired"
node -e 'const f=".claude/settings.json",fs=require("fs");const j=JSON.parse(fs.readFileSync(f,"utf8"));delete j.hooks.PreToolUse[0].hooks[0].onFailure;fs.writeFileSync(f,JSON.stringify(j,null,2))'
expect_reject "dropping onFailure: block is caught" 'must set "onFailure": "block"'
# Shell form (no args array) re-parses the path through a shell; the check requires exec form.
# SC2016: ${CLAUDE_PROJECT_DIR} is literal on purpose; Claude Code expands it when it runs the hook.
# shellcheck disable=SC2016
node -e 'const f=".claude/settings.json",fs=require("fs");const j=JSON.parse(fs.readFileSync(f,"utf8"));const h=j.hooks.PreToolUse[0].hooks[0];h.command="bash ${CLAUDE_PROJECT_DIR}/scripts/claude-bash-guard.sh";delete h.args;fs.writeFileSync(f,JSON.stringify(j,null,2))'
expect_reject "a shell-form hook command is caught" "claude-bash-guard.sh is not wired"
portable_sed '/"disableBypassPermissionsMode": "disable",/d' .claude/settings.json
expect_reject "removing the bypass-mode lock is caught" "disableBypassPermissionsMode must be"
portable_sed '/"Read(.env)",/d' .claude/settings.json
expect_reject "removing a Read deny rule is caught" "deny rule removed from .claude/settings.json: Read(.env)"
portable_sed '/"Bash(gh pr create \*)",/d' .claude/settings.json
expect_reject "removing a non-sample ask rule is caught" "consent rule removed from .claude/settings.json: Bash(gh pr create *)"
mkdir -p .claude; printf '{"disableAllHooks": true}\n' > .claude/settings.local.json
expect_reject "disableAllHooks in the local file is caught" "disableAllHooks is true"; clean_local
mkdir -p .claude; printf '{"permissions":{"defaultMode":"bypassPermissions"}}\n' > .claude/settings.local.json
expect_reject "bypassPermissions as the local default mode is caught" "defaultMode is bypassPermissions"; clean_local
local_allow '["Bash(git push:*)"]'
expect_reject "the legacy :* prefix form is caught as creep" "permission creep"; clean_local
rm -f .claude/settings.json
expect_reject "a missing settings file is caught" ".claude/settings.json is missing"
local_allow '["Bash(npm test)", "Bash(git push *)"]'
expect_reject "a local allow for git push is caught" "permission creep"; clean_local
local_allow '["Bash(npx *)"]'
expect_reject "an npx wildcard that pre-approves deploys is caught" "permission creep"; clean_local
local_allow '["Bash"]'
expect_reject "a bare Bash allow is caught" "permission creep"; clean_local
local_allow '["Bash(cat *)"]'
expect_reject "an allow that would let cat read .env is caught" "permission creep"; clean_local
local_allow '["Bash(npm test)", "Bash(npx biome check *)", "Bash(git status *)", "Read(src/**)"]'
expect_accept "ordinary local allows are accepted" "no allow rule pre-approves a consent command"; clean_local
mkdir -p .claude; printf '{not json\n' > .claude/settings.local.json
expect_reject "an unparseable local settings file fails closed" "could not parse the settings files"; clean_local
portable_sed '/"Edit(.npmrc)",/d' .claude/settings.json
expect_reject "removing the ask rule for editing .npmrc is caught" "consent rule removed from .claude/settings.json: Edit(.npmrc)"
local_allow '["Bash(npm install *)"]'
expect_reject "a local allow that pre-approves adding packages is caught" "permission creep"; clean_local

echo "── [9] client denylist: blocks, and never prints the name it protects"
mkdir -p .guardrails
printf '# client identifiers\n\nGlobex[[:space:]]+Holdings\n' > .guardrails/denylist.local
expect_accept "a denylist with a blank line does not match everything" "none found"
mkdir -p .guardrails
printf '# client identifiers\n\nGlobex[[:space:]]+Holdings\n' > .guardrails/denylist.local
printf '\n// Prepared for Globex Holdings Ltd\n' >> src/server/db.ts
out=$(guardrails_out); rc=$?
if [ "$rc" -ne 0 ] && grep -qF "denylisted client identifier(s) found" <<<"$out" \
   && grep -qF "src/server/db.ts:" <<<"$out"; then
  t_pass "a denylisted name in a tracked file is caught, by location"
else
  t_fail "denylist hit (rc=$rc)" "$out"
fi
if grep -qi globex <<<"$out"; then
  t_fail "the guardrails output printed the denylisted name" "$out"
else
  t_pass "the output does not contain the denylisted name"
fi
reset_project
printf 'Globex Holdings\n' > notes.md; git add notes.md
expect_reject "a staged, never-committed file is caught" "denylisted client identifier(s) found"
printf 'Globex(\n' > .guardrails/denylist.local
expect_reject "an invalid denylist regex fails closed" "could not be applied"
printf 'Globex\n' > .guardrails/denylist.local; git add -f .guardrails/denylist.local
expect_reject "a tracked denylist is caught" "is tracked"; clean_local
printf '\n// Prepared for Globex Holdings Ltd\n' >> src/server/db.ts
export GUARDRAILS_DENYLIST='Globex[[:space:]]+Holdings'
expect_reject "the CI variable alone arms the check" "denylisted client identifier(s) found"
unset GUARDRAILS_DENYLIST
expect_accept "with no denylist at all, the check announces itself" "[9] Client denylist: SKIPPED"

echo "── [10] local git hooks installed"
mv .git/hooks/pre-push .git/hooks/pre-push.parked
expect_reject "a missing pre-push hook is caught" "pre-push hook not installed"
out=$(CI=true GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -qF "[10] Local git hooks installed: SKIPPED" <<<"$out"; then
  t_pass "on a CI runner the check is skipped, and says so"
else
  t_fail "CI skip (rc=$rc)" "$out"
fi
mv .git/hooks/pre-push.parked .git/hooks/pre-push

echo "── [11] governance records: Done needs evidence, deviations need cost, exit and owner"
EV=docs/governance/EVIDENCE.md
DEC=docs/governance/DECISIONS.md
# add_row <markdown row>: insert a status-table row directly after Phase 0's.
add_row() {
  ROW="$1" node -e '
    const fs = require("fs"), f = process.argv[1]
    const s = fs.readFileSync(f, "utf8").replace(/^(\| 0 \|.*)$/m, (m) => m + "\n" + process.env.ROW)
    fs.writeFileSync(f, s)' "$EV"
}
# add_section <file> <before-heading> <text>: insert text just before a "## " heading.
add_section() {
  TEXT="$3" node -e '
    const fs = require("fs"), [f, h] = process.argv.slice(1)
    const s = fs.readFileSync(f, "utf8")
    if (!s.includes("\n## " + h)) { console.error("no heading " + h); process.exit(1) }
    fs.writeFileSync(f, s.replace("\n## " + h, () => "\n" + process.env.TEXT + "\n\n## " + h))' "$1" "$2"
}
expect_accept "the bootstrapped records pass, Phase 0 included" "every Done phase has evidence"
if grep -qE '^\| 0 \|.*\| Done \|' "$EV" && grep -qF 'GUARDRAILS PASSED.' "$EV"; then
  t_pass "bootstrap recorded Phase 0 as Done, with the real guardrails output"
else
  t_fail "Phase 0 was not recorded" "$(sed -n '/## Status/,/## Out-of-band/p' "$EV")"
fi
add_row '| 1 | Session expiry | session test passes | Done | |'
expect_reject "Done with no evidence link is caught" "phase 1 is Done but has no evidence link"
add_row '| 1 | Session expiry | session test passes | Done | [Phase 1](#phase-1-session-expiry) |'
expect_reject "Done linking to a missing section is caught" "which is not a section in this file"
add_row '| 1 | Session expiry | session test passes | Done | [Phase 1](#phase-1-session-expiry) |'
add_section "$EV" "Out-of-band changes" '## Phase 1: Session expiry

It works, all tests pass.'
expect_reject "Done with a prose-only evidence section is caught" "has no output block or link"
add_row '| 1 | Session expiry | session test passes | Done | [Phase 1](#phase-1-session-expiry) |'
add_section "$EV" "Out-of-band changes" '## Phase 1: Session expiry

```text
PASS src/server/session.test.ts (4 tests)
```'
expect_accept "Done with an output block is accepted" "every Done phase has evidence"
add_row '| 1 | Session expiry | session test passes | Done | [Phase 1](#phase-1-session-expiry) |'
add_section "$EV" "Out-of-band changes" '## Phase 1: Session expiry

CI run: https://github.com/acme/portal/actions/runs/123'
expect_accept "Done with a link to a CI run is accepted" "every Done phase has evidence"
add_row '| 1 | Session expiry | session test passes | Complete | |'
expect_reject "an unknown state cannot dodge the rule" "has unknown state \"Complete\""
add_row '| 1 | Session expiry | session test passes | In progress | |'
expect_accept "a phase in progress needs no evidence yet" "every Done phase has evidence"
add_section "$DEC" "Open questions" '### D-001: Static deploy token in CI
- **Standard:** short-lived OIDC credentials
- **Cost:** a long-lived token that must be rotated by hand
- **Owner:** platform lead
- **Recorded:** 2026-10-26'
expect_reject "a deviation with no Exit is caught" "has no Exit"
add_section "$DEC" "Open questions" '### D-001: Static deploy token in CI
- **Standard:** short-lived OIDC credentials
- **Cost:** a long-lived token that must be rotated by hand
- **Exit:** TBD
- **Owner:** platform lead'
expect_reject "a placeholder Exit (TBD) is caught" "has no Exit"
add_section "$DEC" "Open questions" '### D-001: Static deploy token in CI
- **Standard:** short-lived OIDC credentials
- **Cost:** a long-lived token that must be rotated by hand
- **Exit:** OIDC federation is live, target 2026-12-01
- **Owner:** platform lead
- **Recorded:** 2026-10-26'
expect_accept "a complete deviation is accepted" "every Done phase has evidence"
portable_sed 's/^## Deviations$/## Exceptions/' "$DEC"
expect_reject "renaming a required section is caught" "no \"deviations\" section"
rm -f "$EV"
expect_reject "a deleted evidence log fails, it does not skip" "docs/governance/EVIDENCE.md is missing"
portable_sed "s|^GOVERNANCE_ENABLED=.*|GOVERNANCE_ENABLED='maybe'|" scripts/ci-guardrails.sh
expect_reject "a bad GOVERNANCE_ENABLED value fails closed" "must be 'on' or 'off'"
if [ -f .github/pull_request_template.md ] && grep -qF '## Evidence' .github/pull_request_template.md; then
  t_pass "the PR template is installed with an Evidence section"
else
  t_fail "PR template missing"
fi
if grep -qF 'docs/governance/EVIDENCE.md' CLAUDE.md && ! grep -F 'docs/governance' CLAUDE.md | grep -qF 'not present yet'; then
  t_pass "CLAUDE.md points at the governance records, with no 'not present yet' note"
else
  t_fail "CLAUDE.md governance pointers wrong" "$(grep -n governance CLAUDE.md)"
fi


echo "── [12] dependency policy: .npmrc, package-lock.json and npm version"
# Lockfile fixtures are built here, never committed whole: a package entry is name, version,
# resolved URL and integrity, and each case changes one of them. The hash is a placeholder of the
# right shape; check [12] verifies the algorithm, not the bytes (npm itself does that on install).
REG=https://registry.npmjs.org
SHA="sha512-$(printf 'A%.0s' $(seq 1 86))=="
# lockfile <json of the packages object, without the root entry>
lockfile() {
  PKGS="$1" node -e '
    const fs = require("fs"), pkg = JSON.parse(fs.readFileSync("package.json", "utf8"))
    const packages = Object.assign({ "": { name: pkg.name, version: pkg.version } }, JSON.parse(process.env.PKGS))
    fs.writeFileSync("package-lock.json", JSON.stringify({ name: pkg.name, version: pkg.version, lockfileVersion: 3, requires: true, packages }, null, 2) + "\n")'
}
entry() { printf '"node_modules/%s":{"version":"%s","resolved":"%s","integrity":"%s"}' "$1" "$2" "$3" "$4"; }
good_is_number=$(entry is-number 7.0.0 "$REG/is-number/-/is-number-7.0.0.tgz" "$SHA")
good_types=$(entry @types/node 24.0.0 "$REG/@types/node/-/node-24.0.0.tgz" "$SHA")

expect_accept "the installed .npmrc and lockfile pass" ".npmrc keeps the policy: 7-day release cooldown"
lockfile "{$good_is_number,$good_types}"
expect_accept "registry packages with sha512 hashes are accepted, scoped ones included" "2 package(s), all from an allowed registry"
lockfile "{$(entry is-number 7.0.0 'git+ssh://git@github.com/acme/is-number.git#4f2c' "$SHA")}"
expect_reject "a git dependency in the lockfile is caught" "not an allowed registry"
lockfile "{$(entry is-number 7.0.0 'https://cdn.acmecorp.net/is-number-7.0.0.tgz' "$SHA")}"
expect_reject "a tarball from another host is caught" "not an allowed registry"
lockfile "{$(entry is-number 7.0.0 'http://registry.npmjs.org/is-number/-/is-number-7.0.0.tgz' "$SHA")}"
expect_reject "the registry over plain http is caught" "not an allowed registry"
lockfile "{$(entry is-number 7.0.0 "$REG/is-numbr/-/is-numbr-7.0.0.tgz" "$SHA")}"
expect_reject "a name pointed at another package's tarball is caught" "tarball for a different package"
lockfile "{$(entry is-number 7.0.0 "$REG/is-number/-/is-number-7.0.0.tgz" '')}"
expect_reject "a package with no integrity hash is caught" "has no sha512 integrity hash"
lockfile "{$(entry is-number 7.0.0 "$REG/is-number/-/is-number-7.0.0.tgz" 'sha1-AAAAAAAAAAAAAAAAAAAAAAAAAAA=')}"
expect_reject "a weak sha1 hash is caught" "has no sha512 integrity hash"
printf '{"name":"x","version":"1.0.0","lockfileVersion":1,"dependencies":{}}\n' > package-lock.json
expect_reject "a version 1 lockfile cannot dodge the check" "lockfile version 1"
rm -f package-lock.json
expect_reject "a missing lockfile is caught" "package-lock.json is missing"
printf '{not json\n' > package-lock.json
expect_reject "an unparseable lockfile fails closed" "could not read .npmrc or package-lock.json"

rm -f .npmrc
expect_reject "a missing .npmrc is caught" ".npmrc is missing"
for bad in 'min-release-age=0' 'min-release-age=3' 'min-release-age=seven'; do
  portable_sed "s/^min-release-age=.*/$bad/" .npmrc
  expect_reject "a weakened cooldown ($bad) is caught" ".npmrc: min-release-age is"
done
portable_sed '/^min-release-age=/d' .npmrc
expect_reject "a removed cooldown is caught" "min-release-age is not set"
printf '\nmin-release-age=0\n' >> .npmrc
expect_reject "a later line overriding the cooldown is caught (the last one wins)" ".npmrc: min-release-age is \"0\""
portable_sed 's/^min-release-age=.*/min-release-age=14/' .npmrc
expect_accept "a longer cooldown is accepted" "14-day release cooldown"
printf '\nbefore=2099-01-01\n' >> .npmrc
expect_reject "a 'before' date that overrides the cooldown is caught" "before is set"
portable_sed 's/^allow-git=.*/allow-git=all/' .npmrc
expect_reject "allowing git dependencies is caught" ".npmrc: allow-git is \"all\""
portable_sed '/^allow-remote=/d' .npmrc
expect_reject "removing the URL-dependency rule is caught" ".npmrc: allow-remote is \"unset\""
portable_sed 's/^strict-allow-scripts=.*/strict-allow-scripts=false/' .npmrc
expect_reject "relaxing the install-script policy is caught" "strict-allow-scripts must be true"
printf '\ndangerously-allow-all-scripts=true\n' >> .npmrc
expect_reject "running every install script is caught" "dangerously-allow-all-scripts is true"
printf '\nregistry=https://npm.acmecorp.net/\n' >> .npmrc
expect_reject "an unlisted registry is caught" "not in ALLOWED_REGISTRIES"
printf '\n@acme:registry=https://npm.acmecorp.net/\n' >> .npmrc
expect_reject "an unlisted scoped registry is caught" "@acme:registry points at"
portable_sed "s|^ALLOWED_REGISTRIES=.*|ALLOWED_REGISTRIES='https://registry.npmjs.org/ https://npm.acmecorp.net/'|" scripts/ci-guardrails.sh
printf '\n@acme:registry=https://npm.acmecorp.net\n' >> .npmrc
lockfile "{$(entry @acme/ui 1.0.0 'https://npm.acmecorp.net/@acme/ui/-/ui-1.0.0.tgz' "$SHA")}"
expect_accept "a registry added to ALLOWED_REGISTRIES is accepted" "1 package(s), all from an allowed registry"

SHIM=$(mktemp -d)
printf '#!/bin/sh\necho 10.9.2\n' > "$SHIM/npm"; chmod +x "$SHIM/npm"
out=$(PATH="$SHIM:$PATH" GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -qF "npm 10.9.2 ignores min-release-age" <<<"$out"; then
  t_pass "an npm too old to enforce the cooldown is caught"
else
  t_fail "old npm (rc=$rc)" "$out"
fi
printf '#!/bin/sh\nexit 1\n' > "$SHIM/npm"
out=$(PATH="$SHIM:$PATH" GUARDRAILS_BASE=base bash scripts/ci-guardrails.sh 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -qF "npm is not on PATH, so its version cannot be checked (failing closed)" <<<"$out"; then
  t_pass "a broken npm fails closed"
else
  t_fail "broken npm (rc=$rc)" "$out"
fi
rm -rf "$SHIM"
reset_project

echo "── nothing of the template survives bootstrap"
# Asserted here as well as in install.sh, so the install cannot mark its own homework.
for p in .template tests scripts/template-integrity.sh CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md \
         .github/CODEOWNERS .github/ISSUE_TEMPLATE .claude/commands/bootstrap.md; do
  if [ -e "$p" ]; then t_fail "template file survived: $p"; else t_pass "gone: $p"; fi
done
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
CI=.github/workflows/ci.yml
if grep -qE '^  dependencies:' "$CI" && grep -qE 'SHA256: "[0-9a-f]{64}"' <(sed -n '/^  dependencies:/,/^  secrets:/p' "$CI") \
   && grep -qF 'osv-scanner scan source --lockfile package-lock.json' "$CI" && grep -qF 'npm audit signatures' "$CI"; then
  t_pass "CI scans dependencies with a checksum-pinned OSV-Scanner and checks registry signatures"
else
  t_fail "CI is missing the dependency scan or the signature check" "$(cat "$CI")"
fi
if [ "$(cut -d. -f1 .nvmrc)" -ge 24 ] 2>/dev/null && grep -qE '^  - package-ecosystem: npm' .github/dependabot.yml \
   && [ "$(grep -c 'default-days: 7' .github/dependabot.yml)" -eq 2 ]; then
  t_pass "Node 24+ (npm with the cooldown) is pinned, and Dependabot waits the same 7 days"
else
  t_fail "Node pin or Dependabot cooldown wrong" "$(cat .nvmrc .github/dependabot.yml)"
fi
if [ ! -e LICENSE ]; then
  t_pass "no licence chosen: LICENSE removed (all rights reserved)"
else
  t_fail "LICENSE should have been removed for scenario A" "$(head -3 LICENSE)"
fi

t_summary "GUARDRAIL CASES"
