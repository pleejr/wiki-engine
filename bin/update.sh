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
# The submodule work below is canonical-only by necessity; this resolves the separate
# question of which tree a TRACKED page edit belongs in (see the provenance block).
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
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
#
# WHICH TREE THE PAGE IS WRITTEN IN is a separate question from where the submodule lives.
# The pin is a gitlink and exists only in canonical; a repo page is ordinary TRACKED vault
# content, and writing it into the shared checkout is the exact thing worktrees exist to
# prevent — last-writer-wins on disk against a concurrent session, before git sees it, and
# a staged change appearing in a tree whose session did not author it.
#
# So: write it in the caller's own worktree when it is in one; otherwise, if a commit in
# canonical would be REFUSED, do not write at all — print the intended values so the
# operator applies them in the branch that should carry them. A vault that can commit in
# canonical (no gate wired, or WIKI_WORKTREE=0) is unaffected: canonical IS its working
# tree, and today's behaviour is correct there.
#
# The test was once "does the vault have live linked worktrees?", and that was the wrong
# question. Isolation being CONFIGURED and a worktree being OPEN are different states, and
# between sessions the second is false while the first stays true — so an ordinary vault
# with nothing open got the page written and staged in canonical, where the guard then
# refused the commit that would land it. Ask instead whether the caller can commit what is
# written; canonical_commit_gated answers exactly that, and the two runs (worktree open,
# none open) stop differing on something the caller never asked about.
PAGE_TREE="$(resolve_wiki_root "$WIKI")" || PAGE_TREE="$WIKI"
defer_page=0
if [ "$PAGE_TREE" = "$WIKI" ] && [ -n "$(canonical_commit_gated "$WIKI")" ]; then
  defer_page=1
fi
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
    if [ "$defer_page" = "1" ]; then deferred="${page#$WIKI/}"; continue; fi
    # The page is written in PAGE_TREE, which is canonical unless the caller is standing
    # in a worktree of this same vault — the tree they will actually commit from.
    page="$PAGE_TREE/${page#$WIKI/}"
    [ -f "$page" ] || continue
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
    git -C "$PAGE_TREE" add "${page#$PAGE_TREE/}" 2>/dev/null || true
    bumped="${page#$PAGE_TREE/}"
  done
fi

# The remedy names the PATH, never `-am`. In a shared checkout `-am` stages every modified
# tracked file, including a concurrent session's — the precise clobber the guard exists to
# refuse, printed as an instruction. `commit engine` cannot do that, and the guard now
# permits it because a gitlink-only commit is the one commit no worktree can make.
cat <<EOF

Staged: engine -> $latest. Review the CHANGELOG, then commit the POINTER ONLY:
  git -C "$WIKI" commit engine -m "Bump engine to $latest"
EOF

if [ -n "$bumped" ]; then
  cat <<EOF
Also staged: $bumped provenance -> $latest ($new_sha), in $PAGE_TREE.
  Its verified: stamp was left alone on purpose, so the page now reads VERIFIED-STALE and
  \`upkeep scan\` will queue a verify pass. That is the honest state: the pointer is current,
  the CONTENT has not been re-read against this release. Run the verify pass before
  checkpoint — do not stamp it without actually reading the repo.
EOF
fi

if [ -n "${deferred:-}" ]; then
  cat <<EOF
NOT written: $deferred provenance. This vault gates commits in the canonical checkout, and
  that page is tracked content — writing it here would put an edit in the shared checkout
  that the session committing it did not make, and the gate would refuse the commit that
  lands it. Apply it in a worktree instead (\`vault-worktree.sh ensure\`):
      ref: $latest
      sha: $new_sha
      ingested: $(date +%Y-%m-%d)
  Leave \`verified:\` alone; the page then reads VERIFIED-STALE, which is the honest state
  until someone re-reads the repo. Running update.sh from inside your worktree writes it
  there for you.
EOF
fi
