---
slug: rag-build-no-concurrency-lock
outcome: accepted
reason: "built the suggested shape: a per-vault lock (lock-lib, <vault>/.rag/build.lock) plus a rebuild-owed flag the holder serves before releasing, so any number of callers costs one extra pass and a late commit is still indexed. Reproduced at v3.9.0 with a slow stub embedder (2 embeds in flight). The unverified interleave of index.jsonl and vectors.npz is closed by the same lock rather than separately tested. Also: dead-holder reclaim, --force carried through the owed flag, and distill-finish reports a deferred rebuild."
received: 2026-11-17
---

HANDOFF — engine defect report
slug: rag-build-no-concurrency-lock
boundary: generic (engine-domain; contains no consumer-private context)

Title: rag-build.sh runs unbounded in parallel, so concurrent distill-finish runs exhaust host memory

Engine version: v3.9.0 (plugin)
Still live at that release: `grep -ciE lock bin/rag-build.sh` returns 0 at v3.9.0; reproduced on the same day.

Observed:
Two sessions ran distill-finish.sh about 25 seconds apart, each from its own session worktree.
Each run reached step 4 (recall index) and launched bin/rag-build.sh against the same canonical vault.
The two embedder Python processes ran side by side; `top` showed each at a 16G memory footprint.
On a 24 GB host this left 138M free with 13G-18G in the compressor and heavy swapping; load average about 10.
Stopping one build returned about 7G free within seconds.

Expected:
At most one rag-build.sh embeds a given vault at a time.
A second caller should wait for the running build, or skip and leave a rebuild owed, rather than start a second embedder.
distill-finish.sh already serialises its integrate step through lock-lib.sh; the index rebuild that follows it has no equivalent.

Reproduction (generic):
  1. Have a consumer vault with a provisioned .rag/ index (so distill-finish step 4 runs).
  2. From two sessions, run distill-finish.sh --work <worktree> so both land a commit within the same minute.
  3. Watch `top -o mem` while both are in step 4.
  -> two Python embedder processes, each holding a multi-GB footprint at once, against the same <vault>/.rag/.

Failure shape: fail-closed for correctness (output files are written via tempfile + os.replace), but resource exhaustion on the host.
Possible fail-open aspect, NOT verified: index.jsonl and the vectors sidecar are each replaced separately, so two interleaved builds might leave the two files from different builds; and a build that started before a sibling commit landed can replace a newer index last (last writer wins, older content).

Already ruled out:
- Not a recursion or hook spawn: both builds were children of human-initiated distill-finish.sh runs.
- Not a corrupt partial write: both writes go through tempfile + os.replace.
- Killing one build is safe for distill-finish: step 4 treats a failed rebuild as optional and continues.

Suggested fix (HOLD LOOSELY — may be wrong):
Take a per-vault lock (lock-lib.sh, keyed on <vault>/.rag) around the embed-and-replace in rag-build.sh.
On contention, either wait, or mark a rebuild as owed so the running build re-runs once at the end, which also covers the stale-last-writer case.
A rebuild-owed flag needs only one extra pass however many callers arrive, unlike plain waiting.

Redactions: vault path written as <vault>, worktree path as <worktree>; process IDs, host name and session IDs omitted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
