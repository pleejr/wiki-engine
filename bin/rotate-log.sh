#!/usr/bin/env bash
# rotate-log.sh — move `log.md` entries older than the current quarter into
# `log/<YYYY>-Q<n>.md`, byte for byte, leaving one pointer line behind.
#
# WHY. A vault's history is append-only by design, and correctly so — but an append-only
# single file is a FILE-SIZE problem, not a history problem, and the two have different
# answers. Measured on one vault: 443 entries, 1.04 MB, loaded whole by every tool that
# reads it and chunked by a splitter tuned for a quarter of its current entry size. Rotation
# moves bytes; it never edits them.
#
# TWO CONSTRAINTS THIS CARRIES, both on-disk contracts other components name:
#   - the live file stays at `log.md` — `skill-candidates`, `wiki-context` and the chunker's
#     own comment name it literally, and `lint-links.sh` excludes it by name;
#   - the archive lands under `log/`, a plain directory the RAG builder walks (its skip rule
#     is `engine` plus any dot-prefixed segment — read from bin/rag-build.sh, not assumed),
#     so a rotated entry stays recallable after the next `rag-build`.
#
# KEYED ON THE DATE IN EACH ENTRY, NEVER ON POSITION. The file is not in chronological order:
# concurrent sessions each append in their own worktree and reconcile by merge, so a
# positional rule would archive the wrong entries on exactly the vaults the worktree tooling
# serves. Each `- **YYYY-MM-DD…** —` header is parsed; anything that is not such an entry
# (the `# Log` title, the pointer line, blank lines) stays where it is.
#
# IDEMPOTENT. A second run finds nothing older than the current quarter and moves nothing —
# a repair path that degrades on retry is worse than the failure it repairs. The pointer line
# is ONE line, rewritten in place to list every archive file, never appended twice.
#
# WRITES TRACKED CONTENT, so it resolves the tree the way the generators do (explicit --wiki,
# else the session worktree cwd is in, else $WIKI_PATH) and belongs in a worktree commit.
#
# Usage:
#   rotate-log.sh [--wiki DIR] [--dry-run]
#   LOG_TODAY=YYYY-MM-DD    what "today" is (default: the system date) — the current quarter
#                           is derived from it; fixtures age themselves with this
# Exit 0 whether or not anything moved (the summary says which); 1 on a malformed file.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI=""; DRY=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
LOG="$WIKI/log.md"
[ -f "$LOG" ] || { echo "rotate-log: no log.md at $WIKI — nothing to rotate"; exit 0; }

today="${LOG_TODAY:-$(date +%Y-%m-%d)}"
case "$today" in 20[0-9][0-9]-[01][0-9]-[0-3][0-9]) ;; *) echo "error: LOG_TODAY must be YYYY-MM-DD (got '$today')" >&2; exit 1;; esac
cur_y="${today%%-*}"; cur_m="${today#*-}"; cur_m="${cur_m%%-*}"; cur_m="${cur_m#0}"
cur_q=$(( (cur_m - 1) / 3 + 1 ))
# First day of the current quarter: everything dated before it rotates.
cutoff="$(printf '%s-%02d-01' "$cur_y" $(( (cur_q - 1) * 3 + 1 )))"

# Pass 1: which archive files would receive entries, and how many.
plan="$(LC_ALL=C awk -v C="$cutoff" '
  /^- \*\*20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
    d=substr($0, 5, 10)
    if (d < C) { y=substr(d,1,4); m=substr(d,6,2)+0; q=int((m-1)/3)+1; k=y "-Q" q; n[k]++ }
  }
  END { for (k in n) print k, n[k] }' "$LOG" | sort)"
if [ -z "$plan" ]; then
  echo "rotate-log: nothing older than $cutoff in log.md — nothing to move"
  exit 0
fi
total=0
while read -r k n; do [ -n "$k" ] && total=$((total + n)); done <<< "$plan"
if [ "$DRY" = 1 ]; then
  echo "rotate-log (dry run): would move $total entr$([ "$total" = 1 ] && echo y || echo ies) dated before $cutoff:"
  printf '%s\n' "$plan" | awk '{printf "  log/%s.md  +%d\n", $1, $2}'
  exit 0
fi

mkdir -p "$WIKI/log"
# Pass 2: append each old entry, verbatim, to its quarter file (created with a one-line
# title); keep everything else in a temp copy of log.md; then rewrite the pointer line.
tmp="$(mktemp "$WIKI/.log.md.rotate.XXXXXX")"
LC_ALL=C awk -v C="$cutoff" -v DIR="$WIKI/log" -v KEEP="$tmp" '
  function target(d,   y, m, q) { y=substr(d,1,4); m=substr(d,6,2)+0; q=int((m-1)/3)+1; return DIR "/" y "-Q" q ".md" }
  /^- \*\*20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
    d=substr($0, 5, 10)
    if (d < C) {
      f=target(d)
      if (!(f in seen)) { seen[f]=1; if ((getline line < f) < 0) { print "# Log — " substr(d,1,4) " Q" int((substr(d,6,2)+0-1)/3)+1 " (rotated from log.md; entries verbatim)" > f; print "" > f } close(f) }
      print $0 >> f; close(f)
      next
    }
  }
  /^_\(rotated: / { next }
  { print > KEEP }
' "$LOG" || { rm -f "$tmp"; echo "error: rotation failed; log.md untouched" >&2; exit 1; }
# Pointer line: one line, directly under the title, listing every archive present.
archives="$(cd "$WIKI" && ls log/*.md 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
LC_ALL=C awk -v P="_(rotated: entries before $cutoff live in ${archives// /, } — moved by rotate-log.sh, text unchanged)_" '
  NR==1 && /^# / { print; print ""; print P; print ""; skipblank=1; next }
  skipblank && $0=="" { skipblank=0; next }
  { skipblank=0; print }
' "$tmp" > "$LOG" && rm -f "$tmp"
echo "rotate-log: moved $total entr$([ "$total" = 1 ] && echo y || echo ies) dated before $cutoff:"
printf '%s\n' "$plan" | awk '{printf "  log/%s.md  +%d\n", $1, $2}'
echo "rotate-log: log.md keeps the current quarter; run rag-build to index the archive; commit log.md and log/ together"
exit 0
