---
slug: checkpoint-prune-confirm-scope
outcome: accepted
received: 2026-08-11
---

HANDOFF — engine improvement proposal
slug: checkpoint-prune-confirm-scope
boundary: generic (engine-domain; contains no consumer-private context)

Title: Scope checkpoint §3's confirm-before-removing clause to unpromoted content

Problem: §3 mandates pruning promoted `raw/sessions` blocks, then closes with
"Deletion is a **guided in-session action** — confirm before removing." Read
literally, that makes every ordinary prune a question for the user, including a
block whose keeper is already a `log.md` entry or a curated note. That question
has no content in it: the block is spent buffer metadata, the keeper landed in a
tracked page, and deleting it neither destroys anything nor decides anything.
The clause's own rationale is that pruning "needs a human judgement about what is
worth keeping" — but that judgement was made at promotion. The confirm therefore
fires exactly where no judgement remains, and is silent about the one case that
still needs it.

The cost is not only friction. A prompt that is always answered the same way
trains the consumer to wave the step through, and a step that is habitually
waved through is one whose silent failure nobody notices. That is the shape §3
already has a scar from: between two releases it aimed at the session worktree,
where a git-ignored buffer cannot exist, so it pruned nothing while reporting
success — for nine releases. A confirm that carries no decision is camouflage
for that failure mode, because "nothing to prune" and "the prune is broken" both
end the turn quietly.

Motivating use case (generic): a checkpoint in a consumer vault finds one block
in `raw/sessions`, left by the previous session, whose keeper is already written
up in `log.md`. Following §3 literally, the session ends by asking whether to
delete it. The consumer's instruction back: do not ask about pruning unless
there is a backlog large enough to suggest the prune has stopped running.

Proposed shape (hold loosely):
  - Scope the confirm to what it actually protects — content **not yet
    promoted**. A block whose keeper is in `log.md`, `memory/`, or a project
    page is pruned in the same turn, recorded in the buffer's existing ledger
    line, and reported in one clause alongside the rest of the checkpoint.
  - An unpromoted block still stops the step, and for a stronger reason than a
    confirm: distil it first, then prune. Never delete uncaptured content.
  - Give §3 the signal that IS worth surfacing — a **backlog**. Many blocks, or
    blocks spanning several sessions, is not a deletion decision; it is evidence
    the prune stopped running. Report the count and the symptom, not a request
    for permission.
  - Leave "never delete content you haven't first promoted" verbatim. This
    narrows the confirm, not the safety rule.

Alternatives considered:
  - Leave §3 as written and let each consumer override it locally — rejected:
    every consumer re-derives the same override, and the engine text remains the
    thing that produced the behaviour. A rule that every reader has to correct is
    a defect in the rule.
  - Drop the confirm entirely — rejected: it is correct for unpromoted content,
    which is unrecoverable once deleted, and that case is real.
  - Batch it — one confirmation per checkpoint, with the full list — rejected:
    still a question with no content when every block is promoted. It was tried:
    compiling the list showed the answer was already determined by promotion
    state, which is the argument for deriving it rather than asking.

Acceptance criteria:
  - §3 states that the confirm applies to unpromoted content only, and that a
    promoted block is pruned without asking.
  - §3 names the backlog signal and what to report for it (count + symptom),
    stated as distinct from a deletion decision.
  - The "never delete what you have not promoted" rule is present and unweakened.
  - A reader following §3 against a buffer of entirely promoted blocks reaches no
    confirmation prompt — checkable by reading the step, no judgement needed.
  - The existing doc lint over the skill text still passes.
  - Block contains no vault name, username, email, absolute path, or repo slug.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
