---
slug: distill-finish-rerun-resurrects-merged-session-branch
outcome: open
received: 2026-10-19
---

HANDOFF — engine defect report
slug: distill-finish-rerun-resurrects-merged-session-branch
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill-finish.sh (pr route) re-pushes a session branch whose pull request is already merged and deleted, and a later distill in the same session then cannot land

Engine version: v3.6.1
Still live at that release: reproduced twice in one session on 2026-10-19 against the installed v3.6.1 plugin; the pr-route block of bin/distill-finish.sh still pushes before it checks pull-request state.

Observed:
  1. distill-finish.sh opened pull request A from wt/<session> and printed VAULT OUTSTANDING ("merge it, then rerun distill-finish.sh").
  2. The operator squash-merged A with the remote branch deleted on merge.
  3. The rerun printed, in order: "pushed wt/<session>", "pull request #A is merged; main fast-forwarded", "retired worktree ...", "VAULT DONE". The remote wt/<session> branch exists again, at A's pre-squash commit. Retiring removes only the local branch.
  4. A second distill in the same session: vault-worktree.sh ensure recreates wt/<session> off origin/main and a new commit is made.
  5. distill-finish.sh: the push is rejected as non-fast-forward against the resurrected tip ("push of wt/<session> failed"). Because no pull request matches the new tip, it runs gh pr create --head wt/<session>, which opens pull request B against the stale remote head (A's old commit, already squash-merged). B conflicts with main, so pull_request CI never runs and B cannot be merged with a required check. VAULT OUTSTANDING lists both items.
  The second time it happened, the rerun after merging B resurrected the branch again (step 3 repeats).
Expected: after a rerun that finds the pull request MERGED, the remote session branch stays deleted (or is deleted), so the next landing in the same session starts clean. Equivalently: a push is never made for a tip already contained in main.

Reproduction (generic):
  1. In a pr-route vault, make a commit in the session worktree and run distill-finish.sh -> pull request A opened.
  2. Squash-merge A, deleting its head branch.
  3. Rerun distill-finish.sh from the same worktree -> "pushed wt/<session>" then VAULT DONE; git ls-remote origin refs/heads/wt/<session> shows the branch again.
  4. vault-worktree.sh ensure, commit, distill-finish.sh -> push rejected (non-fast-forward); new pull request opened against the stale head; it reports CONFLICTING and no checks register.

Failure shape: fail-closed (push refused, pull request unmergeable), plus a leftover remote branch after every successful landing.

Already ruled out:
  - Not the merge tool: the remote branch was confirmed deleted after the merge and present again only after the distill-finish.sh rerun.
  - Not the PR-matching logic: matching on headRefOid behaves as documented; it simply finds no PR for the new tip and creates one on the stale remote head.
  - The orphan-branch sweep in vault-worktree.sh covers local wt/* refs, not remote ones.

Suggested fix (HOLD LOOSELY — may be wrong): in the pr route, look up the pull request for the local tip before pushing, and skip the push when that PR is MERGED or the tip is already an ancestor of / patch-equivalent to origin/main. Separately, when the push is rejected and the remote tip is patch-equivalent to main (git cherry shows "-"), force-with-lease over it rather than opening a PR against it. Either half alone would give the Expected; the first prevents the resurrection, the second recovers from one.

Redactions: vault path -> <vault>; session id -> <session>; pull request numbers -> A and B; the external merge helper is described by behaviour only (squash-merge, delete head branch).

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
