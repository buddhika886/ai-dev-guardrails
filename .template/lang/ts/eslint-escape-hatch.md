# Swapping Biome for ESLint + Prettier

The template ships Biome for TypeScript because it is one fast binary for lint and format with no
plugin management. If your team standardises on ESLint and Prettier, you can swap the lint tool
**without touching the guardrails layer**. The guardrails never call Biome directly: they call lint
through a single glob/command pair in `lefthook.yml` and a single `lint` script in `package.json`.
Change those two, and everything else (the five layers, the CI parity, the hooks) is unaffected.

## Steps

1. Remove Biome and add the ESLint + Prettier toolchain:

   ```bash
   npm rm @biomejs/biome
   npm i -D eslint @eslint/js typescript-eslint prettier eslint-config-prettier
   ```

2. Add a flat config `eslint.config.js` (extend `@eslint/js` recommended and
   `typescript-eslint` recommended; put `eslint-config-prettier` last so formatting rules defer to
   Prettier). Add a `.prettierrc` for formatting.

3. Change the two integration points:

   - **`package.json`**: replace the `lint` script:

     ```json
     "lint": "eslint . && prettier --check .",
     "format": "eslint --fix . && prettier --write ."
     ```

   - **`lefthook.yml`**: replace the `lint` command's `glob` and `run` values (the pair bootstrap
     filled in from the language fragment):

     ```yaml
     lint:
       glob: "*.{ts,tsx,js,jsx}"
       run: npx --no-install eslint {staged_files}
     ```

     Keep it in **check mode** (no `--fix`) in the hook so pre-commit stays read-only and safe to run
     in parallel with the other checks, matching the Biome setup.

4. Delete `biome.json`.

## What you must NOT change

Do not edit `scripts/ci-guardrails.sh`, the guard scripts, `ci/verify.yml`, or the CONFIG blocks to
accommodate the swap. If lint is wired through the two integration points above, the enforcement
layer does not know or care which linter runs. If you find yourself editing an enforcement file to
make the swap work, stop: the wiring is wrong, not the guardrails.
