#!/usr/bin/env bash
# doctor.sh — one-shot freshness report for a vault's consumed components:
#   1. the pinned engine        (vs the latest tag on origin)
#   2. the RAG venv Python deps  (drift from scaffold/rag-requirements.txt + newer on PyPI)
#   3. the embedding model       (provisioned? which one)
#
# Deterministic — git + pip, never `claude`. Run on demand, or from the freshness CI
# cron. `update.sh` applies engine + dep updates in one step. Reports; changes nothing.
#
# Exit: 0 all current · 1 something behind/drifted · 2 offline/can't-check.
#
# Usage: doctor.sh [--wiki DIR]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIKI="${WIKI_PATH:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }

rc=0
sec() { printf '\n=== %s ===\n' "$1"; }

# 1. engine ---------------------------------------------------------------------
sec "engine"
if [ -x "$SCRIPT_DIR/engine-version.sh" ]; then
  "$SCRIPT_DIR/engine-version.sh"; ev=$?
  [ "$ev" -eq 1 ] && rc=1
  [ "$ev" -eq 2 ] && [ "$rc" -eq 0 ] && rc=2
else
  echo "engine-version.sh not found"
fi

# 2. RAG deps -------------------------------------------------------------------
sec "rag deps"
VENV="$WIKI/.rag/venv"
REQ="${RAG_REQUIREMENTS:-$ENGINE_ROOT/scaffold/rag-requirements.txt}"
if [ ! -x "$VENV/bin/python" ]; then
  echo "not provisioned (no .rag/venv) — run engine/bin/rag-setup.sh to enable recall"
else
  # a) drift from the engine's pinned requirements (offline, cheap)
  if [ -f "$REQ" ]; then
    if drift="$("$VENV/bin/python" - "$REQ" <<'PY'
import sys, re
from importlib.metadata import version, PackageNotFoundError
out = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    m = re.match(r'([A-Za-z0-9_.\-]+)==([^;# ]+)', line)
    if not m:
        continue
    name, want = m.group(1), m.group(2)
    try:
        have = version(name)
    except PackageNotFoundError:
        have = None
    if have != want:
        out.append("  %s: pinned %s, installed %s" % (name, want, have))
if out:
    print("DRIFT"); print("\n".join(out))
else:
    print("on pinned versions")
PY
)"; then
      if printf '%s' "$drift" | head -1 | grep -q DRIFT; then
        echo "venv drifted from $(basename "$REQ") — run rag-setup.sh to sync:"
        printf '%s\n' "$drift" | tail -n +2
        rc=1
      else
        echo "venv matches $(basename "$REQ")"
      fi
    fi
  fi
  # b) newer releases on PyPI (needs network)
  if outdated="$("$VENV/bin/python" -m pip list --outdated --format=json 2>/dev/null)"; then
    n="$(printf '%s' "$outdated" | "$VENV/bin/python" -c 'import sys,json;print(len(json.load(sys.stdin) or []))' 2>/dev/null || echo 0)"
    if [ "${n:-0}" != "0" ]; then
      echo "newer on PyPI ($n) — review before bumping rag-requirements.txt:"
      printf '%s' "$outdated" | "$VENV/bin/python" -c 'import sys,json
for p in json.load(sys.stdin): print("  %s: %s -> %s" % (p["name"],p["version"],p["latest_version"]))' 2>/dev/null
      [ "$rc" -eq 0 ] && rc=1
    else
      echo "no newer releases on PyPI"
    fi
  else
    echo "could not reach PyPI (offline?) — skipped the newer-release check"
    [ "$rc" -eq 0 ] && rc=2
  fi
fi

# 3. model ----------------------------------------------------------------------
sec "embedding model"
CFG="$WIKI/.rag/config.json"
if [ -f "$CFG" ] && [ -x "$VENV/bin/python" ]; then
  "$VENV/bin/python" -c 'import json;c=json.load(open("'"$CFG"'"));print("  %s via %s (%s-dim)"%(c.get("model"),c.get("lib"),c.get("dim")))'
else
  echo "no model configured (.rag/config.json absent)"
fi

echo
case "$rc" in
  0) echo "doctor: all consumed components current";;
  2) echo "doctor: could not fully check (offline)";;
  *) echo "doctor: updates available — see engine/bin/update.sh";;
esac
exit "$rc"
