#!/usr/bin/env bash
# plugin-lib.sh — how the engine tells plugin delivery from submodule delivery.
#
# SOURCED, never executed. Since 1.80.0 the engine ships two ways at once: as the
# `wiki-engine` Claude Code plugin (hooks in hooks/hooks.json, skills namespaced
# `wiki-engine:<name>`) and as the vault's pinned `engine/` submodule wired by adopt.d.
# During the move a machine can carry both, and every question below exists so the two
# never both act:
#
#   engine_plugin_enabled   is the plugin switched on for this machine (user settings)?
#   engine_running_as_plugin  was THIS script started by the plugin (vs. a settings hook
#                           or a hand run from the submodule)?
#   engine_superseded_by_plugin  plugin on, but this copy was not started by it — the
#                           legacy settings hook firing beside the plugin's own. Callers
#                           exit quietly so a session boots and captures exactly once.
#   engine_release          the version this engine tree is: `git describe` in a checkout,
#                           the manifest's version in a plugin cache (which is not a repo).
#
# "Enabled" is read from user settings, never inferred from where a file sits: the same
# tree is reached as a submodule and as a plugin source, so position proves nothing.

_engine_settings() { printf '%s\n' "${CLAUDE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"; }

engine_plugin_enabled() {
  grep -qE '"wiki-engine@[^"]*"[[:space:]]*:[[:space:]]*true' "$(_engine_settings)" 2>/dev/null
}

engine_running_as_plugin() {
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] || return 1
  grep -qE '"name"[[:space:]]*:[[:space:]]*"wiki-engine"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
}

engine_superseded_by_plugin() {
  engine_plugin_enabled && ! engine_running_as_plugin
}

engine_release() { # <engine-dir>
  local e="${1:?engine dir}" v
  if git -C "$e" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$e" describe --tags --always 2>/dev/null && return 0
  fi
  v="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$e/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  [ -n "$v" ] && printf 'v%s\n' "$v" || echo unknown
}
