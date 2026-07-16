#!/usr/bin/env bash
# rag-setup.sh — provision a vault's self-contained embedding runtime for semantic
# recall. Creates a git-ignored venv at $WIKI/.rag/venv, installs a CPU embedder,
# prefetches the model, and writes $WIKI/.rag/config.json. Idempotent.
#
# This is what makes RAG a packaged, works-out-of-the-box feature: clone the engine,
# run new-wiki.sh (which calls this), and recall works with no server, no GPU, and
# nothing external after the one-time install. Needs Python 3.10–3.14 + pip + one model
# download; fully offline thereafter — and if the default python3 is out of that range,
# it auto-selects an in-range interpreter from PATH/pyenv (else use the model2vec
# fallback below). Runs a small CPU model, never `claude` — see [[lesson-no-claude-in-hooks]].
#
# Config:
#   RAG_REQUIREMENTS pinned deps file  (default: engine scaffold/rag-requirements.txt)
#   RAG_PIP_PKG      override: install this package instead of the pinned file (unpinned)
#   RAG_LOCAL_MODEL  model to prefetch           (default: BAAI/bge-base-en-v1.5)
#
# Default is fastembed + bge-base (contextual, 768-dim, quantized ONNX ~210MB, CPU,
# offline) — the best-quality-within-reason local retriever. Lighter alt:
# RAG_PIP_PKG=model2vec RAG_LOCAL_MODEL=minishlab/potion-base-8M (~30MB, static).
# Heavier: RAG_LOCAL_MODEL=BAAI/bge-large-en-v1.5 (~1.2GB, slower on CPU).
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

ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQ="${RAG_REQUIREMENTS:-$ENGINE_ROOT/scaffold/rag-requirements.txt}"
MODEL="${RAG_LOCAL_MODEL:-BAAI/bge-base-en-v1.5}"
VENV="$WIKI/.rag/venv"
MIN_PY=310 MAX_PY=314   # supported Python range for the pinned bge stack (X*100+Y)

# major*100+minor for an interpreter (0 if it can't run).
pyver() { "$1" -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])' 2>/dev/null || echo 0; }
in_range() { [ "$1" -ge "$MIN_PY" ] && [ "$1" -le "$MAX_PY" ]; }

# Self-healing interpreter pick for the pinned path: prefer python3 if it's in range,
# else fall back to any in-range interpreter on PATH or under pyenv (does automatically
# what you'd otherwise do by hand when the default python3 is newer than the ceiling).
# Echoes the chosen interpreter, or "" if none in 3.10–MAX is found.
choose_python() {
  local v c p
  v="$(pyver python3)"; if in_range "$v"; then echo python3; return; fi
  for c in python3.14 python3.13 python3.12 python3.11 python3.10; do
    command -v "$c" >/dev/null 2>&1 && { v="$(pyver "$c")"; in_range "$v" && { echo "$c"; return; }; }
  done
  if [ -d "$HOME/.pyenv/versions" ]; then
    for p in "$HOME/.pyenv/versions"/*/bin/python; do
      [ -x "$p" ] || continue; v="$(pyver "$p")"; in_range "$v" && { echo "$p"; return; }
    done
  fi
  echo ""
}

# Printed when no usable interpreter / the pinned install fails — turns an opaque abort
# into the actual remedies. Recall is optional, so this is a guided skip, not a crash.
pinned_install_hint() {
  cat >&2 <<EOF
rag-setup: could not provision the pinned bge stack (needs Python 3.10–3.14; this
  machine's python3 is $(python3 -V 2>&1 | awk '{print $2}') and no in-range interpreter was found).
  Remedies:
    • Install/select a Python in 3.10–3.14 (pyenv or Homebrew), then rerun.
    • Or use the lightweight, onnxruntime-free embedder (works on any modern Python):
        RAG_PIP_PKG=model2vec RAG_LOCAL_MODEL=minishlab/potion-base-8M \\
          $ENGINE_ROOT/bin/rag-setup.sh --wiki "$WIKI"
  Semantic recall is optional — the vault's lexical index + link graph work without it.
EOF
}

mkdir -p "$WIKI/.rag"
[ "$FORCE" -eq 1 ] && rm -rf "$VENV"
if [ ! -x "$VENV/bin/python" ]; then
  # The RAG_PIP_PKG override (e.g. model2vec) runs on any Python — use python3 as-is.
  # The pinned bge path needs 3.10–3.14, so pick an in-range interpreter or guide out.
  if [ -n "${RAG_PIP_PKG:-}" ]; then
    PY=python3
  else
    PY="$(choose_python)"
    [ -n "$PY" ] || { pinned_install_hint; exit 1; }
    [ "$PY" != "python3" ] && echo "rag-setup: default python3 is out of range 3.10–3.14; using $PY ($("$PY" -V 2>&1 | awk '{print $2}'))"
  fi
  echo "rag-setup: creating venv at .rag/venv"
  "$PY" -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --quiet --upgrade pip
if [ -n "${RAG_PIP_PKG:-}" ]; then
  echo "rag-setup: installing $RAG_PIP_PKG (override — unpinned)"
  # shellcheck disable=SC2086
  "$VENV/bin/python" -m pip install --quiet $RAG_PIP_PKG
elif [ -f "$REQ" ]; then
  echo "rag-setup: installing pinned deps from $(basename "$REQ")"
  if ! "$VENV/bin/python" -m pip install --quiet -r "$REQ"; then pinned_install_hint; exit 1; fi
else
  echo "rag-setup: installing fastembed (no requirements file)"
  "$VENV/bin/python" -m pip install --quiet fastembed
fi

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
