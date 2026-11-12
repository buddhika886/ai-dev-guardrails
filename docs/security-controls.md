# Security controls

The complete list of controls in this project: every block, prompt, check, scan, policy and setting,
where each one is enforced, when it runs, what proves it works, and where it stops. For why each one
exists, see [why-these-rules.md](why-these-rules.md); for how to change one, see
[configuring-rules.md](configuring-rules.md).

The template's test suite fails if a control exists in the code but is missing from this page, so
the list cannot quietly fall behind.

## How to read this page

| Type | Meaning |
| --- | --- |
| **Block** | Refused outright; nobody can approve it from the AI session |
| **Ask** | You are prompted every time the command is recognised, even if "don't ask again" was clicked before and in auto mode. Bypass-permissions mode would skip the prompt, so the settings disable that mode |
| **Check** | A guardrail that fails the commit, push or CI run |
| **Scan** | A scanner that fails on findings (secrets, known vulnerabilities) |
| **Policy** | A setting in a committed file that a tool enforces, and a check keeps in place |
| **Written rule** | Stated in `CLAUDE.md` for the AI and every contributor; enforced by people and review |
| **Manual setting** | A GitHub repository setting. **No file in the repository can switch it on or prove it is on** |

"Proven by" names the test suite in the template repository that shows the control catching what it
is for and allowing normal work: `hook-cases`, `guardrail-cases`, `sparse-cases`, `profile-cases`,
`gitleaks-config-cases` and `install` (all in `tests/`).

---

## 1. AI command guard

**File:** `scripts/claude-bash-guard.sh`. **Runs:** before every shell command the AI runs, whichever
model is behind Claude Code. **Proven by:** `hook-cases`, `sparse-cases`.

| Control | Type | Covers |
| --- | --- | --- |
| `PROD_GUARD_PATTERNS` | Block | Commands naming your production hosts or deploy verbs (set at bootstrap) |
| `PROD_ENV_VAR_NAMES` | Block | Commands using variables that carry production credentials |
| Force-push | Block | `git push --force`, `-f`, `--force-with-lease`, `--mirror`, `--delete`/`-d`, and a `+ref` refspec (`git push origin +main`), including through a command-line alias |
| Destructive git | Block | `git reset --hard`, `git clean -f`, `git clean --force` |
| `SECRET_FILE_READ` | Block | Reading `.env*`, `.dev.vars`, model-provider profiles (`.claude/profiles/*.settings.json`), the client denylist (`.guardrails/*.local`), `/proc/*/environ`, key and certificate files, `~/.npmrc`, `.netrc`, `.pgpass`, credential files, SSH keys, Docker and Kubernetes config (committed example files are exempt). The file list is `SECRET_FILES`; the readers include `curl` and `wget`, so sending one (`curl -d @.env`) or reading it through a `file://` address is blocked too |
| `GLOB_READ` | Block | A secret reader given a glob the shell would expand to a secret file: a dotfile glob (`cat .en*`, `cat ./.e??`), `.*`, or a glob ending in a key extension (`cat *.pem`). Ordinary globs (`cat src/*.ts`) are not affected |
| `ENV_DUMP` | Block | `env` and `printenv` wherever they appear as a command, with or without a prefix (`FOO=bar env`, `eval 'env'`, `env -0`); `set`, `export -p`, `declare -x` in command position; dumping `process.env` or `os.environ`. `env FOO=1 cmd` stays allowed |
| `SECRET_CLIS` | Block | Secret-manager and platform commands that print a secret (1Password, Doppler, Vault, `gh auth token`, cloud secret managers, `kubectl get secret -o`) |
| `SECRET_VAR_NAMES`, `SECRET_NAME_SHAPE` | Block | Echoing or `printenv` of a configured secret, or any variable named like `*SECRET*`, `*TOKEN*`, `*PASSWORD*`, `*API_KEY*` |
| `SECRET_VIA_CODE` | Block | The same secrets reached through code or a here-string: `process.env.NAME`, `os.environ["NAME"]`, `os.environ.get("NAME")`, awk `ENVIRON["NAME"]`, `cat <<< "$NAME"`, `tee x <<< "$NAME"`. Presence tests (`[ -n "$NAME" ]`) and non-secret names (`process.env.NODE_ENV`) are not affected |
| `DEP_WEAKEN` | Block | Overriding the dependency policy for one command: `--min-release-age`, `--before`, `--registry`, `--allow-git`, `--allow-remote`, `--strict-allow-scripts`, `--dangerously-allow-all-scripts`, `npm config set` or `edit` on those keys, `npm_config_*` variables |
| `GIT_ALIAS` | Ask | Any `git -c alias.<name>=<command>` on the command line, which can stand for commit, push or anything else and so hides the verb from the patterns above |
| `CONSENT_PATTERNS` | Ask | `git commit`, `git push` (also behind `-C`, `-c`, `--no-pager`); `gh pr create`, `merge`, `close`, `ready`; `gh release create`, `upload`, `edit`, `delete`; `gh repo create`, `edit`, `delete`; `gh workflow run`; `gh api` with POST, PUT, PATCH or DELETE; `publish`, `unpublish`, `deprecate`, `dist-tag` for npm, pnpm, yarn and bun; `changeset publish`; `docker push` |
| `DEPLOY_PATTERNS` | Ask | Vercel, Netlify, Wrangler, Fly, Firebase, Railway, Heroku rollback, Serverless, EAS, Supabase `db push` and functions deploy, `prisma migrate deploy` and `db push`, `drizzle-kit push` and `migrate` |
| `REMOTE_CONFIG_PATTERNS` | Ask | Setting or deleting secrets and config on GitHub, Wrangler, Vercel, Fly, Supabase, Heroku |
| `DEPENDENCY_PATTERNS` | Ask | `npm install <name>`, `npm add`, `pnpm add`, `yarn add`, `bun add`, `bun install <name>`, `pnpm dlx`, `yarn dlx`, `bunx`, `npm approve-scripts` |
| `NETWORK_FETCH` | Ask | Fetching from the network from the shell: `curl`, `wget` and HTTPie (`http`, `https`, `xh`). One plain `curl` or `wget` whose only hosts are this machine's (`LOCAL_HOSTS`: `localhost`, `127.0.0.1`, `[::1]`) runs without asking; a second command, a redirect, a variable, a proxy, resolve or config flag, a secret file, or any other host or IP makes it ask |
| `ENFORCEMENT_WRITE` | Ask | A shell command that rewrites a guardrail file (`sed -i`, `perl -i`, a redirect, `tee`, `cp`, `mv`, `rm`, `truncate`, `chmod`, `install`, `ln` onto the guard, the checks, the Stop hook, `lefthook.yml`, the CI workflow, `CODEOWNERS`, `.gitleaks.toml`, `.claude/settings.json`, `CLAUDE.md`, `.npmrc`, `.mcp.json`, the decision log `.guardrails/guard.log`, or the AI's other instruction files: `CLAUDE.local.md`, `AGENTS.md`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.agents/`). Reading, running or diffing them is not asked about |
| Decision log | Record | Every block and ask adds one line to `.guardrails/guard.log`: the time (UTC), the decision and the rule's name, for example `2026-11-11T10:42:07Z ask NETWORK_FETCH`. Never the command, which can hold a secret. `(raw)` marks a decision made on an unparsed payload. Kept on this machine (gitignored), moved to `guard.log.1` past 1 MB. Best effort: a failure to write never changes the decision, and a symlinked log is not written through. Rewriting it asks (`ENFORCEMENT_WRITE`, `Edit(.guardrails/guard.log)`) |
| No payload | Block | The guard was called without a command to inspect (fails closed) |
| Misconfigured pattern | Block | A filled pattern that is not a valid regex, or a name list that is not plain identifiers, blocks every command with a "misconfigured" reason until it is fixed. Otherwise an invalid pattern would make grep exit 2 and the check it feeds would silently vanish |
| Unreadable payload | Block or Ask | No JSON parser, or malformed input: the patterns are matched against the raw payload instead of trusting an empty command |
| Long commands | Block or Ask | A match is never lost on a long, multi-line command (matching reads the whole command, never a pipe that can be cut short) |

**Limits.** The guard reads command text. A command that reaches production or prints a secret
indirectly (through a variable, a script, or an unexpected form) can pass it. It gates the AI only:
commands you type yourself are not inspected.

## 2. Claude Code settings

**File:** `.claude/settings.json`. **Runs:** on every AI tool call; Claude Code evaluates deny, then
ask, then allow, so a saved "allow" cannot override these. **Proven by:** `guardrail-cases` (check 8),
`hook-cases`.

| Control | Type | Covers |
| --- | --- | --- |
| `Bash(git commit *)`, `Bash(git push *)` | Ask | Commits and pushes, as a second layer behind the guard |
| `Bash(gh pr create *)`, `Bash(gh pr merge *)`, `Bash(gh release create *)` | Ask | Pull requests and releases |
| `Bash(npm publish *)`, `Bash(pnpm publish *)`, `Bash(yarn publish *)`, `Bash(yarn npm publish *)`, `Bash(bun publish *)` | Ask | Publishing a package |
| `Edit(.npmrc)` | Ask | The AI changing the dependency policy file. (`Edit` rules cover every file-editing tool; a `Write(...)` rule matches nothing, per Claude Code's own diagnostics) |
| `Edit(scripts/claude-bash-guard.sh)`, `Edit(scripts/ci-guardrails.sh)`, `Edit(scripts/claude-stop-guardrails.sh)`, `Edit(lefthook.yml)`, `Edit(.github/workflows/ci.yml)`, `Edit(.github/CODEOWNERS)`, `Edit(.gitleaks.toml)`, `Edit(CLAUDE.md)`, `Edit(.claude/settings.json)`, `Edit(.mcp.json)`, `Edit(.guardrails/guard.log)`, `Edit(CLAUDE.local.md)`, `Edit(AGENTS.md)`, `Edit(.claude/agents/**)`, `Edit(.claude/skills/**)`, `Edit(.claude/commands/**)`, `Edit(.agents/**)` | Ask | The AI changing an enforcement file with its editing tools. A prompt-injected or over-eager agent would otherwise weaken the guard with one edit, and the guard script is read fresh on every command. The guard's `ENFORCEMENT_WRITE` (section 1) covers the same files from the shell; CODEOWNERS (section 5) covers them in pull requests |
| `mcp__*` | Ask | Every tool from every MCP server, project or user level. MCP tools run outside the bash guard, so each call asks first. Claude Code already asks before connecting a server listed in `.mcp.json`; check 8 fails if `enableAllProjectMcpServers` switches that off |
| `disableBypassPermissionsMode: "disable"` | Policy | A session cannot be started in bypass-permissions mode, which skips every prompt including the ask rules above and the guard's ask decisions. Check 8 fails without it |
| `Read(.env)`, `Read(.env.*)`, `Read(.dev.vars)` (with `Read(!.env.example)`, `Read(!.env.sample)` allowed) | Block | Claude Code's file reader opening environment files |
| `Read(.claude/profiles/*.settings.json)`, `Read(.guardrails/*.local)` | Block | The file reader opening a model-provider profile (holds a live API key) or the client denylist. The `.example` profiles stay readable |
| `Read(*.pem)`, `Read(*.key)`, `Read(*.p12)`, `Read(*.pfx)` | Block | Opening private keys and certificates |
| `Read(~/.npmrc)`, `Read(~/.netrc)`, `Read(~/.pgpass)`, `Read(~/.ssh/id_*)`, `Read(~/.aws/credentials)`, `Read(~/.docker/config.json)`, `Read(~/.kube/config)` | Block | Opening credential files in your home directory |
| `sandbox` (chosen at bootstrap, Q6) | Optional | Claude Code's operating-system sandbox around shell commands: they reach only the project's files and the allowed internet addresses (npm and GitHub, none, or a list you give); anything else asks. Covers what the guard cannot see, such as `grep -r` over the whole project. Not enforced by a check: it is a per-project choice, and native Windows has no sandbox. Allowing a broad domain such as `github.com` leaves a path for data to leave the machine |
| `Bash(dangerouslyDisableSandbox:true)` (added with the sandbox) | Ask | A command Claude retries outside the sandbox always asks first |
| `WebFetch` (chosen at bootstrap, Q7) | Ask, Allow list or Block | Claude's web-fetch tool. Ask (recommended): every page asks, and a saved "don't ask again" cannot override it. Allow list: `WebFetch(domain:<site>)` rules in `settings.json` for the sites named at bootstrap, every other site asks. Block: a `WebFetch` deny rule. Check 8 fails if a site is saved to `settings.local.json` |
| PreToolUse hook | Policy | Wires the command guard (section 1) to every shell command, in exec form through `${CLAUDE_PROJECT_DIR}` so it is found after the AI changes directory, with `onFailure: block` so a guard that cannot start blocks the command rather than letting it run (needs Claude Code 2.1.295 or later; older versions ignore the field). Check 8 fails on a relative path, shell form or a missing `onFailure` |
| Stop hook (`scripts/claude-stop-guardrails.sh`) | Check | At the end of each AI turn, runs the fast guardrails from the project root and warns, naming the first failing check. Never blocks |

## 3. Guardrail checks

**File:** `scripts/ci-guardrails.sh`. **Runs:** on commit (fast mode), on push, in CI, and at the end
of each AI turn (fast mode). Fast mode skips checks 6 and 7. A check that does not apply prints
`SKIPPED (reason)`, never a tick, and a check that cannot run fails. **Proven by:** `guardrail-cases`
(scenario A, everything on) and `sparse-cases` (scenario B, empty settings).

| # | Check | Settings | Skipped when |
| --- | --- | --- | --- |
| 0 | Configuration is valid: every filled pattern parses, name lists are plain identifiers, every configured directory exists. A grep error anywhere below (exit 2) is reported as a failure, never read as "no match" | All CONFIG values | Never |
| 1 | No confidential files in git, and never Claude Code's `.claude/settings.local.json` (it stores saved approvals, passwords included) whatever the patterns say | `SECRET_FILE_PATTERNS`, `ALLOWED_TRACKED`, `AGENT_LOCAL_FILES` | Never |
| 2 | Only approved public variables reach the browser; no server secret names in client code | `PUBLIC_VAR_PREFIX`, `PUBLIC_VAR_ALLOWLIST`, `SECRET_VAR_NAMES`, `CLIENT_DIR` | No public prefix |
| 3 | Database queries are parameterised | `UNSAFE_SQL`, `SERVER_DIRS` | Never |
| 4 | No browser storage in client code | `STORAGE_PATTERNS`, `CLIENT_DIR` | Never |
| 5 | Migrations are only ever added | `MIGRATIONS_DIR` | No migrations folder; base ref unavailable |
| 6 | No secrets in the built app | `BUNDLE_DIR`, `BUNDLE_LEAK_PATTERNS` | No build folder; fast mode; not built yet |
| 7 | Database schema matches the committed copy | `SCHEMA_DUMP_CMD`, `SCHEMA_DUMP_FILE` | No database; fast mode |
| 8 | AI safety settings intact (parsed, not grepped): both hooks wired through `${CLAUDE_PROJECT_DIR}` in exec form with `onFailure: block` on the guard; every required ask and deny rule present; bypass-permissions mode disabled; no `disableAllHooks`, bypass default mode or `enableAllProjectMcpServers` in either settings file; no allow rule (`*` or `:*` form) pre-approves a consent, deploy, package or secret-printing command; no web-fetch approval saved to `settings.local.json`; no permission rule in either file contains a credential (inline password, password flag, `sshpass -p`, credentials in a URL, an authorisation header, a known API key or token shape, a private key). Rules holding a credential are reported by position, never printed | `CONSENT_SAMPLES`, `REQUIRED_ASK_RULES`, `REQUIRED_DENY_RULES`, `SAVED_SECRET_SHAPES` | Never |
| 9 | No client names in tracked or staged files (reports file and line only); the denylist itself is never tracked | `.guardrails/denylist.local`, `GUARDRAILS_DENYLIST` | No denylist |
| 10 | Local git hooks installed | None | In CI |
| 11 | Governance records honest: Done needs evidence; exceptions need cost, exit and owner | `GOVERNANCE_ENABLED` | Governance tier not installed |
| 12 | Dependency policy holds: `.npmrc` keeps its settings; lockfile entries from an allowed registry over https, with sha512 hashes, naming the right package; npm 11.10 or later | `MIN_RELEASE_AGE_DAYS`, `NPM_MIN_VERSION`, `ALLOWED_REGISTRIES` | No `package.json` |
| 13 | No hidden characters in the files the AI reads as instructions (`CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `.claude/`, `.agents/`, `.mcp.json`, Cursor and Copilot rules): tag characters, zero-width and invisible characters, bidirectional controls, and variation selectors or joiners that are not part of an emoji. Reported by file, line and code point, never the text. OWASP GenAI LLM Top 10 2026, LLM01 | `AI_INSTRUCTION_FILES` | Never |
| 14 | MCP servers in `.mcp.json` are pinned: a package runner (`npx`, `bunx`, `pnpm dlx`, `yarn dlx`, `uvx`, `pipx run`) names an exact version, a container image a `sha256` digest, a remote server uses https. A server run from the repository's own code passes. An unparseable file fails. OWASP GenAI LLM Top 10 2026, LLM01 and LLM04 | None | No `.mcp.json` |

## 4. Local git hooks

**File:** `lefthook.yml`. **Runs:** on your machine at `git commit` and `git push`, once installed
with `npx lefthook install` (check 10 fails until it is). **Proven by:** `install`, `guardrail-cases`
(check 10).

| Hook | Command | Type | What it does |
| --- | --- | --- | --- |
| pre-commit | `guardrails-fast` | Check | Guardrail checks in fast mode |
| pre-commit | `gitleaks-staged` | Scan | Secret scan of the staged changes (skipped, and says so, if gitleaks is not installed) |
| pre-commit | `lint` | Check | Lint on staged files |
| pre-push | `1-typecheck` | Check | Type check |
| pre-push | `2-build` | Check | Build, so check 6 has output to scan |
| pre-push | `3-guardrails-full` | Check | All guardrail checks |
| pre-push | `4-dependency-scan` | Scan | OSV-Scanner on the lockfile (skipped, and says so, if not installed) |

**Limit.** `git commit --no-verify` skips local hooks. CI (section 5) is the authority.

## 5. CI

**File:** `.github/workflows/ci.yml`. **Runs:** on every pull request to `main` and every push to
`main`. **Proven by:** `guardrail-cases` asserts the installed workflow's contents; the template's own
CI runs actionlint on it. The scan steps' behaviour was verified against real projects when added.

| Control | Type | What it does |
| --- | --- | --- |
| `permissions: contents: read` | Policy | The workflow token can read the repository and nothing else |
| Actions pinned to commit SHAs | Policy | A moved or hijacked version tag cannot change what runs |
| `verify` job | Check | `npm ci` (fails on lockfile drift), `npm audit signatures`, typecheck, lint, build, all guardrail checks with the `GUARDRAILS_DENYLIST` secret. On a pull request the checks run from the **base branch's** copy of `scripts/ci-guardrails.sh`, so a change that weakens a check cannot grade itself |
| SBOM (`sbom` artifact) | Record | Each `verify` run writes a CycloneDX software bill of materials from `package-lock.json` (`npm sbom`), listing every package with its version and licence, and attaches it to the run. It blocks nothing: it answers "do we ship the affected version?" when an advisory lands, and is build evidence for audits. Artifacts expire with the repository's retention setting (90 days by default) |
| `.github/CODEOWNERS` | Policy | Names the guardrail owners for every enforcement file (guard, checks, Stop hook, settings, `lefthook.yml`, `.github/`, `.gitleaks.toml`, `.npmrc`, `CLAUDE.md`, `.mcp.json`, `AGENTS.md`, `.claude/agents/`, `.claude/skills/`, `.claude/commands/`, `.agents/`). With the ruleset's "require review from Code Owners" (section 11), a pull request that touches them needs an owner's approval |
| `dependencies` job | Scan | OSV-Scanner, checksum-pinned, on `package-lock.json`; fails on any known vulnerability or a missing lockfile; skips, and says so, with no dependencies yet |
| `secrets` job | Scan | gitleaks, checksum-pinned, over the full git history |
| `dco` job (optional, chosen at bootstrap) | Check | Every commit in a pull request carries a `Signed-off-by` line, the contributor's statement that they may submit it under the project's licence. Bootstrap also sets `git config format.signoff true` in the clone so the line is added automatically |

## 6. Secret scanning

**File:** `.gitleaks.toml`. **Runs:** on commit (staged changes) and in CI (full history). **Proven
by:** `gitleaks-config-cases`.

| Control | Type | What it does |
| --- | --- | --- |
| gitleaks default ruleset | Scan | Hundreds of known key and token formats |
| `credential-in-connection-string` | Scan | A password inside a database or service URL |
| `openrouter-api-key` | Scan | OpenRouter keys (`sk-or-v1-...`) |
| Allowlist | Policy | Ignores obvious placeholders (`example`, `changeme`, `localhost` and similar), `.env.example` and `.dev.vars.example`; no directory is skipped |

## 7. Dependencies

**Proven by:** `guardrail-cases` (check 12 and CI contents), `hook-cases` (ask and block).

| Control | Type | File | What it does |
| --- | --- | --- | --- |
| `min-release-age=7` | Policy | `.npmrc` | npm installs only versions at least 7 days old (applies when npm chooses versions; `npm ci` installs the reviewed lockfile as it is) |
| `allow-git=none`, `allow-remote=none` | Policy | `.npmrc` | No dependencies straight from git repositories or URLs |
| `strict-allow-scripts=true` | Policy | `.npmrc` | A dependency's install script runs only when approved in `package.json`; an unreviewed one fails the install |
| Node 24 | Policy | `.nvmrc` | Pins a Node release whose npm enforces the cooldown |
| Dependabot version updates, 7-day cooldown | Policy | `.github/dependabot.yml` | Weekly update pull requests for npm and GitHub Actions, never for a version npm would refuse |
| Vulnerability exceptions with an expiry | Policy | `osv-scanner.toml` (only when needed) | An accepted finding stops applying on its `ignoreUntil` date and CI fails again |

Plus check 12 (section 3), the guard's `DEPENDENCY_PATTERNS` and `DEP_WEAKEN` (section 1), the
`.npmrc` ask rules (section 2) and the `dependencies` CI job (section 5).

**Limits.** Set up for npm; pnpm, yarn and bun have their own settings, which check 12 does not read.
A vulnerability scanner only knows what has been reported.

## 8. Model profiles

**Files:** `scripts/claude-profile.sh`, `scripts/claude-or.sh`, `.claude/profiles/`. **Runs:** when a
developer starts Claude Code with a profile. **Proven by:** `profile-cases`.

| Control | Type | What it does |
| --- | --- | --- |
| Per-session only | Policy | A profile applies to the session the launcher starts; plain `claude` is never affected, and no file is written |
| Settings merge | Policy | A profile adds to the project settings, so every hook and permission rule still applies |
| Committable profile refused | Block | The launcher will not start from a profile that git tracks or would not ignore |
| Placeholder refused | Block | The launcher will not start while any value reads `REPLACE-ME` |
| Invalid name or JSON refused | Block | Names cannot step outside `.claude/profiles/`; a broken file is reported before Claude Code starts |
| Example profiles ship with placeholders | Policy | `openrouter`, `bedrock`, `vertex`, `openai` examples hold no key |

The `openrouter-api-key` scan (section 6) catches an OpenRouter key that reaches a committed file.

## 9. Files kept out of git

**File:** `.gitignore` (bootstrap makes sure these lines exist). **Proven by:** `install`,
`guardrail-cases`, `sparse-cases`.

| Entry | Type | Keeps out |
| --- | --- | --- |
| `.guardrails/*.local` | Policy | The private client denylist |
| `.claude/settings.local.json` | Policy | Each developer's own saved permissions |
| `.claude/profiles/*.settings.json` | Policy | Model profiles and their API keys |
| `.claude/openrouter.settings.json` | Policy | The OpenRouter profile's old location |
| `.guardrails/guard.log*` | Policy | The command guard's local decision log and its rotated copy |

Check 1 (section 3) is the backstop for everything else: a committed `.env`, key or credential file
fails it whether or not `.gitignore` lists it.

## 10. Governance tier (optional)

**Files:** `docs/governance/`, `.github/pull_request_template.md`. **Proven by:** `install`,
`guardrail-cases` (check 11).

| Control | Type | What it does |
| --- | --- | --- |
| Evidence log (`EVIDENCE.md`) | Check | Each phase has an observable "done when"; a phase marked Done must link to real output or a CI run (check 11). Bootstrap records Phase 0 from its own verified run |
| Decision record (`DECISIONS.md`) | Check | Settled decisions; every known exception states its cost, when it ends and who owns it (check 11) |
| Phase briefs (`briefs/`) | Written rule | The AI works from a written brief per phase |
| Pull request template | Written rule | Asks for evidence with every change |

**Limit.** Check 11 checks structure, not quality. A reviewer still judges whether the evidence proves
the claim.

## 11. GitHub settings (manual)

**Set up by:** the repository owner, once, as listed in the project README's "One-time GitHub
setup". **No file can switch these on, and no check can see them.** If they are off, the protection
they describe is not there.

| Setting | Type | What it adds |
| --- | --- | --- |
| Dependabot alerts | Manual setting | Warnings when a dependency has a known vulnerability |
| Dependabot security updates | Manual setting | Automatic pull requests that fix those vulnerabilities |
| Secret scanning with push protection | Manual setting | GitHub rejects a push that contains a recognised secret |
| Ruleset on `main` | Manual setting | Pull request with at least one approval and review from Code Owners; `verify`, `dependencies` and `secrets` must pass; no force-push. Without it, CI reports but does not block, and CODEOWNERS is advisory |
| Read-only workflow token | Manual setting | The default token for every workflow can only read |
| `GUARDRAILS_DENYLIST` secret | Manual setting | Lets CI enforce check 9 (client work only) |

## 12. Written rules and design rules

**File:** `CLAUDE.md` (the AI reads it at the start of every session). These are enforced by people,
review and, where named, by the controls above.

| Rule | Type | Backed by |
| --- | --- | --- |
| Consent each time before commit, push or deploy | Written rule | Guard `CONSENT_PATTERNS`, `DEPLOY_PATTERNS`; settings ask rules; check 8 |
| Production: prepare, then a person runs it | Written rule | Guard `PROD_GUARD_PATTERNS`, `PROD_ENV_VAR_NAMES` (backstop only) |
| Local-first: no cloud resources until told | Written rule | People and review |
| Transcript hygiene: never print a secret; test presence instead | Written rule | Guard secret blocks; settings `Read` denies |
| Security rules: no secrets in files, only approved public values, hash tokens, parameterised SQL, no browser storage, generic errors, no force-push | Written rule | Checks 1 to 4 and 6; gitleaks; guard |
| Least-privilege database role; access through parameterised, access-controlled procedures | Design rule | Review; check 3 |
| Tokens random, hashed at rest, single-use where possible, expiring | Design rule | Review |
| Uploads validated by content, size-capped, stored under a generated key | Design rule | Review |
| Test data synthetic and flagged (`is_fixture`); never real personal data | Design rule | Review; check 9 for client names |
| Migrations additive; schema dump regenerated with every schema change | Written rule | Checks 5 and 7 |
| Evidence standard: done means output shown, not described | Written rule | Check 11 (governance tier) |
| Client confidentiality: codenames only | Written rule | Check 9 |
| Dependencies: add only when needed, confirm the name, never weaken `.npmrc` | Written rule | Guard; check 12; CI scans |
| MCP servers: add only when needed, from a trusted source, pinned to an exact version; approve each tool call | Written rule | Settings `mcp__*` and `Edit(.mcp.json)` ask rules; checks 8 and 14; CODEOWNERS |
| Record any change made outside the repository | Written rule | People; governance evidence log |
| Known limits stated plainly in any security write-up | Written rule | People |

## 13. Bootstrap safeguards

**File:** `.claude/commands/bootstrap.md`. **Runs:** once, when the template becomes a project.
**Proven by:** `install` (which executes the steps).

| Control | Type | What it does |
| --- | --- | --- |
| Verify green before finishing | Check | Bootstrap must reach `GUARDRAILS PASSED.`; if it cannot, it stops and reports |
| No template leftovers | Check | Fails if any template-only file, or any unfilled `{{...}}` placeholder, remains |
| Existing `.npmrc` never loosened | Written rule | Bootstrap adds or tightens the policy lines and shows the result |
| Existing lockfile problems | Written rule | A lockfile that fails check 12 is reported and bootstrap stops; replacing a dependency is the user's decision |
| Stop for consent before the first commit | Written rule | Bootstrap describes what it would commit and waits |

---

## The template repository's own controls

These protect the template itself and its contributors. They are removed from a project at bootstrap.

| Control | Type | What it does |
| --- | --- | --- |
| Behaviour suite (`tests/run.sh`) | Check | Bootstraps throwaway projects and proves every control above both catches and allows |
| Completeness test | Check | Fails if a control in the code is missing from this page |
| shellcheck, actionlint (checksum-pinned), template integrity | Check | Scripts and workflows are valid; every template placeholder is in bootstrap's token table |
| Secret scan with no directory-wide allowlist | Scan | gitleaks over the full history, plus tests that the config still catches real keys |
| Sign-off (DCO) | Check | Every commit in a pull request must be signed off |
| Code owners and review | Policy | Changes reach `main` only through a reviewed pull request |
| The repo's own `.claude/settings.json` | Policy | Maintainer sessions get the bash guard (unfilled tokens treated as empty patterns), ask rules for commits, pushes, pull requests and edits under `.template/core/`, and bypass mode disabled |
| Private vulnerability reporting | Policy | Ways around a guardrail are reported privately (`SECURITY.md`) |
| House rules | Written rule | Every enforcement change needs a test that fails without it; never weaken a check to make it pass |
