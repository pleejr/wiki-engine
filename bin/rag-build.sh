#!/usr/bin/env bash
# rag-build.sh — build a semantic-recall index over a vault's markdown.
#
# A derived, git-ignored sidecar at $WIKI/.rag/index.jsonl: one record per heading
# chunk with its embedding vector, so `recall.sh` can find pages by *meaning* (not
# just words/links). The markdown stays the source of truth — this index is fully
# rebuildable (rm -rf .rag && rag-build.sh). Additive & optional; a vault without an
# embedding endpoint simply never runs it.
#
# Embeddings come from a LOCAL endpoint (default Ollama) — no cloud, no secrets:
#   RAG_EMBED_URL    default http://localhost:11434/api/embeddings
#   RAG_EMBED_MODEL  default nomic-embed-text
#   RAG_EMBED_API    ollama | openai   (request/response shape; default ollama)
#   RAG_API_KEY      optional bearer token (openai-compatible endpoints)
#
# Deterministic & hook-safe in the fork-bomb sense: it calls an embedding model,
# never `claude`, and never spawns recursively. See [[lesson-no-claude-in-hooks]].
#
# Usage:
#   rag-build.sh                 build/refresh against $WIKI_PATH
#   rag-build.sh --wiki DIR      target DIR
#   rag-build.sh --force         re-embed every file (ignore unchanged-file reuse)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki)  WIKI="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 required" >&2; exit 1; }

export RAG_WIKI="$WIKI"
export RAG_FORCE="$FORCE"
export RAG_EMBED_URL="${RAG_EMBED_URL:-http://localhost:11434/api/embeddings}"
export RAG_EMBED_MODEL="${RAG_EMBED_MODEL:-nomic-embed-text}"
export RAG_EMBED_API="${RAG_EMBED_API:-ollama}"
export RAG_API_KEY="${RAG_API_KEY:-}"

python3 - <<'PY'
import os, sys, json, glob, hashlib, urllib.request, urllib.error

WIKI = os.environ["RAG_WIKI"]
FORCE = os.environ["RAG_FORCE"] == "1"
URL   = os.environ["RAG_EMBED_URL"]
MODEL = os.environ["RAG_EMBED_MODEL"]
API   = os.environ["RAG_EMBED_API"]
KEY   = os.environ["RAG_API_KEY"]
RAGDIR = os.path.join(WIKI, ".rag")
INDEX  = os.path.join(RAGDIR, "index.jsonl")
SKIP_DIRS = {".git", "engine", ".obsidian", ".rag"}

def vault_boundary():
    p = os.path.join(WIKI, "CLAUDE.md")
    if not os.path.isfile(p): return None
    for line in open(p, encoding="utf-8", errors="replace"):
        # matches `boundary: personal` or "- `boundary: personal`."
        if "boundary:" in line:
            after = line.split("boundary:", 1)[1].strip().strip("`.*_ ")
            tok = after.split()[0].strip("`.,") if after.split() else ""
            if tok in ("personal", "work"): return tok
    return None
VBOUND = vault_boundary()

def embed(text):
    text = text[:6000]
    if API == "openai":
        body = {"model": MODEL, "input": text}
    else:
        body = {"model": MODEL, "prompt": text}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    if KEY: req.add_header("Authorization", "Bearer " + KEY)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.load(r)
    except urllib.error.URLError as e:
        sys.exit("error: embedding endpoint %s unreachable (%s).\n"
                 "  Start a local model, e.g.  ollama pull %s && ollama serve\n"
                 "  or point RAG_EMBED_URL/RAG_EMBED_MODEL/RAG_EMBED_API elsewhere."
                 % (URL, e, MODEL))
    if API == "openai":
        return data["data"][0]["embedding"]
    return data["embedding"]

def parse(path):
    """Return (sha, boundary, list-of-chunks). Chunk = (heading, start_line, text)."""
    raw = open(path, encoding="utf-8", errors="replace").read()
    sha = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    lines = raw.splitlines()
    i, boundary, title = 0, None, None
    if lines and lines[0].strip() == "---":       # frontmatter
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            s = lines[i].strip()
            if s.startswith("boundary:"):
                boundary = s.split(":", 1)[1].strip()
            i += 1
        i += 1                                     # past closing ---
    body_start = i
    # split body into ## sections; text before the first ## is the intro chunk
    chunks, cur, cur_head, cur_line = [], [], None, body_start + 1
    def flush():
        txt = "\n".join(cur).strip()
        if txt:
            head = cur_head or (title or os.path.basename(path))
            chunks.append((head, cur_line, txt))
    for n in range(body_start, len(lines)):
        ln = lines[n]
        if title is None and ln.startswith("# "):
            title = ln[2:].strip()
        if ln.startswith("## "):
            flush()
            cur, cur_head, cur_line = [ln], ln[3:].strip(), n + 1
        else:
            cur.append(ln)
    flush()
    return sha, boundary, chunks

# reuse vectors for files whose sha is unchanged
old = {}
if os.path.isfile(INDEX) and not FORCE:
    for line in open(INDEX, encoding="utf-8"):
        try: rec = json.loads(line)
        except Exception: continue
        old.setdefault(rec["file"], {"sha": rec.get("sha"), "recs": []})["recs"].append(rec)

files = []
for p in glob.glob(os.path.join(WIKI, "**", "*.md"), recursive=True):
    rel = os.path.relpath(p, WIKI)
    if any(part in SKIP_DIRS for part in rel.split(os.sep)): continue
    files.append((rel, p))
files.sort()

records, embedded, reused, skipped = [], 0, 0, 0
for rel, p in files:
    sha, boundary, chunks = parse(p)
    if VBOUND and boundary and boundary != VBOUND:
        skipped += 1
        print("  skip (boundary %s != %s): %s" % (boundary, VBOUND, rel))
        continue
    if rel in old and old[rel]["sha"] == sha:
        records.extend(old[rel]["recs"]); reused += len(old[rel]["recs"]); continue
    for head, line, text in chunks:
        vec = embed(text)
        records.append({"file": rel, "line": line, "heading": head,
                        "sha": sha, "text": text[:600], "vector": vec})
        embedded += 1

os.makedirs(RAGDIR, exist_ok=True)
tmp = INDEX + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    for r in records:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
os.replace(tmp, INDEX)
print("rag-build: %d files, %d chunks (%d embedded, %d reused%s) -> %s"
      % (len(files) - skipped, len(records), embedded, reused,
         (", %d skipped" % skipped) if skipped else "", os.path.relpath(INDEX, WIKI)))
PY
