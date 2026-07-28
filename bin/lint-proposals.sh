#!/usr/bin/env bash
#
# lint-proposals.sh — keep PROPOSALS.md and the `Proposal:` commit trailers from drifting.
#
# The ledger is the ONLY channel a consumer vault has for learning that its proposal was
# declined (a rejection produces no commit, no release note, and nothing in this repo
# otherwise). A hand-appended file rots, so the two halves are pinned against each other
# here: every trailer must have a row, every row must be well-formed, and a `Proposal:`
# line written where git's trailer parser cannot see it is a HARD FAILURE rather than a
# silent no-trailer.
#
# That last check is the load-bearing one. Git only parses trailers in the LAST paragraph
# of a commit message, so a `Proposal:` line placed mid-body yields nothing at all — CI
# would see "no trailer", demand no ledger row, and pass, while the consumer reads `open`
# forever on a proposal that shipped. Fail-open, and invisible from both ends.
#
# Deterministic; no `claude`, no network.
#
# Usage: lint-proposals.sh [--repo DIR]
#
# Needs FULL history for the trailer checks — in CI that means `fetch-depth: 0`. On a
# shallow clone the history half is SKIPPED LOUDLY rather than passing vacuously.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "lint-proposals: unknown arg: $1" >&2; exit 2;;
  esac
done
if [ -z "$REPO" ]; then
  REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
[ -d "$REPO" ] || { echo "lint-proposals: no such dir: $REPO" >&2; exit 2; }

LEDGER="$REPO/PROPOSALS.md"
FAIL=0
err()  { printf '  ✗ %s\n' "$*"; FAIL=$((FAIL+1)); }
note() { printf '  · %s\n' "$*"; }

echo "lint-proposals: $LEDGER"
[ -f "$LEDGER" ] || { err "PROPOSALS.md missing"; exit 1; }

# ---------------------------------------------------------------- parse rows --
# Only the table under `## Ledger` is data; the doc above it has explanatory tables
# of its own, and parsing those would report the column glossary as malformed rows.
ROWS="$(awk '
  /^## Ledger[[:space:]]*$/ { inledger=1; next }
  /^## / { inledger=0 }
  inledger && /^\|/ {
    if ($0 ~ /^\|[[:space:]]*slug[[:space:]]*\|/) next     # header
    if ($0 ~ /^\|[[:space:]]*-+/) next                     # separator
    print
  }
' "$LEDGER")"

[ -n "$ROWS" ] || { err "no rows under '## Ledger'"; exit 1; }

declare -a SLUGS=() OUTCOMES=() DETAILS=()
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

while IFS= read -r line; do
  [ -n "$line" ] || continue
  # split on '|'; a well-formed row is  | a | b | c |  -> a leading empty field plus the
  # three cells (bash's `read -a` drops the empty field after the trailing pipe)
  [ "${line: -1}" = "|" ] || { err "row does not end with '|': $line"; continue; }
  IFS='|' read -r -a f <<<"$line"
  if [ "${#f[@]}" -ne 4 ]; then
    err "row has $(( ${#f[@]} - 1 )) cell(s), want 3 (| slug | outcome | detail |): $line"
    continue
  fi
  slug="$(trim "${f[1]}")"; outcome="$(trim "${f[2]}")"; detail="$(trim "${f[3]}")"
  slug="${slug#\`}"; slug="${slug%\`}"          # rows write the slug as `code`
  detail_bare="${detail#\`}"; detail_bare="${detail_bare%\`}"

  if ! [[ "$slug" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    err "slug not [a-z0-9][a-z0-9._-]*: '$slug'"; continue
  fi
  case "$outcome" in
    open|shipped|partially-accepted|rejected|alias) ;;
    *) err "$slug: unknown outcome '$outcome' (open|shipped|partially-accepted|rejected|alias)"; continue;;
  esac
  [ -n "$detail" ] || { err "$slug: empty detail column"; continue; }

  # a decline the reporter cannot act on is the failure this whole file exists to fix
  if [ "$outcome" = "rejected" ] || [ "$outcome" = "partially-accepted" ]; then
    if [ "${#detail}" -lt 12 ]; then
      err "$slug: '$outcome' needs a reason in the detail column, got '$detail'"
    fi
  fi
  if [ "$outcome" = "shipped" ]; then
    if [ "$detail" != "derived" ] && ! [[ "$detail" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      err "$slug: 'shipped' detail must be 'derived' or an explicit vX.Y.Z, got '$detail'"
    fi
  fi

  for s in "${SLUGS[@]:-}"; do
    [ "$s" = "$slug" ] && err "duplicate slug '$slug' — the slug is the only correlation key"
  done
  SLUGS+=("$slug"); OUTCOMES+=("$outcome"); DETAILS+=("$detail_bare")
done <<<"$ROWS"

row_index() {  # slug -> index, or empty
  local want="$1" i
  for i in "${!SLUGS[@]}"; do [ "${SLUGS[$i]}" = "$want" ] && { printf '%s' "$i"; return 0; }; done
  return 1
}

# ------------------------------------------------------------------- aliases --
# Recording an alias is not resolving one: an alias pointing at nothing leaves the
# reporter exactly where the rename put them.
for i in "${!SLUGS[@]}"; do
  [ "${OUTCOMES[$i]}" = "alias" ] || continue
  tgt="${DETAILS[$i]}"
  if ! j="$(row_index "$tgt")"; then
    err "${SLUGS[$i]}: alias target '$tgt' has no row"; continue
  fi
  [ "${OUTCOMES[$j]}" = "alias" ] && err "${SLUGS[$i]}: alias chains to another alias ('$tgt') — point at the canonical row"
done

note "${#SLUGS[@]} row(s) parsed"

# ------------------------------------------------------------------- history --
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  note "not a git repo — trailer checks skipped"
elif [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  # a check that silently sees no commits is decoration; say so instead of passing
  echo "  ! SHALLOW clone — trailer checks SKIPPED. CI must use fetch-depth: 0." >&2
  FAIL=$((FAIL+1))
else
  RS=$'\x1e'; US=$'\x1f'
  stream="$(git -C "$REPO" log --format="%H${US}%(trailers:key=Proposal,valueonly,separator=%x2c)${US}%B${RS}" 2>/dev/null)"

  seen_trailers=0
  declare -a TRAILED=()
  # herestring, not a pipe: the loop must run in THIS shell or every slug it records
  # is lost with the subshell and the derived-release check below silently passes
  while IFS= read -r -d "$RS" rec; do
    [ -n "${rec//[$'\n\r\t ']/}" ] || continue
    sha="${rec%%"$US"*}"; sha="${sha#$'\n'}"
    rest="${rec#*"$US"}"
    parsed="${rest%%"$US"*}"
    body="${rest#*"$US"}"

    # LITERAL lines are authoritative, not git's trailer parser. Placement used to be
    # required — `Proposal:` had to sit in the final paragraph, or `%(trailers)` ignored it
    # and lint hard-failed. But the documented workflow PRODUCES the rejected state: the
    # slug goes in the PR description's last paragraph (merges here are squashed), and
    # GitHub then appends its own `---------` + `Co-authored-by:` footer, which becomes the
    # last block. So following the instructions guaranteed the failure, and it was only
    # detectable AFTER the merge, when the sole remedy is rewriting published history.
    #
    # Placement was never what the slug is FOR. It is a correlation key; git-parseability
    # bought nothing except compatibility with %(trailers), an implementation detail of
    # this script and `engine-proposal.sh status` — both of which this repo owns. Reading
    # the line wherever it appears makes GitHub's footer irrelevant, and with that the
    # placement error has nothing left to protect: an unparsed line is no longer read as
    # untagged. `parsed` is still collected, but only to report the divergence as a note.
    #
    # FENCED AND INDENTED LINES ARE SKIPPED. Under the old scheme a commit that quoted the
    # convention at column 0 tripped the count mismatch — loud, and fixable by indenting.
    # Reading literally would instead have silently registered the quote as a real trailer,
    # so the quote-handling has to move from "error out" to "don't look there".
    lits="$(printf '%s\n' "$body" | awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^Proposal:[[:space:]]*[^[:space:]]/ { sub(/^Proposal:[[:space:]]*/, ""); print }
    ')"
    vals=()
    while IFS= read -r line; do [ -n "$line" ] && vals+=("$line"); done <<<"$lits"

    # Divergence is informational now, not a failure: it only means `git log --format=
    # '%(trailers:key=Proposal)'` will not show what this script correctly found.
    if [ -n "$parsed" ]; then pcount="$(printf '%s' "$parsed" | tr ',' '\n' | grep -c . || true)"; else pcount=0; fi
    if [ "${#vals[@]}" -gt "$pcount" ]; then
      note "${sha:0:9}: 'Proposal:' is outside the final paragraph — read literally, but git's own trailer parser will not see it"
    fi

    for v in "${vals[@]:-}"; do
      v="$(trim "$v")"; [ -n "$v" ] || continue
      seen_trailers=$((seen_trailers+1)); TRAILED+=("$v")
      # Resolve the citation against the QUEUE, which is the source of truth, falling back
      # to the table for a repo with no queue. Keying it on the DERIVED table was wrong in
      # a way only using it exposed: merging a proposal PR IS the arrival record by design, and
      # that necessarily makes the table stale — so every arrival turned main red until
      # someone regenerated by hand, reintroducing the exact manual step the queue removed.
      k=""
      if [ -d "$REPO/proposals" ] && [ -f "$REPO/proposals/$v.md" ]; then
        qa="$(awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&index($0,"alias:")==1{sub(/^[^:]*:[ \t]*/,"");print;exit}' "$REPO/proposals/$v.md" 2>/dev/null)"
        if [ -n "$qa" ] && [ ! -f "$REPO/proposals/$qa.md" ] && ! row_index "$qa" >/dev/null; then
          err "${sha:0:9}: trailer '$v' aliases to '$qa', which is neither a queue entry nor a row"
        fi
      elif ! k="$(row_index "$v")"; then
        err "${sha:0:9}: trailer 'Proposal: $v' has no proposal in proposals/ and no row in PROPOSALS.md"
        continue
      fi
      if [ -n "$k" ] && [ "${OUTCOMES[$k]}" = "alias" ]; then
        row_index "${DETAILS[$k]}" >/dev/null || err "${sha:0:9}: trailer '$v' aliases to a missing row"
      fi
    done
  done <<<"$stream"
  # The ledger is GENERATED from proposals/. A stale table is the same class of failure as
# skills/projects catalog drift: the file people read stops matching the source of truth,
# and nothing says so. Checked here rather than only in CI so a pre-commit run catches it.
if [ -d "$REPO/proposals" ] && [ -x "$SCRIPT_DIR/gen-proposals-ledger.sh" ]; then
  if ! "$SCRIPT_DIR/gen-proposals-ledger.sh" --repo "$REPO" --check >/dev/null 2>&1; then
    # A NOTE, not an error: the queue is authoritative and the table renders it. An
    # arrival makes the table stale by construction, and failing the build for that
    # punishes the merge which IS the arrival record.
    note "PROPOSALS.md is stale relative to proposals/ — run bin/gen-proposals-ledger.sh (cosmetic; the queue is authoritative)"
  else
    note "PROPOSALS.md is in sync with the proposals/ queue"
  fi
fi

note "$seen_trailers trailer(s) seen in history"

  # `shipped | derived` asserts the release is READ FROM GIT — so a trailer has to exist,
  # or `status` resolves it to nothing and reports a shipped proposal as merged-not-released.
  for i in "${!SLUGS[@]}"; do
    [ "${OUTCOMES[$i]}" = "shipped" ] && [ "${DETAILS[$i]}" = "derived" ] || continue
    hit=0
    for t in "${TRAILED[@]:-}"; do [ "$t" = "${SLUGS[$i]}" ] && { hit=1; break; }; done
    [ "$hit" -eq 1 ] || err "${SLUGS[$i]}: 'shipped | derived' but no commit carries its trailer — give an explicit vX.Y.Z, or add the trailer"
  done

  # an explicit version is a backfill claim; if tags are present it must name a real one
  if [ -n "$(git -C "$REPO" tag -l 'v*' 2>/dev/null | head -1)" ]; then
    for i in "${!SLUGS[@]}"; do
      [ "${OUTCOMES[$i]}" = "shipped" ] && [ "${DETAILS[$i]}" != "derived" ] || continue
      git -C "$REPO" rev-parse -q --verify "refs/tags/${DETAILS[$i]}" >/dev/null \
        || err "${SLUGS[$i]}: detail '${DETAILS[$i]}' is not a tag in this repo"
    done
  fi
fi

if [ "$FAIL" -eq 0 ]; then echo "lint-proposals: OK"; exit 0; fi
echo "lint-proposals: $FAIL problem(s)" >&2; exit 1
