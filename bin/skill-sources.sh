#!/usr/bin/env bash
# skill-sources.sh — install/verify a machine's declared EXTERNAL skill repos.
# The engine ships only its own skills/; a consumer keeps extra skills in their own repo(s).
# A machine declares those in ~/.claude/skill-sources, one per line:
#     <git-remote> [<dir>]
# (blank lines and # comments ignored; <dir> defaults to ~/Documents/repos/<repo-basename>).
# This clones any declared-but-missing source and runs its bin/link.sh (which links that
# repo's skills + installs any session-check drop-in it ships). GENERIC by design — the
# engine never names a specific repo; the machine declares them (wiki-adopt seeds this at
# adoption). Deterministic; NEVER runs `claude`.
#
# Usage:
#   skill-sources.sh            clone+link any missing declared source (and relink present ones)
#   skill-sources.sh --check    report missing sources, exit 1 if any — NO network, NO clone
set -uo pipefail

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC_FILE="$CFG/skill-sources"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

if [ ! -f "$SRC_FILE" ]; then
  [ "$CHECK" -eq 1 ] && exit 0
  echo "skill-sources: no $SRC_FILE — nothing declared"; exit 0
fi

resolve_dir() {   # $1=remote $2=dir(optional) -> prints absolute dir
  local remote="$1" dir="$2"
  [ -n "$dir" ] || dir="$HOME/Documents/repos/$(basename "$remote" .git)"
  case "$dir" in "~/"*) dir="$HOME/${dir#\~/}";; esac
  printf '%s' "$dir"
}

missing=0
while read -r remote dir _rest; do
  case "$remote" in ''|'#'*) continue;; esac
  dir="$(resolve_dir "$remote" "${dir:-}")"
  if [ -d "$dir/.git" ]; then
    [ "$CHECK" -eq 1 ] && continue
    echo "ok    $(basename "$dir") present"
    [ -x "$dir/bin/link.sh" ] && "$dir/bin/link.sh" >/dev/null && echo "      linked ($dir/bin/link.sh)"
    continue
  fi
  missing=$((missing+1))
  if [ "$CHECK" -eq 1 ]; then
    echo "missing: $remote -> $dir"
  else
    echo "clone $remote -> $dir"
    mkdir -p "$(dirname "$dir")"
    if git clone "$remote" "$dir" </dev/null; then
      [ -x "$dir/bin/link.sh" ] && "$dir/bin/link.sh" >/dev/null && echo "      linked"
    else
      echo "  ! clone failed: $remote (check access/identity for this remote)" >&2
    fi
  fi
done < "$SRC_FILE"

if [ "$CHECK" -eq 1 ]; then
  [ "$missing" -eq 0 ] || echo "$missing declared skill source(s) not installed — run skill-sources.sh" >&2
  [ "$missing" -eq 0 ]
fi
