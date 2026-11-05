#!/usr/bin/env bash
set -euo pipefail

# Smoke test for session-name-date-prefixer: install the hook with each setup script that fits
# this OS (sh everywhere, ps1 on Windows) into a throwaway config dir seeded with someone else's
# settings, run the exact command it wrote the way Claude Code does, and uninstall. HOME and
# LOCALAPPDATA point at temp dirs, so the user's real wrapper, rc files and PATH are untouched.
# Needs jq; on Windows also pwsh and powershell (Windows PowerShell 5.1).

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
# A Windows path for native programs on Git Bash, the path itself elsewhere.
native() { if command -v cygpath >/dev/null; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

windows=""; [ -n "${LOCALAPPDATA:-}" ] && windows=1
scripts="sh"; [ -n "$windows" ] && scripts="sh ps1"

mkdir -p "$WORK/my proj"
seed='{"model":"opus","hooks":{"SessionStart":[{"matcher":"resume","hooks":[{"type":"command","command":"echo theirs"}]}]}}'

# setup <ps1|sh> <dir> <install|uninstall>
setup() {
  if [ "$1" = ps1 ]; then
    LOCALAPPDATA="$(native "$WORK/lad")" pwsh -NoProfile -File "$HOOK_DIR/session-name-date-prefixer-setup.ps1" \
      -ClaudeDir "$(native "$2")" -Action "$3"
  else
    HOME="$WORK/home" bash "$HOOK_DIR/session-name-date-prefixer-setup.sh" "$3" --claude-dir "$2"
  fi
}

# others_intact <file>: the seeded key and hook survive, and SessionStart is still an array.
others_intact() {
  jq -e '.model == "opus"
    and (.hooks.SessionStart | type == "array")
    and any(.hooks.SessionStart[]; .hooks[0].command == "echo theirs")' "$1" >/dev/null
}

# run_hook <ps1|sh> <runner> <command> <stdin>: run the hook from "my proj".
run_hook() {
  (cd "$WORK/my proj" && if [ "$1" = ps1 ]; then printf '%s' "$4" | "$2" -NoProfile -Command "$3"
                         else printf '%s' "$4" | bash -c "$3"; fi)
}

for s in $scripts; do
  dir="$WORK/claude-$s"; mkdir -p "$dir"; printf '%s' "$seed" > "$dir/settings.json"
  # A fake old wrapper where each setup looks for it.
  mkdir -p "$WORK/lad/claude-automation/cc-inject-date-to-session-name" "$WORK/home/.local/bin"
  echo "# Claude wrapper — auto-injects --name" > "$WORK/lad/claude-automation/cc-inject-date-to-session-name/claude.ps1"
  echo "# Claude wrapper — auto-injects --name" > "$WORK/home/.local/bin/claude"

  setup "$s" "$dir" install >/dev/null || fail "$s: install exited non-zero"
  setup "$s" "$dir" install >/dev/null || fail "$s: second install exited non-zero"
  others_intact "$dir/settings.json" || fail "$s: install damaged other settings"
  [ "$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | contains("session-name-date-prefixer"))] | length' "$dir/settings.json")" = 1 ] \
    || fail "$s: expected exactly one session-name hook"
  [ "$(jq -r '.hooks.SessionStart[-1].matcher' "$dir/settings.json")" = 'startup|clear' ] || fail "$s: matcher is not startup|clear"
  if [ "$s" = ps1 ]; then
    [ ! -e "$WORK/lad/claude-automation/cc-inject-date-to-session-name" ] || fail "ps1: old wrapper folder left behind"
    runners="pwsh powershell"
  else
    [ ! -e "$WORK/home/.local/bin/claude" ] || fail "sh: old wrapper left behind"
    runners="bash"
  fi

  cmd="$(jq -r '.hooks.SessionStart[-1].hooks[0].command' "$dir/settings.json")"
  for r in $runners; do
    for src in startup clear; do
      out="$(run_hook "$s" "$r" "$cmd" "{\"source\":\"$src\"}")" || fail "$s/$r/$src: hook exited non-zero"
      title="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.sessionTitle')" || fail "$s/$r/$src: output is not JSON: $out"
      [[ "$title" =~ ^my-proj-[0-9]{10}$ ]] || fail "$s/$r/$src: unexpected title '$title'"
      out="$(run_hook "$s" "$r" "$cmd" "{\"source\":\"$src\",\"session_title\":\"mine\"}")" || fail "$s/$r/$src: hook exited non-zero"
      [ -z "$out" ] || fail "$s/$r/$src: hook overrode an existing title: $out"
      # /clear inherits the hook's own earlier title: that one is replaced, not kept.
      out="$(run_hook "$s" "$r" "$cmd" "{\"source\":\"$src\",\"session_title\":\"my-proj-0001010000\"}")" || fail "$s/$r/$src: hook exited non-zero"
      new="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.sessionTitle')" || fail "$s/$r/$src: output is not JSON: $out"
      [[ "$new" =~ ^my-proj-[0-9]{10}$ && "$new" != my-proj-0001010000 ]] || fail "$s/$r/$src: kept its own old title: '$new'"
      echo "pass  $s/$r/$src  $title"
    done
  done

  setup "$s" "$dir" uninstall >/dev/null || fail "$s: uninstall exited non-zero"
  others_intact "$dir/settings.json" || fail "$s: uninstall damaged other settings"
  ! grep -q session-name-date-prefixer "$dir/settings.json" || fail "$s: hook left behind"

  # Install + uninstall on an empty file leaves no hooks key behind.
  printf '{}' > "$dir/settings.json"
  setup "$s" "$dir" install >/dev/null && setup "$s" "$dir" uninstall >/dev/null
  [ "$(jq -c . "$dir/settings.json")" = '{}' ] || fail "$s: empty settings not restored: $(cat "$dir/settings.json")"
done

echo "PASS"
