#!/usr/bin/env bash
# adopt-lib.sh — shared helpers for adopt.d/ steps.
#
# SOURCED, never run as a step. It lives in bin/ precisely BECAUSE apply-adopt.sh globs
# `adopt.d/*.sh` — a helper placed there would be executed as a step on every adopt run,
# its output would become a phantom "ADOPTED:" line, and a non-zero exit from it would
# block the adoption marker forever. Steps pick it up via the exported $ADOPT_LIB:
#
#     . "${ADOPT_LIB:?}" || exit 3
#
# The `|| exit 3` is load-bearing and not decoration: steps run under `set -uo pipefail`
# (no `-e`), so a failed `source` would otherwise print an error and let the step carry
# on — reintroducing, at the root of the mechanism, exactly the silent skip this file
# exists to abolish. `:?` covers an unset variable; `|| exit 3` covers a missing file.
#
# ---------------------------------------------------------------------------------
# THE RULE THIS FILE EXISTS FOR — two kinds of missing thing, two opposite responses:
#
#   CONSUMER STATE — something the VAULT may or may not have: a git repo, a settings
#     file, a hook the vault wrote itself, an opted-out feature.
#     -> `|| exit 0`. A legitimate no-op. Absence is information, not a bug.
#
#   ENGINE ASSET — something the ENGINE ITSELF ships: a scaffold template, the skills
#     directory, one of its own bin scripts.
#     -> `require_engine_asset`. Absence is a packaging or path bug in the engine, and
#        there is no correct silent response to it.
#
# Both used to be written `|| exit 0`, which is how the pre-commit gate shipped in
# v1.28.0 and installed on nothing for four minor releases: the step resolved its
# template one directory too high, found no file, and exited 0. apply-adopt.sh cannot
# tell those two cases apart — "rc=0, no output" is the correct and common result for an
# idempotent step on a converged machine. The STEP knows which guard it is; the adopter
# never can. So the distinction has to be made here, at the call site.
#
# REQUIRES RUN UNCONDITIONALLY, at the TOP of a step, ABOVE every consumer-state guard.
# Ordering is not incidental: put a require below `is this a git repo?` or below the
# ephemeral-vault guard and a mispackaged engine goes unreported on every vault that
# isn't a git repo and on every throwaway run — narrowing the detector to exactly the
# machines least likely to be running CI.
# ---------------------------------------------------------------------------------

# require_engine_asset <path> <file|dir> [description]
#
# Assert that an engine-bundled asset is where the step thinks it is. On failure: name
# the RESOLVED path (the whole point — "$ENGINE/../scaffold/pre-commit" reads fine and
# resolves into the consumer's vault root), say it is an engine bug rather than vault
# state, and exit 3 so apply-adopt.sh reports the step as failed and leaves the adoption
# marker unwritten. The next session retries; steps are idempotent, so retrying is safe.
require_engine_asset() {
  local path="${1:?require_engine_asset: path}"
  local kind="${2:?require_engine_asset: file|dir}"
  local what="${3:-}"

  case "$kind" in
    file) [ -f "$path" ] && return 0 ;;
    dir)  [ -d "$path" ] && return 0 ;;
    *) echo "adopt: FATAL — require_engine_asset: bad kind '$kind' (want file|dir)" >&2; exit 3 ;;
  esac

  echo "adopt: FATAL — missing engine $kind: $path" >&2
  [ -n "$what" ] && echo "adopt:   needed for: $what" >&2
  echo "adopt:   This is an ENGINE packaging/path bug, not vault state — the engine is" >&2
  echo "adopt:   supposed to ship this. Not skipping: a skipped step reports as adopted." >&2
  exit 3
}

# gate_wiring_status <vault>
#
# Answer the question every reporting surface got wrong three times running: not "did we
# install a hook?" but "will a hook actually RUN on the commits this workflow tells you
# to make?" Those differ, and the gap is silent — git treats a `core.hooksPath` that
# resolves to a missing directory as "no hooks configured" and commits without a word.
#
# Resolves the way GIT does, per checkout: a RELATIVE core.hooksPath is taken against the
# working tree the commit is made in, so it lands in `<worktree>/.githooks` — which does
# not exist, because an untracked `.githooks/` lives only in the canonical checkout. That
# is the v1.34.0 defect, and it is why this asks each worktree separately rather than
# asking the canonical checkout once.
#
# Prints one line per checkout; returns 1 if ANY checkout would commit ungated.
gate_wiring_status() {
  local vault="${1:?gate_wiring_status: vault}" bad=0 wt hp resolved
  git -C "$vault" rev-parse --git-dir >/dev/null 2>&1 || { echo "  not a git repo — no gate to wire"; return 0; }

  # Full precedence, not --local: a vault using extensions.worktreeConfig can override
  # this per worktree, and what matters is the value git will actually obey there.
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    hp="$(git -C "$wt" config core.hooksPath 2>/dev/null || true)"
    if [ -z "$hp" ]; then
      resolved="$(git -C "$wt" rev-parse --git-path hooks 2>/dev/null)"
      case "$resolved" in /*) ;; *) resolved="$wt/$resolved" ;; esac
    else
      case "$hp" in /*) resolved="$hp" ;; *) resolved="$wt/$hp" ;; esac
    fi
    if [ -x "$resolved/pre-commit" ]; then
      echo "  gate ARMED   $wt -> $resolved/pre-commit"
    else
      echo "  gate INERT   $wt -> $resolved/pre-commit (missing or not executable)"
      bad=1
    fi
  done < <(git -C "$vault" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10)}')

  return "$bad"
}
