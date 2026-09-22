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
#   engine_marketplace_source which marketplace gates this plugin's updates, and whether it
#                             is a DIRECTORY source (a local clone that must be pulled first).
#   engine_update_remedy      the one command that actually advances this machine.
#   engine_installed_root     where the host installed this plugin — which a mid-session
#                             `claude plugin update` moves while CLAUDE_PLUGIN_ROOT stays put.
#   engine_bump_level         how a running release relates to a latest one: same / ahead /
#                             MAJOR / minor / patch. The single definition both the
#                             freshness report and the session banner read.

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

# WHICH MARKETPLACE GATES THIS PLUGIN, and how it is advanced. `claude plugin update`
# installs whatever the machine's marketplace advertises, and a DIRECTORY marketplace
# advertises whatever a local clone says — so on such a machine the update command answers
# "already at the latest version" however many releases have shipped, and every remedy the
# engine printed was a dead end. Observed on a second machine: `doctor.sh` reported
# `latest v2.1.0` (it asks the remote) while the update command reported 2.0.2 (it asks the
# clone); both true, about different sources, with nothing saying so.
#
# Echoes: <marketplace-name><TAB><source-type><TAB><path>  (path empty unless directory).
# FAIL-OPEN and silent — no host metadata, no python3, unreadable JSON: prints nothing and
# the caller falls back to the plain remedy. This reads the host's own plugin registry,
# which is why it is guarded rather than trusted.
engine_marketplace_source() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" name
  name="$(sed -nE 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
         "${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
  [ -n "$name" ] || name=wiki-engine
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$cfg" "$name" <<'PYMP' 2>/dev/null || true
import json, os, sys
cfg, plugin = sys.argv[1], sys.argv[2]
try:
    installed = json.load(open(os.path.join(cfg, "installed_plugins.json")))["plugins"]
    known = json.load(open(os.path.join(cfg, "known_marketplaces.json")))
except Exception:
    sys.exit(0)
# The plugin id is "<plugin>@<marketplace>"; the marketplace half is what gates updates.
mp = next((k.split("@", 1)[1] for k in installed if k.split("@", 1)[0] == plugin and "@" in k), None)
if not mp or mp not in known:
    sys.exit(0)
src = known[mp].get("source") or {}
kind = src.get("source") or ""
path = src.get("path") or (known[mp].get("installLocation") if kind == "directory" else "") or ""
print("%s\t%s\t%s" % (mp, kind, path if kind == "directory" else ""))
PYMP
}

# The ONE remedy string, so the five places that tell someone how to update cannot drift
# into four right answers and one wrong one. On a directory marketplace it leads with the
# pull that makes the update command mean anything; everywhere else it is the plain
# command, exactly as before.
engine_update_remedy() {
  local line mp kind path
  line="$(engine_marketplace_source)"
  mp="$(printf '%s' "$line" | cut -f1)"; kind="$(printf '%s' "$line" | cut -f2)"; path="$(printf '%s' "$line" | cut -f3)"
  [ -n "$mp" ] || mp=wiki-engine
  if [ "$kind" = "directory" ] && [ -n "$path" ]; then
    printf 'git -C %s pull --ff-only && claude plugin marketplace update %s && claude plugin update wiki-engine@%s\n' "$path" "$mp" "$mp"
  else
    printf 'claude plugin update wiki-engine@%s\n' "$mp"
  fi
}

# The directory the host's registry says this plugin is installed at. The session's own
# CLAUDE_PLUGIN_ROOT is fixed when it starts, so after an in-session `claude plugin update`
# only the registry names the new release. Prints nothing when it cannot tell (no registry,
# no python3, no entry, or an entry whose directory is not a wiki-engine plugin).
engine_installed_root() {
  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" p
  command -v python3 >/dev/null 2>&1 || return 0
  p="$(python3 - "$cfg" <<'PYIR' 2>/dev/null || true
import json, os, sys
try:
    installed = json.load(open(os.path.join(sys.argv[1], "installed_plugins.json")))["plugins"]
except Exception:
    sys.exit(0)
for key, entries in installed.items():
    if key.split("@", 1)[0] != "wiki-engine":
        continue
    for e in entries if isinstance(entries, list) else [entries]:
        if isinstance(e, dict) and e.get("installPath"):
            print(e["installPath"]); sys.exit(0)
PYIR
)"
  [ -n "$p" ] && [ -f "$p/.claude-plugin/plugin.json" ] \
    && grep -qE '"name"[[:space:]]*:[[:space:]]*"wiki-engine"' "$p/.claude-plugin/plugin.json" \
    && printf '%s\n' "$p"
  return 0
}

# The ONE definition of how two releases relate. `engine-version.sh` reports it and
# `session-preflight.sh` renders it into the banner; two copies of the same comparison
# drifting apart is a defect this engine has already shipped once (ensure-hook's guard
# asked `any(...)` while its writer answered with `map(...)`).
#
# Echoes: same | ahead | MAJOR | minor | patch. A release-suffixed running tag
# (`v1.2.3-4-gabc`) compares as its base release, which is what a consumer can install.
engine_bump_level() { # <running-tag> <latest-tag>
  local r="${1:-}" l="${2:-}" rmaj lmaj rrest lrest rmin lmin
  r="${r#v}"; r="${r%%-*}"; l="${l#v}"; l="${l%%-*}"
  if [ -z "$r" ] || [ -z "$l" ]; then echo unknown; return 1; fi
  if [ "$r" = "$l" ]; then echo same; return 0; fi
  if [ "$(printf '%s\n%s\n' "$r" "$l" | sort -V | tail -1)" = "$r" ]; then echo ahead; return 0; fi
  rmaj="${r%%.*}"; lmaj="${l%%.*}"
  rrest="${r#*.}"; lrest="${l#*.}"; rmin="${rrest%%.*}"; lmin="${lrest%%.*}"
  if [ "$rmaj" != "$lmaj" ]; then echo MAJOR
  elif [ "$rmin" != "$lmin" ]; then echo minor
  else echo patch; fi
}

engine_version_lt() { # <a> <b>
  local a="${1#v}" b="${2#v}"
  [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" = "$a" ]
}
