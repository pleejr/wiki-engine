---
slug: transcript-pointer-defeats-content-free-suppression
outcome: partially-accepted
reason: "the observation is confirmed in full and reproduced twice — at the reporter's pin and at HEAD — by a controlled A/B where only RAG_CAPTURE_TRANSCRIPT_PATH differs: flag on appends a `(no repo activity found)` block, flag off says `nothing to append` and leaves the buffer unchanged. The mechanism is as reported: the transcript line set `substantive` with no reference to whether the block carried content, and the hook supplies a transcript path every session, so on a flagged machine the emptiness gate was unreachable and v1.65.0 was not weakened but inert. Suggested fix taken as written — the pointer now augments a block rather than justifying one — and `--note` still forces one, which is the escape hatch the suppression message already advertises. PARTIAL on the open question the report deliberately left to intake: a fanned-out one-shot that did something a transcript would show still files nothing unless it passes `--note`, and that is now the decided behaviour rather than an accident. No separate mechanism was built to detect a headless one-shot; v1.65.0 declined that axis for the reason that still holds, which is that emptiness subsumes it. Worth recording for the next reader: v1.65.0's own gate was green throughout, because every one of its cases ran with the flag unset — it measured only the population that never had the bug. That is the sibling class swept for here, and no other suppression gate in bin/ takes an override from a session attribute."
received: 2026-08-22
---

HANDOFF — engine defect report
slug: transcript-pointer-defeats-content-free-suppression
boundary: generic (engine-domain; contains no consumer-private context)

Title: A transcript pointer alone marks a block substantive, so v1.65.0's content-free suppression never fires on any machine that opts into RAG_CAPTURE_TRANSCRIPT_PATH=1

Engine version: v1.73.2
Still live at that pin: reproduced at v1.73.2 by a controlled A/B run — same fixture directory, same command, only the environment variable differing. See the reproduction below; both branches were run minutes before filing.

Observed: `rag-capture.sh` appended one `(no repo activity found)` block per headless one-shot on a session that spawned roughly ninety of them. The consumer's session buffer went from 1 block to 90 in an afternoon, all content-free, all from throwaway fixture directories that contain no repo.

The suppression that should have stopped this is present and correct in the file. `substantive` is initialised to 0, the two content-free shapes deliberately do not set it, and the gate that follows exits 0 without appending. But two lines above that gate:

```
[ -n "$NOTE" ] && substantive=1
[ "${RAG_CAPTURE_TRANSCRIPT_PATH:-0}" = "1" ] && [ -n "$TRANSCRIPT" ] && substantive=1
```

The second line sets `substantive=1` unconditionally on the presence of a transcript path, with no reference to whether the block carries any repo content. The hook is invoked with a transcript path on every session, so on a machine that enables the flag the emptiness test can never be reached with `substantive` still 0. The feature is not weakened on those machines; it is inert.

The file's own comment states the intent the flag contradicts: *"A block that carries nothing is not appended at all... wrong the moment anything fans out headless one-shots: each ends, fires the hook, and files a block that a one-shot touching no repo cannot fill"*, and *"Keyed on the block's own EMPTINESS rather than on a session attribute"*. The transcript flag is a session attribute, and it wins.

Expected: a block whose repo content is one of the two content-free shapes should be suppressed regardless of whether a transcript pointer is available. The pointer is attribution *for* a block; it is not by itself a reason to file one. A machine that turns on transcript pointers is asking for better provenance on the blocks it keeps, not for the fan-out suppression to be switched off.

Reproduction (generic):
  1. Create a fixture vault: a directory with `raw/sessions/` and a `CLAUDE.md` declaring `boundary: <a boundary>`.
  2. Create an empty working directory containing no git repository — this is what a fanned-out one-shot runs in.
  3. From that directory, with the flag ON:
       WIKI_PATH=<fixture vault> RAG_CAPTURE_TRANSCRIPT_PATH=1 <engine>/bin/rag-capture.sh --transcript <any path>
     -> `rag-capture: appended session entry to raw/sessions/<month>.md`
     -> the buffer gains a `## <ts> — workspace: <dir> (no repo activity found)` block
  4. Same directory, same command, flag absent:
       WIKI_PATH=<fixture vault> <engine>/bin/rag-capture.sh --transcript <any path>
     -> `rag-capture: nothing to append — no repo activity found in the last 12h. Buffer unchanged.`
     -> the buffer is unchanged
  Only the environment variable differs between 3 and 4.

Failure shape: fail-open. Nothing errors and nothing warns; the suppression reports success by staying silent, which is indistinguishable from it working. The cost accrues where the release's own rationale predicted — a disposable buffer becomes a pile a distillation pass has to scan, and the same content-free blocks reach the recall index. The release note for v1.65.0 measured 65 of 79 blocks in a 21-minute window as these shapes, and 144 chunks — 9.4% of one vault's whole index — from a single day. That is the outcome this defect restores on any machine with the flag on.

Already ruled out:
  - Not a hook-wiring problem. The hook fires correctly; the blocks prove it.
  - Not the peer-fleet fan-out already recorded against concurrent sessions. This is one interactive session spawning headless one-shots in sequence, each ending normally.
  - Not v1.65.0 missing or unadopted. The code and its comments are present at the pinned version; the flag bypasses them.
  - Not specific to any one spawning tool. Anything that fans out one-shots — an eval harness billing one spawn per query, a batch runner, a scripted sweep — produces the same shape.

Suggested fix (HOLD LOOSELY — may be wrong): make the transcript pointer augment a block rather than justify one — that is, let it enrich a block that is already being filed, and stop it setting `substantive` on its own. `--note` is a different case and should keep setting it, because a note is content the operator deliberately supplied.

Worth deciding explicitly rather than inheriting from the fix: whether a fanned-out one-shot should be able to file a block at all when it genuinely did something a transcript would show. The reporter has no view into that trade-off; the observation above does not depend on how it is resolved.

Redactions: absolute paths replaced with `<fixture vault>`, `<engine>` and `<dir>`; the spawning tool described by behaviour rather than named, since it is consumer-private. Nothing else was removed — the two quoted source lines and both command outputs are verbatim.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
