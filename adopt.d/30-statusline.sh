#!/usr/bin/env bash
# 30-statusline.sh — adoption step: wire statusline.sh as the Claude Code status line, so
# the version preflight's verdict is USER-VISIBLE (a persistent row) instead of reaching
# only the assistant's context. Conservative via ensure-statusline.sh: sets ours when no
# statusLine exists, self-heals ours if the path drifts, and NEVER clobbers a foreign one
# the user configured themselves.
#
# Run by apply-adopt.sh with these exported: WIKI, ENGINE, CLAUDE_SETTINGS, ENSURE_HOOK,
# and ADOPT_CHECK (set when only reporting). Idempotent and add-only.
set -uo pipefail

: "${ENGINE:?}"

ENSURE_STATUSLINE="$(dirname "${ENSURE_HOOK:-$ENGINE/bin/ensure-hook.sh}")/ensure-statusline.sh"
[ -x "$ENSURE_STATUSLINE" ] || { echo "30-statusline: ensure-statusline.sh not found — skipping" >&2; exit 0; }

"$ENSURE_STATUSLINE" \
  --command "$ENGINE/bin/statusline.sh" \
  --marker  'engine/bin/statusline.sh' \
  --padding 2 \
  ${ADOPT_CHECK:+--check}
