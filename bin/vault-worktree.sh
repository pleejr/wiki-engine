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
#   WIKI_LEASE_STALE_MIN  a lease unrefreshed this long counts as dead (default 120)
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

# A lease is LIVE if refreshed within LEASE_STALE_MIN. Time-based rather than pid-based:
# the pid recorded here is the helper script's, not the agent's, and dies immediately —
# so liveness has to come from the session continuing to touch its lease.
lease_live() {
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
  mkdir -p "$LEASE_DIR" 2>/dev/null || return 0
  {
    printf 'session=%s\n' "$(session_id)"
    printf 'worktree=%s\n' "$wt"
    printf 'branch=%s\n' "$branch"
    printf 'started=%s\n' "$([ -f "$f" ] && lease_get "$f" started || date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'heartbeat=%s\n' "$(now_epoch)"
    printf 'paths=%s\n' "$paths"
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

# Remove ONE clean worktree + its wt/ branch. Refuses if it has uncommitted changes
# (never discard working-tree edits) and deletes the branch only with `-d` (merged-only),
# so committed-but-unintegrated work survives too. Returns 0 iff the worktree was removed.
retire_worktree() {
  local wt="$1" br
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    log "vault-worktree: keeping $wt (uncommitted changes)"; return 1
  fi
  br="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo)"
  git -C "$WIKI" worktree remove --force "$wt" 2>/dev/null || return 1
  log "vault-worktree: removed $wt"
  case "$br" in
    wt/*)
      if git -C "$WIKI" branch -d "$br" >/dev/null 2>&1; then
        log "vault-worktree: deleted merged branch $br"
      else
        log "vault-worktree: kept branch $br (unmerged commits — integrate or delete by hand)"
      fi ;;
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
    wt="$WT_ROOT/$slug"; branch="wt/$slug"
    if git -C "$WIKI" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $wt"; then
      write_lease "$wt" "$branch"      # refresh the heartbeat so peers see us as live
      printf '%s\n' "$wt"; exit 0
    fi
    exclude_default_root
    mkdir -p "$WT_ROOT" || { log "vault-worktree: cannot create $WT_ROOT; using $WIKI"; printf '%s\n' "$WIKI"; exit 0; }
    base="origin/main"
    git -C "$WIKI" fetch -q origin main 2>/dev/null || base="$(git -C "$WIKI" symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
    # With a stable session slug the branch can outlive its worktree (retired but kept
    # because it held unmerged commits). Reattach to the existing branch — never reset it,
    # so those commits survive — otherwise cut a fresh one off base.
    if git -C "$WIKI" show-ref --verify --quiet "refs/heads/$branch"; then
      if git -C "$WIKI" worktree add -q "$wt" "$branch" 2>/dev/null; then
        log "vault-worktree: reattached $wt to existing $branch"
        write_lease "$wt" "$branch"
        printf '%s\n' "$wt"; exit 0
      fi
    elif git -C "$WIKI" worktree add -q "$wt" -b "$branch" "$base" 2>/dev/null; then
      log "vault-worktree: created $wt (branch $branch off $base)"
      write_lease "$wt" "$branch"
      printf '%s\n' "$wt"; exit 0
    fi
    log "vault-worktree: worktree add failed; falling back to canonical $WIKI"
    printf '%s\n' "$WIKI"; exit 0
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
    wt="$(cd "$PWD" && git rev-parse --show-toplevel 2>/dev/null || echo "$WIKI")"
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

  peers)
    [ -d "$LEASE_DIR" ] || { echo "no leases recorded"; exit 0; }
    me="$(session_id)"; n=0
    printf '%-28s %-22s %-8s %s\n' SESSION BRANCH AGE PATHS
    for f in "$LEASE_DIR"/*.lease; do
      [ -f "$f" ] || continue
      lease_live "$f" || continue
      s="$(lease_get "$f" session)"; b="$(lease_get "$f" branch)"
      age=$(( ( $(now_epoch) - $(lease_get "$f" heartbeat) ) / 60 ))
      mark=""; [ "$s" = "$me" ] && mark=" (you)"
      printf '%-28s %-22s %-8s %s\n' "$s$mark" "$b" "${age}m" "$(lease_get "$f" paths)"
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
    if [ -n "$(git -C "$WIKI" status --porcelain 2>/dev/null)" ]; then
      log "vault-worktree: canonical $WIKI is dirty — refusing to move its HEAD under whoever owns those edits"
      exit 1
    fi
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
    # Rebase INSIDE the worktree: a conflict then surfaces in the session's own tree,
    # where it can be resolved, instead of leaving canonical mid-merge for everyone.
    if ! git -C "$wt" rebase -q "$main" 2>/dev/null; then
      git -C "$wt" rebase --abort 2>/dev/null || true
      log "vault-worktree: $branch does not rebase cleanly onto $main — resolve in $wt, then re-run integrate"
      exit 3
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
    # Reap leases whose session stopped refreshing, so `peers` shows live sessions only —
    # a registry that accumulates ghosts stops being read.
    reaped=0
    if [ -d "$LEASE_DIR" ]; then
      for lf in "$LEASE_DIR"/*.lease; do
        [ -f "$lf" ] || continue
        lease_live "$lf" || { rm -f "$lf" 2>/dev/null && reaped=$((reaped+1)); }
      done
    fi
    log "vault-worktree: gc removed $removed worktree(s), reaped $reaped dead lease(s)"
    ;;
  list)
    git -C "$WIKI" worktree list
    ;;
  -h|--help)
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    log "usage: vault-worktree.sh [ensure|gc|list]"; exit 1
    ;;
esac
