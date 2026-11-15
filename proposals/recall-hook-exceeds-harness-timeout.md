---
slug: recall-hook-exceeds-harness-timeout
outcome: partially-accepted
reason: "partially accepted. Reproduced at HEAD with an embedder that answers after 30s: the hook ran 31s with no bound of its own, so under the 10s hooks.json timeout the harness, not the hook, ends the run and shows the error. Fix 1 shipped: recall-hook.sh runs recall.sh in its own process group under RAG_RECALL_DEADLINE (default 6s) and on expiry kills the group and exits 0 silently; killing only recall.sh would leave the embedding process holding its connection, so the group kill is asserted separately. CI asserts stdin timeout + deadline + 1s stays below the hooks.json timeout. Fix 2 (binary vector sidecar) held: it changes the on-disk index contract and needs the design pass; fix 1 alone produces the Expected, as the report itself said. Measured on a reporter-shaped vault at intake: one recall.sh run took 10.1s wall on 2.2s CPU, and across runs the model init stage varied 0.35-2.7s while the index parse held at ~1.0s, with a real-time file scanner busy; the variance is wait time in model load, which a vector sidecar would not remove, so fix 2 is held as a separate latency improvement, not this defect's fix."
received: 2026-11-15
---

HANDOFF — engine defect report
slug: recall-hook-exceeds-harness-timeout
boundary: generic (engine-domain; contains no consumer-private context)

Title: recall-hook.sh intermittently exceeds its 10s UserPromptSubmit timeout and surfaces a visible error

Engine version: v3.7.3
Still live at that release: read origin/main at tag v3.7.3 on 2026-11-15 — hooks/hooks.json still sets "timeout": 10 for recall-hook.sh, and bin/recall-hook.sh has no internal deadline (its header says "the hook's own timeout in hooks/hooks.json bounds the latency"). No open proposal in proposals/ covers it.

Observed: from time to time a session shows
  UserPromptSubmit hook ["${CLAUDE_PLUGIN_ROOT}/bin/recall-hook.sh"] timed out after 10s — output discarded. Raise the hook's "timeout" to allow more time.
The prompt proceeds; that turn gets no recall pointers and the user sees the error.
Per-prompt cost, measured 2026-11-15 on one consumer vault with a fastembed backend (BAAI/bge-base-en-v1.5, ONNX, ~208M of weights) and a .rag/index.jsonl of 114M / 6726 chunks:
  - recall.sh end to end, warm: 1.5s, 1.9s, 2.4s across three runs
  - Python start + model load + query embed: 0.4–0.9s
  - json.loads over every line of index.jsonl: 0.9s (vectors are stored as JSON text inside each line)
Every prompt pays both costs from cold, because each hook run is a fresh process.

Expected: the hook header says it is "Quiet by design" and "Always exits 0, so a slow or broken index can never block a prompt". A slow run should therefore end silently with no recall, not be killed by the harness with a user-visible error. The harness timeout is the outer bound, not the intended exit path.

Reproduction (generic):
  1. Consumer vault with a local-backend .rag index of ~100M+ (a few thousand chunks).
  2. Submit prompts of 4+ words while the machine is under load (other sessions submitting at the same moment, a real-time file scanner active, or immediately after rag-build rewrote the index).
  -> intermittently: the "timed out after 10s — output discarded" error above.
  The spike past 10s was NOT reproduced on demand; only the 1.5–2.4s warm baseline was measured.

Failure shape: fail-closed (prompt proceeds, nothing lost; recall is skipped for that turn and a misleading "raise the timeout" error is shown, which invites a local edit to the plugin's hooks.json that the next update discards).

Already ruled out:
  - Not a hang on stdin: the bounded read (RAG_RECALL_STDIN_TIMEOUT) returns promptly.
  - Not a missing model or offline fetch: the venv path sets HF_HUB_OFFLINE and warm runs finish in ~2s.
  - Transcripts do not record the harness timeout message, so frequency and timing could not be measured from history.
  - Root cause of the >10s spikes is a hypothesis: candidates are CPU contention from a real-time file scanner (observed at ~90% CPU on the reporting machine), several sessions firing the hook at once, and a first read of a freshly rewritten 114M index. None verified.

Suggested fix (HOLD LOOSELY — may be wrong):
  1. Give recall-hook.sh its own deadline below the harness timeout (e.g. RAG_RECALL_DEADLINE, default ~7s): run recall.sh under it, and on expiry kill it and exit 0 with no output. This produces the Expected directly regardless of the cause of the spike.
  2. Cut the per-prompt floor: store vectors in a binary sidecar (e.g. a float32 array file next to a metadata JSONL without vectors) so recall loads the matrix instead of json-parsing every vector as text. Lowers how often the deadline is reached; does not by itself guarantee the Expected.
  Fix 1 alone satisfies Expected; fix 2 is a latency improvement. If only one ships, keep fix 1.

Redactions: the consumer vault name, its absolute path and the user's home directory were removed; the endpoint scanner product name was generalised to "a real-time file scanner". Numbers and the error text are verbatim.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
