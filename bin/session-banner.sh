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

# Live peer sessions (local file reads only, no git, no network). Surfaced because the
# concurrency guard fires at COMMIT time — by then a session has already done its editing
# in whatever tree it chose. Knowing at session START that someone else is writing is what
# makes taking a worktree an informed choice rather than a rule to remember.
peers=""
if [ -n "$WIKI" ]; then
  ldir="${WIKI_WORKTREE_ROOT:-$WIKI/.worktrees}/.leases"
  if [ -d "$ldir" ]; then
    me="${WIKI_WT_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
    stale_sec=$(( ${WIKI_LEASE_STALE_MIN:-120} * 60 ))
    now="$(date +%s)"; n=0
    for lf in "$ldir"/*.lease; do
      [ -f "$lf" ] || continue
      s="$(awk -F= '$1=="session"{sub(/^[^=]*=/,"");print;exit}' "$lf" 2>/dev/null)"
      [ -n "$me" ] && [ "$s" = "$me" ] && continue
      hb="$(awk -F= '$1=="heartbeat"{sub(/^[^=]*=/,"");print;exit}' "$lf" 2>/dev/null)"
      [ -n "$hb" ] || continue
      [ $(( now - hb )) -lt "$stale_sec" ] && n=$((n+1))
    done
    if [ "$n" -gt 0 ]; then
      peers="$(printf '  ·  ⚠ %d other session(s) writing — take a worktree' "$n")"
    fi
  fi
fi

if [ -z "$frag" ]; then
  printf 'wiki-engine %s ✓%s\n' "$eng" "$peers"
else
  printf 'wiki-engine %s  ·  ⚠ %s%s\n' "$eng" "$frag" "$peers"
fi
