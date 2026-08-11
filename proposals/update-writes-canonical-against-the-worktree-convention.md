---
slug: update-writes-canonical-against-the-worktree-convention
outcome: partially-accepted
received: 2026-08-11
reason: "both halves reproduced and fixed, and part 2 — which the reporter read rather than triggered — was confirmed live in a fixture vault: with a session worktree open, update.sh rewrote and staged a tracked repo page in the shared checkout. The fix splits the two questions the old code conflated. The PIN is a gitlink and can only live in canonical, so `guard` now judges the STAGED SET rather than the tree and permits a submodule-pointer-only commit — the one commit no worktree can make — while anything staged beside it still refuses; that replaces the previous workaround of WIKI_WORKTREE=0, which turned isolation off for the whole command to land one legitimate commit. The PAGE is ordinary tracked content, so it is written in the caller's worktree when they are in one, and when they stand in canonical with live worktrees present it is not written at all, only printed for them to apply on their branch. DECLINED, in favour of a stronger fix than proposed: the reporter's minimum for part 1 was wording that names the worktree route. Wording alone would have left the documented instruction still refused by the engine's own gate, so the guard was made path-precise instead. The `-am` in the remedy was also treated as the defect rather than a detail — in a shared tree it stages a concurrent session's modified files, which is precisely the clobber the guard exists to refuse — and the sweep the reporter did not ask for found the same instruction in `engine-version.sh` and in the SESSION BANNER, the most-read surface of the three. The reporter's WIKI_WORKTREE=0 worry was well placed and is covered by a no-regression assertion: a vault with isolation off, or with no worktrees at all, keeps today's behaviour exactly"

HANDOFF — engine defect report
slug: update-writes-canonical-against-the-worktree-convention
boundary: generic (engine-domain; contains no consumer-private context)

Title: update.sh stages into canonical and prints a commit the worktree convention forbids, and can also rewrite tracked pages there

Engine version: v1.51.0
Still live at that pin: read from the source at the pinned tag, not from memory.
`bin/update.sh` contains no occurrence of the string "worktree" (`grep -c` = 0), so
it has no awareness of the convention the rest of the engine mandates.

Observed:
  Two behaviours, one always and one conditional.

  1. ALWAYS — it stages the submodule pin in canonical `<vault>` and ends with:

         Staged: engine -> <tag>. Review the CHANGELOG, then commit:
           git -C "<vault>" commit -am "Bump engine to <tag>"

     That instruction cannot be followed in a vault that adopts the worktree
     convention. Attempting it is refused:

         refusing a commit in the CANONICAL checkout.
           Another session may be editing here, and staging in a shared tree
           sweeps up its work.

     (The refusal above is emitted by a consumer-side gate, not by the engine —
     but the engine mandates the same rule itself, in `bin/vault-worktree.sh`
     and in `skills/checkpoint` §0: "Make all edits to TRACKED vault content —
     and every commit and lint run — against $WORK, never $WIKI_PATH directly.")

  2. CONDITIONAL — for every `<vault>/repos/*.md` whose `sources.repo` names the
     engine repository, it rewrites the `ref`/`sha`/`ingested` frontmatter and runs
     `git -C "<vault>" add` on the page. That is a write to TRACKED vault content in
     the shared tree — precisely the write the convention exists to prevent, with
     last-writer-wins on disk against any concurrent session holding that page open,
     before git ever sees it.

     NOT OBSERVED, only read: the vault I ran this in ingests no repo page for the
     engine, so the loop body did not execute here. I confirmed the code path and its
     guard by reading `bin/update.sh`; I did not manufacture a page to trigger it.
     Worth reproducing at your end before sizing it.

Expected:
  The updater should leave the operator in a state the engine's own convention can
  carry forward — and must not write tracked content into the shared tree at all.
  The engine-dev vault reading must not regress: there, canonical *is* the working
  tree and today's behaviour is correct.

Reproduction (generic):
  1. In a vault that adopts the worktree convention and pins the engine behind the
     latest tag, run `<vault>/engine/bin/update.sh`.
  2. Follow the printed remedy: `git -C "<vault>" commit -am "..."`.
  -> Refused, if the vault gates commits in canonical. Where it is not gated, the
     commit succeeds in the shared tree and can sweep up a concurrent session's
     staged work — which is the harm the convention names.
  3. For part 2: add a `repos/<page>.md` whose `sources.repo` is the engine repo,
     then re-run. The page is rewritten and staged in canonical.

Failure shape: fail-open

  Nothing warns. Part 1 is merely unfollowable — annoying, self-announcing, and the
  operator works around it. Part 2 is the severe half: the write succeeds silently in
  the shared tree, and its damage is only visible to a *different* session, later,
  as content it did not author appearing in its staging area or as its own edit
  vanishing. That is the same class the engine already fixed twice — a step aimed at
  the wrong tree that reports success — and the reason I am reporting the pair rather
  than only the part I hit.

Already ruled out:
  - Not stale — read at the current tag.
  - Not already covered by the accepted `generators-resolve-wiki-path-not-session-worktree`.
    That one is a tool invoked FROM a worktree resolving to canonical and writing the
    result outside the branch that changed it. This is a tool that only ever runs against
    canonical by necessity (the submodule checkout lives there) and whose *remedy and
    content writes* ignore the convention. Same family, different mechanism; I flag the
    overlap so you can fold them if you disagree.
  - Not the consumer's gate being wrong. The gate's refusal is correct and the engine
    states the same rule in two places; the inconsistency is internal to the engine.

Suggested fix (HOLD LOOSELY — may be wrong):
  The pin itself genuinely must be staged where the submodule lives, so the honest
  minimum may be wording: have the printed remedy name the worktree route when one is
  in use, the way the engine already routes other context-dependent advice. The
  content-rewrite half looks more like a real relocation — either skip `repos/*.md`
  when a session worktree exists and let the operator do it there, or emit the intended
  edit rather than performing it. I have not thought through what that does to a vault
  running without worktrees (`WIKI_WORKTREE=0`), which is the case most likely to be
  broken by a naive fix, so treat all of this as a starting point.

Redactions:
  Absolute paths replaced with `<vault>`; the engine tag replaced with `<tag>`; a repo
  page filename replaced with `<page>`. Quoted output is otherwise verbatim, and the
  quoted engine source and skill text are from the public engine itself.

Instruction to engine-dev: reproduce first, then decide the shape. Part 2 is the half
worth reproducing, since I read it rather than triggered it. Treat the suggested fix as
a hypothesis, not a specification.
