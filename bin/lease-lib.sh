#!/usr/bin/env bash
# lease-lib.sh — the ONE definition of session-lease liveness. SOURCED, never executed.
#
# Why a library rather than a helper each caller re-derives: the lease registry answers a
# single question — "is another session writing right now?" — and every surface that asks
# it must get the same answer. `vault-worktree.sh` (peers, claim, lease, gc) asks it, and
# so does `session-banner.sh` at session start. The banner used to inline its own loop
# over the lease files applying the heartbeat test ALONE, so a session whose worktree and
# branch were both gone — provably finished — was announced as a live peer by the banner
# while `peers`, reading the same directory seconds later, correctly reported none. The
# cost of that is not the wrong line itself: a registry that shows ghosts stops being
# read, and the reader loses the NEXT, genuine warning about a real concurrent writer.
#
# Callers source this and initialise it once with the vault root:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/lease-lib.sh"; lease_lib_init "$WIKI"
#
# Env read here — deliberately in ONE place, so no caller re-derives a default:
#   WIKI_WORKTREE_ROOT    worktree parent dir (default <vault>/.worktrees)
#   WIKI_LEASE_STALE_MIN  a lease unrefreshed this long counts as dead (default 120)
#   WIKI_WT_SESSION       stable session id (falls back to $CLAUDE_CODE_SESSION_ID)

# Resolve the registry's location and thresholds. $1 is the vault root (absolute).
lease_lib_init() {
  LEASE_WIKI="$1"
  LEASE_WT_ROOT="${WIKI_WORKTREE_ROOT:-$LEASE_WIKI/.worktrees}"
  LEASE_DIR="$LEASE_WT_ROOT/.leases"
  LEASE_STALE_MIN="${WIKI_LEASE_STALE_MIN:-120}"
}

now_epoch() { date +%s; }

# This session's id — the same key `ensure` uses for its worktree, so a lease and a
# worktree always belong together.
session_id() {
  local s="${WIKI_WT_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
  [ -n "$s" ] || s="anon-$$"
  printf '%s' "$s" | tr -c 'A-Za-z0-9._-' '-'
}

# key=value read from a lease file (values never contain newlines)
lease_get() { awk -F= -v k="$2" '$1==k { sub(/^[^=]*=/,""); print; exit }' "$1" 2>/dev/null; }

# A session that FINISHED CLEANLY leaves proof: `integrate` merged its branch and `gc`
# removed both the worktree and the branch. When both are gone the lease describes a
# session that cannot still be writing, whatever its heartbeat says — so this is stronger
# evidence than the clock, and it is available immediately instead of LEASE_STALE_MIN
# later. Without it a finished session is reported as a live peer for up to two hours,
# and a registry that shows ghosts stops being read.
#
# Deliberately conservative — it answers "provably finished", never "probably gone":
#   - worktree still on disk     -> not proven (a crashed session leaves its worktree)
#   - branch still exists        -> not proven (unintegrated commits; nothing may delete it)
#   - worktree is the CANONICAL checkout -> unjudgeable, since `lease` run from canonical
#     records canonical, which never disappears. Falls through to the clock.
# Anything not proven dead stays subject to the heartbeat test below, so a crashed
# session is still reaped on time as before.
#
# The one `git` call in this file is the LAST test, reached only for a lease whose
# recorded worktree directory is already gone from disk. Every live session, and every
# session that merely crashed, is decided by file reads alone — which is what lets a
# session-start renderer use this without paying for git on the common path.
lease_finished() {
  local wt br
  wt="$(lease_get "$1" worktree)"; br="$(lease_get "$1" branch)"
  [ -n "$wt" ] && [ -n "$br" ] || return 1
  [ "$wt" != "$LEASE_WIKI" ] || return 1
  [ ! -d "$wt" ] || return 1
  [ -z "$(git -C "$LEASE_WIKI" branch --list "$br" 2>/dev/null)" ] || return 1
  return 0
}

# A lease is LIVE if its session has not provably finished AND it was refreshed within
# LEASE_STALE_MIN. The clock is the fallback, not the only test: it is time-based rather
# than pid-based because the pid recorded here is the helper script's, not the agent's,
# and dies immediately — so for a session that simply stops, liveness can only come from
# it continuing to touch its lease.
#
# Decided in ONE place so `peers`, `for_other_live_leases`, `gc` and the session banner
# cannot disagree about who is live — call sites re-deriving this is how a guard ends up
# wrong differently in each of them.
lease_live() {
  lease_finished "$1" && return 1
  local hb; hb="$(lease_get "$1" heartbeat)"
  [ -n "$hb" ] || return 1
  [ $(( $(now_epoch) - hb )) -lt $(( LEASE_STALE_MIN * 60 )) ]
}

# Walk live leases belonging to OTHER sessions. Callback gets the lease file path.
for_other_live_leases() {
  local cb="$1" f me; me="$(session_id)"
  [ -d "$LEASE_DIR" ] || return 0
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    [ "$(lease_get "$f" session)" = "$me" ] && continue
    lease_live "$f" || continue
    "$cb" "$f"
  done
}

# How many OTHER sessions are live. Same walk and same test as `peers`, so a caller that
# needs only the count never has cause to open the lease files itself.
_lease_tally_n=0
_lease_tally() { _lease_tally_n=$(( _lease_tally_n + 1 )); }
count_other_live_leases() {
  _lease_tally_n=0
  for_other_live_leases _lease_tally
  printf '%d' "$_lease_tally_n"
}
