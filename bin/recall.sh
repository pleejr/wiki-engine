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
# One hit per PAGE (its best-scoring chunk): the result is a list of pages to open, and
# two chunks of one page spent two of five slots on one answer. The hub pages `index.md`
# and `log.md` are left out by default — both mention nearly every note, so they took
# about a fifth of the top-5 slots while pointing only at the page that should have been
# returned instead (RAG_HUB_FILES overrides the list; --include-hubs keeps them).
#
# Usage:
#   recall.sh "why is the gpu node hot"     top matches (human-readable)
#   recall.sh -n 8 "query"                  return N matches (default 5)
#   recall.sh --json "query"                machine-readable (for consult)
#   recall.sh --wiki DIR "query"            target DIR
#   recall.sh --min-score 0.6 "query"       drop matches scoring below 0.6
#   recall.sh --min-gap 0.04 "query"        return nothing unless the best page stands out
#   recall.sh --include-hubs "query"        also return index.md / log.md
#   echo "query" | recall.sh                read query from stdin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
TOPN=5
JSON=0
MINSCORE=""
MINGAP=""
HUBS=1
QUERY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -n)     TOPN="$2"; shift 2;;
    --json) JSON=1; shift;;
    --min-score) MINSCORE="$2"; shift 2;;
    --min-gap) MINGAP="$2"; shift 2;;
    --include-hubs) HUBS=0; shift;;
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

export RAG_WIKI="$WIKI" RAG_BINDIR="$SCRIPT_DIR" RAG_QUERY="$QUERY" RAG_TOPN="$TOPN" RAG_JSON="$JSON" \
  RAG_MINSCORE="$MINSCORE" RAG_MINGAP="$MINGAP" RAG_EXCLUDE_HUBS="$HUBS"

"$PYBIN" - <<'PY'
import os, sys, json, math
sys.path.insert(0, os.environ["RAG_BINDIR"])
from rag_embed import Embedder

WIKI = os.environ["RAG_WIKI"]
Q    = os.environ["RAG_QUERY"]
TOPN = int(os.environ["RAG_TOPN"])
JSON = os.environ["RAG_JSON"] == "1"
INDEX = os.path.join(WIKI, ".rag", "index.jsonl")

# Curated notes rank above the auto-captured raw/ pile: raw chunks get a
# multiplicative penalty (RAG_RAW_WEIGHT, default 0.80) so a curated hit wins ties.
RAW_W = float(os.environ.get("RAG_RAW_WEIGHT", "0.80"))
MINSCORE = float(os.environ["RAG_MINSCORE"]) if os.environ.get("RAG_MINSCORE") else None
MINGAP = float(os.environ["RAG_MINGAP"]) if os.environ.get("RAG_MINGAP") else None
HUBS = set(os.environ.get("RAG_HUB_FILES", "index.md log.md").split()) \
    if os.environ.get("RAG_EXCLUDE_HUBS") == "1" else set()

qv = Embedder(WIKI).embed_query(Q)
recs = []
for line in open(INDEX, encoding="utf-8"):
    try:
        rec = json.loads(line)
    except Exception:
        continue
    if rec["file"] in HUBS:
        continue
    recs.append(rec)

try:   # numpy ships with every local backend; the pure-python path serves endpoint-only vaults
    import numpy as np
    sims = []
    if recs:
        M = np.asarray([r["vector"] for r in recs], dtype=np.float32)
        q = np.asarray(qv, dtype=np.float32)
        n = np.linalg.norm(M, axis=1) * (np.linalg.norm(q) or 1.0)
        sims = (M @ q / np.where(n == 0, 1.0, n)).tolist()
except ImportError:
    def cosine(a, b):
        dot = sum(x*y for x, y in zip(a, b))
        na = math.sqrt(sum(x*x for x in a)); nb = math.sqrt(sum(y*y for y in b))
        return dot / (na*nb) if na and nb else 0.0
    sims = [cosine(qv, r["vector"]) for r in recs]

best = {}
for s, rec in zip(sims, recs):
    if rec["file"] == "raw" or rec["file"].startswith("raw/"):
        s *= RAW_W
    if rec["file"] not in best or s > best[rec["file"]][0]:
        best[rec["file"]] = (s, rec)
scored = sorted(best.values(), key=lambda t: t[0], reverse=True)
# The gap gate: how far the best page stands above the mean of the top 20. Absolute
# cosine is a poor "is this about the vault at all?" test — bge scores crowd into a
# narrow band, and on this engine's own vault a 0.62 floor dropped 10 of 34 on-topic
# queries while still firing on 4 of 18 off-topic ones. A prompt that matches something
# lifts one page clear of the pack; one that matches nothing lifts them all a little.
# At 0.04 the same sets gave 32/34 kept, 7/18 fired.
if MINGAP is not None and scored:
    head = [t[0] for t in scored[:20]]
    if scored[0][0] - sum(head) / len(head) < MINGAP:
        scored = []
if MINSCORE is not None:
    scored = [t for t in scored if t[0] >= MINSCORE]
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
