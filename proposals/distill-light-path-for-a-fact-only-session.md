---
slug: distill-light-path-for-a-fact-only-session
outcome: open
received: 2026-11-19
---

HANDOFF — engine improvement proposal
slug: distill-light-path-for-a-fact-only-session
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill sizes itself to the session: a fact-only session gets a light path

Problem: distill has one depth. Every run does the full step 2 sweep (lesson,
decision and recurrence candidates) and the full step 5 verdict, whatever the
session produced. Many sessions produce almost nothing durable: a ticket resume
that re-reads a pull request, finds no change and moves a follow-up date. The
operator then either runs the full pass for a one-line change, or skips distill
and leaves a project page repeating a fact that is now false (an old due date,
an old "read at" time). Neither is right. A consumer-vault rule already says
"distilled 0 notes" is a claim that must name the candidates it ruled out, so
the light path cannot simply skip step 2 silently.

Motivating use case (generic): an operator resumes a ticket whose pull request
is still awaiting review. Nothing changed except the ticket's follow-up date.
The project page's Current state still names the old date. The operator asks
whether a full distill is warranted. The right answer is: correct the one dated
line, land it, and say why no note was written, in one line.

Proposed shape: a triage step at the top of distill (step 0.5), decided by the
model from the conversation, that picks one of two paths and says which:

  - light: every change this session made to durable state is a re-read of a
    fact the vault already records (a date, a status, a count, a "read at"
    timestamp), and the session had no scope change, wrong assumption, repeat
    of a recorded mistake, or choice with a reason.
      * step 1 shrinks to: correct each stale line in place, dated; do not
        rewrite Current state or Next steps beyond those lines.
      * step 2 is replaced by a one-line ruled-out statement naming the
        candidate classes checked (scope change, wrong assumption, recurrence,
        decision) and "none" for each. This keeps the zero-notes rule honest.
      * step 3 is skipped. Steps 0, 4 and 5 run unchanged: isolation, landing
        and the close verdict are the safety-bearing parts and stay mandatory.
  - full: anything else. Today's behaviour, unchanged.

  Any doubt picks full. The verdict line reports the path:
  `SAFE TO CLOSE — light distill: 1 line corrected; ruled out: scope, assumption, recurrence, decision; ...`

  Also: when the vault holds nothing stale and the session produced nothing,
  the light path says "nothing to distill" and still runs step 5, so the close
  verdict is never skipped.

Alternatives considered:
  - A separate `touch-up` skill: rejected; two entry points for one job, and
    the operator still has to choose which to run.
  - Operator flag (`distill --light`): rejected as the primary trigger; the
    model already has the evidence to decide, and a flag invites skipping the
    sweep on a session that needed it. Could be added as an override later.
  - Skip distill entirely for such sessions: rejected; it leaves the vault
    repeating a false fact, and loses the close verdict.

Acceptance criteria:
  - A session whose only durable change is a moved date runs the light path:
    one dated line corrected, no memory/ note, no log line, and a verdict that
    names the path and the ruled-out candidate classes.
  - A session containing any scope change, wrong assumption, recurrence of a
    recorded mistake, or reasoned choice runs the full path.
  - Steps 0, 4 and 5 run on both paths; the light path never omits the
    process audit or the VAULT line.
  - The triage decision and its reason appear in the verdict, so a wrong
    choice is visible and can be rerun as full.
  - Proposal text passes the boundary scan.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
