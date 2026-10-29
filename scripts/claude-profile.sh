#!/usr/bin/env bash
# Start Claude Code with a named model profile: a different provider, gateway or model for this one
# session. See docs/choosing-a-model.md.
#
#   ./scripts/claude-profile.sh                 list the profiles available
#   ./scripts/claude-profile.sh <name> [args]   run `claude --settings .claude/profiles/<name>.settings.json [args]`
#
# `claude` on its own is never affected: a profile applies only to the session this script starts.
# --settings applies above project and local settings and below managed settings, and it MERGES:
# keys it sets win, keys it omits keep the lower-level value, so every hook and permission rule still
# applies. It lasts one session and writes to no file.
#
# A profile usually holds an API key, so it must never be committed. This script refuses to start
# if the profile is tracked by git or would not be ignored by it, and while any value still reads
# REPLACE-ME (a placeholder fails several steps later as a confusing 401 or "model not found").
set -euo pipefail

root=$(git rev-parse --show-toplevel)
dir="$root/.claude/profiles"

list_profiles() {
  local f found=0
  echo "Profiles in .claude/profiles/:" >&2
  for f in "$dir"/*.settings.json; do
    [ -e "$f" ] || continue
    found=1; echo "  $(basename "$f" .settings.json)" >&2
  done
  for f in "$dir"/*.settings.json.example; do
    [ -e "$f" ] || continue
    local n; n=$(basename "$f" .settings.json.example)
    [ -e "$dir/$n.settings.json" ] && continue
    found=1; echo "  $n  (example only: copy it to $n.settings.json and fill it in)" >&2
  done
  [ "$found" -eq 1 ] || echo "  (none)" >&2
}

name="${1:-}"
if [ -z "$name" ]; then
  echo "usage: ./scripts/claude-profile.sh <profile> [claude arguments]" >&2
  list_profiles
  exit 2
fi
# Names map to file paths, so allow nothing that could step outside .claude/profiles/.
case "$name" in
  -*|*[!a-z0-9-]*)
    echo "Invalid profile name '$name': use lowercase letters, digits and hyphens." >&2; exit 2 ;;
esac
shift

rel=".claude/profiles/$name.settings.json"
profile="$root/$rel"
if [ ! -f "$profile" ]; then
  if [ -f "$profile.example" ]; then
    echo "No profile at $rel yet. Create it from the example, then fill in the REPLACE-ME values:" >&2
    echo "  cp $rel.example $rel" >&2
  else
    echo "No profile named '$name'." >&2
    list_profiles
  fi
  exit 1
fi

if git -C "$root" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
  echo "$rel is tracked by git, so its key is in the repository history." >&2
  echo "Remove it from git (git rm --cached $rel), rotate the key, and try again." >&2
  exit 1
fi
if ! git -C "$root" check-ignore -q "$rel"; then
  echo "$rel is not ignored by git, so the next 'git add' could commit its key." >&2
  echo "Add '.claude/profiles/*.settings.json' to .gitignore and try again." >&2
  exit 1
fi
if grep -q 'REPLACE-ME' "$profile"; then
  echo "$rel still holds placeholder values. Fill in:" >&2
  grep -oE '"[A-Za-z0-9_]+"[[:space:]]*:[[:space:]]*"[^"]*REPLACE-ME' "$profile" | cut -d'"' -f2 | sed 's/^/  /' >&2
  exit 1
fi
if command -v node >/dev/null 2>&1 \
   && ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$profile" 2>/dev/null; then
  echo "$rel is not valid JSON." >&2
  exit 1
fi

exec claude --settings "$profile" "$@"
