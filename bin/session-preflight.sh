#!/usr/bin/env bash
# session-preflight.sh — upfront version check for a SessionStart hook. Reports two
# things and, when either is stale, prints an ACTION-REQUIRED block telling the assistant
# to ASK the user before updating — the hook itself never prompts or changes anything:
#   1. Claude Code  — installed vs latest stable (official endpoint); best-effort by
#                     install method (Homebrew cask · npm global), skips if undeterminable.
#   2. wiki-engine  — pinned submodule vs origin/main, via sibling engine-version.sh.
#
# Deterministic. NEVER runs the `claude` binary (hard rule: no claude in a hook — the
# version is read from install metadata, not `claude --version`); a hook that spawned
# claude is the fork-bomb trap. Uses only readlink/brew/npm, curl, and git. Always exits
# 0 so it can't block session start. Meant to run from a vault's pinned copy
# (engine/bin/session-preflight.sh); locates its siblings via SCRIPT_DIR, the vault via
# WIKI_PATH. The update actions it names are for the assistant to run on confirmation.
#
# Usage: WIKI_PATH=/path/to/vault session-preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"
CC_ENDPOINT="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/stable"

action=""   # accumulates ACTION-REQUIRED lines; empty => everything current
summary=""  # compact one-line staleness summary for the status line (see statusline.sh)
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

echo "=== Session preflight (versions) ==="

# 1. Claude Code — installed version + update command WITHOUT running the binary. -------
installed=""; method=""; update_cmd=""
cc_bin="$(command -v claude 2>/dev/null || true)"
link="$(readlink -f "$cc_bin" 2>/dev/null || true)"
case "$link" in
  */Caskroom/claude-code/*)
    installed="$(printf '%s\n' "$link" | sed -E 's#.*/Caskroom/claude-code/([^/]+)/.*#\1#')"
    method="Homebrew cask"; update_cmd="brew update && brew upgrade --cask claude-code" ;;
esac
if [ -z "$installed" ] && command -v npm >/dev/null 2>&1; then
  installed="$(npm ls -g --depth=0 @anthropic-ai/claude-code 2>/dev/null | sed -nE 's/.*@anthropic-ai\/claude-code@([0-9][^ ]*).*/\1/p')"
  [ -n "$installed" ] && { method="npm global"; update_cmd="npm update -g @anthropic-ai/claude-code"; }
fi
# unknown install method but a binary exists -> fall back to the built-in updater
[ -n "$cc_bin" ] && [ -z "$update_cmd" ] && update_cmd="claude update"

latest="$(curl -fsS --max-time 8 "$CC_ENDPOINT" 2>/dev/null | tr -d '[:space:]')"

if [ -z "$installed" ]; then
  echo "Claude Code: could not read installed version — skipping (checked Homebrew cask + npm global)"
elif [ -z "$latest" ]; then
  echo "Claude Code: installed $installed — could not reach release endpoint (offline?); skipping update check"
elif [ "$installed" = "$latest" ]; then
  echo "Claude Code: up to date ($installed${method:+, $method})"
else
  # newest wins; only flag when the endpoint's version is strictly newer than installed
  newest="$(printf '%s\n%s\n' "$installed" "$latest" | sort -V | tail -1)"
  if [ "$newest" = "$latest" ]; then
    echo "Claude Code: installed $installed, latest $latest — update available${method:+ ($method)}"
    summary="CC $installed→$latest"
    action="${action}
ACTION REQUIRED — Claude Code is out of date (installed $installed, latest $latest).
Ask the user whether to update now. On confirmation run:
  $update_cmd
Then tell the user to RESTART Claude Code (exit and relaunch) — the running binary cannot
hot-swap. (If the package manager reports no newer version, it just hasn't published
$latest yet; nothing to do until it does.)"
  else
    echo "Claude Code: installed $installed (ahead of latest stable $latest) — no action"
  fi
fi

# 2. wiki-engine — delegate to the sibling engine-version.sh (deterministic, no claude). -
ev="$SCRIPT_DIR/engine-version.sh"
if [ ! -x "$ev" ]; then
  echo "wiki-engine: engine-version.sh not found beside this script — skipping"
else
  ev_out="$("$ev" 2>/dev/null)"; ev_rc=$?
  # show its status line(s); drop its generic hint in favor of our update.sh one-liner
  printf '%s\n' "$ev_out" | grep -v '^  to update:'
  if [ "$ev_rc" -eq 1 ]; then
    # compact "engine <pinned>→<latest>" for the status line; tag MAJOR so it renders red
    eng_frag="$(printf '%s' "$ev_out" | sed -nE 's/.*pinned ([^,]+), latest ([^ ]+).*/engine \1→\2/p' | head -n1)"
    [ -n "$eng_frag" ] || eng_frag="engine update available"
    case "$ev_out" in *MAJOR*) eng_frag="$eng_frag MAJOR";; esac
    summary="${summary:+$summary · }$eng_frag"
    if [ -n "$WIKI" ]; then
      upd="WIKI_PATH=$WIKI $SCRIPT_DIR/update.sh"; commit="git -C $WIKI commit -am 'Bump engine'"
    else
      upd="$SCRIPT_DIR/update.sh --wiki <vault>"; commit="git -C <vault> commit -am 'Bump engine'"
    fi
    action="${action}
ACTION REQUIRED — wiki-engine is out of date (see line above).
Ask the user whether to update now. On confirmation run:
  $upd
It advances the submodule to the latest tag (refuses a MAJOR bump) and STAGES the pin.
Then remind the user to review the CHANGELOG and commit:
  $commit"
  fi
fi

# status-line cache — always (re)write so a resolved staleness clears a prior warning. ---
# statusline.sh reads this: one line = the compact summary, empty file = all current.
if mkdir -p "$(dirname "$CACHE")" 2>/dev/null; then
  printf '%s\n' "$summary" > "$CACHE" 2>/dev/null || true
fi

# actionable summary -------------------------------------------------------------------
[ -n "$action" ] && printf '%s\n' "$action"
exit 0
