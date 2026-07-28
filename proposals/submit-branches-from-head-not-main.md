---
slug: submit-branches-from-head-not-main
outcome: accepted
received: 2026-07-28
reason: "accepted as reported; submit now branches from origin/main (falling back to main) and prints the base it used, so a wrong base is visible rather than inferred from the discard hint"
---

HANDOFF — engine defect report slug: submit-branches-from-head-not-main boundary: generic (engine-domain; contains no consumer-private context)

Title: `submit` creates the proposal branch from the current HEAD, so a second proposal carries the first one's file

Engine version: v1.44.0 — the release that introduced the verb. Still live at that pin: reproduced today at v1.44.0, on the second consumer submission ever attempted through the new file queue. The first submission could not expose it; the bug requires a prior proposal branch to still be checked out.

Observed: after submitting one proposal (leaving its branch checked out, which is the state `submit` itself leaves behind), `submit` was run for a second, unrelated proposal. The new branch was cut from the **current HEAD** — the first proposal's branch — rather than from `main` or `origin/main`:

    $ git log --oneline main..HEAD
    <sha> proposal: <second-slug>
    <sha> proposal: <first-slug>

    $ git diff main --stat
     proposals/<first-slug>.md   | 111 ++++++++++++++++++
     proposals/<second-slug>.md  | 102 ++++++++++++++++
     2 files changed, 213 insertions(+)

So the pull request for the second proposal would have contained **both** proposal files. The tool's own discard hint gave it away, naming the *first* proposal's branch as the place to return to — otherwise there is nothing in the output to suggest the new branch is not based on `main`.

Expected: each proposal branch is cut from `main` (or `origin/main`), so a pull request contains exactly the one proposal it is named for.

Reproduction (generic):
  1. `submit` proposal A. Do not switch branches afterwards — `submit` leaves A's branch checked out.
  2. `submit` proposal B.
  3. `git diff main --stat` on B's branch. -> two files, not one.

Failure shape: **fail-open**, and that is the reason to treat this as more than cosmetic. It does not refuse and it does not error; it produces a pull request that looks entirely ordinary and is merely wrong about its own contents. The contamination is visible only to a reviewer who notices a second file they were not expecting — and if A is still open at that moment, merging B silently merges A too, at whatever revision A happened to be, bypassing A's own review. Nothing downstream would distinguish that from an intentional two-proposal change.

It also compounds: a third submission in the same session would stack all three.

Already ruled out (so these need not be re-walked):
  - **Not operator error.** `submit` is what leaves the previous proposal's branch checked out; the contaminating state is the tool's own normal output, not something the consumer did wrong.
  - **Not a dirty tree or leftover work.** The clone was clean, and fast-forwarded to the release tag before the first `submit`.
  - **Not the same defect as `push-verb-omits-git-push`.** Different verb, different mechanism, opposite failure shape. That one refuses and publishes nothing; this one would happily publish the wrong thing. Their only relationship is that working around the first by hand is what left a proposal branch checked out and exposed the second.
  - **Not dependent on the pull request path.** The wrong base is established at branch-creation time and is observable with `git diff main` before anything is pushed.

Suggested fix (HOLD LOOSELY — may be wrong): create the branch explicitly from a known base rather than from wherever HEAD sits. Two judgement calls that belong to whoever fixes it rather than to this report:

  - **Which base — `main` or `origin/main`?** `origin/main` makes the result independent of how current the local clone is, which matches how the vault's own worktree helper picks a base; but it makes the operation depend on a fetch having happened, and this tool is otherwise careful about not assuming network. A stale local `main` produces a branch that merges cleanly but was reviewed against old context.
  - **Whether a dirty or non-`main` checkout should block.** Refusing outright is the conservative reading and matches this engine's habit of failing closed on ambiguous state; silently stashing or switching would be worse than either.

A narrower mitigation worth considering independently of the fix: have `submit` report the base it used, in the same output where it prints the block. The wrong base was silent here — the only clue was an incidental branch name in the discard hint, which is not where a consumer is looking.

Redactions: absolute filesystem paths, the engine remote's owner/repo, and the consumer vault's identifiers are replaced with placeholders, consistently. Proposal slugs in the transcript are generalized to `<first-slug>` / `<second-slug>` because the shape matters and the names do not; shas are elided for the same reason. Nothing else was removed.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification. Related, reported separately: `push-verb-omits-git-push`.
