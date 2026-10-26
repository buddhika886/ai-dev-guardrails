#!/usr/bin/env bash
# Launch Claude Code against OpenRouter instead of the Anthropic subscription.
#
# `claude` on its own stays on the subscription. This script is the only way into OpenRouter, so the
# default is always the safe one and you cannot be left on the paid route by accident.
#
# --settings applies above project and local settings and below managed settings, and it MERGES:
# keys it sets win, keys it omits keep the lower-level value, so the permissions in
# .claude/settings.local.json still apply. It lasts one session and writes to no file.
#
# The routing config and the OpenRouter key live in .claude/openrouter.settings.json, which is
# gitignored. Copy the .example beside it and fill in your key.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
profile="$root/.claude/openrouter.settings.json"

if [[ ! -f "$profile" ]]; then
  echo "No OpenRouter profile at $profile" >&2
  echo "Copy $profile.example to that path, then set ANTHROPIC_AUTH_TOKEN to your sk-or- key." >&2
  exit 1
fi

# A placeholder key fails as a 401 from OpenRouter, several steps away from the cause. Say so here.
if grep -q 'sk-or-REPLACE-ME' "$profile"; then
  echo "$profile still holds the placeholder key." >&2
  echo "Set ANTHROPIC_AUTH_TOKEN to your real sk-or- key before running this." >&2
  exit 1
fi

exec claude --settings "$profile" "$@"
