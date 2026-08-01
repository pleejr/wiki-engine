#!/usr/bin/env bash
# lint-links.sh — link-integrity gate for a wiki vault.
#
# WHY THIS IS NOT "every dangling link is an error": per SCHEMA.md a dangling
# [[link]] is a LEGITIMATE STUB MARKER — it names a page worth writing later. A gate
# that failed on all of them would either be permanently red or force an allowlist
# edit for every forward reference, which is how a gate stops being read. The defect
# worth catching is narrower: a link that was MEANT to resolve and doesn't — a typo,
# or a slug left behind by a rename. So:
#
#   ERROR  — dangling AND near-miss to a real slug (see near_miss below). Almost
#            certainly a typo or a stale slug after a rename; the vault's own
#            `project-pi-cluster` -> `pi-cluster` break is this shape.
#   WARN   — dangling with no near match. A stub, per SCHEMA. Reported, never fatal.
#   silent — a link inside a code span or fenced block (documentation ABOUT wikilinks,
#            e.g. `[[wikilink]]`, not a link), and any target declared in the vault's
#            external-refs file (things that must NEVER resolve here: another
#            boundary's pages, engine files, skill names).
#
# SCOPE: the flat non-raw node folders from scaffold/node-dirs.txt. Root hubs
# (index/log/README/CLAUDE) and raw/ are deliberately not nodes — log.md in
# particular is append-only history that legitimately cites pages since renamed or
# tombstoned, so gating it would make history un-writable.
#
# Usage:
#   lint-links.sh                 target $WIKI_PATH
#   lint-links.sh --wiki DIR      target DIR
#   lint-links.sh --strict        treat stub warnings as failures too
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI="${WIKI_PATH:-}"
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)   WIKI="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

# --- the vault seam (optional; absent = engine defaults) -----------------------
# Parsed, never sourced: a config file that can execute code is a config file that
# can own the machine running the gate.
# Read through resolve_seam_file so a seam file the vault deliberately git-ignores
# is still found when $WIKI is a linked worktree, which structurally cannot hold
# one. See bin/wiki-root-lib.sh — the fallback is gated on `git check-ignore`, not
# on mere absence, so a tracked file a branch legitimately deleted still reads as
# deleted.
GATES_CONF="$(resolve_seam_file "$WIKI" ".wiki-gates.conf")"
conf_get() {
  [ -n "$GATES_CONF" ] && [ -f "$GATES_CONF" ] || return 0
  awk -F= -v k="$1" '
    /^[ \t]*#/ { next }
    {
      key=$1; sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key)
      if (key != k) next
      sub(/^[^=]*=/,""); val=$0
      sub(/^[ \t]+/,"",val); sub(/[ \t]+$/,"",val)
      print val; exit
    }' "$GATES_CONF"
}

EXT_FILE="$(conf_get external_refs)"
[ -n "$EXT_FILE" ] || EXT_FILE=".wiki-gates-external-refs"
EXTERNAL=""
EXT_PATH="$(resolve_seam_file "$WIKI" "$EXT_FILE")"
[ -n "$EXT_PATH" ] && EXTERNAL="$(grep -v '^[ \t]*#' "$EXT_PATH" | grep -v '^[ \t]*$' || true)"

# --- resolvable targets: every page slug in the vault --------------------------
SLUGS="$(find "$WIKI" \
  -type d \( -name .git -o -name engine -o -name .obsidian -o -name .rag -o -name .worktrees \) -prune -o \
  -type f -name '*.md' -print 2>/dev/null \
  | sed -e 's|.*/||' -e 's|\.md$||' | LC_ALL=C sort -u)"

# --- content-node dirs (shared definition with lint.sh) ------------------------
NODE_DIRS=()
NODE_DIRS_FILE="$SCRIPT_DIR/../scaffold/node-dirs.txt"
if [ -f "$NODE_DIRS_FILE" ]; then
  while IFS= read -r d; do
    case "$d" in ''|'#'*|raw/*) continue;; esac
    NODE_DIRS+=("$d")
  done < "$NODE_DIRS_FILE"
fi

# --- links in prose only: strip fenced blocks and inline code spans ------------
# `[[wikilink]]` in backticks is documentation ABOUT the syntax, not a link.
prose_links() {
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      line=$0
      # Strip LONGER backtick runs first. CommonMark lets a code span be delimited
      # by N backticks so it can contain runs of fewer — ``[[x]]`` is the natural
      # way to show a literal link, and a single-backtick-only pass would eat the
      # delimiters and leave [[x]] looking like a real link. Found by dogfooding:
      # the first doc written after this gate shipped tripped exactly this.
      gsub(/```[^`]*```/, "", line)
      gsub(/``[^`]*``/,   "", line)
      gsub(/`[^`]*`/,     "", line)
      print line
    }
  ' "$1" \
  | grep -oE '\[\[[^]]+\]\]' 2>/dev/null \
  | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/[|#].*//' \
  | LC_ALL=C sort -u
}

# --- near-miss: "this was meant to resolve" ------------------------------------
# Three independent tests, because no single one covers the real failure modes:
#   1. normalized equality  — case / punctuation drift (Foo_Bar vs foo-bar)
#   2. edit distance <= 2   — ordinary typos, on targets long enough that a 2-char
#                             difference isn't just a different short word
#   3. component-run        — the rename shape: one slug's hyphen components appear
#                             CONTIGUOUSLY in the other's and cover >=60% of them.
#                             Needed because edit distance does NOT catch this:
#                             project-pi-cluster vs pi-cluster scores only ~0.71
#                             similarity, under any threshold safe to enforce.
# Prints the matched slug (first hit) and exits 0; exits 1 if no near match.
near_miss() {
  printf '%s\n' "$SLUGS" | awk -v t="$1" '
    function min3(a,b,c) { return (a<b ? (a<c?a:c) : (b<c?b:c)) }
    function lev(s, tt,   m,n,i,j,d,prev,cur,cost) {
      m=length(s); n=length(tt)
      if (m==0) return n; if (n==0) return m
      for (j=0; j<=n; j++) prev[j]=j
      for (i=1; i<=m; i++) {
        cur[0]=i
        for (j=1; j<=n; j++) {
          cost = (substr(s,i,1)==substr(tt,j,1)) ? 0 : 1
          cur[j] = min3(cur[j-1]+1, prev[j]+1, prev[j-1]+cost)
        }
        for (j=0; j<=n; j++) prev[j]=cur[j]
      }
      return prev[n]
    }
    function norm(x) { x=tolower(x); gsub(/[^a-z0-9]/,"",x); return x }
    function run_match(a, b,   ac,bc,an,bn,i,j,k,ok) {
      an=split(a, ac, "-"); bn=split(b, bc, "-")
      if (an > bn) return 0                      # a must be the shorter one
      if (an/bn < 0.6) return 0                  # too small a fragment to be a rename
      for (i=1; i<=bn-an+1; i++) {
        ok=1
        for (k=0; k<an; k++) if (ac[k+1] != bc[i+k]) { ok=0; break }
        if (ok) return 1
      }
      return 0
    }
    {
      s=$0
      if (s == t) next                            # resolves; not our business
      if (norm(s) == norm(t)) { print s; found=1; exit }
      if (length(t) >= 5 && length(s) >= 5 && lev(tolower(s), tolower(t)) <= 2) { print s; found=1; exit }
      if (run_match(t, s) || run_match(s, t)) { print s; found=1; exit }
    }
    END { exit !found }
  '
}

is_external() { printf '%s\n' "$EXTERNAL" | grep -qxF "$1"; }
has_slug()    { printf '%s\n' "$SLUGS"    | grep -qxF "$1"; }

errors=0 warnings=0 pages=0
for d in "${NODE_DIRS[@]}"; do
  [ -d "$WIKI/$d" ] || continue
  for f in "$WIKI/$d"/*.md; do
    [ -f "$f" ] || continue
    pages=$((pages+1))
    slug="$(basename "$f" .md)"
    header_shown=0
    while IFS= read -r lk; do
      [ -n "$lk" ] || continue
      [ "$lk" = "$slug" ] && continue
      has_slug "$lk" && continue
      is_external "$lk" && continue
      if hit="$(near_miss "$lk")"; then
        [ "$header_shown" -eq 0 ] && { printf '%s\n' "${f#$WIKI/}"; header_shown=1; }
        printf '  ✗ [[%s]] does not resolve, but [[%s]] does — typo or a slug left behind by a rename\n' "$lk" "$hit"
        errors=$((errors+1))
      else
        [ "$header_shown" -eq 0 ] && { printf '%s\n' "${f#$WIKI/}"; header_shown=1; }
        printf '  ! [[%s]] is a stub (no such page — intended per SCHEMA, or add it to %s)\n' "$lk" "$EXT_FILE"
        warnings=$((warnings+1))
      fi
    done < <(prose_links "$f")
  done
done

echo
echo "link lint: $pages content-node page(s), $errors error(s), $warnings stub warning(s)"
if [ "$errors" -gt 0 ] || { [ "$STRICT" -eq 1 ] && [ "$warnings" -gt 0 ]; }; then
  exit 1
fi
exit 0
