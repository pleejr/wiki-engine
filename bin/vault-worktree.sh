#!/usr/bin/env bash
# vault-worktree.sh — give a vault-writing session its own git worktree so two concurrent
# Claude Code sessions can never clobber each other's edits or HEAD in the single shared
# $WIKI_PATH working tree. Deterministic (plain git, no LLM, no claude) — the isolation
# mechanism the `checkpoint` skill uses before it writes.
#
# Why: two sessions sharing one working dir also share one HEAD and one set of files on
# disk. `git checkout -b` in one moves HEAD under the other; simultaneous writes to the
# same page are last-writer-wins on disk BEFORE git ever sees them (no conflict, silent
# loss). Separate worktrees (own dir + own HEAD, shared .git) make each session
# independent, so real overlap surfaces as a visible merge/PR conflict instead. Measured
# cost is ~0.4s and <1 MB: only tracked text is checked out — the untracked .rag/ index
# and the (submodule) engine are NOT duplicated, so skills run engine tooling from the
# canonical $WIKI_PATH and rebuild RAG there after integrating.
#
# CONCURRENCY MODEL (four layers, each covering what the one below cannot):
#   1. ISOLATION  — `ensure` gives each writing session its own worktree. Prevents the
#      filesystem race: two sessions editing one file in one tree is last-writer-wins on
#      disk BEFORE git sees it, so no lock at the commit step can help.
#   2. ENFORCEMENT — `guard` refuses a commit made in the canonical checkout, so the
#      unsafe path can't be taken by habit. Isolation that is merely available gets
#      skipped; this is what made a session sweep a peer's work into its own commit with
#      `git add -A`. Wire it from the vault's pre-commit hook.
#   3. VISIBILITY — `lease` records which paths a session intends to write and `peers`
#      shows live sessions. ADVISORY ON PURPOSE: git's merge is the authority on real
#      conflicts, and a lease that refused overlap would block the common, harmless case
#      of two sessions touching one index file. Its job is to make a collision course
#      visible EARLY, while it is still cheap to re-plan.
#   4. SERIALIZATION — `integrate` merges a session branch to main under an atomic lock,
#      so N sessions (or N agents) converge one at a time instead of racing HEAD.
#
# Usage:
#   vault-worktree.sh ensure       # idempotent; print the worktree path to write in
#   vault-worktree.sh guard        # exit 1 if run in the canonical checkout (pre-commit)
#   vault-worktree.sh lease [P...] # declare intended paths; warn on overlap with peers
#   vault-worktree.sh claim [SLUG] # declare the PROJECT this session is working; with no
#                                  #   slug, report every claim and whether it is live or
#                                  #   STALE. Advisory, never blocking — see the verb.
#   vault-worktree.sh peers        # live sessions, their branches and declared paths
#   vault-worktree.sh integrate    # locked: rebase this session's branch, ff main to it
#   vault-worktree.sh gc [path...] # with paths: retire exactly those now (clean-only, no
#                                  #   age gate). Bare: sweep clean orphans older than
#                                  #   WIKI_WT_STALE_HOURS. Both never discard uncommitted work.
#   vault-worktree.sh list         # list the vault's worktrees
#
# Env:
#   WIKI_PATH             the vault root (required)
#   WIKI_WORKTREE=0       opt out — `ensure` prints $WIKI_PATH, `guard` passes (single-
#                         session machine, or a deliberate legacy direct-to-main flow)
#   WIKI_WT_SESSION       stable session id so repeat `ensure` calls reuse one worktree.
#                         Defaults to $CLAUDE_CODE_SESSION_ID when unset, so a skill that
#                         calls `ensure` more than once in a session reuses a single
#                         worktree without having to thread an id through every call.
#   WIKI_WORKTREE_ROOT    parent dir for worktrees (default $WIKI_PATH/.worktrees, git-excluded)
#   WIKI_WT_STALE_HOURS   bare-`gc` age threshold for a clean orphan (default 48)
#   WIKI_LEASE_STALE_MIN  a lease unrefreshed this long counts as dead (default 120). The
#                         clock is the FALLBACK: a session whose worktree and branch are
#                         both gone has provably finished and is dead immediately.
#   WIKI_LOCK_WAIT_SEC    how long `integrate` waits for the lock (default 120)
#   VAULT_INTEGRATE=1     set by `integrate`; lets the guard allow its own merge commit
set -uo pipefail

log() { printf '%s\n' "$*" >&2; }

WIKI="${WIKI_PATH:-}"
[ -n "$WIKI" ] || { log "vault-worktree: WIKI_PATH not set"; exit 2; }
WIKI="$(cd "$WIKI" 2>/dev/null && pwd)" || { log "vault-worktree: cannot cd to WIKI_PATH ($WIKI_PATH)"; exit 2; }
git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || { log "vault-worktree: $WIKI is not a git repo"; exit 2; }

CMD="${1:-ensure}"
WT_ROOT="${WIKI_WORKTREE_ROOT:-$WIKI/.worktrees}"
EXCLUDE="$WIKI/.git/info/exclude"
LEASE_DIR="$WT_ROOT/.leases"
LOCK="$WT_ROOT/.integrate.lock"
LEASE_STALE_MIN="${WIKI_LEASE_STALE_MIN:-120}"

now_epoch() { date +%s; }

# This session's id — the same key `ensure` uses for its worktree, so a lease and a
# worktree always belong together.
session_id() {
  local s="${WIKI_WT_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
  [ -n "$s" ] || s="anon-$$"
  printf '%s' "$s" | tr -c 'A-Za-z0-9._-' '-'
}

lease_file() { printf '%s/%s.lease' "$LEASE_DIR" "$(session_id)"; }

# key=value read from a lease file (values never contain newlines)
lease_get() { awk -F= -v k="$2" '$1==k { sub(/^[^=]*=/,""); print; exit }' "$1" 2>/dev/null; }

# A session that FINISHED CLEANLY leaves proof: `integrate` merged its branch and `gc`
# removed both the worktree and the branch. When both are gone the lease describes a
# session that cannot still be writing, whatever its heartbeat says — so this is stronger
# evidence than the clock, and it is available immediately instead of LEASE_STALE_MIN
# later. Without it a finished session is reported as a live peer for up to two hours,
# and a registry that shows ghosts stops being read.
#
# Deliberately conservative — it answers "provably finished", never "probably gone":
#   - worktree still on disk     -> not proven (a crashed session leaves its worktree)
#   - branch still exists        -> not proven (unintegrated commits; nothing may delete it)
#   - worktree is the CANONICAL checkout -> unjudgeable, since `lease` run from canonical
#     records canonical, which never disappears. Falls through to the clock.
# Anything not proven dead stays subject to the heartbeat test below, so a crashed
# session is still reaped on time as before.
lease_finished() {
  local wt br
  wt="$(lease_get "$1" worktree)"; br="$(lease_get "$1" branch)"
  [ -n "$wt" ] && [ -n "$br" ] || return 1
  [ "$wt" != "$WIKI" ] || return 1
  [ ! -d "$wt" ] || return 1
  [ -z "$(git -C "$WIKI" branch --list "$br" 2>/dev/null)" ] || return 1
  return 0
}

# A lease is LIVE if its session has not provably finished AND it was refreshed within
# LEASE_STALE_MIN. The clock is the fallback, not the only test: it is time-based rather
# than pid-based because the pid recorded here is the helper script's, not the agent's,
# and dies immediately — so for a session that simply stops, liveness can only come from
# it continuing to touch its lease.
#
# Decided in ONE place so `peers`, `for_other_live_leases` and `gc` cannot disagree about
# who is live — three call sites re-deriving this is how a guard ends up wrong differently
# in each of them.
lease_live() {
  lease_finished "$1" && return 1
  local hb; hb="$(lease_get "$1" heartbeat)"
  [ -n "$hb" ] || return 1
  [ $(( $(now_epoch) - hb )) -lt $(( LEASE_STALE_MIN * 60 )) ]
}

# Create/refresh this session's lease. Paths are optional and additive-by-replacement:
# passing none refreshes the heartbeat and keeps whatever was declared before.
write_lease() {
  local wt="$1" branch="$2"; shift 2
  local f; f="$(lease_file)"
  local prev_paths=""
  [ -f "$f" ] && prev_paths="$(lease_get "$f" paths)"
  local paths="$*"; [ -n "$paths" ] || paths="$prev_paths"
  # The project this session declared, if any. Carried on the SAME record as the paths,
  # for the same reason `lease_live` is decided in one place: a second presence store with
  # its own liveness rule can disagree with this one about who is working, and disagreement
  # about that is worse than no answer at all.
  local project="${CLAIM_PROJECT:-}"
  [ -n "$project" ] || { [ -f "$f" ] && project="$(lease_get "$f" project)"; }
  mkdir -p "$LEASE_DIR" 2>/dev/null || return 0
  {
    printf 'session=%s\n' "$(session_id)"
    printf 'worktree=%s\n' "$wt"
    printf 'branch=%s\n' "$branch"
    printf 'started=%s\n' "$([ -f "$f" ] && lease_get "$f" started || date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'heartbeat=%s\n' "$(now_epoch)"
    printf 'paths=%s\n' "$paths"
    printf 'project=%s\n' "$project"
  } > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null || true
}

# Walk live leases belonging to OTHER sessions. Callback gets the lease file path.
for_other_live_leases() {
  local cb="$1" f me; me="$(session_id)"
  [ -d "$LEASE_DIR" ] || return 0
  for f in "$LEASE_DIR"/*.lease; do
    [ -f "$f" ] || continue
    [ "$(lease_get "$f" session)" = "$me" ] && continue
    lease_live "$f" || continue
    "$cb" "$f"
  done
}

# Hide the default worktree parent from the main working tree without a committed
# .gitignore change (local-only, per-repo). No-op if the root was relocated elsewhere.
exclude_default_root() {
  [ "$WT_ROOT" = "$WIKI/.worktrees" ] || return 0
  [ -f "$EXCLUDE" ] || return 0
  grep -qxF '/.worktrees/' "$EXCLUDE" 2>/dev/null || printf '/.worktrees/\n' >> "$EXCLUDE"
}

# Is $1 a path inside a worktree of THIS vault's repo (shared .git common dir)?
same_repo_worktree() {
  local top common main_common
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ "$top" != "$WIKI" ] || return 1
  common="$(cd "$top" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" || return 1
  main_common="$(cd "$WIKI" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" || return 1
  [ "$common" = "$main_common" ]
}

# retire_branch <branch> — delete a wt/* branch IF its commits are already contained.
#
# Shared by both callers on purpose. This used to live inline in retire_worktree, which
# meant a branch was only ever evaluated as a side effect of retiring its WORKTREE — so a
# branch whose worktree was already gone was never assessed by anything, and the bare
# sweep (which looks only for stale worktrees) could never reach it. Such a branch was
# unreapable by any invocation, accumulating exactly the way v1.28.2 and v1.38.0 were cut
# to stop. Same fail-safe direction throughout: every uncertain path keeps.
# branch_contained <branch> <target> — does <branch> contribute any CONTENT that <target>
# lacks?  0 = contained (contributes nothing), 1 = holds content target lacks, 2 = unknown.
#
# Extracted from retire_branch so `ensure` can ask the same question before it reattaches
# to an existing branch. Two implementations of "is this branch's work already landed?"
# would drift, and the subtle half — that ancestry is the WRONG test for a squash-merging
# vault, since the work lands as a new commit with a different sha — is exactly the half a
# second implementation gets wrong.
# It also reports HOW it concluded, because the callers' messages differ: BC_REASON is
# `ancestry` (the fast-forward case) or `content` (squash-merged or equivalent), and
# BC_DIFF_FILES counts the files the branch holds that the target lacks.
BC_REASON=""; BC_DIFF_FILES=""
branch_contained() {
  local br="$1" target="$2" mtree res
  BC_REASON=""; BC_DIFF_FILES=""
  if git -C "$WIKI" merge-base --is-ancestor "$br" "$target" 2>/dev/null; then
    BC_REASON="ancestry"; return 0
  fi
  # ANCESTRY IS THE WRONG QUESTION FOR A SQUASH-MERGING VAULT. It is equivalent to
  # containment only when the branch reached the target by a fast-forward. A vault whose
  # house workflow is branch -> PR -> squash-merge lands the work as a NEW commit with a
  # different sha, so the branch tip is not an ancestor and this arm fired on every single
  # session. So ask the question actually meant: does merging this branch into the target
  # CHANGE it? If the merge result tree IS the target's tree, the branch contributes
  # nothing and is contained however it got there.
  #
  # Conservative by construction: only an exact tree match counts as contained. A
  # conflicting merge still writes a tree (with markers), which differs and so reports as
  # holding content — correct, since a branch that conflicts does. An unsupported git
  # (< 2.38) writes no tree at all and reports UNKNOWN, which is a different answer from
  # "holds work" and must stay distinguishable: every uncertain path keeps.
  mtree="$(git -C "$WIKI" rev-parse "$target^{tree}" 2>/dev/null)"
  res="$(git -C "$WIKI" merge-tree --write-tree "$target" "$br" 2>/dev/null | head -1)"
  [ -n "$res" ] && [ "$(git -C "$WIKI" cat-file -t "$res" 2>/dev/null)" = "tree" ] || return 2
  if [ "$res" = "$mtree" ]; then BC_REASON="content"; return 0; fi
  BC_DIFF_FILES="$(git -C "$WIKI" diff --name-only "$mtree" "$res" 2>/dev/null | wc -l | tr -d ' ')"
  return 1
}

# How many commits <target> has that <branch> does not — the distance a reattached
# worktree would be editing behind. Empty if it cannot be computed.
behind_count() { git -C "$WIKI" rev-list --count "$1..$2" 2>/dev/null || true; }

retire_branch() {
  local br="$1"
  case "$br" in wt/*) ;; *) return 0 ;; esac
    # Containment is judged against LOCAL main, not `git branch -d`'s default.
    # `-d` compares to the branch's UPSTREAM (origin/main), so a session branch that
    # `integrate` just fast-forwarded into local main is still reported "not fully
    # merged" whenever main has not been pushed yet — leaving a wt/* branch behind
    # after every single session. `merge-base --is-ancestor` asks the question we
    # actually mean: are these commits already contained in main? Only then -D.
    local mainref rc=0
    mainref="$(git -C "$WIKI" symbolic-ref --short HEAD 2>/dev/null || echo main)"
    branch_contained "$br" "$mainref" || rc=$?
    case "$rc" in
      0)
        if git -C "$WIKI" branch -D "$br" >/dev/null 2>&1; then
          if [ "$BC_REASON" = "ancestry" ]; then
            log "vault-worktree: deleted $br (already contained in $mainref)"
          else
            log "vault-worktree: deleted $br (content already in $mainref — squash-merged or equivalent)"
          fi
        fi ;;
      1)
        # The valuable keep: real content absent from main. Name the files, so the one
        # branch that needs a human is not worded identically to the noise.
        log "vault-worktree: kept $br — UNINTEGRATED CONTENT ($BC_DIFF_FILES file(s) not in $mainref); integrate or delete by hand" ;;
      *)
        # merge-tree unavailable (git < 2.38). The answer is unknown, which is a DIFFERENT
        # report from "has unintegrated work". Every uncertain path keeps, deliberately:
        # deleting an unmerged branch costs work, keeping a merged one costs a stale ref.
        log "vault-worktree: kept $br — could not determine containment (merge-tree unavailable); check by hand" ;;
    esac
}

# Remove ONE clean worktree + its wt/ branch. Refuses if it has uncommitted changes
# (never discard working-tree edits) and deletes the branch only with `-d` (merged-only),
# so committed-but-unintegrated work survives too. Returns 0 iff the worktree was removed.
retire_worktree() {
  local wt="$1" br leftovers
  # Work at risk = tracked modifications, or untracked files that are actually content.
  # `.gitkeep` placeholders are scaffolding adopt.sh drops into empty node folders — they
  # exist in EVERY worktree, so counting them as "uncommitted changes" made retirement
  # impossible for every worktree ever created. That is how orphaned directories piled up
  # and then blocked `ensure`, which silently degraded to the canonical checkout. `-uall`
  # so directories are expanded to files; an empty folder is invisible to git anyway.
  leftovers="$(git -C "$wt" status --porcelain -uall 2>/dev/null | grep -v '/\.gitkeep$' || true)"
  if [ -n "$leftovers" ]; then
    log "vault-worktree: keeping $wt (uncommitted changes)"
    printf '%s\n' "$leftovers" | sed 's/^/    /' >&2
    return 1
  fi
  br="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo)"
  git -C "$WIKI" worktree remove --force "$wt" 2>/dev/null || return 1
  log "vault-worktree: removed $wt"
  case "$br" in
    wt/*) retire_branch "$br" ;;
  esac
  return 0
}

case "$CMD" in
  ensure)
    if [ "${WIKI_WORKTREE:-1}" = "0" ]; then printf '%s\n' "$WIKI"; exit 0; fi
    # Already operating inside a worktree of this vault? Reuse it (idempotent).
    if same_repo_worktree "$PWD"; then git -C "$PWD" rev-parse --show-toplevel; exit 0; fi
    slug="${WIKI_WT_SESSION:-${CLAUDE_CODE_SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$}}"
    slug="$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-')"
    wt="$WT_ROOT/$slug"; branch="wt/$slug"; bc=""; behind=""; why=""
    if git -C "$WIKI" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $wt"; then
      write_lease "$wt" "$branch"      # refresh the heartbeat so peers see us as live
      # Same invariant as the reattach path below, one case earlier: a long session's own
      # worktree drifts behind while peers land work. Reported WITHOUT fetching — this is
      # the hot path, called repeatedly within a session, and a network round trip does not
      # belong on it. So the number can UNDER-report (origin/main as last fetched), never
      # over-report: silence here means "nothing known to be behind", not "current".
      behind="$(behind_count "$branch" origin/main)"
      if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
        log "vault-worktree: reusing $wt — $behind commit(s) behind origin/main as last fetched; rebase before editing appended-to pages"
      fi
      printf '%s\n' "$wt"; exit 0
    fi
    exclude_default_root
    mkdir -p "$WT_ROOT" || { log "vault-worktree: cannot create $WT_ROOT; using $WIKI"; printf '%s\n' "$WIKI"; exit 1; }

    # ORPHANED DIRECTORY RECOVERY. If the path exists but git does not list it as a
    # worktree, a previous removal left the checkout behind while its gitdir went away.
    # `worktree add` then fails on "already exists", and the fallback below hands back the
    # canonical checkout — silently re-enabling the very shared-tree editing this tool
    # exists to prevent. Move it aside rather than delete it: it may hold untracked work,
    # and nothing here is ever worth losing to make a path free.
    if [ -e "$wt" ] && ! git -C "$WIKI" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $wt"; then
      orphan="$wt.orphaned-$(date +%Y%m%d-%H%M%S)"
      if mv "$wt" "$orphan" 2>/dev/null; then
        log "vault-worktree: found an ORPHANED worktree dir at $wt (git no longer tracks it)."
        log "  Moved to $orphan — inspect and delete it yourself; it may hold untracked files."
      else
        log "vault-worktree: $wt exists, git does not track it, and it could not be moved aside."
      fi
    fi
    base="origin/main"
    git -C "$WIKI" fetch -q origin main 2>/dev/null || base="$(git -C "$WIKI" symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
    # With a stable session slug the branch can outlive its worktree (retired but kept
    # because it held unmerged commits). Reattach to the existing branch — never reset it,
    # so those commits survive — otherwise cut a fresh one off base.
    #
    # BUT REATTACHING SILENTLY IS A FAIL-OPEN. `ensure` returns a valid path, exit 0, and a
    # genuinely isolated worktree — only the BASE is wrong, and nothing surfaces that until
    # merge time, when appended-to files (a chronological log, a generated index region)
    # conflict deterministically. The skill text describes `ensure` as putting the session
    # on a branch off origin/main, which is true only on the create path.
    #
    # Worse, this is the NORMAL case for a squash-merging vault: the branch is retained
    # because its work is not an ancestor of main, so it grows staler with every merge in
    # the session — stale precisely BECAUSE its work already landed.
    #
    # So ask the question `gc` already asks, with the same shared test, before reattaching:
    # if the branch contributes no content the base lacks, there is nothing to protect, and
    # cutting a fresh branch off base is strictly better than editing behind it. If it DOES
    # hold work — or the answer is unknown — keep it and reattach, but say how far behind
    # the caller now is instead of reporting plain success.
    if git -C "$WIKI" show-ref --verify --quiet "refs/heads/$branch"; then
      bc=0; branch_contained "$branch" "$base" || bc=$?
      if [ "$bc" = "0" ] && ! git -C "$WIKI" worktree list --porcelain 2>/dev/null | grep -qxF "branch refs/heads/$branch"; then
        if git -C "$WIKI" branch -D "$branch" >/dev/null 2>&1; then
          log "vault-worktree: $branch held nothing $base lacks (already landed) — cutting it fresh off $base rather than reattaching behind it"
        fi
      fi
    fi
    if git -C "$WIKI" show-ref --verify --quiet "refs/heads/$branch"; then
      if git -C "$WIKI" worktree add -q "$wt" "$branch" 2>/dev/null; then
        behind="$(behind_count "$branch" "$base")"
        if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
          if [ "$bc" = "1" ]; then
            why="it holds $BC_DIFF_FILES file(s) $base lacks"
          else
            why="containment could not be determined, so it was kept"
          fi
          log "vault-worktree: reattached $wt to existing $branch — $behind commit(s) BEHIND $base ($why)."
          log "  You are editing on a stale base; appended-to pages will conflict at merge time."
          log "  Rebase before editing:  git -C $wt rebase $base"
        else
          log "vault-worktree: reattached $wt to existing $branch (level with $base)"
        fi
        write_lease "$wt" "$branch"
        printf '%s\n' "$wt"; exit 0
      fi
    elif git -C "$WIKI" worktree add -q "$wt" -b "$branch" "$base" 2>/dev/null; then
      log "vault-worktree: created $wt (branch $branch off $base)"
      write_lease "$wt" "$branch"
      printf '%s\n' "$wt"; exit 0
    fi
    # FALLBACK IS A FAILURE, and says so. It still prints the canonical path so an existing
    # caller degrades rather than breaks, but it exits NON-ZERO: handing back the shared
    # working tree while reporting success is how isolation turns itself off without anyone
    # noticing. A caller that checks (`WORK="$(... ensure)" || abort`) can now refuse to
    # write; one that does not is no worse off than before, and the `guard` still blocks the
    # commit. The commit gate is the backstop — it is not a substitute, because the
    # filesystem race happens while editing, long before anything is committed.
    log "vault-worktree: FAILED to create a worktree — falling back to the canonical checkout."
    log "  Writes here are NOT isolated: a concurrent session shares this tree, and edits to"
    log "  one file are last-writer-wins on disk. Resolve before doing vault work, or accept"
    log "  the risk deliberately with WIKI_WORKTREE=0."
    printf '%s\n' "$WIKI"; exit 1
    ;;

  guard)
    # Refuse a commit made in the CANONICAL checkout. This is the layer that turns
    # isolation from "available" into "taken": today's clobber happened because a
    # session did ad-hoc work straight in $WIKI_PATH and ran `git add -A`, sweeping a
    # peer's finished-but-uncommitted work into its own commit.
    #
    # Canonical vs worktree is decided by git itself: in the main checkout --git-dir and
    # --git-common-dir resolve to the same directory; in a linked worktree they differ.
    # No path guessing, no name matching.
    [ "${WIKI_WORKTREE:-1}" = "0" ] && exit 0      # deliberate single-session machine
    [ "${VAULT_INTEGRATE:-0}" = "1" ] && exit 0    # `integrate` merging, below
    gd="$(git -C "$PWD" rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
    gcd="$(cd "$(git -C "$PWD" rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" || exit 0
    if [ "$gd" != "$gcd" ]; then exit 0; fi        # in a linked worktree — fine
    log "vault-worktree: refusing a commit in the CANONICAL checkout ($WIKI)."
    log "  Another session may be editing here, and staging in a shared tree sweeps up"
    log "  its work. Take an isolated worktree first:"
    log "      WORK=\"\$($WIKI/engine/bin/vault-worktree.sh ensure)\"   # then edit + commit in \$WORK"
    log "  Integrate when done:  vault-worktree.sh integrate"
    log "  Override for a single-session machine:  WIKI_WORKTREE=0"
    exit 1
    ;;

  lease)
    shift
    # Record THIS SESSION's worktree, preferring the one `ensure` keyed to it over the
    # CWD's toplevel. CWD was the only source before, which recorded whatever repo the
    # shell happened to sit in — an unrelated one if `lease` is called from elsewhere.
    # That field is now load-bearing: lease_finished() reads it to decide a session has
    # provably ended, so a wrong path there means a ghost that never reaps, or worse, a
    # live session judged finished because some other repo's directory is missing.
    if [ -d "$WT_ROOT/$(session_id)" ]; then
      wt="$WT_ROOT/$(session_id)"
    else
      wt="$(cd "$PWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$WIKI")"
    fi
    branch="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
    write_lease "$wt" "$branch" "$@"
    # Advisory overlap warning. Compares declared path PREFIXES — deliberately coarse,
    # because the point is "you two are heading for the same area", not adjudicating
    # which file wins. Git decides that later, correctly, at merge time.
    mine="$*"
    if [ -n "$mine" ]; then
      warn_overlap() {
        local f="$1" theirs p q
        theirs="$(lease_get "$f" paths)"; [ -n "$theirs" ] || return 0
        for p in $mine; do
          for q in $theirs; do
            case "$p" in "$q"*) ;; *) case "$q" in "$p"*) ;; *) continue;; esac;; esac
            log "vault-worktree: NOTE — session $(lease_get "$f" session) also declared '$q' (yours: '$p')"
            log "  Not blocked: overlap is often harmless and git resolves the real thing at merge."
            log "  Worth a look now if you both intend to rewrite the same page."
            return 0
          done
        done
      }
      for_other_live_leases warn_overlap
    fi
    printf 'lease: %s -> %s [%s]\n' "$(session_id)" "${mine:-<paths unchanged>}" "$branch"
    ;;

  claim)
    # PROJECT PRESENCE — advisory, and deliberately NOT a lock.
    #
    # Two collision classes are already covered: vault-content edits collide as merge
    # conflicts (fail-closed, nothing lost), and working-tree collisions are covered by the
    # per-session worktree. The uncovered class is work a session performs OUTSIDE version
    # control — investigation, and state-changing commands issued against external systems.
    # That work has no coordination surface at all, so two sessions can converge on one
    # project, duplicate the investigation and contend over the side effects, with neither
    # able to see the other.
    #
    # This makes the overlap VISIBLE, which is the layer the concurrency model calls
    # visibility, and it stops there on purpose. It is not a mutual-exclusion lock: a lock
    # is advisory against an agent whose instruction to check it can be compacted out of
    # context, sessions end by interrupt rather than clean release so stale locks are the
    # normal outcome, and a gate that blocks at the wrong moments trains its user to force
    # past it — which removes the gate entirely.
    #
    # It rides the LEASE record rather than a store of its own: liveness, staleness and the
    # "provably finished" evidence are already decided there, in one place, and a second
    # presence mechanism would give a second answer to the same question.
    shift
    slug="${1:-}"
    if [ -d "$WT_ROOT/$(session_id)" ]; then wt="$WT_ROOT/$(session_id)"
    else wt="$(cd "$PWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$WIKI")"; fi
    branch="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo '?')"
    if [ -n "$slug" ]; then
      CLAIM_PROJECT="$slug" write_lease "$wt" "$branch"
      report_claim() {
        local f="$1" theirs age
        theirs="$(lease_get "$f" project)"; [ "$theirs" = "$slug" ] || return 0
        age=$(( ( $(now_epoch) - $(lease_get "$f" heartbeat) ) / 60 ))
        log "vault-worktree: NOTE — session $(lease_get "$f" session) is also on project '$slug' (active ${age}m ago)."
        log "  Not blocked. Vault edits still collide as merge conflicts; what this warns about is"
        log "  the work with NO other surface — investigation you would both repeat, and commands"
        log "  issued against systems outside version control, where you would contend silently."
      }
      for_other_live_leases report_claim
      printf 'claim: %s -> project %s [%s]\n' "$(session_id)" "$slug" "$branch"
    else
      # No slug: report, do not modify. A claim whose session is not live is shown as STALE
      # rather than deleted — a session that died mid-work is exactly the thing a human
      # should be able to see, and silently reaping it hides it.
      [ -d "$LEASE_DIR" ] || { echo "no claims recorded"; exit 0; }
      me="$(session_id)"; n=0
      for f in "$LEASE_DIR"/*.lease; do
        [ -f "$f" ] || continue
        p="$(lease_get "$f" project)"; [ -n "$p" ] || continue
        age=$(( ( $(now_epoch) - $(lease_get "$f" heartbeat) ) / 60 ))
        s="$(lease_get "$f" session)"; mark=""; [ "$s" = "$me" ] && mark=" (you)"
        state="live"; lease_live "$f" || state="STALE"
        printf '%-28s %-24s %-8s %s\n' "$s$mark" "$p" "${age}m" "$state"
        n=$((n+1))
      done
      if [ "$n" -eq 0 ]; then echo "(no project claims)"; fi
    fi
    ;;

  peers)
    [ -d "$LEASE_DIR" ] || { echo "no leases recorded"; exit 0; }
    me="$(session_id)"; n=0
    printf '%-28s %-22s %-8s %-20s %s\n' SESSION BRANCH AGE PROJECT PATHS
    for f in "$LEASE_DIR"/*.lease; do
      [ -f "$f" ] || continue
      lease_live "$f" || continue
      s="$(lease_get "$f" session)"; b="$(lease_get "$f" branch)"
      age=$(( ( $(now_epoch) - $(lease_get "$f" heartbeat) ) / 60 ))
      mark=""; [ "$s" = "$me" ] && mark=" (you)"
      printf '%-28s %-22s %-8s %-20s %s\n' "$s$mark" "$b" "${age}m" "$(lease_get "$f" project)" "$(lease_get "$f" paths)"
      n=$((n+1))
    done
    # if/then, not `[ ] &&` — a trailing false test would become this branch's exit
    # status and make a successful `peers` look like a failure to any caller.
    if [ "$n" -eq 0 ]; then echo "(no live sessions)"; fi
    ;;

  integrate)
    # Serialize the one genuinely shared step. Everything else is isolated per worktree;
    # merging to main is where N sessions actually contend, so it happens one at a time.
    wt="$(cd "$PWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$WIKI")"
    if ! same_repo_worktree "$wt"; then
      log "vault-worktree: integrate must run from inside a session worktree (got $wt)"; exit 2
    fi
    branch="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null)" || { log "vault-worktree: detached HEAD"; exit 2; }
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
      log "vault-worktree: $wt has uncommitted changes — commit them before integrating"; exit 1
    fi
    # The canonical dirty-check is PATH-PRECISE and lives further down, immediately
    # before the fast-forward — the only point where the set of paths the ff will touch
    # is known exactly (it is decided by the REBASED branch, which does not exist yet).
    #
    # It used to be here, and categorical: any tracked modification anywhere in canonical
    # refused the integrate. That is strictly broader than the danger, because a
    # fast-forward can only clobber an uncommitted edit to a path it actually changes.
    # And the engine itself guaranteed the check would be red: rag-capture.sh appends to
    # raw/sessions/ in the CANONICAL checkout at SessionEnd (by then the session's
    # worktree is gc'd, so there is nowhere else to write), so every session left dirt
    # behind and the next session's integrate refused — while `guard` refused the commit
    # that would clear it. Two correct guards, jointly a deadlock.
    #
    # Same failure the -uno flag was added to fix for UNTRACKED files, one notch deeper:
    # a check that is always red is a check that gets bypassed. The buffer is now
    # gitignored (cause), and this check is precise (over-breadth).
    mkdir -p "$WT_ROOT" 2>/dev/null || true
    waited=0; wait_max="${WIKI_LOCK_WAIT_SEC:-120}"
    until mkdir "$LOCK" 2>/dev/null; do
      # Break a lock whose owner is gone, so one crashed session can't wedge everyone.
      if [ -f "$LOCK/owner" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
        log "vault-worktree: breaking a stale integrate lock (owner $(cat "$LOCK/owner" 2>/dev/null), >30m old)"
        rm -rf "$LOCK" 2>/dev/null || true; continue
      fi
      [ "$waited" -ge "$wait_max" ] && { log "vault-worktree: integrate lock held by $(cat "$LOCK/owner" 2>/dev/null) — timed out after ${wait_max}s"; exit 4; }
      [ "$waited" -eq 0 ] && log "vault-worktree: waiting for the integrate lock (held by $(cat "$LOCK/owner" 2>/dev/null))..."
      sleep 3; waited=$((waited+3))
    done
    session_id > "$LOCK/owner" 2>/dev/null || printf '%s\n' "$(session_id)" > "$LOCK/owner"
    trap 'rm -rf "$LOCK" 2>/dev/null || true' EXIT

    main="$(git -C "$WIKI" symbolic-ref --short HEAD 2>/dev/null || echo main)"
    git -C "$WIKI" fetch -q origin "$main" 2>/dev/null || true

    # Reconcile canonical <main> with what we just fetched, BEFORE choosing a rebase base.
    # Without this the fetch above is never consulted: the rebase below uses the LOCAL ref,
    # so a vault publishing by branch -> pull request -> squash-merge (where the squash is a
    # new object its local <main> is not an ancestor of) based every integrate on a
    # superseded history and printed success — leaving canonical divergent and the NEXT
    # publication unmergeable, far from the tool that caused it.
    #
    # Rebasing onto origin/<main> instead is NOT the fix, though it looks like the obvious
    # one-word change: the fast-forward below then refuses, because local <main> is no
    # longer an ancestor of the rebased branch. The local ref has to actually move.
    if git -C "$WIKI" rev-parse -q --verify "origin/$main" >/dev/null 2>&1; then
      if git -C "$WIKI" merge-base --is-ancestor "$main" "origin/$main" 2>/dev/null; then
        # Behind (or equal) — advance it so the rebase base is what origin actually has.
        # --ff-only is the backstop: git refuses rather than clobber an uncommitted edit.
        if ! VAULT_INTEGRATE=1 git -C "$WIKI" merge --ff-only -q "origin/$main" 2>/dev/null; then
          log "vault-worktree: $main is behind origin/$main but will not fast-forward — resolve in $WIKI, then re-run integrate"
          exit 3
        fi
      elif ! git -C "$WIKI" merge-base --is-ancestor "origin/$main" "$main" 2>/dev/null; then
        # Neither ref contains the other. Before refusing, check for the ONE divergence that
        # is provably safe to resolve: identical CONTENT, different history. That is the
        # signature of a squash-merge — local <main>'s commits were published as a single
        # new object — and it is the normal steady state of any vault whose convention is
        # branch -> pull request -> squash-merge, so refusing there would refuse forever.
        # -uno: `reset --hard` does not touch UNTRACKED files, so they are not at risk and
        # must not block. Counting them would make this check permanently red in any vault
        # that leaves a stray file in canonical — the always-red-check-gets-bypassed failure
        # this repo has already fixed twice, most recently for the canonical dirty-check
        # below.
        if [ -z "$(git -C "$WIKI" diff --name-only "origin/$main" "$main" 2>/dev/null)" ] \
           && [ -z "$(git -C "$WIKI" status --porcelain -uno 2>/dev/null)" ]; then
          # Content-equal and canonical is clean: nothing to lose by adopting origin's
          # history. Both conditions are required — the diff proves no committed work is
          # dropped, the status check proves no uncommitted TRACKED work is, and `reset --hard`
          # would destroy the latter without complaint.
          git -C "$WIKI" reset --hard -q "origin/$main" 2>/dev/null || {
            log "vault-worktree: could not adopt origin/$main — resolve in $WIKI, then re-run integrate"; exit 3; }
          log "vault-worktree: adopted origin/$main (same content, republished history — squash-merge)"
        else
          # Real divergence: histories AND content differ, or canonical has uncommitted
          # work. Picking a side silently drops one of them, and this is precisely the
          # state the old behaviour created, so it has to be said out loud.
          log "vault-worktree: $main has DIVERGED from origin/$main — nothing was integrated"
          log "vault-worktree: reconcile canonical first (e.g. rebase $main onto origin/$main), then re-run integrate"
          exit 3
        fi
      fi
      # else: local is AHEAD of origin (unpushed work, e.g. a push-to-main vault). It
      # already contains origin/<main>, so the local ref is the correct base — proceed.
    fi
    # Rebase INSIDE the worktree: a conflict then surfaces in the session's own tree,
    # where it can be resolved, instead of leaving canonical mid-merge for everyone.
    if ! git -C "$wt" rebase -q "$main" 2>/dev/null; then
      git -C "$wt" rebase --abort 2>/dev/null || true
      log "vault-worktree: $branch does not rebase cleanly onto $main — resolve in $wt, then re-run integrate"
      exit 3
    fi
    # PATH-PRECISE canonical dirty-check. Now that the rebase has run, the paths the
    # fast-forward will change are known exactly: main..branch. Refuse only if one of
    # them is also modified in canonical — that is the whole of what a ff can clobber.
    #
    # `merge --ff-only` below is the real backstop; git refuses to overwrite a locally
    # modified file on its own. This check exists to fail with an ACTIONABLE message
    # naming the files, rather than git's generic one, and to fail before HEAD moves.
    # Being narrower than git is therefore not a safety loss — git still has the veto.
    dirty="$(git -C "$WIKI" diff --name-only HEAD 2>/dev/null)"
    if [ -n "$dirty" ]; then
      changed="$(git -C "$WIKI" diff --name-only "$main..$branch" 2>/dev/null)"
      # intersection, exact whole-line matches only
      overlap="$(printf '%s\n' "$dirty" | grep -Fxf <(printf '%s\n' "$changed") 2>/dev/null)"
      if [ -n "$overlap" ]; then
        log "vault-worktree: canonical $WIKI has uncommitted edits to path(s) this integrate would change:"
        printf '%s\n' "$overlap" | sed 's/^/    /' >&2
        log "  refusing to move its HEAD under whoever owns those edits."
        log "  Commit them from a worktree, or 'git -C $WIKI stash' them, then re-run integrate."
        exit 1
      fi
    fi
    # Fast-forward only: after the rebase this always applies, and it guarantees we never
    # author a merge commit in a tree someone else may be sitting in.
    if VAULT_INTEGRATE=1 git -C "$WIKI" merge --ff-only -q "$branch" 2>/dev/null; then
      log "vault-worktree: integrated $branch -> $main"
      printf 'integrated %s -> %s\n' "$branch" "$main"
    else
      log "vault-worktree: fast-forward of $main to $branch failed (did $main move mid-integrate?)"; exit 3
    fi
    ;;
  gc)
    shift  # drop "gc"; remaining args are explicit worktree paths to retire NOW
    removed=0
    if [ "$#" -gt 0 ]; then
      # Explicit targets: retire exactly these, regardless of age — this is how a skill
      # retires the worktree it just finished with (checkpoint §0), which the age-gated
      # sweep below can never do (a just-created worktree is always < stale threshold).
      for target in "$@"; do
        wt="$(cd "$target" 2>/dev/null && pwd)" || { log "vault-worktree: gc target not found: $target"; continue; }
        case "$wt" in
          "$WT_ROOT"/*) ;;
          *) log "vault-worktree: refusing to gc $wt (not under $WT_ROOT)"; continue;;
        esac
        retire_worktree "$wt" && removed=$((removed+1))
      done
    else
      # Bare gc: sweep CLEAN orphans whose dir hasn't changed in WIKI_WT_STALE_HOURS —
      # worktrees a crashed/abandoned session left behind, not one a live session owns.
      stale_min=$(( ${WIKI_WT_STALE_HOURS:-48} * 60 ))
      while IFS= read -r line; do
        case "$line" in worktree\ *) wt="${line#worktree }";; *) continue;; esac
        case "$wt" in "$WT_ROOT"/*) ;; *) continue;; esac
        if ! find "$wt" -maxdepth 0 -mmin +"$stale_min" 2>/dev/null | grep -q .; then
          continue  # still fresh; a live session likely owns it
        fi
        retire_worktree "$wt" && removed=$((removed+1))
      done < <(git -C "$WIKI" worktree list --porcelain 2>/dev/null)
    fi
    git -C "$WIKI" worktree prune 2>/dev/null || true
    # Reap leases for sessions that provably finished (worktree and branch both gone) or
    # stopped refreshing, so `peers` shows live sessions only — a registry that accumulates
    # ghosts stops being read. Runs AFTER the worktree sweep above on purpose: retiring a
    # worktree is exactly what makes its lease provably dead, so the same gc that removes
    # the directory also clears the entry, instead of leaving a ghost until the clock.
    reaped=0
    if [ -d "$LEASE_DIR" ]; then
      for lf in "$LEASE_DIR"/*.lease; do
        [ -f "$lf" ] || continue
        lease_live "$lf" || { rm -f "$lf" 2>/dev/null && reaped=$((reaped+1)); }
      done
    fi
    # ORPHAN BRANCHES — a wt/* branch whose worktree is already gone. Nothing else ever
    # looks at these: a branch is otherwise evaluated only as a side effect of retiring
    # its worktree, and the sweep above only finds stale WORKTREES. So a branch left
    # behind by a crashed session, or by a worktree removed some other way, was
    # unreapable by any invocation of this tool and simply accumulated — the same
    # unbounded growth v1.28.2 and v1.38.0 were each cut to stop, arrived at by a third
    # route. Found in the wild on a vault whose orphan was provably contained by BOTH
    # the ancestry and the content test, and still needed deleting by hand.
    #
    # A branch that is checked out ANYWHERE is skipped: it belongs to a live session
    # (or to canonical), and this sweep must never touch a tree someone is working in.
    # `branch -D` would refuse anyway, but relying on that would make the skip an
    # accident rather than a decision.
    attached="$(git -C "$WIKI" worktree list --porcelain 2>/dev/null \
                | awk '/^branch /{sub(/^branch refs\/heads\//,""); print}')"
    orphans=0
    while IFS= read -r ob; do
      [ -n "$ob" ] || continue
      printf '%s\n' "$attached" | grep -qxF "$ob" && continue
      orphans=$((orphans+1))
      retire_branch "$ob"
    done <<EOF
$(git -C "$WIKI" for-each-ref --format='%(refname:short)' 'refs/heads/wt/*' 2>/dev/null)
EOF
    log "vault-worktree: gc removed $removed worktree(s), reaped $reaped dead lease(s), assessed $orphans orphan branch(es)"
    ;;
  list)
    git -C "$WIKI" worktree list
    ;;
  -h|--help)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    log "usage: vault-worktree.sh [ensure|guard|lease|claim|peers|integrate|gc|list]"; exit 1
    ;;
esac
