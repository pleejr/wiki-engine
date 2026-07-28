#!/usr/bin/env bash
# release-title.sh — derive a GitHub Release title suffix from a CHANGELOG section.
#
# EXTRACTED FROM release.yml SO IT CAN BE TESTED. The logic lived inline in the release
# workflow, which runs only on a version-tag push — so it was never exercised by CI, and it
# has now been wrong twice: once slicing mid-word and leaving raw markdown in the title, and
# once cutting at a colon inside an inline code span. A copy in a test and a copy in the
# workflow would drift; one script used by both cannot.
#
# THE RULE. Take the section's first prose line, drop the Minor/Patch/Major prefix, and cut
# at the first clause boundary — punctuation followed by whitespace — that is **outside** a
# code span. Punctuation inside backticks belongs to a token (`Proposal:`, `gen-x.sh`, a
# ratio) and ends nothing. The previous version stripped the backticks one step BEFORE the
# split, destroying the very markers that distinguish the two cases; that is why a summary
# containing `Proposal:` published as "<version> — the Proposal".
#
# Then cap at 80 characters on a word boundary, so a long clause degrades to an ellipsis
# rather than a mid-word slice.
#
# Deterministic: no network, no model. Reads the section on stdin or from --notes.
set -uo pipefail

MAX=80
NOTES=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2;;
    --max)   MAX="$2"; shift 2;;
    -h|--help) sed -n '1,22p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$NOTES" ] || NOTES="$(cat)"

# First line that is prose: not blank, not a heading, not a bullet.
line="$(printf '%s\n' "$NOTES" | grep -m1 -E '^[[:space:]]*[^[:space:]#*-]' || true)"
[ -n "$line" ] || { printf '%s' ""; exit 0; }

suffix="$(printf '%s\n' "$line" \
  | sed -E 's/^(Minor|Patch|Major) — //' \
  | awk '{
      n = length($0); inb = 0; out = ""
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "`") { inb = !inb; continue }   # drop the marker, but track the span
        out = out c
        if (!inb && (c == "." || c == ";" || c == ":") && i < n && substr($0, i+1, 1) ~ /[ \t]/) break
      }
      gsub(/\*+/, "", out)                        # emphasis markers are never boundaries
      sub(/[ \t]*[.;:]+$/, "", out)               # no dangling punctuation in a title
      print out
    }')"

# Cap on a word boundary. An unclosed backtick makes the whole line one span, so no boundary
# is found and the cap is what keeps the title sane — a degradation, not a failure.
if [ "${#suffix}" -gt "$MAX" ]; then
  suffix="$(printf '%s' "$suffix" | cut -c1-"$MAX" | sed -E 's/[[:space:]]+[^[:space:]]*$//')…"
fi
printf '%s' "$suffix"
