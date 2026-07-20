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
SRC="$ENGINE/skills"
DEST="$HOME/.claude/skills"
[ -d "$SRC" ] || exit 0

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
