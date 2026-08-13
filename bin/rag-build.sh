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
import os, sys, json, glob, re
sys.path.insert(0, os.environ["RAG_BINDIR"])
from rag_embed import Embedder, MAX_CHARS
from rag_chunk import parse_file, CHUNKER_VERSION

WIKI  = os.environ["RAG_WIKI"]
FORCE = os.environ["RAG_FORCE"] == "1"
RAGDIR = os.path.join(WIKI, ".rag")
INDEX  = os.path.join(RAGDIR, "index.jsonl")
# SKIP THE CLASS, NOT A LIST. `engine` is the submodule; everything else worth skipping is
# a dot-directory the vault keeps untracked — `.git`, `.obsidian`, `.rag`, and the one that
# proved the point, `.worktrees/`, which holds a full checkout of every page. An enumerated
# list missed that (fixed in v1.54.3 by adding the name); the class rule cannot miss the
# next one, and it makes deliberate what was previously accidental — glob() already skips
# dot-prefixed entries, an immunity that would have ended the day the directory was renamed
# without its dot. The shell walkers keep their explicit VAULT_SCAN_SKIP_DIRS, since `find`
# has no such default; lint-docs.sh asserts THIS rule rather than list-equality with it.
SKIP_NAMES = {"engine"}

def current_model():
    m = os.environ.get("RAG_LOCAL_MODEL") or os.environ.get("RAG_EMBED_MODEL")
    if m:
        return m
    cfgp = os.path.join(RAGDIR, "config.json")
    if os.path.isfile(cfgp):
        try:
            return json.load(open(cfgp, encoding="utf-8")).get("model")
        except Exception:
            pass
    return "BAAI/bge-base-en-v1.5"   # keep in sync with rag_embed.DEFAULT_MODEL
CURMODEL = current_model()

def vault_boundary():
    """The vault's own boundary, read from its CLAUDE.md — used below to skip pages
    declaring a *different* one, so cross-boundary content that leaked in never gets
    indexed into recall.

    Accepts any well-formed token rather than a fixed pair. Matching against a
    hardcoded ("personal", "work") made the check fail *open*: a vault on any other
    boundary fell through to None, which switches the skip off entirely — so the one
    automated cross-boundary guard was disabled on exactly the vaults that had
    adopted a new boundary. A declaration we cannot parse is reported and skipped
    over rather than silently accepted; genuinely absent metadata still yields None
    (filter off), because there is nothing to compare against.
    """
    p = os.path.join(WIKI, "CLAUDE.md")
    if not os.path.isfile(p):
        return None
    for line in open(p, encoding="utf-8", errors="replace"):
        if "boundary:" in line:
            after = line.split("boundary:", 1)[1].strip().strip("`.*_ ")
            tok = after.split()[0].strip("`.,") if after.split() else ""
            if re.match(r"^[a-z][a-z0-9-]*$", tok):
                return tok
            # not a boundary token (prose mentioning "boundary:") — keep looking
            sys.stderr.write("rag-build: ignoring unparseable boundary %r in CLAUDE.md\n" % tok)
    return None
VBOUND = vault_boundary()

# reuse vectors for unchanged files. The chunker version participates: a page whose
# text never changes is still re-chunked when the split itself changes shape, or the
# fix ships inert on every existing vault.
old = {}
if os.path.isfile(INDEX) and not FORCE:
    for line in open(INDEX, encoding="utf-8"):
        try:
            rec = json.loads(line)
        except Exception:
            continue
        old.setdefault(rec["file"], {"sha": rec.get("sha"), "model": rec.get("model"),
                                     "cv": rec.get("cv"), "recs": []})["recs"].append(rec)

files = []
for p in glob.glob(os.path.join(WIKI, "**", "*.md"), recursive=True):
    rel = os.path.relpath(p, WIKI)
    if any(part in SKIP_NAMES or part.startswith(".") for part in rel.split(os.sep)):
        continue
    files.append((rel, p))
files.sort()

emb = None  # lazily built only if something needs embedding
records, embedded, reused, skipped = [], 0, 0, 0
for rel, p in files:
    sha, boundary, chunks = parse_file(p)
    if VBOUND and boundary and boundary != VBOUND:
        skipped += 1
        print("  skip (boundary %s != %s): %s" % (boundary, VBOUND, rel))
        continue
    if (rel in old and old[rel]["sha"] == sha and old[rel]["model"] == CURMODEL
            and old[rel]["cv"] == CHUNKER_VERSION):
        records.extend(old[rel]["recs"]); reused += len(old[rel]["recs"]); continue
    if not chunks:
        continue
    if emb is None:
        emb = Embedder(WIKI)
    vecs = emb.embed([c[2] for c in chunks])
    for (head, line, text), vec in zip(chunks, vecs):
        # `chars` is what was actually embedded; `text` is only a display preview.
        # Recording it makes "was this chunk complete?" greppable instead of a
        # property nobody can see.
        records.append({"file": rel, "line": line, "heading": head,
                        "sha": sha, "model": CURMODEL, "cv": CHUNKER_VERSION,
                        "chars": len(text), "text": text[:600], "vector": vec})
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

# Report the largest chunk against the cap, always. A "0 truncated" line would be
# constant and therefore unread; a high-water mark moves with the content, so a page
# creeping toward the limit is visible before it is a problem. At-cap chunks are the
# hard-slice case (a single line longer than the whole budget) and are named.
if records:
    biggest = max(r.get("chars", 0) for r in records)
    at_cap = [r for r in records if r.get("chars", 0) >= MAX_CHARS]
    print("rag-build: largest chunk %d/%d chars" % (biggest, MAX_CHARS))
    for r in at_cap[:5]:
        print("  at cap (unbroken line): %s:%d — %s" % (r["file"], r["line"], r["heading"]))
    if len(at_cap) > 5:
        print("  ... and %d more at cap" % (len(at_cap) - 5))

# The cross-boundary filter reports ALWAYS, including zero. Its skip is correct but was
# silent, so a page mis-stamped with another vault's boundary vanished from recall with
# no message anywhere: committed, linted, indexed, unanswerable. Three states have to be
# distinguishable, and only one of them used to print — a steady nonzero is normal for a
# vault legitimately holding foreign pages, a *newly* nonzero one on a vault that should
# hold none is the signal, and "not armed" must never look like "armed and clean".
if VBOUND is None:
    print("rag-build: cross-boundary filter NOT ARMED — no parseable 'boundary:' in "
          "CLAUDE.md, so nothing was filtered")
else:
    print("rag-build: cross-boundary filter armed (%s) — %d page(s) skipped"
          % (VBOUND, skipped))
PY
