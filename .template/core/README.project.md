# {{PROJECT_NAME}}

<!-- Describe the project here: what it does, who it is for, and how to run it locally. -->

## Guardrails

This project was set up with
[ai-dev-guardrails](https://github.com/buddhika886/ai-dev-guardrails). Every
change, whether written by a person or by an AI assistant, passes through automatic checks before it
can reach `main`. The rules are written down in [CLAUDE.md](CLAUDE.md) and enforced in five layers:
the AI's own commands, your machine on commit and push, and CI on every pull request.

### First time in this repo

1. Install dependencies: `npm ci`
2. Install the local git hooks: `npx lefthook install`. The guardrails fail until you do, because
   a clone without hooks has no local checks at all.
3. Run the checks: `npm run guardrails`. You should see `GUARDRAILS PASSED.`

### What to expect when working with Claude Code

- **It asks before anything leaves your machine:** commits, pushes, pull requests, publishes,
  deploys, remote migrations, remote secret and config changes. Every time, even if someone clicked
  "don't ask again" earlier.
- **It is blocked from a few things outright:** touching production from your laptop, rewriting
  shared git history, and printing secrets into the chat (for example `cat .env` or `printenv`).
- **It warns at the end of a turn** if any guardrail check has gone red.

### Where the rules live

- [CLAUDE.md](CLAUDE.md): the rules the AI reads first, and the known limits of each control.
- [docs/five-layers.md](docs/five-layers.md): how the five layers fit together.
- [docs/configuring-rules.md](docs/configuring-rules.md): how to change a rule, one by one.
{{IF_GOVERNANCE_TIER}}- [docs/governance/](docs/governance/): the evidence log, decision record and phase briefs.

### Client names and secrets

Never commit a secret, personal data or a client's real name. Put client identifiers that must never
be committed in `.guardrails/denylist.local` (it is gitignored), one pattern per line; the guardrails
block any commit that contains them. Ask a maintainer for the list rather than sharing it in chat.

### Using OpenRouter instead of a Claude subscription (optional)

A developer can run Claude Code through OpenRouter with `./scripts/claude-or.sh`. Before doing so
on this project, check that routing code and prompts through a third party is allowed for this work.
See [docs/openrouter.md](docs/openrouter.md).
