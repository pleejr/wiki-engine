#!/usr/bin/env bash
# engine-version.sh — report the vault's pinned engine vs the latest on origin/main,
# by semver tag when available. Deterministic (plain git, no LLM, no claude) — safe to
# run at session start. Meant to run from a vault's pinned submodule copy
# (engine/bin/engine-version.sh), where this script's own repo IS the pinned engine.
#
# Exit: 0 up to date · 1 update available · 2 error (no remote / offline).
# A MAJOR-version bump is flagged as breaking — review migration before adopting.
#
# Usage: engine-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"

git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1 || { echo "engine-version: $ENGINE is not a git repo" >&2; exit 2; }

pinned_sha="$(git -C "$ENGINE" rev-parse --short HEAD)"
pinned_ver="$(git -C "$ENGINE" describe --tags --always 2>/dev/null || echo "$pinned_sha")"

if ! git -C "$ENGINE" fetch -q origin main --tags 2>/dev/null; then
  echo "engine: pinned $pinned_ver — could not reach origin (offline?); skipping update check"
  exit 2
fi

latest_sha="$(git -C "$ENGINE" rev-parse --short FETCH_HEAD)"
latest_ver="$(git -C "$ENGINE" describe --tags FETCH_HEAD 2>/dev/null || echo "$latest_sha")"

if [ "$pinned_sha" = "$latest_sha" ]; then
  echo "engine: up to date ($pinned_ver)"
  exit 0
fi

# semver core (v1.2.3-4-gabc -> 1 2 3); empty if the ref isn't tagged
core() { printf '%s' "$1" | sed -E 's/^v//; s/-.*$//'; }
pc="$(core "$pinned_ver")"; lc="$(core "$latest_ver")"

level=""
case "$pinned_ver$latest_ver" in
  v*v*)  # both tagged — classify the bump
    pmaj="${pc%%.*}"; lmaj="${lc%%.*}"
    prest="${pc#*.}"; lrest="${lc#*.}"; pmin="${prest%%.*}"; lmin="${lrest%%.*}"
    if [ "$pmaj" != "$lmaj" ]; then level="MAJOR"
    elif [ "$pmin" != "$lmin" ]; then level="minor"
    else level="patch"; fi
    ;;
esac

behind="$(git -C "$ENGINE" rev-list --count HEAD..FETCH_HEAD 2>/dev/null || echo '?')"

if [ "$level" = "MAJOR" ]; then
  echo "engine: pinned $pinned_ver, latest $latest_ver — ⚠ MAJOR bump ($behind commit(s) behind): review CHANGELOG + migration BEFORE adopting"
elif [ -n "$level" ]; then
  echo "engine: pinned $pinned_ver, latest $latest_ver — $level update ($behind commit(s) behind); safe to adopt"
else
  echo "engine: pinned $pinned_ver, latest $latest_ver ($behind commit(s) behind) — update available"
fi
echo "  to update: git -C <vault> submodule update --remote engine && <vault>/engine/bin/adopt.sh && git -C <vault> commit -am 'Bump engine'"
exit 1
