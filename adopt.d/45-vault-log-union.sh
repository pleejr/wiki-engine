#!/usr/bin/env bash
# 45-vault-log-union.sh — adoption step: merge the vault's log.md with git's `union` driver,
# ADD-ONLY.
#
# log.md is append-only and every session that does work appends to it. Two sessions that
# each append a line therefore conflict at the same place when the second one integrates —
# a textual conflict with no real disagreement in it, and the one thing every parallel
# distill would trip over. The `union` driver keeps both sides' lines, which is exactly the
# right resolution for an append-only file (main's line first, then the session's).
#
# ADD-ONLY: a vault's .gitattributes is the vault's file. If log.md already resolves to
# `merge=union` nothing is written; otherwise one line (with its reason) is appended. The
# file is tracked, so the change shows up for the operator to commit with the adoption.
#
# Run by apply-adopt.sh with WIKI / ENGINE exported (ADOPT_CHECK set when only reporting).
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"
# shellcheck source=bin/adopt-lib.sh
. "${ADOPT_LIB:?}" || exit 3

GA="$WIKI/.gitattributes"
CHECK="${ADOPT_CHECK:-}"

# CONSUMER STATE — no git repository, no merge to configure.
git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || exit 0

[ "$(git -C "$WIKI" check-attr merge -- log.md 2>/dev/null | sed 's/.*: //')" = "union" ] && exit 0

if [ -n "$CHECK" ]; then
  echo "adopt: would append 'log.md merge=union' to $GA (add-only)"
  exit 0
fi
fresh=0; [ -f "$GA" ] || fresh=1    # tested BEFORE the append, which would create the file
{
  [ "$fresh" = 1 ] && printf '# Vault attributes. Engine-managed entries are appended by adoption (add-only).\n'
  printf '# log.md is append-only: concurrent sessions each add a line, and union keeps both.\n'
  printf 'log.md merge=union\n'
} >> "$GA"
echo "adopt: appended 'log.md merge=union' to .gitattributes — commit it with this adoption"
exit 0
