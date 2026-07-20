#!/usr/bin/env bash
# session-banner.sh — render the one-line version banner MESSAGE (plain text) to stdout.
# A PURE RENDERER: no network, no JSON, no hook semantics. session-boot.sh calls it right
# AFTER session-preflight.sh has written the staleness cache, then delivers the string to
# the user via the hook `systemMessage` field. Keeping the text in one testable place —
# and out of the hook-output layer — is what lets session-boot guarantee the banner
# reflects the CURRENT session's check (preflight → render, one process, no race).
#
# Instant: engine version from `git describe`, Claude Code version from
# $CLAUDE_CODE_EXECPATH, staleness from the preflight cache (empty cache = all current).
# Deterministic; never runs `claude`.
#
# Usage: WIKI_PATH=/path/to/vault session-banner.sh   # prints e.g.
#   wiki-engine v1.13.0 ✓  ·  claude code 2.1.216 ✓
set -uo pipefail

WIKI="${WIKI_PATH:-}"
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

# engine pinned version (local, instant)
eng="?"; [ -n "$WIKI" ] && eng="$(git -C "$WIKI/engine" describe --tags --always 2>/dev/null || echo '?')"

# Claude Code version without running the binary
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
  printf 'wiki-engine %s ✓  ·  claude code %s ✓\n' "$eng" "$cc"
else
  printf 'wiki-engine %s  ·  claude code %s  ·  ⚠ %s\n' "$eng" "$cc" "$frag"
fi
