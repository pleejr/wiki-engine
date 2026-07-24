#!/usr/bin/env bash
# upkeep.sh — a drainable maintenance queue for a wiki vault. A live artifact
# ($WIKI/.upkeep/queue.tsv) IS the work-list: `scan` (re)builds it from the vault's
# current state, `next` pops the next pending item for the in-session agent (or a
# human) to act on, `done` marks it complete. Drain until `next` reports empty.
#
# WHY a queue and not just `status:` — a project page's status is prose, not a
# machine-drainable list. This gives upkeep backlogs (stale repo pages, un-verified
# pages) a real queue an agent can pop from, one item per iteration, to empty.
#
# NO-CLAUDE-IN-HOOKS (the hard constraint, see the vault's lesson of that name):
# increment 1 has NO spawn at all — the drain is driven by the in-session agent or a
# human calling next→act→done, so there is no lifecycle-hook/child-recursion surface.
# Any FUTURE automated driver that spawns `claude -p` per item MUST stay within the
# guards this script already sets up: it is human/cron-initiated (never a hook whose
# event a child re-triggers), carries the re-entry sentinel ($UPKEEP_DEPTH, refused
# above 0 here), is concurrency-bounded (the mkdir lock), and terminates (a finite
# scan drained to empty — it NEVER self-requeues into a watch loop).
#
# Queue sources (kinds):
#   refresh  — a repos/ page that has drifted from its local clone (best-effort,
#              offline: compares against $UPKEEP_REPOS_ROOT/<repo>). TAG-AWARE:
#              a tagged page (sources.ref != sources.sha) compares its recorded ref
#              against the clone's latest tag — so a clone sitting a commit past the
#              release tag isn't a false positive; an untagged page (ref == sha)
#              compares sha vs the clone HEAD. A clone itself behind upstream can
#              still yield a false-negative — `wiki-repo` re-ingest resolves both.
#   verify   — a repos/ page that is un-verified or verified-stale (verify-status.sh --todo).
#
# Usage:
#   upkeep.sh scan                (re)build the queue from current vault state
#   upkeep.sh list [--pending]    show the queue (all, or only pending)
#   upkeep.sh next                print the next pending item (empty ⇒ drained)
#   upkeep.sh done <id>           mark item <id> done
#   upkeep.sh --wiki DIR <cmd>    target DIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
REPOS_ROOT="${UPKEEP_REPOS_ROOT:-}"

# re-entry sentinel — insurance for any future spawning driver; harmless here.
: "${UPKEEP_DEPTH:=0}"
if [ "$UPKEEP_DEPTH" -gt 0 ]; then
  echo "upkeep: re-entry detected (UPKEEP_DEPTH=$UPKEEP_DEPTH) — refusing to recurse" >&2
  exit 3
fi

CMD=""
ARG=""
PENDING_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)     WIKI="$2"; shift 2;;
    --pending)  PENDING_ONLY=1; shift;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    scan|list|next|done) CMD="$1"; shift;;
    *) if [ -z "$CMD" ]; then echo "unknown arg: $1" >&2; exit 1; fi; ARG="$1"; shift;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$CMD" ]  || { echo "error: need a command (scan|list|next|done)" >&2; exit 1; }
[ -n "$REPOS_ROOT" ] || REPOS_ROOT="$(cd "$WIKI/.." && pwd)"   # sibling repos by default

UPKEEP_DIR="$WIKI/.upkeep"
QUEUE="$UPKEEP_DIR/queue.tsv"
LOCK="$UPKEEP_DIR/lock"
HEADER=$'# id\tkind\ttarget\tdetail\tstatus'

mkdir -p "$UPKEEP_DIR"

# mkdir is atomic — a cheap concurrency bound so two sessions can't clobber the
# queue file (cf. the vault's concurrent-session-clobber lesson).
lock()   { mkdir "$LOCK" 2>/dev/null || { echo "upkeep: queue locked (another run in progress) — $LOCK" >&2; exit 4; }; }
unlock() { rmdir "$LOCK" 2>/dev/null || true; }

# frontmatter sources.sha of a repo page (first sha under the sources block)
page_sha() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && /^sources:/       { blk=1; next }
    infm && /^[A-Za-z_]+:/    { blk=0 }
    infm && blk && /^[ \t]+(- )?sha:/ { sub(/^[^:]*:[ \t]*/,""); gsub(/[" \t]/,""); print; exit }
  ' "$1"
}
# frontmatter sources.repo (defaults to the page slug)
page_repo() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && /^sources:/       { blk=1; next }
    infm && /^[A-Za-z_]+:/    { blk=0 }
    infm && blk && /^[ \t]+(- )?repo:/ { sub(/^[^:]*:[ \t]*/,""); gsub(/[" \t]/,""); print; exit }
  ' "$1"
}
# frontmatter sources.ref (the primary freshness signal; a tag for tagged repos,
# else the same short sha as sources.sha for untagged ones)
page_ref() {
  awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && /^sources:/       { blk=1; next }
    infm && /^[A-Za-z_]+:/    { blk=0 }
    infm && blk && /^[ \t]+(- )?ref:/ { sub(/^[^:]*:[ \t]*/,""); gsub(/[" \t]/,""); print; exit }
  ' "$1"
}

build_rows() {
  # refresh: stale repo pages. TAG-AWARE — a repo page records ref (primary signal)
  # + sha. If it's TAGGED (ref != sha), compare the recorded ref against the clone's
  # latest tag, so a clone sitting a commit or two past the release tag (e.g. a
  # docs-only commit) is NOT a false "stale". Only UNTAGGED pages (ref == sha, or no
  # ref) fall back to comparing the recorded sha against the clone's HEAD.
  if [ -d "$WIKI/repos" ]; then
    for f in "$WIKI/repos"/*.md; do
      [ -f "$f" ] || continue
      slug="$(basename "$f" .md)"
      rec_sha="$(page_sha "$f")"; [ -n "$rec_sha" ] || continue
      rec_ref="$(page_ref "$f")"
      repo="$(page_repo "$f")"; [ -n "$repo" ] || repo="$slug"
      clone="$REPOS_ROOT/$repo"
      [ -d "$clone/.git" ] || continue

      if [ -n "$rec_ref" ] && [ "$rec_ref" != "$rec_sha" ]; then
        # tagged page: compare recorded tag vs the clone's latest tag
        clone_tag="$(git -C "$clone" describe --tags --abbrev=0 2>/dev/null || true)"
        if [ -n "$clone_tag" ]; then
          [ "$rec_ref" != "$clone_tag" ] && \
            printf 'refresh:%s\trefresh\trepos/%s.md\trecorded tag %s ≠ clone tag %s\tpending\n' "$slug" "$slug" "$rec_ref" "$clone_tag"
          continue
        fi
        # clone has no tags reachable — fall through to sha comparison (best-effort)
      fi

      # untagged page (or a tagged page against a tagless clone): sha vs HEAD
      head="$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || true)"
      [ -n "$head" ] || continue
      [ "$rec_sha" != "$head" ] && \
        printf 'refresh:%s\trefresh\trepos/%s.md\trecorded %s ≠ clone %s\tpending\n' "$slug" "$slug" "$rec_sha" "$head"
    done
  fi
  # verify: un-verified / verified-stale repo pages (from the verified reporter)
  if [ -x "$SCRIPT_DIR/verify-status.sh" ]; then
    while IFS= read -r slug; do
      [ -n "$slug" ] || continue
      printf 'verify:%s\tverify\trepos/%s.md\tneeds a verification pass\tpending\n' "$slug" "$slug"
    done < <("$SCRIPT_DIR/verify-status.sh" --wiki "$WIKI" --todo 2>/dev/null || true)
  fi
}

case "$CMD" in
  scan)
    lock; trap unlock EXIT
    rows="$(build_rows | LC_ALL=C sort -t$'\t' -k1,1)"
    { printf '%s\n' "$HEADER"; [ -n "$rows" ] && printf '%s\n' "$rows"; } > "$QUEUE"
    n="$(printf '%s' "$rows" | grep -c . || true)"
    echo "upkeep: scanned → $n pending item(s) in ${QUEUE#$WIKI/}"
    ;;
  list)
    [ -f "$QUEUE" ] || { echo "upkeep: no queue yet — run 'upkeep.sh scan'"; exit 0; }
    awk -F'\t' -v p="$PENDING_ONLY" '
      /^#/ { next }
      p==1 && $5!="pending" { next }
      { printf "%-24s %-8s %-22s %s [%s]\n", $1, $2, $3, $4, $5 }
    ' "$QUEUE"
    ;;
  next)
    [ -f "$QUEUE" ] || { echo "upkeep: no queue yet — run 'upkeep.sh scan'" >&2; exit 0; }
    row="$(awk -F'\t' '!/^#/ && $5=="pending" { print; exit }' "$QUEUE")"
    if [ -z "$row" ]; then echo "upkeep: queue drained — nothing pending"; exit 0; fi
    printf '%s\n' "$row" | awk -F'\t' '{ printf "next: %s\n  kind:   %s\n  target: %s\n  detail: %s\n", $1, $2, $3, $4 }'
    ;;
  done)
    [ -n "$ARG" ] || { echo "error: usage: upkeep.sh done <id>" >&2; exit 1; }
    [ -f "$QUEUE" ] || { echo "upkeep: no queue" >&2; exit 1; }
    lock; trap unlock EXIT
    grep -qF "$(printf '%s\t' "$ARG")" "$QUEUE" || { echo "upkeep: no such id: $ARG" >&2; exit 1; }
    tmp="$(mktemp)"
    awk -F'\t' -v id="$ARG" 'BEGIN{OFS="\t"} /^#/{print;next} $1==id{$5="done"} {print}' "$QUEUE" > "$tmp"
    mv "$tmp" "$QUEUE"
    echo "upkeep: marked $ARG done"
    ;;
esac
