# Subagents: placeholder

Not built yet. Arrives in template release T2.

Will hold the guardrails subagents (for example a security-reviewer and a schema-truth checker) that
bootstrap copies to `.claude/agents/` and the generated `CLAUDE.md` points at when the relevant tiers
are on.

This lives under `.template/` on purpose: everything here is deleted at the end of bootstrap, so a
bootstrapped project never inherits a file telling it a feature is missing. Nothing is copied to
`.claude/agents/` until the real subagents exist.
