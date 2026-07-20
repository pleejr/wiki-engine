#!/usr/bin/env bash
# session-boot.sh — the engine's single SessionStart entrypoint. Wire THIS one hook and
# the engine owns the rest. In ONE deterministic pass it:
#   1. apply-adopt.sh       — auto-wire features the pinned engine introduced.
#   2. session-preflight.sh — check Claude Code + wiki-engine staleness; writes the cache.
#   3. renders the version banner from the JUST-written cache (session-banner.sh) and
#      emits it to the USER via the hook `systemMessage` field, while the adopt/preflight
#      detail goes to the MODEL via `hookSpecificOutput.additionalContext`.
#
# Doing (2) then (3) in the same process is the point: a separate banner hook raced the
# preflight (Claude Code runs SessionStart hooks without ordering guarantees), so the
# banner could read a cache a sibling was still writing and show a stale verdict. Folding
# them here makes the banner always reflect the current session's check — at no extra
# latency, since preflight already runs every start.
#
# Deterministic. NEVER runs `claude` (hard rule: no claude in a hook — the fork-bomb
# trap). Always exits 0 so it can't block session start.
#
# Usage (from a SessionStart hook): WIKI_PATH=/path/to/vault session-boot.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

ctx=""   # accumulates human-readable text destined for the model (additionalContext)

# 1. Auto-adopt features the pinned engine shipped since this machine last adopted.
if [ -x "$SCRIPT_DIR/apply-adopt.sh" ]; then
  if [ -n "$WIKI" ]; then a="$("$SCRIPT_DIR/apply-adopt.sh" --wiki "$WIKI" 2>&1)" || true
  else a="$("$SCRIPT_DIR/apply-adopt.sh" 2>&1)" || true; fi
  [ -n "${a:-}" ] && ctx="${ctx}${a}
"
fi

# 2. Version staleness (Claude Code + wiki-engine). Side effect: (re)writes the cache.
if [ -x "$SCRIPT_DIR/session-preflight.sh" ]; then
  p="$(WIKI_PATH="$WIKI" "$SCRIPT_DIR/session-preflight.sh" 2>&1)" || true
  [ -n "${p:-}" ] && ctx="${ctx}${p}
"
fi

# 3. Render the banner from the fresh cache (no race — preflight already ran above).
banner=""
if [ -x "$SCRIPT_DIR/session-banner.sh" ]; then
  banner="$(WIKI_PATH="$WIKI" "$SCRIPT_DIR/session-banner.sh" 2>/dev/null || true)"
fi

# Emit one combined hook-JSON: systemMessage -> user, additionalContext -> model.
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg sm "$banner" --arg ac "$ctx" '
    {suppressOutput: true}
    + (if $sm == "" then {} else {systemMessage: $sm} end)
    + {hookSpecificOutput: (
         {hookEventName: "SessionStart"}
         + (if $ac == "" then {} else {additionalContext: $ac} end)
       )}
  '
else
  # No jq: fall back to plain stdout, which SessionStart routes to the model's context.
  # The user banner needs the systemMessage field, so it's unavailable without jq.
  printf '%s\n' "$ctx"
fi
exit 0
