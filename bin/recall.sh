#!/usr/bin/env bash
# recall.sh — semantic recall over a vault's markdown.
#
# Embeds a query and returns the nearest chunks from the .rag index built by
# rag-build.sh, as `file:line` pointers back into the real (curated) pages. It never
# replaces the markdown — it just finds which pages to open. `wiki-context` calls this
# automatically so you can start prompting without naming pages.
#
# Config (same env as rag-build.sh):
#   RAG_EMBED_URL / RAG_EMBED_MODEL / RAG_EMBED_API / RAG_API_KEY
#
# Usage:
#   recall.sh "why is the gpu node hot"     top matches (human-readable)
#   recall.sh -n 8 "query"                  return N matches (default 5)
#   recall.sh --json "query"                machine-readable (for wiki-context)
#   recall.sh --wiki DIR "query"            target DIR
#   echo "query" | recall.sh                read query from stdin
set -euo pipefail

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
[ -n "$QUERY" ] || QUERY="$(cat)"           # fall back to stdin
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
[ -n "$QUERY" ] || { echo "error: empty query" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 required" >&2; exit 1; }

INDEX="$WIKI/.rag/index.jsonl"
[ -f "$INDEX" ] || { echo "error: no index at $INDEX — run rag-build.sh first" >&2; exit 1; }

export RAG_WIKI="$WIKI" RAG_QUERY="$QUERY" RAG_TOPN="$TOPN" RAG_JSON="$JSON"
export RAG_EMBED_URL="${RAG_EMBED_URL:-http://localhost:11434/api/embeddings}"
export RAG_EMBED_MODEL="${RAG_EMBED_MODEL:-nomic-embed-text}"
export RAG_EMBED_API="${RAG_EMBED_API:-ollama}"
export RAG_API_KEY="${RAG_API_KEY:-}"

python3 - <<'PY'
import os, sys, json, math, urllib.request, urllib.error

WIKI = os.environ["RAG_WIKI"]
Q     = os.environ["RAG_QUERY"]
TOPN  = int(os.environ["RAG_TOPN"])
JSON  = os.environ["RAG_JSON"] == "1"
URL   = os.environ["RAG_EMBED_URL"]; MODEL = os.environ["RAG_EMBED_MODEL"]
API   = os.environ["RAG_EMBED_API"]; KEY   = os.environ["RAG_API_KEY"]
INDEX = os.path.join(WIKI, ".rag", "index.jsonl")

def embed(text):
    body = {"model": MODEL, "input": text} if API == "openai" else {"model": MODEL, "prompt": text}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    if KEY: req.add_header("Authorization", "Bearer " + KEY)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
    except urllib.error.URLError as e:
        sys.exit("error: embedding endpoint %s unreachable (%s)" % (URL, e))
    return data["data"][0]["embedding"] if API == "openai" else data["embedding"]

def cosine(a, b):
    dot = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a)); nb = math.sqrt(sum(y*y for y in b))
    return dot / (na*nb) if na and nb else 0.0

qv = embed(Q)
scored = []
for line in open(INDEX, encoding="utf-8"):
    try: rec = json.loads(line)
    except Exception: continue
    scored.append((cosine(qv, rec["vector"]), rec))
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
