---
slug: rag-model-cache-durable-path
outcome: accepted
received: 2026-07-27
release: v1.26.0
---

# rag-model-cache-durable-path

Migrated from the `PROPOSALS.md` table when the queue directory became the source of truth. The table is now generated from these files.

**`received:` is the date this row entered `PROPOSALS.md`, which is the day the ledger itself was created — not necessarily the day the proposal arrived.** For rows whose release pre-dates that, arrival was demonstrably earlier and the true date was never recorded; the ledger only began recording arrival prospectively. Stated rather than back-filled with a guess.

`release:` is a **back-fill**, set only because this proposal pre-dates the `Proposal:` trailer convention, so no commit carries the slug and git cannot derive the answer. A new proposal never sets this field — `shipped` is derived from `git tag --contains` on the trailer commit.
