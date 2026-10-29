# TypeScript language fragment

What `/bootstrap` reads from here when the stack is TypeScript. The values below fill the language
tokens in the core files; the files listed are copied into the project.

## Files copied into the project

| Source (this dir)      | Destination            | Notes                                              |
| ---------------------- | ---------------------- | -------------------------------------------------- |
| `biome.json`           | `biome.json`           | Strict defaults: recommended + security rules on. Bootstrap installs `@biomejs/biome` pinned to the version in its `$schema` URL; to move to a newer Biome, run `npx biome migrate` in a reviewed change and bump the pin and its `allowScripts` entry together. |
| `.nvmrc`               | `.nvmrc`               | Pins Node 24 (ships npm 11.10+, which the cooldown needs). |
| `.npmrc`               | `.npmrc`               | Dependency policy: 7-day release cooldown, registry-only dependencies, reviewed install scripts. Check [12] enforces it. |
| `package-scripts.json` | merged into `package.json` | `scripts` block; `build` is a hand-filled placeholder. |
| `eslint-escape-hatch.md` | `docs/eslint-escape-hatch.md` | Reference, only if the team wants ESLint later. |
| `tsconfig-note.md`     | `docs/tsconfig-note.md` | Why typecheck uses the project's own tsconfig.      |

## Token values (fill the core tokens)

| Token                 | Value for TypeScript                                        |
| --------------------- | ----------------------------------------------------------- |
| `{{LANG_LINT_GLOB}}`  | `*.{ts,tsx,js,jsx,json,jsonc}`                              |
| `{{LANG_LINT_CMD}}`   | `npx --no-install biome check --no-errors-on-unmatched`     |
| `{{UNSAFE_SQL}}`      | `(\.unsafe\(\|\.raw\()` (raw/unsafe query escape hatches)  |
| `{{STORAGE_PATTERNS}}`| `localStorage\|sessionStorage\|indexedDB\|document\.cookie` |
| `{{PUBLIC_VAR_PREFIX}}` | Framework-dependent: see the prefix table below.          |

Lint runs in **check mode** (no `--write`), so the pre-commit hook is read-only and safe to run in
parallel with the other checks. Typecheck uses the project's own `tsconfig.json` with `--noEmit`
(see `tsconfig-note.md`, copied to `docs/`); the guardrails layer does not ship its own tsconfig.

## Public-env prefix by framework

| Framework            | `{{PUBLIC_VAR_PREFIX}}` | Typical `{{BUNDLE_DIR}}` |
| -------------------- | ----------------------- | ------------------------ |
| Next.js              | `NEXT_PUBLIC_`          | `out` (static export) or leave empty for SSR (scan client chunks) |
| Vite / React / SvelteKit (Vite) | `VITE_`      | `dist`                   |
| Astro                | `PUBLIC_`               | `dist`                   |
| Remix                | (none; server-only env) | `build/client`           |
| Plain / library      | `` (empty; skips check 2) | `dist` or empty          |

Bootstrap presents this table during the interview and fills `{{PUBLIC_VAR_PREFIX}}` and
`{{BUNDLE_DIR}}` from the chosen framework (or "none yet").
