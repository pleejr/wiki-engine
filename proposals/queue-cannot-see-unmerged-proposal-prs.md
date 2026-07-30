---
slug: queue-cannot-see-unmerged-proposal-prs
outcome: accepted
received: 2026-07-30
---

HANDOFF — engine improvement proposal
slug: queue-cannot-see-unmerged-proposal-prs
boundary: generic (engine-domain; contains no consumer-private context)

Title: A pushed-but-unmerged proposal is outstanding to nobody — the engine-dev end has no surface that shows it, while the consumer end reports it as sent

Problem:

Arrival in the file queue is defined as the *merged* pull request: `proposals/<slug>.md`
on the default branch. `queue` lists those files. That is coherent, and `queue` behaves
as documented.

The gap is the interval between `push` and merge. In that window:

  - the consumer end reports `SUBMITTED, not yet merged`, and its own guidance says the
    pull request IS the record and not to re-send;
  - the engine-dev end's only "what is outstanding" surface, `queue`, reads merged files
    and therefore shows nothing at all.

So a proposal in flight is visible to the party who cannot act on it and invisible to the
party who must. Neither end is malfunctioning; between them there is no surface on which
the proposal exists.

**This is worse when the consumer lacks write access to the engine repository.** `push`
then forks and opens the pull request from the fork, so merging — the act that creates
arrival — is something *only the engine-dev end can do*. That end cannot see that there is
anything to merge. The proposal can sit indefinitely with both ends behaving correctly.

Failure shape: fail-open. Nothing errors, nothing is lost, and both ends report states
that are individually accurate. What is absent is any signal that the two disagree, so the
default outcome of a dropped handoff is silence rather than a complaint.

This is the same `unknown`-vs-`open` ambiguity the file queue was built to remove,
reappearing one step earlier in the pipeline. The queue moved the ambiguity from
*after arrival* (a human forgetting to write a ledger row) to *before arrival* (nobody
observing an open pull request). The earlier fix's own reasoning applies unchanged: a
state whose visibility depends on someone remembering to look in a second place is the
state that gets missed.

Motivating use case (generic):

A consumer vault hit an engine defect during unrelated work, packaged it through this
skill, and pushed it. `push` reported success. The consumer reported to its human that the
defect had been filed and, on the strength of `status --slug` returning
`SUBMITTED, not yet merged`, described it as delivered.

The human then checked the engine-dev side and found no outstanding proposals, and had to
come back and ask whether it had actually landed. Only that question surfaced the gap. The
proposal was in fact sitting as a green, mergeable, non-duplicate pull request the whole
time — correctly prepared, publicly visible, and outstanding to no one.

The before/after was then confirmed directly, with nothing else changed:

  - Pull request open, checks green, `mergeable`, adding `proposals/<slug>.md` —
    `queue` on the engine-dev side reported **zero** open proposals awaiting intake.
  - The same pull request merged, no other edit — `queue` reported it immediately.

So the invisibility is exactly co-extensive with the unmerged state; nothing else about the
proposal changed between the two observations. A reviewer wanting to reproduce this needs
only to submit a proposal and run `queue` before merging.

Two details make this a mechanism problem rather than a consumer mistake:

  - The consumer's misreading was real (the `until merged` wording was there to be read),
    but nothing structural would have caught it. Had the human not asked, the proposal
    would simply have sat.
  - The verification the consumer *did* perform was the one the skill prescribes —
    `status --slug` rather than a git-log grep — and it returned an accurate answer that
    still supported the wrong conclusion, because "the pull request is the record" reads
    as *delivered* rather than as *awaiting an action by someone who cannot see it*.

Proposed shape:

Give the engine-dev end one surface where a pushed-but-unmerged proposal appears. Sketch,
held loosely:

  - `queue` additionally lists open pull requests that add a `proposals/<slug>.md`,
    labelled distinctly from merged-and-open proposals — the distinction matters, because
    an unmerged one needs a *merge*, not a design review.
  - Remote lookup degrades gracefully and *says so*: on no network or no host CLI, print
    that the remote could not be checked rather than silently omitting the section. A
    surface that is quietly empty when it cannot look is the failure being fixed, one
    level up. (Same reasoning as the existing empty-case message that was corrected to
    name what it actually scanned.)
  - Optionally the engine-dev session banner nudges when open proposal pull requests
    exist, which is where a consumer-side equivalent already landed.

Alternatives considered:

  - **Write the ledger row at `push` time instead of at merge.** Rejected: it records
    arrival for a pull request that may never merge, and re-introduces exactly the
    un-observed marker the file queue replaced. Arrival should stay derived from merge.
  - **Require the consumer to merge its own proposal.** Rejected: it is impossible in the
    no-write-access case, which is the case the fork path exists to serve, and it is the
    configuration where this gap bites hardest.
  - **Documentation only** — state more loudly that `push` is not arrival. Rejected on the
    file queue's own precedent: the previous mechanism also documented its bookkeeping step
    and the step still got missed. That reasoning is why the queue exists.
  - **Have the consumer poll `status` until it flips to `open`.** Rejected: it makes the
    consumer responsible for chasing an action only the other end can take, and gives the
    engine-dev end no signal at all.

Acceptance criteria:

  - With a proposal pushed and its pull request unmerged, a single command on the
    engine-dev end lists it, distinguishing "needs merge" from "merged, awaiting review".
  - The same holds when the pull request originates from a fork (the no-write-access path).
  - With no network or no host CLI available, the command states that remote proposals
    could not be checked; it never renders an empty or partial list as complete.
  - Once merged, the proposal appears exactly once — the remote-derived entry does not
    double with the file-derived one.
  - Arrival remains derived from the merge; nothing in this change writes a ledger row
    earlier, and `PROPOSALS.md` stays generated.
  - Boundary: the added output carries repository and pull-request identifiers only, no
    consumer-vault identifiers, and the block adds no consumer-side node.

Related queue entries (checked, not duplicates):

  - `bare-status-ignores-submitted-markers` (accepted) — the *consumer*-side twin: bare
    `status` could not see its own submitted markers. Same shape of defect, opposite end
    of the channel. This proposal is the engine-dev-side counterpart, and the pair
    suggests the general rule: every state the channel can be in should be listable from
    both ends.
  - `session-banner-pending-proposal-nudge` — resolved as an alias of
    `engine-proposal-file-queue`, so the banner idea has a home but was absorbed rather
    than built for this case.
  - `engine-proposal-file-queue` — the change that created the queue; the natural place
    for this to be treated as unfinished business rather than a new mechanism.

Instruction to engine-dev: create the project in the engine-dev vault, build it, ship it
in the engine so consumer vaults receive it on their next update. Treat the proposed
shape as a sketch — the load-bearing claim is the gap, not the remedy.
