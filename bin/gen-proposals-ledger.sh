#!/usr/bin/env bash
# gen-proposals-ledger.sh — render the PROPOSALS.md ledger table from proposals/*.md.
#
# The QUEUE DIRECTORY is the source of truth; this file is a DERIVED artifact, spliced
# between sentinels exactly like the skills and projects catalogs.
#
# Why generate rather than retire PROPOSALS.md, which is what the proposal asked for: the
# `Proposal:` trailer contract and `lint-proposals.sh` both key on a row existing in that
# file, and `lint-proposals.sh` hard-errors on a trailer with no row. Retiring it in the
# same change would rewrite the trailer gate, the CI job, and the literal-citation reading —
# for no gain, because the objection to keeping the file was *two sources of truth that can
# disagree*, and a generated file cannot disagree with what generated it. Retiring it later
# is a separate, safe change once nothing reads it.
#
# `shipped` is NOT stored. Frontmatter carries only what git cannot answer:
#   outcome:  open | accepted | partially-accepted | rejected | alias   (human judgement)
#   received: YYYY-MM-DD                                                (arrival)
#   reason:   required for rejected / partially-accepted
#   alias:    required for alias
#   release:  BACK-FILL ONLY, for proposals pre-dating the trailer convention
# Note outcome and shipped are ORTHOGONAL — a proposal can be partially-accepted AND
# shipped. The old single-column table could not express that; a file can.
#
# Deterministic: no network, no model. Exit 0 on success, 1 on a malformed queue entry,
# 2 when --check finds drift.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --check) CHECK=1; shift;;
    -h|--help) sed -n '1,25p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

QUEUE="$REPO/proposals"
LEDGER="$REPO/PROPOSALS.md"
START='<!-- proposals:start -->'
END='<!-- proposals:end -->'

[ -d "$QUEUE" ] || { echo "error: no queue directory at $QUEUE" >&2; exit 1; }
[ -f "$LEDGER" ] || { echo "error: no ledger at $LEDGER" >&2; exit 1; }

fm() {  # fm <file> <key>
  awk -v key="$2" '
    NR==1 && $0=="---" { f=1; next }
    f && $0=="---" { exit }
    f { if (index($0, key ":") == 1) { sub(/^[^:]*:[ \t]*/,""); gsub(/^"|"$/,""); print; exit } }
  ' "$1" 2>/dev/null
}

rc=0
rows=""
for f in "$QUEUE"/*.md; do
  [ -e "$f" ] || continue
  slug="$(basename "$f" .md)"
  fslug="$(fm "$f" slug)"
  outcome="$(fm "$f" outcome)"
  reason="$(fm "$f" reason)"
  alias="$(fm "$f" alias)"
  release="$(fm "$f" release)"

  # The filename IS the correlation key; a disagreeing slug: field means one of the two is
  # wrong and every later lookup silently asks about a different proposal.
  if [ -n "$fslug" ] && [ "$fslug" != "$slug" ]; then
    echo "  ✗ proposals/$slug.md: slug: field says '$fslug' — the filename is the key" >&2; rc=1; continue
  fi

  case "$outcome" in
    accepted)
      # Render as the ledger has always rendered it, so a migrated row reads identically.
      if [ -n "$release" ]; then rows="$rows| \`$slug\` | shipped | $release |"$'\n'
      else                        rows="$rows| \`$slug\` | shipped | derived |"$'\n'; fi ;;
    open)
      rows="$rows| \`$slug\` | open | received $(fm "$f" received) |"$'\n' ;;
    rejected|partially-accepted)
      if [ -z "$reason" ]; then
        echo "  ✗ proposals/$slug.md: outcome '$outcome' requires a reason: — a decline the reporter cannot act on is the failure the ledger exists to fix" >&2
        rc=1; continue
      fi
      rows="$rows| \`$slug\` | $outcome | $reason |"$'\n' ;;
    alias)
      if [ -z "$alias" ]; then
        echo "  ✗ proposals/$slug.md: outcome 'alias' requires alias: naming the canonical slug" >&2; rc=1; continue
      fi
      rows="$rows| \`$slug\` | alias | $alias |"$'\n' ;;
    '')
      echo "  ✗ proposals/$slug.md: no outcome:" >&2; rc=1; continue ;;
    *)
      echo "  ✗ proposals/$slug.md: unknown outcome '$outcome'" >&2; rc=1; continue ;;
  esac
done
[ "$rc" -eq 0 ] || exit 1

blockfile="$(mktemp)"
{
  printf '%s\n' "$START"
  printf '| slug | outcome | detail |\n|---|---|---|\n'
  printf '%s' "$rows"
  printf '%s\n' "$END"
} > "$blockfile"

if ! grep -qF "$START" "$LEDGER"; then
  rm -f "$blockfile"
  echo "error: $LEDGER has no $START sentinel — add it around the table" >&2; exit 1
fi

# Splice by reading the block from a FILE, never via `awk -v`: a -v assignment cannot
# carry newlines, and the earlier version that tried silently produced an empty result
# that `mv` then installed over the real ledger. Generating into a temp and comparing
# before moving is what kept that recoverable.
tmp="$(mktemp)"
awk -v start="$START" -v end="$END" -v bf="$blockfile" '
  index($0, start) == 1 { while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
  index($0, end)   == 1 { skip=0; next }
  !skip { print }
' "$LEDGER" > "$tmp"
rm -f "$blockfile"

# A generator that empties its target has failed, whatever awk's exit status said.
if [ ! -s "$tmp" ]; then
  rm -f "$tmp"
  echo "error: refusing to write an EMPTY $LEDGER — the splice produced nothing" >&2; exit 1
fi

if cmp -s "$tmp" "$LEDGER"; then
  rm -f "$tmp"
  [ "$CHECK" = 1 ] && echo "ok: PROPOSALS.md is in sync with proposals/" || echo "ok: PROPOSALS.md already current"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  rm -f "$tmp"
  echo "  ✗ PROPOSALS.md is stale — regenerate with bin/gen-proposals-ledger.sh" >&2
  exit 2
fi

mv "$tmp" "$LEDGER"
echo "updated PROPOSALS.md from proposals/ ($(printf '%s' "$rows" | grep -c . ) entries)"
