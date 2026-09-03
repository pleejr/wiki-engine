#!/usr/bin/env bash
# lint-always-on.sh — the vault's CLAUDE.md is in context before the first tool call of every
# session. This reports the word count of each `##` section, and FAILS a section over the
# budget the vault declares for itself.
#
# WHY. Every other always-on cost here is a number a script reports; this one was a paragraph
# a session had to remember, and one vault re-measured its own frozen budget by hand three
# times — which is exactly the work a lint does for free, and the fact that it was done by hand
# three times is the evidence it is a recurring cost.
#
# THE BUDGET IS THE VAULT'S, NEVER THE ENGINE'S. The right size is a consumer decision and an
# engine-chosen number would be wrong for every vault, so there is no default: absent a
# declared budget this prints the counts and passes — a measurement, not a verdict. The seam
# is the one `lint.sh` already composes for its consumer-specific values, `$WIKI/.wiki-gates.conf`
# (parsed, never sourced; `key = value`):
#
#   always_on_budget_words = 120     # every `##` section of CLAUDE.md must be at or under this
#
# Read through resolve_seam_file, so a linted worktree still finds a conf that lives only in
# canonical. Lines that are `@imports` are not counted — they load another file, whose size is
# that file's business — and the heading line itself is not counted.
#
# Deterministic; no network, no model.
#
# Usage:
#   lint-always-on.sh [--wiki DIR]
# Exit 1 only when a budget is declared and a section exceeds it.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
FILE="$WIKI/CLAUDE.md"
[ -f "$FILE" ] || { echo "ok: no CLAUDE.md — nothing to measure"; exit 0; }

budget=""
conf="$(resolve_seam_file "$WIKI" ".wiki-gates.conf")"
if [ -n "$conf" ] && [ -f "$conf" ]; then
  budget="$(awk -F= '
    /^[ \t]*#/ { next }
    { key=$1; sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key)
      if (key != "always_on_budget_words") next
      sub(/^[^=]*=/,""); val=$0; sub(/[ \t]*#.*$/,"",val); sub(/^[ \t]+/,"",val); sub(/[ \t]+$/,"",val)
      print val; exit }' "$conf")"
  case "$budget" in ''|*[!0-9]*) [ -n "$budget" ] && { echo "error: always_on_budget_words must be a number (got '$budget') in $conf" >&2; exit 1; }; budget="";; esac
fi

# Section word counts. Text before the first `##` is the preamble and is counted as its own
# row so nothing loaded is invisible to the report.
rows="$(awk '
  function flush() { if (have) printf "%d\t%s\n", n, sec }
  /^## / { flush(); sec=$0; n=0; have=1; next }
  /^@/   { next }
  { if (!have) { sec="(preamble)"; have=1 } n+=NF }
  END { flush() }
' "$FILE")"
rc=0
while IFS=$'\t' read -r n sec; do
  [ -n "$sec" ] || continue
  if [ -n "$budget" ] && [ "$n" -gt "$budget" ]; then
    printf '  ✗ %5d words  %s  — over the declared budget of %s\n' "$n" "$sec" "$budget"; rc=1
  else
    printf '  %7d words  %s\n' "$n" "$sec"
  fi
done <<< "$rows"
total="$(printf '%s\n' "$rows" | awk -F'\t' '{t+=$1} END{print t+0}')"
if [ -n "$budget" ]; then
  echo "always-on: $total words across $(printf '%s\n' "$rows" | grep -c .) section(s); budget $budget words per section"
else
  echo "always-on: $total words across $(printf '%s\n' "$rows" | grep -c .) section(s); no budget declared (set always_on_budget_words in .wiki-gates.conf to gate it)"
fi
exit "$rc"
