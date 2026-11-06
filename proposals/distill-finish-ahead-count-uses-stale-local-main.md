---
slug: distill-finish-ahead-count-uses-stale-local-main
outcome: open
received: 2026-11-06
---

HANDOFF — engine defect report
slug: distill-finish-ahead-count-uses-stale-local-main
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill-finish counts commits ahead against the canonical checkout's local main, not origin/main, so a stale local main opens a pull request for an empty branch

Engine version: 3.7.3
Still live at that release: read bin/distill-finish.sh in the 3.7.3 plugin cache; line 110 computes ahead as `rev-list --count "$main..HEAD"` where `$main` is the canonical checkout's current branch name, resolved to its local ref.

Observed: in a publish = pr vault, the canonical checkout's local main was behind origin/main (it could not fast-forward because the tree held an untracked file). vault-worktree.sh ensure created the session worktree off origin/main. The session made no vault commits. distill-finish reported "lint passed", pushed the session branch, then:
  VAULT OUTSTANDING — 1 item(s):
    - opening the pull request for wt/<session> failed (pull request create failed: GraphQL: No commits between main and wt/<session> (createPullRequest)): open it by hand, merge it, then rerun
The branch held zero commits relative to origin/main.

Expected: the existing zero-ahead path ("nothing on <branch> that <main> lacks", VAULT DONE — nothing new to land) runs, because the worktree's base is origin/main and the guard should measure against the same base the worktree was created from.

Reproduction (generic):
  1. In a publish = pr vault, leave the canonical checkout's local main one or more commits behind origin/main (e.g. an untracked file blocking a fast-forward, or simply no pull since another session merged).
  2. vault-worktree.sh ensure (worktree created off origin/main); make no commits.
  3. distill-finish.sh from the worktree.
  -> branch pushed; pull request create fails "No commits between main and wt/<session>"; VAULT OUTSTANDING.

Failure shape: fail-closed (nothing lost; it reports outstanding work that does not exist and leaves an empty remote branch behind to clean up by hand).

Already ruled out: not a lint or route problem (lint passed, route is pr); the fetch on line 108 does run, but it updates origin/main only, not the local main the count reads.

Suggested fix (HOLD LOOSELY — may be wrong): count ahead against "origin/$main" (falling back to "$main" when there is no remote), matching the base vault-worktree.sh ensure uses. The direct route's integrate step may want the same check reviewed.

Redactions: the session id in the branch name is replaced with <session>; vault and repository names omitted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
