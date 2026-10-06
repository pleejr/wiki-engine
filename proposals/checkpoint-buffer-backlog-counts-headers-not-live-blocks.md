---
slug: checkpoint-buffer-backlog-counts-headers-not-live-blocks
outcome: partially-accepted
reason: "the defect is real and is resolved by a different mechanism: v3.2.0 replaces the per-block prune with age-out of whole month files (distill-finish.sh, under rag-capture.sh's lock, never the current month), so there is no live-block definition to get wrong, no backlog count to inflate and no marker line to lose. DECLINED: the proposed bin/buffer.sh status/prune tool, which would maintain the per-block mechanism this release removes. The overcount and the lost markers were both produced by hand-written parsers over an untracked file; nothing now parses the buffer except to read its newest block date."
received: 2026-10-05
---

HANDOFF — engine improvement proposal
slug: checkpoint-buffer-backlog-counts-headers-not-live-blocks
boundary: generic (engine-domain; contains no consumer-private context)

Title: Checkpoint §3 has no definition of a live capture block, so backlog counts and prune scripts misread the buffer

Engine version: v2.8.1 (checkpoint SKILL.md at the v2.8.1 tag)

Problem:
checkpoint §3 says to "state the count" of a raw/sessions backlog and to leave a
`_(pruned <date>: …)_` marker "in place of the removed block". It never defines what
a live block is, and the buffer's real shape after a few prune passes is not
"one header per live block":

  - Prunes in practice keep the `## <timestamp> — <repo>@<branch> (<sha>)` header
    and put the marker under it. A header with only a marker below it is history,
    not backlog.
  - A marker can also follow a still-live block (written after that block's
    `Transcript (…)` line), so it sits inside that block when the file is split
    on headers.

Two failures follow, both hit in one consumer session:

  1. Overcount. Counting `^## ` lines across two monthly buffer files reported 194
     backlog blocks; 93 were already pruned, so the live backlog was 101. The
     overcount was reported to the operator as the backlog size.
  2. Lost history. A prune script that split on headers and rewrote every block
     replaced already-pruned header+marker pairs with new markers, dropping the
     earlier markers. A second pass that skipped those still swallowed one marker
     that trailed a live block. Both were recovered only because the files were
     copied before the write and old marker lines were diffed afterwards.

The buffer is untracked, so git cannot restore it; a lost marker is unrecoverable
without a manual pre-write copy.

Motivating use case (generic):
A checkpoint in <consumer vault> offers to prune a raw/sessions backlog spanning
several weeks. The agent counts headers, reports an inflated number, then writes a
throwaway script to match blocks against log.md and replace the spent ones.

Proposed shape:
  1. checkpoint §3 text: define a live block as one that still carries its fenced
     body (```), and say the backlog count is the number of live blocks. State that
     a prune leaves the header and puts the marker under it, and that any
     `_(pruned` line inside a block's span must be carried forward when that block
     is replaced.
  2. A deterministic bin tool (e.g. `bin/buffer.sh`), so no session hand-writes a
     parser over an untracked file:
       - `buffer.sh status --wiki <vault>` — per file: headers, live blocks,
         markers; one line per live block (timestamp, repo@branch, sha).
       - `buffer.sh prune --wiki <vault> --block <timestamp> --repo <repo@branch>
          --reason "<text>"` — replaces that live block's body with a dated marker
         under its header, carries forward any marker inside its span, refuses a
         block with no fence (already pruned), and writes a copy of the file
         before changing it.
     Matching blocks to log.md stays the agent's judgement (§3 already says so);
     the tool owns only the counting and the byte-safe rewrite.
  3. Optional: a lint/self-check that the number of `_(pruned` lines never drops
     across a `buffer.sh prune` run.

Alternatives considered:
  - Text-only fix in §3: cheaper, but each session still writes its own splitter
    over an untracked file, which is where both failures came from.
  - Deleting the header along with the block on prune: makes header counts
    correct, but loses the "a capture happened here" record §3 deliberately keeps.
  - Having rag-capture.sh write a machine-readable index: larger change to the
    capture contract for a problem that lives entirely on the prune side.

Acceptance criteria:
  - §3 defines a live block and says the backlog count is live blocks, not headers.
  - `buffer.sh status` on a fixture with N live blocks and M header+marker pairs
    reports N live, N+M headers.
  - `buffer.sh prune` on a fixture where a marker trails a live block keeps that
    marker; the count of `_(pruned` lines after a prune is old count + 1.
  - `buffer.sh prune` on an already-pruned block exits non-zero and changes nothing.
  - No `claude` invocation; in-session only, never from a hook.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
