#!/usr/bin/env bash
# Start Claude Code through OpenRouter: the shortcut for `./scripts/claude-profile.sh openrouter`.
# All the checks (no committable profile, no placeholder key) live in claude-profile.sh; see
# docs/choosing-a-model.md, which also covers zero data retention (ZDR) on OpenRouter.
set -euo pipefail

root=$(git rev-parse --show-toplevel)

# Profiles used to live at .claude/openrouter.settings.json. Point anyone with the old file at the
# new place rather than failing with "no profile".
old="$root/.claude/openrouter.settings.json"
new="$root/.claude/profiles/openrouter.settings.json"
if [ -f "$old" ] && [ ! -f "$new" ]; then
  echo "Your OpenRouter profile has moved to .claude/profiles/. Move it with:" >&2
  echo "  mkdir -p .claude/profiles && mv .claude/openrouter.settings.json .claude/profiles/openrouter.settings.json" >&2
  exit 1
fi

exec "$root/scripts/claude-profile.sh" openrouter "$@"
