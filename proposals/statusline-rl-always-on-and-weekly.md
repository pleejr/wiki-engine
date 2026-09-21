---
slug: statusline-rl-always-on-and-weekly
outcome: accepted
received: 2026-09-21
reason: "accepted as proposed — a second segment name, `rl-all`, listed by `--segments`; `rl` untouched and CI asserts it byte-identical to the previous release for the same payloads, as it does the default row, which does not gain the new segment. Field names checked against the host's status-line reference before building: `rate_limits.five_hour`, `.seven_day` and `.spend_limit`, each independently absent, and the spend limit can exceed 100% — it stays red. One implementation of the bands: `_band` now serves both the context gauge and `rl-all`, so escalation cannot drift between them. `rl` keeps its own fixed amber because it is gated at 80% and byte-identity was the stated criterion. The one detail the proposal left open, the separator between windows inside the fragment, is a single space; a row owner separates segments, not windows."
---

HANDOFF — engine improvement proposal
slug: statusline-rl-always-on-and-weekly
boundary: generic (engine-domain; contains no consumer-private context)

Title: Let the status line report subscription usage before it is a problem — an always-on rate-limit segment carrying both windows

Problem: `seg_rl` answers one question — "am I about to hit the wall?" — and answers
it well: it is gated at 80% so it appears only when it is actionable. There is a
second, distinct question it cannot answer: "how much of this window have I spent,
and should I start the long task now or after the reset?" That one needs the number
BEFORE it is a problem, and it needs the 7-day window, which is the one that
constrains a heavy week. Today the segment reads `.rate_limits.five_hour` only and
prints nothing below the threshold.

The segments contract lets a foreign row STYLE what a segment prints. It gives that
row no way to un-gate a segment's silence. So a vault owner who wants a calm,
always-visible usage figure has exactly the two options the contract was written to
end: hand-roll the fields in the local row, duplicating logic the engine already
owns, or go without. The asymmetry is the point — composition solved presentation
and left suppression unreachable.

Motivating use case (generic): an operator wants the row to carry the 5-hour and
7-day percentages next to the context gauge, read at a glance while deciding
whether to begin a long piece of work, the same way the context gauge is read.
The host exposes both windows plus a gateway spend limit on the status-line
payload; only the first is surfaced, and only above 80%.

Proposed shape: a SECOND segment name rather than a flag or a config knob — e.g.
`--segment rl-all` — listed by `--segments` like every other. A name is
discoverable where a knob is not, which is the reasoning the bold-green intake
already applied when it declined to make a colour configurable. `rl` keeps its
current behaviour, byte for byte: same threshold, same wording, same emphasis.
The new segment prints each window the host reports — 5-hour, 7-day, and the
gateway spend limit when present — and nothing for the ones it does not, with the
context gauge's bands (calm below 70%, amber at 70%, red at 85%) so escalation
reads identically across the row. Both segments compose the same underlying
formatter, per the contract's one-implementation rule.

Alternatives considered:
  - A flag on `rl` (`--segment rl --always`): same behaviour, less discoverable —
    it does not appear in `--segments`, so nobody finds it without reading source.
  - Lowering `rl`'s threshold globally: rejected. It destroys the property that
    makes the gated segment worth having, and changes the default row for every
    vault to serve a preference.
  - A config knob: rejected on the bold-green precedent — a setting nobody would
    find, when a segment name costs nothing and is self-advertising.
  - Hand-rolling the fields in the consuming row: rejected. It is the per-machine
    fork the segments contract exists to prevent, and it re-implements band logic
    the engine already owns.

Acceptance criteria:
  - `--segments` lists the new name.
  - Given a payload with five_hour, seven_day and spend_limit, the new segment
    prints a fragment for each; given a payload with none, it prints nothing and
    exits 0.
  - `rl`'s output is character-identical to today's for the same payload.
  - Bands match the context gauge's thresholds and truncate rather than round, so
    84.9% never escalates.
  - NO_COLOR is honoured and every path exits 0.
  - The full renderer composes the same functions; CI asserts the composed row and
    the full row stay character-identical.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
