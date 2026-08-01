#!/usr/bin/env bash
# lint.sh — umbrella lint for a wiki vault. Runs every deterministic check and
# aggregates the result, so `checkpoint` (or a pre-commit) can call one command:
#   1. memory notes         — lint-memory.sh (frontmatter, type, >=2 wikilinks, drift)
#   2. frontmatter props     — wikilink-valued properties must be a quoted YAML block
#                              list; catches Obsidian's "invalid properties"
#   3. soft-wrap drift       — reflow.sh --check (hard wraps that would render broken)
#   4. skills catalog drift  — gen-skills-index.sh --check
#   5. projects catalog drift — gen-projects-index.sh --check
#   6. boundary present      — every content-node page (the non-raw node folders in
#                              scaffold/node-dirs.txt) declares a boundary: — the
#                              first line of defense for the vault's boundary rule
#   7. provenance present    — every repos/ page carries a sources: block with
#                              ref: + sha: (a version-keyed node must record what it
#                              was ingested from, so freshness is checkable)
#   8. summary volatility    — a project page's summary: must name IDENTITY, not state;
#                              a decaying summary goes false with no edit at all. Skipped
#                              for done/ pages (frozen claims), flagged for unknown status
#   9. link integrity        — lint-links.sh: a dangling [[link]] that NEARLY matches
#                              a real slug is an error (typo / stale slug after a
#                              rename); one that matches nothing is a stub per SCHEMA
#                              and stays a warning
#  10. foreign boundary      — no other-boundary identifiers in this vault's pages.
#                              OPT-IN: inactive until the vault supplies a patterns
#                              file, and says so rather than passing silently
#
# Checks 6–9 are vault-invariant GATES: they must hold at zero, so lint.sh doubles
# as the enforced write-time gate (vault CI + pre-commit) — see the pleejr-wiki
# engine-gates-at-zero project. 6–8 carry no per-vault values, so they ship
# engine-default-on; 9 needs a consumer-specific denylist and therefore sits behind
# the vault seam ($WIKI/.wiki-gates.conf) — the engine composes it, the vault fills
# it in, and the engine names no consumer's strings.
#
# Exit 1 if any check fails.
#
# Usage:
#   lint.sh                 lint $WIKI_PATH
#   lint.sh --wiki DIR      lint DIR
#   lint.sh --strict        pass --strict through to lint-memory (warnings fail)
set -uo pipefail   # deliberately not -e: run all checks, then aggregate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI="${WIKI_PATH:-}"
STRICT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)   WIKI="$2"; shift 2;;
    --strict) STRICT="--strict"; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

# vault markdown, excluding the engine submodule and non-content dirs.
# (while-read, not mapfile — macOS ships bash 3.2.)
PAGES=()
while IFS= read -r p; do PAGES+=("$p"); done < <(find "$WIKI" \
  -type d \( -name .git -o -name engine -o -name .obsidian -o -name .rag \) -prune -o \
  -type f -name '*.md' -print | sort)
[ "${#PAGES[@]}" -gt 0 ] || { echo "error: no pages under $WIKI" >&2; exit 1; }

rc=0
section() { printf '\n=== %s ===\n' "$1"; }

# 1. memory ---------------------------------------------------------------------
section "memory notes"
"$SCRIPT_DIR/lint-memory.sh" --wiki "$WIKI" $STRICT || rc=1

# 2. frontmatter properties -----------------------------------------------------
# A wikilink in frontmatter is valid only as a quoted block-list item
#   key:
#     - "[[Target]]"
# Any other frontmatter line containing [[ is the Obsidian "invalid properties"
# footgun (inline value, or an unquoted list item YAML reads as a nested list).
section "frontmatter properties"
fp=0
for f in "${PAGES[@]}"; do
  bad="$(awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && index($0,"[[")>0 {
      if ($0 ~ /^[ \t]*-[ \t]+".*"[ \t]*$/) next   # ok: quoted block-list item
      printf "  %d: %s\n", NR, $0
    }
  ' "$f")"
  if [ -n "$bad" ]; then
    printf '%s\n' "$f"
    printf '%s\n' "$bad"
    fp=1; rc=1
  fi
done
[ "$fp" -eq 0 ] && echo "ok: no inline wikilink properties (use quoted block lists)"

# 3. soft-wrap drift ------------------------------------------------------------
section "soft-wrap"
if out="$("$SCRIPT_DIR/reflow.sh" --check "${PAGES[@]}")"; then
  echo "ok: no hard-wrap drift"
else
  printf '%s\n' "$out"; rc=1
fi

# 4. skills catalog drift -------------------------------------------------------
section "skills catalog"
"$SCRIPT_DIR/gen-skills-index.sh" --check --wiki "$WIKI" || rc=1

# 5. projects catalog drift -----------------------------------------------------
section "projects catalog"
"$SCRIPT_DIR/gen-projects-index.sh" --check --wiki "$WIKI" || rc=1

# content-node pages: the flat, non-raw node folders the engine defines as the
# vault's curated nodes. Root hubs (CLAUDE.md/index.md/log.md/README.md) and raw/
# captures are deliberately NOT nodes, so they're exempt from the node invariants.
NODE_DIRS=()
NODE_DIRS_FILE="$SCRIPT_DIR/../scaffold/node-dirs.txt"
if [ -f "$NODE_DIRS_FILE" ]; then
  while IFS= read -r d; do
    case "$d" in ''|'#'*|raw/*) continue;; esac
    NODE_DIRS+=("$d")
  done < "$NODE_DIRS_FILE"
fi

# read a page's frontmatter (between the first two --- fences) into a check.
# fm_has KEY FILE  → true if a frontmatter line matches ^[ \t]*KEY (KEY a regex-safe literal)
fm_has() {
  awk -v key="$1" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ ("^[ \t]*" key) { found=1; exit }
    END { exit !found }
  ' "$2"
}

# 6. boundary present on every content-node page --------------------------------
section "boundary present"
bp=0
for d in "${NODE_DIRS[@]}"; do
  for f in "$WIKI/$d"/*.md; do
    [ -f "$f" ] || continue
    if ! fm_has "boundary:" "$f"; then
      printf '  ✗ %s — no boundary: in frontmatter\n' "${f#$WIKI/}"; bp=1; rc=1
    fi
  done
done
[ "$bp" -eq 0 ] && echo "ok: every content-node page declares a boundary"

# 6b. boundary MATCHES the vault's own declaration ------------------------------
# Gate 6 asks whether the field exists; it never asked whether it is right. The gap was
# silent end to end: a page stamped with some other vault's boundary passes gate 6, is
# committed and indexed, and is then dropped from semantic recall by rag-build's
# cross-boundary skip — correct behaviour there, but the page simply stops answering
# and nothing says why. A write-time error turns that into an obvious failure, and it
# covers mis-stamps from ANY source, not just the skill templates that used to name a
# literal value.
section "boundary matches the vault"
vb="$("$SCRIPT_DIR/vault-boundary.sh" --wiki "$WIKI" 2>/dev/null || true)"
if [ -z "$vb" ]; then
  # Consistent with the foreign-boundary gate and with rag-build's filter: with nothing
  # to compare against, say so rather than pass silently — an unarmed gate and a clean
  # one are otherwise indistinguishable.
  echo "not armed: no parseable 'boundary:' declaration in $WIKI/CLAUDE.md"
else
  bm=0
  for d in "${NODE_DIRS[@]}"; do
    for f in "$WIKI/$d"/*.md; do
      [ -f "$f" ] || continue
      pb="$(awk 'NR==1&&$0!~/^---/{exit} NR>1&&/^---/{exit} /^boundary:/{sub(/^boundary:[[:space:]]*/,""); gsub(/[[:space:]"'"'"'`]/,""); print; exit}' "$f")"
      [ -n "$pb" ] || continue          # absent is gate 6's error, not this one's
      if [ "$pb" != "$vb" ]; then
        printf '  ✗ %s — boundary: %s, but this vault declares %s\n' "${f#$WIKI/}" "$pb" "$vb"
        printf '      A mis-stamped page is dropped from semantic recall with no message.\n'
        bm=1; rc=1
      fi
    done
  done
  [ "$bm" -eq 0 ] && echo "ok: every content-node page matches the vault's boundary ($vb)"
fi

# 7. provenance present on every repo page --------------------------------------
# A repos/ page is version-keyed: it must record a sources: block with ref: + sha:
# so freshness (recorded ref/sha vs live HEAD) is checkable.
section "provenance present"
pp=0
if [ -d "$WIKI/repos" ]; then
  for f in "$WIKI/repos"/*.md; do
    [ -f "$f" ] || continue
    miss=""
    fm_has "sources:" "$f" || miss="sources:"
    fm_has "ref:"     "$f" || miss="$miss ref:"
    fm_has "sha:"     "$f" || miss="$miss sha:"
    if [ -n "$miss" ]; then
      printf '  ✗ %s — missing provenance:%s\n' "${f#$WIKI/}" " $miss"; pp=1; rc=1
    fi
  done
fi
[ "$pp" -eq 0 ] && echo "ok: every repo page carries sources: ref/sha provenance"

# 7b. ref is a clean tag, not a git-describe string ------------------------------
# SCHEMA's convention is `ref: <latest release tag>`, and nothing enforced it — so
# ingest commonly wrote the full describe form vX.Y.Z-<N>-g<sha>, which can never
# equal a clean tag and therefore false-flagged the page for refresh forever.
#
# DELIBERATELY A NEGATIVE CHECK. Asserting a ref IS a clean tag is not something lint
# can do: tags are arbitrary strings (`stable`, `release-2024-01`), so the only real
# test is "does this tag exist in the clone?" — and that would make the write-time
# gate depend on every documented repo being cloned at a particular path on whatever
# machine is committing. A gate that cannot run everywhere gets loosened until it
# cannot fail. Rejecting the describe FORM needs no clone, cannot false-positive on a
# legitimate tag (nobody names one `v1.0.0-3-gabc1234`), and prevents exactly the
# regression this exists for.
section "repo ref is a clean tag"
rt=0
if [ -d "$WIKI/repos" ]; then
  for f in "$WIKI/repos"/*.md; do
    [ -f "$f" ] || continue
    r="$(awk '/^[[:space:]]*-?[[:space:]]*ref:/{sub(/^[^:]*:[[:space:]]*/,""); gsub(/[[:space:]"'"'"'`]/,""); print; exit}' "$f")"
    [ -n "$r" ] || continue
    if printf '%s' "$r" | grep -qE -- '-[0-9]+-g[0-9a-f]{7,}$'; then
      printf '  ✗ %s — ref: %s is a git-describe string, not a tag\n' "${f#$WIKI/}" "$r"
      printf '      Record the base tag (%s); the commit offset is already in sha:.\n' \
        "$(printf '%s' "$r" | sed -E 's/-[0-9]+-g[0-9a-f]{7,}$//')"
      rt=1; rc=1
    fi
  done
fi
[ "$rt" -eq 0 ] && echo "ok: no repo page records a git-describe ref"

# 8. summary volatility ---------------------------------------------------------
# A project page's summary: is the machine-read surface (the index buckets are
# generated from it) but lives in frontmatter, away from the Current state section
# SCHEMA marks "overwritten each session" — so a summary holding a decaying fact goes
# false with no edit to the page. Enforced via a content-hashed baseline rather than a
# warning: lint.sh is the pre-commit gate, and a warn on pre-existing offenders is
# standing noise on every commit forever.
section "summary volatility"
"$SCRIPT_DIR/lint-summary-volatility.sh" --wiki "$WIKI" || rc=1

# 9. link integrity -------------------------------------------------------------
section "link integrity"
"$SCRIPT_DIR/lint-links.sh" --wiki "$WIKI" $STRICT || rc=1

# 10. foreign boundary ----------------------------------------------------------
# The motivating case for the whole gates project: a personal-boundary vault should
# mechanically reject work-org identifiers, instead of relying on a human noticing
# during an import. Necessarily consumer-specific — only the vault knows which
# strings are foreign — so it reads them from the seam and is INACTIVE without one.
#
# The patterns file is expected to be git-ignored: naming the forbidden strings in a
# tracked file would write the other boundary's identifiers into this vault's
# permanent history, i.e. commit the very thing the gate exists to keep out. The
# cost is that a fresh clone starts unarmed, so an unarmed gate SAYS SO — a silent
# pass would be indistinguishable from a clean one.
#
# The patterns file is therefore read through resolve_seam_file: present in the tree
# being linted it wins, and when it is ABSENT-AND-GIT-IGNORED there — which is what
# every linked worktree looks like, and `pre-commit` lints the worktree while
# `vault-worktree.sh guard` refuses canonical commits — it is read from the canonical
# checkout, the only tree that can hold it. Without that, this gate said `not armed`
# on every commit an adopted vault makes, and vault CI could not backstop it either
# (a fresh clone has no copy of an ignored file). See bin/wiki-root-lib.sh.
section "foreign boundary"
GATES_CONF="$(resolve_seam_file "$WIKI" ".wiki-gates.conf")"
fb_file=""
if [ -n "$GATES_CONF" ] && [ -f "$GATES_CONF" ]; then
  fb_file="$(awk -F= '
    /^[ \t]*#/ { next }
    { key=$1; sub(/^[ \t]+/,"",key); sub(/[ \t]+$/,"",key)
      if (key != "foreign_boundary_patterns") next
      sub(/^[^=]*=/,""); val=$0; sub(/^[ \t]+/,"",val); sub(/[ \t]+$/,"",val)
      print val; exit }' "$GATES_CONF")"
fi
[ -n "$fb_file" ] || fb_file=".wiki-gates.local"
fb_path="$(resolve_seam_file "$WIKI" "$fb_file")"

if [ -z "$fb_path" ]; then
  echo "not armed: no $fb_file (declare foreign-boundary patterns there to enable)"
else
  fb=0
  pats="$(grep -v '^[ \t]*#' "$fb_path" | grep -v '^[ \t]*$' || true)"
  if [ -z "$pats" ]; then
    echo "not armed: $fb_file declares no patterns"
  else
    for d in "${NODE_DIRS[@]}"; do
      for f in "$WIKI/$d"/*.md; do
        [ -f "$f" ] || continue
        while IFS= read -r pat; do
          [ -n "$pat" ] || continue
          if hits="$(grep -inE "$pat" "$f" 2>/dev/null)"; then
            # print the line number and the matched pattern, never the matched text —
            # echoing it back would put the foreign string in CI logs.
            while IFS= read -r h; do
              printf '  ✗ %s:%s — matches foreign-boundary pattern /%s/\n' \
                "${f#$WIKI/}" "${h%%:*}" "$pat"
            done <<EOF
$hits
EOF
            fb=1; rc=1
          fi
        done <<EOF
$pats
EOF
      done
    done
    [ "$fb" -eq 0 ] && echo "ok: no foreign-boundary identifiers in content-node pages"
  fi
fi

echo
[ "$rc" -eq 0 ] && echo "lint: all checks passed" || echo "lint: FAILURES above"
exit $rc
