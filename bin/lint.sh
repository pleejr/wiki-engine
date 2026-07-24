#!/usr/bin/env bash
# lint.sh — umbrella lint for a wiki vault. Runs every deterministic check and
# aggregates the result, so `checkpoint` (or a pre-commit) can call one command:
#   1. memory notes         — lint-memory.sh (frontmatter, type, >=2 wikilinks, drift)
#   2. frontmatter props     — wikilink-valued properties must be a quoted YAML block
#                              list; catches Obsidian's "invalid properties"
#   3. soft-wrap drift       — reflow.sh --check (hard wraps that would render broken)
#   4. skills catalog drift  — gen-skills-index.sh --check
#   5. projects catalog drift — gen-projects-index.sh --check
#   6. boundary present      — every content-node page (the non-raw node folders in
#                              scaffold/node-dirs.txt) declares a boundary: — the
#                              first line of defense for the vault's boundary rule
#   7. provenance present    — every repos/ page carries a sources: block with
#                              ref: + sha: (a version-keyed node must record what it
#                              was ingested from, so freshness is checkable)
#
# Checks 6–7 are vault-invariant GATES: they must hold at zero, so lint.sh doubles
# as the enforced write-time gate (vault CI + pre-commit) — see the pleejr-wiki
# engine-gates-at-zero project. Universal invariants (no consumer-specific values),
# so they ship engine-default-on; consumer-specific gates (a foreign-boundary
# denylist, link-integrity with a stub allowlist) land later behind a vault seam.
#
# Exit 1 if any check fails.
#
# Usage:
#   lint.sh                 lint $WIKI_PATH
#   lint.sh --wiki DIR      lint DIR
#   lint.sh --strict        pass --strict through to lint-memory (warnings fail)
set -uo pipefail   # deliberately not -e: run all checks, then aggregate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
STRICT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)   WIKI="$2"; shift 2;;
    --strict) STRICT="--strict"; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

# vault markdown, excluding the engine submodule and non-content dirs.
# (while-read, not mapfile — macOS ships bash 3.2.)
PAGES=()
while IFS= read -r p; do PAGES+=("$p"); done < <(find "$WIKI" \
  -type d \( -name .git -o -name engine -o -name .obsidian -o -name .rag \) -prune -o \
  -type f -name '*.md' -print | sort)
[ "${#PAGES[@]}" -gt 0 ] || { echo "error: no pages under $WIKI" >&2; exit 1; }

rc=0
section() { printf '\n=== %s ===\n' "$1"; }

# 1. memory ---------------------------------------------------------------------
section "memory notes"
"$SCRIPT_DIR/lint-memory.sh" --wiki "$WIKI" $STRICT || rc=1

# 2. frontmatter properties -----------------------------------------------------
# A wikilink in frontmatter is valid only as a quoted block-list item
#   key:
#     - "[[Target]]"
# Any other frontmatter line containing [[ is the Obsidian "invalid properties"
# footgun (inline value, or an unquoted list item YAML reads as a nested list).
section "frontmatter properties"
fp=0
for f in "${PAGES[@]}"; do
  bad="$(awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && index($0,"[[")>0 {
      if ($0 ~ /^[ \t]*-[ \t]+".*"[ \t]*$/) next   # ok: quoted block-list item
      printf "  %d: %s\n", NR, $0
    }
  ' "$f")"
  if [ -n "$bad" ]; then
    printf '%s\n' "$f"
    printf '%s\n' "$bad"
    fp=1; rc=1
  fi
done
[ "$fp" -eq 0 ] && echo "ok: no inline wikilink properties (use quoted block lists)"

# 3. soft-wrap drift ------------------------------------------------------------
section "soft-wrap"
if out="$("$SCRIPT_DIR/reflow.sh" --check "${PAGES[@]}")"; then
  echo "ok: no hard-wrap drift"
else
  printf '%s\n' "$out"; rc=1
fi

# 4. skills catalog drift -------------------------------------------------------
section "skills catalog"
"$SCRIPT_DIR/gen-skills-index.sh" --check --wiki "$WIKI" || rc=1

# 5. projects catalog drift -----------------------------------------------------
section "projects catalog"
"$SCRIPT_DIR/gen-projects-index.sh" --check --wiki "$WIKI" || rc=1

# content-node pages: the flat, non-raw node folders the engine defines as the
# vault's curated nodes. Root hubs (CLAUDE.md/index.md/log.md/README.md) and raw/
# captures are deliberately NOT nodes, so they're exempt from the node invariants.
NODE_DIRS=()
NODE_DIRS_FILE="$SCRIPT_DIR/../scaffold/node-dirs.txt"
if [ -f "$NODE_DIRS_FILE" ]; then
  while IFS= read -r d; do
    case "$d" in ''|'#'*|raw/*) continue;; esac
    NODE_DIRS+=("$d")
  done < "$NODE_DIRS_FILE"
fi

# read a page's frontmatter (between the first two --- fences) into a check.
# fm_has KEY FILE  → true if a frontmatter line matches ^[ \t]*KEY (KEY a regex-safe literal)
fm_has() {
  awk -v key="$1" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^[ \t]*" key) { found=1; exit }
    END { exit !found }
  ' "$2"
}

# 6. boundary present on every content-node page --------------------------------
section "boundary present"
bp=0
for d in "${NODE_DIRS[@]}"; do
  for f in "$WIKI/$d"/*.md; do
    [ -f "$f" ] || continue
    if ! fm_has "boundary:" "$f"; then
      printf '  ✗ %s — no boundary: in frontmatter\n' "${f#$WIKI/}"; bp=1; rc=1
    fi
  done
done
[ "$bp" -eq 0 ] && echo "ok: every content-node page declares a boundary"

# 7. provenance present on every repo page --------------------------------------
# A repos/ page is version-keyed: it must record a sources: block with ref: + sha:
# so freshness (recorded ref/sha vs live HEAD) is checkable.
section "provenance present"
pp=0
if [ -d "$WIKI/repos" ]; then
  for f in "$WIKI/repos"/*.md; do
    [ -f "$f" ] || continue
    miss=""
    fm_has "sources:" "$f" || miss="sources:"
    fm_has "ref:"     "$f" || miss="$miss ref:"
    fm_has "sha:"     "$f" || miss="$miss sha:"
    if [ -n "$miss" ]; then
      printf '  ✗ %s — missing provenance:%s\n' "${f#$WIKI/}" " $miss"; pp=1; rc=1
    fi
  done
fi
[ "$pp" -eq 0 ] && echo "ok: every repo page carries sources: ref/sha provenance"

echo
[ "$rc" -eq 0 ] && echo "lint: all checks passed" || echo "lint: FAILURES above"
exit $rc
