#!/usr/bin/env bash
# Layer 2: the PreToolUse bash guard and the Stop hook, as installed.
#
# Guard contract, three outcomes:
#   block  exit 2, reason on stderr (shown to the model)
#   ask    exit 0 with a PreToolUse permissionDecision "ask" on stdout (the user is prompted)
#   allow  exit 0, no output
# Two properties matter equally and are both tested here: it stops what it claims to stop, and it
# does NOT stop ordinary work. A guard that over-blocks gets disabled by the first person it annoys,
# which is a security regression by another route.
#
#   usage: tests/hook-cases.sh <installed-project-dir>
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "usage: tests/hook-cases.sh <installed-project-dir>" >&2
  exit 2
fi
ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
cd "$PROJ" || exit 2

# guard <block|ask|allow> <label> <command-text>: feeds a realistic PreToolUse payload on stdin.
guard() {
  local want="$1" label="$2" cmd="$3" payload
  payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$cmd")
  guard_decide "$want" "$label" "$payload" "$PATH"
}

# guard_raw <block|ask|allow> <label> <raw-stdin> <PATH-value>: for the degraded-environment cases.
guard_raw() { guard_decide "$1" "$2" "$3" "$4"; }

echo "── production from local must be BLOCKED"
guard block "psql against the prod host"          'psql postgres://app@db.prod.acme.example:5432/acme -c "select 1"'
guard block "vercel deploy"                       'vercel deploy --prod'
guard block "vercel link"                         'vercel link'
guard block "wrangler deploy"                     'npx wrangler deploy'
# SC2016: these must reach the guard UNEXPANDED. The whole point is a command that names a
# prod-bearing env var without any prod hostname in the text, which is the guard's documented blind
# spot and the reason it matches variable names too.
# shellcheck disable=SC2016
guard block "prod env-var indirection (psql)"     'psql "$PROD_DATABASE_URL" -f migrations/0002_add_expiry.sql'
# shellcheck disable=SC2016
guard block "prod env-var indirection (deploy)"   'curl -H "Authorization: Bearer $DEPLOY_TOKEN" https://api.example.com/release'
guard block "prod host buried mid-pipeline"       'pg_dump postgres://app@db.prod.acme.example/acme | gzip > dump.gz'

echo "── destructive git must be BLOCKED"
guard block "git push --force"                    'git push --force origin main'
guard block "git push -f"                         'git push -f origin main'
guard block "git push --force-with-lease"         'git push --force-with-lease origin main'
guard block "git reset --hard"                    'git reset --hard HEAD~1'
guard block "git clean -fd"                       'git clean -fd'

echo "── ordinary work must be ALLOWED"
guard allow "npm test"                            'npm test'
guard allow "git status"                           'git status --short'
guard allow "psql against localhost"              'psql postgres://app@localhost:5432/acme -c "select 1"'
guard allow "grepping for a public var name"      'grep -rn NEXT_PUBLIC_APP_URL src/app'
guard allow "git reset without --hard"            'git reset HEAD~1'
guard allow "the guardrails themselves"           'bash scripts/ci-guardrails.sh'

echo "── outward-facing actions must ASK, every time"
guard ask   "git commit"                          'git commit -m "add session expiry"'
guard ask   "an ordinary branch push"             'git push origin feature/session-expiry'
guard ask   "push hidden after cd &&"             'cd src && git push'
guard ask   "git options before the subcommand"   'git -C . commit -am wip'
guard ask   "git --no-pager push"                 'git --no-pager push'
guard ask   "opening a pull request"              'gh pr create --fill'
guard ask   "merging a pull request"              'gh pr merge 12 --squash'
guard ask   "a mutating gh api call"              'gh api -X POST repos/acme/portal/releases'
guard ask   "npm publish"                         'npm publish --access public'
guard ask   "pnpm publish"                        'pnpm publish'
guard ask   "netlify deploy (built-in, no prod pattern needed)" 'netlify deploy --prod'
guard ask   "vercel --prod without the deploy verb" 'npx vercel --prod'
guard ask   "a remote migration"                  'npx supabase db push'
guard ask   "prisma migrate deploy"               'npx prisma migrate deploy'
guard ask   "drizzle-kit push"                    'npx drizzle-kit push'
guard ask   "setting a remote secret"             'gh secret set STRIPE_SECRET_KEY'
guard ask   "setting platform config"             'heroku config:set FEATURE_X=1'
# Deny outranks ask: scenario A lists `wrangler deploy` as a prod pattern, so it stays a hard block.
guard block "a configured prod pattern still blocks, not asks" 'npx wrangler deploy'

echo "── read-only and local work must NOT ask"
guard allow "git log mentioning push"             'git log --oneline --grep push'
guard allow "git diff"                            'git diff --stat'
guard allow "gh pr view"                          'gh pr view 12'
guard allow "a read-only gh api call"             'gh api repos/acme/portal/pulls'
guard allow "prisma migrate dev (local)"          'npx prisma migrate dev'
guard allow "vercel dev (local)"                  'npx vercel dev'

echo "── printing a secret into the transcript must be BLOCKED"
guard block "cat .env"                            'cat .env'
guard block "cat .env.local"                      'cat .env.local'
guard block "a nested env file"                   'less ./config/.env.production'
guard block "grep in .env prints values"          'grep -n SECRET .env'
guard block "input redirection from .env"         'sort < .env'
guard block "diff against the real .env"          'diff .env .env.example'
guard block "a private key file"                  'cat certs/server.key'
guard block "an SSH private key"                  'cat ~/.ssh/id_ed25519'
guard block "home npm credentials"                'cat ~/.npmrc'
guard block "bare env"                            'env'
guard block "env piped onward"                    'env | sort'
guard block "bare printenv"                       'printenv'
guard block "env after a separator"               'source .env && env'
guard block "process.env dumped from node"        "node -e 'console.log(process.env)'"
# SC2016: the variable must reach the guard unexpanded; that is the command being judged.
# shellcheck disable=SC2016
guard block "echo of a configured secret var"     'echo $SESSION_SECRET'
# shellcheck disable=SC2016
guard block "echo of a secret-shaped var name"    'echo "token is ${GITHUB_TOKEN}"'
guard block "printenv of a configured secret"     'printenv DATABASE_URL'
guard block "a secret-manager read"               'op read op://dev/stripe/secret'
guard block "a token printer"                     'gh auth token'
guard block "platform config dump"                'heroku config'

echo "── ordinary work around secrets must be ALLOWED"
guard allow "reading the committed example"       'cat .env.example'
guard allow "creating .env from the example"      'cp .env.example .env'
guard allow "grepping the example"                'grep -n DATABASE_URL .env.example'
guard allow "the dev.vars example"                'cat .dev.vars.example'
guard allow "an env prefix on a command"          'env NODE_ENV=test npm test'
guard allow "sourcing without printing"           'source .env && npm run dev'
guard allow "set -euo pipefail"                   'set -euo pipefail'
# shellcheck disable=SC2016
guard allow "echo of a non-secret var"            'echo $NODE_ENV'
# shellcheck disable=SC2016
guard allow "presence test without printing"      '[ -n "$SESSION_SECRET" ] && echo set'
guard allow "printenv of a non-secret var"        'printenv NODE_ENV'
guard allow "an SSH public key"                   'cat ~/.ssh/id_ed25519.pub'
guard allow "jq field named key"                  'jq .key package.json'

echo "── adding a dependency must ASK; installing the lockfile must not"
guard ask   "npm install of a named package"              'npm install left-pad'
guard ask   "npm i with a flag before the name"           'npm i -D typescript'
guard ask   "a scoped package with a long flag"           'npm install --save-dev @types/node'
guard ask   "npm add"                                     'npm add zod'
guard ask   "a global install"                            'npm install -g some-cli'
guard ask   "an install hidden after cd &&"               'cd web && npm install react'
guard ask   "pnpm add"                                    'pnpm add zod'
guard ask   "yarn add"                                    'yarn add zod'
guard ask   "bun add"                                     'bun add zod'
guard ask   "pnpm dlx (does not read .npmrc)"             'pnpm dlx create-vite my-app'
guard ask   "bunx"                                        'bunx cowsay hi'
guard ask   "approving an install script"                 'npm approve-scripts esbuild'
guard allow "npm install from the lockfile"               'npm install'
guard allow "npm ci"                                      'npm ci'
guard allow "npm install with flags only"                 'npm install --ignore-scripts'
guard allow "install then test"                           'npm install && npm test'
guard allow "npx of a local tool (obeys .npmrc)"          'npx tsc --noEmit'
guard allow "npm view"                                    'npm view react version'
guard allow "pnpm install from the lockfile"              'pnpm install --frozen-lockfile'

echo "── switching off the dependency policy must be BLOCKED"
guard block "a cooldown override on the command line"     'npm install left-pad --min-release-age=0'
guard block "running every install script"               'npm ci --dangerously-allow-all-scripts'
guard block "relaxing the install-script policy"          'npm install --no-strict-allow-scripts'
guard block "allowing git dependencies"                   'npm install --allow-git=all'
guard block "a registry override"                         'npm install zod --registry=https://npm.acmecorp.net/'
guard block "a before date that overrides the cooldown"   'npx --before=2099-01-01 create-thing'
guard block "npm config set on a policy key"              'npm config set min-release-age 0'
guard block "npm config delete on a policy key"           'npm config delete allow-git'
guard block "npm config edit"                             'npm config edit'
guard block "an environment-variable override"           'npm_config_min_release_age=0 npm install left-pad'
guard block "an upper-case environment override"          'NPM_CONFIG_REGISTRY=https://npm.acmecorp.net/ npm ci'
guard allow "git log --before is not npm"                 'git log --before=2026-01-01 --oneline'
guard allow "npm config get is read-only"                 'npm config get min-release-age'

echo "── rewriting a guardrail file from the shell must ASK"
guard ask   "sed -i on the bash guard"                   'sed -i "s/exit 2/exit 0/" scripts/claude-bash-guard.sh'
guard ask   "a redirect over the checks"                 'echo "" > scripts/ci-guardrails.sh'
guard ask   "rm on the hooks config"                     'rm lefthook.yml'
guard ask   "cp over the CI workflow"                    'cp /tmp/ci.yml .github/workflows/ci.yml'
guard ask   "tee into CLAUDE.md"                         'tee CLAUDE.md < /tmp/rules.md'
guard ask   "appending to .npmrc"                        'printf "allow-git=all\n" >> .npmrc'
guard allow "reading the checks is fine"                 'cat scripts/ci-guardrails.sh'
guard allow "running the checks is fine"                 'bash scripts/ci-guardrails.sh'
guard allow "diffing a guardrail file is fine"           'git diff scripts/ci-guardrails.sh'
guard allow "sed without -i on a guardrail file is fine" 'sed -n 1,20p scripts/ci-guardrails.sh'
guard allow "cp between ordinary files is fine"          'cp src/a.ts src/b.ts'

echo "── the ask decision must be well-formed"
payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:"git push origin main"}}))')
out=$(printf '%s' "$payload" | bash scripts/claude-bash-guard.sh 2>/dev/null)
if printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s).hookSpecificOutput;if(o.hookEventName!=="PreToolUse"||o.permissionDecision!=="ask"||!o.permissionDecisionReason)process.exit(1)})' 2>/dev/null; then
  t_pass "valid JSON with hookEventName, permissionDecision and a reason"
else
  t_fail "malformed ask output" "$out"
fi

echo "── the guard must FAIL CLOSED when it cannot read the command"
# A shim dir where both JSON parsers exist but fail, forcing the raw-payload fallback path.
SHIM=$(mktemp -d)
trap 'rm -rf "$SHIM"' EXIT
for p in node python3; do printf '#!/bin/sh\nexit 9\n' > "$SHIM/$p"; chmod +x "$SHIM/$p"; done
BROKEN_PATH="$SHIM:$PATH"

guard_raw block "no hook payload at all blocks"            ''                                                        "$PATH"
guard_raw block "unparseable payload hiding a prod host"   '{not json vercel deploy --prod'                          "$PATH"
guard_raw block "no working parser, prod command"          '{"tool_input":{"command":"vercel deploy --prod"}}'        "$BROKEN_PATH"
guard_raw block "no working parser, force-push"            '{"tool_input":{"command":"git push --force origin main"}}' "$BROKEN_PATH"
guard_raw ask   "no working parser, a push still asks"   '{"tool_input":{"command":"git push origin main"}}'      "$BROKEN_PATH"
guard_raw allow "no working parser, ordinary command"      '{"tool_input":{"command":"npm test"}}'                    "$BROKEN_PATH"
guard_raw allow "valid payload with no command field"      '{"tool_input":{}}'                                        "$PATH"

echo "── a long command must not slip past"
# The match is on line 1 and about 200 KB of text follows, well past a 64 KiB pipe buffer. A guard
# that pipes the command into `grep -q` under pipefail loses the match to SIGPIPE and allows these.
# The filler is built inside node: a 200 KB command-line argument exceeds Linux's per-argument limit.
guard_long() {
  local want="$1" label="$2" first="$3" payload
  payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]+"\n"+"# filler line\n".repeat(15000)}}))' "$first")
  guard_decide "$want" "$label" "$payload" "$PATH"
}
guard_long ask   "a push followed by 200 KB still asks"       'git push origin main'
guard_long block "reading .env followed by 200 KB still blocks" 'cat .env'
guard_long block "printenv followed by 200 KB still blocks"   'printenv'
guard_long block "prod deploy followed by 200 KB still blocks" 'vercel deploy --prod'
guard_long allow "an ordinary command followed by 200 KB"     'npm test'

echo "── the hooks must still work after the agent changes directory"
# Claude Code runs command hooks in the agent's current directory, which follows its `cd`. The
# settings wire each hook through ${CLAUDE_PROJECT_DIR}; these cases run the EXACT command and args
# from settings.json, substituted the way Claude Code does, from a subdirectory of the project.
hook_from_subdir() {
  local event="$1" want="$2" label="$3" cmd="$4" root="$PWD" sub payload out rc decided
  sub=$(mktemp -d "$PWD/subdir-case.XXXXXX")
  payload=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$cmd")
  out=$(cd "$sub" && printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$root" node -e '
    const fs=require("fs"), {spawnSync}=require("child_process")
    const root=process.env.CLAUDE_PROJECT_DIR
    const h=JSON.parse(fs.readFileSync(root+"/.claude/settings.json","utf8")).hooks[process.argv[1]][0].hooks[0]
    const sub=(x)=>x.replace(/\$\{CLAUDE_PROJECT_DIR\}/g, root)
    const r=spawnSync(sub(h.command), (h.args||[]).map(sub), {input: fs.readFileSync(0), encoding:"utf8"})
    process.stdout.write(r.stdout); process.stderr.write(r.stderr); process.exit(r.status===null?126:r.status)
  ' "$event" 2>/dev/null); rc=$?
  rm -rf "$sub"
  if [ "$rc" -eq 2 ]; then decided=block
  elif [ "$rc" -eq 0 ] && grep -q '"permissionDecision":"ask"' <<<"$out"; then decided=ask
  elif [ "$rc" -eq 0 ]; then decided=allow
  else decided="rc=$rc"; fi
  if [ "$decided" = "$want" ]; then t_pass "$label"; else t_fail "$label (wanted $want, got $decided)" "$out"; fi
}
hook_from_subdir PreToolUse block "from a subdirectory, reading .env still blocks" 'cat .env'
hook_from_subdir PreToolUse block "from a subdirectory, a prod deploy still blocks" 'vercel deploy --prod'
hook_from_subdir PreToolUse ask   "from a subdirectory, a push still asks"          'git push origin main'
hook_from_subdir PreToolUse allow "from a subdirectory, ordinary work is allowed"   'npm test'
hook_from_subdir Stop       allow "from a subdirectory, the Stop hook finds the guardrails" ''

echo "── the Stop hook warns without ever blocking"
out=$(bash scripts/claude-stop-guardrails.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  t_pass "a green project produces no noise"
else
  t_fail "green project (rc=$rc)" "$out"
fi

printf '\nlocalStorage.setItem("token", "abc")\n' >> src/app/page.tsx
out=$(bash scripts/claude-stop-guardrails.sh 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -qF '"systemMessage"' <<<"$out" && grep -qF 'Guardrails FAILED' <<<"$out"; then
  t_pass "a red project emits a systemMessage and still exits 0"
else
  t_fail "red project (rc=$rc)" "$out"
fi
# The message is embedded in JSON by hand, so prove it is still valid JSON.
if printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{JSON.parse(s)})' 2>/dev/null; then
  t_pass "the warning is valid JSON"
else
  t_fail "the warning is not valid JSON" "$out"
fi
# A path containing a double quote must not break the JSON it gets embedded in.
mkdir -p 'src/app/we"ird'
printf 'localStorage.setItem("t","x")\n' > 'src/app/we"ird/page.tsx'
out=$(bash scripts/claude-stop-guardrails.sh 2>&1)
if printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{JSON.parse(s)})' 2>/dev/null; then
  t_pass "a quote in the failing path does not break the JSON"
else
  t_fail "quote in path broke the JSON" "$out"
fi
reset_project

t_summary "HOOK CASES"
