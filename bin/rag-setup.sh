#!/usr/bin/env bash
# rag-setup.sh — provision a vault's self-contained embedding runtime for semantic
# recall. Creates a git-ignored venv at $WIKI/.rag/venv, installs a CPU embedder,
# prefetches the model, and writes $WIKI/.rag/config.json. Idempotent.
#
# This is what makes RAG a packaged, works-out-of-the-box feature: clone the engine,
# run new-wiki.sh (which calls this), and recall works with no server, no GPU, and
# nothing external after the one-time install. Needs pip + one model download; fully
# offline thereafter. Runs a small CPU model, never `claude` — see [[lesson-no-claude-in-hooks]].
#
# Config:
#   RAG_PIP_PKG      pip package(s) to install   (default: model2vec)
#   RAG_LOCAL_MODEL  model to prefetch           (default: minishlab/potion-base-8M)
#
# Usage:
#   rag-setup.sh                provision $WIKI_PATH
#   rag-setup.sh --wiki DIR     target DIR
#   rag-setup.sh --force        recreate the venv from scratch
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

PKG="${RAG_PIP_PKG:-model2vec}"
MODEL="${RAG_LOCAL_MODEL:-minishlab/potion-base-8M}"
VENV="$WIKI/.rag/venv"

mkdir -p "$WIKI/.rag"
[ "$FORCE" -eq 1 ] && rm -rf "$VENV"
if [ ! -x "$VENV/bin/python" ]; then
  echo "rag-setup: creating venv at .rag/venv"
  python3 -m venv "$VENV"
fi

echo "rag-setup: installing $PKG (CPU embedder)"
"$VENV/bin/python" -m pip install --quiet --upgrade pip
# shellcheck disable=SC2086
"$VENV/bin/python" -m pip install --quiet $PKG

echo "rag-setup: prefetching model $MODEL"
RAG_BINDIR="$SCRIPT_DIR" RAG_EMBED_API=local RAG_LOCAL_MODEL="$MODEL" \
"$VENV/bin/python" - "$WIKI" <<'PY'
import os, sys, json
sys.path.insert(0, os.environ["RAG_BINDIR"])
from rag_embed import Embedder
wiki = sys.argv[1]
e = Embedder()                    # loads + downloads the model
dim = len(e.embed(["probe"])[0])
cfg = {"backend": "local", "lib": e.lib, "model": e.model, "dim": dim}
json.dump(cfg, open(os.path.join(wiki, ".rag", "config.json"), "w"), indent=2)
print("rag-setup: ready — %s via %s (%d-dim). Wrote .rag/config.json" % (e.model, e.lib, dim))
PY

echo "rag-setup: next — engine/bin/rag-build.sh to index the vault"
