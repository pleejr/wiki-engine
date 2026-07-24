#!/usr/bin/env bash
# verify-status.sh — report the CORRECTNESS signal (`verified:`) across a vault,
# the complement to freshness (`sources.sha` vs HEAD). See SCHEMA.md.
#
# Freshness says "nothing changed since ingest"; it never says the page was right.
# A `verified:` block records that a human/agent confirmed the content correct:
#   verified:
#     date: 2026-07-24
#     by:   preston
#     against: <sha>     # repo pages: the sources.sha it was confirmed against
#
# For a repo page the stamp is CURRENT only while verified.against == sources.sha,
# so a `wiki-repo` refresh (which bumps sources.sha) auto-demotes it to STALE. This
# check is deterministic and offline — it compares recorded fields, never fetches.
#
# Scope: repo pages (repos/*.md) are the verification universe (they carry an
# objective against-sha). Any OTHER page that carries a `verified:` block is also
# reported, but an unverified non-repo page is not "todo" (verifying curated notes
# is opt-in, not a vault-wide obligation).
#
# States: verified (against == sha) · stale (against != sha, or no sha) · unverified.
#
# Usage:
#   verify-status.sh                 human report over $WIKI_PATH
#   verify-status.sh --wiki DIR      target DIR
#   verify-status.sh --todo          print slugs needing a pass (unverified + stale
#                                    repo pages), one per line — the drainable
#                                    work-list for the upkeep loop
#   verify-status.sh --check         exit 1 if any repo page is unverified or stale
set -euo pipefail

WIKI="${WIKI_PATH:-}"
MODE="report"   # report | todo | check

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)  WIKI="$2"; shift 2;;
    --todo)  MODE="todo"; shift;;
    --check) MODE="check"; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

# Parse a page's frontmatter, tracking which top-level block we're inside, and emit
#   sha=<sources.sha>|against=<verified.against>|date=<verified.date>|by=<verified.by>|hasver=<0|1>
# sources.* and verified.* keys are disjoint, but we still scope by block to be safe.
parse() {
  awk '
    function val(l){ sub(/^[^:]*:[ \t]*/,"",l); sub(/^"/,"",l); sub(/"$/,"",l); return l }
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { done=1; exit }
    infm && /^[A-Za-z_][A-Za-z0-9_]*:/ {           # a top-level frontmatter key
      if ($0 ~ /^sources:/)       block="sources"
      else if ($0 ~ /^verified:/) { block="verified"; hasver=1 }
      else                        block=""
      next
    }
    infm && block=="sources"  && /^[ \t]+sha:/     && sha==""     { sha=val($0) }
    infm && block=="verified" && /^[ \t]+against:/ && against=="" { against=val($0) }
    infm && block=="verified" && /^[ \t]+date:/    && vdate==""   { vdate=val($0) }
    infm && block=="verified" && /^[ \t]+by:/      && vby==""     { vby=val($0) }
    END { printf "sha=%s|against=%s|date=%s|by=%s|hasver=%d", sha, against, vdate, vby, hasver+0 }
  ' "$1"
}

field() { printf '%s' "$1" | tr '|' '\n' | sed -n "s/^$2=//p"; }

verified=0 stale=0 unverified=0 other=0
report=""; todo=""

# --- repo pages: the verification universe ------------------------------------
if [ -d "$WIKI/repos" ]; then
  for f in "$WIKI/repos"/*.md; do
    [ -f "$f" ] || continue
    slug="$(basename "$f" .md)"
    p="$(parse "$f")"
    sha="$(field "$p" sha)"; against="$(field "$p" against)"
    vdate="$(field "$p" date)"; hasver="$(field "$p" hasver)"
    if [ "$hasver" != "1" ]; then
      unverified=$((unverified+1)); todo="$todo$slug"$'\n'
      report="$report  ? $slug — unverified (sha ${sha:-–})"$'\n'
    elif [ -n "$sha" ] && [ "$against" = "$sha" ]; then
      verified=$((verified+1))
      report="$report  ✓ $slug — verified ${vdate:-?} against $sha"$'\n'
    else
      stale=$((stale+1)); todo="$todo$slug"$'\n'
      report="$report  ⚠ $slug — verified-stale (against ${against:-–} ≠ sha ${sha:-–})"$'\n'
    fi
  done
fi

# --- non-repo pages that opted in with a verified: block ----------------------
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in "$WIKI/repos/"*) continue;; esac
  slug="$(basename "$f" .md)"
  p="$(parse "$f")"; [ "$(field "$p" hasver)" = "1" ] || continue
  other=$((other+1))
  report="$report  ✓ $slug — verified $(field "$p" date) (non-repo, opt-in)"$'\n'
done < <(find "$WIKI" \
  -type d \( -name .git -o -name engine -o -name .obsidian -o -name .rag -o -name raw \) -prune -o \
  -type f -name '*.md' -print | sort)

if [ "$MODE" = "todo" ]; then
  printf '%s' "$todo" | sed '/^$/d'
  exit 0
fi

printf '%s' "$report"
echo
echo "verify-status: $verified verified, $stale stale, $unverified unverified (repo pages); $other verified non-repo"

if [ "$MODE" = "check" ]; then
  [ $((stale+unverified)) -eq 0 ] || { echo "verify: $((stale+unverified)) repo page(s) need a verification pass" >&2; exit 1; }
fi
exit 0
