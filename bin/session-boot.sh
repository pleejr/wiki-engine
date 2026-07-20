#!/usr/bin/env bash
# session-boot.sh — the engine's single SessionStart entrypoint. Wire THIS one hook into
# a vault's settings.json (adopt.sh/update.sh/new-wiki.sh do it for you) and the engine
# owns the rest: on every session start it
#   1. apply-adopt.sh  — auto-wires features the pinned engine introduced since this
#                        machine last adopted (idempotent; takes effect next session).
#   2. session-preflight.sh — reports Claude Code + wiki-engine staleness vs upstream and,
#                        when stale, prints an ACTION-REQUIRED block for the assistant.
#
# Deterministic. NEVER runs `claude` (hard rule: no claude in a hook — the fork-bomb
# trap). Both children are deterministic and always exit 0, and so does this; a hook that
# blocks or recurses is the failure mode we design against.
#
# Usage (from a SessionStart hook): WIKI_PATH=/path/to/vault session-boot.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

# 1. Auto-adopt features the pinned engine shipped since this machine last adopted.
if [ -x "$SCRIPT_DIR/apply-adopt.sh" ]; then
  if [ -n "$WIKI" ]; then
    "$SCRIPT_DIR/apply-adopt.sh" --wiki "$WIKI" || true
  else
    "$SCRIPT_DIR/apply-adopt.sh" || true
  fi
fi

# 2. Report version staleness (Claude Code + wiki-engine).
if [ -x "$SCRIPT_DIR/session-preflight.sh" ]; then
  WIKI_PATH="$WIKI" "$SCRIPT_DIR/session-preflight.sh" || true
fi

exit 0
