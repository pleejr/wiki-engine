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
# Usage:
#   vault-worktree.sh ensure    # idempotent; print the worktree path to write in
#   vault-worktree.sh gc        # remove stale/orphaned session worktrees (clean ones only)
#   vault-worktree.sh list      # list the vault's worktrees
#
# Env:
#   WIKI_PATH             the vault root (required)
#   WIKI_WORKTREE=0       opt out — `ensure` prints $WIKI_PATH (legacy direct-to-main)
#   WIKI_WT_SESSION       stable session id so repeat `ensure` calls reuse one worktree
#   WIKI_WORKTREE_ROOT    parent dir for worktrees (default $WIKI_PATH/.worktrees, git-excluded)
#   WIKI_WT_STALE_HOURS   `gc` age threshold for a clean orphan (default 48)
set -uo pipefail

log() { printf '%s\n' "$*" >&2; }

WIKI="${WIKI_PATH:-}"
[ -n "$WIKI" ] || { log "vault-worktree: WIKI_PATH not set"; exit 2; }
WIKI="$(cd "$WIKI" 2>/dev/null && pwd)" || { log "vault-worktree: cannot cd to WIKI_PATH ($WIKI_PATH)"; exit 2; }
git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || { log "vault-worktree: $WIKI is not a git repo"; exit 2; }

CMD="${1:-ensure}"
WT_ROOT="${WIKI_WORKTREE_ROOT:-$WIKI/.worktrees}"
EXCLUDE="$WIKI/.git/info/exclude"

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

case "$CMD" in
  ensure)
    if [ "${WIKI_WORKTREE:-1}" = "0" ]; then printf '%s\n' "$WIKI"; exit 0; fi
    # Already operating inside a worktree of this vault? Reuse it (idempotent).
    if same_repo_worktree "$PWD"; then git -C "$PWD" rev-parse --show-toplevel; exit 0; fi
    slug="${WIKI_WT_SESSION:-$(date +%Y%m%d-%H%M%S)-$$}"
    slug="$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-')"
    wt="$WT_ROOT/$slug"; branch="wt/$slug"
    if git -C "$WIKI" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $wt"; then
      printf '%s\n' "$wt"; exit 0
    fi
    exclude_default_root
    mkdir -p "$WT_ROOT" || { log "vault-worktree: cannot create $WT_ROOT; using $WIKI"; printf '%s\n' "$WIKI"; exit 0; }
    base="origin/main"
    git -C "$WIKI" fetch -q origin main 2>/dev/null || base="$(git -C "$WIKI" symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
    if git -C "$WIKI" worktree add -q "$wt" -b "$branch" "$base" 2>/dev/null; then
      log "vault-worktree: created $wt (branch $branch off $base)"
      printf '%s\n' "$wt"; exit 0
    fi
    log "vault-worktree: worktree add failed; falling back to canonical $WIKI"
    printf '%s\n' "$WIKI"; exit 0
    ;;
  gc)
    stale_min=$(( ${WIKI_WT_STALE_HOURS:-48} * 60 ))
    removed=0
    while IFS= read -r line; do
      case "$line" in worktree\ *) wt="${line#worktree }";; *) continue;; esac
      case "$wt" in "$WT_ROOT"/*) ;; *) continue;; esac
      # Only reap CLEAN worktrees — never discard uncommitted work.
      if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
        log "vault-worktree: keeping $wt (uncommitted changes)"; continue
      fi
      if ! find "$wt" -maxdepth 0 -mmin +"$stale_min" 2>/dev/null | grep -q .; then
        continue  # still fresh; a live session likely owns it
      fi
      br="$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo)"
      if git -C "$WIKI" worktree remove --force "$wt" 2>/dev/null; then
        removed=$((removed+1)); log "vault-worktree: removed stale $wt"
        [ -n "$br" ] && git -C "$WIKI" branch -D "$br" >/dev/null 2>&1 || true
      fi
    done < <(git -C "$WIKI" worktree list --porcelain 2>/dev/null)
    git -C "$WIKI" worktree prune 2>/dev/null || true
    log "vault-worktree: gc removed $removed worktree(s)"
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
