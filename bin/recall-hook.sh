#!/usr/bin/env bash
# recall-hook.sh — the plugin's UserPromptSubmit hook: semantic recall on every prompt.
#
# Recall was built, indexed and correct, and almost never ran: its only trigger was the
# `wiki-context` skill, which sessions rarely invoke. Over 30 days, two machines logged
# 2 recall calls across ~600 transcripts. This hook makes the lens automatic: it embeds
# the user's prompt, and when one vault page stands clear of the rest it hands the model up
# to RAG_RECALL_N `file:line` pointers as additionalContext. Pointers, never page text —
# the model still decides what to open, and the map and links stay authoritative.
#
# Quiet by design. It prints nothing when: WIKI_PATH is unset or has no `.rag` index; the
# prompt is a slash command or shorter than RAG_RECALL_MIN_WORDS (a "yes" or "continue"
# has no topic to recall); or no page stands RAG_RECALL_MIN_GAP above the rest (see
# recall.sh: a prompt unrelated to the vault should cost nothing). RAG_RECALL_MIN_SCORE
# adds an absolute floor, unset by default. RAG_RECALL_HOOK=0 switches it off.
#
# Deterministic: runs a CPU embedder, NEVER `claude` — no re-entry path (hard rule, see
# CLAUDE.md). Always exits 0, so a slow or broken index can never block a prompt; its own
# RAG_RECALL_DEADLINE (at most 6s) bounds the recall step, leaving the hooks.json timeout
# room for the stdin read and the short Python steps around it. Each run appends one line
# (time, ok|deadline|error|interrupted, seconds, deadline) to <vault>/.rag/recall-hook.log.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

[ "${RAG_RECALL_HOOK:-1}" = "0" ] && exit 0
[ -n "$WIKI" ] && [ -f "$WIKI/.rag/index.jsonl" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Bounded stdin read, same reasoning as rag-capture.sh: an open pipe nobody closes must
# fall through to "no payload", not hang the prompt.
payload=""
if [ ! -t 0 ]; then
  IFS= read -r -d '' -t "${RAG_RECALL_STDIN_TIMEOUT:-2}" payload || true
fi
[ -n "$payload" ] || exit 0

prompt="$(printf '%s' "$payload" | python3 -I -c '
import sys, json, os
try: p = json.load(sys.stdin).get("prompt") or ""
except Exception: p = ""
p = p.strip()
if p.startswith("/") or len(p.split()) < int(os.environ.get("RAG_RECALL_MIN_WORDS", "4")):
    p = ""
print(p[:1000])' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0

set -- --min-gap "${RAG_RECALL_MIN_GAP:-0.04}"
[ -n "${RAG_RECALL_MIN_SCORE:-}" ] && set -- "$@" --min-score "$RAG_RECALL_MIN_SCORE"

# The hook ends a slow recall itself, inside RAG_RECALL_DEADLINE seconds, and adds nothing.
# Left to the harness timeout in hooks/hooks.json, the same run is killed with a visible
# "timed out ... output discarded" error on the prompt. recall.sh execs its embedder, so the
# kill reaches the process doing the work, and it stays in the hook's process group, so a
# signal the harness sends to that group reaches it too. The deadline can only be lowered:
# a value that is not a number in (0, RECALL_DEADLINE_MAX] uses the maximum, because a
# longer one hands the run back to the harness timeout. CI asserts stdin timeout + maximum
# + 1s stays below the hooks.json timeout.
RECALL_DEADLINE_MAX=6
hits="$(RAG_RECALL_LOG="$WIKI/.rag/recall-hook.log" python3 -I -c '
import os, subprocess, sys, time
top = float(sys.argv[2])
try: deadline = float(sys.argv[1])
except ValueError: deadline = top
if not 0 < deadline <= top: deadline = top
t0 = time.time()
p = subprocess.Popen(sys.argv[3:], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                     stderr=subprocess.DEVNULL)
def log(outcome):
    # One line per run, so how often recall misses its deadline is a reading, not a guess.
    # Kept under ~256K by dropping the older half; failure to log never fails the hook.
    try:
        path = os.environ["RAG_RECALL_LOG"]
        if os.path.exists(path) and os.path.getsize(path) > 262144:
            lines = open(path).readlines(); open(path, "w").writelines(lines[len(lines) // 2:])
        with open(path, "a") as f:
            f.write("%s %s %.2f %g\n" % (time.strftime("%Y-%m-%dT%H:%M:%S%z"), outcome,
                                         time.time() - t0, deadline))
    except Exception: pass
try:
    out, _ = p.communicate(timeout=deadline)
except BaseException as e:
    p.kill(); p.wait()
    log("deadline" if isinstance(e, subprocess.TimeoutExpired) else "interrupted")
    sys.exit(124)
log("ok" if p.returncode == 0 else "error")
sys.stdout.buffer.write(out)
sys.exit(p.returncode)' "${RAG_RECALL_DEADLINE:-}" "$RECALL_DEADLINE_MAX" \
  "$SCRIPT_DIR/recall.sh" --wiki "$WIKI" --json -n "${RAG_RECALL_N:-5}" "$@" \
  "$prompt" 2>/dev/null)" || exit 0

printf '%s' "$hits" | RAG_WIKI="$WIKI" python3 -I -c '
import sys, json, os
try: hits = json.load(sys.stdin)
except Exception: hits = []
if not hits: sys.exit(0)
w = os.environ["RAG_WIKI"]
lines = ["Vault recall — pages in %s whose meaning matches this prompt (pointers, not facts; "
         "open one only if it bears on the task):" % w]
for h in hits:
    lines.append("- %s:%d — %s (%.2f)" % (h["file"], h["line"], h["heading"][:100], h["score"]))
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                         "additionalContext": "\n".join(lines)}}))' 2>/dev/null
exit 0
