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
# WHO USES THIS. Every tool whose target is tracked vault content: the two index
# generators, and (v1.66.0) the tools that issue a VERDICT about that content —
# lint.sh, lint-links.sh, lint-memory.sh, verify-status.sh, lint-summary-volatility.sh.
# The verdict tools were the original omission: they bound $WIKI_PATH directly, so a bare
# run from a session worktree reported on canonical and said nothing about the choice.
# lint-summary-volatility.sh was the worst of them — `--seed-baseline` WRITES, and the
# comment beside that write already cited this function as its protection while never
# calling it.
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

# _canonical_root DIR — the CANONICAL working tree of DIR's repository (DIR itself
# when DIR is canonical); empty when DIR is not in a repository, or when the derived
# root is not a working tree root after all (a `.git` FILE, as a submodule has,
# resolves its common dir into the superproject's .git/modules/... where `..` names
# no worktree). Same derivation scaffold/pre-commit already uses.
_canonical_root() {
  local dir="$1" common top
  common="$(_abs_common_dir "$dir")" || return 0
  [ -n "$common" ] || return 0
  top="$(cd "$common/.." 2>/dev/null && pwd)" || return 0
  local check; check="$(cd "$top" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ "$check" = "$top" ] && printf '%s\n' "$top"
  return 0
}

# resolve_seam_file CONTENT_ROOT REL — echo the path a vault-seam file should be READ
# from; empty when it exists in neither place.
#
# THE PROBLEM this solves is the mirror image of resolve_wiki_root's, and the two want
# OPPOSITE trees, which is why they are separate functions rather than one setting.
# A gate scans the tree being committed, but some of its INPUTS are per-machine state
# the vault git-ignores ON PURPOSE — the foreign-boundary patterns file names the
# identifiers a vault must reject, so tracking it would commit the very strings the
# gate exists to keep out. Git-ignored means structurally absent from every linked
# worktree, while `pre-commit` lints the worktree and `vault-worktree.sh guard`
# refuses canonical commits — so such a gate read its rules from the one tree that
# cannot hold them and reported itself `not armed` on every commit. Fail-open, on a
# boundary gate, and indistinguishable from a vault that never configured it.
#
# THE FALLBACK IS GATED ON `git check-ignore`, not on mere absence, and that is the
# load-bearing part. "Absent from the content tree" also describes a tracked file the
# branch legitimately deleted, and a file a tool is about to CREATE — the summary
# baseline is written by `--seed-baseline`, so resolving it to canonical would write
# outside the branch being committed, which is precisely the bug resolve_wiki_root
# was added to fix. Ignored-and-absent is narrow enough to mean only one thing:
# deliberate per-machine state that lives in canonical or nowhere.
resolve_seam_file() {
  local root="${1:-}" rel="${2:-}"
  [ -n "$root" ] && [ -n "$rel" ] || return 0
  if [ -f "$root/$rel" ]; then printf '%s\n' "$root/$rel"; return 0; fi
  ( cd "$root" 2>/dev/null && git check-ignore -q -- "$rel" 2>/dev/null ) || return 0
  local canon; canon="$(_canonical_root "$root")" || canon=""
  [ -n "$canon" ] && [ "$canon" != "$root" ] && [ -f "$canon/$rel" ] && printf '%s\n' "$canon/$rel"
  return 0
}

# --- WHAT A VAULT WALK MUST NOT SEE ----------------------------------------------------
#
# VAULT_SCAN_SKIP_DIRS is the one list, and it is one list because four copies of it is
# what produced the defect it now closes. Every tool that walks "the vault's pages" had its
# own prune list; four of five omitted `.worktrees`, so every page of every live session
# worktree — a checkout of ANOTHER BRANCH that happens to live inside the vault directory —
# was walked as vault content. Measured with one worktree open: repo pages listed twice by
# the verified-status report, 179 extra pages in the umbrella lint's per-page gates, a
# memory-lint slug set in which a `[[link]]` resolves because some other branch has the
# target, and a migration sweep that would REWRITE files in a checkout its session did not
# author. The counts changed back when the worktree was retired, which is why it survived:
# a tool run from a quiet vault behaves perfectly.
#
# `.worktrees` covers the orphan case too (`<id>.orphaned-<stamp>` is renamed aside INSIDE
# that root), and the RAG indexer names it explicitly even though its language's recursive
# glob already skips dot-prefixed directories — an accidental immunity ends the day the
# directory is renamed to something without a dot.
VAULT_SCAN_SKIP_DIRS=".git engine .obsidian .rag .worktrees"

# vault_pages ROOT [EXTRA_SKIP...] — every markdown page under ROOT that is vault content,
# sorted. Callers add their own extra skips (the verified-status report skips `raw`), and
# get the shared list for free. Returns 0 with no output when ROOT has none.
vault_pages() {
  local root="${1:-}"; shift 2>/dev/null || true
  [ -n "$root" ] || return 0
  local args=() name
  for name in $VAULT_SCAN_SKIP_DIRS "$@"; do
    [ "${#args[@]}" -eq 0 ] && args+=(-name "$name") || args+=(-o -name "$name")
  done
  find "$root" -type d \( "${args[@]}" \) -prune -o -type f -name '*.md' -print 2>/dev/null | sort
  return 0
}

# vault_grep_excludes — the same list as `--exclude-dir=` flags, for the recursive greps
# that cannot use `vault_pages` (they search content rather than enumerate paths). Word
# splitting is intended and safe: these are directory names, never paths.
vault_grep_excludes() {
  local name out=""
  for name in $VAULT_SCAN_SKIP_DIRS; do out="$out --exclude-dir=$name"; done
  printf '%s' "${out# }"
  return 0
}

# canonical_commit_gated ROOT — echo "1" when an ordinary TRACKED-CONTENT commit made in
# ROOT would be refused by this vault's write-time gate; empty when it would be allowed.
#
# THE QUESTION A WRITER MUST ASK is not "does some other session have a worktree open?"
# but "will the caller be able to commit what I am about to write?" Those differ in the
# ordinary between-sessions state: isolation stays configured while the worktree count
# drops to zero. Keying a deferral on the worktree count therefore wrote tracked content
# into canonical and left the guard — correctly — refusing the only commit that would
# land it, with `WIKI_WORKTREE=0` printed as the remedy: a tool creating the state its
# own gate exists to refuse, then recommending the gate be turned off.
#
# Two conditions, matching what `vault-worktree.sh guard` actually does:
#   1. isolation is on — WIKI_WORKTREE=0 is the documented single-session opt-out, and
#      the guard's own first line honours it, so honour it identically here.
#   2. a gate is ARMED for ROOT — resolved the way GIT resolves it, per checkout, because
#      git treats a `core.hooksPath` pointing at a missing directory as "no hooks" and
#      commits without a word. A vault that never wired the gate, or whose gate is inert,
#      can commit in canonical, and nothing should be deferred away from it.
# It reports on the gate's PRESENCE, not on which checks a vault's own hook runs — a
# vault may edit its pre-commit (adoption never overwrites one). Presence is the honest
# test: erring toward deferral costs a printed instruction, erring the other way stages
# a change in a tree that cannot commit it.
canonical_commit_gated() {
  local root="${1:-}" hp resolved
  [ -n "$root" ] || return 0
  [ "${WIKI_WORKTREE:-1}" = "0" ] && return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  hp="$(git -C "$root" config core.hooksPath 2>/dev/null || true)"
  if [ -z "$hp" ]; then
    resolved="$(git -C "$root" rev-parse --git-path hooks 2>/dev/null)" || return 0
    case "$resolved" in /*) ;; *) resolved="$root/$resolved" ;; esac
  else
    case "$hp" in /*) resolved="$hp" ;; *) resolved="$root/$hp" ;; esac
  fi
  [ -x "$resolved/pre-commit" ] && printf '1\n'
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
