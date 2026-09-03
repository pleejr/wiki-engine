#!/usr/bin/env bash
# lint-log.sh — the vault's `log.md` (and any rotated `log/*.md` archive) holds ONE DATED
# ENTRY PER SESSION, each a single physical line, linking the notes it distilled.
#
# THE RULE, STATED ONCE. The entry shape is:
#   - **YYYY-MM-DD** — <what happened, in one entry, with [[links]] to the notes it produced>
#   - **YYYY-MM-DD (tag)** — <same, with a session tag in parentheses>
# The engine used to say "one dated LINE" on three surfaces and measure it nowhere; measured
# on two vaults the compliance was 2% and ~0% (median entry 331 and 222 words). A rule obeyed
# by 2% of its population was never in force, so the rule now says what is practised — one
# ENTRY, of bounded length — and this script is what makes it true rather than aspirational.
#
# CHECKS
#   ERROR — a top-level bullet whose header is not `- **YYYY-MM-DD` (optionally ` (tag)`)
#           followed by `** —`: the template shape, which every reader of the file keys on.
#   WARN  — an entry over LOG_ENTRY_WARN_WORDS words (default 400). Chosen from the measured
#           distribution rather than from taste: the engine-dev vault's 90th percentile was
#           435 and the reporting vault's median 331, so an ordinary entry passes and only
#           the narrative long tail is named. The number is the rule; --strict makes it fail.
#   WARN  — an entry with no [[wikilink]]: the log's value is that it points at the notes a
#           session distilled; an entry that links nothing is a paragraph nobody can follow.
#   WARN  — a header date earlier than the entry above it, within one file. History is
#           append-only and concurrent sessions reconcile by merge, so inversions are
#           expected in small numbers; a rotation must therefore key on the DATE in each
#           entry, never on its position (see rotate-log.sh), and this names them.
# Only the header date is read — a date inside the entry's prose is what a narrative
# contains, and a check that read it would flag every real history.
#
# WARN-FIRST, --strict TO PROMOTE, for the reason every warn-first lint here gives: an
# arriving vault has a full backlog, and an always-red gate teaches --no-verify.
#
# Usage:
#   lint-log.sh [--wiki DIR] [--strict]
#   LOG_ENTRY_WARN_WORDS=N     words per entry before a warning (default 400)
# Exit 1 on any ERROR, or on any WARN under --strict.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI=""; STRICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
WARN_WORDS="${LOG_ENTRY_WARN_WORDS:-400}"
case "$WARN_WORDS" in ''|*[!0-9]*) echo "error: LOG_ENTRY_WARN_WORDS must be a number (got '$WARN_WORDS')" >&2; exit 1;; esac

files=()
[ -f "$WIKI/log.md" ] && files+=("$WIKI/log.md")
for f in "$WIKI"/log/*.md; do [ -f "$f" ] && files+=("$f"); done
[ "${#files[@]}" -gt 0 ] || { echo "ok: no log.md — nothing to check"; exit 0; }

errors=0; warnings=0; entries=0
for f in "${files[@]}"; do
  rel="${f#$WIKI/}"
  # LC_ALL=C: the header is ASCII and words are whitespace-split, and a locale-aware awk
  # aborts on a byte it cannot map (seen on a real log), which would read as "0 entries".
  out="$(LC_ALL=C awk -v W="$WARN_WORDS" -v F="$rel" '
    /^- / {
      if ($0 ~ /^- \*\*20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]( \([^)]*\))?\*\* /) {
        n++
        d=substr($0, 5, 10)
        if (prev != "" && d < prev) { printf "  ! %s:%d — entry dated %s follows %s (date inversion; rotation keys on the date, not the position)\n", F, NR, d, prev; w++ }
        prev=d
        if (NF > W) { printf "  ! %s:%d — entry of %s is %d words (budget %d); one entry, linking the notes it distilled\n", F, NR, d, NF, W; w++ }
        if (index($0, "[[") == 0) { printf "  ! %s:%d — entry of %s links nothing\n", F, NR, d; w++ }
      } else {
        printf "  ✗ %s:%d — bullet is not a dated entry (want `- **YYYY-MM-DD** — …`): %s\n", F, NR, substr($0, 1, 60); e++
      }
    }
    END { printf "__COUNTS__ %d %d %d\n", n+0, e+0, w+0 }
  ' "$f")"
  printf '%s\n' "$out" | grep -v '^__COUNTS__'
  read -r n e w <<< "$(printf '%s\n' "$out" | awk '/^__COUNTS__/{print $2, $3, $4}')"
  entries=$((entries + ${n:-0})); errors=$((errors + ${e:-0})); warnings=$((warnings + ${w:-0}))
done
echo "log lint: $entries entr$([ "$entries" = 1 ] && echo y || echo ies) across ${#files[@]} file(s), $errors error(s), $warnings warning(s) (budget $WARN_WORDS words)"
if [ "$errors" -gt 0 ] || { [ "$STRICT" = 1 ] && [ "$warnings" -gt 0 ]; }; then exit 1; fi
exit 0
