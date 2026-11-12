#!/usr/bin/env bash
# Executes the /bootstrap install algorithm against a throwaway project, so the documented steps are
# tested rather than trusted. This script deliberately MIRRORS .claude/commands/bootstrap.md step for
# step: if you change the install algorithm there, change it here in the same PR, or the tests stop
# describing reality.
#
#   usage: tests/install.sh <scenario> <dest-dir>
#          scenario ∈ { a, b }  (see tests/values/scenario-*.json)
#
# The destination starts as a COPY OF THIS REPO (every tracked file, plus new files not yet ignored),
# exactly as a user's clone of the template would, so the install is tested against the template's
# own files and not an empty folder. That is what proves Step 4.0 and Step 5 leave nothing of the
# template behind. It is left in place for the case scripts to poke at, with its own git repo and a
# `base` branch: the ref the migration guardrail diffs against and the ref cases reset to.
set -euo pipefail

scenario="${1:-}"
dest="${2:-}"
if [ -z "$scenario" ] || [ -z "$dest" ]; then
  echo "usage: tests/install.sh <a|b> <dest-dir>" >&2; exit 2
fi

ROOT=$(git rev-parse --show-toplevel)
# The scenario is a letter (tests/values/scenario-<x>.json) or a path to a values file, which lets
# a case feed deliberately bad answers through the same validation bootstrap applies.
case "$scenario" in
  */*|*.json) VALUES="$scenario" ;;
  *) VALUES="$ROOT/tests/values/scenario-${scenario}.json" ;;
esac
[ -f "$VALUES" ] || { echo "✗ no such scenario: $scenario ($VALUES missing)" >&2; exit 2; }

case "$dest" in
  "$ROOT"|"$ROOT"/*) echo "✗ refusing to install into the template repo itself: $dest" >&2; exit 2 ;;
esac

value() { node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))[process.argv[2]] ?? ""))' "$VALUES" "$1"; }

echo "── installing scenario $scenario into $dest"
rm -rf "$dest"
mkdir -p "$dest"
# The user's starting point: a clone of the template. Working-tree content is copied (not HEAD), so
# uncommitted template changes are what get tested.
( cd "$ROOT" && git ls-files -z --cached --others --exclude-standard ) | while IFS= read -r -d '' f; do
  [ -e "$ROOT/$f" ] || continue
  mkdir -p "$dest/$(dirname "$f")"
  cp -p "$ROOT/$f" "$dest/$f"
done
cd "$dest"
T="$dest/.template"
git init -q -b main
git config user.email "tests@example.invalid"
git config user.name "Template Tests"

# ---- bootstrap Step 4.0: clear the template's own files ----
rm -rf README.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md tests scripts/template-integrity.sh \
  .github/CODEOWNERS .github/ISSUE_TEMPLATE .github/pull_request_template.md .github/dependabot.yml \
  .github/workflows/ci.yml
# The template-only .gitignore entries, and the comment lines directly above each.
node -e '
  const fs = require("fs"), lines = fs.readFileSync(".gitignore", "utf8").split("\n")
  for (const entry of ["DEVLOG.md", "PROJECT-GUIDE.md"]) {
    const i = lines.indexOf(entry); if (i < 0) continue
    let j = i; while (j > 0 && lines[j - 1].startsWith("#")) j--
    lines.splice(j, i - j + 1)
  }
  fs.writeFileSync(".gitignore", lines.join("\n").replace(/\n{3,}/g, "\n\n"))'
# ensure_ignored <line>: append to .gitignore unless already present (Step 4.1's "make sure").
ensure_ignored() { grep -qxF "$1" .gitignore 2>/dev/null || printf '%s\n' "$1" >> .gitignore; }

# ---- bootstrap Step 4.1: copy core ----
mkdir -p scripts .claude .github/workflows docs
cp "$T/core/lefthook.yml"      lefthook.yml
cp "$T/core/.gitleaks.toml"    .gitleaks.toml
cp "$T/core/ci/verify.yml"     .github/workflows/ci.yml
cp "$T"/core/scripts/*.sh      scripts/
cp "$T/core/settings.json"     .claude/settings.json
cp "$T/core/dependabot.yml"    .github/dependabot.yml
cp "$T/core/CODEOWNERS"        .github/CODEOWNERS
cp "$T/core/CLAUDE.project.md" CLAUDE.md.pending   # held back for Step 5
cp "$T/core/README.project.md" README.md.pending   # held back for Step 5
ensure_ignored '.guardrails/*.local'
ensure_ignored '.claude/settings.local.json'
ensure_ignored '.claude/profiles/*.settings.json'
ensure_ignored '.claude/openrouter.settings.json'
ensure_ignored '.guardrails/guard.log*'
# Step 4.1, sandbox (Q6): merged into the parsed settings, never edited as text.
node -e '
const fs = require("fs"), [mode, domains] = process.argv.slice(1), f = ".claude/settings.json"
if (mode === "off") process.exit(0)
const allowed = { "npm-github": ["registry.npmjs.org", "github.com", "*.github.com"], isolated: [] }[mode]
  ?? domains.split(/\s+/).filter(Boolean)
const j = JSON.parse(fs.readFileSync(f, "utf8"))
j.sandbox = { enabled: true, network: { allowedDomains: allowed } }
j.permissions.ask.push("Bash(dangerouslyDisableSandbox:true)")
fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n")' "$(value SANDBOX_MODE)" "$(value SANDBOX_DOMAINS)"
# Step 4.1, web pages (Q7).
node -e '
const fs = require("fs"), [mode, sites] = process.argv.slice(1), f = ".claude/settings.json"
const j = JSON.parse(fs.readFileSync(f, "utf8"))
if (mode === "ask") j.permissions.ask.push("WebFetch")
else if (mode === "block") j.permissions.deny.push("WebFetch")
else j.permissions.allow = sites.split(/\s+/).filter(Boolean).map((s) => "WebFetch(domain:" + s + ")")
fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n")' "$(value WEBFETCH_MODE)" "$(value WEBFETCH_SITES)"

# ---- bootstrap Step 4.2: copy the TypeScript fragment ----
cp "$T/lang/ts/biome.json"             biome.json
cp "$T/lang/ts/.nvmrc"                 .nvmrc
cp "$T/lang/ts/.npmrc"                 .npmrc
cp "$T/lang/ts/eslint-escape-hatch.md" docs/eslint-escape-hatch.md
cp "$T/lang/ts/tsconfig-note.md"       docs/tsconfig-note.md
node -e '
const fs = require("fs")
const frag = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
const name = process.argv[2]
fs.writeFileSync("package.json", JSON.stringify({ name, private: true, version: "0.1.0", scripts: frag.scripts }, null, 2) + "\n")
' "$T/lang/ts/package-scripts.json" "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).PROJECT_NAME)' "$VALUES")"
# No lockfile yet, so create one. The fixture has no dependencies, so this needs no network.
# Bootstrap step 4.2 also installs @biomejs/biome at the version biome.json names. That needs the
# registry, and this suite runs offline, so it is the one bootstrap step not mirrored here; the
# lint hook's behaviour with Biome present is covered by the template's own pre-commit run.
[ -f package-lock.json ] || npm install --package-lock-only --ignore-scripts --offline --no-audit --no-fund >/dev/null

GOVERNANCE=$(value GOVERNANCE_ENABLED)

# ---- bootstrap Step 4.2a: copy the governance tier (scenario A: on; scenario B: off) ----
gov_files=()
if [ "$GOVERNANCE" = "on" ]; then
  mkdir -p docs/governance/briefs
  cp "$T/governance/EVIDENCE.md"               docs/governance/EVIDENCE.md
  cp "$T/governance/DECISIONS.md"              docs/governance/DECISIONS.md
  cp "$T/governance/briefs/BRIEF-TEMPLATE.md"  docs/governance/briefs/BRIEF-TEMPLATE.md
  cp "$T/governance/pull_request_template.md"  .github/pull_request_template.md
  gov_files=(docs/governance/EVIDENCE.md docs/governance/DECISIONS.md)
fi

# ---- bootstrap Step 4.4: tier conditionals (security ON in both; governance per scenario) ----
# Security on: keep the line, strip the marker, and annotate it as pending (its files do not exist
# yet). Governance on: strip the marker, no annotation (Step 4.2a installed its files). Off: drop.
if [ "$GOVERNANCE" = "on" ]; then gov_expr='s/^{{IF_GOVERNANCE_TIER}}//'; else gov_expr='/^{{IF_GOVERNANCE_TIER}}/d'; fi
SIGNOFF=$(value SIGNOFF_ENABLED)
# In the YAML file the marker sits behind a comment sign so the template stays valid YAML.
if [ "$SIGNOFF" = "on" ]; then so_expr='s/^#\{0,1\}{{IF_SIGNOFF}}//'; else so_expr='/^#\{0,1\}{{IF_SIGNOFF}}/d'; fi
for f in CLAUDE.md.pending README.md.pending .github/workflows/ci.yml; do
  sed -e 's/^{{IF_SECURITY_TIER}}\(.*\)$/\1 (arrives in template release T2; not present yet)/' \
      -e "$gov_expr" -e "$so_expr" \
      "$f" > "$f.tiered"
  mv "$f.tiered" "$f"
done
[ "$SIGNOFF" = "on" ] && git config format.signoff true

# ---- bootstrap Step 4.3: fill every token ----
# Step 4.3's validation rule, mirrored: a value that would break the scripts or silently disable a
# check stops the install, which is what bootstrap must do too.
# SC2016: the single-quoted block is JavaScript; its ${} are template literals, not shell.
# shellcheck disable=SC2016
node -e '
  const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
  const { execFileSync } = require("child_process")
  const errs = []
  for (const [k, val] of Object.entries(v)) {
    if (k.startsWith("_") || typeof val !== "string") continue
    if (val.includes("\x27")) errs.push(`${k} contains a single quote`)
  }
  for (const k of ["PROD_GUARD_PATTERNS","SECRET_FILE_PATTERNS","ALLOWED_TRACKED","UNSAFE_SQL","STORAGE_PATTERNS","BUNDLE_LEAK_PATTERNS","PUBLIC_VAR_PREFIX"]) {
    if (!v[k]) continue
    try { execFileSync("grep", ["-qE", v[k]], { input: "", stdio: ["pipe","ignore","ignore"] }) }
    catch (e) { if (e.status >= 2) errs.push(`${k} is not a valid extended regex`) }
  }
  for (const k of ["PROD_ENV_VAR_NAMES","SECRET_VAR_NAMES","PUBLIC_VAR_ALLOWLIST"]) {
    if (v[k] && !/^[A-Za-z_][A-Za-z0-9_]*( [A-Za-z_][A-Za-z0-9_]*)*$/.test(v[k])) errs.push(`${k} must be space-separated identifiers`)
  }
  if (errs.length) { console.error("  ✗ invalid interview values:\n    " + errs.join("\n    ")); process.exit(1) }
' "$VALUES"
node "$ROOT/tests/lib/fill.mjs" "$VALUES" \
  lefthook.yml \
  .github/workflows/ci.yml \
  .github/CODEOWNERS \
  scripts/ci-guardrails.sh \
  scripts/claude-bash-guard.sh \
  scripts/claude-stop-guardrails.sh \
  .claude/settings.json \
  .gitleaks.toml \
  CLAUDE.md.pending \
  README.md.pending \
  ${gov_files[@]+"${gov_files[@]}"}

# ---- bootstrap Step 4.5: install hooks ----
# `npx lefthook install` needs the network and a lefthook binary, so it is stood in for by hook files
# carrying the marker check [10] looks for. Hooks live under .git/, so `git reset --hard` and
# `git clean` between cases leave them in place.
for h in pre-commit pre-push; do
  printf '#!/bin/sh\n# installed by lefthook (test stand-in)\nexit 0\n' > ".git/hooks/$h"
  chmod +x ".git/hooks/$h"
done

# ---- fixtures: a minimal, RULE-ABIDING project, so every guardrail has real code to inspect ----
for line in node_modules/ .env .env.local .dev.vars out/; do ensure_ignored "$line"; done

cat > .env.example <<'EOF'
# Public: safe to ship to the browser.
NEXT_PUBLIC_APP_URL=http://localhost:3000
# Server-only. Real values live outside the repo; never commit them.
DATABASE_URL=postgres://app:local_dev_only@localhost:5432/acme
SESSION_SECRET=changeme-local-dev-only
EOF

if [ "$scenario" = "a" ]; then
  mkdir -p src/app/api/session src/components src/server migrations db
  # A tracked file keeps src/components alive across `git clean -fd` between cases.
  printf 'export const Nav = () => null;\n' > src/components/nav.tsx
  cat > src/app/page.tsx <<'EOF'
export default function Page() {
  const appUrl = process.env.NEXT_PUBLIC_APP_URL ?? '/'
  return <a href={appUrl}>Sign in</a>
}
EOF
  cat > src/app/api/session/route.ts <<'EOF'
import { findSessionByTokenHash } from '../../../server/db'

export async function GET(request: Request) {
  const hash = request.headers.get('x-session-hash') ?? ''
  const session = await findSessionByTokenHash(hash)
  // Generic error to the client: no internal detail, no echo of the request.
  if (!session) return new Response('Not found', { status: 404 })
  return Response.json({ id: session.id })
}
EOF
  cat > src/server/db.ts <<'EOF'
import { sql } from './client'

// Parameterised only: the value is bound, never interpolated into the statement.
export async function findSessionByTokenHash(tokenHash: string) {
  const rows = await sql.query('select id from app.session where token_hash = $1', [tokenHash])
  return rows[0] ?? null
}
EOF
  cat > src/server/client.ts <<'EOF'
export const sql = {
  async query(_text: string, _params: unknown[]): Promise<Array<{ id: string }>> {
    return []
  },
}
EOF
  cat > migrations/0001_init.sql <<'EOF'
create schema if not exists app;
create table app.session (id uuid primary key, token_hash text not null);
EOF
  # Stands in for a real schema-dump command: SCHEMA_DUMP_CMD is `cat db/schema.source.sql`, so
  # mutating this file simulates the code and the committed dump drifting apart.
  cat > db/schema.source.sql <<'EOF'
schema app
table app.session (id uuid, token_hash text)
EOF
  cp db/schema.source.sql db/schema.sql
else
  mkdir -p src/client src/core
  cat > src/client/index.ts <<'EOF'
export const version = '0.1.0'
EOF
  cat > src/core/sign.ts <<'EOF'
import { createHmac } from 'node:crypto'

// Hash, never store or log the raw key.
export const sign = (body: string, key: string) =>
  createHmac('sha256', key).update(body).digest('hex')
EOF
fi

# ---- bootstrap Steps 4.6 and 4.7: verify green, then record Phase 0 (governance only) ----
if [ "$GOVERNANCE" = "on" ]; then
  verify=$(CI=false bash scripts/ci-guardrails.sh 2>&1) || {
    echo "  ✗ guardrails not green before recording Phase 0:"; printf '%s\n' "$verify" | sed 's/^/      /'; exit 1; }
  # SC2016: the single-quoted block is JavaScript; "$1" and "$2" there are regex back-references.
  # shellcheck disable=SC2016
  VERIFY="$verify" node -e '
    const fs = require("fs"), f = "docs/governance/EVIDENCE.md"
    let s = fs.readFileSync(f, "utf8")
    const marker = "<!-- bootstrap: guardrails output goes here -->"
    if (!s.includes(marker)) { console.error("Phase 0 marker missing"); process.exit(1) }
    s = s.replace(marker, () => "```text\n" + process.env.VERIFY.trimEnd() + "\n```")
    s = s.replace(/^(\| 0 \|.*\|) In progress (\|[^|]*\|)$/m, "$1 Done $2")
    fs.writeFileSync(f, s)
  '
  grep -qE '^\| 0 \|.*\| Done \|' docs/governance/EVIDENCE.md || { echo "  ✗ Phase 0 was not marked Done"; exit 1; }
  CI=false bash scripts/ci-guardrails.sh >/dev/null 2>&1 || {
    echo "  ✗ guardrails not green after recording Phase 0"; CI=false bash scripts/ci-guardrails.sh; exit 1; }
  echo "  ✓ Phase 0 recorded in the evidence log, and check [11] accepts it"
fi

# ---- bootstrap Step 5: the self-rewrite ----
mv CLAUDE.md.pending CLAUDE.md
mv README.md.pending README.md
holder=$(value _LICENSE_HOLDER)
if [ -z "$holder" ]; then
  rm -f LICENSE
else
  HOLDER="$holder" node -e '
    const fs = require("fs"), s = fs.readFileSync("LICENSE", "utf8")
    const out = s.replace(/^Copyright \(c\) .*$/m, () => "Copyright (c) " + new Date().getFullYear() + " " + process.env.HOLDER)
    if (out === s) { console.error("no copyright line in LICENSE"); process.exit(1) }
    fs.writeFileSync("LICENSE", out)'
fi
rm -rf .template .claude/commands/bootstrap.md
rmdir .claude/commands 2>/dev/null || true

# Step 5.5: nothing of the template may be left.
left=''
for p in .template tests scripts/template-integrity.sh CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md \
         .github/ISSUE_TEMPLATE .claude/commands/bootstrap.md; do
  [ -e "$p" ] && left="$left $p"
done
head -1 README.md | grep -qxF '# ai-dev-guardrails' && left="$left README.md(template's)"
{ ! grep -q '^/scripts/ci-guardrails.sh ' .github/CODEOWNERS || grep -q '/\.template/' .github/CODEOWNERS; } && left="$left .github/CODEOWNERS(template's)"
grep -qxE 'DEVLOG.md|PROJECT-GUIDE.md' .gitignore && left="$left .gitignore(template entries)"
if [ -n "$left" ]; then echo "  ✗ template files survived the install:$left"; exit 1; fi
echo "  ✓ nothing of the template is left (its README, tests, community files and bootstrap command are gone)"

# An installed project must carry no template placeholders. Match the same token shape the repo's
# template-integrity check uses, so GitHub Actions expressions (${{ github.base_ref }}) are not
# mistaken for unfilled tokens.
if leftover=$(grep -rnE '\{\{[A-Z_]+\}\}' --exclude-dir=.git . 2>/dev/null); then
  echo "  ✗ unfilled placeholder(s) survived the install:"; printf '%s\n' "$leftover" | sed 's/^/      /'
  exit 1
fi
echo "  ✓ no template placeholders left in the installed project"

git add -A
git commit -qm "baseline: bootstrapped guardrails and a minimal compliant source tree"
git branch -q base HEAD
echo "  ✓ scenario $scenario installed and committed at base"
