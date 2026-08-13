---
slug: rag-capture-fetch-clause-selects-repos-the-engine-itself-fetched
outcome: partially-accepted
received: 2026-08-12
reason: "The defect and its mechanism are accepted in full and fixed at the writer (sync-clones restores the timestamps it disturbs, on every path out of the fetch). Shape (b) — require the fetch to have changed a remote-tracking ref — is DECLINED: the clause detects operator ACCESS, and reviewing an already-current repo produces a no-op fetch, so that test would delete the case the clause was added for. Shape (a) is what shipped, and its stated limit stands: a consumer's own `fetch --all` is indistinguishable from access and is documented rather than handled. One residual is disclosed rather than fixed — a fast-forward that brings a genuinely recent commit still selects the repo, via the separate COMMIT clause, which is that clause telling the truth about a repo that moved."
---

HANDOFF — engine defect report
slug: rag-capture-fetch-clause-selects-repos-the-engine-itself-fetched
boundary: generic (engine-domain; contains no consumer-private context)

Title: A bare `FETCH_HEAD` mtime selects a repo as worked, and `upkeep.sh sync-clones` stamps that mtime on every clone it manages

Engine version: v1.54.2 (pinned; adopted today)
Still live at that pin: reproduced in a throwaway fixture built against the v1.54.2
  checkout, after `update.sh` advanced the pin and `adopt.sh` was re-run from the new
  copy. The v1.54.0 half of the same area is genuinely fixed and was re-measured as
  fixed (see "Already ruled out"), so this is not the earlier report resurfacing.

Observed:
  v1.54.0 correctly time-bounded the workspace `touched()` scan and added a
  fetch/checkout clause (`access_recent`, reading `FETCH_HEAD` mtime and the `HEAD`
  reflog) to cover read-only sessions. That clause is satisfied by a fetch that
  brings back nothing, on a repo that is otherwise entirely quiet.

  In a workspace holding one clone with a clean working tree, a six-week-old newest
  commit, no `HEAD` reflog and no `FETCH_HEAD`, the scan correctly declines it:

    ## <ts> — workspace: ws (no repo activity found)

  A single `git fetch` against an already-current remote — exit 0, nothing
  transferred, `HEAD` unchanged — flips the same repo, unchanged in every other
  respect, into a full repo block:

    ## <ts> — quiet-repo@main (a89b5d7)

  Nothing distinguishes that block from one produced by a session that actually
  worked in the repo.

  The engine ships a verb that does exactly this to every repo it knows about.
  `bin/upkeep.sh` `sync-clones` iterates the repo pages' clones and runs
  `git fetch --quiet` on each; a clone that is already current is counted `current`
  and skipped *after* the fetch has already run. So one `sync-clones` run stamps a
  fresh `FETCH_HEAD` across the whole workspace, and the next session-end capture
  records every one of those repos as worked.

Expected:
  A repo the operator never opened should not appear in the session buffer, and in
  particular the engine's own maintenance verbs should not manufacture the signal
  another engine tool reads as evidence of work. This is the same hazard v1.54.0
  already reasoned about and rejected a different signal for: the index mtime was
  turned down because the scan's own `status --porcelain` rewrites a stale index and
  would stamp every repo as just-accessed — "the reported symptom again with a new
  cause". `FETCH_HEAD` has that property with respect to a sibling verb that ships in
  the same engine.

Reproduction (generic):
  1. Create a bare origin and a clone under a workspace root, with a single commit
     dated well outside `RAG_CAPTURE_SINCE` (default 12 h). Point `WIKI_PATH` at a
     minimal vault declaring a boundary.
  2. Remove the clone-time signals so the repo is genuinely quiet:
       rm -rf <clone>/.git/logs <clone>/.git/FETCH_HEAD
  3. From the workspace root:  WIKI_PATH=<vault> <engine>/bin/rag-capture.sh
     -> "workspace: ws (no repo activity found)"   # correct
  4. Run a real, no-op fetch, then clear the reflog it writes so only FETCH_HEAD
     carries a fresh mtime:
       git -C <clone> fetch --quiet ; rm -rf <clone>/.git/logs
  5. Re-run the capture from the workspace root.
     -> "## <ts> — quiet-repo@main (<sha>)"        # selected, nothing else changed

  Step 4's fetch transfers nothing and leaves HEAD unchanged; the mtime alone is the
  whole difference between the two runs.

Failure shape: fail-open

  The capture exits 0 and writes a well-formed block asserting work happened in a
  repo nobody opened. Nothing in the block's shape marks it, and `SCHEMA.md` names
  this buffer as distillation input while `rag-build` indexes it — so the wrong
  association is retrieved later as evidence. A consumer asking a future session
  "what was I working on" gets the answer the maintenance verb produced.

Already ruled out:
  - Not the v1.54.0 dirt defect resurfacing. That fix works and was re-measured on a
    real workspace at this pin: a repo carrying an untracked directory whose mtime is
    thirteen days old is no longer selected by it. Only the fetch clause is at issue.
  - Not the reflog clause. The reproduction deletes `.git/logs` at both steps, so the
    difference is `FETCH_HEAD` alone. The reflog has the same exposure in principle
    (a `checkout`/`reset` driven by tooling), but the reproduction does not rest on it.
  - Not a `RAG_CAPTURE_SINCE` tuning matter. Narrowing the window shortens the
    interval in which a tooling-driven fetch counts, but any value leaves the same
    hole immediately after a maintenance run — which is precisely when the operator's
    next session begins.
  - Not observable from live data alone. A workspace whose repos were all fetched
    during a working day is indistinguishable from one swept by tooling; the fixture
    is what separates them, and a report resting on the live buffer would not have
    been evidence.
  - Not fixed by dropping the clause. It was added deliberately to cover read-only
    sessions, and that case is real — removing it re-opens the gap that motivated it.

Suggested fix (HOLD LOOSELY — may be wrong):
  Two directions, offered because they differ in what they assume, not because either
  is worked out:
  (a) Have the engine's own fetching verbs declare themselves — `sync-clones` records
      the clones it fetched and when, and `touched()` discounts a `FETCH_HEAD` whose
      mtime matches a fetch the engine performed. It fixes the named trigger and
      nothing else; a consumer's own `fetch --all` sweep still selects everything.
  (b) Require the fetch to have *changed* something — compare the remote-tracking refs
      rather than the file's mtime, so a no-op fetch is not a signal. This covers any
      caller, not only the engine's, but it also loses the genuine case where someone
      fetches an already-current repo while working in it.
  The choice depends on whether the clause is meant to detect *access* or *change*,
  which the design should state either way — the current behaviour reads as access and
  is documented as "a fetch or a checkout", and those diverge exactly here.

Redactions:
  The live-workspace observations are described by shape only — no repo names, org,
  paths or counts of a real estate. The reproduction is fully self-contained and needs
  none of it. `<vault>`, `<engine>` and `<clone>` stand for absolute paths, used
  consistently. Fixture output is verbatim apart from the timestamp, shown as `<ts>`.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
