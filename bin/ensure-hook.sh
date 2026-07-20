#!/usr/bin/env bash
# ensure-hook.sh — idempotently ensure a Claude Code hook command is present in a
# settings.json. The reusable primitive behind engine feature auto-adoption
# (adopt.d/*.sh call this): ADD-ONLY, never edits or removes an existing hook, and
# backs the file up before any write. Matches the target hook by exact command string,
# so re-running is a no-op once wired.
#
# Deterministic — plain jq + file writes, NEVER runs `claude` (safe from a hook per the
# engine's hard rule). Exits 0 whether it changed anything or not, so it can't block a
# session start; a genuine error (bad JSON, unwritable file) exits non-zero instead.
#
# On a change it prints one line to stdout:   wired <event>[<matcher>] -> <command>
# On a no-op it prints nothing.
#
# Usage:
#   ensure-hook.sh --event SessionStart --matcher 'startup|resume' \
#                  --command 'WIKI_PATH=/v /v/engine/bin/session-boot.sh' \
#                  [--status 'engine boot'] [--settings ~/.claude/settings.json]
#
# --settings defaults to $CLAUDE_SETTINGS, else ~/.claude/settings.json.
set -uo pipefail

EVENT=""; MATCHER=""; COMMAND=""; STATUS=""; CHECK=0
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    --event)    EVENT="$2"; shift 2;;
    --matcher)  MATCHER="$2"; shift 2;;
    --command)  COMMAND="$2"; shift 2;;
    --status)   STATUS="$2"; shift 2;;
    --settings) SETTINGS="$2"; shift 2;;
    --check)    CHECK=1; shift;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "ensure-hook: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$EVENT" ]   || { echo "ensure-hook: --event required" >&2; exit 2; }
[ -n "$COMMAND" ] || { echo "ensure-hook: --command required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ensure-hook: jq not found; cannot wire $EVENT hook" >&2; exit 2; }

# Ensure the settings file exists as a JSON object (never create it in --check mode).
if [ ! -f "$SETTINGS" ]; then
  if [ "$CHECK" -eq 1 ]; then
    current='{}'
  else
    mkdir -p "$(dirname "$SETTINGS")" 2>/dev/null || { echo "ensure-hook: cannot create $(dirname "$SETTINGS")" >&2; exit 2; }
    printf '{}\n' > "$SETTINGS"
    current="$(cat "$SETTINGS")"
  fi
else
  jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "ensure-hook: $SETTINGS is not valid JSON — refusing to edit" >&2; exit 2; }
  current="$(cat "$SETTINGS")"
fi

updated="$(
  printf '%s' "$current" | jq --arg ev "$EVENT" --arg m "$MATCHER" --arg cmd "$COMMAND" --arg sm "$STATUS" '
    def newhook: {type:"command", command:$cmd} + (if $sm == "" then {} else {statusMessage:$sm} end);
    .hooks = (.hooks // {})
    | .hooks[$ev] = (.hooks[$ev] // [])
    # ensure a matcher entry exists ("" matches an entry that omits .matcher too)
    | (if any(.hooks[$ev][]; (.matcher // "") == $m) then .
       else .hooks[$ev] += [ (if $m == "" then {hooks:[]} else {matcher:$m, hooks:[]} end) ] end)
    # add the command into that matcher entry if not already present (by exact command)
    | .hooks[$ev] |= map(
        if (.matcher // "") == $m then
          .hooks = (.hooks // [])
          | (if any(.hooks[]; .command == $cmd) then . else .hooks += [newhook] end)
        else . end)
  '
)" || { echo "ensure-hook: jq transform failed on $SETTINGS" >&2; exit 2; }

# No change? Compare canonical forms; stay silent and exit 0.
if [ "$(printf '%s' "$current" | jq -S .)" = "$(printf '%s' "$updated" | jq -S .)" ]; then
  exit 0
fi

# A change is needed. In --check mode, report it but write nothing.
if [ "$CHECK" -eq 1 ]; then
  printf 'wired %s[%s] -> %s\n' "$EVENT" "$MATCHER" "$COMMAND"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.bak" 2>/dev/null || true
printf '%s\n' "$updated" > "$SETTINGS" || { echo "ensure-hook: could not write $SETTINGS" >&2; exit 2; }

printf 'wired %s[%s] -> %s\n' "$EVENT" "$MATCHER" "$COMMAND"
exit 0
