#!/usr/bin/env bash
# statusline.sh — the engine's Claude Code status-line renderer. Prints one row (shown at
# the bottom of the UI, above the footer badges) with the working dir, model, and — when
# something is stale — a version warning. It exists to make session-preflight.sh's version
# verdict USER-VISIBLE: a SessionStart hook can only feed its output to the assistant (docs:
# stdout is "added as context", never drawn in the UI), so the assistant might never relay
# it. This closes that gap by surfacing the verdict on a persistent, always-drawn surface.
#
# Data flow (fast path — NO network here): session-preflight.sh runs once per session and
# writes a one-line staleness summary to the cache file below (empty file = all current);
# this script only READS that cache, so it stays cheap enough to run on every re-render.
#
# Input: Claude Code sends session JSON on stdin (see `code.claude.com/docs/.../statusline`);
# we read .workspace.current_dir and .model.display_name. Output: one line to stdout, with
# ANSI color (amber = update available, red = MAJOR/breaking). Degrades gracefully with no
# jq and with no cache. Deterministic; never runs `claude`. Always exits 0 — a failing
# status-line command must not disrupt the session.
#
# ---------------------------------------------------------------------------------------
# SEGMENTS — the composition contract
#
# The host allows exactly ONE status line, so a vault that already has its own row could
# not adopt any element of this one without abandoning theirs. ensure-statusline.sh
# correctly refuses to clobber a foreign row — but that refusal was a dead end rather than
# a fork in the road, which meant every element shipped here (the staleness warning, the
# context gauge, anything added later) was permanently unreachable for those vaults, and
# nothing reported that. The two available workarounds were both bad: abandon the local row,
# or hand-copy this implementation into it — a per-machine fork that receives no upstream
# fix and whose divergence is invisible from both ends.
#
#   statusline.sh --segment ctx    < session-json     # just the context gauge
#   statusline.sh --segment stale  < session-json     # just the version warning
#   statusline.sh --segments                          # list the available names
#
# The contract a consuming row can rely on:
#   * stdin is the same session JSON the host sends a status line. Each invocation reads
#     its own stdin, so a row composing several segments feeds the payload to each.
#   * a segment prints ONLY its own fragment, with no separators and no trailing newline
#     beyond the single one. Ordering and separators are the row owner's taste, not ours.
#   * a segment with nothing to say prints NOTHING and exits 0 — absent, null, or
#     non-numeric fields produce silence, never a placeholder like "ctx 0%".
#   * NO_COLOR is honored, and every path exits 0.
#   * an unknown segment name prints nothing to stdout (so a typo cannot corrupt a row)
#     and explains itself on stderr, where running it by hand will show it.
#
# THE FULL RENDERER COMPOSES THESE SAME FUNCTIONS — there is exactly one implementation of
# each element. A segment path that duplicated the renderer's logic would just relocate the
# drift problem it exists to solve, so CI asserts the composed row and the full row are
# character-identical for the same payload.
set -uo pipefail

CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

SEGMENT=""; LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --segment)  SEGMENT="${2:-}"; shift 2;;
    --segments) LIST=1; shift;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) printf 'statusline: unknown arg: %s\n' "$1" >&2; exit 0;;
  esac
done

if [ "$LIST" -eq 1 ]; then
  printf 'dir\nmodel\nctx\nrl\nstale\n'
  exit 0
fi

# ANSI (statusline supports color; keep it minimal). Disable if NO_COLOR is set.
if [ -n "${NO_COLOR:-}" ]; then
  DIM=""; BOLD=""; AMBER=""; RED=""; GREEN=""; RESET=""
else
  DIM=$'\033[2m'; BOLD=$'\033[1m'; AMBER=$'\033[33m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
fi

# --- session context from stdin JSON (dir + model + context usage), best-effort -------
input=""; [ -t 0 ] || input="$(cat)"
dir=""; model=""; ctx=""; ratelimit=""
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  dir="$(printf '%s' "$input"  | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)"
  model="$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)"
  # Pre-calculated by Claude Code; `// empty` so an older client that doesn't send the
  # field degrades to the previous banner rather than printing "0%" and implying a fresh
  # context. Truncated, not rounded — 89.9% must not display as 90.
  ctx="$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null | cut -d. -f1)"
  ratelimit="$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null | cut -d. -f1)"
fi

# --- the segments ----------------------------------------------------------------------
seg_dir() {
  local d="$dir"
  [ -n "$d" ] || d="$PWD"
  case "$d" in "$HOME"*) d="~${d#"$HOME"}";; esac
  printf '%s%s%s' "$DIM" "$d" "$RESET"
}

seg_model() { [ -n "$model" ] && printf '%s' "$model"; return 0; }

# WHY the context gauge exists: compaction is the thing a long session should get AHEAD of,
# not react to. `checkpoint` is what makes a session disposable — once it has run, closing
# the session costs nothing and a fresh one starts with the vault as its handoff. Without a
# visible gauge the decision is made by surprise, mid-task, which is exactly when it is most
# expensive. So the thresholds name the ACTION, not just the number.
#
# EVERY band is BOLD; escalation is carried entirely by hue and by the action text the calm
# band deliberately lacks. The gauge started out DIM below 70%, which was close to unreadable
# on many themes, so it only became legible once it had already escalated to amber:
# "everything is fine" and "this indicator is not working" looked alike, and the absent case
# (no field, non-numeric input, a degraded render) looks like nothing too. An indicator meant
# to be watched passively has to be readable in its calm state or it stops being consulted.
# Bolding the calm band alone then made it the only unbolded pair on the row, so the whole
# gauge is bold and the contrast between bands is purely chromatic. BOLD must be blanked in
# the NO_COLOR branch alongside the others, or raw escapes leak into the row.
seg_ctx() {
  [ -n "$ctx" ] && [ "$ctx" -eq "$ctx" ] 2>/dev/null || return 0
  if   [ "$ctx" -ge 85 ]; then printf '%sctx %s%% — checkpoint now%s'    "$BOLD$RED" "$ctx" "$RESET"
  elif [ "$ctx" -ge 70 ]; then printf '%sctx %s%% — checkpoint soon%s' "$BOLD$AMBER" "$ctx" "$RESET"
  else                         printf '%sctx %s%%%s'                   "$BOLD$GREEN" "$ctx" "$RESET"
  fi
}

# Rate limit only when it is close enough to change a plan — a number that is always on
# screen and never actionable is one people stop reading. Bold, like the context gauge: it is
# threshold-gated, so it appears ONLY when it is actionable, and an element that has earned
# its place on the row should not then be the quietest thing on it.
seg_rl() {
  [ -n "$ratelimit" ] && [ "$ratelimit" -eq "$ratelimit" ] 2>/dev/null || return 0
  [ "$ratelimit" -ge 80 ] || return 0
  printf '%s5h limit %s%%%s' "$BOLD$AMBER" "$ratelimit" "$RESET"
}

# The staleness verdict, read from the preflight cache (may be empty/absent). A cache the
# preflight has not refreshed in a week is IGNORED rather than shown: stale information
# about staleness is worse than none.
seg_stale() {
  local frag="" col
  if [ -f "$CACHE" ]; then
    local fresh=1
    if find "$CACHE" -mtime +7 >/dev/null 2>&1; then
      [ -n "$(find "$CACHE" -mtime +7 2>/dev/null)" ] && fresh=0
    fi
    [ "$fresh" -eq 1 ] && frag="$(head -n1 "$CACHE" 2>/dev/null)"
  fi
  [ -n "$frag" ] || return 0
  case "$frag" in
    *MAJOR*|*⚠*) col="$RED";;
    *)           col="$AMBER";;
  esac
  printf '%s⚠ %s%s' "$col" "$frag" "$RESET"
}

if [ -n "$SEGMENT" ]; then
  case "$SEGMENT" in
    dir|model|ctx|rl|stale) out="$("seg_$SEGMENT")"; [ -n "$out" ] && printf '%s\n' "$out" ;;
    *) printf 'statusline: no such segment "%s" — try: statusline.sh --segments\n' "$SEGMENT" >&2 ;;
  esac
  exit 0
fi

# --- render (composed from the SAME segments a foreign row consumes) --------------------
line="$(seg_dir)"
m="$(seg_model)";  [ -n "$m" ] && line="${line} ${DIM}·${RESET} ${m}"
c="$(seg_ctx)";    [ -n "$c" ] && line="${line} ${DIM}·${RESET} ${c}"
r="$(seg_rl)";     [ -n "$r" ] && line="${line} ${DIM}·${RESET} ${r}"
s="$(seg_stale)";  [ -n "$s" ] && line="${line}  ${s}"

printf '%s\n' "$line"
exit 0
