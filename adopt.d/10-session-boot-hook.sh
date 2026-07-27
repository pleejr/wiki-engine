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

# Never wire a REAL ~/.claude/settings.json boot hook for an EPHEMERAL vault (test / CI /
# scratchpad). ensure-hook keys the boot command on WIKI_PATH, so a throwaway vault leaves a
# permanent, un-dedupable SessionStart hook that fires an extra banner every session. If the
# caller isolated CLAUDE_SETTINGS to its own temp file, wiring is safe (it lands there);
# otherwise skip silently. See [[lesson-ephemeral-vault-settings-pollution]].
case "$WIKI" in
  "${TMPDIR:-/nonexistent-tmpdir}"*|/private/tmp/*|/tmp/*|/var/folders/*|*/scratchpad/*)
    # Isolated means "points somewhere OTHER than the machine's real settings" — not
    # merely "the variable is set". apply-adopt.sh exports CLAUDE_SETTINGS
    # unconditionally, defaulting it to the real file, so a `[ -n ... ]` test here could
    # never be false and this guard never fired: a throwaway vault wired a permanent
    # SessionStart hook into the real settings every time.
    _real="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    [ "${CLAUDE_SETTINGS:-$_real}" != "$_real" ] || exit 0 ;;
esac

cmd="WIKI_PATH=$WIKI $ENGINE/bin/session-boot.sh"

"$ENSURE_HOOK" \
  --event SessionStart \
  --matcher 'startup|resume' \
  --command "$cmd" \
  --status 'engine boot' \
  ${ADOPT_CHECK:+--check}
