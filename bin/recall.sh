#!/usr/bin/env bash
# recall.sh — semantic recall over a vault's markdown.
#
# Embeds a query and returns the nearest chunks from the .rag index built by
# rag-build.sh, as `file:line` pointers back into the real (curated) pages. It never
# replaces the markdown — it just finds which pages to open. `wiki-context` calls this
# automatically so you can start prompting without naming pages.
#
# Uses the vault's own .rag/venv CPU embedder (rag_embed.py resolves backend/model).
#
# Usage:
#   recall.sh "why is the gpu node hot"     top matches (human-readable)
#   recall.sh -n 8 "query"                  return N matches (default 5)
#   recall.sh --json "query"                machine-readable (for wiki-context)
#   recall.sh --wiki DIR "query"            target DIR
#   echo "query" | recall.sh                read query from stdin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
TOPN=5
JSON=0
QUERY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -n)     TOPN="$2"; shift 2;;
    --json) JSON=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) QUERY="${QUERY:+$QUERY }$1"; shift;;
  esac
done
[ -n "$QUERY" ] || QUERY="$(cat)"
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$QUERY" ] || { echo "error: empty query" >&2; exit 1; }

INDEX="$WIKI/.rag/index.jsonl"
[ -f "$INDEX" ] || { echo "error: no index at $INDEX — run rag-build.sh first" >&2; exit 1; }

PYBIN="$WIKI/.rag/venv/bin/python"
if [ -x "$PYBIN" ]; then
  export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1   # model cached by rag-setup — stay offline + quiet
else
  PYBIN="$(command -v python3 || true)"
fi
[ -n "$PYBIN" ] || { echo "error: python3 required" >&2; exit 1; }

export RAG_WIKI="$WIKI" RAG_BINDIR="$SCRIPT_DIR" RAG_QUERY="$QUERY" RAG_TOPN="$TOPN" RAG_JSON="$JSON"

"$PYBIN" - <<'PY'
import os, sys, json, math
sys.path.insert(0, os.environ["RAG_BINDIR"])
from rag_embed import Embedder

WIKI = os.environ["RAG_WIKI"]
Q    = os.environ["RAG_QUERY"]
TOPN = int(os.environ["RAG_TOPN"])
JSON = os.environ["RAG_JSON"] == "1"
INDEX = os.path.join(WIKI, ".rag", "index.jsonl")

def cosine(a, b):
    dot = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a)); nb = math.sqrt(sum(y*y for y in b))
    return dot / (na*nb) if na and nb else 0.0

# Curated notes rank above the auto-captured raw/ pile: raw chunks get a
# multiplicative penalty (RAG_RAW_WEIGHT, default 0.80) so a curated hit wins ties.
RAW_W = float(os.environ.get("RAG_RAW_WEIGHT", "0.80"))

qv = Embedder(WIKI).embed([Q])[0]
scored = []
for line in open(INDEX, encoding="utf-8"):
    try:
        rec = json.loads(line)
    except Exception:
        continue
    s = cosine(qv, rec["vector"])
    if rec["file"] == "raw" or rec["file"].startswith("raw/"):
        s *= RAW_W
    scored.append((s, rec))
scored.sort(key=lambda t: t[0], reverse=True)
top = scored[:TOPN]

if JSON:
    out = [{"score": round(s, 4), "file": r["file"], "line": r["line"],
            "heading": r["heading"], "snippet": r["text"][:200]} for s, r in top]
    print(json.dumps(out, ensure_ascii=False))
else:
    if not top:
        print("(no matches — is the index built?)"); sys.exit(0)
    for s, r in top:
        snippet = " ".join(r["text"].split())[:80]
        print("  %.2f  %s:%d   %s — %s" % (s, r["file"], r["line"], r["heading"], snippet))
PY
