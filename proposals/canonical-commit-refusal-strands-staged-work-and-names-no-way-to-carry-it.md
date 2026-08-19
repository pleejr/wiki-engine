---
slug: canonical-commit-refusal-strands-staged-work-and-names-no-way-to-carry-it
outcome: open
received: 2026-08-19
---

HANDOFF — engine defect report
slug: canonical-commit-refusal-strands-staged-work-and-names-no-way-to-carry-it
boundary: generic (engine-domain; contains no consumer-private context)

Title: The canonical-checkout commit refusal fires only after work is staged, and its message names the worktree remedy without naming any way to carry the staged work there — so the conventional rescue silently discards it

Engine version: v1.73.1

Still live at that pin: reproduced today at v1.73.1 while committing ordinary vault
content. The guard is `vault-worktree.sh`, `guard` case — the block that ends with
`refusing a commit in the CANONICAL checkout`. Read at the pinned commit (the
submodule checkout is exactly the tag, not ahead of it), and the six-line message
below is quoted from that source, not from memory.

Observed:
  A session edited two tracked pages in the canonical checkout, ran `git add -A`,
  and ran `git commit`. The guard refused, correctly, and printed:

    vault-worktree: refusing a commit in the CANONICAL checkout (<vault>).
      Another session may be editing here, and staging in a shared tree sweeps up
      its work. Take an isolated worktree first:
          WORK="$(<vault>/engine/bin/vault-worktree.sh ensure)"   # then edit + commit in $WORK
      Integrate when done:  vault-worktree.sh integrate
      Override for a single-session machine:  WIKI_WORKTREE=0

  Every line of that is true, and none of it answers the question the operator now
  has, which is not "where should I have worked" but "how do I move what I have
  already written into that worktree". `ensure` cuts a fresh branch off
  `origin/main`; it does not carry the working state, and nothing says so.

  The state the refusal leaves behind is the specific hazard. The commit failed, so
  the edits are still there — but they are STAGED, because the guard cannot decide
  anything until they are (it reads `git diff --cached --raw` to allow a
  submodule-pointer-only commit). The reflex rescue for "move an edit out of a
  checkout I should not be in" is:

    git diff > /tmp/x.patch
    git checkout -- . && git reset --hard HEAD

  `git diff` reports UNSTAGED changes only. Against a fully-staged tree it writes a
  0-byte file and exits 0, so the save looks successful and the destroy that follows
  removes the only copy. Discarded worktree changes were never git objects, so unlike
  a lost commit they cannot be recovered from the object store.

  This is the third time this sequence has run in this consumer vault. It is written
  down there, with the correct instrument, and the note was not loaded — which is the
  point of reporting it rather than re-reading the note: the moment the guidance is
  needed is the moment nobody is looking it up.

Expected:
  The refusal names a non-lossy way to carry already-staged work into the worktree it
  is sending the operator to. The guard is the one component that knows, at that
  instant, that staged changes exist — it has just read them to make its own decision
  — so it is the only place the advice can be given without the operator having to
  already know it.

  I am deliberately NOT asking for the guard to move earlier or to refuse at
  `git add`. Reading the staged set is load-bearing for the gitlink exemption shipped
  under `update-writes-canonical-against-the-worktree-convention`, and that exemption
  is what stops the guard training its users into `WIKI_WORKTREE=0`. Whatever ships
  here should leave that intact.

Reproduction (generic):
  1. On an isolation-enabled vault with no session worktree open, edit a tracked page
     in the canonical checkout.
  2. git add -A && git commit -m "…"
     -> refused, with the six lines quoted above. The edits remain, staged.
  3. git diff > /tmp/x.patch
     -> exit 0, and `wc -c /tmp/x.patch` is 0. Nothing warns.
  4. git checkout -- . && git reset --hard HEAD
     -> the edits are gone, and the patch that was supposed to hold them is empty.

Failure shape: fail-closed — and I want to be precise, because the report would be
  wrong the other way. The GUARD is fail-closed and behaves correctly: it refuses,
  and it destroys nothing. The data loss in step 4 is the operator's, not the
  engine's. What I am reporting is that the refusal leaves a state whose conventional
  recovery is silently lossy, while saying nothing about it — so the severity sits
  between the two categories: no engine code loses data, and yet the engine is where
  the cheapest fix lives. Treat it as fail-closed with a data-loss aftermath, not as
  a data-loss defect.

Already ruled out:
  - Not a duplicate of the three existing canonical-refusal proposals
    (`update-writes-canonical-against-the-worktree-convention`,
    `update-writes-a-page-canonical-refuses-when-no-worktree-is-live`,
    `adoption-leaves-the-skills-catalog-stale-so-the-pin-commit-is-refused-both-ways`).
    All three are about what WRITES into canonical and whether the resulting commit is
    legal. None concerns what happens to work already staged when the refusal fires.
  - Not fixable by moving the guard earlier, per the Expected section.
  - `git stash` as a bare recommendation is WRONG here, and this is the part most
    likely to be got wrong by whoever fixes it. Verified in a throwaway fixture:
    with a peer's untracked file present alongside mine, `git stash push
    --include-untracked` took BOTH and removed the peer's file from their tree —
    which is precisely the clobber the guard exists to prevent, reintroduced by the
    remedy. `git stash push -m <msg> -- <paths>` left the peer's file untouched. Any
    advice this guard prints must be path-scoped for the same reason the guard's own
    dirty-check was made path-precise.
  - Cross-worktree stash does work, so the remedy is real and not theoretical.
    Verified in the same fixture: `git stash push` in canonical, then `git stash pop`
    in a linked worktree on a DIFFERENT branch, restored the content; `pop --index`
    additionally preserved the staged state. `refs/stash` lives in the common git
    directory, which is shared with linked worktrees.

Suggested fix (HOLD LOOSELY — may be wrong):
  Add to the refusal the one thing the operator needs and cannot infer: that the
  staged work must be carried, and a path-scoped way to carry it. Sketch only —

      You have staged changes here. Do NOT `git diff > patch` (it reports unstaged
      changes only, so it would write an empty file), and do NOT stash unscoped
      (that takes a peer's work too). Carry only your own paths:
          git stash push -m carry -- <your paths>
          WORK="$(… ensure)" && git -C "$WORK" stash pop --index

  I hold this loosely for a specific reason: the precedent here is that a
  wording-only fix was DECLINED. `update-writes-canonical-against-the-worktree-convention`
  asked for wording naming the worktree route and intake shipped a path-precise guard
  instead, on the grounds that wording alone leaves the engine's own instruction
  refused by the engine's own gate. The analogous stronger fix would be for the guard
  to carry the work itself. I am not proposing that: it would move an operator's
  uncommitted work as a side effect of a refusal, and a gate that silently relocates
  your files is a worse thing to be surprised by than one that only tells you how.
  That is a judgement made from outside the internals, so overrule it if the shape
  looks different from there.

  Checked against my own Expected, as this skill asks: my Expected is that the
  refusal names a non-lossy carry. A message change does produce exactly that, so the
  two are consistent. If intake prefers a structural fix, note that it would satisfy
  the Expected too — the Expected does not depend on the fix being wording.

Redactions: the vault's absolute path is `<vault>` throughout, including inside the
  quoted message where the real path appears twice. No other substitutions; the
  quoted output is otherwise verbatim, and the fixture used throwaway paths and a
  throwaway git identity that are not reproduced here because they carry nothing.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
