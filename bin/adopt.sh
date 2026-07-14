#!/usr/bin/env bash
# adopt.sh — bring an existing vault up to the engine's current framework.
# Ensures every node folder in scaffold/node-dirs.txt exists (idempotent). Run after
# bumping the engine submodule pin, so new node types added to the engine actually
# appear in the vault (a pin bump alone updates skills/SCHEMA/bin, not vault folders).
#
# Usage:
#   adopt.sh                lint/create against $WIKI_PATH
#   adopt.sh --wiki DIR     target DIR
#   adopt.sh --check        report missing folders and exit 1 (no changes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIRS_FILE="$ENGINE_ROOT/scaffold/node-dirs.txt"

WIKI="${WIKI_PATH:-}"
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)  WIKI="$2"; shift 2;;
    --check) CHECK=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -f "$DIRS_FILE" ] || { echo "error: missing $DIRS_FILE" >&2; exit 1; }

missing=0
while IFS= read -r d; do
  case "$d" in ''|'#'*) continue;; esac
  if [ -d "$WIKI/$d" ]; then continue; fi
  missing=$((missing+1))
  if [ "$CHECK" -eq 1 ]; then
    echo "missing: $d"
  else
    mkdir -p "$WIKI/$d"; touch "$WIKI/$d/.gitkeep"
    echo "+ created $d/"
  fi
done < "$DIRS_FILE"

if [ "$missing" -eq 0 ]; then
  echo "vault already matches the engine's node folders"
  exit 0
fi
if [ "$CHECK" -eq 1 ]; then
  echo "$missing folder(s) missing — run adopt.sh (no --check) to create them" >&2
  exit 1
fi
echo "adopted $missing new node folder(s); add an index.md section for each"
