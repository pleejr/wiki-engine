#!/usr/bin/env bash
# gen-skills-index.sh — regenerate a wiki's index.md skills catalog by scanning
# the engine's skills/*/SKILL.md frontmatter. The skill node is kept current by a
# deterministic scan (see engine SCHEMA.md), not by hand.
#
# Each catalog line is:  - **<name>** _(<status>)_ — <summary>
# using the SKILL.md frontmatter `name`, `status` (default: active) and `summary`
# (falling back to the first sentence of `description`).
#
# The catalog is written between these sentinels in the wiki's index.md:
#   <!-- skills:start -->
#   ... generated lines ...
#   <!-- skills:end -->
#
# Usage:
#   gen-skills-index.sh                 update $WIKI_PATH/index.md in place
#   gen-skills-index.sh --stdout        print the generated block only
#   gen-skills-index.sh --check         exit 1 if index.md is out of date (no write)
#   gen-skills-index.sh --wiki DIR      target DIR/index.md instead of $WIKI_PATH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$ENGINE_ROOT/skills"

MODE="write"
WIKI="${WIKI_PATH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --stdout) MODE="stdout"; shift;;
    --check)  MODE="check"; shift;;
    --wiki)   WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -d "$SKILLS_DIR" ] || { echo "error: no skills dir at $SKILLS_DIR" >&2; exit 1; }

# --- generate the catalog block (sorted by skill name, deterministic) ----------
gen_block() {
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    awk '
      NR==1 && $0=="---" { infm=1; next }
      infm && $0=="---"  { exit }
      infm {
        if      ($0 ~ /^name:/)        name=val($0)
        else if ($0 ~ /^status:/)      status=val($0)
        else if ($0 ~ /^summary:/)     summary=val($0)
        else if ($0 ~ /^description:/) desc=val($0)
      }
      END {
        if (name=="") exit
        if (status=="")  status="active"
        if (summary=="") summary=first_sentence(desc)
        printf "- **%s** _(%s)_ — %s\n", name, status, summary
      }
      function val(l){ sub(/^[^:]*:[ \t]*/,"",l); sub(/^"/,"",l); sub(/"$/,"",l); return l }
      function first_sentence(s,   p){ p=index(s,". "); return (p>0) ? substr(s,1,p) : s }
    ' "$f"
  done | LC_ALL=C sort
}

BLOCK="$(gen_block)"
[ -n "$BLOCK" ] || { echo "error: no skills parsed from $SKILLS_DIR" >&2; exit 1; }

if [ "$MODE" = "stdout" ]; then
  printf '%s\n' "$BLOCK"
  exit 0
fi

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
INDEX="$WIKI/index.md"
[ -f "$INDEX" ] || { echo "error: no index at $INDEX" >&2; exit 1; }

grep -q '<!-- skills:start -->' "$INDEX" && grep -q '<!-- skills:end -->' "$INDEX" || {
  echo "error: $INDEX is missing the <!-- skills:start --> / <!-- skills:end --> sentinels" >&2
  exit 1
}

# splice BLOCK between the sentinels, leaving the rest of index.md untouched.
# The block is passed via a temp file — awk -v mangles embedded newlines.
splice() {
  local bf; bf="$(mktemp)"; printf '%s\n' "$BLOCK" > "$bf"
  awk -v bf="$bf" '
    /<!-- skills:start -->/ { print; while ((getline l < bf) > 0) print l; close(bf); skip=1; next }
    /<!-- skills:end -->/   { skip=0 }
    !skip { print }
  ' "$INDEX"
  rm -f "$bf"
}

NEW="$(splice)"

if [ "$MODE" = "check" ]; then
  if [ "$NEW" = "$(cat "$INDEX")" ]; then
    echo "ok: $INDEX skills catalog is up to date"
    exit 0
  fi
  echo "drift: $INDEX skills catalog is stale — run gen-skills-index.sh" >&2
  exit 1
fi

printf '%s\n' "$NEW" > "$INDEX"
echo "updated $INDEX skills catalog ($(printf '%s\n' "$BLOCK" | wc -l | tr -d ' ') skills)"
