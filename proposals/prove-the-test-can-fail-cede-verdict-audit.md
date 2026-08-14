---
slug: prove-the-test-can-fail-cede-verdict-audit
outcome: accepted
received: 2026-08-13
reason: "collision confirmed from the engine side: the description never mentioned a verdict that already exists, so the boundary was stated from the consumer's side only — exactly as reported. Built as proposed, frontmatter-only, with the axis named explicitly (does a verdict already exist?) and the NOT-for clause covering both polarities. One addition the report did not ask for: its own constraint — never name a skill the engine does not ship — was already violated in the sentence being extended, which named `scrutinize` flatly. That is now hedged in the form the engine already uses in `update` ('e.g. a `sync-skills` skill'), which keeps the retrieval token for vaults that have it without asserting it is installed. NO lint gate was added for that class, deliberately: the distinguishing property is whether a reference is hedged as an example or asserted as installed, and a token-matching gate flags the legitimate hedged form — confirmed by running one, which still flags all three references after the fix. That is the loosened-until-it-cannot-fail trap lint-docs' own check 3 warns about. This change has no mechanical gate and none is claimed; its acceptance criteria are read, not run."
---

HANDOFF — engine improvement proposal
slug: prove-the-test-can-fail-cede-verdict-audit
boundary: generic (engine-domain; contains no consumer-private context)

Title: `prove-the-test-can-fail` should cede the "this green is suspect" case it does not own

Problem: `prove-the-test-can-fail` answers a capability question — *can this check go red at all?* — by breaking the subject and requiring a real failure. A different question shares almost all of its surface prose: *this diagnostic already ran and returned a verdict, and I do not trust what it measured.* Both are provoked by a user saying some variant of "it says it passed, but". The skill's own framing invites the collision, because it advertises itself as proving "a PASSING check is capable of failing", which reads as covering any suspect pass.

The two are not the same job and their methods are opposites. Proving capability **manufactures a red** against a check that has never failed. Auditing a verdict **re-runs and controls a measurement that already happened**, asking whether the harness ran, whether the pattern or query parsed as written, whether the population under it was the intended one, and whether the result can distinguish a real absence from a broken probe. Neither substitutes for the other, and the second frequently ends with "the check is fine, the input never matched".

The existing description already cedes two neighbours (an engine release-loop skill, and a read-only artifact-review skill) and carries a NOT-for clause about debugging a check that is *already failing*. The uncovered case is the mirror of that clause: a check that is **already passing**, where the doubt is about what the pass measured rather than about whether the check has teeth.

Motivating use case (generic): in a consumer vault, an operator hits a run of failures that are all instrument defects rather than system defects — a pattern that cannot match what it is searched against, an enumeration answered from the wrong index, a greedy expression capturing an adjacent field so a watcher fires on its first poll and reports a clean pass against a system that had not yet changed state. Each is a verdict that was returned and believed. None is a check lacking the ability to fail. A consumer that installs its own skill for that class will find the two descriptions competing for the same prompts, and progressive disclosure means the router sees only descriptions — so the collision is decided before either body is read.

Proposed shape: extend the existing "Distinct from …" run in the description with one clause ceding verdict-auditing, and generalise the NOT-for clause so it covers a suspect pass as well as an active failure. No body change is required; this is a routing-surface fix. Wording is engine-dev's call, but the axis to encode is **whether a verdict already exists**: no verdict yet and the check has never failed → this skill; a verdict returned and its meaning in doubt → not this skill. Naming a specific consumer skill would be wrong, since none is guaranteed to be installed — the clause should describe the *case*, not a neighbour.

Alternatives considered:
  - Leave it and let consumers add the clause on their own side only. Rejected: the consumer can only edit its own skill, so the boundary ends up stated from one side, which is the collision this would fix. A consumer editing the engine submodule directly is a time bomb against the next update.
  - Broaden this skill to cover verdict-auditing too. Rejected: the methods are opposites (manufacture a failure vs control an existing measurement), and merging them would make a focused skill diffuse.
  - Do nothing, on the grounds that the NOT-for clause about "already failing" is close enough. Rejected: it addresses the opposite polarity. A passing-but-doubted check is exactly the gap.

Acceptance criteria:
  - The description names the verdict-already-returned case and directs it elsewhere, without naming any skill that is not shipped by the engine.
  - The distinguishing axis is stated explicitly enough that a reader can classify a prompt with no other context: does a verdict already exist?
  - The NOT-for clause covers both polarities — a check already failing, and a check passing whose pass is doubted.
  - No change to the skill body or its procedure; the diff is confined to frontmatter.
  - A consumer installing a verdict-auditing skill alongside this one can state a mutual boundary without editing the engine.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
