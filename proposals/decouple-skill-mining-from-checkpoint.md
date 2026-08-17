---
slug: decouple-skill-mining-from-checkpoint
outcome: partially-accepted
received: 2026-08-17
reason: "the decoupling is ACCEPTED whole and shipped as asked — checkpoint offers the pass as its last step, after commit and integrate, and a deferral writes nothing; the ordering constraint survives because the notes are on disk by then, and the retired worktree is a second reason the offer belongs last rather than earlier. The one criterion OVERRIDDEN is that skill-candidates keep handing verdicts back rather than writing them: with the call removed there is no caller to hand them to, and the proposal's own defer option depends on the write it removes — it argues no new mechanism is needed because deferrals already compound as verdict notes carrying their count, but those notes were written by checkpoint's §2b, not by skill-candidates, which wrote nothing by design. Left as proposed, the 'run it now, separately' branch ends with decisions the operator just made and no record of them, and because the two-modes check keys on a verdict note existing, every later standalone run would report backlog mode over the whole record and re-ask everything already settled. So skill-candidates gains its own worktree, commit and integrate and records its own verdicts. That does not reopen the cycle the one-way edge existed to prevent: the ban is on the two INVOKING each other, and writing a note invokes nothing — the edge count between them is now zero in both directions, which is strictly stronger than the one-way edge it replaces. No new lint gate was added for the acyclicity criterion, deliberately: no such cycle has ever occurred here, and this repo's own rule is to leave an unobserved defect unbuilt rather than guessed at. The change does put skill-candidates under lint-docs check 4 for the first time, which caught its description naming a git-ignored path with no canonical tree beside it"
---

HANDOFF — engine improvement proposal
slug: decouple-skill-mining-from-checkpoint
boundary: generic (engine-domain; contains no consumer-private context)

Title: checkpoint should offer the skill-mining pass, not perform it

Problem: `checkpoint` §2b runs `skill-candidates` automatically inside every
checkpoint, and states this is deliberate — "not as a suggestion at the end". That
couples two kinds of work with different costs and different cadences:

  - capturing state (project page, log line, distilled notes) — bounded, cheap,
    wanted every time;
  - mining the record and settling verdicts — open-ended, and it ends in
    develop/discard/defer choices the operator must answer.

An operator who wants the first cannot decline the second. §2b argues the pass is
cheap in steady state, and in *tokens* that is true — the sweep starts from the
newest verdict note. But the cost that matters is not tokens: it is a set of
decisions injected at the end of unrelated work, at the moment the operator is
trying to close out. A `develop` verdict then implies authoring a skill, which
implies an eval, which implies fixture and harness work — a chain begun by a
checkpoint the operator ran to record something else.

Measured in one consumer vault: over seven days, commits to vault-and-tooling
repositories outnumbered commits to the substantive work repositories roughly 3:1.
Not all of that is attributable to this coupling, but the loop it belongs to —
checkpoint produces notes, mining reads notes and yields a skill, the skill needs
an eval, the eval needs fixing, checkpoint records the fixing — is self-sustaining,
and this is the one edge in it that is mandatory rather than chosen.

Motivating use case (generic): a session does a piece of infrastructure work and
ends with a checkpoint to record it. The checkpoint is correct and takes minutes.
It then mines the record and presents candidate verdicts, each needing an answer
before the pass can finish and commit. The operator wanted a record written; they
are instead making tooling decisions.

Proposed shape: `checkpoint` finishes its own job — state, notes, lint, commit,
integrate — and *ends by offering* the mining pass:

  - **defer** — do nothing. The compounding list already exists: `skill-candidates`
    records every deferral as a decision note carrying the count it was deferred at,
    and re-checks those on later runs. No new file or mechanism is needed.
  - **now, separately** — run the mining pass in its own session or pane, so its
    verdicts and any authoring that follows are their own unit of work.

The ordering constraint §2b cites is real and survives this: mining must read the
notes checkpoint just wrote. Offering it *after* the commit preserves that — the
notes are on disk and pushed. Verdicts written later are ordinary notes and land in
their own commit, which is arguably better provenance than folding them into a
state-capture commit.

Alternatives considered:
  - Keep as-is. Rejected: the operator has no way to decline, and the coupling is
    the loop's only mandatory edge.
  - A flag or environment variable to skip it. Rejected: an opt-out nobody
    remembers exists is the same as no opt-out, and it adds configuration surface
    to avoid asking a question.
  - Remove the automatic call and say nothing. Rejected: mining genuinely is
    valuable, and silently dropping it loses the per-session cadence the consumer
    wants to keep — the ask is decoupling, not removal.

Acceptance criteria:
  - `checkpoint` completes fully — including commit and integrate — without
    invoking `skill-candidates`.
  - `checkpoint` ends by presenting the choice, and a deferral writes nothing.
  - `skill-candidates` run standalone in a later session still surfaces prior
    deferrals with their counts, and still hands verdicts back rather than
    writing them itself.
  - The one-way edge is preserved: `skill-candidates` must still never invoke
    `checkpoint`, so decoupling does not reintroduce the cycle the current
    §2b ordering was written to avoid.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
