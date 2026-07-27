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
set -uo pipefail

CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

# ANSI (statusline supports color; keep it minimal). Disable if NO_COLOR is set.
if [ -n "${NO_COLOR:-}" ]; then
  DIM=""; AMBER=""; RED=""; RESET=""
else
  DIM=$'\033[2m'; AMBER=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
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
[ -n "$dir" ] || dir="$PWD"
# abbreviate $HOME -> ~
case "$dir" in "$HOME"*) dir="~${dir#"$HOME"}";; esac

# --- staleness fragment from the preflight cache (may be empty/absent) ----------------
frag=""
# ignore a very stale cache (preflight hasn't run in a week) rather than show old info
if [ -f "$CACHE" ]; then
  fresh=1
  if find "$CACHE" -mtime +7 >/dev/null 2>&1; then
    [ -n "$(find "$CACHE" -mtime +7 2>/dev/null)" ] && fresh=0
  fi
  [ "$fresh" -eq 1 ] && frag="$(head -n1 "$CACHE" 2>/dev/null)"
fi

# --- context-usage fragment -----------------------------------------------------------
# WHY this is here: compaction is the thing a long session should get AHEAD of, not react
# to. `checkpoint` is what makes a session disposable — once it has run, closing the
# session costs nothing and a fresh one starts with the vault as its handoff. Without a
# visible gauge the decision is made by surprise, mid-task, which is exactly when it is
# most expensive. So the thresholds name the ACTION, not just the number.
ctx_frag=""
if [ -n "$ctx" ] && [ "$ctx" -eq "$ctx" ] 2>/dev/null; then
  if   [ "$ctx" -ge 85 ]; then ctx_frag="${RED}ctx ${ctx}% — checkpoint now${RESET}"
  elif [ "$ctx" -ge 70 ]; then ctx_frag="${AMBER}ctx ${ctx}% — checkpoint soon${RESET}"
  else                         ctx_frag="${DIM}ctx ${ctx}%${RESET}"
  fi
fi

# Rate limit only when it is close enough to change a plan — a number that is always on
# screen and never actionable is one people stop reading.
rl_frag=""
if [ -n "$ratelimit" ] && [ "$ratelimit" -eq "$ratelimit" ] 2>/dev/null && [ "$ratelimit" -ge 80 ]; then
  rl_frag="${AMBER}5h limit ${ratelimit}%${RESET}"
fi

# --- render ---------------------------------------------------------------------------
line="${DIM}${dir}${RESET}"
[ -n "$model" ] && line="${line} ${DIM}·${RESET} ${model}"
[ -n "$ctx_frag" ] && line="${line} ${DIM}·${RESET} ${ctx_frag}"
[ -n "$rl_frag" ]  && line="${line} ${DIM}·${RESET} ${rl_frag}"
if [ -n "$frag" ]; then
  case "$frag" in
    *MAJOR*|*⚠*) col="$RED";;
    *)           col="$AMBER";;
  esac
  line="${line}  ${col}⚠ ${frag}${RESET}"
fi

printf '%s\n' "$line"
exit 0
