#!/usr/bin/env bash
# session-preflight.sh — upfront version check for a SessionStart hook. Reports the
# wiki-engine status and, when it is stale, prints an ACTION-REQUIRED block telling the
# assistant to ASK the user before updating — the hook itself never prompts or changes
# anything:
#   - wiki-engine  — the running release vs the vault's .engine-version; a leftover 1.x
#                    submodule or settings.json hook.
#
# Deterministic. NEVER runs the `claude` binary (hard rule: no claude in a hook); a hook
# that spawned claude is the fork-bomb trap. Always exits 0 so it can't
# block session start. Run by session-boot.sh from the plugin; locates its siblings via
# SCRIPT_DIR, the vault via WIKI_PATH. The actions it names are for the assistant to run
# on confirmation.
#
# Usage: WIKI_PATH=/path/to/vault session-preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKI="${WIKI_PATH:-}"

action=""   # accumulates ACTION-REQUIRED lines; empty => everything current
summary=""  # compact one-line staleness summary for the status line (see statusline.sh)
CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-status"

echo "=== Session preflight (versions) ==="

# wiki-engine — the running release, and how it relates to the vault's record. ----------
. "$SCRIPT_DIR/plugin-lib.sh"
run_ver="$(engine_release "$(cd "$SCRIPT_DIR/.." && pwd)")"
if engine_running_as_plugin; then
  echo "wiki-engine: plugin $run_ver (updates arrive through the plugin marketplace)"
else
  echo "wiki-engine: $run_ver, run from $(cd "$SCRIPT_DIR/.." && pwd) rather than the plugin"
fi

# A 1.x vault still pins the engine as a submodule. 2.x reads nothing from it, so its
# CLAUDE.md import, pre-commit gate and CI keep running the old copy until it is dropped.
if [ -n "$WIKI" ] && vault_has_engine_submodule "$WIKI"; then
  echo "wiki-engine: ⚠ the vault still carries the 1.x engine/ submodule, which 2.x does not use"
  action="${action}- wiki-engine: the vault at $WIKI still has an engine/ submodule. 2.x ignores it; its import, gate and CI run the stale copy. Tell the user and offer the migration in the engine CHANGELOG, 2.0.0 section (\"Dropping the vault's submodule\").
"
  summary="${summary:+$summary · }engine submodule"
fi

# settings.json hooks a 1.x adoption wired. The plugin carries boot and capture now, and a
# legacy command pointing into a dropped engine/ fails on every session.
legacy="$(settings_legacy_engine_hooks)"
if [ -n "$legacy" ]; then
  echo "wiki-engine: ⚠ settings.json still wires engine hooks by path; the plugin carries them now"
  action="${action}- wiki-engine: delete these settings.json hook entries (the plugin runs them itself); confirm with the user first:
$(printf '%s\n' "$legacy" | sed 's/^/    /')
"
  summary="${summary:+$summary · }legacy engine hooks"
fi

# The vault records the release its CI checks out.
req_ver=""; [ -n "$WIKI" ] && req_ver="$(vault_engine_required "$WIKI")"
if [ -n "$WIKI" ] && [ -z "$req_ver" ] && ! vault_has_engine_submodule "$WIKI"; then
  echo "wiki-engine: the vault records no .engine-version — run update.sh to record $run_ver"
elif [ -n "$req_ver" ] && [ "$req_ver" != "$run_ver" ]; then
  if [ "$(printf '%s' "${req_ver#v}" | cut -d. -f1)" != "$(printf '%s' "${run_ver#v}" | cut -d. -f1)" ]; then
    echo "wiki-engine: ⚠ the vault requires $req_ver and the plugin is $run_ver — a different MAJOR; follow the CHANGELOG migration"
    action="${action}- wiki-engine: the plugin ($run_ver) and the vault's .engine-version ($req_ver) differ in MAJOR version. Tell the user; do not change either without their confirmation.
"
    summary="${summary:+$summary · }engine MAJOR ${run_ver}≠${req_ver}"
  elif engine_version_lt "$run_ver" "$req_ver"; then
    echo "wiki-engine: ⚠ the vault requires $req_ver but the plugin is $run_ver — update the plugin"
    action="${action}- wiki-engine: plugin $run_ver is older than the vault's .engine-version $req_ver. Offer to run: claude plugin update wiki-engine@wiki-engine (then restart).
"
    summary="${summary:+$summary · }engine ${run_ver}<${req_ver}"
  else
    echo "wiki-engine: the vault records $req_ver in .engine-version — its CI runs that tag until update.sh records $run_ver"
  fi
fi

# consumer session-checks — a generic seam so a machine can fold ITS OWN extra checks into
# this one banner without the engine knowing anything about them. Each executable drop-in in
# ~/.claude/session-checks.d/ is run (deterministic; it MUST NOT call `claude`) and its output
# folded in: first stdout line = a compact banner fragment (empty => nothing to report),
# any remaining lines = action/notes for the assistant. This is how a consumer's skill repo
# surfaces "first run / catch up" beside the engine's own freshness — the engine stays generic.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CHECKS_D="$CFG/session-checks.d"
if [ -d "$CHECKS_D" ]; then
  for chk in "$CHECKS_D"/*.sh; do
    [ -e "$chk" ] || continue
    out="$(bash "$chk" 2>/dev/null)" || true
    [ -n "$out" ] || continue
    frag="$(printf '%s\n' "$out" | sed -n '1p')"
    rest="$(printf '%s\n' "$out" | sed -n '2,$p')"
    [ -n "$frag" ] && summary="${summary:+$summary · }$frag"
    [ -n "$rest" ] && action="${action}
$rest"
  done
fi

# status-line cache — always (re)write so a resolved staleness clears a prior warning. ---
# statusline.sh reads this: one line = the compact summary, empty file = all current.
if mkdir -p "$(dirname "$CACHE")" 2>/dev/null; then
  printf '%s\n' "$summary" > "$CACHE" 2>/dev/null || true
fi

# actionable summary -------------------------------------------------------------------
[ -n "$action" ] && printf '%s\n' "$action"
exit 0
