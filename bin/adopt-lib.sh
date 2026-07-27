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
