---
description: Bootstrap this guardrails template into a real project (interview, fill, verify, self-rewrite).
---

# /bootstrap

You are turning this template into a working project. Follow these steps in order. Do not improvise
around the enforcement files' content: you fill CONFIG values and copy files, you never rewrite a
check to make it pass. If any step errors, STOP, report exactly what failed, and wait.

## Step 1: Where are we? (do this first, before anything else)

Run these checks in order and act on the first that applies. Do not run anything else yet.

1. **Already bootstrapped.** If `.template/` does **not** exist, this repo is already a project. Say
   so, point the user at `docs/five-layers.md` and `docs/configuring-rules.md`, and STOP.
2. **No git repository.** If `git rev-parse --git-dir` fails, the kit was downloaded as a ZIP. Say:
   "This folder is not a git repository yet (the kit was downloaded rather than cloned). The
   guardrails need one. Shall I run `git init -b main`?" Wait. If yes, run it and continue; if no,
   STOP.
3. **A direct clone of the kit.** If `git remote get-url origin` names `ai-dev-guardrails`, this is
   a clone of the template rather than a repository made from it. Say: "This is a clone of the
   kit itself, so `origin` points at the kit's repository and your first push would go to the
   wrong place. Shall I remove the `origin` remote? You add your own repository as `origin` when
   you are ready to push. (Using GitHub's **Use this template** button avoids this and gives a
   clean history.)" Wait. If yes, run `git remote remove origin`; either way, continue.
4. Otherwise continue.

## Step 2: The offer (say exactly this, then WAIT)

Print these lines verbatim and then stop and wait for the user's reply. Do not run anything yet.

> This repo is the ai-dev-guardrails template. I can bootstrap it into your project. I'll walk you
> through a short set of questions, one at a time, each with a recommended answer if you are
> unsure; then I'll fill in all the guardrails, verify they pass, and stop for your consent before
> committing anything.
> Shall I start? This edits files in place and deletes `.template/` at the end; nothing is committed
> or pushed without your explicit go-ahead.

Only continue once the user consents. If they decline, STOP.

## Step 3: The guided interview

**How to run it.** Ask every question below with the `AskUserQuestion` tool, one question per call,
in exactly this order. Each call carries the question text (the question and the one-line "why"),
the options with their descriptions (the examples), and `multiSelect` where marked. Never present
the questions as a list to answer in one go, never skip, merge, reorder or add a question, and
never guess an answer. If the user volunteers answers to later questions, record them, but still
present each remaining question (with the volunteered answer as the first option) so nothing is
assumed. If `AskUserQuestion` is not available in this session, ask the same questions one at a
time in text, with the options numbered, and wait for each answer.

The first option of every question is a safe default. A user who picks the first option every time
ends up with a working, safe project; that is the design, not an accident. Every option list ends
with an "Other" that the tool adds itself, so free text (a path, a name) always has a way in.

Before the first question, run `basename "$PWD"` and `gh api user -q .login 2>/dev/null || true`
so the defaults below can be filled in. Read `.template/lang/ts/fragment.md` for the prefix and
bundle table.

### Basics

**B1. Project name.** "What is the project called? This names the README and the rules file."
- `<directory name>` (recommended): the folder you are in
- Other: type a name

**B2. Spelling.** "Which spelling should the written rules and docs use?"
- British English (recommended): organisation, optimise
- US English: organization, optimize

### Q1. Stack

**Q1a. Framework.** "What is the project built with? Only TypeScript is supported in this release;
Python and React Native come later. The framework decides which settings are allowed to reach the
browser and where the built app lands."
- Next.js: `NEXT_PUBLIC_` settings reach the browser
- Vite-based (React, SvelteKit): `VITE_` settings reach the browser; built app in `dist`
- Astro or Remix: I'll ask which next
- Plain TypeScript, a library, or nothing yet (recommended if unsure): no browser settings check;
  you can add one later

If the user answers Python or React Native through Other, say: "Those language fragments arrive in
the next template release. I can bootstrap a TypeScript-only project now, or stop and wait for that
release." Then do only what the user chooses.

**Q1b. Only if Next.js.** "How is it built? This decides where the kit scans for secrets that
should never ship."
- Static export (recommended if unsure): built files land in `out`, and the kit scans them
- Server-rendered: there is no static output to scan

**Q1c. Only if Astro or Remix.**
- Astro: `PUBLIC_` settings reach the browser; built app in `dist`
- Remix: no public prefix; built app in `build/client`

Derive `{{PUBLIC_VAR_PREFIX}}` and `{{BUNDLE_DIR}}` from the fragment table.

### Q2. Repo shape

**Q2a. Layout.** "Is this one package or several? The kit needs to know where browser code and
server code live, because different rules apply to each."
- Single package (recommended if unsure): one `package.json` at the root
- Monorepo: several packages; type the package paths, for example `apps/web packages/api`

**Q2b. Browser code.** "Which folder holds the code that runs in the browser? The kit checks that
no secrets and no browser storage end up there." Options: the framework's usual folder first
(`src/app src/components` for Next.js, `src` for Vite and Astro, `app` for Remix), then
`src/client`, then Other.

**Q2c. Server code.** "Which folders hold code that runs on the server or at the edge? The kit
checks that database queries there are written safely." Options: the framework's usual folder first
(`src/server` for Next.js, `src/server` for Vite, `src/pages/api` for Astro, `app/routes` for
Remix), then `server`, then Other (space-separated paths).

**Q2d. Database migrations.** "Where do database migrations live? The kit stops an old migration
from being edited, which would make databases drift apart."
- No database (recommended if unsure): the migration check is switched off and says so
- `prisma/migrations`
- `db/migrations`

### Q3. Data

**Q3a. Sensitivity.** "Will the project handle personal or regulated data, such as names, emails,
payments or health records? This switches on the stricter security rules and records the choice
for audits."
- No: the security tier stays dormant; it can be added later
- Yes: the security tier is armed (its files arrive in a later release; the choice is recorded)

**Q3b. Only if Q3a is yes and Q2d named a migrations folder.** "What command prints the database
schema, and where should the committed copy live? The kit compares the two so a change made by
hand shows up in review."
- Skip for now (recommended if unsure): the schema check is switched off and says so
- Prisma: `npx prisma migrate diff --from-empty --to-schema-datamodel prisma/schema.prisma --script`, saved to `db/schema.sql`
- Other: type the command and the file path

### Q4. Production

**Q4a. Production.** "Is there a live production system yet? The kit blocks the AI from touching
it from your computer, and asks before every deploy either way."
- None yet (recommended if unsure): deploys still ask; add the host later in
  `scripts/claude-bash-guard.sh`
- Yes, describe it: type the production host or connection (for example `db.prod.example.com`),
  how production changes are meant to happen (for example "deploys run from GitHub only"), and the
  names of any settings that point at production (for example `PROD_DATABASE_URL`)

**Q4b. Secret settings.** "Which settings must never be shown? The kit blocks the AI from printing
these into the chat and checks they never reach browser code or the built app. Anything named with
SECRET, TOKEN, PASSWORD, API_KEY or CREDENTIALS is already covered; name the others."
- None beyond the usual names (recommended if unsure): the built-in patterns cover you; add names
  later in `docs/configuring-rules.md`
- Typical set: `DATABASE_URL SESSION_SECRET STRIPE_SECRET_KEY`
- Other: type the names, separated by spaces

**Q4c. Public setting.** Only if Q1 gave a public prefix. "Which setting is allowed to be public?
Anything starting with `<prefix>` is sent to every visitor's browser, so the kit only allows the
ones you name."
- None yet (recommended if unsure): the kit fails if any public setting appears, until you add it
- `<prefix>APP_URL`: the site's own address, the usual first one
- Other: type the names, separated by spaces

### Q5. Tiers

**Q5. Extras** (`multiSelect`). "Which records do you want alongside the code? Choose any; none is
fine."
- Governance records (recommended for client, regulated or audited work): an evidence log where
  "done" needs proof, a decision record where every exception has a cost, an end date and an owner,
  phase briefs, and a pull request template
- Security tier: switched on already if you said yes to personal data; choosing it here records the
  choice (its files arrive in a later release)
- Core only: just the guardrails

### Ownership and licence

**O1. Source documents.** "Are there documents the AI should treat as the source of truth, such as
a spec, a PRD or a runbook? They are linked from the rules file so the AI reads them first."
- None yet (recommended if unsure): the rules file says so; add links later
- Other: type paths or links

**O2. Guardrail owners.** "Who must review any change to the safety rules? This is written into
`.github/CODEOWNERS`, so no one can weaken a guardrail without their approval."
- `@<handle from gh>` (recommended): you
- Other: a GitHub handle or team, for example `@acme/platform`

**O3. Licence.** "Should the code carry an open-source licence? For client or internal work, no
licence file is the safe default: the code stays all rights reserved."
- No licence file (recommended for client and internal work)
- MIT: open source; type the copyright holder, for example "Jane Doe and contributors"

The template's own `LICENSE` names the template's author, so it is never kept as it is.

### Confirm

Show every answer in one table (question, answer, and the token or file it fills), then ask one
last question with `AskUserQuestion`: "Install the guardrails with these answers?"
- Install now
- Change an answer: ask which, re-ask that one question, show the table again
- Stop: nothing has been changed yet

Only continue to Step 4 on "Install now".

## Step 4: Install algorithm (conservative, step by step)

Do these in order. Show the user what you are doing at each step.

0. **Clear the template's own files.** These belong to the template repo, not to the user's project,
   and must not survive into it. Remove each one that exists:
   - `README.md` (Step 5 writes the project's own), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
     `SECURITY.md`
   - `tests/` (the template's behaviour suite) and `scripts/template-integrity.sh`
   - `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`,
     `.github/dependabot.yml`, `.github/workflows/ci.yml` (Step 1 copies the project's own versions
     of the last two; Step 2a copies a PR template if governance is on)
   - in `.gitignore`, the template-only entries `DEVLOG.md` and `PROJECT-GUIDE.md` and the comment
     lines directly above each
   `LICENSE` is handled in Step 5. Keep `docs/five-layers.md`, `docs/configuring-rules.md`,
   `docs/why-these-rules.md`, `docs/security-controls.md`, `docs/choosing-a-model.md`, `scripts/claude-profile.sh`, `scripts/claude-or.sh`
   and the `.claude/profiles/*.settings.json.example` files: they are project documentation and an
   optional developer tool (running Claude Code with another provider or model), shipped on purpose.
1. **Copy core.** Copy every file from `.template/core/` to its destination:
   - `.template/core/CLAUDE.project.md` → hold for Step 5 (do not place yet).
   - `.template/core/lefthook.yml` → `lefthook.yml`
   - `.template/core/.gitleaks.toml` → `.gitleaks.toml`
   - `.template/core/ci/verify.yml` → `.github/workflows/ci.yml`
   - `.template/core/scripts/*.sh` → `scripts/`
   - `.template/core/settings.json` → `.claude/settings.json`
   - `.template/core/dependabot.yml` → `.github/dependabot.yml`
   - `.template/core/CODEOWNERS` → `.github/CODEOWNERS` (the project's own, naming the enforcement
     files; the template's was removed in step 0)
   - `.template/core/README.project.md` → hold for Step 5 (do not place yet).
   - Make sure `.gitignore` contains `.guardrails/*.local`, `.claude/settings.local.json`,
     `.claude/profiles/*.settings.json` and `.claude/openrouter.settings.json` (append any that are
     missing; create `.gitignore` if there is none). The first keeps the client denylist out of git;
     the second keeps per-machine permission approvals out of the shared repo; the last two keep a
     developer's model-provider keys out (the fourth is the OpenRouter profile's old location).
2. **Copy the language fragment** (TypeScript): `biome.json`, `.nvmrc`, `.npmrc` to the repo root;
   `eslint-escape-hatch.md` and `tsconfig-note.md` → `docs/`. Merge `package-scripts.json`'s
   `scripts` block into `package.json` (create a minimal `package.json` first if none exists). Leave
   the `build` placeholder for the user to fill and tell them so. Do not copy `fragment.md` itself:
   it is bootstrap's own lookup table, not project documentation.
   - If the project already has an `.npmrc`, merge: keep its other lines and add or tighten the four
     policy lines; never loosen one. Show the user the result.
   - If there is no `package-lock.json`, create it with `npm install --package-lock-only
     --ignore-scripts`. Check [12] needs one, and CI's `npm ci` refuses to run without it.
   - If an existing lockfile fails check [12] in Step 6 (a git or URL dependency, a missing hash),
     report the entries to the user and stop: replacing a dependency is their decision, not
     bootstrap's.
2a. **Copy the governance tier** (only if governance is on):
   - `.template/governance/EVIDENCE.md` → `docs/governance/EVIDENCE.md`
   - `.template/governance/DECISIONS.md` → `docs/governance/DECISIONS.md`
   - `.template/governance/briefs/BRIEF-TEMPLATE.md` → `docs/governance/briefs/BRIEF-TEMPLATE.md`
   - `.template/governance/pull_request_template.md` → `.github/pull_request_template.md`
3. **Fill every token.** Replace each `{{ ... }}` placeholder in the copied files with the value from the
   interview, per the **token table** below. This table is the contract: every token in any template
   file appears here, and nothing here is absent from the templates (the repo's own CI enforces this
   with `scripts/template-integrity.sh`). Leave a value empty only where the table and the check
   allow it (e.g. `{{PROD_GUARD_PATTERNS}}` when there is no production yet, `{{SCHEMA_DUMP_CMD}}`
   when there is no database).
   - **Default for `{{SECRET_FILE_PATTERNS}}`**, extended (never shortened) from Q3:
     `.*\.env$|.*\.env\..*|.*\.dev\.vars$|.*\.pem$|.*\.key$|.*\.p12$|.*\.pfx$|.*\.jks$|.*\.keystore$|.*\.ppk$|(^|/)id_(rsa|dsa|ecdsa|ed25519)$|.*credentials.*\.json$|.*service-account.*\.json$|.*\.local$`
     The last shape catches `.guardrails/denylist.local` if it is ever force-added.
4. **Apply tier conditionals.** For each line tagged `{{IF_SECURITY_TIER}}` or
   `{{IF_GOVERNANCE_TIER}}` in `CLAUDE.project.md` and `README.project.md`: if the tier is on, strip the tag prefix and keep
   the line; if off, delete the whole line.
   - **Do not leave a dangling pointer.** The security tier ships only a placeholder, so a kept
     security line would point at a file that does not exist. When security is on, keep its lines
     and append ` (arrives in template release T2; not present yet)` to each. Governance lines need
     no annotation: Step 2a installed the files they point at. That
     records the choice without pretending the file is there. Nothing is copied to `.claude/agents/`
     in T1 either: leave that directory absent.
5. **Install hooks.** Run `npx lefthook install`. Guardrail check [10] fails until this has run, so a
   fresh clone without local hooks is visible rather than silent.
6. **Verify green.** Run `bash scripts/ci-guardrails.sh` and show the full output. It MUST print
   `GUARDRAILS PASSED.` before you go on. Check [9] reports SKIPPED until a client denylist exists;
   that is expected.
7. **Record Phase 0** (only if governance is on). The evidence log's first entry is the run you
   just made. In `docs/governance/EVIDENCE.md`, replace the line
   `<!-- bootstrap: guardrails output goes here -->` with the full output of Step 6 inside a fenced
   code block, and change Phase 0's State from `In progress` to `Done`. Then run
   `bash scripts/ci-guardrails.sh` again: it must still print `GUARDRAILS PASSED.`, which proves
   check [11] accepts the record. Paste the output exactly; never summarise it. If it fails, fix the **configuration** (a token value, a
   directory path) or the code (never the checks) and re-run until green. If you cannot get it
   green, STOP and report.

### Token table (the contract)

Every token below exists in the template files; the source is the interview answer (or derivation)
that fills it. Empty-allowed tokens are marked.

| Token                     | Source question / derivation                                             | Empty allowed |
| ------------------------- | ------------------------------------------------------------------------ | ------------- |
| `{{PROJECT_NAME}}`        | B1                                                                       | no            |
| `{{LANGUAGE_SPELLING}}`   | B2                                                                       | no            |
| `{{SOURCE_OF_TRUTH_DOCS}}`| O1                                                                       | no            |
| `{{LOCAL_TOOLCHAIN}}`     | Q1a stack (e.g. "Node 24 + npm")                                         | no            |
| `{{LANG_LINT_GLOB}}`      | Q1 → `fragment.md` token values                                          | no            |
| `{{LANG_LINT_CMD}}`       | Q1 → `fragment.md` token values                                          | no            |
| `{{UNSAFE_SQL}}`          | Q1 → `fragment.md` default                                               | no            |
| `{{STORAGE_PATTERNS}}`    | Q1 → `fragment.md` default                                               | no            |
| `{{PUBLIC_VAR_PREFIX}}`   | Q1 framework → `fragment.md` prefix table                                | yes (no prefix) |
| `{{BUNDLE_DIR}}`          | Q1 framework → `fragment.md` prefix/bundle table                         | yes (SSR/none) |
| `{{CLIENT_DIR}}`          | Q2 repo shape (client code dir)                                          | no            |
| `{{SERVER_DIRS}}`         | Q2 repo shape (server/edge dirs, space-separated)                        | no            |
| `{{MIGRATIONS_DIR}}`      | Q2 repo shape / Q3 (migrations folder)                                   | yes (no DB)   |
| `{{SECRET_FILE_PATTERNS}}`| Q3 data + defaults (`.csv` left out; noisy)                              | no            |
| `{{ALLOWED_TRACKED}}`     | Derived default (`.env.example`, `.dev.vars.example`)                    | no            |
| `{{SECRET_FILES}}`        | Q1/Q3a (gitignored secret files, for CLAUDE.md prose; default `.env`)    | no            |
| `{{PUBLIC_VAR}}`          | Q4c (the legitimately public variable, or "(none yet)")                   | no            |
| `{{PUBLIC_VAR_ALLOWLIST}}`| Q4c (allowlisted public var names, space-separated)                      | yes           |
| `{{SECRET_VAR_NAMES}}`    | Q4b (extra secret names, space-separated; may be empty: shape patterns still apply) | no            |
| `{{BUNDLE_LEAK_PATTERNS}}`| Q4b names joined with `\|`, plus the default shapes `sk_live_\|sk-or-v1-\|AKIA[0-9A-Z]{16}\|BEGIN [A-Z ]*PRIVATE KEY` | no            |
| `{{SCHEMA_DUMP_CMD}}`     | Q3 (command that prints the schema)                                      | yes (no DB)   |
| `{{SCHEMA_DUMP_FILE}}`    | Q3 (committed dump path)                                                 | yes (no DB)   |
| `{{PROD_HOST}}`           | Q4 (prod host / connection)                                              | no*           |
| `{{PROD_APPROVED_PATH}}`  | Q4 (approved path for prod changes)                                      | no*           |
| `{{PROD_GUARD_PATTERNS}}` | Q4 (host/verb patterns for the bash guard)                               | yes ("none yet") |
| `{{PROD_ENV_VAR_NAMES}}`  | Q4 (prod-bearing env-var names)                                          | yes ("none yet") |
| `{{GOVERNANCE_ENABLED}}`  | Q5 (tier): `on` if governance is selected, otherwise `off`               | no            |
| `{{CODEOWNERS}}`          | O2 (GitHub handle or team, for `.github/CODEOWNERS`)                     | no            |
| `{{BOOTSTRAP_DATE}}`      | Today's date, ISO (YYYY-MM-DD), for the governance records               | no            |
| `{{IF_SECURITY_TIER}}`    | Q3 (data) and/or Q5 (tier): line kept if on, dropped if off              | line marker   |
| `{{IF_GOVERNANCE_TIER}}`  | Q5 (tier): line kept if on, dropped if off                               | line marker   |

\* When the user answers "none yet" for production, set `{{PROD_HOST}}` to a placeholder like
"(no production yet)" and `{{PROD_APPROVED_PATH}}` to "(to be defined)", and leave the pattern tokens
empty. Prod safety by process still applies.

## Step 5: Self-rewrite

1. Place the filled `CLAUDE.project.md` content as the new `CLAUDE.md` (replace the bootstrap-mode
   one entirely).
2. Place the filled `README.project.md` content as the new `README.md`. Tell the user to add their
   own project description at the top, where the file says so.
3. **Licence**, per the O3 answer: for **no licence file**, delete `LICENSE`; for **MIT**,
   replace the copyright line in `LICENSE` with `Copyright (c) <current year> <holder>` and keep
   the rest of the text unchanged.
4. Delete `.template/` and `.claude/commands/bootstrap.md` (this command; it has done its job).
5. **Check nothing of the template is left.** None of these may exist: `.template/`, `tests/`,
   `scripts/template-integrity.sh`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
   `.github/ISSUE_TEMPLATE/`, `.claude/commands/bootstrap.md`; `README.md` must not be the
   template's own (first line exactly `# ai-dev-guardrails`); and `.github/CODEOWNERS` must be the
   project's own (it names `/scripts/ci-guardrails.sh` and never `/.template/`). If any check fails,
   STOP and report it.
6. `git add -A`.
7. **STOP and ask for consent to commit.** Show the user exactly what would be committed (the file
   list). Never commit or push without a fresh, explicit go-ahead. This holds even here. Do not run
   `git commit` until they say yes.
8. **Tell the user about the one-time GitHub setup.** If the project is on GitHub, point the user to
   the "One-time GitHub setup" section of the new `README.md`: Dependabot alerts and security
   updates, secret scanning with push protection, a ruleset protecting `main` that requires review
   from code owners, and a read-only CI token. These are repository settings, so bootstrap cannot switch them on.
9. **Tell the user about the client denylist.** If the project is for a client, the user should
   create `.guardrails/denylist.local` themselves, one extended regex per line for each identifier
   that must never be committed (the client's legal name, for example), and set the same lines as
   the `GUARDRAILS_DENYLIST` repository secret for CI. Do not ask them to type the names into the
   chat: the transcript is stored, and the list exists to keep those names out of stored text.

## Step 6: Failure discipline

Any step that errors → stop, report the exact error, and do not work around it by editing an
enforcement file's logic. Configuration is yours to change; the checks are not. If the guardrails
will not go green because a check is genuinely wrong for this project, say so and let the human
decide. Do not silently weaken it.
