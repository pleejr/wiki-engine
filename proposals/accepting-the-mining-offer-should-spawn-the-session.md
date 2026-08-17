---
slug: accepting-the-mining-offer-should-spawn-the-session
outcome: partially-accepted
received: 2026-08-17
reason: "Shape built as proposed — adapter seam, thin contract, fail-closed fallback, no edge back. One acceptance criterion was declined on a false premise: `checkpoint` §6 printed no command today, so the no-adapter path cannot be byte-identical to a fallback that never existed. It now prints the working directory and prompt, which is a superset of the prose it replaces, and no machine is left worse off."
---

HANDOFF — engine improvement proposal
slug: accepting-the-mining-offer-should-spawn-the-session
boundary: generic (engine-domain; contains no consumer-private context)

Title: Accepting checkpoint's mining offer should start the session, not print instructions for starting it

Problem:

`checkpoint` §6 offers two outcomes — defer, or "run it now, separately, in its own
session or pane". The second is written as advice to a human, so accepting it produces
a printed command and nothing else. Two costs follow, and the second is the one that
matters.

The operator has to perform the handoff by hand at the exact moment the pass was
designed to protect: the end of unrelated work. That is the friction the deferral
option already exists to relieve, so "run it separately" collapses toward "defer" for
reasons that have nothing to do with whether mining is worth doing.

And the parent session cannot close out. It has just committed, integrated, retired
its worktree and reindexed — it is finished — but the accepted outcome lives entirely
outside it, unstarted. So either the operator keeps a finished session open as a
reminder, or the accepted verdict quietly becomes a deferral. v1.70.0 moved the offer
to the very end *precisely* so the parent would be free at that point; the offer
cannot deliver that while acceptance is only a suggestion.

Motivating use case (generic):

A consumer runs `checkpoint` at the end of a session. It commits, integrates, retires
the worktree, reindexes, and offers the mining pass. The operator answers "run it
separately". Today: the skill prints a `cd … && <agent>` line, and the operator either
runs it now by hand or loses it. What the answer meant was *start it somewhere else and
let me close this one* — the separation is the point of the answer, not an incidental
detail of it.

Proposed shape:

Give the accept path a **spawn seam**, on the same pattern the engine already uses for
`session-checks.d/`: the engine composes an adapter the consumer's machine supplies,
without knowing anything about the host.

- Engine ships the seam and the skill text; a consumer machine drops in an executable
  adapter (e.g. `session-spawn.d/<name>` or a single `bin/spawn-session.sh`) that knows
  how to open a new pane/tab/window on that host, start an agent in it, and submit one
  initial prompt.
- `checkpoint` §6, on accept: resolve an adapter; if one exists, invoke it with the
  working directory and the skill invocation to submit, confirm the new session reached
  a running state, report its handle, and **stop** — no waiting, no polling, nothing
  comes back.
- If no adapter is present, fall back to exactly today's behaviour: print the command.
  A machine with no way to open a pane must not be worse off than it is now.
- The adapter contract is deliberately thin — working directory in, prompt in, a handle
  out, non-zero exit if it could not start. Anything richer would put host semantics
  into the engine.

Alternatives considered:

- **Run the pass inline in `checkpoint`** — this is what v1.70.0 deliberately removed,
  and re-adding it would restore the cost that release measured: develop/discard/defer
  decisions injected into the close-out of unrelated work. Rejected. The value here is
  that the pass runs *elsewhere*, not that it runs automatically.
- **Keep printing the command** — the status quo, and the thing being reported. It is
  the correct fallback and the wrong default where a host can do better.
- **Have the engine drive one specific terminal or workspace manager** — rejected;
  it would make a boundary-agnostic engine depend on one host's tooling. The engine
  should know that a session can be spawned, never how.
- **A background/headless one-shot instead of an interactive session** — rejected on the
  engine's own safety rule. The pass is interactive by design: it puts every candidate to
  the operator as a develop/discard/defer choice, so a headless run has nobody to ask.

Acceptance criteria:

  - With an adapter present, accepting the offer leaves a *running* session executing
    the mining pass, and the parent skill's final output names its handle. Verifiable by
    asserting the adapter was invoked with the intended working directory and prompt.
  - With no adapter present, the printed-command behaviour is byte-identical to today's,
    and the skill says the fallback is why.
  - An adapter that fails (non-zero exit, or a session that never reaches a running
    state) degrades to the printed command and says so. It must not report a handoff
    that did not happen — that would be the fail-open shape, and it would silently
    convert an accepted verdict into a lost one.
  - The parent skill does not wait on, poll, or read the spawned session. No edge back:
    the spawned pass records its own verdicts already, which is what makes this safe.
  - The adapter is invoked only on explicit accept, never on defer and never
    unprompted — this is not a hook, and it must not fire on a session-lifecycle event.

Note on scope, stated rather than assumed: the engine alone cannot produce the
end-to-end outcome, because the adapter is host-specific and lives on the consumer
machine. The engine's deliverable is the seam, the thin contract, the fallback, and the
skill text that uses it — the same division as `session-checks.d/`, where the engine
composes checks it does not ship. A reviewer should judge the seam, not expect a
bundled implementation.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
