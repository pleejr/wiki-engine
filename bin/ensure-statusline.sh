#!/usr/bin/env bash
# ensure-statusline.sh — idempotently ensure a `statusLine` command is set in a
# settings.json. The status-line sibling of ensure-hook.sh, and the primitive for opt-in
# statusline wiring — the status line is NOT auto-adopted (the banner via session-banner.sh
# is the default surface); run this yourself, or from your own adopt.d step, to enable it.
# Claude Code allows exactly ONE statusLine, so this cannot be additive the way hooks are;
# instead it is CONSERVATIVE:
#
#   * no statusLine present            -> set ours
#   * ours already present (by marker) -> update the command in place (self-heal path)
#   * a FOREIGN statusLine present     -> leave it untouched (the user's own wins)
#
# "Ours" is recognized by --marker, a substring of the command (e.g. the script path).
# Backs the file up before any write. Deterministic — plain jq + file writes, NEVER runs
# `claude` (safe from a hook). Exits 0 whether it changed anything or not so it can't block
# session start; a genuine error (bad JSON, unwritable file) exits non-zero instead.
#
# On a change it prints one line to stdout:   set statusLine -> <command>
# On a no-op (already ours, or a foreign one left alone) it prints nothing.
#
# Usage:
#   ensure-statusline.sh --command '/v/engine/bin/statusline.sh' \
#                        --marker 'engine/bin/statusline.sh' \
#                        [--padding 2] [--settings ~/.claude/settings.json] [--check]
set -uo pipefail

COMMAND=""; MARKER=""; PADDING=""; CHECK=0
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    --command)  COMMAND="$2"; shift 2;;
    --marker)   MARKER="$2"; shift 2;;
    --padding)  PADDING="$2"; shift 2;;
    --settings) SETTINGS="$2"; shift 2;;
    --check)    CHECK=1; shift;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "ensure-statusline: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$COMMAND" ] || { echo "ensure-statusline: --command required" >&2; exit 2; }
[ -n "$MARKER" ]  || MARKER="$COMMAND"   # default: recognize ourselves by exact command
command -v jq >/dev/null 2>&1 || { echo "ensure-statusline: jq not found; cannot set statusLine" >&2; exit 2; }

# Ensure the settings file exists as a JSON object (never create it in --check mode).
if [ ! -f "$SETTINGS" ]; then
  if [ "$CHECK" -eq 1 ]; then
    current='{}'
  else
    mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null || { echo "ensure-statusline: cannot create $(dirname "$SETTINGS")" >&2; exit 2; }
    printf '{}\n' > "$SETTINGS"
    current="$(cat "$SETTINGS")"
  fi
else
  jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "ensure-statusline: $SETTINGS is not valid JSON — refusing to edit" >&2; exit 2; }
  current="$(cat "$SETTINGS")"
fi

# Decide: is there a foreign statusLine we must not clobber?
existing_cmd="$(printf '%s' "$current" | jq -r '.statusLine.command // empty' 2>/dev/null)"
if [ -n "$existing_cmd" ] && ! printf '%s' "$existing_cmd" | grep -qF "$MARKER"; then
  exit 0   # someone else's statusLine — respect it, do nothing
fi

updated="$(
  printf '%s' "$current" | jq --arg cmd "$COMMAND" --arg pad "$PADDING" '
    .statusLine = ({type:"command", command:$cmd}
                   + (if $pad == "" then {} else {padding:($pad|tonumber)} end))
  '
)" || { echo "ensure-statusline: jq transform failed on $SETTINGS" >&2; exit 2; }

# No change? Compare canonical forms; stay silent and exit 0.
if [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$updated" | jq -S .)" ]; then
  exit 0
fi

# A change is needed. In --check mode, report it but write nothing.
if [ "$CHECK" -eq 1 ]; then
  printf 'set statusLine -> %s\n' "$COMMAND"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak" 2>/dev/null || true
printf '%s\n' "$updated" > "$SETTINGS" || { echo "ensure-statusline: could not write $SETTINGS" >&2; exit 2; }

printf 'set statusLine -> %s\n' "$COMMAND"
exit 0
