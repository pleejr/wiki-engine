---
name: engine-proposal
description: This skill should be used on BOTH ends of a wiki-engine improvement handoff. On the CONSUMER end: a vault discovers an engine improvement during normal work and hands it UPSTREAM to the engine-dev vault — genericized and boundary-scrubbed so no consumer-private context leaks, and without creating any node in the consumer vault. It strips consumer identifiers (vault/org/repo names, usernames, emails, absolute paths, values, secrets), restates the problem in engine-generic terms, runs a deterministic boundary scan, and emits a self-contained copy-pastable kickoff block. On the ENGINE-DEV end (intake): it drives a critical design-review pass over an arriving proposal before any shape is chosen, then files the project and records which findings were accepted or rejected. Also the route for a DEFECT found while running the engine in a consumer vault, which cannot fix it in place (a local edit to the pinned engine/ submodule is discarded by the next update): the same channel carries a defect-report block that separates the observation from the suggested fix, names the failure shape (fail-closed / fail-open / data-loss), and confirms the bug is still live at the pinned version. Triggers: "engine-proposal", "propose an engine change", "propose this upstream", "send this idea to the engine-dev vault", "package this as an engine improvement", "scrub this and hand it to the engine", "this should live in the engine, not here", "act on this proposal", "intake this engine proposal", "here is a HANDOFF block", "I found a bug in the engine", "this looks like an engine bug", "report this defect upstream", "the engine is broken here", "file this engine bug", "should I fix this in engine/ or send it upstream", "did my proposal ship", "what happened to the proposal I sent", "is that engine proposal still open", "check my outbox against the engine". Distinct from crossover (which MOVES an existing canonical vault page to another vault with sha256 integrity + soft-delete + tombstones) — engine-proposal ORIGINATES a new, forward-only idea that never was and shouldn't become a consumer node: no integrity handshake, no origin deletion; the only shared surface is the boundary gate. Distinct from checkpoint (which curates content INTO this vault) — engine-proposal creates no consumer node by default. NOT for moving an existing note between vaults (use crossover) or recording a decision/lesson in this vault (use checkpoint).
status: active
summary: "genericize + boundary-scrub a consumer vault's engine improvement OR defect report into a self-contained, scan-verified handoff block for the engine-dev vault (creates no consumer node); on the engine-dev end, reproduce/design-review before building."
updated: 2026-07-27
used_by: []
---

# engine-proposal — hand a scrubbed engine improvement *or defect* upstream

A consumer vault (one that only *runs* the engine, where engine development does not happen) keeps discovering engine-improvement ideas mid-work, each soaked in that vault's private/domain context. Handing them to the engine-dev vault by hand is inconsistent and a boundary risk — identifiers leak unless someone scrubs them every time. This skill makes that handoff repeatable and boundary-safe: it genericizes the idea, gates it through a mechanical scan, and produces a self-contained kickoff block — **without writing anything into the consumer vault.**

**Vault**: `$WIKI_PATH` — the consumer vault on *this* machine; must be set. The deterministic gate lives in `engine/bin/engine-proposal.sh`; this skill owns the genericization and drives the handoff.

## Routing — this vs crossover vs checkpoint

- **engine-proposal** — a *new, forward-only* idea that never was a consumer node and shouldn't become one. No integrity handshake, no deletion; the destination (engine-dev vault) owns everything that results.
- **crossover** — *moves* an existing canonical page to a vault on another machine, with sha256 integrity + soft-delete + tombstones. Use it when the thing already exists as a node.
- **checkpoint** — writes a curated node *into this vault*. Use it when the idea belongs here.

If the idea should leave and never lived here, it's this skill. **A bug you hit while running the engine is the same case** — see §1b; the consumer vault cannot fix it, so the report is the deliverable.

## 1. Capture the idea + its raw context

Collect the improvement, the motivating use case, and why it surfaced now. Keep the raw (private) context as *input to the scrub* — it never appears in the output. One idea per handoff block (mirrors crossover's one-connected-cluster rule); a second idea is a second block.

## 1b. Found a DEFECT rather than an improvement? Same channel, different block

A consumer vault is where engine bugs actually get hit — it is the thing running the engine all day. It is also the one place that **cannot fix them**: engine development does not happen there, and a local edit inside `engine/` is not a fix but a time bomb, because the submodule is pinned and the next `update.sh` moves the pointer straight past your change. So a defect found in a consumer vault travels the *same* upstream channel as an idea; only the block's contents differ.

Four things a defect report needs that an improvement proposal does not:

- **Confirm it is still live at the pin you are running — do not assume.** A bug can be fixed *incidentally* by unrelated work and stay open on paper for days, because the change that fixed it never cited it. State the engine version you reproduced against; the engine-dev end cannot tell a live defect from a stale one otherwise, and re-deriving that costs more than reporting it.
- **Separate what you OBSERVED from what you PROPOSE.** The observation is evidence; the fix is a hypothesis, and a reporter's hypothesis can be wrong while the bug is entirely real. A worked example from this engine's own history: a report correctly identified that a lost terminator line dropped the last item, and prescribed treating the missing terminator as an integrity failure — which would have *rejected a payload whose hash matched*, forcing another paste over exactly the lossy channel the tool exists to survive. The defect was real; the prescription would have made it worse. Report the first with confidence, offer the second loosely.
- **Say which failure shape it is** — this, not severity adjectives, is what sets urgency:
  - **fail-closed** — it refuses, nothing is lost. Annoying, rarely urgent.
  - **fail-open** — it proceeds while *looking* correct. Severe, because nothing surfaces it. A boundary filter that silently disabled itself on an unrecognized value, a write-time gate that skipped every commit taking the intended path, and an isolation helper that handed back the shared tree with exit 0 were all this shape.
  - **data-loss** — it destroys or overwrites work. Report immediately, and say what you did to preserve the evidence.
- **List what you already ruled out.** Saves the engine-dev end re-deriving your dead ends, and often contains the real clue.

**The scrub is harder here, and skimping is tempting.** The material that makes a defect report useful — error output, stack traces, command lines, file paths, config dumps — is precisely the material that carries absolute paths, vault and org names, usernames, and machine names. Scrub it anyway, but **keep the reproduction runnable**: substitute placeholders *consistently* (the same path becomes the same `<vault>` everywhere) so the steps still work, and **declare what you redacted** so a gap reads as deliberate rather than as evidence you forgot to include. Never quietly drop a detail because scrubbing it is awkward — say it was redacted and describe its shape.

Use this block shape instead of §3's:

```
HANDOFF — engine defect report
slug: <stable-kebab-slug>
boundary: generic (engine-domain; contains no consumer-private context)

Title: <one line naming the DEFECT, not the fix>

Engine version: <the tag this vault is pinned to>
Still live at that pin: <how you confirmed — a bug can be fixed incidentally and stay open>

Observed: <what happened, with scrubbed evidence>
Expected: <what should have happened, and why you believe that>

Reproduction (generic):
  1. <step>
  2. <step>
  -> <output, redacted where noted>

Failure shape: fail-closed | fail-open | data-loss

Already ruled out: <dead ends, so engine-dev need not walk them again>

Suggested fix (HOLD LOOSELY — may be wrong): <optional; omit rather than guess>

Redactions: <what was replaced, and with what, so nothing looks accidentally missing>

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
```

Everything else — the scrub discipline in §2, the mechanical scan in §4, the no-consumer-node rule in §5 — applies unchanged.

## 2. Genericize / boundary-scrub — the core value

This is the step that gets skipped when done by hand, so do it deliberately:

- **Strip consumer identifiers** — vault name, org/repo slugs, usernames, emails, machine names, absolute paths.
- **Replace concrete values with placeholders** — `<consumer vault>`, `<a repo page>`, `<the private boundary>` rather than the real ones.
- **Restate the problem generically** — describe what would be true for *any* consumer vault, not just this one. If the motivating use case only makes sense with private detail, abstract the detail until it doesn't.
- **Drop secrets entirely** — never carry key material or credentials, even as an example.
- Reuse crossover's boundary discipline (respect the destination boundary; one item per block) but **not** its move / integrity / tombstone machinery — there is nothing to move or delete here.

## 3. Draft the kickoff block

Produce a self-contained block the engine-dev session can act on with **zero** access to the consumer vault. Use this shape:

```
HANDOFF — engine improvement proposal
slug: <stable-kebab-slug>
boundary: generic (engine-domain; contains no consumer-private context)

Title: <one line>

Problem: <generic problem statement — true for any consumer vault>

Motivating use case (generic): <scrubbed scenario>

Proposed shape: <skill / bin tool / convention; how it behaves>

Alternatives considered: <options + why rejected>

Acceptance criteria:
  - <testable outcome>
  - <boundary/scan criterion>

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
```

Keep the slug stable — it's how the engine-dev vault names the resulting project.

## 4. Scan — the boundary gate (mechanical, fail-closed)

Before showing the block to anyone, run the scan. It derives the consumer's own identifiers (vault slug, directory name, git user/email) and flags any literal appearance, plus home paths, emails, non-generic `boundary:` tags, and secret assignments:

```bash
$WIKI_PATH/engine/bin/engine-proposal.sh scan --vault "$WIKI_PATH" --file <draft.md>
# or pipe it:  printf '%s' "$block" | $WIKI_PATH/engine/bin/engine-proposal.sh scan --vault "$WIKI_PATH"
```

Any finding → revise the block (return to §2) and re-scan. Do not hand off until it prints `scan clean`. The scan is a **backstop, not a substitute** for the §2 scrub: it only catches identifiers it can derive from the vault, so a leak of some *other* private detail still rides on your genericization. Read the block once more yourself.

## 5. Hand off — create NO consumer node

- Present the clean block for the user to paste into the engine-dev vault's session.
- **Stash it — this is required, not optional.** `engine-proposal.sh stash --vault "$WIKI_PATH" --slug <slug>` writes the block to `.engine-proposal/<slug>.outbox` (git-ignored scratch). This is the *only* file this skill may create in the consumer vault — never a project or memory page.
  - **Why it stopped being optional:** the handoff is forward-only, so if the block is not kept, it cannot be re-sent. That is not hypothetical — of two proposals that needed nudging, only the stashed one could be; the other had to be reconstructed from an unrelated note that happened to cover the same ground. It is also what `status` enumerates.
  - `stash` rejects a `--slug` that disagrees with the block's own `slug:` line. They are the same key; letting them diverge means every later lookup silently asks about a different proposal.
- Do **not** run checkpoint and do **not** create a project/memory/lesson node here. The engine-dev vault owns the resulting project, notes, lessons, and skill.

## 5b. Ask what happened to it — `status`, not a grep

```bash
$WIKI_PATH/engine/bin/engine-proposal.sh status --vault "$WIKI_PATH"
$WIKI_PATH/engine/bin/engine-proposal.sh status --vault "$WIKI_PATH" --slug <slug>
```

Reports every stashed block as **shipped** (with the release, and whether your pin already has it), **merged** (landed, not yet released), **rejected** (with the reason), **partially accepted**, **open** (received, in progress — do not re-send), or **unknown** (the engine has no record of it — re-sending is the right move). It reads the engine repo's `PROPOSALS.md` plus the `Proposal:` commit trailers; no network.

Three things to know before trusting an answer:

- **`unknown` and `open` are different answers.** The engine writes a row when a proposal *arrives*, so `unknown` means it never got there — a paste that was never intaken, or a session that dropped it. That is the case where re-sending is correct; `open` is the case where re-sending is noise.
- **The outbox is git-ignored and per-machine**, so a bare `status` only sees blocks stashed on *this* machine. An empty result is not evidence that nothing is outstanding, and it says so. Use `--slug` to ask about a proposal drafted elsewhere.
- **It resolves against `origin/main` when the submodule has it**, not the pinned tag — otherwise anything that shipped after your pin reads as still open. It prints the horizon it used. If it says it resolved against `HEAD` only, run `update` first.

**Never hand-maintain a `status:` line on a stashed block.** Derived status cannot go stale; a hand-kept one drifts, which is the failure that produced this subcommand.

## 5c. Nothing to grep — do NOT reach for the git log

If a consumer asks "did my proposal ship?", the answer is `status`, not a keyword search of the engine's commit subjects. Guessed keywords against reworded prose is how already-shipped blocks sat in the outbox as clutter while genuinely open ones looked identical to rejected ones.

## 6. Intake — receiving a proposal (engine-dev session)

The other end of the handoff. A proposal arrives as a `HANDOFF` block; it is the **design input for the build**, so review it *before* choosing a shape — a gap found here costs a paragraph, the same gap found mid-build costs a format change with artifacts already in flight.

**When to review.** Run the pass when the proposal touches a **wire/file format, a protocol, an on-disk contract, or a safety gate**, or when it flips a default. Skip it for additive doc/skill-text or a one-line fix — this is a gate on expensive-to-revise decisions, not a tax on every idea.

**If it is a DEFECT report (§1b), reproduce before designing anything.** Three failure modes, all seen here:

- **The bug may already be gone.** A defect can be fixed *incidentally* by unrelated work while its report stays open, because the change that fixed it never cited it. Reproduce at current `HEAD` first. If it no longer reproduces, the work is not "close it" — it is **find the commit that fixed it and pin it with a regression test**, because a fix nobody aimed at is exactly the one no test covers. Then close it, citing both.
- **The reporter's suggested fix may be wrong while the bug is real.** Treat it as a hypothesis. Judge it against the *observation*, never adopt it because the report sounded confident. One filed prescription in this engine's history would have rejected payloads that were provably intact.
- **The reported symptom may not be the defect.** Reproduce, then find the mechanism; report and mechanism agree less often than they appear to. Only once you have the mechanism is the shape decision a design question at all.

A defect that reproduces and has an obvious, contained fix does **not** need the full design pass below — go fix it, with a test that fails first.

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

**First, record that it ARRIVED — before anything else.** Append a row to the engine's `PROPOSALS.md`:

```
| `<slug>` | open | received <date> |
```

Do this on arrival, not at the end. The reporter has no return channel, so this file is the only thing that can ever tell them what happened — and a proposal you **decline** produces no commit, no trailer and no release note, meaning the resolution path has no mechanical trigger to remind you. Writing the row first also makes `unknown` mean something on the consumer end: *the engine never received this*, which is a different instruction to the reporter than "we're working on it".

- **Do not rename the slug to fit engine vocabulary.** It is the reporter's only correlation key, and renaming it silently severs their ability to match the result back — they will never learn why. If a rename is genuinely necessary, keep the incoming slug as an `alias` row pointing at the canonical one; `status` follows it.
- The terminal outcome is an **edit of that row**, never a second row: `shipped` (detail `derived`, or an explicit `vX.Y.Z` for anything predating the trailer convention), `rejected`, or `partially-accepted`. **A `rejected` or `partially-accepted` row must carry the reason** — `lint-proposals.sh` rejects a bare one, because a decline the reporter cannot act on is the failure this whole mechanism exists to fix.

**Then file it.** Create the project page under the proposal's slug, carrying its evidence and acceptance criteria; record the review's accepted *and* rejected findings in the project's **Key decisions** (append-only), so the reasoning survives the session. Build, ship, release — consumer vaults receive it on their next `update`.

**Cite the slug on the implementing commit** as a `Proposal: <slug>` trailer, in the **final paragraph** beside `Co-authored-by:`. Git parses trailers only in the last block of a message, so a `Proposal:` line anywhere else is silently invisible — CI would read the commit as untagged and the reporter would see `open` forever. Merges are squashed, so the surface that matters is the **pull request description's** final paragraph. `bin/lint-proposals.sh` hard-fails on a misplaced line rather than treating it as "no trailer", and on any trailer with no ledger row.

**Then review the diff, before you push.** The design pass above and the acceptance criteria it produces are both derived from the *design* — so a defect that lives outside the design's frame is invisible to both, and to the tests you wrote from those criteria. Reading the change as written is the only layer that catches it. The worked example is this gate's own first use: the reviewed design was sound and every acceptance criterion passed, while the implementation ran its cache-migration side effect during a *probe* for a library that wasn't installed — outside the design's frame, so nothing upstream could have seen it.

- **Use the host's diff-review tool** (in Claude Code, `/code-review`) — a line-level pass over the working diff. Reach for the design-critique skill only when the change is design-shaped; on a plain diff it produces architecture commentary where you want line-level scrutiny.
- **Gated like the design pass, for the same reason** — run it when the change touches an on-disk contract, a safety gate, or a default, or when it has filesystem/network side effects; skip it for docs, comments, and skill text. Deterministic checks (CI) already cover the mechanical layer; this is a gate on expensive-to-revise code, not a tax on every commit.
- **Findings go where the design findings went** — the project's Key decisions, accepted and rejected, so the next build inherits the reasoning.

## Notes

- **Forward-only.** The idea never was a consumer node, so there is nothing to delete and no receipt to match — the only surface shared with crossover is the boundary gate, which is why this is a separate skill rather than a crossover mode.
- **The review belongs at intake, not authoring.** The consumer's gate is the mechanical boundary scan; a design critique there is produced by the same model that just wrote the idea, in private context, and yields findings that can't travel in a forward-only block. The engine-dev end reviews the genericized artifact — which is what actually gets built.
- **Self-seeding.** The first artifact this skill would have produced is the proposal that created the skill itself; thereafter consumers use the skill instead of hand-authoring.
- **In-session by default; automate only behind the recursion guards.** The thing to prevent is *runaway agent generation*, not headless `claude` as such — a deliberately-initiated one-shot or subagent is legitimate when it carries a re-entry sentinel, is concurrency-bounded, and terminates. What this skill must never become is a hook that fires on an event its own child can re-trigger. See the **Hard safety rule** in the engine's `CLAUDE.md`.
