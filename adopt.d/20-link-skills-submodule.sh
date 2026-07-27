#!/usr/bin/env bash
# 20-link-skills-submodule.sh — adoption step: point the machine's skill symlinks at the
# vault's PINNED submodule engine, so skills track the pin instead of drifting.
#
# The cold-start bootstrap (`link-skills.sh`, run from a standalone clone before a vault
# exists) symlinks ~/.claude/skills/* at whatever engine clone it ran from. Post-adoption
# that clone is no longer the source of truth — the vault's `engine/` submodule is — but
# nothing repointed the symlinks, so `update.sh` (which bumps only the pin) left the LIVE
# skills lagging the pinned engine. This step closes that gap: on each session `apply-
# adopt.sh` repoints any engine-skill slot that doesn't already resolve to `$ENGINE/skills`
# (here `$ENGINE` is the pinned submodule), so a pin bump updates tooling AND skills.
#
# Run by apply-adopt.sh with WIKI, ENGINE, ADOPT_CHECK exported. Idempotent — prints only
# what it changes. Only iterates the engine's OWN skills, so foreign skills (e.g. a
# `redteam` symlinked from another repo) are never touched; a real dir/file in a slot is
# left alone. Deterministic; never runs `claude`.
set -uo pipefail

: "${ENGINE:?}"
. "${ADOPT_LIB:?}" || exit 3

SRC="$ENGINE/skills"
DEST="${ADOPT_SKILLS_DIR:?}"

# ENGINE ASSET — unconditional, and above the ephemeral guard on purpose. This was
# `[ -d "$SRC" ] || exit 0`, which resolves correctly today and so was silent for the
# right reason; a future refactor of the engine's layout would have made it silent for
# the wrong one, with skill links this time. See bin/adopt-lib.sh for the rule.
require_engine_asset "$SRC" dir "the engine's own skills, which the machine links to"

# Never repoint the MACHINE's live skills at an EPHEMERAL vault (test / CI / scratchpad).
# Worse than the stale-hook case this mirrors: these symlinks are what Claude Code loads,
# so aiming them at a throwaway engine breaks every engine skill on the machine the moment
# that directory is cleaned — and they keep resolving until then, so nothing announces it.
# apply-adopt.sh decides this once (ADOPT_WIRE_SKILLS); not re-derived here.
#
# Gated on the SKILLS redirect specifically, not on a shared machine flag: redirecting
# --settings contains settings.json and nothing else, and treating it as blanket isolation
# is what let a throwaway vault repoint this machine's real skill links.
[ "${ADOPT_WIRE_SKILLS:-1}" = "1" ] || exit 0

for s in "$SRC"/*/; do
  [ -d "$s" ] || continue
  name="$(basename "$s")"
  want="$SRC/$name"
  tgt="$DEST/$name"

  if [ -L "$tgt" ]; then
    cur="$(cd "$(dirname "$tgt")" && cd "$(readlink "$tgt")" 2>/dev/null && pwd || true)"
    [ "$cur" = "$want" ] && continue                 # already tracks the submodule
    action="repoint $name (was $(readlink "$tgt"))"
  elif [ -e "$tgt" ]; then
    continue                                         # real path in the slot — don't clobber
  else
    action="link $name"
  fi

  if [ -n "${ADOPT_CHECK:-}" ]; then
    echo "would $action -> $want"
  else
    mkdir -p "$DEST"
    ln -sfn "$want" "$tgt"
    echo "${action%% *} skill $name -> $want"
  fi
done
