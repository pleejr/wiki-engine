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
#              SELF-PAGE: a vault that documents itself has one page whose clone IS
#              this vault. Its sha-vs-HEAD test is structurally unsatisfiable —
#              recording the new sha is itself a commit, which advances HEAD and
#              re-stales the page it just refreshed — so that page would sit in the
#              queue forever. Only the sha branch is suppressed; a TAGGED self-page
#              still compares tags, which do not move on every commit.
#   verify   — a repos/ page that is un-verified or verified-stale (verify-status.sh --todo).
#   unresolvable — a repos/ page whose clone cannot be found at $UPKEEP_REPOS_ROOT/<repo>,
#              so its freshness could not be assessed AT ALL. Reported rather than
#              skipped: the page the tool could not examine is the one most likely to be
#              wrong, and a silent skip made a clean queue mean "every page whose clone I
#              could find is current" while reading as "every page is current". Drainable
#              either way — fix sources.repo if the clone lives under another directory
#              name, or clone it on this machine.
#
# Usage:
#   upkeep.sh sync-clones [--check]   ff-only pull the clones backing repo pages
#   upkeep.sh scan                (re)build the queue from current vault state
#   upkeep.sh list [--pending]    show the queue (all, or only pending)
#   upkeep.sh next                print the next pending item (empty ⇒ drained)
#   upkeep.sh done <id>           mark item <id> done
#   upkeep.sh --wiki DIR <cmd>    target DIR
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
REPOS_ROOT="${UPKEEP_REPOS_ROOT:-}"
# How long an untouched project page may go before it is queued. Vault knobs, because
# "how often should an active project move?" is a property of the consumer's cadence, not
# of the engine. Conservative defaults: a fortnight for active work, a quarter before
# asking whether a paused project should still be paused.
STALE_ACTIVE_DAYS="${UPKEEP_STALE_ACTIVE_DAYS:-14}"
STALE_PAUSED_DAYS="${UPKEEP_STALE_PAUSED_DAYS:-90}"

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
    scan|list|next|done|sync-clones) CMD="$1"; shift;;
    *) if [ -z "$CMD" ]; then echo "unknown arg: $1" >&2; exit 1; fi; ARG="$1"; shift;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$CMD" ]  || { echo "error: need a command (sync-clones|scan|list|next|done)" >&2; exit 1; }
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


# --- project-page staleness -----------------------------------------------------
# Project pages had NO decay signal. A repo page carries ref/sha provenance and a
# verified: stamp, and both feed this queue; a project page nobody has touched in weeks
# rendered identically to one confirmed accurate yesterday, and every gate passed on both.
#
# THE AGE IS DERIVED, NOT READ FROM A HAND-MAINTAINED FIELD. The proposal keyed on
# frontmatter `updated:`; measured against a real vault, two of three active project pages
# disagreed with git by three days — drifting toward LOOKING STALE, so a queue built on it
# fires on pages that were in fact touched. Same rule that keeps `shipped` derived:
# hand-maintained status drifts and a derived answer cannot.
#
# We take the NEWEST of three signals, and report which one answered:
#   reviewed:        an explicit "I read this and it is still right" (see below)
#   git last-commit  derived, cannot be forgotten
#   updated:         last resort, for a page git does not track yet
#
# WHY `reviewed:` EXISTS AT ALL. Without it an item can never be cleared: confirming a page
# is still accurate changes nothing, so the item re-fires on every scan and the queue is
# permanently non-empty — the always-red failure this engine keeps re-learning. Bumping
# `reviewed:` IS the drain, and it is a real commit recording a real act.
#
# HONEST LIMIT, stated because a fresh clock is not evidence of review: a bulk reflow or an
# index regeneration bumps the git date with nobody having read the page. `reviewed:` is the
# only signal that cannot be satisfied mechanically.
page_field() {  # page_field <file> <key>
  awk -v key="$2" '
    NR==1 && $0=="---" { f=1; next }
    f && $0=="---" { exit }
    f { if (index($0, key ":") == 1) { sub(/^[^:]*:[ \t]*/,""); gsub(/^"|"$/,""); print; exit } }
  ' "$1" 2>/dev/null
}

days_since() {  # days_since <YYYY-MM-DD> -> integer days, or empty if unparseable
  [ -n "$1" ] || return 0
  # Validate the SHAPE before handing it to date(1). BSD `date -j -f` parses a leading
  # date and ignores trailing garbage, while GNU `date -d` rejects the same string — so a
  # malformed value was silently accepted on macOS and reported unassessable on Linux.
  # A check whose answer depends on which date(1) is installed is not a check.
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) return 0 ;;
  esac
  local t
  t="$(date -j -f %Y-%m-%d "$1" +%s 2>/dev/null)" || t="$(date -d "$1" +%s 2>/dev/null)" || return 0
  [ -n "$t" ] || return 0
  echo $(( ( $(date +%s) - t ) / 86400 ))
}

project_rows() {
  [ -d "$WIKI/projects" ] || return 0
  local f slug status rev upd gitd best src age limit
  for f in "$WIKI/projects"/*.md; do
    [ -f "$f" ] || continue
    slug="$(basename "$f" .md)"
    status="$(page_field "$f" status)"

    # Status decides WHICH QUESTION is being asked, and for one status there is no question.
    case "$status" in
      done)    continue ;;                                   # closed: expected never to move
      active)  limit="$STALE_ACTIVE_DAYS" ;;
      paused|planned)
               # Not "is this current?" — a paused project is SUPPOSED to sit untouched.
               # The longer horizon asks "should this still be paused?", a different and
               # less urgent question, so it gets its own threshold.
               limit="$STALE_PAUSED_DAYS" ;;
      *)       # An unknown or missing status is not silently skipped: it is exactly the
               # page most likely to be wrong, and skipping it would recreate the invisible
               # failure this whole queue exists to remove.
               printf 'stale:%s	stale	projects/%s.md	unassessable — status %s is not one of planned|active|paused|done	pending
' \
                 "$slug" "$slug" "${status:-<missing>}"
               continue ;;
    esac

    rev="$(page_field "$f" reviewed)"
    upd="$(page_field "$f" updated)"
    gitd="$(git -C "$WIKI" log -1 --format=%ad --date=short -- "projects/$slug.md" 2>/dev/null || true)"

    best=""; src=""
    for cand in "reviewed:$rev" "git:$gitd" "updated:$upd"; do
      d="${cand#*:}"; [ -n "$d" ] || continue
      if [ -z "$best" ] || [ "$d" \> "$best" ]; then best="$d"; src="${cand%%:*}"; fi
    done

    if [ -z "$best" ]; then
      printf 'stale:%s	stale	projects/%s.md	unassessable — no reviewed:, no git history, no updated:	pending
' "$slug" "$slug"
      continue
    fi
    age="$(days_since "$best")"
    [ -n "$age" ] || { printf 'stale:%s	stale	projects/%s.md	unassessable — could not parse date %s	pending
' "$slug" "$slug" "$best"; continue; }
    if [ "$age" -gt "$limit" ]; then
      printf 'stale:%s	stale	projects/%s.md	%s project untouched %sd (limit %sd, by %s %s) — reconcile or bump reviewed:	pending
' \
        "$slug" "$slug" "$status" "$age" "$limit" "$src" "$best"
    fi
  done
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
      # AN UNLOCATABLE CLONE IS ITS OWN ANSWER, NOT "up to date". This used to be a bare
      # `continue`: a page whose clone sits under a directory name differing from its
      # sources.repo (a rename, a disambiguating prefix, a second checkout) was dropped
      # from the freshness comparison and NO row of any kind was emitted about it. The
      # failure was disguised rather than merely quiet — such a page still appears via the
      # verify: path, which needs no clone, so the operator drains it and reasonably
      # concludes it was attended to while the freshness question was never asked. It also
      # silently changed what a clean queue MEANS: "every repo page matches its clone"
      # became "every repo page whose clone I could find matches".
      #
      # The scan already holds exactly this principle for project pages with an unknown
      # status — "it is exactly the page most likely to be wrong, and skipping it would
      # recreate the invisible failure this whole queue exists to remove". The defect was
      # applying it to one page type and not the other.
      #
      # It reports rather than guesses. Searching the repos root for a directory whose
      # remote matches would bind the page to an unrelated second checkout of the same
      # upstream; hard-erroring would punish a page legitimately not cloned on THIS
      # machine, which is a normal state on a multi-machine vault. Both possibilities are
      # named in the detail, because the row is drainable by a real action in either case.
      if [ ! -d "$clone/.git" ]; then
        printf 'unresolvable:%s\tunresolvable\trepos/%s.md\tno clone at %s — freshness unknown, not up to date (fix sources.repo if it is cloned under another name, or clone it here)\tpending\n' \
          "$slug" "$slug" "$clone"
        continue
      fi

      if [ -n "$rec_ref" ] && [ "$rec_ref" != "$rec_sha" ]; then
        # tagged page: compare recorded tag vs the clone's latest tag.
        #
        # TOLERATE A GIT-DESCRIBE REF. The convention is `ref: <latest release tag>`
        # (SCHEMA), but it was never enforced, and ingest commonly recorded the full
        # describe form vX.Y.Z-<N>-g<sha> instead. That never equals a clean tag, so
        # EVERY such page was flagged for refresh forever — a queue where the one
        # genuinely-stale page is buried among dozens of false ones is not a queue
        # anyone drains, which is the same "a signal that always fires stops being
        # read" failure as the always-kept gc branch and the always-red integrate.
        #
        # Normalising to the base tag loses nothing: the describe suffix's extra
        # information (commit count + sha) is already carried by sources.sha, and the
        # verify axis is the one that uses it. The two staleness axes stay independent.
        rec_base="$(printf '%s' "$rec_ref" | sed -E 's/-[0-9]+-g[0-9a-f]{7,}$//')"
        clone_tag="$(git -C "$clone" describe --tags --abbrev=0 2>/dev/null || true)"
        if [ -n "$clone_tag" ]; then
          [ "$rec_base" != "$clone_tag" ] && \
            printf 'refresh:%s\trefresh\trepos/%s.md\trecorded tag %s ≠ clone tag %s\tpending\n' "$slug" "$slug" "$rec_base" "$clone_tag"
          continue
        fi
        # clone has no tags reachable — fall through to sha comparison (best-effort)
      fi

      # untagged page (or a tagged page against a tagless clone): sha vs HEAD.
      # Skip the SELF-PAGE here — the vault documenting its own repo. Refreshing it
      # commits a new sha, which advances the very HEAD it is compared against, so
      # the test can never come out equal and the item is perpetual queue noise.
      # Resolved by path (physical, so a symlinked vault still matches), not by
      # name — nothing consumer-specific is baked in.
      if [ "$(cd "$clone" && pwd -P)" = "$(cd "$WIKI" && pwd -P)" ]; then
        continue
      fi
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
  # stale: project pages whose age exceeds the status-appropriate threshold
  project_rows
}

case "$CMD" in
  sync-clones)
    # WHY THIS IS A SEPARATE, DELIBERATE VERB AND NOT PART OF scan.
    # scan and verify-status measure freshness against the LOCAL clone's HEAD, offline
    # and deterministically. That is right and load-bearing: it is what lets them run
    # anywhere, including with no network and on intentionally pinned clones. But it
    # means a drain is only as current as the clones on this machine — and a lagging
    # clone produces a FALSE NEGATIVE: the page refreshes, `verified:` is stamped
    # against a sha behind the real release, and the vault reports a clean fully-
    # verified state that is quietly wrong. The failure is invisible in exactly the
    # output meant to surface staleness, and the cost is a second full drain once
    # someone notices. So the network step is opt-in and explicit; folding a fetch into
    # a "just tell me what is stale" command would trade that determinism away and add
    # latency and failure modes to a read-only-sounding verb.
    #
    # CONSERVATIVE BY CONSTRUCTION. Every state is DECIDED before anything is touched,
    # and only a proven fast-forward is applied. No force, no stash, no rebase, and no
    # merge that could ever create a commit: `git merge --ff-only` is issued solely
    # after `merge-base --is-ancestor` has already proven the fast-forward. `git pull`
    # is deliberately NOT used — it consults pull.rebase and friends, so what it
    # actually does depends on the operator's config rather than on this code.
    #
    # A SKIP IS A REPORTED OUTCOME, NOT AN ERROR. Silence about a clone the tool
    # refuses to touch would recreate the original bug one level up: the operator would
    # again believe everything was current when it was not.
    # --check arrives via the shared parser's ARG slot, not as a positional here
    sc_check=""
    [ "$ARG" = "--check" ] && sc_check=1
    [ -d "$WIKI/repos" ] || { echo "upkeep: no repos/ — nothing to sync"; exit 0; }
    synced=0; skipped=0; current=0
    for f in "$WIKI/repos"/*.md; do
      [ -f "$f" ] || continue
      slug="$(basename "$f" .md)"
      repo="$(page_repo "$f")"; [ -n "$repo" ] || repo="$slug"
      clone="$REPOS_ROOT/$repo"
      # Named, like every other skip here — this verb's own doctrine is that a skip is a
      # reported outcome, and it already applied that to a dirty tree and a detached HEAD
      # while staying silent about the one case where the clone cannot be found at all.
      if [ ! -d "$clone/.git" ]; then
        printf '  skip   %-28s no clone at %s\n' "$repo" "$clone"; skipped=$((skipped+1)); continue
      fi

      # THE VAULT'S OWN CLONE IS NEVER TOUCHED. A vault that documents itself has one
      # page whose clone IS this vault — the tree a session is working in, possibly
      # with a live worktree holding uncommitted work. Pulling it underneath that is
      # the exact hazard the concurrency model exists to prevent, and no freshness
      # benefit could justify it. Matched by physical path, as the scan does.
      if [ "$(cd "$clone" && pwd -P)" = "$(cd "$WIKI" && pwd -P)" ]; then
        printf '  skip   %-28s this vault'"'"'s own checkout — never pulled from under a session\n' "$repo"
        skipped=$((skipped+1)); continue
      fi
      if [ -n "$(git -C "$clone" status --porcelain 2>/dev/null)" ]; then
        printf '  skip   %-28s uncommitted changes\n' "$repo"; skipped=$((skipped+1)); continue
      fi
      br="$(git -C "$clone" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      if [ -z "$br" ]; then
        printf '  skip   %-28s detached HEAD\n' "$repo"; skipped=$((skipped+1)); continue
      fi
      if ! up="$(git -C "$clone" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
        printf '  skip   %-28s %s tracks no upstream\n' "$repo" "$br"; skipped=$((skipped+1)); continue
      fi
      if [ -n "$sc_check" ]; then
        # Deliberately hedged: divergence is only knowable AFTER a fetch, so --check
        # can report what it would attempt but must not promise the fast-forward.
        printf '  would  %-28s fetch %s, then ff-only if it is one\n' "$repo" "$up"; continue
      fi
      if ! git -C "$clone" fetch --quiet 2>/dev/null; then
        printf '  skip   %-28s fetch failed (offline?)\n' "$repo"; skipped=$((skipped+1)); continue
      fi
      local_sha="$(git -C "$clone" rev-parse HEAD 2>/dev/null)"
      up_sha="$(git -C "$clone" rev-parse '@{u}' 2>/dev/null)"
      if [ "$local_sha" = "$up_sha" ]; then
        printf '  current %-27s %s\n' "$repo" "$br"; current=$((current+1)); continue
      fi
      # Decide BEFORE acting: only a proven fast-forward is applied. Anything else —
      # diverged, or upstream rewound — is reported and left exactly as it was.
      if git -C "$clone" merge-base --is-ancestor HEAD '@{u}' 2>/dev/null; then
        if git -C "$clone" merge --ff-only --quiet '@{u}' 2>/dev/null; then
          printf '  synced %-28s %s -> %s\n' "$repo" "${local_sha:0:9}" "$(git -C "$clone" rev-parse --short HEAD)"
          synced=$((synced+1))
        else
          printf '  skip   %-28s fast-forward refused by git\n' "$repo"; skipped=$((skipped+1))
        fi
      else
        printf '  skip   %-28s diverged from %s\n' "$repo" "$up"; skipped=$((skipped+1))
      fi
    done
    if [ -n "$sc_check" ]; then
      echo "upkeep: sync-clones --check — nothing was fetched or modified"
    else
      printf 'upkeep: sync-clones — %d synced, %d already current, %d skipped (skips are reported, not errors)\n' \
        "$synced" "$current" "$skipped"
      echo "upkeep: now run 'upkeep.sh scan' so the queue reflects the updated clones"
    fi
    ;;
  scan)
    lock; trap unlock EXIT
    rows="$(build_rows | LC_ALL=C sort -t$'\t' -k1,1)"
    { printf '%s\n' "$HEADER"; [ -n "$rows" ] && printf '%s\n' "$rows"; } > "$QUEUE"
    n="$(printf '%s' "$rows" | grep -c . || true)"
    echo "upkeep: scanned → $n pending item(s) in ${QUEUE#$WIKI/}"
    # Called out separately because these are the pages the scan could NOT assess. Folded
    # into the total they read as ordinary work; omitted entirely — which is what used to
    # happen — a drained queue would keep meaning more than it can.
    u="$(printf '%s' "$rows" | grep -c '^unresolvable:' || true)"
    if [ "${u:-0}" -gt 0 ]; then
      echo "upkeep: $u of those are repo pages with no locatable clone — their freshness is UNKNOWN, not current"
    fi
    ;;
  list)
    [ -f "$QUEUE" ] || { echo "upkeep: no queue yet — run 'upkeep.sh scan'"; exit 0; }
    awk -F'\t' -v p="$PENDING_ONLY" '
      /^#/ { next }
      p==1 && $5!="pending" { next }
      { printf "%-24s %-12s %-22s %s [%s]\n", $1, $2, $3, $4, $5 }
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
