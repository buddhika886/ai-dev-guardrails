## What and why

<!-- One short paragraph. Link the issue this closes, if there is one. -->

## Evidence

<!-- Paste the output that shows this works, for example the summary lines of `bash tests/run.sh`.
A description of the output is not evidence. Say plainly if anything was not verified. -->

```text

```

## Checklist

- [ ] Every commit is signed off (`git commit -s`), certifying the [DCO](https://developercertificate.org/)
- [ ] `bash tests/run.sh` passes, along with shellcheck, actionlint and `scripts/template-integrity.sh`
- [ ] If this changes a check or the guard, a test case is included that **fails without the change**
- [ ] If this adds or renames a `{{TOKEN}}`, the token table in `.claude/commands/bootstrap.md` is updated
- [ ] If this changes the install steps, `tests/install.sh` is updated to match `bootstrap.md`
- [ ] No secrets, personal data or client names anywhere in the diff, this description or commit messages
- [ ] Docs updated where behaviour changed; British English, no em dashes
