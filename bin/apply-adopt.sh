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
#
# Env:
#   CLAUDE_SKILLS_DIR   where skill symlinks go (default ${CLAUDE_CONFIG_DIR:-~/.claude}/skills).
#                       For an EPHEMERAL vault, each machine-shared surface is gated on its
#                       OWN redirect: --settings contains settings.json, this contains the
#                       skills dir. Containing one never licenses writing the other.
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
export ADOPT_LIB="$SCRIPT_DIR/adopt-lib.sh"

# adopt-lib.sh carries require_engine_asset, which is how a step distinguishes "the
# consumer doesn't have this" (no-op) from "the engine failed to ship this" (hard fail).
# Checked ONCE here rather than by each step: if the helper itself is missing, every step
# that sources it fails identically, and one message is more useful than N.
# Exits 0 from a session hook (it must never block session start) but non-zero under
# --check, which is a human/wire-machine convergence question: "is this machine adopted?"
# answered by a tool that cannot even load its own helper must not come back green.
if [ ! -f "$ADOPT_LIB" ]; then
  echo "apply-adopt: FATAL — missing $ADOPT_LIB (engine packaging bug)" >&2
  [ "$CHECK" -eq 1 ] && exit 1
  exit 0
fi

# --- may a step modify THIS MACHINE's shared config? ----------------------------------
# Decided ONCE, here, rather than re-derived by each step. Two earlier attempts lived in
# the steps themselves and both failed: one tested `[ -n "$CLAUDE_SETTINGS" ]`, which the
# export above makes permanently true, so the guard never fired; the other enumerated
# ephemeral path prefixes that happened to be macOS-shaped and did not match a CI runner's
# temp dir. Steps consult the flags below and do not re-implement the test.
#
# Machine-shared surfaces are the machine's real settings.json and its skills directory. A
# throwaway vault touching either leaves damage that outlives it: a permanent SessionStart
# hook, or skill symlinks aimed at a directory that later disappears (those keep resolving
# until it is cleaned, so nothing announces the breakage).
#
# ONE FLAG PER SURFACE, not one flag for both. A single flag was the bug: redirecting
# --settings is the documented way to contain a throwaway vault, and it flipped the shared
# flag on — licensing the skills step to repoint the machine's REAL ~/.claude/skills at
# the throwaway engine. The settings redirect isolates settings.json; nothing about it
# isolates the skills directory. Each surface is now gated on ITS OWN redirect, so
# containing one cannot silently authorize writing the other.
_claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
_real_settings="$_claude_dir/settings.json"
_real_skills="$_claude_dir/skills"

# Where skill symlinks go. Honors CLAUDE_CONFIG_DIR, which the previous hardcoded
# "$HOME/.claude/skills" in the step did not — so a machine with that variable set had the
# skills step aiming somewhere the rest of the engine never looked.
ADOPT_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$_real_skills}"

ADOPT_WIRE_SETTINGS=1
ADOPT_WIRE_SKILLS=1
case "$WIKI" in
  "${TMPDIR:-/nonexistent-tmpdir}"*|"${RUNNER_TEMP:-/nonexistent-runnertmp}"*|\
  /private/tmp/*|/tmp/*|/var/folders/*|*/scratchpad/*|*/_temp/*)
    # Ephemeral vault: each surface may be written only when the caller redirected THAT
    # surface somewhere other than the real one, which is what "isolated" actually means.
    [ "$SETTINGS" != "$_real_settings" ]          || ADOPT_WIRE_SETTINGS=0
    [ "$ADOPT_SKILLS_DIR" != "$_real_skills" ]    || ADOPT_WIRE_SKILLS=0 ;;
esac
export ADOPT_WIRE_SETTINGS ADOPT_WIRE_SKILLS ADOPT_SKILLS_DIR
# Name the surface AND the redirect that would allow it — a bare "skipping machine-level
# wiring" told the caller nothing about which knob to turn.
[ "$ADOPT_WIRE_SETTINGS" -eq 0 ] && \
  echo "adopt: ephemeral vault ($WIKI) — not writing the machine's settings.json (redirect with --settings)" >&2
[ "$ADOPT_WIRE_SKILLS" -eq 0 ] && \
  echo "adopt: ephemeral vault ($WIKI) — not repointing $ADOPT_SKILLS_DIR (redirect with \$CLAUDE_SKILLS_DIR)" >&2

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
