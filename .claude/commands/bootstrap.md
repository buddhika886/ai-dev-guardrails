---
description: Bootstrap this guardrails template into a real project (interview, fill, verify, self-rewrite).
---

# /bootstrap

You are turning this template into a working project. Follow these steps in order. Do not improvise
around the enforcement files' content: you fill CONFIG values and copy files, you never rewrite a
check to make it pass. If any step errors, STOP, report exactly what failed, and wait.

## Step 1: Idempotency check (do this first, before anything else)

If `.template/` does **not** exist, this repo is already bootstrapped. Say so, point the user at
`docs/five-layers.md` and `docs/configuring-rules.md`, and STOP. Do not proceed.

If `.template/` exists, continue.

## Step 2: The offer (say exactly this, then WAIT)

Print these two lines verbatim and then stop and wait for the user's reply. Do not run anything yet.

> This repo is the ai-dev-guardrails template. I can bootstrap it into your project: I'll ask five
> short questions, fill in all the guardrails, verify they pass, then stop for your consent before
> committing anything.
> Shall I start? This edits files in place and deletes `.template/` at the end; nothing is committed
> or pushed without your explicit go-ahead.

Only continue once the user consents. If they decline, STOP.

## Step 3: The five-question interview

Ask these five questions. Ask them one at a time or as a group, but collect all five answers before
installing. Also confirm the **project name** (default: this directory's name) at the same time.

1. **Stack.** What language and framework? (e.g. TypeScript + Next.js, TypeScript + Vite.)
   - For T1, only **TypeScript** is supported. If the answer is **Python** or **React Native**, say:
     "Those language fragments arrive in the next template release. I can bootstrap a TypeScript-only
     project now, or stop and wait for that release." Then do only what the user chooses.
   - From the framework, read `{{PUBLIC_VAR_PREFIX}}` and `{{BUNDLE_DIR}}` off the table in
     `.template/lang/ts/fragment.md`. Present that table if the framework is unclear or "none yet".
2. **Repo shape.** Single package or monorepo? If monorepo, what are the package paths? Which
   directories hold client code and which hold server/edge code? Where do database migrations live
   (or none)?
3. **Data sensitivity.** Does the project handle personal or regulated data (PII, financial, health)?
   - **Yes** → arm the security tier (`{{IF_SECURITY_TIER}}` lines are kept) and ask for the schema
     dump command and dump file if there is a database.
   - **No** → leave the security tier dormant (`{{IF_SECURITY_TIER}}` lines dropped); it can be added
     later.
4. **Production.** What is the production host / connection, the approved path for prod changes, and
   the names of env vars that carry prod credentials or targets? If there is no production yet,
   answer **"none yet"** and the prod patterns are left empty (the guard still blocks force-push,
   destructive git and secret disclosure, still asks before every commit, push and deploy, and
   prepare-versus-execute still applies).
5. **Tiers.** Which tiers beyond core? Security (auto-armed by Q3, or force on), governance, or
   core-only.
   - **Governance** is built: an evidence log, a decision record (settled decisions, deviations,
     open questions), phase briefs and a PR template, kept honest by guardrail check [11]. Recommend
     it for client work, regulated work, or anything that will be audited or handed over.
   - **Security** ships only its placeholder for now, so selecting it keeps its `CLAUDE.md` pointers
     and records the choice; the tier files arrive in a later release.

Also capture the **source-of-truth documents** the project's CLAUDE.md should point at (PRD, runbook,
spec), the **language/spelling** convention (default: British English), and the **licence**:

- **No licence file** (recommended for client and internal work): the code stays all rights
  reserved, which is the right default for anything not being open-sourced.
- **MIT**, with the name of the copyright holder (a person, a company, or "<name> and
  contributors").

The template's own `LICENSE` names the template's author, so it is never kept as it is.

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
| `{{PROJECT_NAME}}`        | Directory name, confirmed at Step 3                                      | no            |
| `{{LANGUAGE_SPELLING}}`   | Step 3 convention (default British English)                              | no            |
| `{{SOURCE_OF_TRUTH_DOCS}}`| Step 3 source-of-truth docs list                                         | no            |
| `{{LOCAL_TOOLCHAIN}}`     | Q1 stack (e.g. "Node 24 + npm")                                          | no            |
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
| `{{SECRET_FILES}}`        | Q1/Q3 (gitignored secret files, for CLAUDE.md prose)                     | no            |
| `{{PUBLIC_VAR}}`          | Q1/Q4 (the one legitimately public variable)                             | no            |
| `{{PUBLIC_VAR_ALLOWLIST}}`| Q1/Q4 (allowlisted public var names, space-separated)                    | yes           |
| `{{SECRET_VAR_NAMES}}`    | Q4 (server secret env-var names, space-separated)                        | no            |
| `{{BUNDLE_LEAK_PATTERNS}}`| Q4/Q3 (secret-like strings that must not ship)                           | no            |
| `{{SCHEMA_DUMP_CMD}}`     | Q3 (command that prints the schema)                                      | yes (no DB)   |
| `{{SCHEMA_DUMP_FILE}}`    | Q3 (committed dump path)                                                 | yes (no DB)   |
| `{{PROD_HOST}}`           | Q4 (prod host / connection)                                              | no*           |
| `{{PROD_APPROVED_PATH}}`  | Q4 (approved path for prod changes)                                      | no*           |
| `{{PROD_GUARD_PATTERNS}}` | Q4 (host/verb patterns for the bash guard)                               | yes ("none yet") |
| `{{PROD_ENV_VAR_NAMES}}`  | Q4 (prod-bearing env-var names)                                          | yes ("none yet") |
| `{{GOVERNANCE_ENABLED}}`  | Q5 (tier): `on` if governance is selected, otherwise `off`               | no            |
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
3. **Licence**, per the Step 3 answer: for **no licence file**, delete `LICENSE`; for **MIT**,
   replace the copyright line in `LICENSE` with `Copyright (c) <current year> <holder>` and keep
   the rest of the text unchanged.
4. Delete `.template/` and `.claude/commands/bootstrap.md` (this command; it has done its job).
5. **Check nothing of the template is left.** None of these may exist: `.template/`, `tests/`,
   `scripts/template-integrity.sh`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
   `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/`, `.claude/commands/bootstrap.md`; and
   `README.md` must not be the template's own (first line exactly `# ai-dev-guardrails`). If any check fails, STOP and
   report it.
6. `git add -A`.
7. **STOP and ask for consent to commit.** Show the user exactly what would be committed (the file
   list). Never commit or push without a fresh, explicit go-ahead. This holds even here. Do not run
   `git commit` until they say yes.
8. **Tell the user about the one-time GitHub setup.** If the project is on GitHub, point the user to
   the "One-time GitHub setup" section of the new `README.md`: Dependabot alerts and security
   updates, secret scanning with push protection, a ruleset protecting `main`, and a read-only CI
   token. These are repository settings, so bootstrap cannot switch them on.
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
