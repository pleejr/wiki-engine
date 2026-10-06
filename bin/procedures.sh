#!/usr/bin/env bash
# procedures.sh — the procedures the vault records as DONE, counted for `mine`.
#
# A memory note that records a procedure carried out (steps done, not only a conclusion)
# carries one frontmatter key, `procedure: <verb>-<object>` (the verb from bin/skill-verbs.txt,
# the same list skill names use). `distill` reuses an existing key when the steps match, so
# keys converge instead of fragmenting; `mine` counts them instead of guessing repetition
# from free tags and prose. Occurrences are counted by `created:`, never `updated:`.
#
# Usage: procedures.sh [--wiki DIR] [--min N] [--span-days D]
#   prints one line per key: <count> <key> <first-created> <last-created> <span-days> <notes...>
#   --min N        only keys with at least N notes (default 1)
#   --span-days D  only keys whose occurrences span at least D days (default 0)
# Deterministic, read-only, no `claude`.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI="" MIN=1 SPAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --min) MIN="$2"; shift 2;;
    --span-days) SPAN="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "procedures: unknown arg: $1" >&2; exit 2;;
  esac
done
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1
shopt -s nullglob; notes=("$WIKI"/memory/*.md)
[ "${#notes[@]}" -gt 0 ] || exit 0
printf '%s\0' "${notes[@]}" | xargs -0 awk '
  FNR == 1 { infm = ($0 == "---"); key = ""; cr = ""; slug = FILENAME; sub(/.*\//, "", slug); sub(/\.md$/, "", slug); next }
  infm && $0 == "---" { infm = 0; if (key != "" && cr != "") print key "\t" cr "\t" slug; next }
  infm && /^procedure:/ { key = $0; sub(/^procedure:[ \t]*/, "", key); gsub(/["\047]/, "", key) }
  infm && /^created:/   { cr = $0;  sub(/^created:[ \t]*/, "", cr) }
' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 | awk -F '\t' -v min="$MIN" -v span="$SPAN" '
  function days(d,   y, m, dd) { y = substr(d,1,4)+0; m = substr(d,6,2)+0; dd = substr(d,9,2)+0
    if (m < 3) { y--; m += 12 }; return int(365.25*(y+4716)) + int(30.6001*(m+1)) + dd }
  function flush() { if (k != "" && n >= min && days(last) - days(first) >= span) print n " " k " " first " " last " " (days(last)-days(first)) notes }
  $1 != k { flush(); k = $1; n = 0; first = $2; notes = "" }
  { n++; last = $2; notes = notes " " $3 }
  END { flush() }
' | sort -k1,1nr -k2,2
