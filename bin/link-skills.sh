#!/usr/bin/env bash
# link-skills.sh — symlink this engine's skills into ~/.claude/skills so Claude Code
# discovers them (as global skills) from any folder. Deterministic; never calls
# `claude`. This is the bootstrap that makes `/wiki-adopt` available on a fresh
# machine — Claude Code scans ~/.claude/skills and <project>/.claude/skills, never a
# repo's bare skills/ dir, so cloning the engine alone does not expose the skills.
#
# Idempotent and non-destructive: an existing link already pointing at this engine is
# left as-is; a slot occupied by something ELSE (another engine, a real dir/file) is
# warned about and skipped unless --force repoints it.
#
# Usage:
#   link-skills.sh            link all engine skills into ~/.claude/skills
#   link-skills.sh --force    repoint slots held by a foreign target
#   -h, --help                show this
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_SRC="$ENGINE_ROOT/skills"
DEST="$HOME/.claude/skills"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -d "$SKILLS_SRC" ] || { echo "error: no skills dir at $SKILLS_SRC" >&2; exit 1; }
mkdir -p "$DEST"

linked=0 kept=0 skipped=0
for s in "$SKILLS_SRC"/*/; do
  [ -d "$s" ] || continue
  name="$(basename "$s")"
  src="$SKILLS_SRC/$name"
  tgt="$DEST/$name"
  if [ -L "$tgt" ]; then
    cur="$(cd "$(dirname "$tgt")" && cd "$(readlink "$tgt")" 2>/dev/null && pwd || true)"
    if [ "$cur" = "$src" ]; then kept=$((kept+1)); continue; fi
    if [ "$FORCE" -eq 1 ]; then ln -sfn "$src" "$tgt"; echo "  repointed $name -> $src"; linked=$((linked+1)); continue; fi
    echo "  ! $name already links elsewhere ($(readlink "$tgt")) — skipped (use --force to repoint)" >&2
    skipped=$((skipped+1)); continue
  elif [ -e "$tgt" ]; then
    echo "  ! $name exists as a real path (not our symlink) — skipped (remove it by hand if intended)" >&2
    skipped=$((skipped+1)); continue
  fi
  ln -sfn "$src" "$tgt"; linked=$((linked+1))
done

echo "link-skills: $linked linked, $kept already current, $skipped skipped -> $DEST"
[ "$skipped" -eq 0 ] || exit 0