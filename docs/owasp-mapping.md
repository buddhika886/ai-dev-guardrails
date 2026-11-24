# OWASP GenAI LLM Top 10 (2026) mapping

How this template's controls line up against the
[OWASP GenAI LLM Top 10 2026](https://genai.owasp.org/resource/owasp-genai-llm-top-10-2026/),
published 4 August 2026. Each risk is named by its OWASP ID and title only; follow the link for
OWASP's own description, which is licensed CC BY-SA 4.0.

**Read this with the right question in mind.** The OWASP list is written for applications that use
a large language model. This template governs an AI coding assistant working on your code. So each
risk is looked at twice:

- **For the assistant:** what the template does about this risk while the AI writes your code.
- **For your app:** what is left for you if the app you build itself uses a model.

**Status** means: **Covered** (controls address the risk for the assistant, within the limits
stated), **Partial** (some controls, with known gaps), **Not applicable** (the risk does not arise
for a coding assistant), **Not covered** (it arises and nothing here addresses it).

Control names and check numbers refer to [security-controls.md](security-controls.md), the complete
list.

| ID | Risk | Status for the assistant |
| --- | --- | --- |
| LLM01 | Prompt Injection | Partial |
| LLM02 | Sensitive Information Disclosure | Covered |
| LLM03 | Excessive Agency | Covered |
| LLM04 | Supply Chain | Covered |
| LLM05 | Data and Model Poisoning | Not applicable |
| LLM06 | Unbounded Consumption | Not covered |
| LLM07 | Misinformation | Partial |
| LLM08 | Hidden Context Exposure | Covered |
| LLM09 | Vector and Embedding Weaknesses | Not applicable |
| LLM10 | Improper Output Handling | Covered |

---

### LLM01 Prompt Injection

**Status: Partial.** Text the AI reads (a web page, an MCP tool result, a file) can try to steer it.
No control outside the model can stop it being persuaded, so the template limits what a persuaded
assistant can do.

- Anything that leaves the machine or changes shared state asks every time: commits, pushes, pull
  requests, deploys, remote config, new packages (command guard; settings ask rules).
- Web pages ask, follow a reviewed list, or are blocked, chosen at setup (`WebFetch`, bootstrap Q7).
  Fetching from the shell asks, except to this machine (`NETWORK_FETCH`).
- Every MCP tool call asks first (`mcp__*`).
- The AI's instruction files are checked for hidden characters (check 13), and editing them asks
  (settings ask rules, `ENFORCEMENT_WRITE`, CODEOWNERS).
- The guardrail files cannot be edited without asking, and CI judges a pull request with `main`'s
  copy of the checks, so an injected change cannot weaken the check that reviews it.

**Gap:** an injected instruction can still shape code the AI writes within a task; review and CI
are the backstop. The template is built for mistakes, not for an assistant deliberately working
against you.

**For your app:** keep instructions and untrusted content apart, ask a person before any action that
changes data, and strip hidden Unicode from everything the model reads.

### LLM02 Sensitive Information Disclosure

**Status: Covered.**

- The AI cannot read secret files, dump the environment, echo secret-named variables or run
  secret-manager commands (command guard: `SECRET_FILE_READ`, `GLOB_READ`, `ENV_DUMP`,
  `SECRET_CLIS`); Claude Code's own file tools are denied the same files (`Read` deny rules).
- Sending a secret file with `curl` or `wget` is blocked.
- No secret files in git (check 1), no secrets in the built app (check 6), no saved approval holding
  a password (check 8), gitleaks on every commit and over the full history in CI.
- Client names never reach the repository, once a client list is set (check 9).
- The guard's decision log records no command text.
- Written rule: a secret that reaches the transcript counts as leaked and is rotated;
  [choosing-a-model.md](choosing-a-model.md) covers zero data retention.

**Gap:** protection matches file names and known shapes, not content. A search across the whole
project (`grep -r`) is stopped only when the optional sandbox is on. A secret you paste into the chat
yourself is not caught.

**For your app:** keep secrets out of prompts, mask or turn off prompt and response recording in
tracing tools, and set retention with every provider that stores conversations.

### LLM03 Excessive Agency

**Status: Covered.** This is the template's core.

- Fresh consent for every commit, push, pull request, release, publish and deploy; production is
  blocked from the laptop (command guard; settings ask rules; written rules).
- "Don't ask again" cannot quietly widen access: check 8 fails if a saved approval pre-approves a
  consent command, an MCP server or a website, and bypass-permissions mode is disabled.
- MCP tools ask; the optional sandbox (bootstrap Q6) limits what shell commands can reach.
- The guard mediates every shell command and blocks if it cannot run (`onFailure: block`).
- The decision log records what was blocked or asked.

**For your app:** give the model the fewest tools, the narrowest permissions and a human approval
step before anything irreversible.

### LLM04 Supply Chain

**Status: Covered.**

- Package versions must be 7 days old; packages only from the registry; install scripts only when
  approved by name; the lockfile is verified (check 12; `.npmrc`).
- Adding a package asks, and overriding the policy for one command is blocked (`DEPENDENCY_PATTERNS`,
  `DEP_WEAKEN`).
- CI scans for known vulnerabilities and checks registry signatures; GitHub Actions are pinned to
  commit hashes and downloaded tools to checksums.
- MCP servers are pinned to an exact version, an image digest or https (check 14), and `.mcp.json`
  is reviewed through CODEOWNERS.
- A software bill of materials is attached to every CI run.

**Gap:** set up for npm only; a vulnerability scanner knows only what has been reported.

**For your app:** vet every model provider and plug-in, and record the models and datasets you use
alongside the SBOM.

### LLM05 Data and Model Poisoning

**Status: Not applicable.** The template does not train or fine-tune a model. The nearest control
is check 13, which keeps hidden instructions out of the files the AI reads every session.

**For your app:** if you fine-tune or build retrieval data, track where every training and
retrieval source came from.

### LLM06 Unbounded Consumption

**Status: Not covered.** Nothing here limits the tokens or money a session spends, including on the
model profiles. Set spending limits in your provider account (Anthropic Console, OpenRouter,
Bedrock or Vertex).

**For your app:** rate limits per user, input size limits, hard spending caps and timeouts on agent
loops.

### LLM07 Misinformation

**Status: Partial.**

- A package name the AI invents is caught by the ask before adding a package and the 7-day
  cooldown, since an invented name is almost always brand new.
- "Done" needs proof: with the governance tier, a phase cannot be marked done without test output
  or a CI link (check 11).
- Every change passes the checks and CI, whatever the AI says about it.

**Gap:** wrong but plausible code that passes the tests is a matter for review.

**For your app:** ground answers in sources, check facts before acting on them, and show users
what is verified.

### LLM08 Hidden Context Exposure

**Status: Covered.** For a coding assistant, the hidden context is `CLAUDE.md` and the other
instruction files.

- They are committed, so gitleaks scans them, and check 9 keeps client names out once a client list
  is set.
- The template's thesis is OWASP's: rules in the prompt are backed by deterministic controls
  (hooks, checks, CI), and authorisation sits outside the model (permissions and the guard).

**For your app:** assume the system prompt can be extracted; never put secrets or access logic in
it.

### LLM09 Vector and Embedding Weaknesses

**Status: Not applicable.** The template uses no retrieval or vector store.

**For your app:** if you use retrieval, enforce access control inside the vector query, per user and
per tenant.

### LLM10 Improper Output Handling

**Status: Covered.** The assistant's output is its commands and its code.

- Every shell command the AI produces is treated as untrusted and inspected before it runs (command
  guard).
- Its code passes the checks before commit and in CI: safe database queries (check 3), nothing
  sensitive in browser storage (check 4), only approved values reach the browser (check 2).

**Gap:** output encoding and a Content Security Policy are design rules checked by review, not by a
check.

**For your app:** treat model output as user input. Escape or sanitise it before rendering, never
insert model-written HTML unsanitised, set a Content Security Policy, and do not let rendered output
load images or links from arbitrary addresses.
