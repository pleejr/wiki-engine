---
slug: vault-worktree-integrate-rebases-onto-stale-local-main
outcome: partially-accepted
reason: "defect confirmed and fixed; the suggested one-word change was tested and REJECTED — rebasing onto origin/<main> makes local <main> no longer an ancestor of the rebased branch, so the final merge --ff-only refuses and the divergence remains, trading a silent success for a misleading 'did main move mid-integrate?'. The local ref has to move instead: integrate now fast-forwards canonical to origin/<main> when behind, ADOPTS origin when the divergence is content-equal (the squash-merge signature, guarded by a clean-canonical check because reset --hard would discard uncommitted work), and refuses with exit 3 on real divergence. The two open design questions are deferred, not adopted: integrate still moves canonical <main>, and the success message still does not distinguish integrated-locally from published."
received: 2026-07-30
---

HANDOFF — engine defect report
slug: vault-worktree-integrate-rebases-onto-stale-local-main
boundary: generic (engine-domain; contains no consumer-private context)

Title: vault-worktree.sh integrate fetches origin/<main> and then rebases onto the LOCAL <main>, so an integrate onto a stale local branch reports success while leaving the canonical checkout divergent from origin

Engine version: v1.48.5 (submodule at the v1.48.5 tag exactly, confirmed via `git -C engine describe --tags`)
Still live at that pin: reproduced twice in one session at v1.48.5, ~40 minutes apart, in a vault whose publication convention is branch -> pull request -> squash-merge. The second occurrence is the one that surfaced it, because the first integrate's divergence is what made the second fail.

Observed:

`integrate` performs these three steps in order (bin/vault-worktree.sh, the `integrate)` case):

  1. `git -C "$WIKI" fetch -q origin "$main"`
  2. `git -C "$wt" rebase -q "$main"`          # <-- rebases onto the LOCAL ref
  3. `git -C "$WIKI" merge --ff-only -q "$branch"`

Step 1 updates the remote-tracking ref. Step 2 then rebases onto `"$main"` — the local
branch — not `origin/"$main"`. **The fetched result is never consulted.** So whenever the
local <main> is behind origin, step 2 picks a stale base and step 3 fast-forwards local
<main> onto a history that does not contain what origin has. It then prints:

    vault-worktree: integrated <branch> -> <main>
    integrated <branch> -> <main>

...which reads as a completed publication. Nothing has been published, and the canonical
checkout is now divergent.

Any flow where origin/<main> advances by a commit the local <main> does not have will
trigger this. Squash-merge is simply the most common such flow, because the squash commit
is by construction a new object that the local pre-squash commit is not an ancestor of —
so a consumer vault following branch -> PR -> squash-merge diverges on *every* integrate,
not occasionally.

Concrete sequence, all within one session:

  1. Integrate worktree branch A. Local <main> fast-forwards to commit X. Prints success.
  2. Publish X by pushing a branch and squash-merging its PR. origin/<main> is now
     commit Y (new object; X is not an ancestor of Y).
  3. Local <main> is still X. It has diverged from origin/<main>.
  4. Later in the same session, edit again, `ensure` a worktree, commit, `integrate`.
     Prints success again. Local <main> moves to Z, whose parent is X.
  5. Push a branch at Z and open a PR. **The PR cannot merge** — Z's history does not
     contain Y. The host offers a manual merge/rebase as the only route.

Expected:

`integrate` should rebase onto the ref it just fetched (`origin/"$main"`), since fetching
it and then ignoring it cannot be the intent. Failing that, it should refuse — or at
minimum not report success — when the local <main> is not an ancestor of the fetched
`origin/"$main"`, because at that point "integrated -> <main>" describes a local state
that cannot be published without manual history repair.

Failure shape: fail-closed, with a fail-open success message

The refusal happens, but it happens *later and elsewhere* — at pull-request merge time,
in the host's UI, on a step the tool does not own. Nothing is destroyed. But `integrate`
declares the operation complete at a moment when it has published nothing and has made
the next publication attempt fail, so the failure surfaces well after the tool that
caused it has exited reporting success.

Worth flagging a data-loss adjacency, because the obvious recovery is destructive: with
local <main> divergent, the natural repair is `git reset --hard origin/<main>` on the
canonical checkout — which discards the commit `integrate` just created. In this
reproduction the commit happened to have been pushed to a branch already and survived. A
consumer who integrates, sees divergence, and resets before pushing loses the work, and
`integrate`'s success message is what makes that sequence feel safe.

Already ruled out:

  - Not a stale-fetch problem in the consumer's own commands. `origin` was fetched
    immediately before branching, and step 1 fetches it again inside `integrate`.
  - Not the write-gate / worktree-guard interaction. The guard correctly allowed the
    worktree and correctly refused canonical; both behaved as documented.
  - Not a dirty-canonical case. The path-precise dirty check passed; canonical was clean.
  - Not specific to one branch. Two independent branches, ~40 minutes apart, same result.
  - `ensure` is NOT affected and in fact silently repairs it: re-running `ensure` after
    the divergence produced a worktree branch already rebased onto the current
    origin-derived <main>. So the rebasing capability is present in the tool — it is just
    not applied against the fetched ref at integrate time. That asymmetry between the two
    verbs looks like the actual bug rather than a missing feature.
  - Force-push recovery is not universally available: in one agent harness a
    `git push --force` was denied by a policy classifier, so a fix or workaround that
    assumes the consumer can rewrite a published branch is weaker than it appears. The
    recovery that worked was pushing a fresh branch and closing/reopening the PR.

Suggested fix (HOLD LOOSELY — may be wrong):

Rebasing onto `origin/"$main"` instead of `"$main"` in step 2 looks like a one-word change
that matches the evident intent of step 1, but I have not traced what else depends on the
local ref, and there may be a deliberate reason for it — a single-machine push-to-main
consumer would see no difference either way, which is consistent with the current
behaviour never having been noticed. Two things I would want decided by whoever owns the
design rather than by this report:

  - Whether `integrate` should touch the canonical <main> at all, or leave publication
    entirely to the consumer's own convention. The verb's value may be the locked,
    serialized rebase; moving canonical HEAD is a separate concern that only helps a
    consumer who publishes by pushing <main> directly.
  - Whether the success message should distinguish "integrated locally" from "published",
    since a consumer whose convention is pull-request-based never reaches the latter via
    this verb.

Redactions:

  - Vault name, org, repository slugs, usernames, emails and absolute paths removed
    throughout. The vault's default branch name is written as <main>, its path as $WIKI
    (the variable the script itself uses).
  - Pull-request numbers and commit SHAs replaced with X / Y / Z placeholders; the same
    letter always means the same commit.
  - The consumer's publication convention (branch -> PR -> squash-merge) is stated
    because it is load-bearing for the reproduction, not incidental.
  - Nothing else was withheld; the quoted three steps and the success message are
    verbatim from the engine's own source and output.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification. In particular, confirm whether step
2's use of the local ref is deliberate before changing it — the asymmetry with `ensure`
is the strongest evidence that it is not, but that is inference, not a reading of intent.
