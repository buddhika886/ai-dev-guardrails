# Choosing a model

Optional. By default, `claude` uses your Claude subscription or account, and nothing on this page
changes that. This page explains how a developer can run their own Claude Code sessions through a
different provider, a gateway such as OpenRouter, or a different model, and what to check first.

**You always need Claude Code itself:** `/bootstrap`, the command guard and the "always ask" rules
are Claude Code features. **The model behind it is your choice.**

---

## What stays the same, whatever the model

| Layer | Depends on the model? |
| --- | --- |
| Command guard (block, ask, allow) | **No.** Claude Code runs it before any command, whichever model asked for the command |
| Permission rules (`.claude/settings.json`) | **No.** Anthropic's docs: "Permission rules are enforced by Claude Code, not by the model." |
| Git hooks and CI | **No.** They check the code, not who or what wrote it, so they also cover Cursor, Copilot and hand-written code |
| Written rules (`CLAUDE.md`) | **Yes.** How well they are followed depends on the model |
| Tool use (editing files, running commands well) | **Yes.** Claude Code is built around Claude's tool use; other models can misuse tools or stall |

So switching model never switches off a guardrail. It can change how often one has to step in.

## Before you switch: who sees your code?

Choosing a provider chooses who receives your code, your prompts and the AI's responses. For
personal or open-source work that is usually fine. For client or regulated work it may not be:

- A client contract or NDA may restrict which third parties can see their code.
- Under GDPR, a service that processes personal data on your behalf may need to be approved and
  covered by the data processing agreement, and transfers outside the UK or EU need a lawful basis.
- Regulated clients (for example FCA- or PRA-regulated firms) usually keep a list of approved
  suppliers and expect to be asked before a new one is added.
- Where the provider runs matters. For example, DeepSeek's own API is operated from China.

If you are not sure, ask whoever owns the client relationship before you switch. The default Claude
subscription keeps the fewest parties in the chain.

---

## How switching works

Each way of running Claude Code is a **profile**: a small settings file that tells Claude Code where
to send requests, which key to use and which model names to ask for. Profiles live in
`.claude/profiles/`, one per provider. Examples ship with the project:

| Profile | What it is |
| --- | --- |
| `openrouter` | Claude through OpenRouter |
| `bedrock` | Claude on Amazon Bedrock |
| `vertex` | Claude on Google Cloud Vertex AI |
| `openai` | OpenAI models through OpenRouter (not supported by Anthropic; see below) |

To use one:

1. Copy the example and fill in every `REPLACE-ME` value:

   ```bash
   cp .claude/profiles/openrouter.settings.json.example .claude/profiles/openrouter.settings.json
   ```

   The copy is gitignored, so your key stays on your machine. Never put a key in
   `.claude/settings.json`, which is committed and shared.

2. Start a session with it:

   ```bash
   ./scripts/claude-profile.sh openrouter
   ```

   For OpenRouter, `./scripts/claude-or.sh` is a shortcut for the same thing. Run
   `./scripts/claude-profile.sh` on its own to list the profiles you have.

3. Inside the session, run `/status` to confirm which provider and credential are live.

To go back, run `claude` as normal. There is nothing to undo.

**What the launcher guarantees.** The profile applies to that one session only and writes no file.
It merges with the project's settings rather than replacing them, so every guardrail, hook and
permission rule still applies. And it refuses to start if:

- the profile is tracked by git, or would not be ignored by it (its key could be committed);
- any value still reads `REPLACE-ME`;
- the file is not valid JSON.

Because plain `claude` never sees a profile, nobody ends up on another provider by accident. Your
claude.ai login stays saved while you use a profile, so switching back needs no new login.

To make your own profile (for example `deepseek` or `litellm`), create
`.claude/profiles/<name>.settings.json` with the settings from the sections below. Names use
lowercase letters, digits and hyphens.

---

## OpenRouter

[OpenRouter](https://openrouter.ai) gives access to many AI models through one account and one API.
Pointed at Claude, it gives you the **same Claude models**, billed to OpenRouter rather than a Claude
subscription. Teams use it to:

- pay from shared credits instead of buying a subscription seat per developer
- see spending in one place, and give each developer a key with its own budget
- route only to providers that keep no copy of the data (zero data retention, below)

The `openrouter` profile sets the address (`ANTHROPIC_BASE_URL=https://openrouter.ai/api`), your key
(`ANTHROPIC_AUTH_TOKEN`), an empty `ANTHROPIC_API_KEY` (so an Anthropic key in your shell is not used
by mistake) and the Claude model names. Check
[OpenRouter's model list](https://openrouter.ai/models) when newer models are released and update the
names in your profile.

### Zero data retention (ZDR)

ZDR means the provider that runs the model does not store your prompts or code at all, and so cannot
train on them. On OpenRouter you can require it, so requests are only ever sent to ZDR endpoints:

- **For your whole account:** in OpenRouter's [privacy settings](https://openrouter.ai/settings/privacy),
  switch on ZDR for the model groups you use (Anthropic, OpenAI, Google, and others each have their
  own switch).
- **For one key:** create a [guardrail](https://openrouter.ai/docs/guides/features/guardrails) with ZDR
  enforced and attach it to the API key in your profile. Use this to give a team or a client project
  a key that cannot reach a non-ZDR endpoint, whatever the developer's own settings are.

Set it on the account or the key, not per request: Claude Code cannot add OpenRouter's per-request
options to the calls it makes.

Things to know, from [OpenRouter's ZDR page](https://openrouter.ai/docs/guides/features/zdr):

- Enforcing ZDR for the Anthropic group removes Anthropic's own endpoints; Claude stays available
  through Amazon Bedrock and Google Vertex.
- ZDR covers model requests only, not plugins or tools you enable on OpenRouter, such as web search.
- From 2026-10-27 OpenRouter screens all traffic, ZDR included, for child sexual abuse material, and
  may keep flagged content where the law requires. Check their current terms before relying on ZDR
  for a contract.

### Protection that is always on

Every project's `.gitleaks.toml` includes a rule for OpenRouter keys (`sk-or-v1-...`), and
`.gitignore` excludes the real profiles. A key pasted into a committed file is caught on commit and
again in CI, whether or not anyone uses a profile.

---

## Claude through your cloud provider

Supported by Anthropic. Useful when your organisation already has an agreement with AWS, Google or
Microsoft, since your code then stays within that agreement. Fill in the matching example profile;
each provider's model IDs are listed in its console. Anthropic's docs recommend pinning the model
names, as the profiles do, because the default names can lag behind or be unavailable on a cloud
provider.

| Provider | Settings | Sign-in |
| --- | --- | --- |
| [Amazon Bedrock](https://code.claude.com/docs/en/amazon-bedrock) | `CLAUDE_CODE_USE_BEDROCK=1`; optionally `AWS_REGION` | Your usual AWS credentials (`AWS_PROFILE`, SSO), or `AWS_BEARER_TOKEN_BEDROCK` |
| [Google Vertex AI](https://code.claude.com/docs/en/google-vertex-ai) | `CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` (for example `global`) | `gcloud` application default credentials, or `GOOGLE_APPLICATION_CREDENTIALS` |
| [Microsoft Foundry](https://code.claude.com/docs/en/microsoft-foundry) | `CLAUDE_CODE_USE_FOUNDRY=1`, and `ANTHROPIC_FOUNDRY_RESOURCE` (the resource name) or `ANTHROPIC_FOUNDRY_BASE_URL` | `ANTHROPIC_FOUNDRY_API_KEY`, or `az login` (Entra ID) with no key set |

An Anthropic API key needs no profile: set `ANTHROPIC_API_KEY` in your shell, and run
`unset ANTHROPIC_API_KEY` to go back to your subscription.

## Other gateways

Any gateway that speaks Anthropic's API format works the same way as OpenRouter: set
`ANTHROPIC_BASE_URL` to its address and `ANTHROPIC_AUTH_TOKEN` to its key. See Anthropic's
[gateway guide](https://code.claude.com/docs/en/llm-gateway-connect).

[LiteLLM](https://docs.litellm.ai/docs/proxy/client_setup/claude_code) is a popular gateway you host
yourself, for example to keep a central log or budget. It is a third-party product: follow its own
setup guide, and note Anthropic "doesn't endorse, maintain, or audit third-party gateway products".

## Other vendors' models (not supported by Anthropic)

You can point Claude Code at a model from another company, such as OpenAI or DeepSeek, through a
gateway or a provider's Anthropic-compatible address. Before you do, read what the vendors say:

- Anthropic: Claude Code "doesn't support routing Claude Code to non-Claude models through any
  gateway" ([source](https://code.claude.com/docs/en/llm-gateway)).
- OpenRouter: "Claude Code is optimized for Anthropic models and may not work correctly with other
  providers."

This project has not tested other vendors' models. The guardrails still apply (see the table at the
top), but expect weaker tool use and some Claude Code features not working. The data question above
matters most here, since you are adding a new company to the chain.

**OpenAI (and others) through OpenRouter.** Use the `openai` example profile, and set the three model
names to OpenAI models from [OpenRouter's list](https://openrouter.ai/models?q=openai) (they look
like `openai/<model>`). The same pattern works for any vendor OpenRouter carries. OpenRouter's ZDR
switches (above) include an OpenAI group.

**DeepSeek directly.** DeepSeek publishes an Anthropic-compatible address and a
[Claude Code guide](https://api-docs.deepseek.com/guides/anthropic_api). A `deepseek` profile would
set `ANTHROPIC_BASE_URL` to `https://api.deepseek.com/anthropic`, your DeepSeek key, and an empty
`ANTHROPIC_API_KEY`. Note that DeepSeek silently maps Claude model names to its own models
(`claude-opus*` to one model, everything else to another), so a session can look like Claude while it
is not. Check `/status` and the model DeepSeek reports, and remember where DeepSeek's API is operated
(above).

---

## Common mistakes

- **Setting only the address.** `ANTHROPIC_BASE_URL` on its own does not switch billing: your saved
  claude.ai login is still used. A gateway profile also needs `ANTHROPIC_AUTH_TOKEN`, which takes
  precedence over the login.
- **A forgotten key in your shell.** An exported `ANTHROPIC_API_KEY` overrides your subscription
  login in every session. The profiles set it to empty for that reason; check `/status` if billing
  looks wrong.
- **A key in a committed file.** Keys belong only in the gitignored profile, never in
  `.claude/settings.json` or anything else that is committed.

## Limits

- **Some features need Anthropic's own service.** With a non-Anthropic address active, Remote
  Control and voice dictation are unavailable, and MCP tool search is off by default (set
  `ENABLE_TOOL_SEARCH=true` in the profile if your gateway supports it).
- **Model names are pinned** in the profiles, so they do not change under you. Update them when you
  want newer models.
- **Provider settings change often.** Anthropic's pages linked above are the reference; re-check
  them if a profile stops working.
