#!/usr/bin/env bash
# wire-machine.sh — make THIS machine ready for the vault at $WIKI_PATH. The idempotent
# "wire an existing vault" verb: run it on a freshly-cloned vault, or re-run anytime, and it
# CONVERGES what a machine needs beyond the plugin itself — WIKI_PATH, the always-on
# CLAUDE.md import, the status line, the semantic-recall runtime, and vault adoption. Every
# step is add-only and re-run-safe; nothing is clobbered. `--check` reports what would
# change and touches nothing. Deterministic — NEVER runs `claude`.
#
# The plugin carries the hooks and skills, so there is nothing here to link or hook. It is
# not installed from here either: that is two `claude plugin` commands, printed when the
# plugin is missing, because a script that edits enabledPlugins would bypass the install.
#
# Called by `new-wiki.sh` after scaffolding and by the `wiki-adopt` skill for a second or
# Nth machine. Scaffolding (create-new) stays in new-wiki.sh; wiring (converge) lives here.
#
# Usage:
#   wire-machine.sh --wiki DIR [options]
#   wire-machine.sh --wiki DIR --wire-env --wire-claude-md --wire-statusline
#   wire-machine.sh --wiki DIR --check
#
# Options:
#   --wire-env          ensure "env": {"WIKI_PATH": DIR} in settings.json, which reaches
#                       hooks, the Bash tool and the status line (the recommended default)
#   --wire-shell [RC]   also ensure `export WIKI_PATH=DIR` in RC (default ~/.zshrc), for
#                       shells outside Claude Code
#   --wire-claude-md    ensure `@DIR/CLAUDE.md` in ~/.claude/CLAUDE.md
#   --wire-statusline   ensure the engine status line, unless a foreign one is set
#   --no-rag            skip provisioning the .rag semantic-recall runtime
#   --check             dry-run: report pending changes, change nothing (exit 1 if any pending)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="${CLAUDE_SETTINGS:-$CFG/settings.json}"
# The boot hook keeps this link at the running engine; the plugin root moves on every update.
POINTER="$CFG/plugins/data/wiki-engine-wiki-engine/engine"

WIKI="${WIKI_PATH:-}"
WIRE_ENV=0 WIRE_SHELL=0 SHELL_RC="" WIRE_CLAUDE_MD=0 WIRE_STATUSLINE=0 RAG=1 CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    --wire-env) WIRE_ENV=1; shift;;
    --wire-shell) WIRE_SHELL=1; case "${2:-}" in ""|--*) SHELL_RC="$HOME/.zshrc"; shift;; *) SHELL_RC="$2"; shift 2;; esac;;
    --wire-claude-md) WIRE_CLAUDE_MD=1; shift;;
    --wire-statusline) WIRE_STATUSLINE=1; shift;;
    --no-rag) RAG=0; shift;;
    --check) CHECK=1; shift;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "wire-machine: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
# shellcheck disable=SC2088  # a LITERAL leading ~/ is what this expands by hand
case "$WIKI" in "~/"*) WIKI="$HOME/${WIKI#\~/}";; esac
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
WIKI="$(cd "$WIKI" && pwd)"
. "$SCRIPT_DIR/plugin-lib.sh"

pending=0
would() { echo "  would: $*"; pending=$((pending+1)); }
did()   { echo "  + $*"; }
ok()    { echo "  ok: $*"; }
note()  { echo "  ! $*"; }

echo "wire-machine: $WIKI  (check=$CHECK)"

# 1. the plugin -------------------------------------------------------------------------
if grep -qE '"wiki-engine@[^"]*"[[:space:]]*:[[:space:]]*true' "$SETTINGS" 2>/dev/null; then
  ok "wiki-engine plugin enabled"
else
  note "the wiki-engine plugin is not enabled in $SETTINGS; install it, then restart Claude Code:"
  echo "       claude plugin marketplace add pleejr/wiki-engine"
  echo "       claude plugin install wiki-engine@wiki-engine --scope user"
  pending=$((pending+1))
fi

# 2. the vault is on 2.x ----------------------------------------------------------------
if vault_has_engine_submodule "$WIKI"; then
  note "the vault still carries the 1.x engine/ submodule — drop it (CHANGELOG 2.0.0, \"Dropping the vault's submodule\")"
  pending=$((pending+1))
elif [ -z "$(vault_engine_required "$WIKI")" ]; then
  note "the vault records no .engine-version — run $SCRIPT_DIR/update.sh --wiki \"$WIKI\""
fi

# 3. WIKI_PATH in settings.json env (conservative: a different value is left alone) ------
if [ "$WIRE_ENV" -eq 1 ]; then
  if ! command -v jq >/dev/null 2>&1; then
    note "jq not found; cannot edit $SETTINGS — add \"env\": {\"WIKI_PATH\": \"$WIKI\"} by hand"
  else
    cur="$(jq -r '.env.WIKI_PATH // empty' "$SETTINGS" 2>/dev/null || true)"
    if [ "$cur" = "$WIKI" ]; then ok "settings.json env.WIKI_PATH already $WIKI"
    elif [ -n "$cur" ]; then note "settings.json env.WIKI_PATH is $cur, not $WIKI — left as-is (one vault per machine)"
    elif [ "$CHECK" -eq 1 ]; then would "set env.WIKI_PATH=$WIKI in $SETTINGS"
    else
      if [ -f "$SETTINGS" ]; then
        jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "error: $SETTINGS is not valid JSON — refusing to edit" >&2; exit 1; }
        cp -p "$SETTINGS" "$SETTINGS.bak.wire-machine"
      else
        mkdir -p "$(dirname "$SETTINGS")"; printf '{}\n' > "$SETTINGS"
      fi
      tmp="$(mktemp)"
      jq --arg w "$WIKI" '.env = ((.env // {}) + {WIKI_PATH: $w})' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      did "env.WIKI_PATH -> $SETTINGS (next Claude Code session)"
    fi
  fi
fi

# 4. WIKI_PATH in the shell rc (grep-guarded) -------------------------------------------
if [ "$WIRE_SHELL" -eq 1 ]; then
  LINE="export WIKI_PATH=\"$WIKI\""
  if [ -f "$SHELL_RC" ] && grep -q '^[[:space:]]*export WIKI_PATH=' "$SHELL_RC"; then
    ok "$SHELL_RC already exports WIKI_PATH (left as-is)"
  elif [ "$CHECK" -eq 1 ]; then would "append WIKI_PATH export to $SHELL_RC"
  else printf '\n# wiki-engine vault\n%s\n' "$LINE" >> "$SHELL_RC"; did "WIKI_PATH -> $SHELL_RC (open a new shell)"; fi
fi

# 5. always-on CLAUDE.md import (grep-guarded) ------------------------------------------
if [ "$WIRE_CLAUDE_MD" -eq 1 ]; then
  CMD="$CFG/CLAUDE.md"; IMPORT="@$WIKI/CLAUDE.md"
  if [ -f "$CMD" ] && grep -qF "$IMPORT" "$CMD"; then
    ok "$CMD already imports this vault (left as-is)"
  elif [ "$CHECK" -eq 1 ]; then would "append '$IMPORT' to $CMD"
  else mkdir -p "$CFG"; printf '\n%s\n' "$IMPORT" >> "$CMD"; did "always-on import -> $CMD"; fi
fi

# 6. status line, through the stable pointer --------------------------------------------
if [ "$WIRE_STATUSLINE" -eq 1 ]; then
  # WIKI_PATH rides on the command, so the status line works whether or not settings `env`
  # or the shell supplies the variable.
  sl_args=(--command "WIKI_PATH=$WIKI $POINTER/bin/statusline.sh" --marker "engine/bin/statusline.sh" --settings "$SETTINGS")
  if [ "$CHECK" -eq 1 ]; then
    out="$("$SCRIPT_DIR/ensure-statusline.sh" "${sl_args[@]}" --check 2>&1)"
    if [ -n "$out" ]; then would "$out"; else ok "status line already set (ours, or a foreign one left alone)"; fi
  else
    out="$("$SCRIPT_DIR/ensure-statusline.sh" "${sl_args[@]}" 2>&1)" || note "status line: $out"
    if [ -n "$out" ]; then did "$out"; else ok "status line already set (ours, or a foreign one left alone)"; fi
  fi
fi

# 7. semantic-recall runtime (provision only if absent) ---------------------------------
if [ "$RAG" -eq 1 ]; then
  if [ -x "$WIKI/.rag/venv/bin/python" ]; then ok "semantic recall already provisioned (.rag/venv)"
  elif [ "$CHECK" -eq 1 ]; then would "provision .rag recall runtime (rag-setup.sh) — offline-tolerant"
  else
    if "$ENGINE_ROOT/bin/rag-setup.sh" --wiki "$WIKI"; then
      "$ENGINE_ROOT/bin/rag-build.sh" --wiki "$WIKI" || true; did "semantic recall provisioned"
    else note "rag-setup skipped (offline or pip restricted) — run $ENGINE_ROOT/bin/rag-setup.sh --wiki \"$WIKI\" later"; fi
  fi
fi

# 8. engine node-folders + vault adoption (idempotent; delegates to adopt.sh) -----------
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
