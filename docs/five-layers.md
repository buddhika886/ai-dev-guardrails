# The five-layer model

Guardrails work because no single control is trusted to be enough. Each layer catches what the last
one misses, and each is independent: a mistake has to defeat all five to reach production. The
layers are ordered from soonest (as the agent thinks) to last-resort (a clean-checkout CI run), with
architecture underneath limiting the blast radius of anything that still slips through.

## 1. Documented rules

`CLAUDE.md` states the intent and the hard limits in imperative, specific language. The agent reads
it on every session and every contributor reads it first. With the security tier, `SECURITY.md`
carries the threat model and a control-status table. Rules that are only written down are advisory,
which is why the next four layers exist to enforce them.

## 2. Agent hooks

`.claude/settings.json` wires two Claude Code hooks that gate the **agent's own** tool calls (a human
running the same command via the input-box `!` prefix is unaffected):

- **PreToolUse on Bash** (`claude-bash-guard.sh`) answers every agent command with one of three
  outcomes before it runs:
  - **Block** (exit 2, reason shown to the model): anything that targets production from local,
    rewrites shared git history, would print a secret into the session transcript (reading
    `.env*` or key files, bare `env`, echoing secret-named variables, secret-manager CLIs), or
    overrides the dependency policy in `.npmrc` for one command.
  - **Ask** (a PreToolUse `permissionDecision: "ask"`): commits, pushes, pull requests, releases,
    package publishes, deploys, remote migrations, remote secret or config changes, and adding a
    package (a name an assistant suggests may not be the package anyone meant). The user is
    prompted every time, including in auto mode. Deploy verbs are on by default, even before a
    project has production: a question is cheaper than an unintended deploy.
  - **Allow**: everything else carries on through the normal permission flow.

  It fails closed on its own failure modes: an absent hook payload blocks, and an unparseable one (or
  a machine with no JSON parser on `PATH`) is pattern-matched raw rather than waved through, because
  a guard that goes quiet when a dependency is missing is worse than no guard.
  The hook is wired in exec form through `${CLAUDE_PROJECT_DIR}`, because Claude Code runs hooks in
  the agent's current directory and a relative path stops resolving after `cd apps/web`; and with
  `onFailure: block`, because Claude Code otherwise treats a hook that cannot start as a non-blocking
  error and runs the command. Both are asserted by check [8].
- **Permission rules** back the guard up. `permissions.ask` covers the core consent commands,
  `permissions.deny` stops the Read tool opening secret files, and `disableBypassPermissionsMode`
  keeps a session out of the one mode that skips every prompt. Claude Code evaluates deny, then ask,
  then allow, so an allowlist wildcard saved in `settings.local.json` cannot silence them. Guardrail
  check [8] parses the settings and fails if any hook or rule is removed or weakened, if either
  settings file disables hooks or defaults to bypass mode, or if an allow rule pre-approves a
  consent command, which is how a written consent rule quietly turns back into prose.
- **Stop** (`claude-stop-guardrails.sh`) runs the fast guardrails when a turn ends and warns, naming
  the first failing check, so a violation is noticed before anything is committed.

The bash guard is a backstop, not the control. Nothing it does can recall a secret once it has
reached the transcript: the only remedy then is rotation, which is why disclosure is blocked rather
than redacted. The real control for production is process:
prepare-versus-execute (below). Environment-variable indirection means no pattern list can catch
every way a command could reach prod, so the guard names the patterns it knows and defers to process
for the rest.

## 3. Local git hooks

Lefthook runs fast checks on the developer's machine before code leaves it: guardrails in fast mode,
a staged-secret scan (gitleaks, soft-skipped if not installed since CI always enforces it), and
per-language lint on pre-commit; typecheck, full guardrails, build and (if OSV-Scanner is
installed) a dependency vulnerability scan on pre-push. This is early
warning, not authority. The guardrails include a client denylist read from a gitignored file
(a committed denylist would leak the names it protects), and a check that fails while the hooks
themselves are not installed, since `core.hooksPath` and `.git/hooks` do not survive a clone, and
a dependency-policy check: `.npmrc` keeps its 7-day release cooldown and registry-only rules, and
every lockfile entry comes from the registry with a sha512 hash.

## 4. CI

GitHub Actions is the authority. On a pull request it runs the guardrails from the base branch's
copy of the script, so a change that weakens a check is still judged by the old one; the new checks
take over once the change is reviewed and merged. `.github/CODEOWNERS` names the owners whose review
every change to an enforcement file needs. It re-runs everything on a clean checkout, so nothing merges on a
"works on my machine". Three jobs: `verify` (typecheck, lint, build, registry signatures,
guardrails, schema-truth), `dependencies` (a checksum-pinned OSV-Scanner binary checking the
lockfile for known vulnerabilities) and `secrets` (a checksum-pinned gitleaks binary scanning full
history). The token is least-privilege
(`contents: read`). Branch protection on `main` requires these checks and a review, and disallows
force-push.

## 5. Architecture

Guardrails catch mistakes; architecture limits what a mistake can do. Design these in from the start:

- **Least-privilege runtime identity.** The role the app connects as has the minimum rights to
  function; prefer access through parameterised, access-controlled procedures over broad table
  rights, so a compromised app layer cannot read or write arbitrarily.
- **Hash secrets at rest.** Store only a hash of tokens; keep the raw value out of the database and
  the logs. Make tokens single-use where the flow allows, and expiring.
- **Validate uploads by content, not name.** Sniff magic bytes, cap size, store under a generated key.
- **Generic errors at trust boundaries.** Never return internal errors, stack traces, secrets, or the
  request body; never log request bodies.
- **Fix the order of the security pipeline** (for example: origin check, bot/human check, hash,
  validate, side effects, write) so a refactor cannot reorder a check after a write.
- **Additive migrations.** New file per change; never edit an applied one. Roll forward.
- **No sensitive data in browser storage.** Keep client state in memory.

## Evidence, not claims

Every layer above produces output, and that output is the evidence. The generated `CLAUDE.md`
carries an evidence standard: a task is done when its output has been shown, not when a session says
it is done; anything unverified is labelled unverified; a failed precondition stops the work rather
than being fixed later. Each control also lists its known limits, so a security write-up describes
what the controls do not cover instead of implying they are complete.

The governance tier turns the standard into records. `docs/governance/EVIDENCE.md` holds a phase
table and the raw output behind each Done phase; `docs/governance/DECISIONS.md` holds settled
decisions, deviations (each with what it costs, how it ends and who owns it) and open questions.
Bootstrap writes the first entry itself: Phase 0 is the guardrails run it just made. Check [11]
fails on Done without evidence, so the records cannot drift into claims.

## Cross-cutting principles

Fail closed (an error in a check counts as a failure), least privilege, generic errors to clients,
never log secrets or request bodies, and human consent gates for anything outward-facing or
irreversible.
