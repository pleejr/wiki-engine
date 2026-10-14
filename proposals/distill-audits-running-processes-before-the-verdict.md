---
slug: distill-audits-running-processes-before-the-verdict
outcome: partially-accepted
reason: "partially-accepted. Reproduced the gap at 3.5.0: distill step 5 named background shells, monitors, subagents and wakeups but gave no way to list them. ACCEPTED: bin/session-processes.sh lists the session's OS processes from one ps snapshot, rooted at $CLAUDE_PID or the nearest `claude` ancestor, excluding the audit's own shell; distill step 5 classifies every entry as legitimate or not, stops a not-legitimate one with a one-line record or reports it, keeps a legitimate running one outstanding, and the verdict states the audit's count. Measured against a live session, the harness's own status-line shell read as session work; tool shells are now told apart by the shell-snapshot marker, trusted only when the audit's own shell carries it, and every shell counts as session work otherwise, so a changed marker over-reports rather than reading as nothing running. The marker is the one statusline.sh's activity segment already counts tool shells by, so the two readers cannot disagree about what a tool shell is. NOT BUILT: listing the harness's background tasks from the tool. Subagents, monitors and wakeups are not OS processes and no script can see them, so the task-list check stays in the skill beside the audit. PARTIAL: orphans (parent died, reparented outside the tree) are found only on Linux, by the exact session id in /proc/<pid>/environ; macOS does not expose another process's environment, so there the AUDIT line says the orphan scan did not run rather than claiming none."
received: 2026-10-14
---

HANDOFF — engine improvement proposal
slug: distill-audits-running-processes-before-the-verdict
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill enumerates and judges the session's running processes before its close verdict

Problem: distill's step 5 asks the model to check "this session's own running work, which no script can see: background shells, monitors, subagents and scheduled wakeups", but gives it no mechanism. In practice the model answers from memory of its own task list. Anything it forgot, anything a tool backgrounded on timeout, and any OS process the session spawned outside the task list (a polling loop, a CLI wait) is never examined. The verdict can then read SAFE TO CLOSE while a process launched by the session is still running, or after one that ran away was stopped by hand with nothing recorded.

Motivating use case (generic): a session waited on pull-request checks with an `until <check-command>; do sleep N; done` loop. The repository had no checks configured, so the command exited non-zero with "no checks reported" on every iteration and the loop never ended. It was noticed and stopped by hand. Later, distill closed on the model's recollection of its task list and enumerated no processes at all. The operator asked that distill check for running scripts itself and judge whether each is legitimate, as an input to whether the session is safe to close.

Proposed shape:
  1. A bin tool (e.g. `bin/session-processes.sh`) that lists candidate processes for the current session: the harness's background tasks where it can see them, plus OS processes descended from the session's shells (process tree from the session's PID or process group), with command line, start time, elapsed time and parent.
  2. distill step 5 gains an explicit sub-step: run the tool, then classify every entry as
     - legitimate: expected, bounded (it has a terminating condition or a timeout), and its purpose is still open;
     - not legitimate: orphaned (parent gone), unbounded (a loop whose exit condition cannot be met, or no timeout), or its purpose already met.
  3. Not-legitimate entries are stopped (with a one-line record of what was stopped and why) or, when stopping is not the session's call, reported.
  4. Legitimate entries still running count as outstanding: the verdict is NOT SAFE TO CLOSE, naming each with the command that clears it (wait for it, or stop it).
  5. The verdict line states that the audit ran and how many processes it examined, so "nothing outstanding" is a measured claim rather than a recollection.

Alternatives considered:
  - Rely on the model's task list (current behaviour): misses forgotten tasks and every process not in the list; the verdict is unverifiable.
  - Kill everything the session started at distill: destroys legitimate long-running work (a deploy watcher the operator wants to keep).
  - A lint on wait loops at authoring time: useful, complementary, but cannot see processes already running.

Acceptance criteria:
  - With an unbounded background loop running, distill names it, classifies it as not legitimate, and the verdict is not SAFE TO CLOSE until it is stopped or explicitly kept.
  - With a bounded, still-needed background wait running, distill reports it as legitimate and outstanding, with the command to clear it.
  - With nothing running, the verdict says the audit ran and found zero processes.
  - The tool never lists or stops processes outside the current session's tree.
  - The scan passes the engine-proposal boundary gate.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
