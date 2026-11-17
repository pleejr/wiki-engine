#!/usr/bin/env bash
# lock-lib.sh — the ONE way an engine script takes a lock. SOURCED, never executed.
#
# Every engine lock is a directory: whoever creates it holds it. That is only a lock if
# exactly one of several racing creators is told it succeeded — true of mkdir(2), and it
# USED to be true of every mkdir(1). It is not true of uutils coreutils, which Ubuntu
# 26.04 ships as /usr/bin/mkdir: its 0.10.0 mkdir let two or more of six racing processes "win"
# the same new directory on 70 of 300 rounds, measured on a hosted runner. Two
# SessionEnd captures then both appended (interleaved, duplicated blocks), and two
# integrates both held the vault lock. Nothing failed loudly; the lock simply stopped
# excluding anyone.
#
# So the lock is taken with mkdir(2) directly, through an interpreter that exposes it —
# perl first (essential on Debian/Ubuntu, shipped on macOS, ~5 ms to start), python3
# second. mkdir(1) is the last resort only, for a host with neither, and is no worse than
# what every caller did before.
#
# Callers:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "$SCRIPT_DIR/lock-lib.sh"
#   lock_mkdir "$LOCK" || <held by someone else>
#
# The CI step "Every lock is one mkdir(2)" races this against six contenders and greps
# bin/ for any lock still taken with a bare mkdir(1) test.

# lock_mkdir DIR — create DIR (its parent must exist); 0 iff THIS call created it.
lock_mkdir() {
  if command -v perl >/dev/null 2>&1; then
    perl -e 'exit(mkdir($ARGV[0]) ? 0 : 1)' "$1" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import os,sys
try: os.mkdir(sys.argv[1])
except OSError: sys.exit(1)' "$1" 2>/dev/null
  else
    mkdir "$1" 2>/dev/null
  fi
}
