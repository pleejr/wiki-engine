---
slug: expected-vs-fix-check-is-intake-only-not-reporter-facing
outcome: accepted
received: 2026-08-14
reason: "built as proposed, both additions and the mechanical criterion. Reproduced at HEAD by measurement rather than by reading: exactly ONE section of the skill related Expected to the suggested fix (§6 intake, two lines), and the reporter-facing half zero — so the asymmetry was confirmed before anything was edited. Shipped the two reporter-facing additions verbatim in intent: a fifth bullet in §1b (the count line moved with it) telling the reporter to ask whether their own fix can produce their own Expected and to cite a precedent's BEHAVIOUR rather than its printed output, and a line under the block template's `Expected:` field asking what the cited tool DOES that lets it say this. The intake section is untouched — the diff changes zero lines of §6 — and the reporter's own rejection of moving the four-claims table stands, for the reason they gave: it is maintainer-facing scepticism, and addressed to the person filing it reads as distrust. Acceptance criterion 3 asked for this to be mechanically checkable, so this is NOT skill text alone: lint-docs.sh gains a seventh check keyed off any SKILL.md shipping a defect-report template — the template's Expected field must point at the fix, and the rule must appear in at least two sections. Written to assert the PROPERTY rather than the shipped wording, and proven in three directions before release: red when either site is removed, red when the rule survives only inside a fence, and GREEN when the rule is reworded but stays sited — the near-miss that a break-it-once test passes. Criterion 4 (no change to the parsed shape) verified against the parser rather than assumed: engine-proposal.sh reads only slug: and boundary:, never Expected:, Observed: or Suggested fix, so blocks already drafted stay valid. The sibling sweep found no second instance: the improvement-proposal block in §3 has no Expected field at all, and its analogue — acceptance criteria versus proposed shape — does not transfer, because an improvement reporter is proposing rather than reporting, so the criteria ARE the spec and there is no observed/expected split to contradict."
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
