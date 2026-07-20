#!/usr/bin/env bash
# engine-version.sh — report the vault's pinned engine vs the latest RELEASE TAG reachable
# on origin/main. Staleness is measured tag-to-tag because that is what `update.sh` adopts
# (it advances tag→tag and refuses untagged commits); comparing against origin/main's HEAD
# instead would flag untagged docs/CI commits sitting past the latest tag as a phantom
# "update available" with nothing to adopt. Deterministic (plain git, no LLM, no claude) —
# safe at session start. Meant to run from a vault's pinned submodule copy.
#
# Exit: 0 up to date (or pinned ahead) · 1 update available · 2 error (no remote / offline).
# A MAJOR-version bump is flagged as breaking — review migration before adopting.
#
# Usage: engine-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"

git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1 || { echo "engine-version: $ENGINE is not a git repo" >&2; exit 2; }

pinned_sha="$(git -C "$ENGINE" rev-parse --short HEAD)"
pinned_ver="$(git -C "$ENGINE" describe --tags --always 2>/dev/null || echo "$pinned_sha")"
# the nearest tag AT or behind the pin (bare, no -N-g suffix); empty if pin has no tag
pinned_tag="$(git -C "$ENGINE" describe --tags --abbrev=0 2>/dev/null || echo '')"

if ! git -C "$ENGINE" fetch -q origin main --tags 2>/dev/null; then
  echo "engine: pinned $pinned_ver — could not reach origin (offline?); skipping update check"
  exit 2
fi

# Latest release tag reachable from the fetched main tip (ignores untagged commits and
# any tags on unmerged branches).
latest_tag="$(git -C "$ENGINE" tag -l 'v*' --merged FETCH_HEAD 2>/dev/null | sort -V | tail -1)"

if [ -z "$latest_tag" ]; then
  echo "engine: pinned $pinned_ver — no release tags on origin/main; skipping update check"
  exit 0
fi
if [ -z "$pinned_tag" ]; then
  echo "engine: pinned $pinned_ver (untagged) — latest tag $latest_tag; review before adopting"
  exit 1
fi

# up to date: pin is at (or past, via untagged commits) the latest tag.
if [ "$pinned_tag" = "$latest_tag" ]; then
  echo "engine: up to date ($pinned_ver)"
  exit 0
fi

# order the two tags; if the pinned tag is the higher one, the pin is ahead — no action.
higher="$(printf '%s\n%s\n' "$pinned_tag" "$latest_tag" | sort -V | tail -1)"
if [ "$higher" = "$pinned_tag" ]; then
  echo "engine: pinned $pinned_ver is ahead of the latest tag ($latest_tag) — no action"
  exit 0
fi

# latest_tag is strictly newer than pinned_tag — classify the bump.
core() { printf '%s' "$1" | sed -E 's/^v//; s/-.*$//'; }
pc="$(core "$pinned_tag")"; lc="$(core "$latest_tag")"
pmaj="${pc%%.*}"; lmaj="${lc%%.*}"
prest="${pc#*.}"; lrest="${lc#*.}"; pmin="${prest%%.*}"; lmin="${lrest%%.*}"
if [ "$pmaj" != "$lmaj" ]; then level="MAJOR"
elif [ "$pmin" != "$lmin" ]; then level="minor"
else level="patch"; fi

# commits from the pin to the latest tag's commit (informational)
behind="$(git -C "$ENGINE" rev-list --count "HEAD..${latest_tag}" 2>/dev/null || echo '?')"

if [ "$level" = "MAJOR" ]; then
  echo "engine: pinned $pinned_ver, latest $latest_tag — ⚠ MAJOR bump ($behind commit(s) behind): review CHANGELOG + migration BEFORE adopting"
else
  echo "engine: pinned $pinned_ver, latest $latest_tag — $level update ($behind commit(s) behind); safe to adopt"
fi
echo "  to update: git -C <vault> submodule update --remote engine && <vault>/engine/bin/adopt.sh && git -C <vault> commit -am 'Bump engine'"
exit 1
