#!/usr/bin/env bash
# plugin-lib.sh — what the engine knows about its own delivery.
#
# SOURCED, never executed. Since 2.0.0 the engine ships only as the `wiki-engine` Claude
# Code plugin: hooks in hooks/hooks.json, skills namespaced `wiki-engine:<name>`. A vault
# records the release it needs in `.engine-version`; the `engine/` submodule and the
# settings.json hooks that 1.x wired are gone.
#
#   engine_running_as_plugin  was THIS script started by the plugin (vs. a hand run or CI
#                             from a checkout)?
#   engine_release            the version this engine tree is: the manifest's version for
#                             the tree the plugin runs from (cache or checkout), else
#                             `git describe`, else the manifest.
#   vault_engine_required     the release a vault records in `.engine-version` (empty when
#                             none is recorded).
#   vault_has_engine_submodule  does the vault still carry the 1.x `engine/` submodule?
#   settings_legacy_engine_hooks  settings.json hook commands a 1.x adoption wired, which
#                             point into a vault's `engine/` and fail once it is gone.
#   engine_version_lt         whether release A sorts before release B (`v`-prefixed or not).

engine_running_as_plugin() {
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] || return 1
  grep -qE '"name"[[:space:]]*:[[:space:]]*"wiki-engine"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
}

engine_release() { # <engine-dir>
  local e="${1:?engine dir}" v plugin=0
  # The tree the plugin runs from is versioned by its manifest even when it is a git checkout
  # (a directory marketplace): `git describe` there would name the same release differently
  # from its cache copy.
  if engine_running_as_plugin && [ "$(cd "$e" 2>/dev/null && pwd -P)" = "$(cd "$CLAUDE_PLUGIN_ROOT" && pwd -P)" ]; then
    plugin=1
  fi
  if [ "$plugin" -eq 0 ] && git -C "$e" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$e" describe --tags --always 2>/dev/null && return 0
  fi
  v="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$e/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  [ -n "$v" ] && printf 'v%s\n' "$v" || echo unknown
}

# One tag per file (e.g. `v2.0.0`). Vault CI checks out that tag; the preflight compares it
# with the running plugin.
vault_engine_required() { # <wiki>
  local w="${1:?wiki}"
  [ -f "$w/.engine-version" ] || return 0
  tr -d '[:space:]' < "$w/.engine-version"
}

# A gitlink or a checked-out submodule both count: either way the vault still expects 1.x.
vault_has_engine_submodule() { # <wiki>
  local w="${1:?wiki}"
  [ -e "$w/engine/.git" ] && return 0
  grep -qE '^[[:space:]]*path[[:space:]]*=[[:space:]]*engine[[:space:]]*$' "$w/.gitmodules" 2>/dev/null
}

settings_legacy_engine_hooks() { # [settings.json]
  local s="${1:-${CLAUDE_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}}"
  [ -f "$s" ] || return 0
  grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*engine/bin/(session-boot|rag-capture|session-preflight|session-banner)\.sh[^"]*"' "$s" 2>/dev/null \
    | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"//; s/"$//' \
    | grep -v 'plugins/' || true
}

engine_version_lt() { # <a> <b>
  local a="${1#v}" b="${2#v}"
  [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" = "$a" ]
}
