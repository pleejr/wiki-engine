#!/usr/bin/env bash
# update.sh — advance a vault's consumed components in one step, instead of one-by-one:
#   1. bump the engine submodule to the latest tag (within the same MAJOR)
#   2. run adopt.sh (new node folders)
#   3. re-sync the RAG venv to the engine's pinned deps (rag-setup.sh, if provisioned)
#
# Refuses a MAJOR bump — those need a reviewed migration (see CHANGELOG). Leaves the
# submodule bump STAGED for you to review + commit; never auto-commits (adoption is a
# human gate). Deterministic; no `claude`. doctor.sh reports; this applies.
#
# Usage: update.sh [--wiki DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_WIKI="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"   # engine is $WIKI/engine
WIKI="${WIKI_PATH:-$DEFAULT_WIKI}"
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
ENGINE="$WIKI/engine"
[ -d "$ENGINE/.git" ] || [ -f "$ENGINE/.git" ] || { echo "error: no engine submodule at $ENGINE" >&2; exit 1; }

core_major() { printf '%s' "$1" | sed -E 's/^v//; s/[.-].*$//'; }

git -C "$ENGINE" fetch -q origin main --tags 2>/dev/null || { echo "update: could not reach origin (offline?)" >&2; exit 2; }

pinned="$(git -C "$ENGINE" describe --tags --always 2>/dev/null)"
latest="$(git -C "$ENGINE" tag -l 'v*' | sort -V | tail -1)"
[ -n "$latest" ] || { echo "update: engine has no version tags; nothing to advance to" >&2; exit 1; }

if [ "$pinned" = "$latest" ]; then
  echo "update: already at $latest"
  # still re-sync RAG deps in case the pin didn't move but requirements did
  [ -x "$WIKI/.rag/venv/bin/python" ] && "$ENGINE/bin/rag-setup.sh" --wiki "$WIKI" >/dev/null && echo "update: RAG deps in sync"
  exit 0
fi

pmaj="$(core_major "$pinned")"; lmaj="$(core_major "$latest")"
if [ -n "$pmaj" ] && [ -n "$lmaj" ] && [ "$lmaj" -gt "$pmaj" ] 2>/dev/null; then
  echo "update: ⚠ $latest is a MAJOR bump over $pinned — breaking; review CHANGELOG + migration and adopt manually. Not applied." >&2
  exit 1
fi

echo "update: $pinned -> $latest"
git -C "$ENGINE" checkout -q "$latest"
"$ENGINE/bin/adopt.sh" --wiki "$WIKI"
if [ -x "$WIKI/.rag/venv/bin/python" ]; then
  echo "update: re-syncing RAG deps to the pinned set"
  "$ENGINE/bin/rag-setup.sh" --wiki "$WIKI" >/dev/null && echo "update: RAG deps in sync"
fi
git -C "$WIKI" add engine 2>/dev/null || true

cat <<EOF

Staged: engine -> $latest. Review the CHANGELOG, then commit:
  git -C "$WIKI" commit -am "Bump engine to $latest"
EOF
