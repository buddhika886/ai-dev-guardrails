# ai-dev-guardrails

> **Status: v0.1, pre-release.** Works end to end for TypeScript projects. Python and React Native
> support, and the security tier, are not built yet. Details may change before v1.

**Safety rails for coding with an AI assistant.** This is a starter kit that sets up a project so the
common mistakes of AI-assisted coding are caught automatically, before they cause damage: leaked
passwords, accidental deploys, pushes nobody approved, secrets committed to git. It catches human
mistakes too.

It is built for [Claude Code](https://claude.com/claude-code). You don't copy files by hand: you open
the kit in Claude Code, type `/bootstrap`, answer a few questions, and it sets everything up.

---

## Why you might want this

An AI coding assistant can run commands on your machine: commit, push, deploy, read files. That is
what makes it useful, and what makes it risky. These are the problems this kit is built around:

| Problem | What it looks like |
| --- | --- |
| Secrets leak through the chat | The AI runs `cat .env` to check a setting, and a password lands in the chat history, which is stored. Now it has to be changed. |
| "Ask me first" quietly stops working | You tell the AI to always ask before pushing, then click "don't ask again" a few times. Weeks later it pushes without asking and nobody noticed. |
| Accidental deploys | The AI runs a deploy while "just testing", and it goes to the live site. |
| Secrets committed to git | An API key gets committed. Deleting it later doesn't help: it stays in the history. |
| Confidential names in code | A client's real name ends up in a comment or commit message. |
| Risky packages | The AI installs a package with a known vulnerability, a hijacked new release, or a plausible name that doesn't exist and that an attacker has registered. |
| "Done" that isn't | Work is reported finished, but nobody actually ran the tests. |

---

## How it works

Five safety nets, one under the other. If something slips through one, the next catches it.

```text
  You or the AI want to...          The safety net that acts
  ─────────────────────────         ─────────────────────────────────────────────
  run a command (AI)        ──►  2. Command guard: block it, ask you, or allow it
  commit or push            ──►  3. Checks on your machine (git hooks)
  merge a pull request      ──►  4. Checks on GitHub (CI): the final word

  Underneath all of it:          1. Written rules the AI reads first (CLAUDE.md)
                                 5. Safe design habits that limit damage if a bug gets through
```

Three principles run through everything:

- **If a check breaks, it fails.** A broken check never quietly lets things through.
- **If a check is switched off, it says so.** It prints `SKIPPED (reason)`, never a green tick.
- **Every check is tested both ways.** It must catch its problem and must not block normal work.

More detail: [docs/five-layers.md](docs/five-layers.md). Why each rule exists, in plain language,
with the real incidents behind them: [docs/why-these-rules.md](docs/why-these-rules.md).

---

## Try it

**You need:** [Claude Code](https://claude.com/claude-code), git, and Node 24. Claude Code itself is
required, but the model behind it is your choice: a Claude subscription by default, or Claude
through OpenRouter, AWS, Google or Azure, among others. See
[docs/choosing-a-model.md](docs/choosing-a-model.md).

1. On GitHub, choose **Use this template** to make your own copy, then clone it.
2. Open the folder in Claude Code and type `/bootstrap`.
3. Answer the questions:
   - **Stack:** what language and framework? (TypeScript for now.)
   - **Repo shape:** where do your frontend, backend and database migrations live?
   - **Data:** does the project handle personal or regulated data?
   - **Production:** what does your live environment look like? ("None yet" is fine.)
   - **Extras:** do you want the governance tier (below)?
   - It also asks for a project name, your source documents and a licence choice.
4. Bootstrap installs everything, runs all the checks until they pass, and shows you the result.
5. **It stops and asks before committing.** Nothing is committed or pushed without your say-so.
6. **On GitHub? Do the one-time repository setup.** Some protections are repository settings that
   no file can switch on: Dependabot alerts and security updates, secret scanning with push
   protection, branch protection for `main`, and a read-only CI token. Your project's new README
   lists each one under "One-time GitHub setup", with where to click.

### What you end up with

| File | What it is |
| --- | --- |
| `CLAUDE.md` | The rules the AI reads first, filled in for your project |
| `README.md` | A starter README for your project (add your own description) |
| `.claude/settings.json` | Claude Code's "always ask" and "never read" rules |
| `scripts/claude-bash-guard.sh` | The command guard |
| `scripts/ci-guardrails.sh` | The guardrail checks |
| `.gitleaks.toml` | The secret scanner's rules |
| `.npmrc` | The dependency policy: a 7-day wait on new releases, registry-only packages, approved install scripts |
| `lefthook.yml` | Checks that run on your machine on commit and push |
| `.github/workflows/ci.yml` | Checks that run on GitHub for every pull request |
| `docs/` | How it all works and how to change it |

Everything that belonged to the template itself (this README, its tests, its contribution files)
is removed, so your project contains only what it needs.

---

## What it's like day to day

**The AI asks before anything leaves your machine.** You get a prompt, every time it recognises
one of these, for:
commits, pushes, pull requests, publishing a package, deploys, changes to a live database, and
changes to secrets or settings on a hosting platform. It also asks before adding a package, so you
see the exact name before anything is installed. This holds even if someone clicked "don't ask
again" earlier, and even in auto mode. (Claude Code's bypass-permissions mode would skip the prompt,
so the project settings switch that mode off.) Deploys ask by default, even before you have a live site: a
question costs a second, an accidental deploy costs much more.

**Some things are blocked outright:**

- touching production from your laptop (you describe production during setup)
- rewriting shared git history (force-push, `git reset --hard`)
- printing secrets into the chat (`cat .env`, `printenv`, `echo $API_SECRET`)
- switching off the dependency policy for one command (`npm install --min-release-age=0`)

Why block secrets instead of asking? If you approved the prompt, the secret would land in the chat
history anyway, and once it's there it can only be changed, never removed.

**Normal work carries on:** reading `.env.example`, copying it to `.env`, checking a value is set
without printing it (`[ -n "$API_SECRET" ] && echo set`), running tests, building.

**At the end of each AI turn**, the checks run quietly and warn you if anything has gone red.

---

## The rules at a glance

| Rule | What it stops | Where it lives |
| --- | --- | --- |
| Ask before outward actions | Pushes, deploys, publishes nobody approved | Command guard + `.claude/settings.json` |
| Block production from local | The AI touching your live systems | Command guard (`PROD_GUARD_PATTERNS`) |
| Block secret printing | Passwords landing in the chat | Command guard + `.claude/settings.json` |
| 1. No secret files in git | `.env`, private keys, credential files committed | `SECRET_FILE_PATTERNS` |
| 2. Only approved browser settings | Server secrets exposed to the browser | `PUBLIC_VAR_ALLOWLIST` |
| 3. Safe database queries | SQL injection | `UNSAFE_SQL`, `SERVER_DIRS` |
| 4. No sensitive browser storage | Tokens in localStorage or cookies | `STORAGE_PATTERNS` |
| 5. Migrations only get added | Databases drifting apart | `MIGRATIONS_DIR` |
| 6. No secrets in the built app | Keys shipped to users | `BUNDLE_DIR`, `BUNDLE_LEAK_PATTERNS` |
| 7. Schema matches the saved copy | Database changes without a migration | `SCHEMA_DUMP_CMD` |
| 8. Safety settings intact | "Ask me first" being quietly switched off | Built in |
| 9. No client names | Confidential names in code or commits | `.guardrails/denylist.local` |
| 10. Local checks installed | A fresh clone with no local checks | Built in |
| 11. Honest records (governance) | "Done" with no proof attached | `docs/governance/` |
| 12. Dependency policy holds | Brand-new releases, git or URL packages, unapproved install scripts, a tampered lockfile | `.npmrc`, `package-lock.json` |
| Ask before adding a package | Made-up or misspelt package names | Command guard |
| Secret scanner | API keys, tokens, passwords in commits | `.gitleaks.toml` |
| Dependency scanner | Packages with known vulnerabilities | CI (OSV-Scanner), optional on push |
| Dependabot | Falling behind on security fixes | `.github/dependabot.yml`, plus alerts and security updates switched on in GitHub (step 6) |

Checks 1 to 12 live in `scripts/ci-guardrails.sh`; the names in the right-hand column are settings
at the top of that file unless another file is named. For why each one exists and how it compares
with common practice, see [docs/why-these-rules.md](docs/why-these-rules.md). For the complete
list of every control (where it is enforced, when it runs, what proves it works and where it stops),
see [docs/security-controls.md](docs/security-controls.md).

---

## Changing the rules

Every rule is plain text you can read and change, and bootstrap already filled in the
project-specific values. Some common changes:

**You moved production to a new host.** In `scripts/claude-bash-guard.sh`, add it to
`PROD_GUARD_PATTERNS`:

```bash
PROD_GUARD_PATTERNS='db\.prod\.acme\.com|db2\.prod\.acme\.com'
```

**You want a new public browser setting.** In `scripts/ci-guardrails.sh`, add it to the allowlist.
That one reviewed line is the record that someone decided it is safe to make public:

```bash
PUBLIC_VAR_ALLOWLIST='NEXT_PUBLIC_APP_URL NEXT_PUBLIC_SUPPORT_EMAIL'
```

**You're working for a client.** Create `.guardrails/denylist.local` (it is never committed) with
one pattern per line, and add the same lines as a `GUARDRAILS_DENYLIST` secret on GitHub:

```text
Globex[[:space:]]+Holdings
```

**The one rule about rules:** change the configuration, never weaken a check to make it pass.

Every rule, with examples: [docs/configuring-rules.md](docs/configuring-rules.md).

---

## Optional extras

### The governance tier

For client work, regulated work, or anything that will be audited or handed over. Choose it during
setup and you also get:

- **An evidence log** (`docs/governance/EVIDENCE.md`): a table of phases, each with an observable
  "done when", and the actual proof (test output, CI links) behind every finished phase. Setup
  writes the first entry itself, from the checks it just ran.
- **A decision record** (`docs/governance/DECISIONS.md`): settled decisions and why; known
  exceptions, each with what it costs, when it ends and who owns it; and open questions.
- **Phase briefs** (`docs/governance/briefs/`): a short plan per phase, so the AI works from a
  written brief, not a half-remembered conversation.
- **A pull request template** that asks for evidence.

Check 11 keeps it honest: a phase can't be marked Done without proof attached.

### Extra dependency scanners

If your team already pays for Snyk, Socket, GitHub Code Security or similar, or is happy to run
OWASP Dependency-Check, each can be added as an extra CI step alongside the free defaults. See
"If you already have an account" in [docs/configuring-rules.md](docs/configuring-rules.md).

### Using a different model or provider

Each developer can run their own Claude Code sessions through another provider without affecting
anyone else, using a saved profile:

```bash
./scripts/claude-profile.sh openrouter   # or bedrock, vertex, openai, or one you make
./scripts/claude-or.sh                   # shortcut for OpenRouter
```

**OpenRouter** gives the same Claude models with different billing, one place to see spending, and
**zero data retention (ZDR)**: you can require that only providers who keep no copy of your code are
used. **Amazon Bedrock and Google Vertex** keep your code within an existing cloud agreement. Other
vendors' models (OpenAI, DeepSeek) also work through a gateway, but Anthropic does not support that
and this project has not tested it.

Whatever you choose, the guardrails still apply, because Claude Code enforces them, not the model:

| Layer | Needs Claude Code? | Depends on the model? |
| --- | --- | --- |
| Written rules (`CLAUDE.md`) | Yes | Yes: how well they are followed varies |
| Command guard and "always ask" rules | Yes | No |
| Git hooks and CI | No: they also check code from Cursor, Copilot or a person | No |

For client or regulated work, check first that sending code to that provider is allowed. Setup,
ZDR, and the data questions to ask: [docs/choosing-a-model.md](docs/choosing-a-model.md).

---

## What it doesn't protect against

No safety system is complete. The gaps:

- **Local checks can be skipped** with `git commit --no-verify`. That's why the GitHub checks are the
  final word: protect your `main` branch so they must pass.
- **It is built for mistakes, not for an AI working against you.** The guard reads command text, so
  an unusual spelling, a variable or a script can get past it, and a prompt injection (instructions
  hidden in a file or page the AI reads) could steer it round the rules. The checks on GitHub and
  branch protection are what limit the damage in that case. The real protection for production is a rule: the AI prepares
  production commands, and a person runs them.
- **It only watches the AI.** Commands you type in your own terminal aren't checked.
- **A leaked secret can't be un-leaked.** If one reaches the chat history, change it.
- **Check 11 checks structure, not quality.** A reviewer still decides whether the proof proves it.
- **Dependency protection is set up for npm.** pnpm, yarn and bun have equivalent settings (see
  [docs/configuring-rules.md](docs/configuring-rules.md)), but check 12 doesn't read them. And a
  vulnerability scanner only knows what has been reported: the 7-day wait is what protects you from
  a malicious release nobody has spotted yet.

---

## Words you'll see

| Term | Plain meaning |
| --- | --- |
| Bootstrap | The one-time setup that turns this kit into your project |
| Hook | A small script that runs automatically at a set moment (before a command, before a commit) |
| Guardrails | The automatic checks |
| CI | The checks GitHub runs on every pull request |
| Lefthook | The tool that runs checks on your machine when you commit or push |
| gitleaks | The tool that scans for passwords and API keys |
| Transcript | The stored chat history between you and the AI |
| Denylist | Your private list of words that must never be committed |
| Fail closed | If a check breaks, treat it as a failure, not a pass |
| Regex / pattern | A short text pattern; `a\|b` means "a or b", `\.` means a real dot |

---

## Contributing, security and licence

- **Contributing:** changes go through pull requests with review, and every commit is signed off.
  See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Found a way around a guardrail?** Please report it privately: see [SECURITY.md](SECURITY.md).
- **Licence:** MIT. See [LICENSE](LICENSE).
