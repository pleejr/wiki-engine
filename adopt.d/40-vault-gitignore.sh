#!/usr/bin/env bash
# 40-vault-gitignore.sh — adoption step: reconcile an existing vault's .gitignore with
# the engine's template, ADD-ONLY.
#
# scaffold/gitignore.tmpl was applied once, by new-wiki.sh, and nothing ever revisited
# it. So every entry added to the template after a vault was scaffolded never reached
# that vault, and the artifact the entry exists to hide stayed untracked forever. Worse,
# adoption itself creates paths — .engine-adopted, .githooks/, the node folders' .gitkeep
# files — so a vault got dirtier the more of the engine it adopted.
#
# WHY THIS IS NOT COSMETIC. The engine's own position is that a check which is always red
# is one that gets bypassed (stated when fixing the always-dirty `integrate` and the
# always-passing adoption guard). A `git status` that permanently lists engine artifacts
# is that same failure at the human layer: it trains the operator to skim untracked
# paths, which is exactly when a real one goes unnoticed. That is not hypothetical — it
# happened while this very step was being written, where standing noise hid three
# uncommitted pages that `git commit -am` had silently not staged.
#
# And one entry carries a safety property outright: .wiki-gates.local names the OTHER
# boundary's identifiers, so a vault that adopts the foreign-boundary gate without
# receiving that ignore line is one `git add -A` away from committing precisely what the
# gate exists to keep out.
#
# ADD-ONLY, and that is the whole discipline: never reorder, never remove, never rewrite
# an entry the vault added itself. A .gitignore is the vault's file; adoption may only
# append what the vault is missing. Matching is on the ENTRY TEXT, normalized, so a vault
# already ignoring a path under a different spelling is not handed a duplicate.
#
# Run by apply-adopt.sh with WIKI / ENGINE exported (ADOPT_CHECK set when only reporting).
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"
# shellcheck source=bin/adopt-lib.sh
. "${ADOPT_LIB:?}" || exit 3

TMPL="$ENGINE/scaffold/gitignore.tmpl"
GI="$WIKI/.gitignore"
CHECK="${ADOPT_CHECK:-}"

# ENGINE ASSET — unconditional, above every consumer-state guard (see adopt-lib.sh).
require_engine_asset "$TMPL" file "the vault .gitignore template"

# CONSUMER STATE — a vault that isn't a git repo has no .gitignore to reconcile.
git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# `.upkeep` / `.upkeep/` / `/.upkeep/` are the same rule; compare them as such so a
# hand-written entry never gets a near-duplicate appended next to it.
norm() { local e="$1"; e="${e#/}"; e="${e%/}"; printf '%s' "$e"; }

have=""
if [ -f "$GI" ]; then
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in ''|'#'*) continue ;; esac
    l="${l%"${l##*[![:space:]]}"}"
    have="$have$(norm "$l")"$'\n'
  done < "$GI"
fi

missing=0
pending=""      # comment block accumulating above the entry it documents
add=""
while IFS= read -r l || [ -n "$l" ]; do
  case "$l" in
    '') pending=""; continue ;;
    '#'*) pending="$pending$l"$'\n'; continue ;;
  esac
  entry="${l%"${l##*[![:space:]]}"}"
  if ! printf '%s' "$have" | grep -qxF "$(norm "$entry")"; then
    # carry the comment across too: the reason an entry exists is the part a reader
    # needs, and .wiki-gates.local's comment IS its safety rationale
    add="$add"$'\n'"$pending$entry"$'\n'
    missing=$((missing+1))
    if [ -n "$CHECK" ]; then echo "adopt: would add '$entry' to $GI"; fi
  fi
  pending=""
done < "$TMPL"

[ "$missing" -eq 0 ] && exit 0

if [ -n "$CHECK" ]; then
  echo "adopt: would append $missing missing entr(y/ies) to .gitignore (add-only)"
  exit 0
fi

# Append only. An absent .gitignore is created; an existing one is never rewritten, so
# the vault's own entries, ordering and comments survive untouched.
if [ ! -f "$GI" ]; then
  printf '# Vault ignores. Engine-managed entries are appended by adoption (add-only).\n' > "$GI"
fi
printf '%s' "$add" >> "$GI"
echo "adopt: appended $missing missing .gitignore entr(y/ies) from the engine template"
exit 0
