---
slug: rag-capture-skip-headless-one-shots
outcome: open
received: 2026-08-13
---

HANDOFF — engine improvement proposal
slug: rag-capture-skip-headless-one-shots
boundary: generic (engine-domain; contains no consumer-private context)

Title: SessionEnd capture floods the raw buffer when a harness fans out headless one-shots

Problem: the SessionEnd capture hook appends one block to the raw session buffer per session that ends. That is correct for interactive sessions, whose count is small and whose blocks carry real repo state. It does not hold once anything spawns headless one-shot sessions in bulk — a description-trigger evaluator, a benchmark, any fan-out that runs one query per process. Each one-shot ends, fires the hook, and appends a block. The buffer becomes mostly noise, and the noise crowds out the small number of blocks that carry a keeper.

Motivating use case (generic): a consumer ran two concurrent evaluation harnesses, each spawning one headless session per query. In a 21-minute window the buffer gained 79 blocks, of which 65 were content-free — the capture's own "no new repo state" and "no repo activity found" shapes. A one-shot that runs a single query touches no repository, so the block it produces is structurally empty. The 14 substantive blocks in the same window were from ordinary interactive work and were worth keeping; separating them was manual.

The buffer is designed as a short disposable scratch space that a periodic distillation step drains. At this volume the drain step stops being cheap, and a reader scanning for a keeper is reading almost entirely filler — which is the failure the buffer's own disposability was meant to prevent.

Proposed shape: give the capture hook a cheap precondition so it does not append a block that cannot carry information. Two candidate axes, engine-dev's call:
  - Skip when the session is a non-interactive one-shot, if the harness exposes that distinction in the hook's environment.
  - Skip when the block would be content-free — no repo activity and no new repo state. This is the more robust axis, because it keys on the block's own emptiness rather than on a session attribute that may not be exposed, and it also suppresses empty blocks from interactive sessions that did nothing.

Alternatives considered:
  - Leave it and prune harder. Rejected: the volume scales with fan-out, so the cost lands on every future distillation, and the pruning is a judgement call each time rather than a mechanical one.
  - Have consumers disable the hook while running a harness. Rejected: it requires remembering, and forgetting fails silently in the direction of more noise. It also disables capture for the interactive session that launched the harness.
  - Cap the buffer by size or age. Rejected: it would drop substantive blocks alongside filler, and the filler is not the oldest content — it is interleaved with real work.

Acceptance criteria:
  - A session that ends having produced no repo activity and no new repo state appends nothing.
  - A session with real repo state still appends exactly as it does today; no change to that block's shape.
  - The suppression is observable — a consumer can tell that suppression happened rather than that the hook silently failed, since "nothing was captured" and "the hook is broken" must not look identical.
  - Fan-out of N headless one-shots that touch no repository adds zero blocks.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
