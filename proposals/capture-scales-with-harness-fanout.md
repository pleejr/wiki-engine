---
slug: capture-scales-with-harness-fanout
outcome: accepted
release: v1.65.0
received: 2026-08-13
reason: "real, and ALREADY FIXED when this was intaken — by 51ef084 (v1.65.0), which shipped an hour earlier in the same drain for a separate report of the same phenomenon. Not closed on paper: reproduced in this report's own shape at the pin it names, 30 ephemeral no-repo directories adding +30 blocks at v1.64.0 and +0 at v1.66.0, with a real repo still filing one block in both runs as the control. Then pinned with its own CI gate, because 'it does not reproduce' is a statement about today. The gate is separate from the sibling one on purpose: that one fans out over a workspace whose repos exist but are unchanged, this one over directories containing no repository at any depth and outside the vault. Both reach the suppression by different routes through the selection logic, and only the first was covered. The report's open question — capture layer or embedding layer? — is answered as CAPTURE: a block never written cannot become a chunk, whereas excluding content-free blocks only at embed time would leave the buffer full of filler for the human distillation pass, which is the cost the sibling report measured. The suggested first shape (skip when no repo at any depth AND outside the vault) was not built as stated: keying on the BLOCK's emptiness subsumes it, needs no vault-relative path test, and also covers an interactive session that did nothing. The environment opt-out was declined for the reason the report itself gives — it relies on every harness author knowing to set it. One residue this does not address, and it is not an engine defect: content-free blocks already sitting in a consumer's buffer and index remain until pruned and reindexed once, by hand."
---

HANDOFF — engine defect report
slug: capture-scales-with-harness-fanout
boundary: generic (engine-domain; contains no consumer-private context)

Title: session capture is per-invocation, so a fan-out harness inflates the buffer by two orders of magnitude and that inflation is embedded into the recall index

Engine version: v1.64.0
Still live at that pin: reproduced today at v1.64.0, twice in one day. Read `rag-capture.sh` at this pin to confirm the mechanism rather than inferring it, and measured the downstream effect on the index before and after pruning.

Observed: the SessionEnd capture appends one block per invocation. That assumes an invocation is a human working session. A fan-out harness — anything firing many headless one-shot runs, each in its own throwaway working directory — breaks the assumption, and capture scales with the harness rather than with sessions.

Measured in one day on one consumer vault:

  - 110 blocks from throwaway per-run working directories created by a single evaluation harness, each named `<harness>-cwd-<random>` and containing no repository at all.
  - 19 further content-free blocks.
  - 15 ordinary repository state blocks — branch, head, recent commit subjects — which is the intended output.

A prune marker already in the same buffer, timestamped earlier the *same day*, records 65 content-free captures removed from two concurrent harness runs. So this had already happened once and been cleaned up by hand before the second occurrence.

**The content-free block text is NOT the defect.** `rag-capture.sh` emits `no repo activity found` and `no new repo state` deliberately, and the in-file comments state the reasoning: the message names the criteria rather than asserting no repository was worked in, and it keeps "a session happened here" true. That reasoning is sound for a human session and is not what this report challenges.

The defect is that capture has no notion of an **ephemeral** invocation, so the buffer's size becomes a function of harness fan-out.

That matters because the buffer is embedded. `rag-build.sh` indexes `raw/sessions`, so the blocks become chunks competing with curated notes at retrieval time:

    before pruning:  152 chunks from raw/sessions, 1537 chunks total
    after pruning:     8 chunks from raw/sessions, 1393 chunks total

144 chunks, **9.4% of the whole index**, were content-free capture blocks from one day. The consuming skill's own instructions describe this buffer as something to keep short so it does not "dilute recall" — which is precisely what occurred, silently.

Expected: an invocation that is transparently ephemeral — no repository anywhere under the working directory, a directory created and discarded by a harness — should either not be captured, or should be captured in a form that does not reach the embedding pass.

Reproduction (generic):
  1. On a vault with the engine pinned and a `.rag` index present, note the current counts:
     `grep -c 'raw/sessions' <vault-root>/.rag/index.jsonl` and `wc -l < <vault-root>/.rag/index.jsonl`
  2. Run any harness that fires N headless one-shot sessions, each with its working directory set to a fresh temporary directory containing no repository. N in the dozens is enough.
  3. Inspect `raw/sessions/<month>.md`
  -> one `## <timestamp> — workspace: <name> (no repo activity found)` block per invocation
  4. Run `engine/bin/rag-build.sh`, then re-measure the two counts from step 1
  -> the buffer's blocks are now chunks in the index, in proportion to N

Failure shape: fail-open. Nothing errors, no exit status changes, and every individual block is correctly formed. Retrieval quality degrades quietly, and the only symptom is a buffer whose size is easy to misread as a prune backlog — which is exactly how it was misread here before the file was opened.

Already ruled out:
  - The content-free message being an oversight. It is deliberate and the reasoning is in the source comments at this pin.
  - `rag-build.sh` mis-selecting inputs. It indexes what the buffer contains; the buffer is the layer with the wrong contents.
  - A missing or un-run prune. The prune had run — a marker earlier the same day removed 65 such blocks — so this is regeneration faster than hand-pruning, not neglect.
  - Volume being an artifact of one unusual harness. It occurred twice in one day from different runs.

Suggested fix (HOLD LOOSELY — may be wrong): the cheapest shape is probably to skip the append entirely when the working directory contains no repository at any depth AND is outside the vault, since that combination is what an ephemeral harness directory looks like and a human session in such a directory has nothing to record either way. An environment opt-out a harness can set is simpler but relies on every harness author knowing to set it. A third option is to keep writing the blocks but exclude content-free ones from the embedding pass, which preserves the "a session happened here" evidence the comments value while removing the retrieval cost — that may be the better trade, and a reviewer is better placed than this reporter to judge it.

Redactions: the harness and workspace names were replaced with `<harness>-cwd-<random>`; they were generated identifiers naming a consumer-side tool and carried no meaning beyond being distinct. The vault root is written as `<vault-root>`. Repository names in the 15 ordinary blocks are omitted entirely; only their count is relevant. Nothing else was removed, and the measured numbers are unmodified.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification — in particular, whether the right layer is capture or the embedding pass is a genuine open question, and this report deliberately does not settle it.
