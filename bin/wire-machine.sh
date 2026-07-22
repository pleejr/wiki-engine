#!/usr/bin/env bash
# wire-machine.sh — make THIS machine ready for the vault at $WIKI_PATH. The idempotent
# "wire an existing vault" verb: run it on a freshly-cloned vault, or re-run anytime, and
# it CONVERGES everything a machine needs — engine submodule, skill links, WIKI_PATH, the
# always-on CLAUDE.md import, the semantic-recall runtime, and engine node-folder/feature
# adoption. Every step is add-only and re-run-safe; nothing is clobbered. `--check` reports
# what would change and touches nothing. Deterministic — NEVER runs `claude`.
#
# This is the single source of machine-wiring truth: `new-wiki.sh` calls it right after
# scaffolding, and the `wiki-adopt` skill calls it to bring up a second/Nth machine from an
# existing clone. Scaffolding (create-new) stays in new-wiki.sh; wiring (converge) lives here.
#
# Usage:
#   wire-machine.sh --wiki DIR [options]
#   wire-machine.sh --wiki DIR --wire-shell [RC] --wire-claude-md
#   wire-machine.sh --wiki DIR --check
#
# Options:
#   --wire-shell [RC]   ensure `export WIKI_PATH=DIR` in RC (default ~/.zshrc); grep-guarded
#   --wire-claude-md    ensure `@DIR/CLAUDE.md` in ~/.claude/CLAUDE.md; grep-guarded
#   --no-link-skills    skip symlinking engine skills into ~/.claude/skills
#   --no-rag            skip provisioning the .rag semantic-recall runtime
#   --check             dry-run: report pending changes, change nothing (exit 1 if any pending)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

WIKI="${WIKI_PATH:-}"
WIRE_SHELL=0 SHELL_RC="" WIRE_CLAUDE_MD=0 LINK_SKILLS=1 RAG=1 CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --wire-shell) WIRE_SHELL=1; case "${2:-}" in ""|--*) SHELL_RC="$HOME/.zshrc"; shift;; *) SHELL_RC="$2"; shift 2;; esac;;
    --wire-claude-md) WIRE_CLAUDE_MD=1; shift;;
    --no-link-skills) LINK_SKILLS=0; shift;;
    --no-rag) RAG=0; shift;;
    --check) CHECK=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "wire-machine: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
case "$WIKI" in "~/"*) WIKI="$HOME/${WIKI#\~/}";; esac
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
WIKI="$(cd "$WIKI" && pwd)"

pending=0
would() { echo "  would: $*"; pending=$((pending+1)); }
did()   { echo "  + $*"; }
ok()    { echo "  ok: $*"; }

echo "wire-machine: $WIKI  (check=$CHECK)"

# 1. engine submodule initialized -------------------------------------------------
if [ -f "$WIKI/.gitmodules" ] && grep -q 'path = engine' "$WIKI/.gitmodules" 2>/dev/null; then
  if [ -f "$WIKI/engine/bin/lint.sh" ]; then ok "engine submodule initialized"
  elif [ "$CHECK" -eq 1 ]; then would "git submodule update --init (engine not checked out)"
  else git -C "$WIKI" submodule update --init --recursive && did "engine submodule initialized"; fi
fi

# 2. skills linked into ~/.claude/skills ------------------------------------------
if [ "$LINK_SKILLS" -eq 1 ]; then
  if [ "$CHECK" -eq 1 ]; then
    if "$ENGINE_ROOT/bin/link-skills.sh" --check >/dev/null 2>&1; then ok "engine skills already linked (~/.claude/skills)"
    else would "symlink engine skills into ~/.claude/skills"; fi
  else
    "$ENGINE_ROOT/bin/link-skills.sh" >/dev/null && ok "engine skills linked (~/.claude/skills)"
  fi
fi

# 3. WIKI_PATH in the shell rc (grep-guarded) -------------------------------------
if [ "$WIRE_SHELL" -eq 1 ]; then
  LINE="export WIKI_PATH=\"$WIKI\""
  if [ -f "$SHELL_RC" ] && grep -q '^[[:space:]]*export WIKI_PATH=' "$SHELL_RC"; then
    ok "$SHELL_RC already exports WIKI_PATH (left as-is)"
  elif [ "$CHECK" -eq 1 ]; then would "append WIKI_PATH export to $SHELL_RC"
  else printf '\n# wiki-engine vault\n%s\n' "$LINE" >> "$SHELL_RC"; did "WIKI_PATH -> $SHELL_RC (open a new shell)"; fi
fi

# 4. always-on CLAUDE.md import (grep-guarded) ------------------------------------
if [ "$WIRE_CLAUDE_MD" -eq 1 ]; then
  CMD="$HOME/.claude/CLAUDE.md"; IMPORT="@$WIKI/CLAUDE.md"
  if [ -f "$CMD" ] && grep -qF "$IMPORT" "$CMD"; then
    ok "$CMD already imports this vault (left as-is)"
  elif [ "$CHECK" -eq 1 ]; then would "append '$IMPORT' to $CMD"
  else mkdir -p "$HOME/.claude"; printf '\n%s\n' "$IMPORT" >> "$CMD"; did "always-on import -> $CMD"; fi
fi

# 5. semantic-recall runtime (provision only if absent) ---------------------------
if [ "$RAG" -eq 1 ]; then
  if [ -x "$WIKI/.rag/venv/bin/python" ]; then ok "semantic recall already provisioned (.rag/venv)"
  elif [ "$CHECK" -eq 1 ]; then would "provision .rag recall runtime (rag-setup.sh) — offline-tolerant"
  else
    if "$ENGINE_ROOT/bin/rag-setup.sh" --wiki "$WIKI"; then
      "$ENGINE_ROOT/bin/rag-build.sh" --wiki "$WIKI" || true; did "semantic recall provisioned"
    else echo "  ! rag-setup skipped (offline or pip restricted) — run $WIKI/engine/bin/rag-setup.sh later" >&2; fi
  fi
fi

# 6. engine node-folders + feature adoption (idempotent; delegates to adopt.sh) ---
if [ "$CHECK" -eq 1 ]; then
  "$ENGINE_ROOT/bin/adopt.sh" --wiki "$WIKI" --check >/dev/null 2>&1 || { would "engine adopt (missing node folders or pending adopt.d steps)"; }
else
  "$ENGINE_ROOT/bin/adopt.sh" --wiki "$WIKI" | sed 's/^/  /' || true
fi

echo
if [ "$CHECK" -eq 1 ]; then
  if [ "$pending" -gt 0 ]; then echo "wire-machine: $pending change(s) pending — run without --check to converge"; exit 1; fi
  echo "wire-machine: machine already converged — nothing to do"; exit 0
fi
echo "wire-machine: done."
