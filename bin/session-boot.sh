#!/usr/bin/env bash
# session-boot.sh — the engine's single SessionStart entrypoint, run by the plugin's hook;
# the engine owns the rest. In ONE deterministic pass it:
#   1. apply-adopt.sh       — auto-adopt features this engine release introduced.
#   2. session-preflight.sh — check wiki-engine staleness; writes the cache.
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
# Usage: the plugin's SessionStart hook (hooks/hooks.json); reads the vault from WIKI_PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

# The plugin's hooks/hooks.json runs this script. Keep a stable path to the running engine:
# CLAUDE_PLUGIN_ROOT moves on every plugin update, so anything outside Claude Code that needs
# the engine (a statusLine, a vault pre-commit, the vault CLAUDE.md import) reads this link.
. "$SCRIPT_DIR/plugin-lib.sh"
if engine_running_as_plugin && [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null && ln -sfn "$CLAUDE_PLUGIN_ROOT" "$CLAUDE_PLUGIN_DATA/engine" 2>/dev/null || true
fi

ctx=""   # accumulates human-readable text destined for the model (additionalContext)
adopt_fail=0

# 1. Auto-adopt features the pinned engine shipped since this machine last adopted.
if [ -x "$SCRIPT_DIR/apply-adopt.sh" ]; then
  if [ -n "$WIKI" ]; then a="$("$SCRIPT_DIR/apply-adopt.sh" --wiki "$WIKI" 2>&1)" || true
  else a="$("$SCRIPT_DIR/apply-adopt.sh" 2>&1)" || true; fi
  [ -n "${a:-}" ] && ctx="${ctx}${a}
"
  # A FAILED adoption step must reach the USER, not just the model. apply-adopt.sh always
  # exits 0 (it must never block session start), and everything it prints lands in
  # additionalContext under suppressOutput — model-only. So without this, an engine that
  # ships a broken adoption step still renders the ordinary green banner, and whether the
  # human ever hears about it depends on the assistant choosing to mention it. Since a
  # step now hard-fails when its own bundled asset is missing, the loud half of that
  # design has to be genuinely loud.
  # -E, not BRE `\|`: alternation via `\|` is a GNU extension and is not portable. Anchored
  # to the two shapes apply-adopt.sh actually reports failure in, so an advisory line that
  # happens to contain the word FATAL cannot raise a false alarm.
  adopt_fail="$(printf '%s\n' "${a:-}" | grep -Ec '^! step |^apply-adopt: FATAL' || true)"
fi

# 2. Version staleness (wiki-engine). Side effect: (re)writes the cache.
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

# Prepend the adoption failure, so a broken step is never masked by a green version line.
if [ "${adopt_fail:-0}" -gt 0 ] 2>/dev/null; then
  banner="⚠ engine adopt: ${adopt_fail} step(s) FAILED — run $SCRIPT_DIR/apply-adopt.sh --check${banner:+
}${banner}"
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
