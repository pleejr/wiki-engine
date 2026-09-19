#!/usr/bin/env bash
# apply-adopt.sh — auto-adopt this engine release's features into the vault.
# Runs every idempotent step in adopt.d/ (in filename order); each step brings the vault up
# to what a release introduced — its git hooks, .gitignore entries, normalised repo refs, a
# seeded baseline. This is what makes a shipped engine feature take effect in the NEXT
# session after the plugin updates, without a hand step.
#
# Steps touch only the vault. Machine-level wiring (hooks, skills) is the plugin's own, so
# no step writes settings.json or ~/.claude/skills.
#
# Version-gated: skips silently when the running engine matches the last-adopted marker
# ($WIKI/.engine-adopted, per-machine, gitignored) unless --force. Because every step is
# idempotent, the marker is only an optimization — a fresh machine with no marker simply
# runs them all once.
#
# Deterministic. NEVER runs `claude` (safe from a hook). Always exits 0 so it can't block
# session start; per-step failures are reported but never fatal.
#
# Usage:
#   apply-adopt.sh [--wiki DIR] [--force] [--check]
#     --check  report pending steps without applying (exit 1 if any would change)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"
ADOPT_D="$ENGINE/adopt.d"

. "$SCRIPT_DIR/plugin-lib.sh"
WIKI="${WIKI_PATH:-}"
FORCE=0; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)     WIKI="$2"; shift 2;;
    --force)    FORCE=1; shift;;
    --check)    CHECK=1; FORCE=1; shift;;   # --check implies "evaluate regardless of marker"
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "apply-adopt: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$WIKI" ] || { echo "apply-adopt: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 0; }
[ -d "$ADOPT_D" ] || exit 0   # engine has no adoption steps; nothing to do

pinned="$(engine_release "$ENGINE")"   # a plugin cache is not a git repo; read the manifest
marker_file="$WIKI/.engine-adopted"
adopted="$( [ -f "$marker_file" ] && cat "$marker_file" 2>/dev/null || echo "" )"

# Fast path: already adopted this exact pin and not forced.
if [ "$FORCE" -eq 0 ] && [ "$adopted" = "$pinned" ]; then
  exit 0
fi

# Export the environment every step relies on.
export WIKI ENGINE
export ADOPT_LIB="$SCRIPT_DIR/adopt-lib.sh"

# adopt-lib.sh carries require_engine_asset, which is how a step distinguishes "the
# consumer doesn't have this" (no-op) from "the engine failed to ship this" (hard fail).
# Checked ONCE here rather than by each step: if the helper itself is missing, every step
# that sources it fails identically, and one message is more useful than N.
# Exits 0 from a session hook (it must never block session start) but non-zero under
# --check, which is a human convergence question: "is this machine adopted?"
# answered by a tool that cannot even load its own helper must not come back green.
if [ ! -f "$ADOPT_LIB" ]; then
  echo "apply-adopt: FATAL — missing $ADOPT_LIB (engine packaging bug)" >&2
  [ "$CHECK" -eq 1 ] && exit 1
  exit 0
fi

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
fi

# Record the pin as adopted even if nothing changed, so the fast path engages next time.
# On a partial failure, leave the marker unset so the next session retries the steps.
if [ "$failed" -eq 0 ]; then
  printf '%s\n' "$pinned" > "$marker_file" 2>/dev/null || true
fi
exit 0
