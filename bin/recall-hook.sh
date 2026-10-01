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
# CLAUDE.md). Always exits 0, so a slow or broken index can never block a prompt; the
# hook's own timeout in hooks/hooks.json bounds the latency.
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

prompt="$(printf '%s' "$payload" | python3 -c '
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
hits="$("$SCRIPT_DIR/recall.sh" --wiki "$WIKI" --json -n "${RAG_RECALL_N:-5}" "$@" \
  "$prompt" 2>/dev/null)" || exit 0

printf '%s' "$hits" | RAG_WIKI="$WIKI" python3 -c '
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
