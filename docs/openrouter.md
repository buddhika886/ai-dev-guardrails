# Running Claude Code through OpenRouter

Optional. By default, `claude` uses your Anthropic subscription or account. This page explains how a
developer can route their own Claude Code sessions through [OpenRouter](https://openrouter.ai)
instead, and when not to.

## What it is, and why you might want it

OpenRouter resells access to AI models. Pointing Claude Code at it gives you the **same Claude
models**, billed to an OpenRouter account rather than a Claude subscription. Teams use it to:

- pay from shared credits instead of buying a subscription seat per developer
- see spending in one place
- give each developer a key with its own budget

It is a choice each developer makes for their own machine. It does not change the project's code,
rules or checks, and one developer using it does not affect anyone else.

## Before you use it on a project: check you are allowed to

Routing a session through OpenRouter means **your code, prompts and the AI's responses pass through
a third party**. For personal or open-source work that is usually fine. For client work, regulated
work, or anything under a data processing agreement, it may not be:

- A client contract or NDA may restrict which third parties can see their code.
- Under GDPR, a service that processes personal data on your behalf may need to be approved and
  covered by the data processing agreement.
- Regulated clients (for example FCA- or PRA-regulated firms) often keep a list of approved
  suppliers and expect to be asked before a new one is added.

If you are not sure, ask whoever owns the client relationship before you switch. Using the default
Claude subscription keeps one fewer party in the chain.

## How to switch

1. Copy the example profile:

   ```bash
   cp .claude/openrouter.settings.json.example .claude/openrouter.settings.json
   ```

2. Open `.claude/openrouter.settings.json` and replace `sk-or-REPLACE-ME` with your OpenRouter key.
   This file is gitignored, so the key stays on your machine. Never put the key in
   `.claude/settings.json`, which is committed and shared.

3. Start a session through OpenRouter:

   ```bash
   ./scripts/claude-or.sh
   ```

4. Inside the session, run `/status` to confirm which credential is live.

To go back, just run `claude` as normal. There is nothing to undo.

## How it works

The profile sets three things for Claude Code: where to send requests (`ANTHROPIC_BASE_URL`), which
key to use (`ANTHROPIC_AUTH_TOKEN`), and which model names to ask for. The launcher passes it with
`--settings`, which:

- applies to **that one session only** and writes no file
- **merges** with the project's settings rather than replacing them, so every guardrail, hook and
  permission rule still applies
- refuses to start if the placeholder key is still in the profile

Because plain `claude` never sees the profile, nobody ends up on the paid route by accident. Your
claude.ai login stays saved while you use OpenRouter, so switching back needs no new login.

## Protection that is always on

Every project's `.gitleaks.toml` includes a rule for OpenRouter keys (`sk-or-v1-...`), and
`.gitignore` excludes the real profile. A key pasted into a committed file is caught on commit and
again in CI, whether or not anyone uses this feature.

## Limits

- **Claude models only.** Anthropic does not support pointing Claude Code at other vendors' models
  through any gateway, and OpenRouter's own guidance is to stay on the Anthropic provider. This is a
  different way to pay for Claude, not a way to use other models.
- **Some features are unavailable** while a non-Anthropic address is active: Remote Control and voice
  dictation. MCP tool search is off by default; set `ENABLE_TOOL_SEARCH=true` in the profile if you
  need it and find that OpenRouter supports it.
- **Model names are pinned** in the example profile. When newer models are released, update the
  names there (check OpenRouter's model list for the exact identifiers).
