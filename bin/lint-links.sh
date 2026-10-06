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
WIKI=""   # explicit --wiki only; the default is resolved below, not here
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)   WIKI="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

# Same verdict-about-the-wrong-tree defect as lint.sh: bound to $WIKI_PATH, a bare
# run from inside a session worktree answered confidently about canonical. Only
# tools whose target is TRACKED VAULT CONTENT resolve this way (wiki-root-lib.sh);
# this one's is, and an explicit --wiki is still never second-guessed.
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1

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
SLUGS="$(vault_pages "$WIKI" | sed -e 's|.*/||' -e 's|\.md$||' | LC_ALL=C sort -u)"

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

# A HERE-STRING, never `printf … | grep -q`. Under `set -o pipefail` the pipe form reports
# FAILURE exactly when the lookup SUCCEEDS on a long list: `grep -q` exits at the first
# match and closes the read end, the writer takes EPIPE, and pipefail promotes that to the
# pipeline's status — so a page that exists reads as missing. It needs the writer to still
# be writing, so it fires once the list outgrows the pipe buffer (~64 KB) and not before:
# one platform stayed clean while a Linux runner reported 40+ false dead links across a
# whole vault, on the same tree. A here-string has no reader to close early.
is_external() { grep -qxF -- "$1" <<<"$EXTERNAL"; }
has_slug()    { grep -qxF -- "$1" <<<"$SLUGS"; }

errors=0 warnings=0 pages=0
# ONE pass over every page, then ONE join against the slug set. The per-link form ran a
# `grep` over the whole slug list for every link, so cost grew as links x pages: a vault
# three times larger linted about nine times slower. Order and output are unchanged:
# pages in NODE_DIRS then glob order, each page's links unique and C-sorted, and
# near_miss still runs per unresolved link — which is rare, so it stays out of the hot path.
LL_TMP="$(mktemp -d)"; trap 'rm -rf "$LL_TMP"' EXIT
: > "$LL_TMP/files"
for d in "${NODE_DIRS[@]}"; do
  [ -d "$WIKI/$d" ] || continue
  for f in "$WIKI/$d"/*.md; do
    [ -f "$f" ] || continue
    pages=$((pages+1))
    printf '%s\n' "$f" >> "$LL_TMP/files"
  done
done
printf '%s\n' "$SLUGS" > "$LL_TMP/slugs"
printf '%s\n' "$EXTERNAL" > "$LL_TMP/external"
if [ "$pages" -gt 0 ]; then
  # Same extraction as prose_links: fenced blocks and code spans (longest backtick runs
  # first) are not links; then [[target|alias#anchor]] -> target.
  tr '\n' '\0' < "$LL_TMP/files" | xargs -0 awk '
    FNR == 1 { idx++; fence = 0 }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    {
      line = $0
      gsub(/```[^`]*```/, "", line)
      gsub(/``[^`]*``/,   "", line)
      gsub(/`[^`]*`/,     "", line)
      while (match(line, /\[\[[^]]+\]\]/)) {
        lk = substr(line, RSTART + 2, RLENGTH - 4)
        sub(/[|#].*/, "", lk)
        if (lk != "") print idx "\t" lk
        line = substr(line, RSTART + RLENGTH)
      }
    }' | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2 -u > "$LL_TMP/links"
  # Keep only what does not resolve: not the page itself, not a slug, not external.
  awk -F '\t' -v files="$LL_TMP/files" -v slugs="$LL_TMP/slugs" -v ext="$LL_TMP/external" '
    BEGIN {
      while ((getline l < slugs) > 0) if (l != "") S[l] = 1
      while ((getline l < ext) > 0)   if (l != "") X[l] = 1
      while ((getline l < files) > 0) { n++; p = l; sub(/.*\//, "", p); sub(/\.md$/, "", p); SELF[n] = p }
    }
    { if ($2 == SELF[$1] || ($2 in S) || ($2 in X)) next; print }
  ' "$LL_TMP/links" > "$LL_TMP/unresolved"
  # near_miss for every unresolved link in ONE process, same tests in the same order, first
  # slug wins. Edit distance is skipped when lengths differ by more than 2, because the
  # distance can then not be <= 2 — the result is identical and the hot path stays linear.
  cut -f2 "$LL_TMP/unresolved" | awk -v slugs="$LL_TMP/slugs" '
    function min3(a,b,c) { return (a<b ? (a<c?a:c) : (b<c?b:c)) }
    function lev(s, tt,   m,n,i,j,prev,cur,cost) {
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
    function run_match(a, b,   ac,bc,an,bn,i,k,ok) {
      an=split(a, ac, "-"); bn=split(b, bc, "-")
      if (an > bn) return 0
      if (an/bn < 0.6) return 0
      for (i=1; i<=bn-an+1; i++) {
        ok=1
        for (k=0; k<an; k++) if (ac[k+1] != bc[i+k]) { ok=0; break }
        if (ok) return 1
      }
      return 0
    }
    BEGIN { while ((getline l < slugs) > 0) { ns++; SL[ns]=l; NM[ns]=norm(l); LN[ns]=length(l); LW[ns]=tolower(l); CP[ns]="-" l "-"; F1[ns]=l; sub(/-.*/, "", F1[ns]) } }
    {
      t=$0; nt=norm(t); lt=length(t); tw=tolower(t); hit=""; tc="-" t "-"; t1=t; sub(/-.*/, "", t1)
      for (k=1; k<=ns; k++) {
        s=SL[k]
        if (s == t) continue
        if (NM[k] == nt) { hit=s; break }
        d = LN[k] - lt; if (d < 0) d = -d
        if (lt >= 5 && LN[k] >= 5 && d <= 2 && lev(LW[k], tw) <= 2) { hit=s; break }
        # A contiguous component run must contain the FIRST component of the shorter side, so a
        # slug that does not hold it as a whole component cannot match: skip the split.
        if ((index(CP[k], "-" t1 "-") && run_match(t, s)) || (index(tc, "-" F1[k] "-") && run_match(s, t))) { hit=s; break }
      }
      print hit
    }' > "$LL_TMP/hits"
  last=""
  while IFS="$(printf '\t')" read -r idx lk <&3 && IFS= read -r hit <&4; do
    f="$(sed -n "${idx}p" "$LL_TMP/files")"
    if [ "$idx" != "$last" ]; then printf '%s\n' "${f#$WIKI/}"; last="$idx"; fi
    if [ -n "$hit" ]; then
      printf '  ✗ [[%s]] does not resolve, but [[%s]] does — typo or a slug left behind by a rename\n' "$lk" "$hit"
      errors=$((errors+1))
    else
      printf '  ! [[%s]] is a stub (no such page — intended per SCHEMA, or add it to %s)\n' "$lk" "$EXT_FILE"
      warnings=$((warnings+1))
    fi
  done 3< "$LL_TMP/unresolved" 4< "$LL_TMP/hits"
fi

echo
echo "link lint: $pages content-node page(s), $errors error(s), $warnings stub warning(s)"
if [ "$errors" -gt 0 ] || { [ "$STRICT" -eq 1 ] && [ "$warnings" -gt 0 ]; }; then
  exit 1
fi
exit 0
