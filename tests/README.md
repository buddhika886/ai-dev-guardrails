# Behaviour tests

The other CI jobs check that the template is well-formed: the shell parses, the workflows are valid,
the token table matches the templates. None of that would notice a guardrail that has quietly stopped
guarding. These tests check that the thing works.

They bootstrap throwaway projects from a full copy of this repo (as a user's clone would be), then
plant one violation at a time and assert the installed guardrails reject it **for the stated
reason**. Starting from a real copy is what proves bootstrap removes the template's own files (its
README, tests, community files and the bootstrap command) and keeps the ones shipped on purpose. Asserting the reason matters: a check that
fails because of an unrelated error looks identical to a check that works.

```bash
bash tests/run.sh          # everything
bash tests/run.sh --keep   # leave the installed projects behind to poke at
```

If a scenario's install fails, its case suites are skipped and counted as failures rather than run
against a half-built project.

Node is the only requirement. `gitleaks-config-cases.sh` also wants gitleaks and announces a SKIP
without it, because CI's `secrets` job runs that suite with the pinned binary. Work happens in a temp
directory outside the repo, because the guardrail scripts resolve their root with
`git rev-parse --show-toplevel` and would otherwise find this repo.

## Layout

| Path                    | What it does                                                             |
| ----------------------- | ------------------------------------------------------------------------ |
| `run.sh`                | Entry point: installs both scenarios, runs every suite, reports.          |
| `install.sh`            | Executes the `/bootstrap` install algorithm on a copy of this repo.       |
| `values/scenario-a.json`| Fully-armed project: Next.js, regulated data, production, database, governance. |
| `values/scenario-b.json`| Sparse project: no framework, no production, no database, no bundle, no governance. |
| `guardrail-cases.sh`    | One violation per check, plus every fail-closed path (scenario A).        |
| `hook-cases.sh`         | The bash guard (block, ask, allow) and Stop hook, including degraded environments. |
| `sparse-cases.sh`       | Empty-token behaviour: skips must be declared, not silent (scenario B).   |
| `lib/assert.sh`         | Shared assertions and the reset-between-cases helper.                     |
| `lib/fill.mjs`          | Literal token substitution, standing in for bootstrap's edits.            |

## The two scenarios

**A** turns everything on, so every check has something to enforce. **B** fills five tokens with the
empty string, which is the path worth testing hardest: an empty regex can turn a check into a no-op
that still reports success. B asserts that a check disabled by configuration says `SKIPPED` and is
never marked with a tick, that all eleven checks account for themselves in the log, and that the
checks which remain still bite (including consent prompts and secret blocking with no production
configured).

## Adding a case

Two properties are tested for every control, and both matter:

1. It rejects what it claims to reject, naming the reason.
2. It does **not** reject ordinary work. A guard that over-blocks gets switched off by the first
   person it annoys, which is a security regression by another route.

Use `expect_reject` / `expect_accept` from `lib/assert.sh`; both revert the project afterwards, so
cases stay independent. Ignored files (`.claude/settings.local.json`, `.guardrails/`, `out/`) survive
that revert, so a case that plants one removes it itself. For the bash guard, use `guard_decide`,
which classifies the answer as `block`, `ask` or `allow` and fails on anything else. For a new guardrail check, add a case to `guardrail-cases.sh` and, if the
check can be disabled by an empty token, a skip assertion to `sparse-cases.sh`.

## The odd one out

Every suite but one tests a GENERATED project. `gitleaks-config-cases.sh` tests this repo's own
`.gitleaks.toml` (and, at the end, the generated project's connection-string rule), because a clean
scan proves nothing by itself: an over-broad allowlist is also
clean. So it asserts both directions, and it asserts that no directory-wide allowlist has crept in
by planting a key under `tests/`, `docs/`, `.template/core/` and `.claude/` and requiring each to be
caught. Fixtures there are assembled at runtime from parts, so no secret-shaped literal sits in the
file at rest and trips the repo's own scan.

`install.sh` deliberately mirrors `.claude/commands/bootstrap.md` step for step. If you change the
install algorithm there, change it here in the same PR, or these tests stop describing reality.
