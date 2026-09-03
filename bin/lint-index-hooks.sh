#!/usr/bin/env bash
# lint-index-hooks.sh — an index.md hook is ONE CLAUSE stating the rule or the fact; dates,
# counts and correction history belong in the note it points at.
#
# WHY. `index.md` is loaded on every turn of every session, so a hook's cost is paid by every
# reader forever, while it is written once by a session that has the note's evidence in hand.
# Inlining a date, an occurrence count or a "second instance" narrative is the locally natural
# thing to do, and no single instance looks wrong — the failure is silent and cumulative.
# Measured on one vault: 567 hooks, mean 32 words, 361 over 25, 31 carrying a date, the longest
# 164 words. The rule was written in that vault's own always-loaded file and broken anyway,
# which is the evidence that it needs a gate rather than a reminder.
#
# WARN-FIRST, --strict TO PROMOTE. The engine cannot know how much backlog a vault carries, and
# a gate that is red on arrival is the always-red-check-gets-bypassed failure this engine has
# fixed more than once. A vault that has drained its backlog promotes it with --strict, or via
# `lint.sh --strict`. The lint reports and stops — it never rewrites a hook, because a hook is
# prose and a clause that exists only in the hook is a fact a truncation would lose.
#
# POPULATION. Hook lines are `- [[slug]] — text` outside the generated Projects / Skills
# blocks (their fix is at the frontmatter, and `gen-*-index.sh --check` already guard them).
# The words counted are the TEXT after the link, not the link itself. Only index.md is read:
# a date inside the NOTE is where dates belong, so the note is never opened.
#
# Deterministic; no network, no model.
#
# Usage:
#   lint-index-hooks.sh [--wiki DIR] [--strict]
#   INDEX_HOOK_WARN_WORDS=N   words per hook before a warning (default 25)
# Exit 0 unless --strict and there is at least one finding.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
WIKI=""; STRICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
WIKI="$(resolve_wiki_root "$WIKI")" || exit 1
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
INDEX="$WIKI/index.md"
[ -f "$INDEX" ] || { echo "ok: no index.md — nothing to check"; exit 0; }

WARN_WORDS="${INDEX_HOOK_WARN_WORDS:-25}"
case "$WARN_WORDS" in ''|*[!0-9]*) echo "error: INDEX_HOOK_WARN_WORDS must be a number (got '$WARN_WORDS')" >&2; exit 1;; esac

# One awk pass. Findings go to stdout as they are found; the three counts come last on one
# line so the caller can parse them. A generated block is skipped by its sentinels.
out="$(awk -v W="$WARN_WORDS" '
  /<!-- [a-z]+:start -->/ { gen=1; next }
  /<!-- [a-z]+:end -->/   { gen=0; next }
  gen { next }
  /^- \[\[[^]]+\]\]/ {
    hooks++
    slug=$0; sub(/^- \[\[/,"",slug); sub(/\]\].*$/,"",slug)
    text=$0; sub(/^- \[\[[^]]+\]\][ \t]*([—–:-][ \t]*)?/,"",text)
    n=split(text, a, /[ \t]+/); if (text=="") n=0
    if (n > W) { over++; printf "  ! index.md:%d — hook is %d words (budget %d): [[%s]]\n", NR, n, W, slug }
    if (text ~ /20[0-9][0-9]-[0-9][0-9]/) { dated++; printf "  ! index.md:%d — hook inlines a date; dates belong in the note: [[%s]]\n", NR, slug }
  }
  END { printf "index hooks: %d hook line(s), %d over %d words, %d dated\n", hooks+0, over+0, W, dated+0 }
' "$INDEX")"
printf '%s\n' "$out"
findings="$(printf '%s\n' "$out" | grep -c '^  ! ' || true)"
if [ "$STRICT" = 1 ] && [ "$findings" -gt 0 ]; then
  echo "index hooks: $findings finding(s) — failing under --strict" >&2
  exit 1
fi
exit 0
