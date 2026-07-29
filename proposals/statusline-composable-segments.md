---
slug: statusline-composable-segments
outcome: accepted
received: 2026-07-29
reason: "accepted as proposed, including the constraint that matters most — the full renderer composes the same segment functions, so there is one implementation and CI asserts the composed row and the full row are character-identical. The opt-in tool still refuses to clobber a foreign row, unchanged; what changed is that the refusal now names the segment path, since a dead end that reports nothing is how the unreachability stayed invisible from both ends"

HANDOFF — engine improvement proposal
slug: statusline-composable-segments
boundary: generic (engine-domain; contains no consumer-private context)

Title: Expose status-line elements as composable segments, so a vault with its own status line can adopt them

Problem: The host allows exactly one status line. The engine ships its
status-line value as a single monolithic renderer, so a vault that already has
its own status line cannot adopt any part of it without abandoning its own row.
`ensure-statusline.sh` correctly refuses to clobber a foreign status line — that
refusal is the right call and should stay — but today it is a dead end rather
than a fork in the road: there is no supported way to consume one element.

The consequence compounds silently over releases. Every status-line feature the
engine ships (the staleness indicator, the context-usage gauge, and anything
added later) is permanently unreachable for those vaults, and nothing reports
that. The two available workarounds are both bad: abandon the local row and the
machine-local information it carries, or hand-copy the engine's implementation
into the local script — which creates a per-machine fork that receives no
upstream fix and whose divergence is invisible from both ends.

Motivating use case (generic): A consumer vault's machine has a hand-written
status line carrying machine-local information the engine knows nothing about. An
engine release adds a context-usage gauge to the *engine's* status line. The
consumer never receives it, and the mechanism is entirely correct at every step:
no adoption step wires a status line (opt-in, by deliberate decision), and the
manual opt-in properly declines to replace the foreign row. The feature was
shipped, is present in the pinned engine, and is unreachable. The consumer
discovers this only by going looking for a feature they remembered reading about.

Proposed shape:
  - Expose each element as an independently-callable segment — e.g.
    `statusline.sh --segment ctx`, `--segment stale` — printing only that
    fragment, and printing nothing (exit 0) when it has nothing to say.
  - The engine's own full renderer composes those same segments, so there is
    exactly ONE implementation. This is the property that matters: a segment path
    that duplicates the renderer's logic just relocates the drift problem.
  - A foreign status line adopts by interpolating a segment call, and thereafter
    receives threshold, band and format fixes with the pin, with no copied code.
  - Segments consume the same stdin payload a status line receives; a segment
    invoked without the field it needs prints nothing rather than a placeholder.
  - Document the composition contract (stdin shape, empty-output convention,
    NO_COLOR, always-exit-0) so a consuming row is not reverse-engineering it.

Alternatives considered:
  - Status quo — copy the code into the local row. Rejected: a silent per-machine
    fork that never receives upstream fixes, invisible to both ends. This is what
    consumers will do anyway, which is the argument for a supported path.
  - Have the opt-in tool wrap or chain a foreign status line. Rejected: the engine
    would have to execute an arbitrary user command and lay out two rows it does
    not understand. Ordering and separators are the row owner's taste, not the
    engine's, and mangling a hand-tuned row is worse than not adopting.
  - Re-add an auto-adopting status-line step. Rejected: opt-in was a deliberate
    decision to avoid double-surfacing the banner's verdict, and this proposal
    deliberately does not disturb it.
  - Deliver the gauge through a one-shot session-start surface instead. Rejected:
    its value is that it is *persistent* and watched over a session's life, which
    is precisely what a status line is and a one-shot announcement is not.

Acceptance criteria:
  - A segment invoked with a status-line payload prints only its own fragment,
    and prints nothing with exit 0 when its field is absent, null, or non-numeric.
  - The full renderer and the segment path produce identical text for the same
    payload and thresholds, asserted mechanically, so the two cannot drift.
  - A vault with a foreign status line can adopt a segment without the opt-in tool
    modifying its status-line setting at all.
  - Honors NO_COLOR and exits 0 on every path, matching the existing renderer's
    guarantees.
  - Adding a future element requires no change to a consuming foreign row beyond
    opting into the new segment.
  - The composition contract is documented, not inferred.

Note for intake: the existing refusal to clobber a foreign status line is correct
and is not what this proposal asks to change. The ask is to give that refusal an
alternative path, so that "we will not touch your row" stops also meaning "and
therefore you get none of this."

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
