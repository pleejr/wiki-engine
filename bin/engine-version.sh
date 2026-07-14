#!/usr/bin/env bash
# engine-version.sh — report the vault's pinned engine vs the latest on origin/main.
# Deterministic (plain git, no LLM, no claude) — safe to run at session start. Meant
# to run from a vault's pinned submodule copy (engine/bin/engine-version.sh), where
# this script's own repo IS the pinned engine.
#
# Exit: 0 up to date · 1 update available · 2 error (no remote / offline).
#
# Usage: engine-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"

git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1 || { echo "engine-version: $ENGINE is not a git repo" >&2; exit 2; }

pinned="$(git -C "$ENGINE" rev-parse --short HEAD)"

if ! git -C "$ENGINE" fetch -q origin main 2>/dev/null; then
  echo "engine: pinned $pinned — could not reach origin (offline?); skipping update check"
  exit 2
fi

latest="$(git -C "$ENGINE" rev-parse --short FETCH_HEAD)"

if [ "$pinned" = "$latest" ]; then
  echo "engine: up to date ($pinned)"
  exit 0
fi

behind="$(git -C "$ENGINE" rev-list --count HEAD..FETCH_HEAD 2>/dev/null || echo '?')"
echo "engine: pinned $pinned, latest $latest ($behind commit(s) behind) — update available"
echo "  to update: git -C <vault> submodule update --remote engine && <vault>/engine/bin/adopt.sh && git -C <vault> commit -am 'Bump engine'"
exit 1
