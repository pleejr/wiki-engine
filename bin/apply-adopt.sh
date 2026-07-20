#!/usr/bin/env bash
# apply-adopt.sh — auto-adopt the pinned engine's features into this vault/machine.
# Runs every idempotent step in engine/adopt.d/ (in filename order); each step wires a
# feature that a version bump introduced — e.g. a SessionStart/PostToolUse hook — via the
# ADD-ONLY ensure-hook.sh primitive. This is what makes a shipped engine feature actually
# take effect in the NEXT session after a bump, without manual settings.json surgery.
#
# Version-gated: skips silently when the pinned engine matches the last-adopted marker
# ($WIKI/.engine-adopted, per-machine, gitignored) unless --force. Because every step is
# idempotent, the marker is only an optimization — a fresh machine with no marker simply
# runs them all once.
#
# Deterministic. NEVER runs `claude` (safe from a hook). Always exits 0 so it can't block
# session start; per-step failures are reported but never fatal.
#
# Usage:
#   apply-adopt.sh [--wiki DIR] [--force] [--check] [--settings FILE]
#     --check  report pending steps without applying (exit 1 if any would change)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"
ADOPT_D="$ENGINE/adopt.d"

DEFAULT_WIKI="$(cd "$ENGINE/.." 2>/dev/null && pwd || true)"   # engine is $WIKI/engine
WIKI="${WIKI_PATH:-$DEFAULT_WIKI}"
FORCE=0; CHECK=0
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)     WIKI="$2"; shift 2;;
    --settings) SETTINGS="$2"; shift 2;;
    --force)    FORCE=1; shift;;
    --check)    CHECK=1; FORCE=1; shift;;   # --check implies "evaluate regardless of marker"
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "apply-adopt: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$WIKI" ] || { echo "apply-adopt: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 0; }
[ -d "$ADOPT_D" ] || exit 0   # engine has no adoption steps; nothing to do

pinned="$(git -C "$ENGINE" describe --tags --always 2>/dev/null || echo unknown)"
marker_file="$WIKI/.engine-adopted"
adopted="$( [ -f "$marker_file" ] && cat "$marker_file" 2>/dev/null || echo "" )"

# Fast path: already adopted this exact pin and not forced.
if [ "$FORCE" -eq 0 ] && [ "$adopted" = "$pinned" ]; then
  exit 0
fi

# Export the environment every step relies on.
export WIKI ENGINE
export CLAUDE_SETTINGS="$SETTINGS"
export ENSURE_HOOK="$SCRIPT_DIR/ensure-hook.sh"

changes=""; failed=0
for step in "$ADOPT_D"/*.sh; do
  [ -e "$step" ] || continue
  if [ "$CHECK" -eq 1 ]; then export ADOPT_CHECK=1; else unset ADOPT_CHECK; fi
  out="$(bash "$step" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    failed=$((failed+1))
    changes="${changes}
! step $(basename "$step") failed (rc=$rc): $out"
    continue
  fi
  [ -n "$out" ] && changes="${changes}
$(printf '%s' "$out" | sed 's/^/ADOPTED: /')"
done

if [ "$CHECK" -eq 1 ]; then
  if [ -n "$changes" ]; then
    echo "=== engine adopt — pending (pinned $pinned) ==="
    printf '%s\n' "$changes" | sed '/^$/d'
    exit 1
  fi
  echo "engine adopt: nothing pending (pinned $pinned)"
  exit 0
fi

if [ -n "$changes" ]; then
  echo "=== engine adopt (${adopted:-<none>} -> $pinned) ==="
  printf '%s\n' "$changes" | sed '/^$/d'
  [ -f "$SETTINGS.bak" ] && echo "(settings backed up to $SETTINGS.bak)"
fi

# Record the pin as adopted even if nothing changed, so the fast path engages next time.
# On a partial failure, leave the marker unset so the next session retries the steps.
if [ "$failed" -eq 0 ]; then
  printf '%s\n' "$pinned" > "$marker_file" 2>/dev/null || true
fi
exit 0
