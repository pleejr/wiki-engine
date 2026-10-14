#!/usr/bin/env bash
# session-processes.sh — list the OS processes this Claude Code session is still running, so
# distill's close verdict rests on a measurement rather than on the model's task list.
#
# The session is the nearest ancestor that is $CLAUDE_PID, else the nearest ancestor whose
# command name is `claude`. Everything is read from ONE `ps` snapshot of that tree:
#   shell    a shell the session started for a tool call, foreground or background
#   work     anything a session shell started, at any depth
#   harness  anything else the session started itself (an MCP server, a keep-awake, the status
#            line or a hook script), and what runs under it; listed as information — it ends
#            with the session and is not the session's work
# Tool shells are told from the harness's own shells by a marker in their command line (Claude
# Code starts each from a shell snapshot). The marker is trusted only when the audit's OWN shell
# carries it — that shell is a tool shell by construction. When it does not, the marker has
# changed and every shell the session started counts as a tool shell: over-reporting is the
# safe direction, since a missed tool shell would read as nothing running.
#   orphan   a process whose parent died, reparented outside the tree, that still carries this
#            session's CLAUDE_CODE_SESSION_ID. Found only where the environment of another
#            process is readable (/proc on Linux); elsewhere the scan says it did not run.
# The shell running this audit, and everything under it, is left out: it is the measurement.
# Nothing outside the session's tree is listed — a peer session has another root and another
# session id. This tool lists only; deciding what is legitimate, and stopping it, is distill's.
#
# Output: one line per process, then exactly one AUDIT line:
#   PROC <pid> <kind> elapsed=<[[dd-]hh:]mm:ss> parent=<ppid> <command>
#   AUDIT — examined <n> process(es) under session <pid>: <w> session-owned, <h> harness; orphan scan: <ran|unavailable (<why>)>
#
# Usage: session-processes.sh
# Exit: 0 nothing session-owned running · 1 session-owned processes running · 2 no session found
# Deterministic: reads `ps` and /proc only; never signals a process, never spawns `claude`.
set -uo pipefail

case "${1:-}" in
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  "") ;;
  *) echo "session-processes: unknown arg: $1" >&2; exit 2;;
esac

# One snapshot; every later question is asked of it, so the tree cannot change between reads.
# A process's name is the basename of its first argument: `comm` would be simpler, but macOS
# prints it as a full path that can hold spaces, which shifts every field after it.
snap="$(ps -A -o pid= -o ppid= -o stat= -o etime= -o args= 2>/dev/null)" \
  || { echo "session-processes: ps failed — cannot audit" >&2; exit 2; }

# Find the root by walking up from this script's own pid.
read -r root chain < <(awk -v me="$$" -v want="${CLAUDE_PID:-}" '
  { ppid[$1]=$2; c=$5; sub(/.*\//, "", c); comm[$1]=c }
  END {
    p=me; chain=""
    while (p != "" && p > 1) {
      if ((want != "" && p == want) || (p != me && comm[p] == "claude")) { print p, chain; exit }
      chain = chain " " p; p = ppid[p]
    }
  }' <<<"$snap")
if [ -z "${root:-}" ]; then
  echo "session-processes: no Claude Code session above this shell (no \$CLAUDE_PID ancestor, no \`claude\` ancestor) — nothing to audit" >&2
  exit 2
fi

# The audit's own branch: the chain element that is a direct child of the root. Its subtree is
# this measurement (this script, its ps, its awk) and is excluded.
self_top=""
for p in $chain; do
  [ "$(awk -v p="$p" '$1==p {print $2; exit}' <<<"$snap")" = "$root" ] && self_top="$p"
done

# The marker test, validated on the audit's own shell.
marker="shell-snapshots/snapshot-"   # the marker statusline.sh's activity segment counts by
self_args="$(awk -v p="${self_top:-none}" '$1==p {print; exit}' <<<"$snap")"
case "$self_args" in *"$marker"*) ;; *) marker="";; esac

# Orphans: only where another process's environment is readable. The match is the exact
# session id, so a peer session's orphan is never named.
orphans="" oscan="unavailable (no CLAUDE_CODE_SESSION_ID in this environment)"
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  if [ -r /proc/self/environ ]; then
    oscan="ran"
    for d in /proc/[0-9]*; do
      p="${d#/proc/}"
      [ -r "$d/environ" ] || continue
      # Captured, then matched: `| grep -q` under pipefail can report a miss through SIGPIPE.
      env_of="$(tr '\0' '\n' < "$d/environ" 2>/dev/null)"
      case $'\n'"$env_of"$'\n' in *$'\n'"CLAUDE_CODE_SESSION_ID=$CLAUDE_CODE_SESSION_ID"$'\n'*) orphans="$orphans $p";; esac
    done
  else
    oscan="unavailable (this platform does not expose another process's environment)"
  fi
fi

out="$(awk -v root="$root" -v self="${self_top:-none}" -v orphans="$orphans" -v marker="$marker" '
  function isshell(c) { return c ~ /^-?(sh|bash|zsh|dash|ksh|fish)$/ }
  function istool(p) { return isshell(comm[p]) && (marker == "" || index(args[p], marker) > 0) }
  function under(p,   q, n) {          # 1 if p descends from root (p != root)
    q = p; n = 0
    while (q != "" && q > 1 && n < 4096) { if (ppid[q] == root) return q; q = ppid[q]; n++ }
    return ""
  }
  {
    pid=$1; ppid[pid]=$2; stat[pid]=$3; et[pid]=$4; c=$5; sub(/.*\//, "", c); comm[pid]=c
    a=$0; for (i = 1; i <= 4; i++) sub(/^[ \t]*[^ \t]+/, "", a); sub(/^[ \t]+/, "", a); args[pid]=a
    order[++n]=pid
  }
  END {
    split(orphans, o, " "); for (i in o) isorph[o[i]]=1
    for (i = 1; i <= n; i++) {
      p = order[i]
      if (p == root || stat[p] ~ /^Z/) continue
      top = under(p)
      if (top == self) continue
      if (top != "") {
        if (p == top) kind = istool(p) ? "shell" : "harness"
        else          kind = istool(top) ? "work" : "harness"
      } else if (isorph[p]) kind = "orphan"
      else continue
      cmd = args[p]
      # A tool shell carries a long preamble before the command it was asked to run.
      if (kind == "shell" && match(cmd, /eval \047/)) { cmd = substr(cmd, RSTART + 6); sub(/\047 < \/dev\/null.*$/, "", cmd); gsub(/\047"\047"\047/, "\047", cmd) }
      if (length(cmd) > 200) cmd = substr(cmd, 1, 197) "..."
      printf "PROC %s %s elapsed=%s parent=%s %s\n", p, kind, et[p], ppid[p], cmd
    }
  }' <<<"$snap")"

owned=0 harness=0 total=0
if [ -n "$out" ]; then
  printf '%s\n' "$out"
  total="$(grep -c '^PROC ' <<<"$out")"
  harness="$(grep -c '^PROC [0-9]* harness ' <<<"$out")"
  owned=$((total - harness))
fi
echo "AUDIT — examined $total process(es) under session $root: $owned session-owned, $harness harness; orphan scan: $oscan"
[ "$owned" -eq 0 ]
