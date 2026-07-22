#!/usr/bin/env bash
# lint.sh — umbrella lint for a wiki vault. Runs every deterministic check and
# aggregates the result, so `checkpoint` (or a pre-commit) can call one command:
#   1. memory notes         — lint-memory.sh (frontmatter, type, >=2 wikilinks, drift)
#   2. frontmatter props     — wikilink-valued properties must be a quoted YAML block
#                              list; catches Obsidian's "invalid properties"
#   3. soft-wrap drift       — reflow.sh --check (hard wraps that would render broken)
#   4. skills catalog drift  — gen-skills-index.sh --check
#   5. projects catalog drift — gen-projects-index.sh --check
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

echo
[ "$rc" -eq 0 ] && echo "lint: all checks passed" || echo "lint: FAILURES above"
exit $rc
