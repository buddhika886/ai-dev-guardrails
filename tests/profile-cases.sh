#!/usr/bin/env bash
# The model-profile launcher (scripts/claude-profile.sh) and its OpenRouter shortcut, as installed.
# A profile holds a live API key, so the launcher's refusals are the point: it must never start a
# session from a profile git could commit, or from one still holding placeholders. A stand-in
# `claude` on PATH records the arguments it was given, so the success path is checked too.
#
#   usage: tests/profile-cases.sh <installed-project-dir>
set -uo pipefail

PROJ="${1:-}"
if [ -z "$PROJ" ] || [ ! -d "$PROJ" ]; then
  echo "usage: tests/profile-cases.sh <installed-project-dir>" >&2
  exit 2
fi
ROOT=$(git rev-parse --show-toplevel)
# shellcheck source=tests/lib/assert.sh
. "$ROOT/tests/lib/assert.sh"
cd "$PROJ" || exit 2
# The launcher resolves the project through git, which reports the canonical path (on macOS,
# /private/var rather than /var), so compare against the same.
TOP=$(git rev-parse --show-toplevel)

SHIM=$(mktemp -d)
trap 'rm -rf "$SHIM"' EXIT
CALLS="$SHIM/claude-calls"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s"\n' "$CALLS" > "$SHIM/claude"; chmod +x "$SHIM/claude"

# A filled-in OpenRouter profile. The key is assembled at runtime so no key-shaped literal sits in
# this file for the repository's own secret scan to find.
key="sk-or-v1-$(printf 'a1b2c3d4%.0s' 1 2 3 4 5 6 7 8)"
filled_profile() {
  mkdir -p .claude/profiles
  sed "s/sk-or-REPLACE-ME/$key/" .claude/profiles/openrouter.settings.json.example > .claude/profiles/openrouter.settings.json
}
clean_profiles() { rm -f .claude/profiles/*.settings.json .claude/openrouter.settings.json "$CALLS"; reset_project; }

# launch <want: refuse|start> <label> <expected text> <command...>
launch() {
  local want="$1" label="$2" text="$3" out rc; shift 3
  rm -f "$CALLS"
  out=$(PATH="$SHIM:$PATH" "$@" 2>&1); rc=$?
  if [ "$want" = refuse ]; then
    if [ "$rc" -ne 0 ] && [ ! -e "$CALLS" ] && grep -qF -- "$text" <<<"$out"; then t_pass "$label"
    else t_fail "$label (rc=$rc, claude started: $([ -e "$CALLS" ] && echo yes || echo no))" "$out"; fi
  else
    if [ "$rc" -eq 0 ] && [ -e "$CALLS" ] && grep -qxF -- "$text" "$CALLS"; then t_pass "$label"
    else t_fail "$label (rc=$rc)" "$out$( [ -e "$CALLS" ] && cat "$CALLS")"; fi
  fi
}

echo "── the shipped examples are safe to ship"
for f in .claude/profiles/*.settings.json.example; do
  n=$(basename "$f" .settings.json.example)
  if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$f" 2>/dev/null && grep -q 'REPLACE-ME' "$f"; then
    t_pass "$n example is valid JSON and holds placeholders, not a key"
  else
    t_fail "$n example is not valid JSON, or ships without a placeholder" "$(cat "$f")"
  fi
done
if git check-ignore -q .claude/profiles/openrouter.settings.json && ! git check-ignore -q .claude/profiles/openrouter.settings.json.example; then
  t_pass "real profiles are gitignored; the examples are not"
else
  t_fail "gitignore does not separate profiles from their examples" "$(cat .gitignore)"
fi

echo "── the launcher refuses anything that could leak or misfire"
launch refuse "no name lists the profiles"                  "openrouter  (example only" bash scripts/claude-profile.sh
launch refuse "a name that steps outside .claude/profiles/" "Invalid profile name"      bash scripts/claude-profile.sh ../../etc
launch refuse "an unknown profile is named and listed"      "No profile named 'nope'"   bash scripts/claude-profile.sh nope
launch refuse "an example not yet copied says how"          "cp .claude/profiles/bedrock.settings.json.example" bash scripts/claude-profile.sh bedrock
cp .claude/profiles/openai.settings.json.example .claude/profiles/openai.settings.json
launch refuse "placeholders are refused, naming each key"   "ANTHROPIC_DEFAULT_OPUS_MODEL" bash scripts/claude-profile.sh openai
clean_profiles

filled_profile; printf '{"env": {\n' > .claude/profiles/openrouter.settings.json
launch refuse "a profile that is not valid JSON"            "is not valid JSON"         bash scripts/claude-profile.sh openrouter
clean_profiles

filled_profile; git add -f .claude/profiles/openrouter.settings.json
launch refuse "a profile tracked by git is refused"         "is tracked by git"         bash scripts/claude-profile.sh openrouter
clean_profiles

filled_profile; portable_sed '/^\.claude\/profiles\/\*\.settings\.json$/d' .gitignore
launch refuse "a profile git would not ignore is refused"   "is not ignored by git"     bash scripts/claude-profile.sh openrouter
clean_profiles

echo "── a good profile starts Claude Code with it, for this session only"
filled_profile
launch start "the profile is passed with --settings"        "$TOP/.claude/profiles/openrouter.settings.json" bash scripts/claude-profile.sh openrouter
launch start "extra arguments reach claude"                 "--continue"                bash scripts/claude-profile.sh openrouter --continue
launch start "claude-or.sh is a shortcut for the same"      "$TOP/.claude/profiles/openrouter.settings.json" bash scripts/claude-or.sh
if git status --porcelain | grep -q .; then t_fail "the launcher left changes in the working tree" "$(git status --porcelain)"
else t_pass "nothing is written to the project"; fi
clean_profiles

echo "── the OpenRouter profile's old location is pointed at the new one"
sed "s/sk-or-REPLACE-ME/$key/" .claude/profiles/openrouter.settings.json.example > .claude/openrouter.settings.json
launch refuse "claude-or.sh explains the move"              "has moved to .claude/profiles/" bash scripts/claude-or.sh
clean_profiles

t_summary "PROFILE CASES"
