#!/usr/bin/env bash
# session-banner.sh — show the version verdict to the USER in-session at SessionStart.
# Emits hook JSON {suppressOutput, systemMessage} on stdout and exits 0. `systemMessage`
# is the documented "message shown to the user" channel — user-visible WITHOUT the
# "SessionStart hook error" heading that stderr+exit2 forces, and unlike plain stdout
# (which SessionStart routes to the model's context only, never to the user).
#
# Instant + no network: engine version from `git describe`, Claude Code version from
# $CLAUDE_CODE_EXECPATH, staleness from the cache session-preflight.sh writes (empty cache
# = all current). This is the reliable user-facing surface for the version verdict: it
# complements statusline.sh (a persistent indicator) with a one-shot start-of-session
# announcement, and works even where the statusLine is suppressed (e.g. workspace-trust
# gating). Deterministic; NEVER runs `claude`. Always exits 0 so it can't block startup.
#
# Usage (from a SessionStart hook): WIKI_PATH=/path/to/vault session-banner.sh
set -uo pipefail

WIKI="${WIKI_PATH:-}"
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

# engine pinned version (local, instant)
eng="?"; [ -n "$WIKI" ] && eng="$(git -C "$WIKI/engine" describe --tags --always 2>/dev/null || echo '?')"

# Claude Code version without running the binary: prefer the exec path Claude Code exports
cc="?"
if [ -n "${CLAUDE_CODE_EXECPATH:-}" ]; then
  cc="$(basename "$CLAUDE_CODE_EXECPATH" 2>/dev/null || echo '?')"
else
  link="$(readlink -f "$(command -v claude 2>/dev/null)" 2>/dev/null || true)"
  case "$link" in */versions/*) cc="$(printf '%s' "$link" | sed -E 's#.*/versions/([^/]+).*#\1#')";; esac
fi

# staleness summary written by session-preflight.sh (empty = all current)
frag=""; [ -f "$CACHE" ] && frag="$(head -n1 "$CACHE" 2>/dev/null)"

if [ -z "$frag" ]; then
  msg="wiki-engine $eng ✓  ·  claude code $cc ✓"
else
  msg="wiki-engine $eng  ·  claude code $cc  ·  ⚠ $frag"
fi

# systemMessage = shown to the user; suppressOutput hides the raw JSON from the transcript.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg m "$msg" '{suppressOutput:true, systemMessage:$m}'
else
  # no jq: degrade to plain stdout (SessionStart routes this to the model only, but it's
  # the best available fallback and keeps the hook harmless).
  printf '%s\n' "$msg"
fi
exit 0
