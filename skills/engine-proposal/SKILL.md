---
name: engine-proposal
description: This skill should be used when a wiki-engine CONSUMER vault discovers an engine improvement during normal work and wants to hand it UPSTREAM to the engine-dev vault — genericized and boundary-scrubbed so no consumer-private context leaks, and without creating any node in the consumer vault. It strips consumer identifiers (vault/org/repo names, usernames, emails, absolute paths, values, secrets), restates the problem in engine-generic terms, runs a deterministic boundary scan, and emits a self-contained copy-pastable kickoff block the engine-dev session can act on with zero consumer-vault access. Triggers: "engine-proposal", "propose an engine change", "propose this upstream", "send this idea to the engine-dev vault", "package this as an engine improvement", "scrub this and hand it to the engine", "this should live in the engine, not here". Distinct from crossover (which MOVES an existing canonical vault page to another vault with sha256 integrity + soft-delete + tombstones) — engine-proposal ORIGINATES a new, forward-only idea that never was and shouldn't become a consumer node: no integrity handshake, no origin deletion; the only shared surface is the boundary gate. Distinct from checkpoint (which curates content INTO this vault) — engine-proposal creates no consumer node by default. NOT for moving an existing note between vaults (use crossover) or recording a decision/lesson in this vault (use checkpoint).
status: active
summary: "genericize + boundary-scrub a consumer vault's engine-improvement idea into a self-contained, scan-verified kickoff block for the engine-dev vault; creates no consumer node."
updated: 2026-07-24
used_by: []
---

# engine-proposal — hand a scrubbed engine improvement upstream

A consumer vault (one that only *runs* the engine, where engine development does not happen) keeps discovering engine-improvement ideas mid-work, each soaked in that vault's private/domain context. Handing them to the engine-dev vault by hand is inconsistent and a boundary risk — identifiers leak unless someone scrubs them every time. This skill makes that handoff repeatable and boundary-safe: it genericizes the idea, gates it through a mechanical scan, and produces a self-contained kickoff block — **without writing anything into the consumer vault.**

**Vault**: `$WIKI_PATH` — the consumer vault on *this* machine; must be set. The deterministic gate lives in `engine/bin/engine-proposal.sh`; this skill owns the genericization and drives the handoff.

## Routing — this vs crossover vs checkpoint

- **engine-proposal** — a *new, forward-only* idea that never was a consumer node and shouldn't become one. No integrity handshake, no deletion; the destination (engine-dev vault) owns everything that results.
- **crossover** — *moves* an existing canonical page to a vault on another machine, with sha256 integrity + soft-delete + tombstones. Use it when the thing already exists as a node.
- **checkpoint** — writes a curated node *into this vault*. Use it when the idea belongs here.

If the idea should leave and never lived here, it's this skill.

## 1. Capture the idea + its raw context

Collect the improvement, the motivating use case, and why it surfaced now. Keep the raw (private) context as *input to the scrub* — it never appears in the output. One idea per handoff block (mirrors crossover's one-connected-cluster rule); a second idea is a second block.

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
- **Optional** traceability only: `engine-proposal.sh stash --vault "$WIKI_PATH" --slug <slug>` writes the block to `.engine-proposal/<slug>.outbox` (git-ignored scratch). This is the *only* file this skill may create in the consumer vault — never a project or memory page.
- Do **not** run checkpoint and do **not** create a project/memory/lesson node here. The engine-dev vault owns the resulting project, notes, lessons, and skill.

## Notes

- **Forward-only.** The idea never was a consumer node, so there is nothing to delete and no receipt to match — the only surface shared with crossover is the boundary gate, which is why this is a separate skill rather than a crossover mode.
- **Self-seeding.** The first artifact this skill would have produced is the proposal that created the skill itself; thereafter consumers use the skill instead of hand-authoring.
- In-session only; never wire into a hook. See [[lesson-no-claude-in-hooks]].
