# Configuring the rules

Every rule in this project lives in a plain text file you can read and change. This page goes through
them one by one: what each rule does, where it lives, and how to change it safely.

Why each rule exists is explained separately, in [why-these-rules.md](why-these-rules.md). Read
that before switching a rule off. The complete list of controls is in
[security-controls.md](security-controls.md).

`/bootstrap` filled in the project-specific values from your interview answers. You only need this
page when the project grows: a new deploy tool, a new secret, a new public setting.

## The one rule about changing rules

**Change the configuration, never weaken the check.** If a check fails, either the code is wrong or
the configuration no longer describes the project. Fix whichever it is. Editing a check's logic so it
passes defeats the point of having it, and the next person will trust a check that no longer works.

Every change to these files goes through a pull request and review, like any other code.

## Where everything lives

| File | What it controls |
| --- | --- |
| `CLAUDE.md` | The written rules the AI reads first |
| `scripts/claude-bash-guard.sh` | What the AI may run: block, ask or allow |
| `.claude/settings.json` | Claude Code's own permission rules and hook wiring |
| `scripts/ci-guardrails.sh` | The twelve guardrail checks |
| `.npmrc` | The dependency policy: release cooldown, registry-only packages, reviewed install scripts |
| `osv-scanner.toml` | Accepted vulnerability exceptions, each with an expiry date (only if you need one) |
| `.gitleaks.toml` | The secret scanner's rules |
| `lefthook.yml` | What runs on your machine on commit and push |
| `.github/workflows/ci.yml` | What runs on GitHub for every pull request |
| `.guardrails/denylist.local` | Your private list of client names (never committed) |
| `docs/governance/` | The governance records, if that tier is installed |

Most files have a block at the top marked `# ---- CONFIG ----`. That block holds the values meant to
change; the logic underneath is not.

## A note on patterns

Many settings are **extended regular expressions** (patterns). You only need three things:

- `|` means "or": `vercel|netlify` matches either word.
- `\.` matches a real dot. A bare `.` matches any character, so write `db\.prod\.example\.com`.
- `[[:space:]]+` matches one or more spaces: `wrangler[[:space:]]+deploy`.

Space-separated lists (such as `SECRET_VAR_NAMES`) are plain names, not patterns.

---

## 1. The AI command guard

**File:** `scripts/claude-bash-guard.sh`

Before the AI runs any shell command, this script reads it and answers in one of three ways.

| Answer | What happens | Used for |
| --- | --- | --- |
| Block | The command does not run; the AI is told why | Things the AI must never do |
| Ask | You get a prompt and must approve it | Anything that leaves your machine |
| Allow | Normal Claude Code permissions apply | Everything else |

### Settings filled by bootstrap (CONFIG block)

| Setting | What it does | Example |
| --- | --- | --- |
| `PROD_GUARD_PATTERNS` | Blocks any command matching these patterns (your production hosts, risky verbs) | `db\.prod\.acme\.com\|wrangler[[:space:]]+deploy` |
| `PROD_ENV_VAR_NAMES` | Blocks any command that mentions these variables, which carry production credentials | `PROD_DATABASE_URL DEPLOY_TOKEN` |
| `SECRET_VAR_NAMES` | Blocks echoing or printing these variables into the chat | `DATABASE_URL SESSION_SECRET` |

**Example: you moved production to a new database host.** Add it to `PROD_GUARD_PATTERNS`:

```bash
PROD_GUARD_PATTERNS='db\.prod\.acme\.com|db2\.prod\.acme\.com|wrangler[[:space:]]+deploy'
```

### Built-in lists (BUILT-IN block)

These work without configuration. You can **add** to them; do not remove entries.

| List | Answer | Covers |
| --- | --- | --- |
| `CONSENT_PATTERNS` | Ask | `git commit`, `git push`, PRs, releases, package publishing |
| `DEPLOY_PATTERNS` | Ask | Vercel, Netlify, Wrangler, Fly, Firebase, Railway, EAS, remote migrations |
| `REMOTE_CONFIG_PATTERNS` | Ask | Changing secrets or settings on GitHub or a hosting platform |
| `DEPENDENCY_PATTERNS` | Ask | Adding a package (`npm install <name>`, `pnpm add`, `yarn add`, `bun add`), `pnpm dlx`/`yarn dlx`/`bunx`, approving install scripts |
| `DEP_WEAKEN` | Block | Overriding the `.npmrc` policy for one command: `--min-release-age`, `--before`, `--registry`, `--allow-git`, `--dangerously-allow-all-scripts`, `npm config set` on those keys, `npm_config_*` variables |
| `SECRET_FILES`, `SECRET_READERS`, `SECRET_CLIS` | Block | Reading `.env` and key files, password-manager commands |

**Example: your team deploys with a tool called `shipit`.** Add a line to `DEPLOY_PATTERNS`:

```bash
DEPLOY_PATTERNS+="|${B}shipit[[:space:]]+(deploy|release)"
```

Then add a sample command to `CONSENT_SAMPLES` in `scripts/ci-guardrails.sh` (see check 8), so an
allow rule for it would also be caught.

**Ask or block?** Use ask for anything a person might reasonably want to do (deploy, publish). Use
block only for things that should never happen from this machine whoever approves (production from a
laptop, printing secrets). A needless prompt costs a second; an unintended deploy costs much more.

### Known limit

The guard reads command text. A command that reaches production indirectly, through a variable or a
script, may not be recognised. The real protection for production is the rule in `CLAUDE.md`: the AI
prepares production commands and a person runs them.

---

## 2. Claude Code permission rules

**File:** `.claude/settings.json`

| Section | What it does |
| --- | --- |
| `permissions.ask` | Always prompt for these commands, even if someone saved an "allow" for them. Also prompts before the AI edits `.npmrc` |
| `permissions.deny` | Stop Claude Code's file reader from opening these files (`.env`, keys, credentials) |
| `hooks` | Wires up the command guard and the end-of-turn check |

Claude Code checks deny rules first, then ask, then allow. That is why an "always allow" saved in
`.claude/settings.local.json` cannot silence an ask rule here.

**Example: stop the AI reading a new credentials file.** Add to `permissions.deny`:

```json
"Read(config/service-account.json)"
```

**Do not** add allow rules for commits, pushes or deploys. Check 8 fails if you do, in either
settings file.

---

## 3. The guardrail checks

**File:** `scripts/ci-guardrails.sh`

These run on every commit (fast mode), every push, and in CI. A check switched off by configuration
prints `SKIPPED (reason)`, never a tick, so nobody mistakes "not checked" for "passed".

### Check 1: no confidential files in git

**Setting:** `SECRET_FILE_PATTERNS` (files that must never be committed) and `ALLOWED_TRACKED`
(safe exceptions such as `.env.example`).

**Example: this repo must never contain CSV exports.** Add `|.*\.csv$` to `SECRET_FILE_PATTERNS`.

### Check 2: only approved settings reach the browser

**Settings:** `PUBLIC_VAR_PREFIX` (your framework's public prefix, such as `NEXT_PUBLIC_` or
`VITE_`), `PUBLIC_VAR_ALLOWLIST` (the public variables you have approved), `SECRET_VAR_NAMES`
(server secrets that must never appear in client code), `CLIENT_DIR` (where client code lives).

**Example: you want a new public variable `NEXT_PUBLIC_SUPPORT_EMAIL`.** Add it to
`PUBLIC_VAR_ALLOWLIST`. That one-line change, reviewed in a PR, is the record that someone decided
it is safe to make public. Leave `PUBLIC_VAR_PREFIX` empty to switch the check off.

### Check 3: database queries are parameterised

**Settings:** `UNSAFE_SQL` (patterns for raw-query escape hatches such as `.raw(` and `.unsafe(`)
and `SERVER_DIRS` (where server code lives, space-separated).

**Example: you added a `workers/` folder that talks to the database.** Add it to `SERVER_DIRS`:
`SERVER_DIRS='src/server workers'`.

### Check 4: no sensitive data in browser storage

**Setting:** `STORAGE_PATTERNS` (localStorage, sessionStorage, indexedDB, cookies), checked in
`CLIENT_DIR`.

### Check 5: migrations only ever get added

**Setting:** `MIGRATIONS_DIR`. A migration that has already run must never be edited or deleted;
add a new one instead. Leave empty if there is no database.

### Check 6: no secrets in the built app

**Settings:** `BUNDLE_DIR` (your build output, such as `out` or `dist`) and `BUNDLE_LEAK_PATTERNS`
(strings that must never ship to users). Leave `BUNDLE_DIR` empty to switch off.

### Check 7: the database structure matches the saved copy

**Settings:** `SCHEMA_DUMP_CMD` (a command that prints your schema) and `SCHEMA_DUMP_FILE` (the
committed copy). When you change the schema, add a migration and regenerate the committed copy in the
same change. Never hand-edit the copy to make the check pass.

### Check 8: the AI safety settings are intact

**Built in.** Parses `.claude/settings.json` (never a text search) and fails if any of these is
missing or changed: the two hooks, each wired in exec form through `${CLAUDE_PROJECT_DIR}` so it is
still found after the AI changes directory, with `"onFailure": "block"` on the command guard so a
hook that cannot start blocks the command instead of letting it run; every ask rule in
`REQUIRED_ASK_RULES` and every `Read` deny rule in `REQUIRED_DENY_RULES`; and
`permissions.disableBypassPermissionsMode: "disable"`, which stops a session being started in the
mode that skips every prompt. It also fails if either settings file sets `disableAllHooks` or a
default mode of `bypassPermissions`, or if any allow rule in either file would let a consent,
deploy, package-adding or secret-printing command through without asking (both the `git push *`
and the older `git push:*` spellings). A saved "always allow" for `npm install *` is caught here:
plain `npm install` and `npm ci` need no allow rule, because the guard only asks when a package
name is given. `CONSENT_SAMPLES` lists the commands it tests against; add one when you add a deploy
tool to the guard. When you add an ask or deny rule to `settings.json`, add it to the matching
`REQUIRED_*` list too, so removing it later is caught.

### Check 9: no client names in the code

**Files:** `.guardrails/denylist.local` on your machine (gitignored) and the `GUARDRAILS_DENYLIST`
repository secret on GitHub. One pattern per line; lines starting with `#` are comments.

```text
# Client names that must never be committed
Globex[[:space:]]+Holdings
globex\.com
```

When it finds a match it reports only the file and line, never the name, so the name does not end up
in logs. Never commit the denylist itself (the check fails if you do), and never paste its contents
into a chat.

### Check 10: local hooks are installed

**Built in.** Fails on your machine until `npx lefthook install` has run in this clone. Skipped in
CI, where it does not apply.

### Check 11: governance records are honest (governance tier only)

**Setting:** `GOVERNANCE_ENABLED` (`on` or `off`). When on, it checks `docs/governance/`:

- a phase marked **Done** must link to an evidence section containing real output or a link
- the state is one of Not started, In progress, Blocked, Done
- every deviation in `DECISIONS.md` has a Cost, an Exit and an Owner

It checks structure, not quality. Reviewers still judge whether the evidence proves the claim.

### Check 12: the dependency policy holds

**Settings:** `MIN_RELEASE_AGE_DAYS` (7), `NPM_MIN_VERSION` (11.10.0) and `ALLOWED_REGISTRIES`
(the public npm registry), in the BUILT-IN block. It checks three things, offline:

- **`.npmrc`** still sets `min-release-age` to at least 7 days, `allow-git=none`,
  `allow-remote=none` and `strict-allow-scripts=true`, sets no `before` date, does not run every
  install script, and points `registry` only at an allowed registry.
- **`package-lock.json`** exists, and every package in it comes from an allowed registry over https,
  has a sha512 integrity hash, and resolves to a tarball for the same package name.
- **npm** on this machine is 11.10 or later, since older npm ignores the cooldown without a word.

**Example: your company uses a private registry for `@acme` packages.** Add it to
`ALLOWED_REGISTRIES` and point the scope at it in `.npmrc`, in the same pull request:

```bash
ALLOWED_REGISTRIES='https://registry.npmjs.org/ https://npm.acme.internal/'
```

```ini
@acme:registry=https://npm.acme.internal/
```

### Adding a check of your own

Copy the shape of an existing check: a numbered heading, `ok` or `fail` for each result, and
`skipped` when configuration turns it off. If something inside the check goes wrong, it must fail,
never pass quietly. Add a test case that proves the check catches what it is for.

---

## 4. The secret scanner

**File:** `.gitleaks.toml`

gitleaks scans staged changes on every commit and the full history in CI. It starts from its large
default ruleset and adds rules for passwords inside connection strings and for OpenRouter keys.

**Example: your payment provider's keys start with `pk_live_`.** Add a rule:

```toml
[[rules]]
id = "payments-live-key"
description = "Payment provider live key"
regex = '''pk_live_[0-9a-zA-Z]{24,}'''
tags = ["payments"]
```

**False positive?** Add the narrowest possible entry to the `[allowlist]` (one exact value or one
file), with a comment saying why. Never allowlist a whole directory: a real key placed there would
become invisible.

---

## 5. Dependencies

A package you install is code from a stranger that runs with your project's permissions. The
protection comes in layers, all free and none needing an account.

| Protection | Where | What it stops |
| --- | --- | --- |
| 7-day release cooldown | `.npmrc` (`min-release-age`) | Hijacked releases (usually pulled within days) and made-up package names (almost always brand new) |
| Registry-only dependencies | `.npmrc` (`allow-git`, `allow-remote`) | Packages pulled straight from a git repo or a URL, past the registry's checks |
| Reviewed install scripts | `.npmrc` (`strict-allow-scripts`), approvals in `package.json` | A dependency running code on `npm install` that nobody approved |
| Ask before adding a package | Command guard | The AI adding a package, or a misspelt one, without you seeing it |
| Lockfile integrity | Check 12 | A lockfile edited to fetch from elsewhere or swap one package for another |
| Known vulnerabilities | CI `dependencies` job and pre-push (OSV-Scanner) | Packages with published security advisories |
| Registry signatures | CI `verify` job (`npm audit signatures`) | Packages altered after the registry signed them |
| Updates and alerts | Dependabot (`.github/dependabot.yml` and repository settings) | Falling behind on fixes |

**Approving an install script.** When an install fails because a dependency has an install script,
decide whether it needs one (native modules such as `esbuild` or `sharp` do), then approve it by
name with `npm approve-scripts <pkg>`. The approval is stored in `package.json`, so it is reviewed
with the rest of the change.

**An urgent fix that is newer than 7 days.** Add the package to `min-release-age-exclude` in
`.npmrc`, in a reviewed pull request, and remove the entry once the release is a week old. The
cooldown applies when npm chooses versions (`npm install`, `npm update`); `npm ci` installs the
reviewed lockfile as it is, so a Dependabot security update still passes CI.

**A vulnerability you cannot fix yet.** OSV-Scanner fails CI on any known vulnerability. If there is
no fixed version, or the vulnerable code is not reachable, record the exception in
`osv-scanner.toml` at the repository root, with an expiry date and the reason:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2026-12-31
reason = "Only the CLI uses this package, never on user input. Upgrade when 4.2 ships."
```

When the date passes, the exception stops applying and CI goes red again, so nobody has to remember
to revisit it.

**Bumping OSV-Scanner.** The version and its sha256 are pinned in `.github/workflows/ci.yml`, the
same way as gitleaks. Take the checksum for `osv-scanner_linux_amd64` from the release's
`osv-scanner_SHA256SUMS` file.

**pnpm, yarn or bun?** The template is set up for npm. The others have equivalents, but check 12
and the guard's blocks do not read them:

- **pnpm** (`pnpm-workspace.yaml`): `minimumReleaseAge: 10080` (minutes), `strictDepBuilds: true`
  with `allowBuilds` for approved packages, `blockExoticSubdeps: true`, `trustPolicy: no-downgrade`.
- **yarn 4.10+** (`.yarnrc.yml`): `npmMinimalAgeGate`. Check the unit for your yarn version.
- **bun**: see bun's documentation for its equivalent settings.

### If you already have an account

These tools need an account, an API key or a paid plan, so they are not switched on by default. If
your team already has one, they add to the layers above rather than replace them:

| Tool | What it adds | Where it goes |
| --- | --- | --- |
| [Snyk](https://snyk.io) | Vulnerability and licence scanning with fix advice; free tier limits monthly tests | A CI step with `SNYK_TOKEN` as a repository secret |
| [Socket](https://socket.dev) GitHub app or CLI | Behaviour analysis that flags malware and risky packages in pull requests | Install the GitHub app, or a CI step with `SOCKET_SECURITY_API_KEY` |
| [OWASP Dependency-Check](https://owasp.org/www-project-dependency-check/) | CVE matching across many ecosystems, with HTML reports | A CI step; needs an NVD API key in practice, and expect false positives to tune |
| [GitHub dependency review](https://github.com/actions/dependency-review-action) | Fails a pull request that adds a vulnerable or disallowed-licence package | A CI step; free on public repositories, needs GitHub Code Security on private ones |
| [StepSecurity Harden-Runner](https://github.com/step-security/harden-runner) | Watches and blocks unexpected network traffic from CI jobs | First step of each CI job; free on public repositories |

Free install-time firewalls such as Socket Firewall Free (`sfw`) and Aikido Safe Chain block known
malware as it is installed. They need no account, but check their licences (PolyForm Shield and
AGPL-3.0) suit your organisation before adopting them.

Add any of these as an extra CI job or step. Pin each Action to a full commit SHA, as the rest of
the workflow does, and keep secrets in repository secrets, never in the workflow file.

---

## 6. Local hooks and CI

**`lefthook.yml`** decides what runs on your machine. Pre-commit runs the fast guardrails, the staged
secret scan and lint; pre-push runs typecheck, build, the full guardrails and, if OSV-Scanner is
installed, the dependency scan. Install once per clone
with `npx lefthook install`.

**`.github/workflows/ci.yml`** runs the same checks on a clean machine for every pull request. It is
the final word. Protect `main` on GitHub so these jobs must pass, at least one review is required,
and force-push is disabled.

GitHub Actions are pinned to exact commit SHAs, and `.github/dependabot.yml` proposes updates as pull
requests. Review those like any other change.

**Dependabot needs switching on.** The `dependabot.yml` file schedules version updates, but
**Dependabot alerts** (known vulnerabilities in your dependencies) and **Dependabot security updates**
(automatic fix pull requests) are repository settings. Enable both in **Settings → Code security**.
The project README's "One-time GitHub setup" section lists these with the other repository settings
(secret scanning, branch protection, read-only CI token).

---

## 7. Tiers

| Tier | What it adds |
| --- | --- |
| Core | Everything on this page except check 11. Always installed. |
| Governance | `docs/governance/` (evidence log, decision record, phase briefs), a PR template, and check 11 |
| Security | Not built yet: a future `SECURITY.md` with threat model and control table |

The governance tier is for client work, regulated work, or anything that will be audited or handed
over. It adds:

- **An evidence log** (`docs/governance/EVIDENCE.md`): a table of phases, each with an observable
  "done when", and the actual proof (test output, CI links) behind every finished phase. Bootstrap
  writes the first entry itself, from the checks it just ran.
- **A decision record** (`docs/governance/DECISIONS.md`): settled decisions and why; known
  exceptions, each with what it costs, when it ends and who owns it; and open questions.
- **Phase briefs** (`docs/governance/briefs/`): a short plan per phase, so the AI works from a
  written brief, not a half-remembered conversation.
- **A pull request template** that asks for evidence.

Check 11 keeps it honest: a phase cannot be marked Done without proof attached, and an exception
cannot be recorded without a cost, an end and an owner.

Bootstrap removes itself when it finishes, so there is no command to add a tier later. To add
governance by hand: copy `.template/governance/` from the template repository (`EVIDENCE.md`,
`DECISIONS.md` and `briefs/` into `docs/governance/`, `pull_request_template.md` into `.github/`),
replace the project-name and date placeholders (the words in double curly braces), set `GOVERNANCE_ENABLED='on'`, add
the governance lines to `CLAUDE.md`, and run `npm run guardrails`.

## 8. Switching language or linter

The TypeScript setup uses Biome. To use ESLint and Prettier instead, see
`docs/eslint-escape-hatch.md`. The guardrails call lint through one glob and one command in
`lefthook.yml`, so you can swap the tool without touching the checks.
