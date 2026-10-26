# CLAUDE.md: ai-dev-guardrails (BOOTSTRAP MODE)

This repo is a **template**, not a project yet. It carries a defence-in-depth guardrails setup
(five layers: documented rules, agent hooks, local git hooks, CI, architecture) that you install
into a real project by running the bootstrap command.

**Fresh clone? Run `/bootstrap`.** It interviews you, fills every project-specific value, wires the
hooks, verifies the guardrails are green, then replaces this file with the real project CLAUDE.md
and deletes `.template/`.

## Consent required (applies even in bootstrap mode, no exceptions)

Never commit, push, or deploy without the user's explicit consent each time. Prior consent does not
carry to the next change; ask again. Bootstrap prepares everything and then stops for consent before
the first commit. Describe what you would commit, then wait.

That is all that applies until bootstrap runs. Everything else arrives with the project.
