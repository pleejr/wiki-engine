---
slug: session-banner-reimplements-lease-liveness
outcome: accepted
reason: "Accepted as reported, including the fix the reporter held loosely — and the caveat they raised against it is the reason it is right rather than an objection to it. The `no git` constraint is not violated by sharing `lease_live()`: the structural proof reaches `git branch --list` only for a lease whose recorded worktree directory is already gone, so every live and every crashed session is still decided by file reads, and a vault with no ghosts pays no git at all. Liveness now lives in `bin/lease-lib.sh`, which both surfaces source; the shared unit is the WALK as well as the test (`count_other_live_leases`), since a caller that re-opens the lease directory to get a number is how this divergence started. Shipped in v1.72.0."
received: 2026-08-18
---

HANDOFF — engine defect report
slug: session-banner-reimplements-lease-liveness
boundary: generic (engine-domain; contains no consumer-private context)

Title: session-banner.sh re-derives lease liveness from the heartbeat alone, so a provably-finished session is announced as a live peer

Engine version: v1.71.0
Still live at that pin: reproduced just now on a vault pinned to v1.71.0 — `engine/bin/session-banner.sh` printed
  `⚠ 1 other session(s) writing — take a worktree` while `engine/bin/vault-worktree.sh peers`, run against the
  same `.leases` directory seconds later, printed `(no live sessions)`.

Observed: one orphan lease file remained in `<worktree-root>/.leases/<session-a>.lease` after its session ended
  without releasing it. Its `worktree=` directory no longer exists on disk and its `branch=wt/<session-a>` no
  longer exists in the repository — `git worktree list` shows only the canonical checkout, and `git branch --list
  'wt/*'` is empty. Its `heartbeat=` was ~37 minutes old, inside the 120-minute `WIKI_LEASE_STALE_MIN` default.
  The banner counted it as a live peer; the `peers` verb did not.

  The two disagree because they answer the question in different places. `vault-worktree.sh:125 lease_live()`
  calls `lease_finished()` first and only falls back to the clock. `session-banner.sh:34-43` inlines its own
  loop that reads `session=` and `heartbeat=` and applies the clock test alone — `lease_finished()` is never
  consulted, so the "both worktree and branch are gone" proof is unreachable from the banner.

Expected: the banner reports the same peer count as the `peers` verb for the same lease directory — here, none.
  I am citing what `lease_live()` DOES, not what any tool prints: it treats a lease whose worktree and branch
  have both disappeared as a finished session regardless of heartbeat, which is exactly this lease. The engine's
  own comment at `vault-worktree.sh:122` states liveness is decided in ONE place so that `peers`,
  `for_other_live_leases` and `gc` cannot disagree — the banner is a fourth call site that does.

Reproduction (generic):
  1. From a vault checkout, run `engine/bin/vault-worktree.sh ensure` in a session, so it writes a lease.
  2. End that session, then remove its worktree and delete its `wt/<session>` branch (i.e. complete the clean
     integrate + gc path), but leave the `.lease` file in place — the state a session leaves when it stops
     before its lease is released.
  3. Within `WIKI_LEASE_STALE_MIN` of that lease's last heartbeat, start a new session in the same vault.
  -> `engine/bin/session-banner.sh` prints `⚠ 1 other session(s) writing — take a worktree`
  -> `engine/bin/vault-worktree.sh peers` prints `(no live sessions)`

Failure shape: fail-open. Nothing refuses and nothing is lost, but the banner emits a confident warning that is
  wrong, and its output carries no way to tell a ghost from a real peer. The cost is the one
  `vault-worktree.sh:96` already names: "a registry that shows ghosts stops being read" — so the degraded signal
  is the NEXT, genuine peer warning being ignored. Worth noting the ghost self-clears at the stale cutoff, which
  makes it easy to dismiss as transient rather than as a divergence that recurs on every unreleased lease.

Already ruled out:
  - Not a stale-threshold tuning problem. Lowering `WIKI_LEASE_STALE_MIN` would shorten the ghost window but
    leaves the divergence intact, and shortens it for genuinely-live quiet sessions too.
  - Not an orphaned-lease-cleanup problem. `gc` clears this one, but the banner runs at session START, before
    any cleanup a user might run, and the two implementations would still disagree on the next orphan.
  - Not a process-liveness question. The engine's comment at `vault-worktree.sh:118` already explains why the
    recorded pid is not usable, and I am not proposing pid checks.

Suggested fix (HOLD LOOSELY — may be wrong): have the banner consult the single liveness decision rather than
  re-deriving it — source the helper, or shell out to the `peers` verb and count its rows.

  Read this against the banner's own constraint before adopting it. `session-banner.sh:25` states the peer block
  is "local file reads only, no git, no network", and that is deliberate for a script on the session-start path.
  `lease_finished()` runs `git branch --list`, so the obvious fix contradicts the constraint the banner was
  written to. I do not know which of the two should give way, and that is the actual design question here — my
  Expected (the two agree) survives either resolution; the specific fix above may not.

Redactions: absolute paths replaced with `<vault>` / `<worktree-root>`; the orphan lease's session UUID replaced
  with `<session-a>` consistently, including inside its branch name. No other content was removed — the lease
  file's remaining fields (`started`, `paths`, `project`) were present and empty or unremarkable.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not
a specification — in particular the no-git constraint tension above is unresolved on my end.
