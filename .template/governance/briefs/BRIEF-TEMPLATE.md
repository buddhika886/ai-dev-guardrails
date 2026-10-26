# Brief: phase name

Copy this file once per phase (for example `phase-1-session-expiry.md`) and fill every section before
work starts. The agent works from the brief, not from memory of a conversation. The "Done when"
section becomes that phase's row in `EVIDENCE.md`.

## Goal

One or two sentences: what will be true when this phase is finished, and why it matters.

## Preconditions

What must already be true before starting. Check each one first. If one fails, stop and report it; do
not proceed on a stale premise and do not "fix it later".

- ...

## In scope

- ...

## Out of scope

Things that look related but are not part of this phase. Naming them stops scope creep.

- ...

## Done when

The observable evidence that ends the phase: a command and its expected output, a page that loads, a
CI run that passes. Never "implemented" or "complete".

- ...

## Stop and hand back if

- the work needs a production change (prepare the exact steps; a human runs them)
- the work needs a commit, push or deploy (ask; consent does not carry over from earlier)
- a precondition fails, or the brief turns out to be wrong
- a settled decision in `DECISIONS.md` would have to change

## Evidence to record

What goes into this phase's section of `EVIDENCE.md` when it is done: which outputs, links or
screenshots, and anything that was not verified.
