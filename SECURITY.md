# Security policy

This project is a set of security controls, so a flaw in it is a security issue for everyone who
uses it. Please report one privately so it can be fixed before it is widely known.

## What counts as a vulnerability here

- **A bypass:** a way to get a command past the AI command guard that it is meant to block or ask
  about (a deploy, a push, printing a secret), or a way to read a secret file despite the deny rules.
- **A check that passes when it should fail:** a guardrail check, secret-scanner rule or CI job that
  reports success while the problem it exists to catch is present.
- **A leak by the template itself:** the template or its generated files exposing a secret, a
  client name from the denylist, or other confidential data (for example in logs).
- **Anything that makes a generated project less safe than its documentation says.**

Known limits listed in the README and in the generated `CLAUDE.md` (for example, the guard reading
command text and so missing environment-variable indirection) are documented trade-offs, not
vulnerabilities. A new, practical way to exploit one is still worth reporting.

## How to report

Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose
**Report a vulnerability**. Only the maintainers can see the report.

Please include what you ran, what you expected, what happened, and the version (commit) you tested.
**Do not include real secrets, credentials or client data** in the report; use obviously fake values.

Please do not open a public issue or pull request for a vulnerability until it has been fixed.

## What to expect

This is a small project maintained in spare time, so there are no guaranteed response times. The
aim is to acknowledge a report within a week, agree a fix and a disclosure date with you, and credit
you in the fix unless you would rather not be named.

## Supported versions

The project is pre-1.0. Only the latest commit on `main` receives fixes.
