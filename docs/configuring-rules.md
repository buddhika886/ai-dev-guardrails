# Configuring the rules

Every rule in this project lives in a plain text file you can read and change. This page goes through
them one by one: what each rule does, where it lives, and how to change it safely.

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
| `scripts/ci-guardrails.sh` | The eleven guardrail checks |
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
| `permissions.ask` | Always prompt for these commands, even if someone saved an "allow" for them |
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

**Built in.** Fails if the hooks or the `git commit`/`git push` ask rules are removed from
`.claude/settings.json`, or if any allow rule in either settings file would let a consent, deploy or
secret-printing command through without asking. `CONSENT_SAMPLES` lists the commands it tests
against; add one when you add a deploy tool to the guard.

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

## 5. Local hooks and CI

**`lefthook.yml`** decides what runs on your machine. Pre-commit runs the fast guardrails, the staged
secret scan and lint; pre-push runs typecheck, build and the full guardrails. Install once per clone
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

## 6. Tiers

| Tier | What it adds |
| --- | --- |
| Core | Everything on this page except check 11. Always installed. |
| Governance | `docs/governance/` (evidence log, decision record, phase briefs), a PR template, and check 11 |
| Security | Not built yet: a future `SECURITY.md` with threat model and control table |

Bootstrap removes itself when it finishes, so there is no command to add a tier later. To add
governance by hand: copy `.template/governance/` from the template repository (`EVIDENCE.md`,
`DECISIONS.md` and `briefs/` into `docs/governance/`, `pull_request_template.md` into `.github/`),
replace the project-name and date placeholders (the words in double curly braces), set `GOVERNANCE_ENABLED='on'`, add
the governance lines to `CLAUDE.md`, and run `npm run guardrails`.

## 7. Switching language or linter

The TypeScript setup uses Biome. To use ESLint and Prettier instead, see
`docs/eslint-escape-hatch.md`. The guardrails call lint through one glob and one command in
`lefthook.yml`, so you can swap the tool without touching the checks.
