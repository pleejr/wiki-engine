# engine-proposal — the intake design pass

Read from `SKILL.md` §6 when a proposal touches a wire/file format, an on-disk contract, a safety gate, or flips a default. The body carries the commands and the hard rules; this file carries the review method and the history that produced it.

## Three failure modes of a defect report, all seen here

**If it is a DEFECT report (§1b), reproduce before designing anything.** Three failure modes, all seen here:

- **The bug may already be gone.** A defect can be fixed *incidentally* by unrelated work while its report stays open, because the change that fixed it never cited it. Reproduce at current `HEAD` first. If it no longer reproduces, the work is not "close it" — it is **find the commit that fixed it and pin it with a regression test**, because a fix nobody aimed at is exactly the one no test covers. Then close it, citing both.
- **The reporter's suggested fix may be wrong while the bug is real.** Treat it as a hypothesis. Judge it against the *observation*, never adopt it because the report sounded confident. One filed prescription in this engine's history would have rejected payloads that were provably intact.
- **The reported symptom may not be the defect.** Reproduce, then find the mechanism; report and mechanism agree less often than they appear to. Only once you have the mechanism is the shape decision a design question at all.

## The four separable claims

**Read the report as FOUR separable claims, and check each on its own.** They arrive as one message and read as one voice, so belief in the half the reporter can see carries into the half they cannot. Each part fails in its own direction:

| part | what it is | how it fails |
|---|---|---|
| **Observation** | what they saw | usually right — they hit it |
| **Mechanism** | why they think it happens | a hypothesis written by someone who stopped investigating |
| **Expected** | the behaviour they want | the most reliable part, and the least read |
| **Acceptance criteria** | what "done" means | prescription wearing neutral clothes |

Two consequences worth stating, because both have decided a shape here:

- **An acceptance criterion is a claim about the system — go falsify it.** "X would happen if we don't do Y" is checkable, and one such criterion, flagged by its reporter as the part most likely to be dropped, was simply **false**; building to it would have added a mechanism to guarantee a property that already held. A property that already holds gets a **regression test, not machinery** — and say in the record that you rejected it and why, or the next reader re-derives the same fear and reads the absence as an oversight.
- **Check the Expected clause against the suggested fix.** They can contradict each other, and when they do the Expected wins — it is the behaviour actually wanted, while the fix is a guess at how to reach it. If the suggested fix *cannot produce* the stated Expected, the report has settled its own design question and what looks like a fork is not one. A reporter naming an alternative and declining it is not a prohibition either; they declined it from outside the internals.

Deviating from a specified shape still needs a technical reason, never a cosmetic one — but "your stated Expected is unreachable by your stated fix" is one. Record it in the outcome's `reason:` so it travels back to the reporter.

A defect that reproduces and has an obvious, contained fix does **not** need the full design pass below — go fix it, with a test that fails first.

## How to review — the checklist

**How to review.** Use a rigorous critique skill if this vault has one installed — check `~/.claude/skills/scrutinize` (this vault's is `scrutinize`; a vault may install it under another name, and the engine depends on none of them):

```bash
[ -e ~/.claude/skills/scrutinize ] && echo "review skill available" || echo "use the checklist below"
```

If none is installed, do the pass inline against this checklist — it is deliberately generic, and each line is a gap a real proposal has actually shipped with:

- **Missing receiver state** — what must the *other* end know that the proposal never names? (identity, ordering, the shape of the whole from one part)
- **Repeat / out-of-order / partial arrival** — is the operation idempotent? Does replaying a step *regress* something already good? A repair path that degrades on retry is worse than the failure it repairs.
- **The new metadata's own failure** — if the field the design adds is itself damaged or absent, does the gate still fail closed, or does it silently trust the damage?
- **Backwards compatibility** — what happens to artifacts already in flight from the previous version?
- **Evidence vs mechanism** — does the cited evidence actually support the proposed axis? (a volume-driven failure is not fixed by a per-item size threshold)
- **Defaults + capability** — what does the *default* do after the change, and does the escape hatch preserve the old behavior rather than remove it?
- **Unverifiable criteria** — which acceptance criteria can't be mechanically checked as written?

## Why `Proposal:` placement no longer matters

This used to require the final paragraph, and that requirement was itself the bug: GitHub appends a `---------` + `Co-authored-by:` footer to a squash body, so the slug the author put last stopped being last, `%(trailers)` returned nothing, and lint failed **after** the merge — when the only remedy is rewriting published history. Following the instructions was what produced the rejected state.

## The diff-review gate

**Then review the diff, before you push.** The design pass above and the acceptance criteria it produces are both derived from the *design* — so a defect that lives outside the design's frame is invisible to both, and to the tests you wrote from those criteria. Reading the change as written is the only layer that catches it. The worked example is this gate's own first use: the reviewed design was sound and every acceptance criterion passed, while the implementation ran its cache-migration side effect during a *probe* for a library that wasn't installed — outside the design's frame, so nothing upstream could have seen it.

- **Use the host's diff-review tool** (in Claude Code, `/code-review`) — a line-level pass over the working diff. Reach for the design-critique skill only when the change is design-shaped; on a plain diff it produces architecture commentary where you want line-level scrutiny.
- **Gated like the design pass, for the same reason** — run it when the change touches an on-disk contract, a safety gate, or a default, or when it has filesystem/network side effects; skip it for docs, comments, and skill text. Deterministic checks (CI) already cover the mechanical layer; this is a gate on expensive-to-revise code, not a tax on every commit.
- **Findings go where the design findings went** — the project's Key decisions, accepted and rejected, so the next build inherits the reasoning.
