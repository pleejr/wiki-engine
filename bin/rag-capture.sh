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
#
# Chat/transcript CONTENT is never captured. Opt in to recording the transcript
# PATH (a pointer only, so review-and-promote can open it in-session to distill)
# with RAG_CAPTURE_TRANSCRIPT_PATH=1; the path comes from the hook JSON or --transcript.
#
# Two modes, auto-selected:
#   - cwd IS a git repo        -> capture that one repo.
#   - cwd is a WORKSPACE ROOT  -> scan immediate child dirs and capture each repo with
#     (parent of many repos)      activity inside the window (RAG_CAPTURE_SINCE hours,
#                                 default 12): a commit, a working-tree change made in
#                                 the window, or a fetch/checkout. Every clause is
#                                 time-bounded on purpose — "the tree is dirty" is a
#                                 state a repo can sit in indefinitely, so it selected
#                                 repos nobody had opened, on every run, forever.
#                                 What it CANNOT see: work that only reads (`git log`,
#                                 `git diff`, browsing files) writes nothing, so a
#                                 read-only session in a clean repo with old commits is
#                                 still missed. Pass --note, or capture from inside the
#                                 repo, when that session is the one worth keeping.
# Note: it captures the repo(s) you were in; point WIKI_PATH at the boundary-appropriate
# vault and don't enable the hook where even filenames/commit subjects are sensitive —
# especially at a parent that mixes personal + work repos.
#
# WIKI_PATH must be a VAULT, not merely a directory that exists. The boundary stamped on
# each capture file is read from the vault's own CLAUDE.md (bin/vault-boundary.sh) and is
# never defaulted, so a target with no readable `boundary:` declaration is refused by name
# rather than captured under a guess. Refusing is deliberate: a mis-stamped page is dropped
# from recall silently by rag-build's cross-boundary filter, which is worse than no page.
#
# Usage:
#   rag-capture.sh                         capture cwd's git state to $WIKI_PATH
#   rag-capture.sh --wiki DIR --repo DIR   explicit targets
#   rag-capture.sh --note "text"           add an explicit note line
#   <hook-json> | rag-capture.sh           reads {"cwd":...} from a SessionEnd hook
#
# The stdin read is bounded (RAG_CAPTURE_STDIN_TIMEOUT, default 2 seconds), so a caller
# whose stdin is an open pipe nobody closes gets the no-payload path instead of a hang.
set -euo pipefail

WIKI="${WIKI_PATH:-}"
REPO=""
NOTE=""
TRANSCRIPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --note) NOTE="$2"; shift 2;;
    --transcript) TRANSCRIPT="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

# SessionEnd hooks pass JSON on stdin. Read it once, pull cwd (repo) and
# transcript_path. We record only the transcript PATH (a pointer), never content,
# and only when RAG_CAPTURE_TRANSCRIPT_PATH=1.
#
# THE READ IS BOUNDED, and that is the whole point of doing it in the shell rather than
# handing the descriptor straight to python. `[ -t 0 ]` alone is NOT enough: the case
# that hangs is an OPEN PIPE with no writer that ever closes it — a supervisor, a cron
# wrapper, a surrounding script that pipes something unrelated into a block containing
# this call — and a pipe fails the tty test exactly as a genuine hook payload does. An
# unbounded read there never returns: no output, no exit status, nothing written, and a
# hook that hangs holds up whatever waits on it. That is worse than either succeeding or
# failing, because there is no status to attribute the stall to. CI cannot see it either
# — a runner hands each step an stdin that reaches EOF, so the environment the tests run
# in is the one environment where the bug cannot appear.
#
# A timeout is therefore treated as "no payload", falling through to the --repo/$PWD path
# that already exists for the no-stdin case. Truncated JSON lands in the same place: the
# parse fails, `d={}`, and the fallback applies — the behaviour when a hook sends nothing.
if [ ! -t 0 ] && command -v python3 >/dev/null 2>&1; then
  hook_json=""
  IFS= read -r -d '' -t "${RAG_CAPTURE_STDIN_TIMEOUT:-2}" hook_json || true
  if [ -n "$hook_json" ]; then
    hook_vals="$(printf '%s' "$hook_json" | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: d={}
print(d.get("cwd",""))
print(d.get("transcript_path",""))' 2>/dev/null || true)"
    [ -z "$REPO" ] && REPO="$(printf '%s\n' "$hook_vals" | sed -n 1p)"
    [ -z "$TRANSCRIPT" ] && TRANSCRIPT="$(printf '%s\n' "$hook_vals" | sed -n 2p)"
  fi
fi

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$REPO" ] || REPO="$PWD"

# The vault's boundary stamps every capture file, so it is ASKED of the vault
# (vault-boundary.sh — the engine names no value) and never guessed. A directory that
# exists but declares none is not a vault, and is refused here exactly as a missing one
# is one line above: the likely misconfiguration is a hook carrying an absolute
# WIKI_PATH that now points at a moved, renamed or stale copy, and a hook's exit status
# is read by nobody, so a quiet refusal is indistinguishable from a quiet session.
# `|| true` is load-bearing: vault-boundary exits 1 when there is no declaration, and
# under `set -e` + `pipefail` that aborted the assignment with no output on EITHER
# stream — the defect this refusal replaces. Do not restore a default: stamping a
# guessed boundary is worse than refusing, because rag-build's cross-boundary filter
# drops a mis-stamped page from recall silently.
VB="$(dirname "${BASH_SOURCE[0]}")/vault-boundary.sh"
[ -x "$VB" ] || { echo "error: missing $VB — broken engine checkout" >&2; exit 1; }
BOUND="$("$VB" --wiki "$WIKI" 2>/dev/null || true)"
[ -n "$BOUND" ] || {
  echo "error: no readable 'boundary:' declaration in $WIKI/CLAUDE.md — not a vault" >&2
  echo "       rag-capture stamps each capture file with the vault's own boundary and will not guess one." >&2
  echo "       Point \$WIKI_PATH at a vault, or restore the declaration in that file." >&2
  exit 1
}

SESS_DIR="$WIKI/raw/sessions"
mkdir -p "$SESS_DIR"
FILE="$SESS_DIR/$(date +%Y-%m).md"
TS="$(date +%Y-%m-%dT%H:%M:%S%z)"

if [ ! -f "$FILE" ]; then
  printf -- '---\ntype: raw\nboundary: %s\n---\n\n# Session capture — %s\n\nAuto-captured session metadata (disposable). Promote keepers to `memory/`, then prune. Never contains file contents or secrets.\n' \
    "$BOUND" "$(date +%Y-%m)" > "$FILE"
fi

# emit_repo DIR — print one reflow-safe "## <ts> — repo@branch (head)" entry with a
# fenced metadata block (repo/branch/head, changed file names, recent commit subjects).
# repo_body DIR — the block body only, with no timestamp in it. Split out so the
# repeat test compares WHAT WAS OBSERVED rather than when it was written.
repo_body() {
  local d="$1" name branch head body changed commits
  name="$(basename "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d")")"
  branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  head="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')"
  body="repo: $name  branch: $branch  head: $head"
  if [ "${RAG_CAPTURE_FILES:-1}" = "1" ]; then
    changed="$(git -C "$d" status --porcelain 2>/dev/null | sed 's/^/  /')"
    [ -n "$changed" ] && body="$body
changes:
$changed"
  fi
  if [ "${RAG_CAPTURE_COMMITS:-1}" = "1" ]; then
    commits="$(git -C "$d" log -5 --pretty='  %h %s' 2>/dev/null)"
    [ -n "$commits" ] && body="$body
recent commits:
$commits"
  fi
  printf '%s' "$body"
}

emit_repo() {
  local d="$1" name branch head body
  name="$(basename "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d")")"
  branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  head="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')"
  body="$(repo_body "$d")"
  printf '\n## %s — %s@%s (%s)\n\n```\n%s\n```\n' "$TS" "$name" "$branch" "$head" "$body"
}

# --- THE BUFFER IS FILED PER SESSION; THE WINDOW IS A FLAT LOOKBACK --------------------
# Those two units do not divide the day the same way. The window runs RAG_CAPTURE_SINCE
# hours back from the moment of capture, and the hook fires at the END OF EVERY SESSION,
# so two sessions ending inside one window both look back over the whole of it and both
# write the same repo. Three consecutive captures over two repos produced six identical
# blocks and three distinct facts: the buffer grew as (sessions x repos in window) rather
# than as work done. Every block was true; the ATTRIBUTION was not — a block filed under a
# session's timestamp read as a record of that session while describing a previous one's
# work, into a buffer that feeds distillation and is indexed for recall.
#
# WHAT WAS NOT DONE, and why: the reporter's first shape — make the window "since the
# previous capture" — was declined on the wrinkle they themselves named. That boundary is
# GLOBAL while the unit is per-session, and this engine ships peer sessions on purpose, so
# whichever session ended first would claim the interval and a long session ending later
# would report a window shorter than its own life. That trades over-reporting for
# under-reporting, and the engine has already made this call once, in the dirt-window
# fallback: over-capture is noise, under-capture loses the session the user just had.
#
# So the window keeps its meaning and the REPEAT is what stops: a repo block whose body is
# byte-identical to the newest one already recorded for that repo is not appended again.
# The session still gets its evidence — the repo is named on an `unchanged since` line —
# which is the objection the reporter raised against this shape, and it costs one line
# instead of a duplicated block. Self-describing on purpose: the line carries the repo,
# branch and sha, so it still reads correctly after the block it refers to has been pruned.
#
# Degrades safely under concurrency. Two sessions ending together may both read the buffer
# before either writes, and the worst case is the duplicate block that used to be the only
# case — never a lost block.
previous_body() {   # previous_body NAME — body of the newest recorded block for NAME
  [ -f "$FILE" ] || return 0
  awk -v name="$1" '
    $0 ~ "^## .* — " name "@" { inblk=1; body=""; fence=0; next }
    inblk && /^```/ { fence++; if (fence==2) { last=body; inblk=0 }; next }
    inblk && fence==1 { body = body $0 "\n" }
    END { printf "%s", last }
  ' "$FILE" 2>/dev/null
  return 0
}

previous_stamp() {  # previous_stamp NAME — timestamp of that newest recorded block
  [ -f "$FILE" ] || return 0
  awk -v name="$1" '$0 ~ "^## .* — " name "@" { split($0, a, " — "); ts=$2 } END { printf "%s", ts }' "$FILE" 2>/dev/null
  return 0
}

# ── the touch test — every clause must be bounded by the window ────────────────
# WINDOW_REF: a file whose mtime is the START of the window, so working-tree dirt can be
# age-tested with `find -newer` (portable — stat(1)'s mtime flag is not). Empty means this
# platform's date(1) does neither arithmetic form; the age test is then skipped and any
# dirt counts, i.e. the old behaviour. That fallback direction is deliberate: over-capture
# is noise, under-capture loses the session the user just had.
WINDOW_REF=""
WINDOW_TRIED=""
window_ref() {
  if [ -z "$WINDOW_TRIED" ]; then
    WINDOW_TRIED=1
    local h="${RAG_CAPTURE_SINCE:-12}" stamp f
    stamp="$(date -v-"${h}"H +%Y%m%d%H%M 2>/dev/null || date -d "$h hours ago" +%Y%m%d%H%M 2>/dev/null || true)"
    if [ -n "$stamp" ]; then
      f="${TMPDIR:-/tmp}/rag-capture-window.$$"
      if touch -t "$stamp" "$f" 2>/dev/null; then
        WINDOW_REF="$f"; trap 'rm -f "$WINDOW_REF"' EXIT
      fi
    fi
  fi
  [ -n "$WINDOW_REF" ]
}

# recent PATH [find-opts] — 0 if anything at PATH was modified inside the window. A
# directory is judged by its newest entry, so an untracked DIR is aged by its contents.
recent() { [ -n "$(find "$@" -newer "$WINDOW_REF" -print -quit 2>/dev/null)" ]; }

# dirt_recent DIR — 0 if the working tree holds a change made inside the window.
# The mere EXISTENCE of dirt is not a session signal: an untracked directory some tool
# creates and nobody commits leaves the repo dirty indefinitely, so it selected that repo
# on every run from then on — the same block forever, and unbounded in time rather than
# incidental. Age the dirt rather than ignoring untracked dirt wholesale: a brand-new
# project's first session is all untracked and has no commit to be selected by instead.
dirt_recent() {
  local d="$1" rec p
  # streamed, not captured: a NUL-separated list cannot survive a shell variable
  while IFS= read -r -d '' rec; do
    p="${rec:3}"                       # -z records are "XY <path>", unquoted
    [ -n "$p" ] || continue
    window_ref || return 0             # dirt exists and cannot be aged -> it counts
    if [ -e "$d/$p" ]; then
      if recent "$d/$p"; then return 0; fi
    # a deleted path has nothing to stat, but removing it bumped its parent directory
    elif recent "$(dirname "$d/$p")" -maxdepth 0; then
      return 0
    fi
  done < <(git -C "$d" status --porcelain -z 2>/dev/null)
  return 1
}

# access_recent DIR — 0 if the repo shows a git operation from inside the window that
# leaves the tree clean and adds no commit: a fetch (FETCH_HEAD) or a HEAD reflog entry
# (checkout/switch/reset/pull). Without this, a session spent reading a repo — fetch, read
# the diff, review — captured nothing at all when its tree was clean and its commits old.
# Measured, not assumed: `log`, `show`, `diff`, `status` and `cat-file` write NEITHER file,
# so purely-read work stays invisible; SCHEMA.md says so rather than implying otherwise.
# The index is deliberately NOT used, though `git diff`-shaped work refreshes it: this
# script runs `status --porcelain` on every child repo, which rewrites a stale index —
# so the first capture would stamp every repo in the workspace as just-accessed.
#
# THIS CLAUSE MEANS ACCESS — *the operator was here* — while the commit clause above means
# CHANGE. Keep them apart: requiring the fetch to have brought something back would read as
# the stricter test and would delete the case this exists for, since reviewing an
# already-current repo produces a no-op fetch. The consequence lives on the WRITER side: a
# tool that fetches on the operator's behalf must not leave this footprint, and
# `upkeep.sh sync-clones` restores the timestamps it disturbs for exactly that reason. A
# consumer's own `fetch --all` is indistinguishable from access and is documented, not
# guessed at.
access_recent() {
  local d="$1" gd f
  window_ref || return 1
  gd="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null || true)"
  [ -n "$gd" ] || return 1
  for f in FETCH_HEAD logs/HEAD; do
    if [ -e "$gd/$f" ] && recent "$gd/$f"; then return 0; fi
  done
  return 1
}

# touched DIR — 0 if the repo saw work inside the window (RAG_CAPTURE_SINCE hours,
# default 12): a commit, a change to the working tree, or a fetch/checkout.
touched() {
  [ -n "$(git -C "$1" log -1 --since="${RAG_CAPTURE_SINCE:-12} hours ago" --pretty=%h 2>/dev/null)" ] && return 0
  dirt_recent "$1" && return 0
  access_recent "$1" && return 0
  return 1
}

# append_repo DIR — emit the block, or record an `unchanged since` line when this repo's
# observed state is byte-identical to the newest block already recorded for it.
unchanged_lines=""
append_repo() {
  local d="$1" name branch head prev now stamp
  name="$(basename "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || echo "$d")")"
  now="$(repo_body "$d")"
  prev="$(previous_body "$name")"
  # both sides come through command substitution, which strips trailing newlines from
  # each — so compare them as-is; adding one back to either side never matches
  if [ -n "$prev" ] && [ "$prev" = "$now" ]; then
    branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    head="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')"
    stamp="$(previous_stamp "$name")"
    unchanged_lines="$unchanged_lines  $name@$branch ($head) — unchanged since ${stamp:-the previous capture}
"
    return 1
  fi
  entries="$entries$(emit_repo "$d")"
  return 0
}

entries=""
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  # cwd is inside a git repo — capture just it
  append_repo "$REPO" || true
else
  # workspace root (parent of several repos) — capture each TOUCHED child repo
  found=0
  for d in "$REPO"/*/; do
    [ -d "${d}.git" ] || continue
    if touched "$d"; then append_repo "$d" || true; found=$((found + 1)); fi
  done
  if [ "$found" -eq 0 ]; then
    # A read-only session lands here too — nothing it did is visible in repo state — so
    # the message names the criteria rather than asserting no repo was worked in.
    entries="$(printf '\n## %s — workspace: %s (no repo activity found)\n\n```\ndir: %s\nno child repo was changed, committed to, fetched or checked out in the last %s h\n(work that only READ a repo leaves no trace this scan can see)\n```\n' \
      "$TS" "$(basename "$REPO")" "$REPO" "${RAG_CAPTURE_SINCE:-12}")"
  fi
fi

{
  [ -n "$entries" ] && printf '%s\n' "$entries"
  # The session is still evidenced even when every repo it touched was already recorded:
  # naming them costs one line and keeps "a session happened here" true, which is what the
  # duplicated blocks were carrying by accident.
  if [ -n "$unchanged_lines" ]; then
    printf '\n## %s — no new repo state\n\n```\n%s```\n' "$TS" "$unchanged_lines"
  fi
  [ -n "$NOTE" ] && printf '\nNote (%s): %s\n' "$TS" "$NOTE"
  # Opt-in transcript POINTER (path only, never content). review-and-promote may open
  # it in-session to distill — applying the boundary/secret gate; never bulk-copy it.
  if [ "${RAG_CAPTURE_TRANSCRIPT_PATH:-0}" = "1" ] && [ -n "$TRANSCRIPT" ]; then
    printf '\nTranscript (%s): %s\n' "$TS" "$TRANSCRIPT"
  fi
} >> "$FILE"

echo "rag-capture: appended session entry to raw/sessions/$(basename "$FILE")"
