#!/usr/bin/env bash
# 10-session-boot-hook.sh — adoption step: wire session-boot.sh as a SessionStart hook.
#
# session-boot.sh is the single durable entrypoint the engine owns; once it is a
# SessionStart hook, every later feature auto-adopts through apply-adopt.sh without any
# further settings.json wiring. This step self-heals that entrypoint: if it is ever
# missing (fresh machine, reset settings), the next adopt run puts it back.
#
# Run by apply-adopt.sh with these exported: WIKI, ENGINE, CLAUDE_SETTINGS, ENSURE_HOOK,
# and ADOPT_CHECK (set when only reporting). Idempotent and add-only via ensure-hook.sh.
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"; : "${ENSURE_HOOK:?}"
# shellcheck source=bin/adopt-lib.sh
. "${ADOPT_LIB:?}" || exit 3

# ENGINE ASSETS — unconditional, above the ephemeral guard. Both were unguarded: a
# missing session-boot.sh would have been wired into settings.json as a hook command
# pointing at nothing, which fails once per session start and is reported nowhere.
require_engine_asset "$ENGINE/bin/session-boot.sh" file "the engine's SessionStart entrypoint"
require_engine_asset "$ENSURE_HOOK" file "the add-only hook writer"

# Never wire a REAL settings.json boot hook for an EPHEMERAL vault (test / CI / scratchpad):
# ensure-hook keys the command on WIKI_PATH, so a throwaway vault leaves a permanent,
# un-dedupable SessionStart hook behind. See [[lesson-ephemeral-vault-settings-pollution]].
# apply-adopt.sh decides this once (see ADOPT_WIRE_SETTINGS there). Deliberately NOT
# re-derived here: the two previous in-step versions of this test both failed silently —
# one could never be false, the other missed CI temp paths.
[ "${ADOPT_WIRE_SETTINGS:-1}" = "1" ] || exit 0

# Plugin delivery: the plugin's hooks/hooks.json carries SessionStart. Adding a settings
# entry would boot twice. ensure-hook is add-only by design, so a legacy entry is left for
# the operator to delete; session-boot.sh already stays silent when it fires beside the
# plugin, so leaving it costs one no-op per session, not a double boot.
if [ "${ADOPT_PLUGIN:-0}" = "1" ]; then
  if grep -q 'engine/bin/session-boot.sh' "${CLAUDE_SETTINGS:-/nonexistent}" 2>/dev/null; then
    echo "note: wiki-engine plugin is enabled; the settings.json SessionStart entry running engine/bin/session-boot.sh is now redundant and can be deleted"
  fi
  exit 0
fi

cmd="WIKI_PATH=$WIKI $ENGINE/bin/session-boot.sh"

"$ENSURE_HOOK" \
  --event SessionStart \
  --matcher 'startup|resume' \
  --command "$cmd" \
  --status 'engine boot' \
  ${ADOPT_CHECK:+--check}
