---
slug: chunk-a-flat-list-on-item-boundaries-not-on-size
outcome: open
received: 2026-08-12
---

HANDOFF — engine improvement proposal
slug: chunk-a-flat-list-on-item-boundaries-not-on-size
boundary: generic (engine-domain; contains no consumer-private context)

Title: A heading-less list page is chunked purely by size, so one embedding has to represent several unrelated entries and recall only finds them by shared vocabulary

Problem: the chunker prefers structure — `## ` section, then `### ` subsection — and falls back
to whole-line size packing when a page has neither. An append-only log is exactly that page: one
`# ` title and a long flat list of dated top-level bullets, each a self-contained entry about a
different day and topic. Size packing fills each chunk to the embedder's cap, so a chunk holds
several entries that have nothing to do with each other, and its single vector is dominated by
whichever entry leads it.

The result is not a coverage failure — the fix that made these pages indexable at all works, and
every character is embedded. It is a *retrieval* failure: a query phrased from memory, sharing
little vocabulary with the entry, ranks the diluted chunk below shorter topical pages, so the
entry is present in the index and unreachable in practice.

Motivating use case (generic): a consumer asks a later session what was decided about some piece
of work. The decision is a single dated bullet in the log. A query using words from the entry
returns it as the top hit; a paraphrase of the same question does not return the log at all,
returning topical pages instead. Both queries were run against an index where the containing
chunk was confirmed present, so the difference is ranking, not coverage.

Measured on one vault's log:

  - 187 dated entries, median 1,475 characters, longest 5,239
  - 64 chunks after the size-packing fallback, median 5,115 characters
  - ~2.9 unrelated entries per chunk

The entries are already the right retrieval unit — self-contained, topically coherent, and
comfortably under the cap on their own. The splitter simply has no rule that sees them.

Proposed shape: add a split level between `### ` and size packing — when a block carries no
sub-headings and its body is a flat list of top-level items, split on item boundaries rather than
on size. Pack consecutive items only up to a budget well below the embedder cap, so a page of
many tiny bullets does not explode into one chunk each, while ordinary long entries stand alone.
A continuation line (indented text, a nested bullet, a fenced block inside an item) must stay with
its item.

Alternatives considered:

  - **Leave it and rely on vocabulary overlap.** Cheapest, and it is what happens today; it makes
    recall useful only when the asker already remembers the words used, which is the opposite of
    what semantic recall is for.
  - **Lower the size cap globally.** Would shrink every chunk on every page, including prose that
    genuinely reads as one unit, trading a broad loss for a narrow gain.
  - **Ask the consumer to add `##` headings to the log.** Changes the vault's content to suit the
    indexer, and an append-only log has no natural heading cadence — the entry IS the unit.

Acceptance criteria:

  - A heading-less page of dated top-level items yields chunks whose median size is close to the
    median item size rather than to the cap, and no chunk mixes items beyond the packing budget.
  - A continuation line stays in the same chunk as the item it belongs to; a fenced block inside
    an item is never split across chunks.
  - Every character of the page is still emitted exactly once — the property the size fallback
    already guarantees — asserted by comparing total emitted characters to file size.
  - Pages that do carry `##`/`###` structure chunk exactly as before, asserted against a fixture.
  - The chunker version is bumped so existing vaults re-chunk rather than reusing vectors built
    by the old split.
  - A retrieval-shaped check: for a fixture page of unrelated dated items, the chunk containing a
    given item does not also contain items whose topics differ from it.

Instruction to engine-dev: create the project in the engine-dev vault, build it, ship it in the
engine so consumer vaults receive it on their next update.
