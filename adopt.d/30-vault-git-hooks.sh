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
. "${ADOPT_LIB:?}" || exit 3

TMPL="$ENGINE/scaffold/pre-commit"
HOOKDIR="$WIKI/.githooks"
HOOK="$HOOKDIR/pre-commit"
CHECK="${ADOPT_CHECK:-}"

# ENGINE ASSET — unconditional, and deliberately ABOVE the git-repo guard below. This
# line used to read `[ -f "$TMPL" ] || exit 0` against `$ENGINE/../scaffold/pre-commit`,
# one directory too high (ENGINE is the engine ROOT), so it pointed into the consumer's
# vault root, found nothing, and exited 0 — for four minor releases, on every vault.
require_engine_asset "$TMPL" file "the vault's pre-commit gate template"

# CONSUMER STATE — a vault that isn't a git repo has no hooks to install. Genuine no-op.
git -C "$WIKI" rev-parse --git-dir >/dev/null 2>&1 || exit 0

if [ ! -f "$HOOK" ]; then
  if [ -n "$CHECK" ]; then
    echo "adopt: would install $HOOK (vault gate + concurrency guard)"
  else
    mkdir -p "$HOOKDIR" && cp "$TMPL" "$HOOK" && chmod +x "$HOOK" \
      && echo "adopt: installed $HOOK (vault gate + concurrency guard)"
  fi
else
  if ! grep -q 'vault-worktree.sh' "$HOOK" 2>/dev/null; then
    # Present but predates the guard. Report rather than edit: this file is the vault's.
    echo "adopt: NOTE — $HOOK exists but does not run the concurrency guard."
    echo "adopt:   Add before the lint call, so a commit in the canonical checkout is refused:"
    echo "adopt:     CANON=\"\$(cd \"\$(git rev-parse --git-common-dir)/..\" && pwd)\""
    echo "adopt:     WIKI_PATH=\"\$CANON\" \"\$CANON/engine/bin/vault-worktree.sh\" guard || exit 1"
  fi
  if ! grep -q 'git-common-dir' "$HOOK" 2>/dev/null; then
    # A hook that resolves engine/ from `git rev-parse --show-toplevel` is SILENTLY
    # INERT in a worktree: a linked worktree never carries the engine/ submodule, so the
    # "engine not initialized, skipping" branch fires every time. Since `checkpoint`
    # commits from a worktree by design, such a vault has been running its gate on
    # exactly the commits that bypass it.
    echo "adopt: WARNING — $HOOK appears to resolve engine/ from the WORKTREE root."
    echo "adopt:   A worktree has no engine/ submodule, so the gate silently skips there —"
    echo "adopt:   and checkpoint commits from a worktree. Resolve the canonical root instead:"
    echo "adopt:     CANON=\"\$(cd \"\$(git rev-parse --git-common-dir)/..\" && pwd)\""
    echo "adopt:   then use \"\$CANON/engine/bin/...\" for both the guard and lint."
    echo "adopt:   Reference implementation: $TMPL"
  fi
fi

# Point git at the hooks dir, by ABSOLUTE path. A relative `.githooks` — which is what
# this step used to write — is resolved by git against the working tree of the checkout
# making the commit, so inside a linked worktree it means `<worktree>/.githooks`. That
# directory does not exist: `.githooks/` is created by this step and never committed
# (adoption does not commit into a consumer's vault), so it lives only in the canonical
# checkout. Git reports a missing hooks directory as "no hooks" and commits silently.
#
# The effect was the gate present exactly where commits are FORBIDDEN and absent exactly
# where they are REQUIRED: the canonical checkout refused the commit via the concurrency
# guard, while every worktree commit — the only kind the workflow permits — ran no guard
# and no lint. Third instance of "the gate is inert and nothing says so" (v1.28.1 resolved
# engine/ from the worktree root; v1.32.0 never installed the hook at all).
#
# Absolute is right rather than merely expedient: `core.hooksPath` is per-checkout LOCAL
# config that adoption re-derives on every machine anyway, so machine-specificity costs
# nothing here. Tracking `.githooks/` instead would fix new vaults only — the engine
# cannot commit into a consumer vault, so it could never repair an existing one.
ABS="$WIKI/.githooks"
cur="$(git -C "$WIKI" config --local core.hooksPath 2>/dev/null || true)"
set_hookspath() {
  if [ -n "$CHECK" ]; then
    echo "adopt: would set core.hooksPath=$ABS in $WIKI ($1)"
  else
    git -C "$WIKI" config core.hooksPath "$ABS" && echo "adopt: set core.hooksPath=$ABS ($1)"
  fi
}
if [ -z "$cur" ]; then
  set_hookspath "absolute, so it resolves from linked worktrees too"
elif [ "$cur" = ".githooks" ]; then
  # The exact value THIS step used to write, so it is provably ours to correct. This is
  # the upgrade path: a vault adopted before this fix is repaired with no manual step.
  set_hookspath "was relative '.githooks', which is inert in every worktree"
elif [ "$cur" != "$ABS" ] && [ "${cur##*/}" = ".githooks" ] && [ ! -d "$cur" ]; then
  # Ours, but stale — the vault was moved or cloned to a different path, which silently
  # disarms an absolute hooksPath the same way. Only rewritten when it resolves nowhere.
  set_hookspath "stale absolute path '$cur' no longer exists"
elif [ "$cur" != "$ABS" ]; then
  echo "adopt: NOTE — core.hooksPath is '$cur', not this vault's .githooks; leaving it alone"
fi

# VERIFY EXECUTION, NOT INSTALLATION. Installing a hook and pointing config at it are two
# claims; whether a commit is actually gated is a third, and it is the only one that
# matters. All three previous instances passed the first two while failing the third, and
# every reporting surface said "adopted".
if [ -z "$CHECK" ]; then
  if ! out="$(gate_wiring_status "$WIKI")"; then
    echo "adopt: WARNING — a checkout of this vault would commit UNGATED:"
    printf '%s\n' "$out"
    echo "adopt:   A worktree created before this fix keeps its own stale config; re-run"
    echo "adopt:   adoption, or remove and re-take the worktree."
  fi
fi
exit 0
