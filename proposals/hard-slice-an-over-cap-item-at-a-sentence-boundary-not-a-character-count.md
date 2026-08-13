---
slug: hard-slice-an-over-cap-item-at-a-sentence-boundary-not-a-character-count
outcome: open
received: 2026-08-13
---

HANDOFF — engine improvement proposal
slug: hard-slice-an-over-cap-item-at-a-sentence-boundary-not-a-character-count
boundary: generic (engine-domain; contains no consumer-private context)

Title: A single-line list item over the embedder cap reaches the hard character slice with no boundary left to try, cutting mid-sentence and emitting a meaningless remainder chunk

Problem:
  This is deliberately filed as an IMPROVEMENT, not a defect. The behaviour below is
  documented and intended: v1.55.0 states that of the split levels "only the last can
  break mid-line, and only for a single line longer than the entire budget", and v1.56.0
  states that "an over-cap item falls back to LINE packing before it is ever sliced".
  Both are true. The observation is that for one common page shape the fallback chain
  bottoms out, because LINE packing cannot reduce an item that is a SINGLE line.

  A vault whose append-only log writes each entry as one paragraph on one physical line
  — no hard wrapping, one `- **<date> (<title>)** — <prose>` bullet per entry — gives the
  chunker exactly one line per item. So for an item over `rag_embed.MAX_CHARS` the chain
  runs: `## ` (absent), `### ` (absent), item boundary (the item IS the unit, still over
  cap), line packing (one line, no reduction possible), hard slice. The hard slice cuts at
  a character count, which lands mid-sentence and often mid-word, and the remainder
  becomes its own chunk and its own embedding.

  Two costs, and I want to be honest that the first is small:
  1. The cut chunk loses the end of its final sentence and the remainder loses its start,
     so both are slightly degraded as retrieval units.
  2. The remainder is a very short chunk whose vector represents a sentence fragment with
     no self-contained meaning. It is still indexed and still matchable, which is the
     shape v1.56.0 argues against elsewhere — "the item is the retrieval unit" — arrived
     at from the opposite direction, by a unit too small rather than too large.

Motivating use case (generic):
  Measured on one consumer vault's `log.md` at v1.57.0, after the v1.55.0/v1.56.0 chunker
  landed. The page carries ZERO `## ` headings and one `# ` title, which is the shape both
  releases were written for, and it is large: 547,212 characters across 265 dated items,
  median item 2,019 characters.

    total chunks for the page: 240   (about 1.1 items per chunk — the item-boundary split
                                      doing exactly what v1.56.0 claims)
    items over the 6,000-char cap:  2 of 265
      item at line 116: 6,289 chars  ->  6,000 + a 289-char remainder
      item at line 298: 6,093 chars  ->  6,000 + a  93-char remainder

  `rag-build.sh` announces both, which matters for how this should be weighted:

    rag-build: largest chunk 6000/6000 chars
      at cap (unbroken line): log.md:116 — Log (cont. 87)
      at cap (unbroken line): log.md:298 — Log (cont. 185)

  So this is neither silent nor invisible — the tool reports it, and a reader who looks
  can see it. That is why it is an improvement rather than a defect, and why I would rank
  it low. 2 items in 265 is 0.8%, and the two remainders are 93 and 289 characters against
  a 542,973-character page.

  It is worth filing anyway because the fix is cheap, the failure is guaranteed to recur
  (log entries only get longer, and one-line-per-entry is a natural house style for an
  append-only log), and because it closes the last level of a chain the two previous
  releases already invested in.

Proposed shape:
  In the hard-slice path of `bin/rag_chunk.py`, before cutting at `MAX_CHARS`, look
  backwards from the cap for a sentence boundary and cut there instead. Roughly:
    - search the last N characters before the cap (N as a fraction of the cap, so it
      scales — a tenth is a reasonable starting point) for a sentence terminator followed
      by whitespace;
    - if one is found, cut immediately after it;
    - if none is found, cut at the cap exactly as today.
  A word boundary is the obvious weaker fallback between the two if a sentence boundary is
  too rare in practice, though I have not measured how often that would trigger.

  Deliberately NOT proposed: any change to `MAX_CHARS`, which is the embedder's own cap
  and correctly has one definition; and no change to whether the remainder is emitted —
  dropping it would be the silent truncation v1.55.0 exists to have removed.

Alternatives considered:
  - Leave it alone. Genuinely defensible at this scale, and the tool already warns. The
    argument against is only that the fix is small and the chain is otherwise complete.
  - Merge the remainder into the following chunk instead of emitting it alone. Rejected:
    it would join the tail of one item to the whole of the next, which is precisely the
    "several unrelated entries in one vector" problem v1.56.0 measured and fixed.
  - Ask consumers to hard-wrap their log entries. Rejected: it pushes an engine
    implementation detail into every vault's authoring style, and the vault's own soft-wrap
    lint would then have an opinion about it.

Acceptance criteria:
  - An over-cap single-line item whose text contains a sentence boundary within the search
    window splits at that boundary; the first chunk ends with a complete sentence.
  - An over-cap single-line item with NO boundary in the window still slices at the cap,
    byte-for-byte as today.
  - Every non-whitespace character of the page survives the split, compared old-vs-new
    with whitespace removed — the invariant v1.55.0 already asserts.
  - No chunk exceeds `rag_embed.MAX_CHARS`.
  - Pages that use `## ` / `### ` headings, and list pages with no over-cap item, produce
    byte-identical output to before.
  - `CHUNKER_VERSION` is bumped, so existing indexes re-chunk rather than keeping vectors
    produced by the old split (the inertness `cv` was added to prevent).

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update. Weight it as low
severity — the measured impact is 2 items in 265 on one page, and `rag-build.sh` already
reports every occurrence. I have not measured whether the resulting recall changes, only
the chunk geometry, so no claim is made about retrieval quality.

Redactions:
  - The vault's name, path, org and remote are omitted entirely; the page is referred to
    only as `log.md`, which is an engine-defined filename in `SCHEMA.md`, not a private one.
  - Item titles and content are not quoted. The quoted `rag-build.sh` output carries the
    engine's own generated section labels (`Log (cont. 87)`), not consumer prose.
  - Character counts and item counts are kept, unredacted, because they are the evidence.
