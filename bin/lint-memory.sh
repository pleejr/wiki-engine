#!/usr/bin/env bash
# lint-memory.sh — validate a wiki's curated memory/ notes against the engine
# SCHEMA. Memory is kept current by supersession + this lint (see SCHEMA.md).
#
# Per $WIKI_PATH/memory/*.md it checks:
#   ERROR   — missing frontmatter, or missing title/type/brain
#   ERROR   — type not one of: memory | lesson | decision | preference
#   ERROR   — fewer than 2 outbound [[wikilinks]] (SCHEMA: >=2 per page)
#   WARN    — missing updated:
#   WARN    — a [[link]] that resolves to no page in the vault (allowed as a stub,
#             flagged so you can see genuinely stale links)
#   WARN    — an active note not referenced anywhere in index.md (catalog drift)
#   (a note with status: superseded is exempt from the index-drift check)
#
# Exit 1 if any ERROR (or any WARN under --strict); else 0.
#
# Usage:
#   lint-memory.sh                target $WIKI_PATH
#   lint-memory.sh --wiki DIR     target DIR
#   lint-memory.sh --strict       treat warnings as failures
set -euo pipefail

WIKI="${WIKI_PATH:-}"
STRICT=0
TYPES="memory lesson decision preference"

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)   WIKI="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
MEMDIR="$WIKI/memory"
INDEX="$WIKI/index.md"
[ -d "$MEMDIR" ] || { echo "error: no memory dir at $MEMDIR" >&2; exit 1; }

# --- set of resolvable link targets: every page slug in the vault -------------
# (basename without .md, excluding the engine submodule, git, and obsidian dirs)
SLUGS="$(find "$WIKI" \
  -type d \( -name .git -o -name engine -o -name .obsidian \) -prune -o \
  -type f -name '*.md' -print 2>/dev/null \
  | sed -e 's|.*/||' -e 's|\.md$||' | LC_ALL=C sort -u)"

has_slug() { printf '%s\n' "$SLUGS" | grep -qxF "$1"; }

# extract a single-line frontmatter value (between the first two --- fences)
fm_get() {
  awk -v k="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ "^" k ":" { sub(/^[^:]*:[ \t]*/,""); sub(/^"/,""); sub(/"$/,""); print; exit }
  ' "$1"
}

has_frontmatter() { [ "$(head -1 "$1")" = "---" ]; }

errors=0 warnings=0
err()  { errors=$((errors+1));   printf '  ✗ %s\n' "$1"; }
warn() { warnings=$((warnings+1)); printf '  ! %s\n' "$1"; }

shopt -s nullglob
notes=("$MEMDIR"/*.md)
[ ${#notes[@]} -gt 0 ] || { echo "no memory notes in $MEMDIR"; exit 0; }

for f in "${notes[@]}"; do
  slug="$(basename "$f" .md)"
  printf '%s\n' "$slug"

  if ! has_frontmatter "$f"; then
    err "no YAML frontmatter"
    continue
  fi

  # required frontmatter
  for k in title type brain; do
    [ -n "$(fm_get "$f" "$k")" ] || err "missing frontmatter: $k"
  done
  [ -n "$(fm_get "$f" updated)" ] || warn "missing frontmatter: updated"

  # valid type
  typ="$(fm_get "$f" type)"
  if [ -n "$typ" ] && ! printf '%s' " $TYPES " | grep -q " $typ "; then
    err "type '$typ' not in: $TYPES"
  fi

  # outbound wikilinks (unique, alias/heading suffixes stripped)
  links="$(grep -oE '\[\[[^]]+\]\]' "$f" 2>/dev/null \
    | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/[|#].*//' | LC_ALL=C sort -u)"
  nlinks="$(printf '%s' "$links" | grep -c . || true)"
  [ "$nlinks" -ge 2 ] || err "only $nlinks outbound [[wikilink]](s) (need >=2)"

  # dead-link warnings (self-links and empties ignored)
  while IFS= read -r lk; do
    [ -n "$lk" ] || continue
    [ "$lk" = "$slug" ] && continue
    has_slug "$lk" || warn "dead link [[$lk]] (no such page — stub or stale)"
  done <<EOF
$links
EOF

  # index.md catalog drift (active notes only)
  status="$(fm_get "$f" status)"
  if [ "$status" != "superseded" ] && [ -f "$INDEX" ]; then
    grep -qF "[[$slug]]" "$INDEX" || warn "not referenced in index.md (catalog drift)"
  fi
done

echo
echo "memory lint: ${#notes[@]} notes, $errors error(s), $warnings warning(s)"
if [ "$errors" -gt 0 ] || { [ "$STRICT" -eq 1 ] && [ "$warnings" -gt 0 ]; }; then
  exit 1
fi
exit 0
