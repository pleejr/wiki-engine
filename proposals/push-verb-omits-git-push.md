---
slug: push-verb-omits-git-push
outcome: open
received: 2026-07-28
---

HANDOFF — engine defect report
slug: push-verb-omits-git-push
boundary: generic (engine-domain; contains no consumer-private context)

Title: `push` opens the pull request without first pushing the branch, so the head ref does not exist

Engine version: v1.44.0 — the release that introduced the verb.
Still live at that pin: reproduced today against v1.44.0, and the code path is
unchanged at `origin/main` (checked after fast-forwarding a standalone clone to the
tag, so this is not a stale-checkout artifact). Found on the verb's **first real
use** — the first consumer submission attempted through the new file queue.

Observed: `submit` behaved correctly end to end — scanned, prepared the branch
locally, printed the block for review, and stopped. `push` then printed its intent
and failed:

    pull request create failed: GraphQL: Head sha can't be blank, Base sha can't be
    blank, No commits between main and proposal/<slug>, Head ref must be a branch
    (createPullRequest)
    engine-proposal: pull request failed — the branch is still local at
    proposal/<slug>, nothing was published

The abort message is **accurate**, and was verified independently rather than taken
at face value: `git ls-remote --heads origin 'proposal/*'` returned empty, no fork
existed, and the local branch was intact with exactly one commit ahead of `main`.

The mechanism: `do_push` calls `gh pr create --repo <owner/repo> --head "$br" …`
without ever running `git push`. The branch exists only locally, so there is no head
ref for GitHub to resolve. `gh` will push a current branch in some invocations, but
not when the target repository is pinned with `--repo`; it then expects the head ref
to already exist on the remote.

Expected: the branch is pushed to the remote (or to a fork) before the pull request
is opened, so the head ref resolves.

Reproduction (generic):
  1. In a consumer vault, `submit` a proposal with the engine-repo override pointing
     at a clone you can branch in.
  2. Confirm the branch is local only — `git ls-remote --heads origin 'proposal/*'`
     is empty.
  3. Run `push`.
  -> the GraphQL error above; still no remote branch, still no fork.

Failure shape: **fail-closed.** Nothing was published, nothing was lost, and the
`.prepared` marker was correctly left in place so `status` continued to report
`WRITTEN LOCALLY, never submitted` — which was true. Low urgency on those grounds,
but it blocks the queue's only publication path, so in practice every consumer
submission hits it.

A second-order consequence worth weighing separately from the fix: **the obvious
workaround silently makes `status` lie.** Running `git push` then `gh pr create` by
hand completes the submission, but `do_push` writes the `.submitted` marker only on
its own success — so a consumer who works around this is left with a real pull
request and a local state reporting `never submitted`. The natural next reading is
"nothing arrived, re-send", which is precisely the duplicate-submission failure the
marker exists to prevent. Whoever fixes the push should decide whether a marker
repair or reconcile path is also warranted; it was patched by hand here.

Already ruled out (so these need not be re-walked):
  - **Not authentication or transport.** The same branch pushed successfully over
    the same remote with the same credentials moments later; the failure returns a
    semantic GraphQL error, not an auth or network error.
  - **Not a missing or unauthenticated `gh`.** It is installed and logged in; the
    call reached GitHub and was rejected on content.
  - **Not a stale clone.** The clone was fast-forwarded to the release tag before
    `submit` ran.
  - **Not malformed branch content.** Exactly one commit ahead of `main`, whose diff
    is the single expected queue file.
  - **Not a `submit` defect.** Everything `submit` is responsible for was correct;
    the break is entirely inside `push`.

Suggested fix (HOLD LOOSELY — may be wrong): push the branch before creating the
pull request. Two things make the right shape less obvious than that sentence:

  - **The no-write-access path is likely broken at the same line, and it is the one
    that matters most.** The comment above the call states "No write access is
    assumed: gh forks on demand" — but `--repo` appears to suppress fork-on-demand
    as well as the push. That path was not exercised here (this reporter has write
    access), so it is an inference from the same mechanism rather than an
    observation. It is also the path a genuine third-party consumer would take, so
    it deserves a deliberate test rather than being fixed by implication.
  - **Simply dropping `--repo` is the obvious alternative and may be wrong.**
    Presumably `--repo` is there to remove ambiguity about which repository is being
    targeted; relying on `gh`'s inference would hand that decision back to whatever
    remote configuration the operator happens to have — the same class of objection
    that kept `git pull` out of the guarded clone refresh.

Redactions: absolute filesystem paths, the engine remote's owner/repo, and the
consumer vault's identifiers are replaced with placeholders, consistently, so the
reproduction still reads. The literal branch name is kept because it is derived from
the proposal slug, which is public by design. Nothing else was removed.

Related, reported separately: `submit-branches-from-head-not-main`, a second defect
in the same verb pair found in the same session. They interact — working around this
one by hand is what exposed the other — but they are independent bugs with different
failure shapes, so they are not merged into one report.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification — in particular, confirm the
no-write-access behaviour directly rather than assuming it follows from the same
cause.
