#!/usr/bin/env bash
# spawn-session.sh — start a NEW interactive session elsewhere, through a host adapter the
# consumer's machine supplies. The engine knows that a session can be spawned; it never knows
# how. Same seam as session-checks.d/: the engine composes a drop-in it does not ship.
#
# Why this exists: a skill that ends by telling the operator to "run that separately, in its
# own session" makes them perform the handoff by hand at the exact moment the separation was
# meant to relieve — the end of unrelated work. So the accepted branch collapses toward the
# deferred one for reasons that have nothing to do with whether the work is worth doing.
#
# THE ADAPTER CONTRACT (deliberately thin — see USAGE.md):
#   path:   $WIKI_ENGINE_SPAWN_ADAPTER, else ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spawn-session
#   argv:   $1 = working directory, $2 = the prompt to submit
#   stdout: line 1 = a HANDLE the operator can use to find the session (pane id, window
#           name, session id). Anything further is ignored.
#   exit:   0 ONLY once the session is actually running. Non-zero if it could not start.
#   env:    CLAUDE_SPAWN_DEPTH, already incremented — pass it through to the child.
#
# FAIL-CLOSED, in the one direction that matters: exit 0 with no handle, a non-zero exit, a
# missing adapter, or an adapter that hangs all land on the SAME printed-by-hand fallback and
# say why. Reporting a handoff that did not happen is the fail-open shape here — it converts
# an accepted verdict into a silently lost one, which is worse than never offering to spawn.
#
# NO EDGE BACK. This waits only for the adapter to report that it started something, then
# exits. It never polls, reads, or waits on the spawned session — that session records its own
# results, which is what makes spawning it safe.
#
# NEVER WIRE THIS TO A LIFECYCLE HOOK. It starts a session, and a hook whose own trigger the
# child can re-fire is the fork-bomb structure the engine's CLAUDE.md bans. Invoked only on an
# explicit human accept. It carries the re-entry sentinel and the concurrency bound that rule
# requires: CLAUDE_SPAWN_DEPTH is incremented and refused above a small cap, and an identical
# (cwd, prompt) spawn is refused inside a short window so a caller that retries an ambiguous
# result cannot start the same work twice.
#
# Usage: spawn-session.sh --cwd DIR --prompt TEXT [--what LABEL] [--force]
# Exit:  0 = a session was started (its handle is on stdout)
#        2 = usage error
#        3 = not started; the by-hand fallback was printed instead, with the reason
set -uo pipefail

CWD=""; PROMPT=""; WHAT="the session"; FORCE=0
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
MARKER="$CFG/.wiki-engine-spawn"
DEDUP_SECS="${WIKI_ENGINE_SPAWN_DEDUP_SECONDS:-90}"
MAX_DEPTH="${WIKI_ENGINE_SPAWN_MAX_DEPTH:-2}"
WAIT_SECS="${WIKI_ENGINE_SPAWN_TIMEOUT:-20}"

die() { echo "spawn-session: $*" >&2; exit 2; }

# A knob read from the environment must be a number or it is not a bound at all: `[ x -ge
# notanumber ]` returns non-zero, so the timeout comparison below would simply never fire and
# the "bounded" wait would be unbounded — the same fail-open the depth guard refuses. Bad
# values fall back to the default and say so, rather than silently disarming a guard.
numeric_or_default() { # <name> <value> <default>
  case "$2" in
    ''|*[!0-9]*|0)
      echo "spawn-session: \$$1='$2' is not a positive whole number — using the default ($3)" >&2
      printf '%s' "$3" ;;
    *) printf '%s' "$2" ;;
  esac
}
DEDUP_SECS="$(numeric_or_default WIKI_ENGINE_SPAWN_DEDUP_SECONDS "$DEDUP_SECS" 90)"
MAX_DEPTH="$(numeric_or_default WIKI_ENGINE_SPAWN_MAX_DEPTH "$MAX_DEPTH" 2)"
WAIT_SECS="$(numeric_or_default WIKI_ENGINE_SPAWN_TIMEOUT "$WAIT_SECS" 20)"

while [ $# -gt 0 ]; do
  case "$1" in
    --cwd)    CWD="${2:-}"; shift 2 ;;
    --prompt) PROMPT="${2:-}"; shift 2 ;;
    --what)   WHAT="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -*) die "unknown flag: $1" ;;
    *)  die "unexpected argument: $1" ;;
  esac
done

[ -n "$CWD" ]    || die "--cwd is required"
[ -n "$PROMPT" ] || die "--prompt is required"
[ -d "$CWD" ]    || die "--cwd is not a directory: $CWD"

# The by-hand fallback. Host-agnostic on purpose: the engine does not know what starts a
# session here, which is the whole reason the adapter exists. `reason` is always printed, so a
# fallback is never mistaken for a spawn, and never silent about which failure produced it.
fallback() {
  local reason="$1"
  printf 'spawn-session: did not start %s — %s\n' "$WHAT" "$reason"
  printf 'Start it by hand instead:\n'
  printf '  1. open a new session with working directory: %s\n' "$CWD"
  printf '  2. submit this prompt:\n'
  printf '     %s\n' "$PROMPT"
  printf 'To have this started for you next time, install a session adapter at\n'
  printf '  %s/spawn-session\n' "$CFG"
  printf 'See the engine USAGE.md section "Spawning a session (spawn-session)" for its contract.\n'
  exit 3
}

# re-entry sentinel ---------------------------------------------------------------------
# A non-numeric value is treated as unusable rather than as zero: the guard exists to bound
# recursion, and a guard that reads garbage as "depth 0" is one that fails open.
DEPTH="${CLAUDE_SPAWN_DEPTH:-0}"
case "$DEPTH" in
  ''|*[!0-9]*)
    fallback "CLAUDE_SPAWN_DEPTH is not a number ('$DEPTH'), so the re-entry guard cannot bound this — refusing to spawn" ;;
esac
if [ "$DEPTH" -ge "$MAX_DEPTH" ]; then
  fallback "already $DEPTH spawn(s) deep (cap $MAX_DEPTH) — refusing to nest another session"
fi

# resolve the adapter -------------------------------------------------------------------
ADAPTER="${WIKI_ENGINE_SPAWN_ADAPTER:-$CFG/spawn-session}"
if [ ! -e "$ADAPTER" ]; then
  fallback "no session adapter installed at $ADAPTER"
fi
if [ ! -x "$ADAPTER" ]; then
  fallback "the adapter at $ADAPTER is not executable (chmod +x it)"
fi

# concurrency bound ---------------------------------------------------------------------
# Keyed on (cwd, prompt) so two different tasks can be started back to back, and recorded
# only AFTER a spawn succeeds so a failed attempt stays retryable. The realistic double-spawn
# here is a caller that re-runs this after an output it read as ambiguous.
KEY="$(printf '%s\n%s\n' "$CWD" "$PROMPT" | cksum | tr -d ' ')"
NOW="$(date +%s)"
if [ "$FORCE" -eq 0 ] && [ -f "$MARKER" ]; then
  while read -r m_when m_key _rest; do
    [ "$m_key" = "$KEY" ] || continue
    case "$m_when" in ''|*[!0-9]*) continue;; esac
    age=$((NOW - m_when))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$DEDUP_SECS" ]; then
      fallback "an identical spawn started ${age}s ago (inside the ${DEDUP_SECS}s window) — refusing to start it twice; pass --force if that was deliberate"
    fi
  done < "$MARKER"
fi

# invoke --------------------------------------------------------------------------------
# Bounded: an adapter that never returns would hold up the caller with no status to attribute
# the stall to, so a hang degrades to the fallback exactly as a failure does.
out_f="$(mktemp)"; err_f="$(mktemp)"
trap 'rm -f "$out_f" "$err_f"' EXIT
CLAUDE_SPAWN_DEPTH="$((DEPTH + 1))" "$ADAPTER" "$CWD" "$PROMPT" >"$out_f" 2>"$err_f" &
pid=$!
waited=0; timed_out=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$waited" -ge "$WAIT_SECS" ]; then
    # TERM, then a short grace, then KILL. `wait` on a process that traps TERM and declines
    # to leave would block forever — a timeout whose own cleanup is unbounded is not one.
    kill -TERM "$pid" 2>/dev/null
    grace=0
    while kill -0 "$pid" 2>/dev/null && [ "$grace" -lt 3 ]; do sleep 1; grace=$((grace + 1)); done
    kill -KILL "$pid" 2>/dev/null
    timed_out=1
    break
  fi
  sleep 1; waited=$((waited + 1))
done
wait "$pid" 2>/dev/null; rc=$?

if [ "$timed_out" -eq 1 ]; then
  fallback "the adapter at $ADAPTER did not return within ${WAIT_SECS}s — it must start the session and exit, never run it in the foreground"
fi

HANDLE="$(sed -n '1p' "$out_f")"
if [ "$rc" -ne 0 ]; then
  detail="$(sed -n '1p' "$err_f")"
  fallback "the adapter exited $rc${detail:+ — $detail}"
fi
if [ -z "$HANDLE" ]; then
  fallback "the adapter exited 0 but named no handle, so there is nothing to say a session is running — treating that as not started"
fi

# record the spawn (append-only; pruned to entries still inside the window) ---------------
if mkdir -p "$CFG" 2>/dev/null; then
  { [ -f "$MARKER" ] && awk -v now="$NOW" -v win="$DEDUP_SECS" \
      '$1 ~ /^[0-9]+$/ && now - $1 < win' "$MARKER"
    printf '%s %s\n' "$NOW" "$KEY"
  } > "$MARKER.tmp" 2>/dev/null && mv -f "$MARKER.tmp" "$MARKER" 2>/dev/null || true
fi

printf 'spawn-session: started %s — handle: %s\n' "$WHAT" "$HANDLE"
printf 'It runs on its own and reports nothing back here. Do not wait on it.\n'
exit 0
