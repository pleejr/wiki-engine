#!/usr/bin/env bash
# ensure-hook.sh — idempotently ensure a Claude Code hook command is present in a
# settings.json. The reusable primitive behind engine feature auto-adoption
# (adopt.d/*.sh call this): ADD-ONLY, never edits or removes an existing hook, and
# backs the file up before any write. Matches the target hook by exact command string,
# so re-running is a no-op once wired.
#
# Matcher coverage: a hook is "already wired" when the exact command is present under a
# matcher whose event-token set (split on `|`, an empty/absent matcher = match-all)
# COVERS — is a superset of, or equal to — the requested matcher. So requesting
# `startup|resume` when the user already runs the command under `startup|resume|clear`
# is a no-op, not a second entry that runs the command twice. (Add-only can't collapse
# the inverse — an existing matcher NARROWER than the request — without editing the
# user's hook, so that partial-overlap case still appends; broaden the request instead.)
#
# Exactly ONE entry receives the command: the FIRST whose matcher equals the request. An
# event may legitimately hold several entries sharing a matcher (that is one hook group
# each), and appending to all of them wires the command — and so runs it — once per group.
#
# Duplicate report: if the command is ALREADY present in more than one entry covering the
# request, every one of them fires, so the hook runs N times per event. That is reported
# on stderr, in --check and in write mode alike. Add-only cannot repair it — removing an
# entry is the one thing this tool must never do — so the report is the whole remedy and
# a human resolves it by hand. Disjoint matchers (`startup` and `resume`) are NOT a
# duplicate: no single event instance matches both, so the command still runs once. The
# partial-overlap append above IS one when later queried with the narrower matcher — a
# `startup` entry beside a `startup|resume` entry really does run twice on startup — so
# that report is correct, not a false positive, and broadening the request is the fix.
#
# Timeout: `--timeout N` writes `"timeout": N` (seconds) beside type/command. The host
# aborts a hook that outruns its window, and the window a hook inherits by DEFAULT is the
# host's, not one the engine chose — a SessionEnd hook was observed cancelled at about one
# second, which is less than a workspace-wide `rag-capture.sh` scan takes. So a slow
# deterministic hook has to state its own budget, and before this option the tool could not
# express the field at all. Add-only still holds: a command already wired WITHOUT a
# sufficient timeout is REPORTED, never edited — see the report below.
#
# Deterministic — plain jq + file writes, NEVER runs `claude` (safe from a hook per the
# engine's hard rule). Exits 0 whether it changed anything or not, so it can't block a
# session start; a genuine error (bad JSON, unwritable file) exits non-zero instead.
#
# On a change it prints one line to stdout:   wired <event>[<matcher>] -> <command>
# On a no-op it prints nothing (bar a duplicate or timeout report, neither of which is a
# no-op finding).
#
# Usage:
#   ensure-hook.sh --event SessionStart --matcher 'startup|resume' \
#                  --command 'WIKI_PATH=/v /v/engine/bin/session-boot.sh' \
#                  [--status 'engine boot'] [--timeout 30] \
#                  [--settings ~/.claude/settings.json]
#
# --settings defaults to $CLAUDE_SETTINGS, else ~/.claude/settings.json.
set -uo pipefail

EVENT=""; MATCHER=""; COMMAND=""; STATUS=""; CHECK=0; TIMEOUT=""; TIMEOUT_SET=0
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    --event)    EVENT="$2"; shift 2;;
    --matcher)  MATCHER="$2"; shift 2;;
    --command)  COMMAND="$2"; shift 2;;
    --status)   STATUS="$2"; shift 2;;
    --timeout)  TIMEOUT="$2"; TIMEOUT_SET=1; shift 2;;
    --settings) SETTINGS="$2"; shift 2;;
    --check)    CHECK=1; shift;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "ensure-hook: unknown arg: $1" >&2; exit 2;;
  esac
done

[ -n "$EVENT" ]   || { echo "ensure-hook: --event required" >&2; exit 2; }
[ -n "$COMMAND" ] || { echo "ensure-hook: --command required" >&2; exit 2; }
# Refuse a malformed timeout rather than writing it. A hook carrying `"timeout": "30"` or
# `"timeout": 0` is worse than one carrying none: the field is present, so it reads as
# handled, while the host falls back to its default or cancels immediately.
if [ "$TIMEOUT_SET" -eq 1 ]; then
  case "$TIMEOUT" in
    ''|*[!0-9]*|0*) echo "ensure-hook: --timeout must be a positive whole number of seconds, got '$TIMEOUT'" >&2; exit 2;;
  esac
fi
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

# Shared jq prelude. `covering` is applied to ONE event's entry list and returns every
# entry that would fire for the requested matcher AND already carries the exact command.
# It is defined once and used by both the already-wired guard and the duplicate count on
# purpose: the guard asking one question while the writer answered a different one is
# precisely the defect this file shipped with.
JQ_LIB='
    # matcher -> token set; null means "match all" (empty/absent matcher)
    def toks($x): (($x // "") | if . == "" then null else split("|") end);
    def covering($want; $cmd): [ .[] | select(
        ( toks(.matcher) as $et
          | if $et == null then true             # entry matches all events
            elif $want == null then false        # want=all but entry is specific
            else ($want - $et) == [] end )       # want tokens ⊆ entry tokens
        and any((.hooks // [])[]; .command == $cmd) ) ];
'

# How many entries already run this command for the requested matcher? Two or more means
# the hook fires that many times per event — the state this tool used to create silently
# and then report as correctly wired. Read from the PRE-write file, because the writer
# below can no longer produce it: what remains is a hand edit, a second tool, a script
# from before the fix, or the documented partial-overlap append seen through a narrower
# matcher — all four genuinely double-fire, so all four are worth saying out loud.
dupes="$(
  printf '%s' "$current" | jq --arg ev "$EVENT" --arg m "$MATCHER" --arg cmd "$COMMAND" "$JQ_LIB"'
    ($m | if . == "" then null else split("|") end) as $want
    | ((.hooks // {})[$ev] // []) | covering($want; $cmd) | length
  '
)" || { echo "ensure-hook: jq duplicate scan failed on $SETTINGS" >&2; exit 2; }
case "$dupes" in ''|*[!0-9]*) dupes=0;; esac
if [ "$dupes" -gt 1 ]; then
  # Reported, never repaired: removing an entry is the one thing an add-only tool must not
  # do, and guessing which of the user's two entries is the redundant one is exactly the
  # edit it promises never to make. So say it plainly and leave the file alone.
  printf 'ensure-hook: duplicate — %s[%s] runs this command %s times per event: %s\n' \
    "$EVENT" "$MATCHER" "$dupes" "$COMMAND" >&2
  printf 'ensure-hook: add-only cannot remove one; edit %s so a single entry carries it\n' \
    "$SETTINGS" >&2
fi

# Already wired, but without a big enough timeout? Add-only cannot repair that either, and
# silence is the worst answer available: the hook stays wired, reports itself wired, and is
# cancelled by the host on every slow run, so the only observable is a buffer that never
# grows. Every vault that adopted the pre-timeout snippet is in exactly this state, so the
# report is what reaches them. A LARGER existing value is the operator having already solved
# it — say nothing there, or the message is noise on the vaults that got it right.
if [ "$TIMEOUT_SET" -eq 1 ] && [ "$dupes" -gt 0 ]; then
  have="$(
    printf '%s' "$current" | jq -r --arg ev "$EVENT" --arg m "$MATCHER" --arg cmd "$COMMAND" "$JQ_LIB"'
      ($m | if . == "" then null else split("|") end) as $want
      | ((.hooks // {})[$ev] // []) | covering($want; $cmd)
      | [ .[].hooks[]? | select(.command == $cmd) | (.timeout // 0) ]
      | if length == 0 then 0 else min end
    '
  )" || { echo "ensure-hook: jq timeout scan failed on $SETTINGS" >&2; exit 2; }
  case "$have" in ''|*[!0-9]*) have=0;; esac
  if [ "$have" -lt "$TIMEOUT" ]; then
    if [ "$have" -eq 0 ]; then
      printf 'ensure-hook: %s[%s] is already wired without a timeout: %s\n' \
        "$EVENT" "$MATCHER" "$COMMAND" >&2
    else
      printf 'ensure-hook: %s[%s] is already wired with timeout %s, under the %s this hook needs: %s\n' \
        "$EVENT" "$MATCHER" "$have" "$TIMEOUT" "$COMMAND" >&2
    fi
    printf 'ensure-hook: the host cancels a hook that outruns its window, and a cancelled hook\n' >&2
    printf 'ensure-hook:   is silent — add "timeout": %s to that entry in %s\n' \
      "$TIMEOUT" "$SETTINGS" >&2
  fi
fi

updated="$(
  printf '%s' "$current" | jq --arg ev "$EVENT" --arg m "$MATCHER" --arg cmd "$COMMAND" --arg sm "$STATUS" --arg to "$TIMEOUT" "$JQ_LIB"'
    def newhook: {type:"command", command:$cmd}
      + (if $sm == "" then {} else {statusMessage:$sm} end)
      + (if $to == "" then {} else {timeout:($to | tonumber)} end);
    ($m | if . == "" then null else split("|") end) as $want
    | .hooks = (.hooks // {})
    | .hooks[$ev] = (.hooks[$ev] // [])
    # Already satisfied? Exact command present under a matcher that COVERS $want
    # (its token set is a superset, or it is match-all). If so, leave the file untouched.
    | if (.hooks[$ev] | covering($want; $cmd) | length) > 0
      then .
      else
        # ensure a matcher entry exists ("" matches an entry that omits .matcher too)
        (if any(.hooks[$ev][]; (.matcher // "") == $m) then .
         else .hooks[$ev] += [ (if $m == "" then {hooks:[]} else {matcher:$m, hooks:[]} end) ] end)
        # Add the command to exactly ONE entry — the first whose matcher equals the request.
        # A `map` here appended to EVERY matching entry, so an event holding two entries
        # that share the matcher (two hook groups, an ordinary shape) got the command twice
        # and ran it twice per event. Resolve the index, then modify only that index.
        | ( [ .hooks[$ev] | to_entries[] | select((.value.matcher // "") == $m) | .key ]
            | first ) as $i
        | .hooks[$ev][$i] |= (
            .hooks = (.hooks // [])
            | if any(.hooks[]; .command == $cmd) then . else .hooks += [newhook] end)
      end
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
