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

# Live peer sessions. Surfaced because the concurrency guard fires at COMMIT time — by
# then a session has already done its editing in whatever tree it chose. Knowing at
# session START that someone else is writing is what makes taking a worktree an informed
# choice rather than a rule to remember.
#
# The count comes from lease-lib.sh, the same definition `vault-worktree.sh peers` uses.
# This block used to inline its own loop with the heartbeat test alone, which made the
# banner a second opinion on liveness: a session whose worktree and branch were both gone
# was announced here as a live peer while `peers`, reading the same directory seconds
# later, reported none. Cheapness is preserved rather than traded away — the structural
# test is decided by file reads and only reaches `git branch --list` for a lease whose
# worktree directory is already gone, so a vault with no ghosts pays no git at all.
peers=""
if [ -n "$WIKI" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=bin/lease-lib.sh
  if . "$SCRIPT_DIR/lease-lib.sh" 2>/dev/null; then
    lease_lib_init "$WIKI"
    n="$(count_other_live_leases)"
    if [ "${n:-0}" -gt 0 ]; then
      peers="$(printf '  ·  ⚠ %d other session(s) writing — take a worktree' "$n")"
    fi
  fi
fi

if [ -z "$frag" ]; then
  printf 'wiki-engine %s ✓%s\n' "$eng" "$peers"
else
  printf 'wiki-engine %s  ·  ⚠ %s%s\n' "$eng" "$frag" "$peers"
fi
