---
name: crossover
description: This skill should be used to migrate vault pages (memory notes, projects, comparisons, repo pages) from one wiki-engine vault to another vault that lives on a different machine and never shares a checkout — a deliberate boundary crossing (e.g. work vault to a personal vault). It moves items over a copy-paste text channel with sha256 integrity, imports them on the receiving session, and only after a returned receipt cryptographically matches does it soft-delete the originals and sweep references to tombstones. Triggers: "crossover", "move this note to my personal vault", "migrate these pages to the other vault", "export this for my personal wiki", "import this crossover block", "finalize the crossover". Distinct from wiki-adopt (which stands up / wires a vault) and checkpoint (which curates content within one vault) — crossover transfers existing items between two vaults. NOT for syncing one vault across machines (that is git) or ingesting an external repo (use wiki-repo).
status: active
summary: "migrate vault items to a vault on another machine over copy-paste, with sha256-verified soft-delete + tombstone sweep."
updated: 2026-07-23
used_by: []
---

# crossover — move vault items across a machine/boundary gap

Transfer pages between two vaults that deliberately never sit on the same computer (the boundary rule: "crossover between vaults is a manual export, never automatic"). Git can't help — the two vaults are different repos on different machines — so the channel is copy-paste text, and the danger is that a lossy paste plus a human "yeah it worked" deletes the only good copy. This skill removes that danger: **nothing is deleted until a returned receipt's hash matches what was sent.**

**Vault**: `$WIKI_PATH` — the vault root on *this* machine; must be set. All transport is deterministic in `engine/bin/crossover.sh`; this skill decides *what* moves and drives the human handoff.

## The handshake (three sessions, two machines)

```
origin (work)          crossover.sh export   → a paste block   [nothing deleted]
   ↓ paste block into the other machine's session
destination (personal) crossover.sh import   → files written + a receipt block
   ↓ paste receipt back into the origin session
origin (work)          crossover.sh finalize → soft-delete + tombstone sweep, ONLY on hash match
```

Each item carries a sha256 of its raw bytes; the batch carries a bundle hash (sha256 of the ordered item hashes). `finalize` refuses to delete unless the receipt's bundle hash equals the sent bundle and every item is confirmed `written`. A truncated or mangled paste therefore fails closed — it can never authorize a wipe.

## 1. Classify before moving (the scope gate)

Not everything that mentions the engine should leave. Read each candidate and bucket it:

- **move** — knowledge that belongs only to the destination (e.g. engine-*development* lessons). Exported as a move batch; eligible for deletion at origin.
- **copy** — dual-purpose content the origin still needs to operate (operational notes, repo pages the origin consumes). Export with `--copy`; `finalize` refuses to delete a copy batch, so the origin keeps its copy.
- **stay** — anything the origin vault runs *on* (the always-on `CLAUDE.md` slice, index/log machinery, pages anchored to the origin's own repos). Not exported.

When unsure, prefer **copy** — a duplicated note is cheap; a wrongly-deleted one is not. Confirm the buckets with the user before exporting a move batch.

## 2. Export (origin session)

```bash
$WIKI_PATH/engine/bin/crossover.sh export --vault "$WIKI_PATH" --batch <id> \
  memory/lesson-foo.md comparisons/bar.md            # move batch
$WIKI_PATH/engine/bin/crossover.sh export --vault "$WIKI_PATH" --batch <id> --copy \
  memory/dual-note.md                                 # copy batch
```

Pick a stable `<id>` (e.g. `2026-07-23-engine-knowledge`). The script secret-scans each file for a secret *assignment* (`key: value` / `key = value`) or literal key material and aborts rather than emit it — a note that merely mentions "secrets"/"tokens" in prose passes. If a genuine false positive blocks a reviewed file, re-run with `--reviewed`. It writes a `.crossover/<id>.outbound` ledger and prints the block. Show the whole block to the user to copy into the other machine's session. **Nothing is deleted here.**

## 3. Import (destination session)

On the other machine, in its own vault session:

```bash
$WIKI_PATH/engine/bin/crossover.sh import --vault "$WIKI_PATH" < paste-block
```

It re-verifies every hash, writes files to the same relative paths, and **rewrites `boundary:` to `personal`** (or whatever the destination declares — adjust if the destination isn't personal). It prints a **receipt**; `status all-verified` means every item landed intact. Then do the curation the script deliberately leaves to you: add the pages to `index.md`, append a `log.md` line, and fix or stub any now-dangling `[[links]]` (links to pages that stayed behind become cross-boundary stubs). Give the receipt block to the user to paste back to the origin.

If the receipt says `incomplete`, the paste was lossy — re-copy the export block and import again before touching the origin.

## 4. Finalize (origin session)

```bash
$WIKI_PATH/engine/bin/crossover.sh finalize --vault "$WIKI_PATH" --batch <id> < paste-receipt
```

On a bundle match it removes the files and rewrites every `[[slug]]` reference to a tombstone (`slug (migrated -> <dest>, <date>)`) — never a silent deletion — and records `.crossover/<id>.finalized`. On any mismatch it refuses and reports which item differs; re-run import at the destination and try again.

**Soft-delete, not scrub.** The script only removes files from the working tree. Commit the removals + tombstones through the vault's normal branch→PR flow — git history retains the deleted pages, which is the recovery path. Do not rewrite history to purge them.

## Notes

- **Resumable** — the `.crossover/` ledgers hold each batch's state; an interrupted migration is safe to re-drive. Commit the ledgers as migration provenance.
- **One batch = one connected cluster** where practical, so a half-moved graph doesn't strand links on both ends.
- New pages that *belong* to the destination should be **created there directly**, not created at the origin and migrated.
- In-session only; never wire any mode into a hook. See [[lesson-no-claude-in-hooks]].
