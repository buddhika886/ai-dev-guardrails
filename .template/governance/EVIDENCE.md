# Evidence log: {{PROJECT_NAME}}

What has actually been verified, phase by phase. `DECISIONS.md` holds the decisions; this file holds
the proof.

Rules for this file:

- Raw output only. A summary of output is not evidence.
- A phase is Done when its evidence is in this file, not when someone says it is done. Guardrail
  check [11] fails on any Done phase whose evidence section is missing or has no output block or link.
- Evidence after a deploy or migration is added after it happens, never written in advance.
- Anything unverified is recorded as unverified, explicitly.
- Redact before pasting. Never paste a credential, token, personal data or client identifier, even
  partially.

Started {{BOOTSTRAP_DATE}}.

## Status

| Phase | Scope | Done when | State | Evidence |
| --- | --- | --- | --- | --- |
| 0 | Guardrails installed by /bootstrap | `bash scripts/ci-guardrails.sh` prints `GUARDRAILS PASSED.` | In progress | [Phase 0](#phase-0-guardrails-installed) |

<!--
Add one row per phase, usually one per brief in docs/governance/briefs/.
State is one of: Not started, In progress, Blocked, Done.
Write "Done when" as something a person can observe (a command's output, a page loading, a CI run),
never as "implemented" or "complete".
The Evidence cell links to the phase's section below: [Phase 1](#phase-1-short-name).
-->

## Phase 0: Guardrails installed

Recorded by /bootstrap on {{BOOTSTRAP_DATE}}.

<!-- bootstrap: guardrails output goes here -->

## Out-of-band changes

Changes made outside the repo (a dashboard setting, a hand-set environment variable, a manual data
fix, a console hotfix), recorded so they are not later found as unexplained drift. Record the change
when it is made, then fill the last column once the repo reflects it.

| Date | What changed | Where | Who | Why | Brought into the repo |
| --- | --- | --- | --- | --- | --- |
