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
3. Run the checks: `npm run guardrails`. You should see `GUARDRAILS PASSED.` It needs npm 11.10
   or later (Node 24 ships it), because older npm ignores the release cooldown in `.npmrc`.
4. Optional: install [OSV-Scanner](https://google.github.io/osv-scanner/) so `git push` also scans
   dependencies for known vulnerabilities. CI runs it either way.

### One-time GitHub setup (repository owner)

If this project lives on GitHub, the repository owner switches these on once. They are repository
settings, so no file in the repo can turn them on for you:

1. **Dependabot.** In **Settings → Code security**, enable **Dependabot alerts** (warnings when a
   dependency has a known vulnerability) and **Dependabot security updates** (automatic fix pull
   requests). `.github/dependabot.yml` already schedules weekly update pull requests for GitHub
   Actions and npm; alerts and security fixes need these two switches.
2. **Secret scanning.** On the same page, enable **Secret scanning** and **Push protection**, so
   GitHub also rejects a pushed secret.
3. **Protect `main`.** In **Settings → Rules → Rulesets**, add a branch ruleset for `main`: require
   a pull request with at least one approval **and review from Code Owners** (so a change to the
   guardrail files listed in `.github/CODEOWNERS` needs an owner's approval), require the `verify`,
   `dependencies` and `secrets` checks to pass, and block force pushes.
4. **Read-only CI token.** In **Settings → Actions → General → Workflow permissions**, choose
   **Read repository contents**.
5. **Client denylist** (client work only). In **Settings → Secrets and variables → Actions**, add a
   secret named `GUARDRAILS_DENYLIST` with the same lines as `.guardrails/denylist.local`.

Prefer the command line? With the GitHub CLI, replace `OWNER/REPO` and run:

```bash
gh api -X PUT repos/OWNER/REPO/vulnerability-alerts        # Dependabot alerts
gh api -X PUT repos/OWNER/REPO/automated-security-fixes    # Dependabot security updates
```

### What to expect when working with Claude Code

- **Start Claude Code at the repository root.** The hooks and permission rules live in
  `.claude/settings.json` here, and Claude Code does not look in parent directories for them: a
  session started inside a subfolder has none of the protections below.

- **It asks before anything leaves your machine:** commits, pushes, pull requests, publishes,
  deploys, remote migrations, remote secret and config changes. Every time, even if someone clicked
  "don't ask again" earlier. (Bypass-permissions mode would skip the prompt; the project settings
  switch it off.)
- **It asks before adding a package** (`npm install <name>`, `pnpm add`, `yarn add`), because a
  package name an assistant suggests may not be the one you meant.
- **It is blocked from a few things outright:** touching production from your laptop, rewriting
  shared git history, printing secrets into the chat (for example `cat .env` or `printenv`), and
  switching off the dependency policy in `.npmrc`.
- **It warns at the end of a turn** if any guardrail check has gone red.

### Where the rules live

- [CLAUDE.md](CLAUDE.md): the rules the AI reads first, and the known limits of each control.
- [docs/five-layers.md](docs/five-layers.md): how the five layers fit together.
- [docs/security-controls.md](docs/security-controls.md): every control, where it is enforced and
  where it stops.
- [docs/why-these-rules.md](docs/why-these-rules.md): why each rule exists, in plain language.
- [docs/configuring-rules.md](docs/configuring-rules.md): how to change a rule, one by one.
{{IF_GOVERNANCE_TIER}}- [docs/governance/](docs/governance/): the evidence log, decision record and phase briefs.

### Client names and secrets

Never commit a secret, personal data or a client's real name. Put client identifiers that must never
be committed in `.guardrails/denylist.local` (it is gitignored), one pattern per line; the guardrails
block any commit that contains them. Ask a maintainer for the list rather than sharing it in chat.

### Using a different model or provider (optional)

A developer can run their own Claude Code sessions through OpenRouter (including zero data
retention), Amazon Bedrock, Google Vertex or another provider, with
`./scripts/claude-profile.sh <profile>` (`./scripts/claude-or.sh` for OpenRouter). The guardrails
still apply. Before doing so on this project, check that sending code and prompts to that provider
is allowed for this work. See [docs/choosing-a-model.md](docs/choosing-a-model.md).
