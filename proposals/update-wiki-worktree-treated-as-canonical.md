---
slug: update-wiki-worktree-treated-as-canonical
outcome: open
received: 2026-09-22
---

HANDOFF — engine defect report
slug: update-wiki-worktree-treated-as-canonical
boundary: generic (engine-domain; contains no consumer-private context)

Title: update.sh treats a linked worktree passed as --wiki as the canonical checkout, writes nothing, and its rerun hint repeats the worktree path

Engine version: v2.5.0
Still live at that release: reproduced 2026-09-22 against the v2.5.0 plugin copy; the cause was read from bin/update.sh and bin/wiki-root-lib.sh at v2.5.0.

Observed:
  Run from a linked worktree of the vault, with --wiki naming that same worktree:
    cd <vault>/.worktrees/<wt> && bin/update.sh --wiki "$PWD"
  update.sh ran adoption, then printed
    "NOT written: this vault gates commits in its canonical checkout ..."
  and exited 0 with nothing written or staged. The rerun hint it printed was
    WORK="$(bin/vault-worktree.sh ensure)" && (cd "$WORK" && bin/update.sh --wiki "<vault>/.worktrees/<wt>")
  i.e. it re-embeds the worktree path as --wiki, the value that caused the refusal.
  Rerunning from the same worktree with --wiki "<vault>" (the canonical checkout) wrote and staged .engine-version as intended.

Cause (read from code, not instrumented):
  1. update.sh:84 computes PAGE_TREE via resolve_wiki_root with WIKI_PATH="$WIKI".
  2. In resolve_wiki_root, when cwd's toplevel equals WIKI_PATH it returns WIKI_PATH, so PAGE_TREE == WIKI.
  3. update.sh:108 treats PAGE_TREE == WIKI as "standing in canonical", then canonical_commit_gated "$WIKI" is true
     because core.hooksPath is an absolute path to the canonical checkout's .githooks, whose pre-commit is executable.
  4. Neither step checks whether WIKI is actually the MAIN worktree; any linked worktree passed as --wiki is classified as canonical.
  5. The hint at update.sh:210 prints "$WIKI" verbatim, so it carries the misclassified path forward.

Expected:
  Either (a) a linked worktree passed as --wiki is recognised as a worktree, and update.sh writes and stages there;
  or (b) update.sh refuses with a message naming the fix: pass the canonical checkout as --wiki and run from the worktree.
  In both cases the rerun hint should name the canonical checkout (the main worktree), never the value that was refused.

Reproduction (generic):
  1. A vault whose canonical checkout is commit-gated (core.hooksPath -> .githooks with an executable pre-commit).
  2. git -C <vault> worktree add -b t <vault>/.worktrees/t origin/main
  3. cd <vault>/.worktrees/t && <engine>/bin/update.sh --wiki "$PWD"   (vault records an older release than the engine)
  -> "NOT written: this vault gates commits in its canonical checkout ..." exit 0, git status clean,
     hint names --wiki "<vault>/.worktrees/t".

Failure shape: fail-closed (nothing written, message printed; but exit 0 and the hint misleads the next attempt).

Already ruled out:
  - Not a stale pointer or version mismatch: the same invocation with --wiki "<vault>" succeeded immediately.
  - Not a dirty tree: the worktree was freshly created from origin/main.
  - Adoption itself ran (it also installed .githooks/pre-commit in the worktree and noted core.hooksPath points elsewhere); only the record step deferred.

Suggested fix (HOLD LOOSELY — may be wrong):
  Normalize WIKI to the main worktree before the PAGE_TREE comparison (e.g. the first entry of `git worktree list --porcelain`,
  or the parent of the absolute common dir), so a linked worktree given as --wiki resolves to PAGE_TREE=<that worktree>, WIKI=<canonical>.
  Print the normalized canonical path in the rerun hint. Consider a non-zero exit when nothing was written.
  If (a) is chosen, check the Expected against it: the hint should then never be reachable from a linked worktree at all.

Redactions: absolute vault and home paths replaced with <vault> and <engine>; worktree name replaced with <wt>/t. Nothing else removed.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
