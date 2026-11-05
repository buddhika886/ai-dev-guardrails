# Contributing

Thanks for helping. This template's rules end up in every project generated from it, so changes are
reviewed carefully and every change to a rule needs a test. This page explains how to get a change
in.

Be respectful and constructive in issues, pull requests and reviews. Found a way around a
guardrail? Report it privately, see [SECURITY.md](SECURITY.md), not in a public issue.

## How changes get in

1. **For anything bigger than a small fix, open an issue first** (use the "Propose a rule or check"
   template for new rules), so the design can be agreed before you write it.
2. **Fork the repository** and create a branch.
3. **Make the change, with tests** (see below), and run the checks locally.
4. **Sign off every commit** (see "Sign-off" below).
5. **Open a pull request** and fill in the template, including the test output as evidence.
6. **CI must pass and a maintainer must approve.** Nothing reaches `main` any other way: no direct
   pushes, no force-pushes.

## Sign-off (Developer Certificate of Origin)

Every commit must be signed off. A sign-off is a line at the end of the commit message:

```text
Signed-off-by: Your Name <your.email@example.com>
```

By adding it you certify the [Developer Certificate of Origin](https://developercertificate.org/):
in short, that you wrote the change (or have the right to submit it) and that it can be shared under
this project's licence. You keep the copyright in your contribution.

Git adds the line for you with `-s`, or once and for all for this clone:

```bash
git config format.signoff true      # every commit in this repo gets the line from now on
git commit -s -m "Add a deploy pattern for shipit"   # or per commit
```

Forgot? Fix the commits on your branch and push again:

```bash
git rebase --signoff main
git push --force-with-lease
```

The `dco` job in CI fails any pull request with an unsigned commit.

## Setting up

You need git, Node 24, and these tools:

| Tool          | Why                                                        |
| ------------- | ---------------------------------------------------------- |
| `lefthook`    | Runs the checks below on commit and push                   |
| `gitleaks`    | Blocks secrets before they enter a commit                  |
| `shellcheck`  | Every guardrail is a shell script                          |
| `actionlint`  | A broken workflow is a disabled CI                         |
| `node`        | The behaviour suite fills tokens and builds hook payloads  |

On macOS:

```bash
brew install lefthook gitleaks shellcheck actionlint node
lefthook install     # once per clone
```

Elsewhere, gitleaks and actionlint publish prebuilt binaries and lefthook is on npm. Use the gitleaks
version pinned in `.github/workflows/ci.yml` if you want your local scan to match CI exactly.

A tool you have not installed prints `SKIPPED` instead of blocking your commit, because CI re-runs
everything on a clean machine.

If you work on this repo with Claude Code, the repo's own `.claude/settings.json` applies the same
discipline to you that generated projects get: the bash guard runs on every command (unfilled
tokens are treated as empty patterns), commits, pushes and pull requests ask every time, editing
anything under `.template/core/`, the bootstrap command, the CI workflow or the secret-scanner
config asks, and bypass-permissions mode is disabled. Start the session at the repository root, or
none of it loads.

## Running the checks

```bash
shellcheck scripts/*.sh .template/core/scripts/*.sh tests/*.sh tests/lib/*.sh
actionlint .github/workflows/ci.yml .template/core/ci/verify.yml
bash scripts/template-integrity.sh
bash tests/run.sh
```

CI runs the same, plus a full-history secret scan and the sign-off check.

## How the repo is laid out

| Path | What it is |
| --- | --- |
| `.claude/commands/bootstrap.md` | The `/bootstrap` command: the install steps and the token table |
| `.template/core/` | Everything copied into every generated project |
| `.claude/settings.json` | This repo's own Claude Code guardrails (the generated ones are in `.template/core/settings.json`) |
| `.template/governance/` | The governance tier |
| `.template/lang/ts/` | The TypeScript language fragment |
| `.template/security/`, `.template/agents/` | Placeholders for tiers not built yet |
| `docs/` | Documentation, shipped into generated projects too |
| `scripts/template-integrity.sh` | Checks every `{{TOKEN}}` is in the bootstrap token table and vice versa |
| `scripts/claude-profile.sh`, `scripts/claude-or.sh` | The optional model-profile launcher and its OpenRouter shortcut (shipped) |
| `.claude/profiles/` | Example model profiles (shipped; real profiles are gitignored) |
| `tests/` | The behaviour suite ([tests/README.md](tests/README.md)) |

`.template/` and the template's own files (this one included) are removed from a project at the end
of bootstrap.

## The house rules

**Every change to a rule needs a test that fails without it.** A check that has quietly stopped
working passes every syntax check there is; only a behaviour test notices. The suite in `tests/`
bootstraps throwaway projects from a copy of this repo, plants one problem at a time, and asserts
the right check catches it for the stated reason. Test both ways: it must catch what it is for, and
it must not block ordinary work.

**Never weaken a check to make it pass.** Fix the code or the configuration instead.

**Fail closed.** If a check cannot run properly, it must fail, never pass quietly. A check that is
switched off says `SKIPPED (reason)`, never shows a tick.

**Match with here-strings, not pipes into `grep -q`.** Write `grep -q PATTERN <<<"$text"`, never
`printf '%s' "$text" | grep -q PATTERN`. Under `pipefail`, `grep -q` exiting at its first match
kills a writer with more than 64 KiB still to send, and the match is reported as a miss. In the
command guard that let a long command through unchecked.

**Keep the install test in step with bootstrap.** `tests/install.sh` mirrors
`.claude/commands/bootstrap.md` step for step. Change both in the same pull request.

**Keep the controls list in step.** A new block, prompt, check, scan, hook, CI job or policy setting
needs a row in `docs/security-controls.md`; `tests/controls-doc-cases.sh` fails until it has one.

**Keep the token table in step.** If you add or rename a `{{TOKEN}}`, update the table in
`bootstrap.md`; `scripts/template-integrity.sh` fails otherwise.

**No secrets, personal data or client names**, anywhere: code, tests, docs, commit messages, issues.
Test fixtures that look like secrets are assembled from parts at runtime so nothing secret-shaped
sits in a file. Never add a directory-wide allowlist to `.gitleaks.toml`.

**Writing style.** British English, ISO dates (2026-10-26), plain language, no em dashes. The style
carries into every generated project.

**Small, focused pull requests.** One change per PR is far easier to review safely.
