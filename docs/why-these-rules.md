# Why these rules exist

Every rule in this project is there because of something that keeps happening to real teams. This
page explains each one in plain language: what it does, why it exists, and how it compares with
common practice. For how to change a rule, see [configuring-rules.md](configuring-rules.md).

Most of these rules are not new ideas. They are the habits careful teams already follow, written
down and checked automatically, so they still hold on a busy day or when an AI assistant is doing
the typing.

---

## The principles behind all of them

**If a check breaks, it fails.** A check that cannot run, because a tool is missing or a file is
unreadable, reports a failure rather than a pass. The worst kind of safety check is one that has
quietly stopped working while everyone still trusts it.

**If a check is switched off, it says so.** A check that does not apply to this project prints
`SKIPPED (reason)`, never a green tick. Anyone reading the output can tell "not checked" from
"checked and fine".

**Every check is tested both ways.** It must catch the problem it exists for, and it must not block
normal work. A rule that gets in the way gets switched off by the first person it annoys, and then it
protects nothing.

**Defence in depth.** No single layer is trusted on its own. The written rules, the AI's command
guard, the checks on your machine and the checks on GitHub each catch what the others miss.

---

## What the AI may do

An AI coding assistant can run commands on your machine. That is what makes it useful, and it is
also the risk. The command guard reads every command before it runs and either blocks it, asks you,
or lets it through.

### It asks before anything leaves your machine

**What it does.** Commits, pushes, pull requests, publishing a package, deploys, remote database
changes, and changes to secrets or settings on a hosting platform all prompt you, every time.

**Why.** These actions are hard or impossible to undo, and they affect other people. AI agents have
already caused real damage this way: in a widely reported 2025 incident, an AI coding agent deleted
a company's production database during a code freeze, despite being told not to. Writing "always
ask first" in the instructions is not enough, because the instruction is only advice to the model.

**Common practice.** Any change that reaches shared systems goes through a person: code review for
merges, an approval step for deploys. This applies the same idea to the AI's own actions.

### "Don't ask again" cannot quietly switch it off

**What it does.** Guardrail check 8 fails if any saved permission would let a commit, push, deploy,
package install or secret-printing command run without asking.

**Why.** Claude Code lets you click "Yes, and don't ask again". Each click saves a rule. After a few
weeks of convenience clicks, "ask before pushing" can be silently replaced by "always allow
`git push`", and nobody notices until the AI pushes something on its own.

**Common practice.** Security teams call this permission creep, and they review access regularly for
exactly this reason. Here the review is automatic and happens on every commit.

### It is blocked from touching production

**What it does.** Commands that target your live systems (the hosts and variables you named during
setup) are refused outright.

**Why.** A mistake against a test database costs an afternoon; the same mistake against production
can lose customer data. The safe pattern is "prepare, then hand over": the AI writes the exact
command and explains it, and a person runs it.

**Common practice.** Most teams keep production access away from developer laptops altogether and
make changes through reviewed pipelines. The guard is a backstop for that process, not a
replacement: a command can reach production in ways no text pattern can see.

### It is blocked from rewriting shared history

**What it does.** Force-push, `git reset --hard` and `git clean -f` are refused.

**Why.** A force-push can erase other people's work from the shared repository. The reset and clean
commands throw away uncommitted work on your machine, which may be hours of your own changes.

**Common practice.** Protected branches on GitHub refuse force-pushes for the same reason.

### It is blocked from printing secrets into the chat

**What it does.** Reading `.env` or key files, dumping environment variables, and echoing variables
with secret-looking names are refused.

**Why.** The chat with the AI is stored. A password that appears there has been disclosed, and the
only fix is to change it everywhere it is used. Asking you first would not help: if you approved, the
secret would land in the chat anyway. That is why these are blocked rather than asked about.

**Common practice.** "Never print secrets to logs" is a standard rule, and CI systems mask secrets in
their output. The chat is a log, so the same rule applies.

---

## Checks on every commit

These run on your machine when you commit, and again on GitHub for every pull request.

### 1. No secret files in git

**What it does.** Fails if files such as `.env`, private keys or credential files are committed.

**Why.** Once a secret is in git history, deleting the file does not remove it: it stays in every
past commit and every clone. Leaked credentials in public repositories are found by automated
scanners within minutes, and millions are exposed every year.

**Common practice.** Keep secrets out of the repository entirely, usually in a secrets manager or the
hosting platform's settings, and commit a `.env.example` with placeholder values instead.

### 2. Only approved settings reach the browser

**What it does.** Fails if a public environment variable (such as `NEXT_PUBLIC_...` or `VITE_...`)
is used that is not on the approved list, or if a server secret's name appears in browser code.

**Why.** Frameworks copy public variables into the JavaScript every visitor downloads. One wrong
prefix on an API key publishes it to the world. The allowlist means someone decided, in a reviewed
change, that each public value is safe.

**Common practice.** Frameworks document this trap prominently; the check makes the decision explicit
instead of relying on everyone remembering it.

### 3. Database queries are parameterised

**What it does.** Fails if server code uses raw-SQL escape hatches such as `.raw(` or `.unsafe(`.

**Why.** Building SQL by pasting values into a string is how SQL injection happens: a crafted input
becomes part of the command and can read or delete data. Injection has been on the OWASP Top 10 list
of web security risks since the list began in 2003.

**Common practice.** Every database library offers parameterised queries, where values are passed
separately and can never become part of the command. This check keeps it that way.

### 4. No sensitive data in browser storage

**What it does.** Fails if browser code uses `localStorage`, `sessionStorage`, IndexedDB or
`document.cookie`.

**Why.** Anything stored there can be read by any script running on the page, including a malicious
one injected through a vulnerability. A session token in `localStorage` can be stolen in one line.

**Common practice.** OWASP advises keeping session tokens out of browser storage and using cookies set
by the server with the `HttpOnly` flag, which page scripts cannot read.

### 5. Migrations are only ever added

**What it does.** Fails if a database migration that already exists is edited or deleted.

**Why.** A migration that has already run on someone's database will not run again. If it is edited
afterwards, databases that ran the old version and databases that run the new one quietly end up
different, and the bugs that follow are hard to trace.

**Common practice.** Migration tools such as Flyway refuse to run when an applied migration has
changed. The rule is "roll forward": fix a mistake with a new migration.

### 6. No secrets in the built app

**What it does.** Scans the build output for secret-looking strings before it ships.

**Why.** Even when the source looks clean, a build step can inline a value from the environment into
the files sent to users. Checking the actual output catches what checking the source misses.

**Common practice.** Scanning build artefacts, not just source, is a standard step in mature release
pipelines.

### 7. The database structure matches the saved copy

**What it does.** Regenerates the database schema and compares it with the committed copy.

**Why.** If someone changes the database by hand, or a migration does something unexpected, the
schema drifts away from what the code and the reviewers believe it is. This check makes that drift
visible in the pull request where it happened.

**Common practice.** Called drift detection; tools such as Prisma and Atlas offer it for the same
reason.

### 8. The AI safety settings are intact

See "Don't ask again cannot quietly switch it off" above. It also fails if the command guard is
unwired or the core "ask" rules are deleted from `.claude/settings.json`.

### 9. No client names in the code

**What it does.** Fails if any name on your private denylist appears in the repository. It reports
only the file and line, never the name.

**Why.** Client names leak into code through comments, test data, branch names and example text.
Repositories get shared, open-sourced, or shown in screenshots, and a contract or NDA may forbid
naming the client at all. The list itself is never committed, because a committed list of client
names would be the very leak it prevents.

**Common practice.** Agencies and consultancies usually work under project codenames for exactly
this reason.

### 10. Local checks are installed

**What it does.** Fails on your machine until the git hooks have been installed in this clone.

**Why.** Git does not copy hooks when you clone a repository. Without this check, a fresh clone has
no local checks at all, and nothing tells you.

**Common practice.** Teams usually rely on a setup step in the README and hope people follow it. This
check turns the hope into a reminder that cannot be missed.

### 11. Records are honest (governance tier only)

**What it does.** A phase marked Done must link to real evidence, such as test output or a CI run,
and every known exception must state its cost, when it ends and who owns it.

**Why.** "Done" is the most over-used word in software. Without evidence attached, the next person,
the client or an auditor has no way to tell finished work from work that was only reported finished.

**Common practice.** Regulated and audited work already asks for evidence and decision records; this
keeps them in the repository next to the code, where they stay up to date.

### 12. The dependency policy holds

**What it does.** Fails if the dependency rules in `.npmrc` are weakened, if any entry in
`package-lock.json` comes from somewhere other than the npm registry, lacks a strong sha512
fingerprint or points one package's name at a different package's download, or if npm on this
machine is too old to enforce the 7-day wait.

**Why.** Your project has two files describing its dependencies: `.npmrc` is the rules, and
`package-lock.json` is the shopping list (exact versions, where to download them, and a fingerprint
of each file). A rule in a file only helps while it is still there, and one edited line or a bad
merge can switch it off. The lockfile is a good hiding place because its changes run to thousands of
machine-written lines that reviewers rarely read: researchers showed in 2019 that one changed
download address can swap a popular package for a malicious one without anyone noticing ("lockfile
injection"). The npm version matters because older npm does not reject the 7-day setting; it
silently ignores it.

**Common practice.** Committing a lockfile and installing exactly it in CI (`npm ci`) is standard.
Checking the lockfile is what the tool `lockfile-lint` exists for; the same checks are built in
here so projects need no extra dependency to check their dependencies.

---

## Dependencies

Every package you install is code written by someone else that runs with your project's
permissions. Most attacks on JavaScript projects now come through dependencies rather than through
the project's own code.

### A 7-day wait on new releases

**What it does.** npm installs only versions released at least 7 days ago.

**Why.** It stops the two most common attacks of recent years:

- **Hijacked releases.** An attacker steals a maintainer's login and publishes a poisoned version
  of a popular package. In 2025 this hit packages downloaded billions of times a week (`chalk`,
  `debug`, and the self-spreading "Shai-Hulud" worm). Bad versions like these are usually spotted
  and removed within hours or days. If you wait a week, you never install them.
- **Made-up package names.** An AI suggests a package that does not exist, and attackers register
  those names in advance ("slopsquatting"). Such packages are almost always brand new, so the wait
  blocks them.

**Common practice.** Became mainstream in 2025 after those attacks. Dependabot waits 3 days by
default, pnpm 1 day (its docs note most malicious releases are removed within an hour), and npm
added its own setting in version 11.10. This project uses 7, and
Dependabot is set to wait the same 7 days so it never proposes a version npm would refuse.

### Only from the npm registry

**What it does.** Packages cannot be installed straight from a git repository or a download URL.

**Why.** Those bypass the registry's own checks, its malware takedowns and its fingerprints, and the
code behind a git link can change at any time.

**Common practice.** npm 12 switched these off by default; this project applies the same on npm 11.

### Install scripts need approval

**What it does.** A dependency's install script runs only if someone has approved that package by
name. The approval is stored in `package.json`, so it is reviewed like any other change.

**Why.** Install scripts run the moment you type `npm install`, before you have used the package at
all. That is how most malicious packages do their damage, including the 2025 worm, which used them
to steal credentials and spread.

**Common practice.** pnpm stopped running dependencies' install scripts by default in version 10
(2025), and npm 12 blocks unapproved scripts by default.

### The AI asks before adding a package

**What it does.** `npm install <name>`, `pnpm add`, `yarn add` and similar commands prompt you, so
you see the exact package name before anything is installed. Overriding the rules for one command
(for example `--min-release-age=0`) is blocked.

**Why.** An AI picks package names from memory, and memory can be wrong or out of date. A prompt
costs a second; installing an attacker's package costs far more.

### Known vulnerabilities fail CI

**What it does.** OSV-Scanner checks `package-lock.json` against the public vulnerability databases
on every pull request, and `npm audit signatures` checks that packages have not been altered since
the registry signed them. An exception you accept has to be written down with an expiry date, after
which CI goes red again.

**Why.** Vulnerabilities are found in existing packages every week. Checking on every pull request
means you find out when you add or update a package, not months later. The expiry date stops an
"we'll fix it later" exception from becoming permanent.

**Common practice.** Vulnerability scanning in CI is universal. OSV-Scanner is Google's free,
open-source scanner and needs no account.

### Dependabot keeps you up to date

**What it does.** Opens pull requests for updates every week, and with alerts and security updates
switched on in GitHub, warns you about vulnerable packages and proposes the fix.

**Why.** Most known vulnerabilities already have a fix; the risk is not applying it. Small regular
updates are also far easier to review than one large catch-up.

**Common practice.** Automated update pull requests (Dependabot or Renovate) are standard on GitHub.

### What if you publish a package?

Nothing here gets in the way. These rules control what you install, not what you publish. npm never
includes `.npmrc` or `package-lock.json` in a published package, so the people who install yours are
not affected by your rules. Your project's own scripts (`prepare`, `build`) still run. The AI has to
ask before `npm publish`, as with any outward action.

If you publish regularly, publish from GitHub Actions with npm's trusted publishing rather than from
a laptop. It needs no stored npm token, and each release carries a public record of the commit and
workflow that built it, which protects against the stolen-login attack described above.

---

## Secrets scanning

**What it does.** gitleaks scans what you are about to commit, and CI scans the whole history.

**Why.** Check 1 catches secret files; this catches secrets pasted into ordinary files, such as an
API key in a config file or a password inside a database address. Scanning history in CI catches
anything that slipped past the local scan, for example with `git commit --no-verify`.

**Common practice.** Secret scanning is standard, and GitHub also offers it with push protection,
which this project's setup steps recommend switching on.

---

## Model profiles

**What it does.** A developer can run Claude Code through another provider (OpenRouter, Amazon
Bedrock, Google Vertex and others) with `./scripts/claude-profile.sh <name>`. The profile applies to
that one session; the launcher refuses a profile that git could commit, or one still holding
placeholder values.

**Why.** A profile holds an API key, and a key in a committed file is a leaked key. Applying it per
session means plain `claude` always stays on the default, so nobody moves the team to another
provider, or another bill, by accident. Choosing a provider also chooses who sees your code, which
is why [choosing-a-model.md](choosing-a-model.md) starts with that question and explains zero data
retention.

**Common practice.** Keys live outside the repository, in a gitignored file or a secrets manager,
with a committed example showing the shape. The guardrails themselves do not depend on the choice:
Claude Code enforces them whatever model is behind it.

---

## CI and the GitHub settings

### CI is the final word

**What it does.** Every pull request re-runs every check on a clean machine, and `main` is protected
so nothing merges until they pass and someone has reviewed it.

**Why.** Local checks can be skipped (`git commit --no-verify`) or missing (a fresh clone). CI cannot
be skipped by anyone working on a pull request, so it is where the rules are actually enforced.

**Common practice.** Protected branches with required checks and review are standard practice for any
shared codebase.

### Actions are pinned to exact versions

**What it does.** Each GitHub Action is referenced by its full commit fingerprint rather than a
version tag, and tools downloaded in CI are checked against a recorded checksum.

**Why.** A version tag can be moved to point at different code. In March 2025 attackers did exactly
that to a popular action (`tj-actions/changed-files`), and thousands of repositories ran the
malicious version, which printed their secrets into public logs. A pinned fingerprint cannot be
moved.

**Common practice.** GitHub's own security guidance recommends pinning Actions to a full commit SHA.

### A read-only CI token

**What it does.** The setup steps ask you to make the CI token read-only by default.

**Why.** If a CI job is ever compromised, as in the attack above, a read-only token cannot push code,
change releases or alter settings. It limits the damage to what can be read.

**Common practice.** "Least privilege": give every account and token only the access it needs.

---

## The governance tier (optional)

**What it does.** Adds an evidence log, a decision record and short phase briefs, and check 11 keeps
them honest.

**Why.** On client, regulated or audited work, the questions come later: what was decided, why, and
how do we know it was done? Records written at the time, next to the code, answer those questions;
memory and chat history do not.

**Common practice.** Decision records (often called ADRs) and evidence of testing are standard in
regulated industries and good practice everywhere else.
