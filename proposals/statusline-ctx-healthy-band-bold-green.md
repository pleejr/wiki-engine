---
slug: statusline-ctx-healthy-band-bold-green
outcome: partially-accepted
received: 2026-07-29
reason: "the legibility complaint is accepted and the healthy band is no longer dim — but PLAIN green, which is the middle the proposal itself named, not bold. The tension the report raised deliberately is real and resolves that way: this row carries escalation by hue and by the action text the calm band lacks, so bolding the least actionable state would make it the loudest thing on the row, against the same principle that keeps the rate limit threshold-gated. Green alone fixes what was actually broken — that 'everything is fine' and 'this indicator is not working' rendered alike. Not made configurable: a knob for one colour is a setting nobody would find, and the segment path already lets a foreign row style its own. Thresholds, wording and truncation untouched; the NO_COLOR trap the report flagged is covered by a test"

HANDOFF — engine improvement proposal
slug: statusline-ctx-healthy-band-bold-green
boundary: generic (engine-domain; contains no consumer-private context)

Title: Render the status line's healthy context band in bold green rather than dim

Problem: Cosmetic, and scoped to one band. The context-usage gauge renders its
healthy state (below 70%) in DIM, which on many terminal themes is close to
unreadable. The practical effect is that the gauge is only legible once it has
already escalated to amber — so at a glance the healthy state is hard to
distinguish from the gauge being absent entirely, which is also how it renders on
a client that does not send the field, on non-numeric input, and when the
renderer degrades. "Everything is fine" and "this indicator is not working" should
not look alike, particularly for an indicator whose whole purpose is to be
watched passively over a long session.

Motivating use case (generic): A user glances at the row mid-session to decide
whether to keep going or checkpoint. Below 70% they cannot read the number
without looking closely, so they stop consulting it and go back to discovering
the ceiling by surprise — the exact failure the gauge was added to prevent. They
also have no cheap confirmation that the gauge is live at all until it turns
amber, by which point the reassurance is worthless.

Proposed shape: In the healthy band only, replace DIM with BOLD GREEN.
  - Below 70%: bold green `ctx 42%`  (changed)
  - 70-84%: amber `ctx 72% — checkpoint soon`  (unchanged)
  - 85%+: red `ctx 88% — checkpoint now`  (unchanged)
  Thresholds, wording, truncation and the action-naming behavior are all
  untouched; this is a single color constant on one branch. The new constant must
  also be blanked in the NO_COLOR branch alongside the existing ones — the cheap
  way to get this wrong is to add the definition and forget the disable path,
  which leaks raw escapes into the row for anyone running NO_COLOR.

Counter-argument, stated deliberately rather than left for intake to find: the
engine already holds the principle that "a number that is always on screen and
never actionable is one people stop reading" — which is why the rate limit
appears only past a threshold. DIM on the healthy band is plausibly a deliberate
application of that same principle, and bold green pushes in the opposite
direction: it makes the least actionable state the most visually prominent one on
the row. That is a real tension and this proposal does not pretend otherwise. The
argument for changing it anyway is that the gauge is *already* always-on in the
healthy band (unlike the rate limit, it is not threshold-gated), so the choice is
not between showing and hiding but between legible and barely legible. If intake
weighs the tension the other way, a reasonable middle is plain (non-dim, non-bold)
green, or making the healthy-band color configurable rather than fixed — either
resolves the legibility complaint without making the calm state shout.

Alternatives considered:
  - Leave it dim and let each consumer patch locally. Rejected: a color constant
    is not worth a per-machine fork, and consumers with their own status line
    cannot adopt engine changes at all today.
  - Threshold-gate the healthy band out of existence (show nothing below 70%).
    Rejected: it removes the passive confirmation that the gauge is working, which
    is half of what this proposal is asking for.
  - Bold the amber and red bands too. Rejected: they already carry a color that
    reads as escalation; bolding everything removes the contrast that makes the
    escalation legible.

Acceptance criteria:
  - Below 70% the fragment renders bold green; at 70-84% amber and at 85%+ red,
    both byte-identical to current output.
  - Thresholds and fragment text are unchanged, and truncation still means 84.9%
    does not escalate a band.
  - Under NO_COLOR every band emits plain text with no escape sequences,
    including the new one.
  - The renderer still exits 0 on all paths, and the fragment is still absent
    entirely for missing / null / non-numeric input.

Instruction to engine-dev: cosmetic and contained — this does not need the full
design pass. Ship it in the engine so consumer vaults receive it on their next
update.
