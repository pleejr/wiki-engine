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

# --- advance the engine's own repo page provenance (NOT its verified stamp) -----------
# A vault that documents the engine it consumes re-stales that page on EVERY release, so
# the refresh item reappears immediately and reliably. Bumping `sources.ref`/`sha` here
# removes that churn WITHOUT losing the signal, because the two staleness axes are
# independent: `refresh` compares provenance to the clone, `verify` compares
# `verified.against` to `sources.sha`. Advancing provenance alone silences the first and
# TRIPS THE SECOND — the page's pointer is current, its content is unconfirmed, which is
# exactly what verified-stale means and a more precise description than "refresh".
#
# `verified:` is deliberately NOT touched. That field asserts a human or agent read the
# repo and confirmed the page; writing it mechanically would fabricate the one signal the
# vault refuses to fabricate, and would convert an honest "unconfirmed" into a false
# "confirmed". The content pass stays manual, and stays queued until someone does it.
engine_repo="$(basename -s .git "$(git -C "$ENGINE" config --get remote.origin.url 2>/dev/null || echo)" 2>/dev/null || true)"
[ -n "$engine_repo" ] || engine_repo="$(basename "$(cd "$ENGINE" && pwd)")"
new_sha="$(git -C "$ENGINE" rev-parse --short HEAD 2>/dev/null || true)"
bumped=""
if [ -n "$engine_repo" ] && [ -n "$new_sha" ] && [ -d "$WIKI/repos" ]; then
  for page in "$WIKI/repos"/*.md; do
    [ -f "$page" ] || continue
    # only a page that actually documents THIS repo (sources.repo), never by filename
    page_repo="$(awk '
      NR==1 && $0=="---" { infm=1; next }
      infm && $0=="---"  { exit }
      infm && /^sources:/ { blk=1; next }
      infm && /^[A-Za-z_]+:/ { blk=0 }
      infm && blk && /^[ \t]+(- )?repo:/ { sub(/^[^:]*:[ \t]*/,""); gsub(/[" \t]/,""); print; exit }
    ' "$page")"
    [ "$page_repo" = "$engine_repo" ] || continue
    tmp="$(mktemp)"
    awk -v newref="$latest" -v newsha="$new_sha" -v today="$(date +%Y-%m-%d)" '
      NR==1 && $0=="---" { infm=1; print; next }
      infm && $0=="---"  { infm=0; print; next }
      infm && /^sources:/ { blk="sources"; print; next }
      infm && /^verified:/ { blk="verified"; print; next }
      infm && /^[A-Za-z_]+:/ { blk=""; print; next }
      # rewrite ONLY inside the sources block; the verified block passes through untouched
      infm && blk=="sources" && /^[ \t]+(- )?ref:/      { sub(/ref:.*/, "ref: " newref);      print; next }
      infm && blk=="sources" && /^[ \t]+(- )?sha:/      { sub(/sha:.*/, "sha: " newsha);      print; next }
      infm && blk=="sources" && /^[ \t]+(- )?ingested:/ { sub(/ingested:.*/, "ingested: " today); print; next }
      { print }
    ' "$page" > "$tmp" && mv "$tmp" "$page"
    git -C "$WIKI" add "${page#$WIKI/}" 2>/dev/null || true
    bumped="${page#$WIKI/}"
  done
fi

cat <<EOF

Staged: engine -> $latest. Review the CHANGELOG, then commit:
  git -C "$WIKI" commit -am "Bump engine to $latest"
EOF

if [ -n "$bumped" ]; then
  cat <<EOF
Also staged: $bumped provenance -> $latest ($new_sha).
  Its verified: stamp was left alone on purpose, so the page now reads VERIFIED-STALE and
  \`upkeep scan\` will queue a verify pass. That is the honest state: the pointer is current,
  the CONTENT has not been re-read against this release. Run the verify pass before
  checkpoint — do not stamp it without actually reading the repo.
EOF
fi
