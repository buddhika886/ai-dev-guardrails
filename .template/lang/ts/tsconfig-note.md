# Typecheck and tsconfig

The guardrails layer does **not** ship its own `tsconfig.json`. Typecheck uses the project's own
config in `--noEmit` mode, so the check sees exactly the settings the project builds with:

```
tsc -p . --noEmit
```

This is the `typecheck` script merged into `package.json`, and it is what both the Lefthook pre-push
hook and CI run.

Why not a separate `tsconfig.guardrails.json`? A second config drifts from the real one and gives
false confidence (green guardrails, red build). Checking the project's own config keeps a single
source of truth. If you genuinely need stricter settings for the check than for the build (rare),
add a `tsconfig.guardrails.json` that `extends` the project config and point the `typecheck` script
at it with `-p tsconfig.guardrails.json`; do not let it diverge silently.

Recommended baseline in the project's own tsconfig (if you are starting fresh): `"strict": true`,
`"noUncheckedIndexedAccess": true`, `"noImplicitOverride": true`, `"exactOptionalPropertyTypes":
true`.
