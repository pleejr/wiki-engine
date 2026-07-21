#!/usr/bin/env bash
# session-preflight.sh — upfront version check for a SessionStart hook. Reports the
# wiki-engine status and, when it is stale, prints an ACTION-REQUIRED block telling the
# assistant to ASK the user before updating — the hook itself never prompts or changes
# anything:
#   - wiki-engine  — pinned submodule vs origin/main, via sibling engine-version.sh.
#
# Deterministic. NEVER runs the `claude` binary (hard rule: no claude in a hook); a hook
# that spawned claude is the fork-bomb trap. Uses only git. Always exits 0 so it can't
# block session start. Meant to run from a vault's pinned copy
# (engine/bin/session-preflight.sh); locates its siblings via SCRIPT_DIR, the vault via
# WIKI_PATH. The update actions it names are for the assistant to run on confirmation.
#
# Usage: WIKI_PATH=/path/to/vault session-preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

action=""   # accumulates ACTION-REQUIRED lines; empty => everything current
summary=""  # compact one-line staleness summary for the status line (see statusline.sh)
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

echo "=== Session preflight (versions) ==="

# wiki-engine — delegate to the sibling engine-version.sh (deterministic, no claude). -
ev="$SCRIPT_DIR/engine-version.sh"
if [ ! -x "$ev" ]; then
  echo "wiki-engine: engine-version.sh not found beside this script — skipping"
else
  ev_out="$("$ev" 2>/dev/null)"; ev_rc=$?
  # show its status line(s); drop its generic hint in favor of our update.sh one-liner
  printf '%s\n' "$ev_out" | grep -v '^  to update:'
  if [ "$ev_rc" -eq 1 ]; then
    # compact "engine <pinned>→<latest>" for the status line; tag MAJOR so it renders red
    eng_frag="$(printf '%s' "$ev_out" | sed -nE 's/.*pinned ([^,]+), latest ([^ ]+).*/engine \1→\2/p' | head -n1)"
    [ -n "$eng_frag" ] || eng_frag="engine update available"
    case "$ev_out" in *MAJOR*) eng_frag="$eng_frag MAJOR";; esac
    summary="${summary:+$summary · }$eng_frag"
    if [ -n "$WIKI" ]; then
      upd="WIKI_PATH=$WIKI $SCRIPT_DIR/update.sh"; commit="git -C $WIKI commit -am 'Bump engine'"
    else
      upd="$SCRIPT_DIR/update.sh --wiki <vault>"; commit="git -C <vault> commit -am 'Bump engine'"
    fi
    action="${action}
ACTION REQUIRED — wiki-engine is out of date (see line above).
Ask the user whether to update now. On confirmation run:
  $upd
It advances the submodule to the latest tag (refuses a MAJOR bump) and STAGES the pin.
Then remind the user to review the CHANGELOG and commit:
  $commit"
  fi
fi

# status-line cache — always (re)write so a resolved staleness clears a prior warning. ---
# statusline.sh reads this: one line = the compact summary, empty file = all current.
if mkdir -p "$(dirname "$CACHE")" 2>/dev/null; then
  printf '%s\n' "$summary" > "$CACHE" 2>/dev/null || true
fi

# actionable summary -------------------------------------------------------------------
[ -n "$action" ] && printf '%s\n' "$action"
exit 0
