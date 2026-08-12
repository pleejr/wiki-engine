---
slug: vault-walks-descend-into-the-worktree-root
outcome: open
received: 2026-08-12
---

HANDOFF — engine defect report
slug: vault-walks-descend-into-the-worktree-root
boundary: generic (engine-domain; contains no consumer-private context)

Title: every vault walk except one descends into the per-session worktree root, so tools read (and one WRITES) other branches' checkouts as if they were vault content

Engine version: v1.54.2
Still live at that pin: reproduced at v1.54.2 by taking a session worktree and re-running the affected tools; the counts change with the worktree's presence and change back when it is retired.

Observed: the isolation feature puts full checkouts of the vault under `<vault>/.worktrees/<session-id>/` — tracked content, on a different branch, belonging to a different session. Five tools walk the vault recursively; four of them prune `.git`, `engine`, `.obsidian` and `.rag` but NOT the worktree root, so every page in every live worktree is walked as if it were a vault page. One tool prunes it correctly, which is what shows the list was meant to include it.

Measured with one live worktree, 179 markdown files beneath it:

  - the verified-status report listed **every repo page twice** — once correctly, once as a
    second class of page — and its summary counted them twice. Retiring the worktree
    returned both to the correct values. The duplicate row reports the state on THAT
    BRANCH, so a page verified on a branch and not in the canonical tree reads as verified.
  - the umbrella lint's page list picked up all 179. Its per-page gates (boundary present,
    boundary matches, provenance present, ref-is-a-clean-tag) therefore run against a tree
    the commit is not about: a page mid-edit on a branch can fail the gate for a commit
    that does not touch it, and the reverse — a page fixed only on a branch — passes it.
  - the memory lint's slug set includes worktree copies, so a `[[link]]` resolves when the
    target exists **on some other branch only**. That is fail-open on the dead-link check.
  - the migration tool's reference sweep is a recursive grep and then rewrites what it
    finds: it would EDIT pages inside another session's checkout. This is the write-side
    instance and the reason the report is not merely cosmetic.

There is a second directory of the same shape: when the isolation helper recovers an
orphaned worktree it renames it aside in place (`<id>.orphaned-<timestamp>`), which is still
under the worktree root and still full of markdown.

Expected: a vault walk sees the vault. A per-session worktree is a checkout of another
branch that happens to live inside the vault directory; no tool that reasons about "the
vault's pages" should see it, and nothing should ever write into it.

Reproduction (generic):

  1. In a vault with isolation wired, take a session worktree.
  2. Run the verified-status report. Note the duplicated rows and the inflated summary.
  3. Retire the worktree and re-run. The duplicates disappear.
  4. For the walk itself: run the same `find` the umbrella lint uses and count paths under
     the worktree root.

Failure shape: **fail-open for the read-side tools** — a link resolves against a branch, a
page reads as verified because some branch verified it, and every count is inflated while
looking ordinary; the numbers change under you depending on whether a session happens to be
open. **Potential data-loss for the write-side sweep**, which would rewrite files in a
checkout its session did not author, and those edits land on that session's branch.

Already ruled out:

  - Not the isolation feature misbehaving: the worktree is exactly where it is documented
    to be. The walks are what did not account for it.
  - Not universal: one of the five walks already prunes the worktree root, so this is a
    missing-instance problem rather than an unknown hazard. That single correct copy is
    also why a shared exclusion is worth more than four edits.
  - Not reproducible with no worktree open, which is why it survived — a tool run from a
    quiet vault behaves perfectly, and the affected runs are exactly the ones made during a
    session that took isolation.
  - Not affecting the indexer, and NOT because it excludes the directory: its language's
    recursive glob skips dot-prefixed directories, so the immunity is accidental and would
    end the day the worktree root is renamed to something without a dot.

Suggested fix (HOLD LOOSELY — may be wrong): put the skip list in ONE place the walks
share, rather than adding the missing name to four lists — four copies drifting apart is
what produced this, and the next tool will copy whichever list it happens to see. Include
the accidental case explicitly, so the indexer states the exclusion it currently gets for
free. A mechanical gate over the engine's own tools ("a vault walk must exclude the worktree
root") would keep the class closed; the reporter has no view of whether that belongs in the
existing convention lint or somewhere else.

Redactions: paths, vault names and the session identifier are described rather than quoted;
the counts are from a single real vault and are illustrative, not contractual.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as
a hypothesis, not a specification.
