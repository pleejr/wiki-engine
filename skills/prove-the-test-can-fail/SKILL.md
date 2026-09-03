---
name: prove-the-test-can-fail
description: Prove a check, gate, lint rule, CI step or test actually FAILS when what it watches is broken — by running it, not reading it. Breaks the SUBJECT (never the assertion), requires a real red whose message names the right thing, restores by explicit path, requires green again, then feeds a NEAR-MISS that merely resembles the subject and requires rejection, since a check can go red on an obvious break and still pass a coincidence. Reports both runs' actual output as evidence. Refuses on a dirty working tree — it cannot tell its own mutation from uncommitted work, and restore would clobber it. Triggers: "prove this test can fail", "did this go red first", "red before green", "is this gate actually checking anything", "make sure this check works", "this check has never failed", "verify the fixture took", or right after writing any new gate or assertion. Distinct from `drain` (carries red-before-green as one clause of the release loop), from read-only artifact review (e.g. a `scrutinize` skill, which never executes), and from auditing a verdict that already came back — the axis is whether a verdict exists: none yet and the check has never failed → this skill. NOT for debugging a check already failing, NOT for doubting a pass that exists, NOT for writing the check.
status: active
summary: run a new check against a deliberately broken subject and a near-miss, proving it goes red for the right reason and rejects the coincidence.
updated: 2026-09-03
---

# prove-the-test-can-fail — a check nobody has seen fail is a hypothesis

A check that has never failed is not known to work. It is known to be *quiet*, and quiet is what a broken check and a satisfied check have in common. The only evidence that separates them is watching the check reject something — which means breaking the thing it watches, on purpose, and looking at the output.

This is written down in the record already, and it did not transfer. `lesson-a-constant-check-is-not-a-check` was written 2026-07-27 and amended twice; the same defect shipped again in v1.57.0 (a coverage check satisfied by the word *drainable*), in v1.58.0 (a gate that could not go red because a stray backtick made it read a snippet as prose), in the v1.62.0 fixture (which passed trivially because the step it tested had silently done nothing), and in v1.62.1 (a mode query that read a mention as a verdict). Four instances in three weeks, by someone who had the note available each time. **A rule you must remember is weaker than a procedure you run**, which is why this exists as a skill rather than another note.

## Where it runs

Locally, in a git repository, against a check that currently **passes**. It mutates files and restores them, so read the safety section before the procedure — the mutation is the whole method, and an unrestored mutation is worse than an unproven check.

## 0. Refuse unless the tree is clean

```sh
git status --porcelain
```

**Any output means stop.** This is not a nicety. The method is "change a file, run, change it back", and restore is `git checkout -- <path>` — which discards uncommitted work in that file without asking. With a dirty tree there is no way to tell your mutation from work the operator has not committed, so a correct restore and a silent clobber are the same command.

Offer the operator the choice: commit or stash first, or point the skill at a check whose subject is in a clean part of the tree. Do not stash on their behalf — that is their call, and a stash the skill created is one more thing to lose.

If the subject is not in a git repository at all, copy it to the scratch directory first and restore from that copy. Say which mechanism you are using; never mutate anything you cannot demonstrably put back.

## 1. State what the check asserts

In one sentence, before touching anything: *what property of what subject does this check enforce?* If that sentence is hard to write, the check probably enforces something other than what its name suggests, and that is a finding on its own — report it and stop.

Name the **subject** (the thing being checked) separately from the **check** (the code doing the checking). Every step below depends on that distinction.

## 2. Break the subject, never the assertion

**Mutate the thing the check watches. Never edit the check itself.**

Deleting an assertion and watching the check stop complaining proves only that you deleted it. The question this skill answers is different: *does the check notice a real violation?* That can only be answered by producing a real violation.

Pick the mutation the check exists to catch — the actual failure it was written for, not a convenient one. Record the exact paths you are about to touch, before touching them. Keep it to the fewest files that produce the violation.

## 3. Run it and require a real red

Run the check's own command. Three things must all hold, and each has failed on its own in this repo's history:

- **A non-zero exit.** Not "no output", not "did not run". A step that never executed reports nothing, which reads exactly like a step that passed — that is `lesson-no-run-is-not-a-red-run`, and it is why a skipped CI job once looked like a green one.
- **A message naming the subject you broke.** A red for the wrong reason is not evidence. A check that fails because a path was missing, a shell expanded something unexpectedly, or an unrelated step blew up has told you nothing about the property under test.
- **Proof the mutation took effect.** Read the file back, or diff it. A fixture that silently failed to apply gives a green that means nothing, and that is exactly how the v1.62.0 sequence test passed before its fix: the step it depended on had quietly done nothing, so there was nothing to detect.

If the check stays green, you have found a real defect — the check does not do what it claims. Report it and stop; do not adjust the mutation until it goes red, which is how a check gets tuned to its test instead of to its subject.

## 4. Restore and require green

Restore the exact paths from step 2 — explicitly, by path:

```sh
git checkout -- <the paths you recorded>
git status --porcelain    # must be empty again
```

Never `git checkout .`, never `git add -A`, never a bare `git stash pop` you did not push. Then run the check again and require it to pass. **Both halves are the evidence.** A check that goes red on a mutation but stays red after restore is stuck, not working, and only the second run distinguishes those.

If restore fails or the tree is not clean afterwards, say so immediately and prominently, name the paths, and stop. Do not continue to step 5 with an unrestored tree.

## 5. Run the near-miss

This is the step the obvious version of the procedure omits, and the one this repo keeps needing.

A check can go red correctly on a blatant break and still pass on a coincidence. Its matching may be loose — an unanchored substring, a bare name, a prefix — so it accepts something that merely *resembles* the subject. Steps 2–4 will never reveal that, because they only ever feed it a genuine violation.

So feed it a **near-miss**: something that resembles the subject closely enough to fool a loose match, but is not the thing. The check must **reject** it.

Concrete shapes, all drawn from real defects here:

- The check greps a name — supply a longer word containing it. `drain` was "documented" by *drainable* in an unrelated table row (v1.57.0).
- The check matches a tag or key — supply one with the same prefix. A note tagged `skill-candidates-meta` satisfied a query looking for `skill-candidate` (v1.62.1).
- The check counts or enumerates — supply an item that inflates the count without being a member. `ci` matched inside "de**ci**sion" and "spe**ci**fic", returning 112 of 117 notes against 9 real ones.
- The check reads a version or a timestamp — supply one that never changes, per `lesson-a-version-that-never-changes-is-not-a-version`.

Restore afterwards exactly as in step 4.

## 6. Report the evidence, not the conclusion

Print what actually happened, so a reader can judge it without rerunning:

```
check      <name / command>
asserts    <the one-sentence property from §1>
broke      <subject + paths mutated>
RED        exit <n> — <the line naming the subject>
restored   clean tree confirmed
GREEN      exit 0
near-miss  <what was supplied> — <rejected | ACCEPTED, which is a defect>
verdict    the check can fail, and fails for the right reason
```

"It passed" is not a report. The two exit statuses and the red message are the evidence; the verdict is an inference from them and is worth less than they are.

## Rules

- **Break the subject, never the assertion.** Editing the check to make it fail proves nothing about the check.
- **A clean tree is a precondition, not a preference.** Restore discards; with uncommitted work in the way, restoring correctly and clobbering silently are the same command.
- **Restore by explicit path, and confirm the tree is clean afterwards.** Never `git add -A`, never `git checkout .`.
- **Never tune the mutation until the check goes red.** That fits the check to your test rather than to its subject, and it manufactures the green you were trying to earn.
- **A green with no red before it is not a result.** Report it as unproven rather than as passing.
