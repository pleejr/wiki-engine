#!/usr/bin/env bash
# rag-build.sh — build a semantic-recall index over a vault's markdown.
#
# A derived, git-ignored sidecar at $WIKI/.rag/index.jsonl: one record per heading
# chunk with its embedding vector, so `recall.sh` can find pages by *meaning* (not
# just words/links). The markdown stays the source of truth — this index is fully
# rebuildable (rm -rf .rag/index.jsonl && rag-build.sh). Additive & optional.
#
# Embeddings run in-process on a CPU model from the vault's own .rag/venv (provisioned
# by rag-setup.sh) — no server, no GPU, nothing external. Backend/model resolve via
# rag_embed.py (.rag/config.json or RAG_EMBED_* env). Calls a small embedding model,
# never `claude`, never recursive — see [[lesson-no-claude-in-hooks]]. In-session only.
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

# prefer the vault's provisioned venv; fall back to system python (endpoint backends)
PYBIN="$WIKI/.rag/venv/bin/python"
if [ -x "$PYBIN" ]; then
  export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1   # model cached by rag-setup — stay offline + quiet
else
  PYBIN="$(command -v python3 || true)"
fi
[ -n "$PYBIN" ] || { echo "error: python3 required" >&2; exit 1; }

export RAG_WIKI="$WIKI" RAG_BINDIR="$SCRIPT_DIR" RAG_FORCE="$FORCE"

"$PYBIN" - <<'PY'
import os, sys, json, glob, hashlib
sys.path.insert(0, os.environ["RAG_BINDIR"])
from rag_embed import Embedder

WIKI  = os.environ["RAG_WIKI"]
FORCE = os.environ["RAG_FORCE"] == "1"
RAGDIR = os.path.join(WIKI, ".rag")
INDEX  = os.path.join(RAGDIR, "index.jsonl")
SKIP_DIRS = {".git", "engine", ".obsidian", ".rag"}

def vault_boundary():
    p = os.path.join(WIKI, "CLAUDE.md")
    if not os.path.isfile(p):
        return None
    for line in open(p, encoding="utf-8", errors="replace"):
        if "boundary:" in line:
            after = line.split("boundary:", 1)[1].strip().strip("`.*_ ")
            tok = after.split()[0].strip("`.,") if after.split() else ""
            if tok in ("personal", "work"):
                return tok
    return None
VBOUND = vault_boundary()

def parse(path):
    """Return (sha, boundary, [(heading, start_line, text), ...])."""
    raw = open(path, encoding="utf-8", errors="replace").read()
    sha = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    lines = raw.splitlines()
    i, boundary, title = 0, None, None
    if lines and lines[0].strip() == "---":
        i = 1
        while i < len(lines) and lines[i].strip() != "---":
            s = lines[i].strip()
            if s.startswith("boundary:"):
                boundary = s.split(":", 1)[1].strip()
            i += 1
        i += 1
    body_start = i
    chunks, cur, cur_head, cur_line = [], [], None, body_start + 1
    def flush():
        txt = "\n".join(cur).strip()
        if txt:
            chunks.append((cur_head or (title or os.path.basename(path)), cur_line, txt))
    for n in range(body_start, len(lines)):
        ln = lines[n]
        if title is None and ln.startswith("# "):
            title = ln[2:].strip()
        if ln.startswith("## "):
            flush(); cur, cur_head, cur_line = [ln], ln[3:].strip(), n + 1
        else:
            cur.append(ln)
    flush()
    return sha, boundary, chunks

# reuse vectors for unchanged files
old = {}
if os.path.isfile(INDEX) and not FORCE:
    for line in open(INDEX, encoding="utf-8"):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        old.setdefault(rec["file"], {"sha": rec.get("sha"), "recs": []})["recs"].append(rec)

files = []
for p in glob.glob(os.path.join(WIKI, "**", "*.md"), recursive=True):
    rel = os.path.relpath(p, WIKI)
    if any(part in SKIP_DIRS for part in rel.split(os.sep)):
        continue
    files.append((rel, p))
files.sort()

emb = None  # lazily built only if something needs embedding
records, embedded, reused, skipped = [], 0, 0, 0
for rel, p in files:
    sha, boundary, chunks = parse(p)
    if VBOUND and boundary and boundary != VBOUND:
        skipped += 1
        print("  skip (boundary %s != %s): %s" % (boundary, VBOUND, rel))
        continue
    if rel in old and old[rel]["sha"] == sha:
        records.extend(old[rel]["recs"]); reused += len(old[rel]["recs"]); continue
    if not chunks:
        continue
    if emb is None:
        emb = Embedder(WIKI)
    vecs = emb.embed([c[2] for c in chunks])
    for (head, line, text), vec in zip(chunks, vecs):
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
