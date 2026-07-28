---
slug: worktree-reattach-returns-stale-base
outcome: open
received: 2026-07-28
---

HANDOFF — engine defect report
slug: worktree-reattach-returns-stale-base
boundary: generic (engine-domain; contains no consumer-private context)

Title: `vault-worktree.sh ensure` reattaches to a stale `wt/<slug>` branch and reports plain success, so callers edit on an out-of-date base

Engine version: v1.46.0
Still live at that pin: read `bin/vault-worktree.sh` at the v1.46.0 commit after
updating. The `ensure` reattach path is unchanged and has no staleness check. My
first hypothesis — "ensure does not fetch" — is WRONG and I want to retract it
explicitly: `ensure` does run `git fetch -q origin main` before computing `base`.
The fetch is not the problem; `base` is simply not consulted on the reattach path.

Observed:
  `ensure` logged `reattached <wt> to existing wt/<slug>` and returned exit 0. The
  returned worktree's HEAD was several merges behind `origin/main` — in one case
  two merges, in another one merge. Nothing in the output indicated a distance.
  Edits were then made on that base. Because the vault's append-only files (a
  chronological log page, and a generated index region) had also been appended to
  on `main` in the meantime, the branch conflicted at merge time.

  This is by design as far as it goes, and the code says so:

    # With a stable session slug the branch can outlive its worktree (retired but kept
    # because it held unmerged commits). Reattach to the existing branch — never reset it,
    # so those commits survive — otherwise cut a fresh one off base.

  Preserving unmerged commits is right. The defect is that the caller cannot tell
  which path it got. The consuming skill text describes `ensure` as putting the
  session "on its own `wt/<session>` branch off `origin/main`", which is true only
  on the create path, and the log line for reattach reads as ordinary success.

  AGGRAVATOR, and I think this is the more valuable half of the report: a vault
  whose review workflow **squash-merges** pull requests will hit the reattach path
  as the NORMAL case, not an edge case. Squashing means the worktree branch's
  commits never appear in the target branch by sha, so `gc`'s "already contained in
  main" containment test cannot recognize them; the branch is therefore kept as
  still-holding-unmerged-work, and the next `ensure` in the same session reattaches
  to it. The branch is stale precisely *because* the work it held was already
  landed — in squashed form. So the mechanism that protects unmerged commits
  systematically mis-fires for an entire class of consumer, and the staleness grows
  with each merge in the session.

Expected:
  Either of these would have prevented it; I am not asserting which is right.
  (a) The reattach path reports the distance from `base` — e.g. `reattached <wt> to
      existing wt/<slug> (N commit(s) behind origin/main)` — so a caller can decide.
  (b) When the reattached branch is clean (no uncommitted changes) AND holds no
      commits absent from `base` by patch-equivalence, it is safe to fast-forward
      it to `base`, because there is nothing to protect.
  The invariant worth preserving: `ensure` should never silently hand back a base
  that is behind the branch it claims to derive from, whichever remedy is chosen.

Reproduction (generic):
  1. In a vault pinned to this engine, take a worktree: `WORK="$(bin/vault-worktree.sh ensure)"`
  2. Commit a change in `$WORK` that appends a line to the vault's chronological log page.
  3. Land it on the default branch by **squash** merge (the case that matters), then
     update the canonical checkout.
  4. Append a line to the same log page on the default branch by any other route and land it.
  5. In the same session (same session-id slug), run `bin/vault-worktree.sh ensure` again.
  -> It prints `reattached <wt> to existing wt/<slug>`, exit 0, no distance reported.
  -> `git -C "$WORK" log --oneline -1` is behind the default branch.
  -> Editing the log page here and merging produces a conflict on the appended region.

Failure shape: fail-open

  It proceeds while looking correct: success is logged, exit status is 0, a valid
  path is returned, and the isolation guarantee the tool exists for is genuinely
  intact. Only the *base* is wrong, and nothing surfaces that until merge time.
  Naming it fail-open rather than data-loss deliberately: in my session it did
  contribute to a near-loss, but the destructive step was mine — a cleanup that
  deleted a branch chained after an unverified merge command. That is a caller bug,
  not this one. I mention it only because it is how a "mere" stale base escalates:
  a surprise conflict lands in whatever error handling the caller happens to have.

Already ruled out:
  - Not a missing fetch. `ensure` fetches `origin main` before computing `base`.
  - Not the orphaned-directory recovery path; the directory was tracked by git both
    times, and no `.orphaned-*` directory was produced.
  - Not the non-zero fallback path (which correctly warns loudly and exits 1) —
    exit status was 0 and the returned path was a real worktree, not the canonical
    checkout.
  - Not concurrent-session interference: the reattached branch carried this
    session's own slug, and a peer session's worktree was on a different slug.
  - Not `WIKI_WORKTREE=0`; that opt-out was not set for these invocations.
  - `integrate` is not a workaround for it. It rebases onto the target *at
    integrate time*, so it surfaces the conflict rather than preventing it, which
    is correct behavior but arrives after the editing is done.

Suggested fix (HOLD LOOSELY — may be wrong):
  Report the distance on the reattach path at minimum, since that is purely
  additive and cannot lose work. Consider the conditional fast-forward in (b)
  above, but note the risk I cannot evaluate from here: "holds no commits absent
  from base" must be judged by patch-equivalence (`git cherry` / patch-id), not by
  sha containment, or squash-merged consumers get the same wrong answer that
  produces the stale branch in the first place — and a naive `reset --hard` to base
  would then destroy exactly the commits the current design protects. If that
  distinction cannot be made reliably, prefer (a) alone and leave the decision to
  the caller.

  Possibly a second, separable item for the engine's judgement: `gc`'s
  branch-retention test may deserve the same patch-equivalence treatment, so a
  squash-merged worktree branch is recognized as landed and retired rather than
  kept forever. I did not verify `gc`'s implementation closely enough to file that
  as its own defect, and it may be intentional conservatism.

Redactions:
  - Vault name, its directory name, org/repo slugs, git identity and machine name:
    omitted entirely; none were needed to state the defect.
  - Absolute paths replaced with `<wt>` / `$WORK` consistently.
  - The session-id slug is referred to as `wt/<slug>`; the real value is a session
    UUID and carries no meaning upstream.
  - Specific page names generalized to "chronological log page" and "generated
    index region" — the shape that matters is *append-only content*, which is what
    makes the conflict deterministic rather than incidental.
  - Commit shas and PR numbers omitted; they identify a private repository and add
    nothing to the reproduction.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification. Note especially that my
initial diagnosis was wrong in a way that would have sent you to the fetch logic;
the squash-merge aggravator is the part I would most want a second opinion on,
since it predicts this is the default experience for a whole class of consumer
rather than a rare race.
