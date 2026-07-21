#!/usr/bin/env bash
# session-banner.sh — render the one-line version banner MESSAGE (plain text) to stdout.
# A PURE RENDERER: no network, no JSON, no hook semantics. session-boot.sh calls it right
# AFTER session-preflight.sh has written the staleness cache, then delivers the string to
# the user via the hook `systemMessage` field. Keeping the text in one testable place —
# and out of the hook-output layer — is what lets session-boot guarantee the banner
# reflects the CURRENT session's check (preflight → render, one process, no race).
#
# Instant: engine version from `git describe`, staleness from the preflight cache
# (empty cache = all current). Deterministic; never runs `claude`.
#
# Usage: WIKI_PATH=/path/to/vault session-banner.sh   # prints e.g.
#   wiki-engine v1.13.0 ✓
set -uo pipefail

WIKI="${WIKI_PATH:-}"
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

# engine pinned version (local, instant)
eng="?"; [ -n "$WIKI" ] && eng="$(git -C "$WIKI/engine" describe --tags --always 2>/dev/null || echo '?')"

# staleness summary written by session-preflight.sh (empty = all current)
frag=""; [ -f "$CACHE" ] && frag="$(head -n1 "$CACHE" 2>/dev/null)"

if [ -z "$frag" ]; then
  printf 'wiki-engine %s ✓\n' "$eng"
else
  printf 'wiki-engine %s  ·  ⚠ %s\n' "$eng" "$frag"
fi
