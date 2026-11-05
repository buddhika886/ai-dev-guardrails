# CLAUDE.md: {{PROJECT_NAME}}

Guidance for working in this repo. Read the source-of-truth documents before changing anything, and
keep the automated guardrails (below) green. If a request conflicts with these rules or those docs,
stop and flag it rather than guessing.

## Consent required (hard rule, no exceptions)

Never commit, push, or deploy without the user's explicit consent each time. Prior consent does not
carry to the next change; ask again. Describe exactly what you would commit, push, or deploy, then
wait for a fresh go-ahead.

This is enforced, not only written down. The PreToolUse bash guard returns "ask" for commits, pushes,
pull requests, releases, package publishes, deploys, remote migrations and remote secret or config
changes, so the user is prompted every time, including in auto mode. The `permissions.ask` rules in
`.claude/settings.json` back it up: ask rules are evaluated before allow rules, so no allowlist entry
can silence them. Do not add allow rules for these commands; guardrail check [8] fails on any that
appear, in either settings file. If an asked command is declined, stop and report; do not look for
another route to the same outcome.

## Production safety (hard rule, no exceptions)

Do NOT touch the production data store from local: no migrations, seeds, scripts, or read queries
against {{PROD_HOST}}. Production changes are made by a human via {{PROD_APPROVED_PATH}}.

The control here is **prepare-versus-execute**: when a prod change is needed, produce the exact
commands or SQL, explain them, and stop. A human runs them against production and pastes the
evidence back. You never connect to prod. The PreToolUse bash guard (`scripts/claude-bash-guard.sh`)
is a backstop that blocks obvious prod-targeting commands and force-pushes, but it cannot catch
production reached through environment-variable indirection, so do not rely on it: follow the
process.

## Start sessions at the repository root

Claude Code loads this project's hooks and permission rules from `.claude/settings.json` in the
directory a session starts in, with no fallback to a parent directory. A session started in a
subdirectory (`cd apps/web && claude`) has this file but none of the guardrails below. Start every
session at the repository root and change directory from there; the hooks follow you.

## Local-first

Create no cloud resources until explicitly told. Everything runs locally via {{LOCAL_TOOLCHAIN}}.

## Transcript hygiene

Never paste real secrets, tokens, credentials, personal data, or production connection strings into
the chat, commit messages, or code comments. Assume the transcript is stored: a secret that reaches
it is disclosed, whatever happens to the repository, and must be rotated.

- Do not print a secret to check it. Test for presence instead (`[ -n "$NAME" ] && echo set`).
- Do not redact with a home-made pipe (`sed`, `cut`, partial `echo`). A filter that fails open leaks
  the value it was meant to hide. If a value must be seen, the human reads it in their own terminal,
  outside this session; a `!` command's output also lands in the transcript.
- The bash guard blocks the common disclosure routes (reading `.env*` and key files, bare `env` or
  `printenv`, echoing secret-named variables, secret-manager CLIs), and `permissions.deny` stops the
  Read tool opening secret files. Both are backstops; this rule is the control.

{{IF_SIGNOFF}}## Commit sign-off
{{IF_SIGNOFF}}
{{IF_SIGNOFF}}Every commit carries a `Signed-off-by` line (`git commit -s`; `git config format.signoff true`
{{IF_SIGNOFF}}makes it automatic). CI rejects a pull request with an unsigned commit. If asked to commit, use `-s`.
{{IF_SIGNOFF}}
## Security rules (verify before every commit and push)

1. No secrets in any tracked file ({{SECRET_FILES}}). Scan the diff before committing.
2. Only {{PUBLIC_VAR}} may be public. Server secrets ({{SECRET_VAR_NAMES}}) must never be exposed to
   client code or the built bundle.
3. Never store or log raw tokens/secrets. Store only a hash. Never log request bodies.
4. All database access is parameterised (no string-built or "unsafe" SQL).
5. Do not weaken the credential model (see Data and credential model below).
6. No sensitive data in browser storage (localStorage/sessionStorage/cookies). In-memory only.
7. Generic errors to clients. Never return internal errors, stack traces, secrets, or the request.
8. Never force-push shared history; changes reach main via reviewed PR, not direct push.

## Data and credential model (do not weaken)

- The runtime role has least privilege: no direct table rights; access only via parameterised,
  access-controlled procedures.
- Migrations are additive: add a new file; never edit an applied one. Roll forward.
- Tokens: CSPRNG, hashed at rest, single-use where possible, expiring.
- Uploads: validated by content (magic bytes), size-capped, stored under a generated key.
- **Fixtures vs real data.** Test and seed data must be clearly synthetic and tagged with an
  `is_fixture` flag (or equivalent) so it can never be mistaken for, or promoted to, production data.
  Never copy real personal or production data into fixtures. Queries and cleanup jobs may rely on
  `is_fixture` to isolate test rows; do not remove or repurpose that flag.

## Schema truth (do not drift)

The committed schema dump is the source of truth for the database shape. If `SCHEMA_DUMP_CMD` is set
in `scripts/ci-guardrails.sh`, the guardrails regenerate the schema with `{{SCHEMA_DUMP_CMD}}` and
diff it against the committed dump; a difference fails the build. When you change the schema, add a
migration and regenerate the committed dump in the same change. Never hand-edit the dump to make the
check pass.

## Dependencies (supply chain)

Every package added is code from a stranger that runs with this project's permissions.

- Prefer the platform and the packages already installed. Add a dependency only when the task needs
  it, and say why in the commit.
- Before adding one, check the name is the package you meant: assistants suggest plausible names
  that do not exist, and attackers register them. Confirm it on the registry (`npm view <name>`)
  and look at its age, maintainers and downloads.
- The bash guard asks before any package is added (`npm install <name>`, `pnpm add`, `yarn add`,
  one-shot runners other than `npx`) and before install scripts are approved. If the user declines,
  do not reach the same package another way.
- Never weaken the policy in `.npmrc`: the 7-day release cooldown, registry-only dependencies and
  reviewed install scripts. The guard blocks overriding it with a flag or environment variable,
  editing `.npmrc` asks every time, and guardrail check [12] fails if it is weakened. If a fix is
  urgent, propose a `min-release-age-exclude` entry for that one package and let the user decide.
- CI scans `package-lock.json` for known vulnerabilities (OSV-Scanner) and checks registry
  signatures. Fix a finding by upgrading; an accepted exception goes in `osv-scanner.toml` with an
  `ignoreUntil` date and a reason, in a reviewed change.

## Evidence standard (hard rule)

Claims of completion are not accepted; observable output is.

- A task is done when its evidence has been produced and shown: the test, lint or guardrails output,
  the CI run, the preview URL loading. A summary of output is not output.
- After a production migration or deploy, the human confirms the end state, not just the command's
  exit code: the schema-truth check shows no drift, the smoke check passes.
- If something was not verified, say so explicitly. Never describe unverified work as complete.
- If a precondition fails, stop at that step. Do not proceed on a stale premise and "fix it later".

## Client confidentiality

Client names, client data and other confidential identifiers never go into code, fixtures, commit
messages, branch names, or anything that reaches a log or a screenshot. Use the project codename.
Identifiers that must never be committed go in `.guardrails/denylist.local` (gitignored; one
extended regex per line), and guardrail check [9] blocks them. CI reads the same list from the
`GUARDRAILS_DENYLIST` repository secret. Never commit the denylist itself.

## Known limits of these controls

Say these plainly in any security write-up rather than describing the controls as complete.

- `git commit --no-verify` skips the local hooks, and a fresh clone has no local hooks until
  `npx lefthook install` runs (check [10] flags this). CI is the authority.
- The bash guard matches command text. It cannot see through environment-variable indirection,
  scripts it is asked to run, or a program invoked in an unexpected form. Process is the control.
- Agent hooks gate the agent only. A human's `!` commands and terminal are not inspected.
- Nothing here can recall a secret once it has reached the transcript. Rotation is the only remedy.
- The client denylist sees what it is given: CI enforces it only when `GUARDRAILS_DENYLIST` is set,
  and it does not scan commit messages or history.
- The release cooldown applies when npm chooses versions (`npm install`, `npm update`), not when
  `npm ci` installs a lockfile already reviewed. Check [12] and the guard cover npm only: pnpm,
  yarn and bun have their own settings (see `docs/configuring-rules.md`). A vulnerability scan finds
  only what has been reported; a brand-new malicious package is the cooldown's job.

## Working conventions

- {{LANGUAGE_SPELLING}}, ISO dates (YYYY-MM-DD). Small, focused commits. Stop for review per task.
- Verify before you push: typecheck, lint, build, and guardrails pass locally first.
- Record any change made outside the repo (a dashboard edit, a hand-set environment variable, a
  manual data fix) where the team will find it, with what was changed and why, so it is not later
  found as unexplained drift.

## Source-of-truth documents (read before changing anything)

- {{SOURCE_OF_TRUTH_DOCS}}
{{IF_SECURITY_TIER}}- SECURITY.md: threat model, credential model, and control-status table.
{{IF_SECURITY_TIER}}- Security reviewer subagent (`.claude/agents/`): run it before a security-sensitive PR.
{{IF_GOVERNANCE_TIER}}- docs/governance/EVIDENCE.md: phase status, the raw evidence for each phase, and the out-of-band changes register.
{{IF_GOVERNANCE_TIER}}- docs/governance/DECISIONS.md: settled decisions, deviations (each with cost, exit and owner), and open questions.
{{IF_GOVERNANCE_TIER}}- docs/governance/briefs/: one brief per phase. Work from the brief, not from memory of a conversation.
{{IF_GOVERNANCE_TIER}}
{{IF_GOVERNANCE_TIER}}## Governance (keep the records current)
{{IF_GOVERNANCE_TIER}}
{{IF_GOVERNANCE_TIER}}The governance records are part of the work, not paperwork after it. Update them in the same change
{{IF_GOVERNANCE_TIER}}as the work they describe, and never write them in advance of what happened.
{{IF_GOVERNANCE_TIER}}
{{IF_GOVERNANCE_TIER}}- Before starting a phase, check its brief exists and its preconditions hold. If a precondition fails,
{{IF_GOVERNANCE_TIER}}  stop and report; do not proceed on a stale premise.
{{IF_GOVERNANCE_TIER}}- A phase is Done only when its evidence section in EVIDENCE.md holds the raw output or a link that
{{IF_GOVERNANCE_TIER}}  proves it. Guardrail check [11] fails on a Done phase without one, and on an unknown state.
{{IF_GOVERNANCE_TIER}}- Any knowing departure from a rule, plan or standard is a deviation in DECISIONS.md, with a Cost, an
{{IF_GOVERNANCE_TIER}}  Exit and an Owner. Check [11] fails on an entry missing any of the three.
{{IF_GOVERNANCE_TIER}}- Any change made outside the repo goes in the out-of-band register in EVIDENCE.md when it is made.
{{IF_GOVERNANCE_TIER}}- Settled decisions are not changed or "improved" without asking. Open questions are not answered
{{IF_GOVERNANCE_TIER}}  by guessing; record what would settle them.
