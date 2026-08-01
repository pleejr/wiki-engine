#!/usr/bin/env bash
# wiki-root-lib.sh — resolve WHICH working tree a vault-content tool should write.
#
# SOURCED, never run. Picked up by a tool as:
#
#     . "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
#     WIKI="$(resolve_wiki_root "$EXPLICIT_WIKI")" || exit 1
#
# ---------------------------------------------------------------------------------
# THE PROBLEM. $WIKI_PATH is a machine-global constant naming the CANONICAL vault
# checkout, set once at session boot. vault-worktree.sh exists so that a writing
# session never touches that shared tree — it works in $WIKI_PATH/.worktrees/<id>/
# and commits from there. A tool that resolves `WIKI="${WIKI_PATH:-}"` and never
# consults cwd therefore does the exact thing the worktree feature forbids: invoked
# from inside a session worktree, it regenerates the CANONICAL index.md.
#
# That is fail-open, not fail-closed — exit 0, a success line, and two consequences:
#
#   1. the regenerated file lands OUTSIDE the branch whose edit caused the
#      regeneration, so the PR carrying a page change can omit the index update
#      that change requires;
#   2. the shared canonical tree acquires an uncommitted modification nothing asked
#      for, and a concurrent session's `git add -A` sweeps it into a foreign commit
#      — the precise clobber worktrees were introduced to prevent.
#
# ---------------------------------------------------------------------------------
# RESOLUTION ORDER (first match wins):
#
#   1. an explicit --wiki DIR         — the caller has stated the target; never
#                                       second-guessed. This is also the escape
#                                       hatch: --wiki "$WIKI_PATH" restores the old
#                                       behaviour from anywhere.
#   2. cwd's working tree, when it is a DIFFERENT working tree of the SAME
#      repository as $WIKI_PATH       — i.e. the session worktree you are standing
#                                       in and will commit from.
#   3. $WIKI_PATH                     — unchanged for every other caller.
#
# The same-repository test is the load-bearing half, and it is why this compares
# git-common-dir rather than trusting `--show-toplevel` alone. Engine development
# happens inside OTHER git repositories with $WIKI_PATH still exported; retargeting
# on cwd alone would make `gen-projects-index.sh` try to generate an index into
# whatever repo the developer happened to be sitting in. Unrelated repo, cwd outside
# any repo, cwd in the canonical checkout itself, $WIKI_PATH not a repo, git absent
# — all fall through to $WIKI_PATH, so no existing caller changes behaviour.
#
# WHAT DELIBERATELY DOES NOT USE THIS. Only tools whose target is TRACKED VAULT
# CONTENT should resolve this way. Two families must keep resolving $WIKI_PATH:
#
#   - the RAG family (rag-setup/rag-build/rag-capture/recall) — .rag/ is untracked
#     and exists only in the canonical checkout by design; a linked worktree has no
#     venv, no index, no config.json.
#   - the machine/engine-wiring family (doctor, update, adopt, apply-adopt, upkeep,
#     session-*, wire-machine) — engine/ is a SUBMODULE, and `git worktree add`
#     never populates one. Inside a worktree, engine/ is an empty directory.
#
# Retargeting either family would not fix a bug; it would invent one.
#
# This file sets no shell options. Its callers run under `set -euo pipefail`, and a
# sourced file that re-`set`s inherits the right to silently relax them. For the same
# reason every helper here RETURNS 0 on every path: under `set -e`, `x="$(helper)"`
# aborts the calling script when the helper exits non-zero, so "no answer" must be an
# empty string, never a failing status.

# _abs_common_dir [DIR] — absolute path of the shared .git dir for the repo
# containing DIR (default: cwd); empty when there is none. --git-common-dir is the
# right question, not --git-dir: for a linked worktree the latter names the
# per-worktree stub, which differs between two worktrees of one repository, while
# the former is identical across all of them. That identity IS the "same repository"
# test. It can answer relatively (plain ".git" from a toplevel), so resolve it.
_abs_common_dir() {
  local dir="${1:-.}" out
  out="$(cd "$dir" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0
  case "$out" in
    /*) ;;
    *) out="$(cd "$dir" 2>/dev/null && cd "$out" 2>/dev/null && pwd)" || return 0;;
  esac
  [ -d "$out" ] && printf '%s\n' "$out"
  return 0
}

# resolve_wiki_root [EXPLICIT_WIKI] — echo the working tree to operate on.
# Exits non-zero (with the historical message) when there is nothing to resolve, so
# a caller that could previously rely on `[ -n "$WIKI" ] || error` keeps that gate.
resolve_wiki_root() {
  local explicit="${1:-}" me="${0##*/}"

  if [ -n "$explicit" ]; then printf '%s\n' "$explicit"; return 0; fi

  local canon="${WIKI_PATH:-}"
  if [ -z "$canon" ]; then
    echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2
    return 1
  fi
  # Normalize before comparing: $WIKI_PATH may carry a trailing slash or a symlinked
  # prefix, and `--show-toplevel` never does. An unnormalized compare reports every
  # canonical invocation as a worktree one.
  local canon_abs; canon_abs="$(cd "$canon" 2>/dev/null && pwd)" || { printf '%s\n' "$canon"; return 0; }

  local canon_common cwd_common
  canon_common="$(_abs_common_dir "$canon_abs")" || canon_common=""
  cwd_common="$(_abs_common_dir .)" || cwd_common=""
  # Not both in a repo, or not the SAME repo -> the old default, unchanged.
  [ -n "$canon_common" ] && [ -n "$cwd_common" ] && [ "$canon_common" = "$cwd_common" ] || {
    printf '%s\n' "$canon_abs"; return 0
  }

  local top; top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf '%s\n' "$canon_abs"; return 0; }
  top="$(cd "$top" 2>/dev/null && pwd)" || { printf '%s\n' "$canon_abs"; return 0; }
  [ "$top" != "$canon_abs" ] || { printf '%s\n' "$canon_abs"; return 0; }

  # Say so. Silence is what made the original bug fail open: the tool reported
  # success naming a path the caller was not committing from, and it read as
  # ordinary success. One line on stderr makes the retarget observable without
  # touching --stdout's contract. The wording names the WORKING TREE rather than
  # "the session worktree" on purpose — the usual case is a session worktree, but a
  # vault whose $WIKI_PATH itself points at a linked worktree would make that claim
  # false, and a message that is confidently wrong is worse than a plain one.
  echo "$me: targeting $top — the working tree cwd is in, not \$WIKI_PATH. Pass --wiki to override." >&2
  printf '%s\n' "$top"
}
