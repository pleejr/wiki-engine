---
slug: distill-recorded-handoff-is-safe-to-close
outcome: open
received: 2026-10-08
---

HANDOFF — engine improvement proposal
slug: distill-recorded-handoff-is-safe-to-close
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill's close verdict lists a recorded hand-off under SAFE TO CLOSE instead of blocking on it

Problem: distill step 5 counts every REVIEW item this session created (its branch,
its pull request, its worktree) as outstanding, so the verdict is NOT SAFE TO CLOSE.
A pull request that is pushed, waits on another person's review, and is already
named on a tracked ticket and on the project page's Next steps survives the session
unchanged. Keeping the session open does nothing for it. The verdict then sends a
false signal: the operator is told not to close a session that has nothing left
to lose.

Motivating use case (generic): a session opens a pull request in a repository whose
owner must review and merge it. The session moves the tracking ticket to Blocked on
that person, records the wait on the project page, and runs distill. The script's
REVIEW line reports the open pull request, and the skill's rule makes the verdict
NOT SAFE TO CLOSE with "merge it" as the clearing command. That command is not the
operator's to run.

Proposed shape: in distill step 5, classify each REVIEW item this session made:
  - Recorded hand-off: the work is pushed (nothing local is lost), its next action
    belongs to someone other than the operator or this session, and a durable record
    names it (a ticket, the project page's Current state or Next steps). Listed under
    SAFE TO CLOSE as "handed off: <item> (<where recorded>)".
  - Outstanding: anything that dies with the session (running shells, monitors,
    subagents, scheduled wakeups, uncommitted edits, unpushed branches, an unmerged
    vault pull request), or an item whose ownership is not recorded anywhere. Recording
    the ownership converts it into a hand-off.
  The SAFE TO CLOSE line gains an optional "; handed off: …" tail.

Alternatives considered:
  - Leave the rule and let the operator override in conversation: the verdict line is
    what the operator reads and acts on, so a known-false NOT SAFE erodes trust in it.
  - Have distill-finish.sh decide: it cannot see tickets or who owns the next action;
    this is judgement, so it belongs in the skill text.

Acceptance criteria:
  - A pushed, recorded, other-owned pull request yields SAFE TO CLOSE with a
    "handed off" tail naming where it is recorded.
  - An unpushed branch, uncommitted edit, running background task, or unmerged vault
    pull request still yields NOT SAFE TO CLOSE.
  - An other-owned item with no record still yields NOT SAFE TO CLOSE, and its
    clearing step is "record it".
  - The proposal text passes engine-proposal.sh scan.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
