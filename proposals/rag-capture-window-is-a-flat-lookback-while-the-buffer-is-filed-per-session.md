---
slug: rag-capture-window-is-a-flat-lookback-while-the-buffer-is-filed-per-session
outcome: partially-accepted
received: 2026-08-12
reason: "Defect, mechanism and fail-open framing accepted in full and reproduced (six blocks, three distinct facts). The primary shape - window = since the previous capture - is DECLINED on the wrinkle the report itself names: that boundary is global while the buffer's unit is per-session, and peer sessions are a shipped feature, so the first session to end claims the interval and a longer one ending later reports a window shorter than its own life. That trades over-capture (noise) for under-capture (losing the session just had), a direction this engine already settled in the dirt-window fallback. The narrower alternative shipped instead, with the reporter's own objection to it answered: a repo block identical to the newest already recorded is not re-appended, and the session is still evidenced by an 'unchanged since <ts>' line carrying repo/branch/sha, which survives pruning of the block it refers to."
---

HANDOFF — engine defect report
slug: rag-capture-window-is-a-flat-lookback-while-the-buffer-is-filed-per-session
boundary: generic (engine-domain; contains no consumer-private context)

Title: The capture window is a fixed lookback while the hook fires per session, so consecutive sessions re-emit the same blocks instead of partitioning the day

Engine version: v1.54.2 (pinned; adopted today)
Still live at that pin: reproduced in a throwaway fixture built against the v1.54.2
  checkout. This is a property of the selection window rather than of any clause
  v1.54.0 changed, so it survived that release untouched — it is not the earlier
  `touched()` report resurfacing, and not the sibling report about the fetch clause
  (`rag-capture-fetch-clause-selects-repos-the-engine-itself-fetched`), which is about
  *which* repos are selected rather than how often the same one is.

Observed:
  `touched()` selects on a window that always runs `RAG_CAPTURE_SINCE` hours back from
  the moment the capture runs (default 12). The hook that drives it fires at the end of
  every session. Those two units do not divide the day the same way: the window is
  absolute and overlapping, the buffer's unit is a session, so two sessions ending
  inside one window both look back over the whole of it.

  Three consecutive captures over a workspace holding two repos, each with one commit
  inside the window, nothing else changing between runs:

    ## <ts1> — alpha@main (af4485c)
    ## <ts1> — beta@main  (e69baf6)
    ## <ts2> — alpha@main (af4485c)
    ## <ts2> — beta@main  (e69baf6)
    ## <ts3> — alpha@main (af4485c)
    ## <ts3> — beta@main  (e69baf6)

  Six blocks, three distinct facts, no deduplication of any kind. Every field but the
  timestamp is identical, including the sha and the commit list. The buffer therefore
  grows as (sessions x repos in window), not as work done.

Expected:
  A block filed under a session's timestamp should describe that session. Either the
  window should be bounded by what the buffer already knows — the previous capture —
  so the blocks partition the day, or an unchanged repeat should not be appended a
  second time. Which of those is right is a design question, not something this report
  should settle.

  Each individual block is *true*: those repos really did hold a commit inside the
  window. What is over-asserted is the attribution — the buffer reads as a record of
  the session it is filed under, and on a multi-session day it is a record of the same
  half-day, repeated.

Reproduction (generic):
  1. Under a workspace root, create two repos, each with one commit made now (inside
     `RAG_CAPTURE_SINCE`). Point `WIKI_PATH` at a minimal vault declaring a boundary.
  2. Run the capture three times in a row, changing nothing between runs:
       for i in 1 2 3; do WIKI_PATH=<vault> <engine>/bin/rag-capture.sh; done
  3. Inspect the buffer.
     -> six blocks, two distinct repos, identical but for the timestamp.

  A real day reaches the same state without the loop: each session end supplies one
  iteration, and the interval between them is smaller than the window.

Failure shape: fail-open

  Named that way with a caveat worth reading, because it is a design-level gap rather
  than a code error and the usual test does not apply cleanly: nothing here refuses,
  nothing is destroyed, and every fact written is accurate. What proceeds while looking
  correct is the *attribution* — a well-formed block asserting that a session's work
  included repos that a previous session, already captured, actually worked in.

  It compounds through the same path as the sibling report: `SCHEMA.md` names this
  buffer as distillation input and `rag-build` indexes it. Whether N identical blocks
  become N chunks, and whether that weights recall toward the repeated text, is a
  question about the indexer that this report deliberately does not answer — it was not
  measured, and the reporter has no evidence either way.

Already ruled out:
  - Not a `RAG_CAPTURE_SINCE` tuning matter, though narrowing the window reduces how
    much two sessions overlap. Any fixed lookback larger than the gap between two
    session ends produces the repeat, and shrinking it far enough to avoid that would
    start missing a long session's early work — trading one wrong answer for another.
  - Not the fetch clause. The reproduction selects purely on the commit clause, on
    repos with no fetch, no dirt and no reflog activity, so it holds regardless of how
    the sibling report is resolved.
  - Not deduplication happening somewhere later. The blocks are appended verbatim and
    remain distinct in the file; nothing downstream in the engine collapses them.
  - Not a prune-discipline problem. Pruning is a curation step performed against a
    buffer that has already been written, and the growth described here is a property
    of how the buffer is produced; a consumer who prunes diligently still reads the
    repeated day before deciding what to keep.

Suggested fix (HOLD LOOSELY — may be wrong):
  The buffer already records when the last capture ran, in the timestamp of its newest
  block, so the window could be "since the previous capture", falling back to
  `RAG_CAPTURE_SINCE` when there is no prior block. That makes the blocks partition
  the day rather than overlap, and needs no new state.

  Two wrinkles the reporter can see and has not resolved, offered so they are not
  discovered later as surprises:
  - Concurrent sessions share one buffer, so "since the previous capture" is a global
    boundary, not a per-session one. Whichever session ends first would claim the
    interval, and a long-running session ending afterwards would report a window
    shorter than its own life.
  - A repo worked in across two sessions with no new commit, dirt or fetch in the
    second would correctly stop appearing, which is the intended behaviour but will
    read as a regression to anyone who expects the block to list what they had open.

  A narrower alternative, if the window itself should stay as it is: skip appending a
  repo block that is identical to the newest one already recorded for that repo. It
  removes the duplication without changing what the window means, but it also loses the
  evidence that a session occurred at all, which the timestamp is currently the only
  carrier of.

Redactions:
  Nothing from a real workspace appears here — the reproduction is self-contained and
  the fixture repos are named `alpha` and `beta`. `<vault>` and `<engine>` stand for
  absolute paths, used consistently; `<ts1>`..`<ts3>` are the three run timestamps,
  which in the fixture were seconds apart. Fixture output is otherwise verbatim.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
