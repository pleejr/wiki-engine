#!/usr/bin/env bash
# gen-projects-index.sh — regenerate a wiki's index.md Projects catalog by scanning
# projects/*.md frontmatter. Like the skills node, the project list is kept current
# by a deterministic scan (see engine SCHEMA.md), not by hand — so closing a project
# (flipping its page `status:`) can't silently drift the index buckets.
#
# Each catalog line is:  - [[<slug>]] — <summary>
# grouped under a `### <Status>` heading, using the page frontmatter `status`
# (default: active) and `summary` (falling back to `title`, then the slug). `slug`
# is the page filename without .md. Statuses are bucketed in a fixed order
# (Planned / Active / Paused / Done); an empty bucket renders `_none_`. Any status
# outside the known set is bucketed under `### Other`.
#
# The catalog is written between these sentinels in the wiki's index.md:
#   <!-- projects:start -->
#   ... generated headings + lines ...
#   <!-- projects:end -->
#
# Usage:
#   gen-projects-index.sh                 update $WIKI_PATH/index.md in place
#   gen-projects-index.sh --stdout        print the generated block only
#   gen-projects-index.sh --check         exit 1 if index.md is out of date (no write)
#   gen-projects-index.sh --wiki DIR      target DIR (its projects/ + index.md)
set -euo pipefail

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

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
PROJECTS_DIR="$WIKI/projects"
[ -d "$PROJECTS_DIR" ] || { echo "error: no projects dir at $PROJECTS_DIR" >&2; exit 1; }

# --- generate the catalog block (bucketed by status, sorted within bucket) ------
# Emit one TSV row per project page: <status>\t<slug>\t<summary>, then let awk
# group + order deterministically.
gen_block() {
  local rows; rows="$(
    for f in "$PROJECTS_DIR"/*.md; do
      [ -f "$f" ] || continue
      slug="$(basename "$f" .md)"
      awk -v slug="$slug" '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---"  { exit }
        infm {
          if      ($0 ~ /^status:/)  status=val($0)
          else if ($0 ~ /^summary:/) summary=val($0)
          else if ($0 ~ /^title:/)   title=val($0)
        }
        END {
          if (status=="")  status="active"
          if (summary=="") summary=(title=="" ? slug : title)
          printf "%s\t%s\t%s\n", status, slug, summary
        }
        function val(l){ sub(/^[^:]*:[ \t]*/,"",l); sub(/^"/,"",l); sub(/"$/,"",l); return l }
      ' "$f"
    done | LC_ALL=C sort -t$'\t' -k1,1 -k2,2
  )"

  printf '%s\n' "$rows" | awk -F'\t' '
    BEGIN {
      n=split("planned active paused done", order, " ")
      label["planned"]="Planned"; label["active"]="Active"
      label["paused"]="Paused";   label["done"]="Done"
    }
    $1 == "" { next }   # empty vault: no rows — still emit the buckets below
    { line[$1] = line[$1] sprintf("- [[%s]] — %s\n", $2, $3); seen[$1]=1 }
    END {
      for (i=1; i<=n; i++) {
        s=order[i]
        printf "### %s\n", label[s]
        if (line[s] != "") printf "%s", line[s]; else print "_none_"
        print ""
        done_known[s]=1
      }
      # any unexpected status value gets surfaced, not silently dropped
      first=1
      for (s in seen) {
        if (done_known[s]) continue
        if (first) { print "### Other"; first=0 }
        printf "%s", line[s]
      }
      if (!first) print ""
    }
  '
}

BLOCK="$(gen_block)"
# BLOCK is always non-empty (the fixed buckets render even for an empty vault);
# $(...) already trims the trailing blank line the generator leaves after Done.
[ -n "$BLOCK" ] || { echo "error: failed to build projects block" >&2; exit 1; }

if [ "$MODE" = "stdout" ]; then
  printf '%s\n' "$BLOCK"
  exit 0
fi

INDEX="$WIKI/index.md"
[ -f "$INDEX" ] || { echo "error: no index at $INDEX" >&2; exit 1; }

grep -q '<!-- projects:start -->' "$INDEX" && grep -q '<!-- projects:end -->' "$INDEX" || {
  echo "error: $INDEX is missing the <!-- projects:start --> / <!-- projects:end --> sentinels" >&2
  exit 1
}

# splice BLOCK between the sentinels, leaving the rest of index.md untouched.
splice() {
  local bf; bf="$(mktemp)"; printf '%s\n' "$BLOCK" > "$bf"
  awk -v bf="$bf" '
    /<!-- projects:start -->/ { print; while ((getline l < bf) > 0) print l; close(bf); skip=1; next }
    /<!-- projects:end -->/   { skip=0 }
    !skip { print }
  ' "$INDEX"
  rm -f "$bf"
}

NEW="$(splice)"

if [ "$MODE" = "check" ]; then
  if [ "$NEW" = "$(cat "$INDEX")" ]; then
    echo "ok: $INDEX projects catalog is up to date"
    exit 0
  fi
  echo "drift: $INDEX projects catalog is stale — run gen-projects-index.sh" >&2
  exit 1
fi

printf '%s\n' "$NEW" > "$INDEX"
echo "updated $INDEX projects catalog ($(printf '%s\n' "$BLOCK" | grep -c '^- \[\[' || true) projects)"
