#!/usr/bin/env bash
# 40-session-banner-hook.sh — adoption step: wire session-banner.sh as a SessionStart hook
# so the version verdict is shown to the USER in-session at start (via the systemMessage
# channel — no "hook error" heading). Self-heals: if the hook is ever missing, the next
# adopt run puts it back.
#
# Run by apply-adopt.sh with these exported: WIKI, ENGINE, CLAUDE_SETTINGS, ENSURE_HOOK,
# and ADOPT_CHECK (set when only reporting). Idempotent and add-only via ensure-hook.sh.
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"; : "${ENSURE_HOOK:?}"

cmd="WIKI_PATH=$WIKI $ENGINE/bin/session-banner.sh"

"$ENSURE_HOOK" \
  --event SessionStart \
  --matcher 'startup|resume' \
  --command "$cmd" \
  --status 'version banner' \
  ${ADOPT_CHECK:+--check}
