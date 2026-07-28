#!/usr/bin/env bash
# lint-summary-volatility.sh — a project page's `summary:` must name IDENTITY, not STATE.
#
# WHY. `gen-projects-index.sh` renders the Projects buckets from `status:` + `summary:`, so
# `summary:` is the machine-read surface of a project page — but it lives in frontmatter,
# away from the body, and nothing ties it to `Current state`, which SCHEMA already marks
# "overwritten each session". Authors therefore fill it with current standing ("built, not
# deployed", "still on <old version>"), which becomes FALSE through the passage of time with
# no edit to the page at all. The generated index then advertises a state the page's own
# body contradicts — a false negative in the one artifact whose job is to summarize project
# state, so the reader who most needs the truth is the one most confidently misled. Every
# other gate passes, because every other gate is structurally sound.
#
# THIS IS A PROXY, NOT A DECISION PROCEDURE. "Describes identity, not state" is a human
# judgement; a word list cannot decide it. Recall is unbounded — "awaiting the lender's
# callback" decays exactly as hard and matches nothing. A clean run means "no listed
# marker", NEVER "these summaries are stable". The SCHEMA rule is what retires the class;
# this only catches the common shape, and says so in its own output.
#
# STATUS-GATED. A state claim on a `done` project is frozen — "<flag rename> (complete)" is
# true forever, and warning about it is pure false positive. The same claim on an
# active/paused/planned project is a live assertion that decays. An UNKNOWN or MISSING
# status flags rather than skips, so a typo'd status cannot silently exempt a page.
#
# ENFORCED, VIA A RATCHET — not advisory. `lint.sh` is the pre-commit gate and CI, so a
# warn-by-default gate with pre-existing offenders would print on every commit forever:
# standing noise is the failure this engine has fixed repeatedly, and it contradicts holding
# gates at zero. Instead, adoption seeds today's offenders into a BASELINE and the gate
# errors on anything new. A vault adopts green and silent; a new violation fails.
#
# THE BASELINE IS KEYED ON THE SUMMARY'S CONTENT HASH, not the page slug. A slug-keyed
# exemption outlives the text it excused — rewrite the summary into something genuinely
# decaying and the page stays exempt forever. Hashing the summary means an edit drops the
# exemption automatically, so the baseline can only shrink without a deliberate re-seed.
#
# Deterministic: no network, no model. Exit 1 on any finding; 0 otherwise.
#
# Usage:
#   lint-summary-volatility.sh [--wiki DIR] [--seed-baseline] [--quiet]
#     --seed-baseline   rewrite the baseline to grandfather ALL current findings (adoption)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
SEED=0
QUIET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --seed-baseline) SEED=1; shift;;
    --quiet) QUIET=1; shift;;
    -h|--help) sed -n '1,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

# --- the vault seam (optional; absent = engine defaults) -----------------------
# Parsed, never sourced: a config file that can execute code is a config file that
# can own the machine running the gate. Same shape as lint-links.sh.
GATES_CONF="$WIKI/.wiki-gates.conf"
conf_get() {
  [ -f "$GATES_CONF" ] || return 0
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

# Marker list: vault override wins, else the engine default. Kept as DATA so a vault can
# tune which words are volatile without waiting for an engine release — that is a property
# of how a vault writes, not of the engine.
MARK_FILE="$(conf_get summary_volatility_markers)"
if [ -n "$MARK_FILE" ] && [ -f "$WIKI/$MARK_FILE" ]; then
  MARKERS_PATH="$WIKI/$MARK_FILE"
else
  MARKERS_PATH="$SCRIPT_DIR/../scaffold/summary-volatility-markers.txt"
fi
# ENGINE ASSET — a missing marker file must not silently pass every page. Fail loudly:
# a gate that cannot load its rules has not checked anything.
if [ ! -f "$MARKERS_PATH" ]; then
  echo "  ✗ marker list not found at $MARKERS_PATH — the gate cannot run" >&2
  exit 1
fi

MARKERS="$(grep -v '^[ \t]*#' "$MARKERS_PATH" | grep -v '^[ \t]*$' || true)"
[ -n "$MARKERS" ] || { echo "  ✗ marker list $MARKERS_PATH is empty — the gate cannot run" >&2; exit 1; }

BASE_FILE="$(conf_get summary_baseline)"
[ -n "$BASE_FILE" ] || BASE_FILE=".wiki-gates-summary-baseline"
BASELINE="$WIKI/$BASE_FILE"

sha_of() {
  # portable: shasum on macOS, sha256sum on Linux
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else printf '%s' "$1" | sha256sum | awk '{print $1}'; fi
}

get_field() {
  awk -v key="$2" '
    NR==1 && $0=="---" { fm=1; next }
    fm && $0=="---" { exit }
    fm {
      if (index($0, key ":") == 1) { sub(/^[^:]*:[ \t]*/,""); gsub(/^"|"$/,""); print; exit }
    }' "$1" 2>/dev/null
}

PROJ_DIR="$WIKI/projects"
if [ ! -d "$PROJ_DIR" ]; then
  [ "$QUIET" = 1 ] || echo "ok: no projects/ directory — nothing to check"
  exit 0
fi

declare -a HITS=()
checked=0
skipped_done=0

for f in "$PROJ_DIR"/*.md; do
  [ -e "$f" ] || continue
  slug="$(basename "$f" .md)"
  summary="$(get_field "$f" summary)"
  status="$(get_field "$f" status)"
  [ -n "$summary" ] || continue
  checked=$((checked+1))

  # A terminal project's claim is frozen; anything else is a live assertion. Unknown or
  # missing status falls through to CHECKED on purpose — fail closed, so `status: activo`
  # cannot buy an exemption.
  if [ "$status" = "done" ]; then skipped_done=$((skipped_done+1)); continue; fi

  matched=""
  while IFS= read -r re; do
    [ -n "$re" ] || continue
    if printf '%s' "$summary" | grep -qiE "$re"; then matched="$re"; break; fi
  done <<<"$MARKERS"
  [ -n "$matched" ] || continue

  h="$(sha_of "$summary")"
  if [ "$SEED" = 0 ] && [ -f "$BASELINE" ] && grep -qF "$slug	$h" "$BASELINE" 2>/dev/null; then
    continue   # grandfathered, and only for THIS exact summary text
  fi
  HITS+=("$slug	$h	$matched	$status")
done

if [ "$SEED" = 1 ]; then
  {
    echo "# .wiki-gates-summary-baseline — grandfathered project summaries."
    echo "# Seeded by lint-summary-volatility.sh --seed-baseline. One <slug>\\t<sha256(summary)>"
    echo "# per line. The hash is the point: rewriting a summary drops its exemption"
    echo "# automatically, so this file can only shrink without a deliberate re-seed."
    echo "# Each line is a summary that names STATE and should be rewritten to name IDENTITY."
    for h in "${HITS[@]:-}"; do
      [ -n "$h" ] || continue
      printf '%s\t%s\n' "$(printf '%s' "$h" | cut -f1)" "$(printf '%s' "$h" | cut -f2)"
    done
  } > "$BASELINE"
  n=${#HITS[@]}
  echo "summary-volatility: seeded baseline with $n grandfathered summar$([ "$n" = 1 ] && echo y || echo ies) -> $BASE_FILE"
  exit 0
fi

if [ "${#HITS[@]}" -eq 0 ]; then
  [ "$QUIET" = 1 ] || echo "ok: $checked project summar$([ "$checked" = 1 ] && echo y || echo ies) checked ($skipped_done done/frozen, skipped); no volatility markers"
  [ "$QUIET" = 1 ] || echo "    (a proxy for the SCHEMA rule — no finding is not evidence a summary is stable)"
  exit 0
fi

for h in "${HITS[@]}"; do
  slug="$(printf '%s' "$h" | cut -f1)"
  hash="$(printf '%s' "$h" | cut -f2)"
  re="$(printf '%s' "$h" | cut -f3)"
  st="$(printf '%s' "$h" | cut -f4)"
  echo "  ✗ projects/$slug.md (status: ${st:-<missing>}) — summary matches volatility marker /$re/" >&2
  echo "      summary: names current STATE; SCHEMA wants IDENTITY (what the project IS)." >&2
  echo "      Move the standing to status: and the body's Current state, or grandfather it:" >&2
  echo "        printf '%s\\t%s\\n' '$slug' '$hash' >> $BASE_FILE" >&2
done
echo "summary-volatility: ${#HITS[@]} finding(s)" >&2
exit 1
