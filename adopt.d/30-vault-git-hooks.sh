#!/usr/bin/env bash
# 30-vault-git-hooks.sh — adoption step: install the vault's pre-commit gate and point
# git at it, so the concurrency guard and the vault invariants are enforced by default
# rather than by remembering.
#
# ADD-ONLY. An existing .githooks/pre-commit is never overwritten — a vault may have
# customized it, and silently replacing a hook someone wrote is the kind of surprise that
# gets hooks disabled entirely. When one exists but does not call the guard, this reports
# the one line to add and moves on.
#
# Run by apply-adopt.sh with WIKI / ENGINE exported (ADOPT_CHECK set when only reporting).
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"

TMPL="$ENGINE/../scaffold/pre-commit.tmpl"
HOOKDIR="$WIKI/.githooks"
HOOK="$HOOKDIR/pre-commit"
CHECK="${ADOPT_CHECK:-}"

git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || exit 0
[ -f "$TMPL" ] || exit 0

if [ ! -f "$HOOK" ]; then
  if [ -n "$CHECK" ]; then
    echo "adopt: would install $HOOK (vault gate + concurrency guard)"
  else
    mkdir -p "$HOOKDIR" && cp "$TMPL" "$HOOK" && chmod +x "$HOOK" \
      && echo "adopt: installed $HOOK (vault gate + concurrency guard)"
  fi
elif ! grep -q 'vault-worktree.sh' "$HOOK" 2>/dev/null; then
  # Present but predates the guard. Report rather than edit: this file is the vault's.
  echo "adopt: NOTE — $HOOK exists but does not run the concurrency guard."
  echo "adopt:   Add before the lint call, so a commit in the canonical checkout is refused:"
  echo "adopt:     CANON=\"\$(cd \"\$(git rev-parse --git-common-dir)/..\" && pwd)\""
  echo "adopt:     WIKI_PATH=\"\$CANON\" \"\$CANON/engine/bin/vault-worktree.sh\" guard || exit 1"
fi

# Point git at the hooks dir. Only set it when unset or already ours — never steal a
# hooksPath a vault deliberately aimed somewhere else.
cur="$(git -C "$WIKI" config --local core.hooksPath 2>/dev/null || true)"
if [ -z "$cur" ]; then
  if [ -n "$CHECK" ]; then
    echo "adopt: would set core.hooksPath=.githooks in $WIKI"
  else
    git -C "$WIKI" config core.hooksPath .githooks \
      && echo "adopt: set core.hooksPath=.githooks"
  fi
elif [ "$cur" != ".githooks" ]; then
  echo "adopt: NOTE — core.hooksPath is '$cur', not .githooks; leaving it alone"
fi
exit 0
