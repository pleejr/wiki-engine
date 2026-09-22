#!/usr/bin/env bash
# session-preflight.sh — upfront version check for a SessionStart hook. Reports the
# wiki-engine status and, when it is stale, prints an ACTION-REQUIRED block telling the
# assistant to ASK the user before updating — the hook itself never prompts or changes
# anything:
#   - wiki-engine  — the running release vs the vault's .engine-version; the running
#                    release vs the newest tag on the engine's remote (rate-limited, see
#                    below); a leftover 1.x submodule or settings.json hook.
#
# THE UPDATE NUDGE. Until 2.0.0 this hook delegated to engine-version.sh and the banner
# said "update available". Plugin delivery removed that call along with the submodule, and
# nothing replaced it: the marketplace advances the plugin only when someone runs
# `claude plugin update`, so a machine could sit releases behind with every surface green.
# The check is back, on two rails. The NETWORK lookup is rate-limited to once per
# WIKI_ENGINE_CHECK_INTERVAL (default 86400s) and bounded by WIKI_ENGINE_NET_TIMEOUT; the
# COMPARISON runs every session against the cached tag, so the warning clears the moment
# the plugin moves rather than lingering until the cache expires. WIKI_ENGINE_UPDATE_CHECK=0
# disables the lookup outright, for a machine that must not reach the network at boot.
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
    action="${action}- wiki-engine: plugin $run_ver is older than the vault's .engine-version $req_ver. Offer to run: $(engine_update_remedy) (then restart).
"
    summary="${summary:+$summary · }engine ${run_ver}<${req_ver}"
  else
    echo "wiki-engine: the vault records $req_ver in .engine-version — its CI runs that tag until update.sh records $run_ver"
  fi
fi

# wiki-engine — the running release vs the newest release tag on the remote. ------------
# Two rails, deliberately separate: the NETWORK lookup is rate-limited and cached, the
# COMPARISON is recomputed every session from the cached tag. That is what makes the nudge
# self-clearing — update the plugin and the very next session reads `same` off the same
# cache with no network at all. Caching a verdict instead would keep nagging for a day
# after the update, which is the "constant warning" shape the engine already refuses.
UPD_CACHE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.wiki-engine-update"
if [ "${WIKI_ENGINE_UPDATE_CHECK:-1}" != "0" ]; then
  upd_ts=0; upd_tag=""
  if [ -f "$UPD_CACHE" ]; then
    IFS="$(printf '\t')" read -r upd_ts upd_tag < "$UPD_CACHE" 2>/dev/null || { upd_ts=0; upd_tag=""; }
    case "${upd_ts:-}" in ''|*[!0-9]*) upd_ts=0;; esac
  fi
  interval="${WIKI_ENGINE_CHECK_INTERVAL:-86400}"
  case "$interval" in ''|*[!0-9]*) interval=86400;; esac
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ "$now" -ge $((upd_ts + interval)) ] 2>/dev/null; then
    # 4 seconds, not engine-version.sh's default 10: this runs inside a 30s SessionStart
    # budget it shares with adoption, and a slow boot is a worse failure than a late nudge.
    fetched="$(WIKI_ENGINE_NET_TIMEOUT="${WIKI_ENGINE_NET_TIMEOUT:-4}" "$SCRIPT_DIR/engine-version.sh" --latest-tag 2>/dev/null)" || fetched=""
    # A failed lookup keeps the PREVIOUS tag and still stamps the attempt: an offline
    # machine must not pay the timeout every session, and must not lose a nudge it had.
    [ -n "$fetched" ] && upd_tag="$fetched"
    printf '%s\t%s\n' "$now" "$upd_tag" > "$UPD_CACHE" 2>/dev/null || true
  fi
  if [ -n "$upd_tag" ]; then
    run_tag="$(printf '%s' "$run_ver" | sed -E 's/-[0-9]+-g[0-9a-f]+$//')"
    case "$(engine_bump_level "$run_tag" "$upd_tag")" in
      MAJOR)
        echo "wiki-engine: ⚠ $upd_tag is released and this is $run_ver — a MAJOR bump; read the CHANGELOG migration first"
        action="${action}- wiki-engine: a MAJOR release ($upd_tag) is available and $run_ver is running. Tell the user and point at the CHANGELOG migration; do NOT update without their confirmation.
"
        summary="${summary:+$summary · }engine ${run_tag}→${upd_tag}"
        ;;
      minor|patch)
        echo "wiki-engine: ⚠ $upd_tag is released and this is $run_ver — update available"
        action="${action}- wiki-engine: $upd_tag is available and $run_ver is running. Offer to run: $(engine_update_remedy), then update.sh for the vault in the same session, then restart.
"
        summary="${summary:+$summary · }engine ${run_tag}→${upd_tag}"
        ;;
    esac
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
