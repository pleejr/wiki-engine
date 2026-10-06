#!/usr/bin/env bash
# lint-memory.sh — validate a wiki's curated memory/ notes against the engine
# SCHEMA. Memory is kept current by supersession + this lint (see SCHEMA.md).
#
# Per $WIKI_PATH/memory/*.md it checks:
#   ERROR   — missing frontmatter, or missing title/type/boundary
#   ERROR   — type not one of: memory | lesson | decision | preference
#   ERROR   — fewer than 2 outbound [[wikilinks]] (SCHEMA: >=2 per page)
#   ERROR   — superseded_by: names a slug that is no page in this vault (v1.78.0). A
#             forwarding pointer to nothing is worse than none: it reads as a resolved
#             redirect. A slug declared in the external-refs file does not satisfy it
#             either — forwarding a reader to a page the vault does not contain is the
#             failure the field exists to prevent.
#   ERROR   — superseded_by: is a list. ONE slug: a note superseded by three has no
#             unambiguous forward target; a fan-out points at a hub page instead.
#   WARN    — missing updated:
#   WARN    — missing created: (v1.78.0) — `mine` reads it to decide whether
#             a procedure recurred, so a note without it is invisible to that pass
#   WARN    — status: superseded with no superseded_by: AND no successor the record can
#             identify (v1.78.0, refined v1.79.1). Before warning, the lint SEARCHES for a
#             candidate: a [[link]] on a line of the retired note that says it was
#             superseded / replaced / retracted / merged, or a line in another memory note
#             that says it supersedes / replaces this one. Exactly one distinct candidate
#             satisfies the check and is reported as INFERRED with the line to add; two
#             candidates, none, or one that resolves to no page still warn. Keyed on the
#             supersession wording, never on the first or any link — a related-reading
#             link must not become a forward pointer.
#   WARN    — superseded_by: present on a note whose status: is not superseded (v1.78.0)
#   WARN    — a [[link]] that resolves to no page in the vault (allowed as a stub,
#             flagged so you can see genuinely stale links)
#   WARN    — an active note not referenced anywhere in index.md (catalog drift)
#   (a note with status: superseded is exempt from the index-drift check)
#
# The memory-node status vocabulary is `current | superseded` (SCHEMA.md). The missing-
# successor case is a WARNING, not an error, on purpose: a vault arriving with N superseded
# notes and no successor fields would otherwise fail its pre-commit gate on N pages unrelated
# to the commit — a hand migration, and the always-red gate that teaches --no-verify. Under
# --strict it fails, which is how a vault that has filled its successors promotes it.
#
# Exit 1 if any ERROR (or any WARN under --strict); else 0.
#
# Usage:
#   lint-memory.sh                target $WIKI_PATH
#   lint-memory.sh --wiki DIR     target DIR
#   lint-memory.sh --strict       treat warnings as failures
set -euo pipefail

# The shared vault-walk exclusion (vault_pages / vault_grep_excludes). Sourced, never run;
# it sets no shell options. A missing lib is fatal: walking the vault WITHOUT the exclusion
# is the defect this closes, so failing loudly beats silently scanning session worktrees.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || { echo "error: missing wiki-root-lib.sh — broken engine checkout" >&2; exit 1; }

WIKI=""   # explicit --wiki only; the default is resolved below, not here
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

# Same verdict-about-the-wrong-tree defect as lint.sh: bound to $WIKI_PATH, a bare
# run from inside a session worktree answered confidently about canonical. Only
# tools whose target is TRACKED VAULT CONTENT resolve this way (wiki-root-lib.sh);
# this one's is, and an explicit --wiki is still never second-guessed.
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
MEMDIR="$WIKI/memory"
INDEX="$WIKI/index.md"
[ -d "$MEMDIR" ] || { echo "error: no memory dir at $MEMDIR" >&2; exit 1; }

# --- set of resolvable link targets: every page slug in the vault -------------
# (basename without .md, excluding a leftover 1.x engine/ checkout, git, obsidian, and .rag dirs)
SLUGS="$(vault_pages "$WIKI" | sed -e 's|.*/||' -e 's|\.md$||' | LC_ALL=C sort -u)"

# A here-string, not `printf … | grep -q`: under pipefail that shape reports failure when
# the match is found early on a long list (the writer takes EPIPE), so a page that exists
# reads as missing. See the same pair in bin/lint-links.sh.
has_slug() { grep -qxF -- "$1" <<<"$SLUGS"; }

# extract a single-line frontmatter value (between the first two --- fences)
fm_get() {
  awk -v k="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && $0 ~ "^" k ":" { sub(/^[^:]*:[ \t]*/,""); sub(/^"/,""); sub(/"$/,""); print; exit }
  ' "$1"
}

has_frontmatter() { [ "$(head -1 "$1")" = "---" ]; }

# successor_candidates FILE SLUG — the distinct slugs the record names as FILE's successor,
# one per line. Keyed on supersession WORDING on the same line as the link, in either
# direction, so a related-reading link never qualifies. `|| true` everywhere: no match is
# the ordinary answer, and pipefail must not turn it into an abort (see the loop below).
successor_candidates() {
  local file="$1" me="$2"
  {
    # the link that FOLLOWS the wording (within 40 characters), not every link on the line
    grep -oiE '(superseded|replaced|retracted|absorbed|folded|merged)( in favou?r of| into| by)?[^[]{0,40}\[\[[^]|#]+' "$file" 2>/dev/null \
      | sed -E 's/.*\[\[//' || true
    grep -liE "(supersedes|replaces|absorbs|folds in|retires)[^[]{0,40}\[\[${me}([]|#])" "$MEMDIR"/*.md 2>/dev/null \
      | sed -e 's|.*/||' -e 's|\.md$||' || true
  } | grep -vxF "$me" | LC_ALL=C sort -u || true
}

errors=0 warnings=0
err()  { errors=$((errors+1));   printf '  ✗ %s\n' "$1"; }
warn() { warnings=$((warnings+1)); printf '  ! %s\n' "$1"; }

shopt -s nullglob
notes=("$MEMDIR"/*.md)
[ ${#notes[@]} -gt 0 ] || { echo "no memory notes in $MEMDIR"; exit 0; }

# A TRUNCATED RUN MUST NOT READ AS A CLEAN ONE — the class, not just the instance above.
# Twice now a script in this family died mid-loop under `set -e` + `pipefail` while every
# printed line said success, and the exit status carried no news because a lint already
# exits 1 whenever it finds an error. The summary is the only statement of how many notes
# were checked, so its ABSENCE is the signal, and this says so on stderr.
checked=0
finished=0
on_exit() {
  local rc=$?
  [ "$finished" = "1" ] && return 0
  echo >&2
  echo "memory lint: ABORTED (rc=$rc) after $checked of ${#notes[@]} note(s) — no summary was" >&2
  echo "  printed, so THIS REPORT IS INCOMPLETE and the notes after '${last_note:-?}' went" >&2
  echo "  unchecked. This is an engine bug, not vault state: please report it." >&2
}
trap on_exit EXIT

# ONE awk pass over every note (and ONE over index.md) computes what the loop below used to
# fork for per note: eight frontmatter reads, a link extraction, a grep over the whole slug
# list per link, and a grep of index.md per note. Those two greps made cost grow with
# (notes x vault), so a vault three times larger linted about six times slower. The loop
# keeps every message, in the same order; it only reads the answers from here.
LM_TMP="$(mktemp -d)"
printf '%s\n' "$SLUGS" > "$LM_TMP/slugs"
printf '%s\0' "${notes[@]}" | xargs -0 awk -v slugs="$LM_TMP/slugs" -v index_file="$INDEX" \
    -v table="$LM_TMP/table" -v dead="$LM_TMP/dead" '
  function emit(   k, n, dl) {
    if (idx == 0) return
    n = 0; for (k in L) if (k != "") n++
    for (k in L) if (k != "" && k != self && !(k in S)) print idx "\t" k > dead
    # \037 (unit separator), not a tab: `read` collapses runs of whitespace separators, so
    # an empty field would shift every field after it.
    print idx US hasfm US V["title"] US V["type"] US V["boundary"] US V["updated"] US V["created"] US V["status"] US V["superseded_by"] US n US ((("[[" self "]]") in IX) ? 1 : 0) > table
  }
  BEGIN {
    US = "\037"
    while ((getline l < slugs) > 0) if (l != "") S[l] = 1
    # Every literal "[[X]]" in index.md: from EACH "[[" (overlapping starts included) to
    # the first "]]" after it. Equivalent to grep -F "[[slug]]" for a bracket-free slug.
    if (index_file != "") while ((getline l < index_file) > 0) {
      for (i = 1; i < length(l); i++) if (substr(l, i, 2) == "[[") {
        j = index(substr(l, i + 2), "]]"); if (j) IX[substr(l, i, j + 3)] = 1
      }
    }
  }
  FNR == 1 {
    emit(); idx++; delete L; delete V; infm = 0; fmdone = 0
    self = FILENAME; sub(/.*\//, "", self); sub(/\.md$/, "", self)
    hasfm = ($0 == "---") ? 1 : 0
    if (hasfm) { infm = 1; next }
  }
  infm && $0 == "---" { infm = 0; fmdone = 1 }
  infm {
    split("title type boundary updated created status superseded_by", K, " ")
    for (q = 1; q <= 7; q++) if (!(K[q] in V) && $0 ~ ("^" K[q] ":")) {
      v = $0; sub(/^[^:]*:[ \t]*/, "", v); sub(/^"/, "", v); sub(/"$/, "", v); V[K[q]] = v
    }
  }
  {
    line = $0
    while (match(line, /\[\[[^]]+\]\]/)) {
      lk = substr(line, RSTART + 2, RLENGTH - 4); sub(/[|#].*/, "", lk); L[lk] = 1
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END { emit() }
'
LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2 -u "$LM_TMP/dead" -o "$LM_TMP/dead" 2>/dev/null || : > "$LM_TMP/dead"
exec 3< "$LM_TMP/table" 4< "$LM_TMP/dead"
pend_idx=""; pend_lk=""
read_dead() { if IFS="$(printf '\t')" read -r pend_idx pend_lk <&4; then :; else pend_idx=""; fi; }
read_dead

for f in "${notes[@]}"; do
  IFS="$(printf '\037')" read -r t_idx t_hasfm t_title t_type t_boundary t_updated t_created t_status t_sby t_nlinks t_inindex <&3
  checked=$((checked+1))
  slug="${f##*/}"; slug="${slug%.md}"   # parameter expansion: no process per note
  last_note="$slug"
  printf '%s\n' "$slug"

  if [ "$t_hasfm" != "1" ]; then
    err "no YAML frontmatter"
    continue
  fi

  # required frontmatter
  [ -n "$t_title" ] || err "missing frontmatter: title"
  [ -n "$t_type" ] || err "missing frontmatter: type"
  [ -n "$t_boundary" ] || err "missing frontmatter: boundary"
  [ -n "$t_updated" ] || warn "missing frontmatter: updated"
  [ -n "$t_created" ] || warn "missing frontmatter: created (mine counts recurrence by it)"

  # valid type
  typ="$t_type"
  if [ -n "$typ" ]; then
    case " $TYPES " in *" $typ "*) ;; *) err "type '$typ' not in: $TYPES";; esac
  fi

  # outbound wikilinks (unique, alias/heading suffixes stripped)
  # `|| true` is load-bearing. A note with NO wikilinks is a valid state this script
  # already knows how to report — the next two lines count zero and raise the error —
  # but `grep` exits 1 on no match, `pipefail` carries that out of the pipeline, and
  # `set -e` then aborted the whole assignment. The loop stopped at the FIRST linkless
  # note, so every note sorting after it went unchecked and the summary line never
  # printed. Zero links is a finding here, not a refusal: do not turn this into one.
  nlinks="$t_nlinks"
  [ "$nlinks" -ge 2 ] || err "only $nlinks outbound [[wikilink]](s) (need >=2)"

  # dead-link warnings (self-links and empties ignored), computed in the pass above
  while [ "$pend_idx" = "$t_idx" ]; do
    warn "dead link [[$pend_lk]] (no such page — stub or stale)"
    read_dead
  done

  # lifecycle: status + superseded_by pairing (SCHEMA: memory status is current|superseded)
  status="$t_status"
  sby="$t_sby"
  sby="${sby#\[\[}"; sby="${sby%\]\]}"     # tolerate the wikilink spelling of one slug
  if [ "$status" = "superseded" ] && [ -z "$sby" ]; then
    # Search the record for the successor before warning. Two sources, both keyed on
    # supersession WORDING on the same line as the link, so ordinary related-reading links
    # never qualify: (1) the retired note's own body — "superseded by [[x]]"; (2) another
    # memory note's body — "supersedes [[this]]". Distinct candidates are unioned.
    cands="$(successor_candidates "$f" "$slug")"
    ncand="$(printf '%s' "$cands" | grep -c . || true)"
    if [ "$ncand" -eq 1 ]; then
      if has_slug "$cands"; then
        printf '  · superseded_by: inferred as [[%s]] from the supersession wording in the record — add `superseded_by: %s` to make it explicit\n' "$cands" "$cands"
      else
        warn "status: superseded without superseded_by:; the record names [[$cands]] as the successor but no such page exists"
      fi
    elif [ "$ncand" -gt 1 ]; then
      warn "status: superseded without superseded_by:; the record names $ncand candidates ($(printf '%s' "$cands" | tr '\n' ' ' | sed 's/ $//')) — name the one to forward to"
    else
      warn "status: superseded without superseded_by: — no successor identified in the record; a reader arriving from an old link is not forwarded"
    fi
  fi
  if [ -n "$sby" ]; then
    case "$sby" in
      *,*|*' '*|*'['*|*']'*) err "superseded_by: must name ONE slug (got '$sby'); a fan-out points at a hub page";;
      *) has_slug "$sby" || err "superseded_by: [[$sby]] is no page in this vault — a forwarding pointer to nothing reads as a resolved redirect";;
    esac
    [ "$status" = "superseded" ] || warn "superseded_by: present but status: is '${status:-<missing>}', not superseded"
  fi

  # index.md catalog drift (active notes only)
  if [ "$status" != "superseded" ] && [ -f "$INDEX" ]; then
    [ "$t_inindex" = "1" ] || warn "not referenced in index.md (catalog drift)"
  fi
done

finished=1
exec 3<&- 4<&-; rm -rf "$LM_TMP"
echo
echo "memory lint: ${#notes[@]} notes, $errors error(s), $warnings warning(s)"
if [ "$errors" -gt 0 ] || { [ "$STRICT" -eq 1 ] && [ "$warnings" -gt 0 ]; }; then
  exit 1
fi
exit 0
