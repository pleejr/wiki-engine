---
name: engine-proposal
description: Hand a wiki-engine improvement or DEFECT from a consumer vault upstream to the engine-dev queue, and intake it on the other end. Consumer side: genericize and boundary-scrub the idea (strip vault/org/repo names, users, emails, paths, secrets), run the fail-closed `engine-proposal.sh scan`, then `submit` + `push` it as a file in the engine's `proposals/` queue by pull request — never a local edit inside `engine/`, which the next update discards, and never a node in the consumer vault. A defect block separates Observed from Suggested fix, names the failure shape (fail-closed / fail-open / data-loss), and confirms the bug is live at the pinned tag. Engine-dev side: reproduce first, design-review the arrival, record outcome + reason in the proposal frontmatter, cite `Proposal: <slug>` on the fix. `status` answers "did it ship". Triggers: "engine-proposal", "propose this upstream", "this should live in the engine", "I found a bug in the engine", "report this defect upstream", "should I fix this in engine/", "intake this proposal", "did my proposal ship", "check my outbox against the engine". Distinct from `crossover` (MOVES an existing page between vaults with integrity + soft-delete) — this originates a forward-only idea that never was a node; distinct from `checkpoint` (curates INTO this vault). NOT for recording a decision or lesson here.
status: active
summary: "genericize + boundary-scrub a consumer vault's engine improvement OR defect report into a self-contained, scan-verified handoff block for the engine-dev vault (creates no consumer node); on the engine-dev end, reproduce/design-review before building."
updated: 2026-09-03
---

# engine-proposal — hand a scrubbed engine improvement *or defect* upstream

A consumer vault (one that only *runs* the engine) discovers engine ideas and defects mid-work, each soaked in private context. This skill makes the handoff repeatable and boundary-safe: genericize, gate through a mechanical scan, submit as a file in the engine's `proposals/` queue — **without writing anything into the consumer vault.** On the engine-dev end it drives intake (§6).

**Vault**: `$WIKI_PATH` — the consumer vault on *this* machine; must be set. The deterministic gate is `$WIKI_PATH/engine/bin/engine-proposal.sh`; this skill owns the genericization and the judgement.

## Routing — this vs crossover vs checkpoint

- **engine-proposal** — a *new, forward-only* idea or defect report that never was a consumer node; the engine-dev end owns the result.
- **crossover** — *moves* an existing page to a vault on another machine, with integrity and soft-delete.
- **checkpoint** — writes a curated node *into this vault*, when the idea belongs here.

## 1. Capture the idea + its raw context

Collect the improvement, the motivating use case, and why it surfaced now. The raw (private) context is *input to the scrub* and never appears in the output. One idea per block.

## 1b. Found a DEFECT rather than an improvement? Same channel, different block

A consumer vault is where engine bugs get hit and the one place that **cannot fix them** — a local edit inside `engine/` is discarded by the next `update.sh`. Five things a defect report needs that an improvement does not:

- **Confirm it is still live at the pin you are running — do not assume.** A bug can be fixed incidentally by unrelated work and stay open on paper. State the engine version you reproduced against.
- **Separate what you OBSERVED from what you PROPOSE.** The observation is evidence; the fix is a hypothesis, and a reporter's hypothesis can be wrong while the bug is entirely real. Report the first with confidence, offer the second loosely.
- **Then read your own Expected against your own suggested fix, before you send it.** They are separate fields, so nothing makes you compare them. Ask: *if engine-dev did exactly what I suggested, would I get exactly what I wrote under Expected?* If not, say which of the two you would keep. When a precedent supplies your Expected, cite the behaviour that earns the output, not the output itself.
- **Say which failure shape it is** — this, not severity adjectives, is what sets urgency:
  - **fail-closed** — it refuses, nothing is lost. Annoying, rarely urgent.
  - **fail-open** — it proceeds while *looking* correct. Severe, because nothing surfaces it. A boundary filter that silently disabled itself on an unrecognized value, a write-time gate that skipped every commit taking the intended path, and an isolation helper that handed back the shared tree with exit 0 were all this shape.
  - **data-loss** — it destroys or overwrites work. Report immediately, and say what you did to preserve the evidence.
- **List what you already ruled out.** Saves the engine-dev end re-deriving your dead ends, and often contains the real clue.

Worked examples of the second and third rules failing: [`references/defect-report.md`](references/defect-report.md).

**The scrub is harder here** — error output, command lines and paths are the material that carries identifiers. Scrub it anyway, **keep the reproduction runnable** (the same path becomes the same `<vault>` everywhere) and **declare what you redacted**, so a gap reads as deliberate. Never quietly drop a detail because scrubbing it is awkward.

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
  If you copied this from another tool's output, name what that tool DOES that
  lets it say this — and check that the fix below can actually produce it.

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

§2, §4 and §5 apply unchanged.

## 2. Genericize / boundary-scrub — the core value

Do this deliberately:

- **Strip consumer identifiers** — vault name, org/repo slugs, usernames, emails, machine names, absolute paths.
- **Replace concrete values with placeholders** — `<consumer vault>`, `<a repo page>`, `<the private boundary>` rather than the real ones.
- **Restate the problem generically** — describe what would be true for *any* consumer vault, not just this one. If the motivating use case only makes sense with private detail, abstract the detail until it doesn't.
- **Drop secrets entirely** — never carry key material or credentials, even as an example.

## 3. Draft the kickoff block

Self-contained — the engine-dev session acts on it with **zero** access to the consumer vault.

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

Keep the slug stable — it names the resulting project and is the reporter's only correlation key.

## 4. Scan — the boundary gate (mechanical, fail-closed)

```bash
$WIKI_PATH/engine/bin/engine-proposal.sh scan --vault "$WIKI_PATH" --file <draft.md>
```

It flags the consumer's own identifiers (vault slug, directory name, git user/email), home paths, emails, non-generic `boundary:` tags and secret assignments. Any finding → revise (§2) and re-scan until `scan clean`. It is a **backstop, not a substitute** for §2 — it catches only what it can derive, so read the block once more yourself.

## 5. Hand off — submit to the queue

**Proposals are files in the engine's `proposals/` queue, submitted by pull request.**

```bash
$WIKI_PATH/engine/bin/engine-proposal.sh submit --vault "$WIKI_PATH" --slug <slug> --file <draft.md>
# read what it prints, then:
$WIKI_PATH/engine/bin/engine-proposal.sh push   --vault "$WIKI_PATH" --slug <slug>
```

**`submit` and `push` are two verbs on purpose.** The engine repository is **public**, so a pushed proposal is permanently public. `submit` runs the fail-closed scan first, prepares the branch locally, and prints the exact text that will become public; `push` performs the irreversible act (forking on demand — the fork is public too). **Read the printed block before pushing**: the scan matches identifiers it can derive; it cannot judge whether the prose discloses something private, and there is no bypass flag. Engine CI is a backstop, not the gate. `stash` is retired and warns; the block is now the file content of `proposals/<slug>.md`. Do **not** run `checkpoint` and do **not** create a node here — the engine-dev vault owns the result.

## 5b. Ask what happened to it — `status`, not a grep

```bash
$WIKI_PATH/engine/bin/engine-proposal.sh status --vault "$WIKI_PATH" [--slug <slug>]
```

Reports **shipped** (with the release), **merged**, **rejected** (with the reason), **partially accepted**, **open** (do not re-send) or **unknown** (never arrived — re-send). A bare `status` sees only this machine's records; `--slug` asks about any proposal. It resolves against `origin/main` and prints the horizon — if it says `HEAD` only, run `update` first. Never hand-maintain a `status:` line or answer "did it ship?" with a grep of the commit log.

## 6. Intake — receiving a proposal (engine-dev session)

The proposal is the **design input for the build**, so review it *before* choosing a shape — the design pass when it touches a wire/file format, an on-disk contract or a safety gate, or flips a default; none for additive doc/skill text or a one-line fix. Checklist, four-claims table and diff-review gate: [`references/intake.md`](references/intake.md).

**If it is a DEFECT report, reproduce at current `HEAD` before designing anything.** If it no longer reproduces, find the commit that fixed it, pin it with a regression test, and close it citing both. The suggested fix is a hypothesis; judge it against the observation. **Check the Expected clause against the suggested fix** — when they contradict, the Expected wins, and *your fix cannot produce your Expected* is a technical reason to deviate; record it in `reason:`. An acceptance criterion is a claim about the system: falsify it before building to it. A defect with an obvious, contained fix needs no design pass — fix it, with a test that fails first.

**See what is waiting:**

```bash
bin/engine-proposal.sh queue          # open proposals, oldest first
bin/engine-proposal.sh queue --all    # include resolved ones
```

Merging the proposal's pull request *is* the arrival record. **Record the outcome by editing the proposal's own frontmatter**, then regenerate:

```
outcome: accepted | partially-accepted | rejected | alias
reason:  "<required for rejected / partially-accepted>"
alias:   <canonical slug, for alias>
```

```bash
bin/gen-proposals-ledger.sh           # PROPOSALS.md is DERIVED from the queue
```

Two hard rules. **Never hand-edit `PROPOSALS.md`** — it is generated and `lint-proposals.sh` fails on drift; *shipped* is derived from `git tag --contains` on the trailer commit, orthogonal to `outcome:`. **Never rename the slug** — if unavoidable, add a file for the incoming slug with `outcome: alias`. A `rejected` or `partially-accepted` entry must carry its reason.

**Then file it**: a project page under the proposal's slug, with the review's accepted *and* rejected findings in **Key decisions**. Build, ship, release. **Cite the slug on the implementing commit** as a `Proposal: <slug>` line (in the PR description for a squashed merge). Placement does not matter — `lint-proposals.sh` and `status` read the literal line wherever it appears, ignoring one inside a code fence or indented as a quoted example; lint notes when git's trailer parser cannot see it, as advice. **Review the diff before you push** when the change touches an on-disk contract, a safety gate or a default — a defect outside the design's frame is invisible to the design pass and to the tests derived from it (`references/intake.md`); file its findings in Key decisions too.

## Rules

- **Forward-only.** The idea never was a consumer node: nothing to delete, no receipt to match.
- **The review belongs at intake, not authoring.** The consumer's gate is the mechanical scan; the engine-dev end reviews the genericized artifact, which is what gets built.
- **In-session, on demand; never from a lifecycle hook** (engine `CLAUDE.md`, Hard safety rule).
