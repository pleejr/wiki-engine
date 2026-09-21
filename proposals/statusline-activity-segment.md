---
slug: statusline-activity-segment
outcome: accepted
received: 2026-09-21
reason: "accepted as proposed, named `activity` (the slug's word; the proposal offered `work` or `activity`). The process-shape claim was checked on a live host before building: a tool command runs as `<shell> -c source …/shell-snapshots/snapshot-… && …`, a direct child of the client whose argv0 is `claude`, and a backgrounded one stays that child after its tool call returns — so the process table does see exactly the case the marker-file alternative misses. The client is found by walking UP from the segment's own process, never by name alone: a second session on the same machine was live during the check, and a by-name lookup would have counted its work. That walk also yields the ancestry to exclude, so the segment cannot count itself however the host spawns the status line. Degrades to silence when no `claude` ancestor exists (an install that runs the client under `node` gets silence, declared in the source) or no child matches the shape; CI proves the shape-mismatch control is silent under the same fake client that counts two tool-shaped shells. Frame state is one small file per session under the cache directory, pruned after a day by the next session's first render. Not added to the default row: it animates only with `refreshInterval`, which is the row owner's setting. Measured at about 49 ms per render on the intake machine."
---

HANDOFF — engine improvement proposal
slug: statusline-activity-segment
boundary: generic (engine-domain; contains no consumer-private context)

Title: Add a status-line segment that shows shell work still in flight, so a backgrounded script is visible after the turn that launched it

Problem: The host animates a spinner while the assistant's turn is running. A
backgrounded command outlives that turn: the tool call returns immediately with a
task id, the turn ends, the spinner stops, and the script keeps running with
nothing on screen saying so. The same blind spot covers a long foreground command
the session is waiting on before it can proceed — the row is silent about whether
anything is happening at all. The status line is the one always-drawn surface that
could carry this, and no segment reports it.

Motivating use case (generic): an operator starts a long-running script in the
background, continues the conversation, and later cannot tell from the screen
whether it is still running or finished minutes ago without asking the assistant
to check.

Proposed shape: a segment — `work`, or `activity` — that reports the session's own
live shell commands and prints nothing when there are none. It reads the process
table rather than any marker file: the children of this session's client process
that were launched through the host's shell snapshot, minus the segment's own
ancestry so it never counts itself. Output is a spinner frame plus the count. The
frame index is stored per session and advances once per render, so a row whose
`statusLine.refreshInterval` is 1 animates at one frame per second and a row
without it still shows a static indicator plus an accurate count.

Reading live processes is what makes it self-clearing: a finished task disappears
because the process is gone, with no hook to fire and no marker that can go stale
across a crash.

One honest fragility, declared rather than discovered later: identifying the
session's shells depends on a host-internal invocation shape. If that shape
changes the segment must degrade to SILENCE, never to a wrong count — a row
claiming one task is running when none is is worse than a row that says nothing.

Alternatives considered:
  - Hook-maintained marker files (a pre-tool hook writes, a post-tool hook clears):
    rejected. A backgrounded command returns from its tool call immediately, so the
    marker clears while the script is still running — it reports the wrong thing in
    exactly the case that motivated it. A crashed session also leaves the marker
    behind forever.
  - Reading the host's own background-task registry: not available. The status-line
    payload carries no such field, and the hook payloads that do carry one deliver
    it at turn end, which is both too late and stale between turns.
  - Leaving it to the host's spinner: it stops when the turn stops, which is
    precisely when the background case starts.

Acceptance criteria:
  - `--segments` lists the new name.
  - With no shell work live, the segment prints nothing and exits 0.
  - With at least one live, it prints a frame and the count.
  - It never counts itself or its own ancestry.
  - Consecutive invocations for the same session advance the frame.
  - NO_COLOR is honoured and every path exits 0.
  - If the host's process shape stops matching, the segment is silent — never wrong.
  - Cheap enough for a once-per-second render: a consuming row carrying this plus a
    context gauge and two usage figures measured 66ms per render on the reporter's
    machine.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
