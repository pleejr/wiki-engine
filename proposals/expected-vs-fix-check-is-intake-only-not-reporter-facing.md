---
slug: expected-vs-fix-check-is-intake-only-not-reporter-facing
outcome: open
received: 2026-08-14
---

HANDOFF — engine improvement proposal
slug: expected-vs-fix-check-is-intake-only-not-reporter-facing
boundary: generic (engine-domain; contains no consumer-private context)

Title: The reporter-facing sections of `engine-proposal` never tell a reporter to check their own Expected against their own suggested fix

Problem: The intake section reads an arriving report as four separable claims and carries the rule
outright — *check the Expected clause against the suggested fix; when they contradict, the Expected
wins*. Both surfaces that a REPORTER reads say something weaker: the consumer guidance says to
separate what you OBSERVED from what you PROPOSE, and the defect-report block template asks for
`Expected:` and `Suggested fix (HOLD LOOSELY)` as independent fields with nothing relating them. A
reporter does not read the intake section, because it is addressed to the other end of the handoff.
So the check that catches the most common way an Expected goes wrong is applied only after the
report is submitted, by the reader who pays a round trip to discover it.

The gap is asymmetric rather than absent, which is why it survives a read-through: every clause the
reporter needs exists somewhere in the skill, and the one that would have caught this class is in
the half they are not the audience for.

Motivating use case: this is the engine's own `lint-announce-resolved-vault`, and its recorded
outcome already states the reason — so the evidence is verifiable at the engine end in one lookup
rather than taken on the reporter's word. A consumer filed that `lint.sh` issues a verdict about a
tree the operator is not standing in, and reports success while doing it. To state `Expected:`, the
reporter cited `gen-projects-index.sh` — a sibling that prints an unprompted line naming its target —
and quoted that line as the output wanted. But that sibling can print the line only because it
RETARGETS; the message is a consequence of switching trees, not a feature sitting beside it. So the
stated Expected was unreachable by the stated suggested fix, which was "announce, like the sibling
does". Intake caught it, declined the prescription, and shipped the retarget that actually delivers
the Expected. The observation was confirmed in full.

The reporter's mistake is specific and repeatable: they cited the precedent by its OBSERVABLE OUTPUT
rather than by the behaviour that earns the output. That direction of error is structural for a
consumer, because the printed string is normally the only part of a sibling tool they ever see —
they run the tools, they do not read the internals. So "cite a precedent" and "cite a precedent's
output" feel identical from the consumer's chair, and only the second one can specify something
unreachable.

Proposed shape: skill text only. No code, no change to the block's parsed shape, no on-disk contract.
Two additions to the reporter-facing half:

  1. A bullet beside "Separate what you OBSERVED from what you PROPOSE" — before submitting, read
     your own Expected against your own suggested fix and ask whether the fix can produce it. If they
     conflict, say which one you would keep. When a cited precedent supplies the Expected, name the
     behaviour that produces it, not the string it prints.
  2. One line in the defect-report block template under `Expected:` — if this is copied from another
     tool's output, name what that tool DOES that lets it say this.

Alternatives considered:
  - Move the four-claims table into a section both ends read. Rejected: it is written as
    maintainer-facing judgement ("a hypothesis written by someone who stopped investigating"), and
    addressed to the reporter that reads as distrust of the person filing, which discourages reports.
    The reporter needs one check, not the whole scepticism table.
  - Add a mechanical check to the submit-time scan. Rejected by the reporter: that scan is a
    fail-closed boundary gate over identifiers it can derive, and "is this Expected reachable by this
    fix" is not pattern-matchable. A check that cannot fail is worse than no check.
  - Decline and leave it at intake. This is today's behaviour and it WORKS — the process caught the
    error and the report was still accepted. Stated plainly so this can be declined cheaply: the
    benefit is one saved round trip per occurrence, not a defect being missed.

Acceptance criteria:
  - The reporter-facing half states the Expected-versus-fix check without requiring the reporter to
    read the intake section.
  - The block template's `Expected:` field carries the cite-the-behaviour-not-the-output instruction.
  - The intake section is not weakened, and the rule is not restated in a form that can drift from it
    — mechanically checkable by asserting both surfaces carry it.
  - No change to the block's parsed shape, so blocks already drafted against the current template
    stay valid.

Not claimed: that this would have changed the outcome of the motivating case. The reporter held the
fix loosely as instructed and intake did its job. This is a cheaper place to catch one class, not a
missing gate.

Instruction to engine-dev: create the project in the engine-dev vault, build it, ship it in the
engine so consumer vaults receive it on their next update. Per this skill's own gating, skill text
alone does not need the design-review pass.
