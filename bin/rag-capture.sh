#!/usr/bin/env bash
# rag-capture.sh — deterministic session auto-capture (the memory design's "axis 1").
#
# Appends a session entry to $WIKI/raw/sessions/YYYY-MM.md so the next session has a
# durable anchor of what you worked on. Wire it to a Claude Code SessionEnd hook to
# make capture automatic; the rich curation (raw -> memory/) stays in-session via the
# review-and-promote step in `wiki-context`.
#
# ┌─ HARD SAFETY ────────────────────────────────────────────────────────────────┐
# │ DETERMINISTIC & HOOK-SAFE: this runs git and writes a file. It MUST NEVER      │
# │ invoke `claude`, spawn an agent, or recurse. That is the .ai-os fork bomb —    │
# │ that hook ran `claude -p` and spawned ~13.7k sessions. Never add one here.     │
# │ See [[lesson-no-claude-in-hooks]].                                             │
# └───────────────────────────────────────────────────────────────────────────────┘
#
# Records ONLY metadata: timestamp, repo/branch/HEAD, changed file NAMES, recent
# commit SUBJECTS, and an optional --note. NEVER file contents or diffs (secret +
# boundary safety). Disable pieces with RAG_CAPTURE_COMMITS=0 / RAG_CAPTURE_FILES=0.
# Note: it captures the repo you were in; point WIKI_PATH at the boundary-appropriate
# vault and don't enable the hook where even filenames/commit subjects are sensitive.
#
# Usage:
#   rag-capture.sh                         capture cwd's git state to $WIKI_PATH
#   rag-capture.sh --wiki DIR --repo DIR   explicit targets
#   rag-capture.sh --note "text"           add an explicit note line
#   <hook-json> | rag-capture.sh           reads {"cwd":...} from a SessionEnd hook
set -euo pipefail

WIKI="${WIKI_PATH:-}"
REPO=""
NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --note) NOTE="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

# SessionEnd hooks pass JSON on stdin; pull cwd from it if --repo wasn't given.
if [ -z "$REPO" ] && [ ! -t 0 ] && command -v python3 >/dev/null 2>&1; then
  REPO="$(python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("cwd",""))
except Exception: pass' 2>/dev/null || true)"
fi

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$REPO" ] || REPO="$PWD"

BOUND="$(grep -m1 'boundary:' "$WIKI/CLAUDE.md" 2>/dev/null | sed -E 's/.*boundary:[[:space:]]*//; s/[^a-z].*//')"
[ -n "$BOUND" ] || BOUND="personal"

SESS_DIR="$WIKI/raw/sessions"
mkdir -p "$SESS_DIR"
FILE="$SESS_DIR/$(date +%Y-%m).md"
TS="$(date +%Y-%m-%dT%H:%M:%S%z)"

if [ ! -f "$FILE" ]; then
  printf -- '---\ntype: raw\nboundary: %s\n---\n\n# Session capture — %s\n\nAuto-captured session metadata (disposable). Promote keepers to `memory/`, then prune. Never contains file contents or secrets.\n' \
    "$BOUND" "$(date +%Y-%m)" > "$FILE"
fi

# Build a fenced block (reflow-safe: fences are left intact) of pure metadata.
suffix=""
body=""
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)"
  name="$(basename "$top")"
  branch="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  head="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
  suffix=" — $name@$branch ($head)"
  body="repo: $name  branch: $branch  head: $head"
  if [ "${RAG_CAPTURE_FILES:-1}" = "1" ]; then
    changed="$(git -C "$REPO" status --porcelain 2>/dev/null | sed 's/^/  /')"
    [ -n "$changed" ] && body="$body
changes:
$changed"
  fi
  if [ "${RAG_CAPTURE_COMMITS:-1}" = "1" ]; then
    commits="$(git -C "$REPO" log -5 --pretty='  %h %s' 2>/dev/null)"
    [ -n "$commits" ] && body="$body
recent commits:
$commits"
  fi
else
  suffix=" — $REPO (no git)"
  body="dir: $REPO (not a git repo)"
fi

{
  printf '\n## %s%s\n\n' "$TS" "$suffix"
  printf '```\n%s\n```\n' "$body"
  [ -n "$NOTE" ] && printf '\nNote: %s\n' "$NOTE"
} >> "$FILE"

echo "rag-capture: appended session entry to raw/sessions/$(basename "$FILE")"
