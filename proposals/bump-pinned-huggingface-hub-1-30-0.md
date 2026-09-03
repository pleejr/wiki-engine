---
slug: bump-pinned-huggingface-hub-1-30-0
outcome: accepted
reason: "accepted as proposed and shipped as proposed — one pin, one commit, nothing else moved. The block arrived with the whole 3.12–3.14 range covered by a nine-venv measurement taken before either pin advanced (baseline, huggingface_hub-only, sibling-only, on each interpreter): pip check clean, 768-dim non-degenerate vectors, and the 1.30.0 vectors bit-identical to the 1.29.0 baseline on every interpreter. Intake confirmed the file-level claims against PyPI metadata (wheel form, requires_python, the fastembed range) and the diff, and rag_deps_check.load_pins() still parses the file. The sibling pin lands in its own commit in the same release, as the v1.73.1 precedent did."
received: 2026-09-03
---

HANDOFF — engine improvement proposal
slug: bump-pinned-huggingface-hub-1-30-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep huggingface_hub 1.29.0 -> 1.30.0

Problem:

`scaffold/rag-requirements.txt` pins `huggingface_hub==1.29.0`. `1.30.0` was released to PyPI on
2026-09-03, and `doctor.sh` reports it on every consumer session under "pinned
deps with newer releases (raise upstream)". The file's own header says to bump
these deliberately, and the accepted precedents in this file's history established
both the cadence and the shape: one pin, one commit, verified by install AND embed
across the whole documented 3.12–3.14 range before the pin moves.

Nothing automates it: Dependabot declares only the github-actions ecosystem, so it
never sees this file, and the freshness cron reports drift rather than acting on it.
A standing advisory nobody owns trains consumers to skim past the whole freshness
section, including the entries that will matter.

Motivating use case (generic):

A consumer vault runs `doctor.sh` (directly, or via the session banner and the
`update` verb). Engine freshness reports clean, then the RAG-deps section names a
newer release for a pin the consumer cannot change — the file lives in the pinned
engine submodule, so a local edit is either refused by the next `update.sh` or
carried forward silently while the consumer's pins stop matching the engine's.
`doctor.sh` says so and tells the consumer to route it upstream; this block is
that route.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.30.0` ships a pure-Python `py3-none-any` wheel. No compiled-wheel-lag risk on a newer interpreter — the hazard that applies to this stack's `onnxruntime` pin does not apply here.
  - `requires_python >=3.10`, inside the file's documented 3.12–3.14 range.
  - The pinned `fastembed==0.8.0` accepts it; the resolver reported no conflict.
  - PATCH/MINOR bump within the pinned major.

Verified across the whole documented 3.12–3.14 range, with only this pin moved and
every other pin held at the file's current value. Nine fresh `uv` venvs in total
for this and the sibling proposal filed alongside it: the file's current set on each
interpreter first (the baseline, measured BEFORE either bump so the comparison
exists), then the set with only `huggingface_hub` at `1.30.0`:

  - Install of the whole pinned set succeeded on 3.12.13, 3.13.14 and 3.14.6;
    `pip check` reported "No broken requirements found" on every venv.
  - An embed of three known texts through `BAAI/bge-base-en-v1.5` returned
    768-dim vectors, every component non-zero, on every venv.
  - The `1.30.0` vectors are bit-identical to the `1.29.0` baseline on every
    interpreter (cosine 1.0000000, max component delta 0.0, on all three texts).
    This dep does not touch numeric output, as every prior bump to it measured. An existing vector store stays valid and no reindex is implied.
  - The baseline itself agrees across interpreters (3.12 vs 3.14 max delta 0.0), so
    the comparison is not confounded by the interpreter.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to `huggingface_hub==1.30.0`,
matching the existing `chore(rag): bump pinned <dep> <old> -> <new>` commit
convention. No other pin moves in the same COMMIT — the sibling proposal's pin lands
in its own commit in the same release, which is what the v1.73.1 precedent did for
two pins reported together: one dep per commit keeps a bad bump trivially
bisectable.

Alternatives considered:

  - **Leave it.** No functional driver, only currency. Rejected for the reason the
    precedents gave — an advisory emitted to every consumer on every session, never
    actioned, devalues the section it sits in.
  - **Add `pip` to Dependabot for this file so it self-proposes.** Still the right
    long-term question and still deliberately not bundled: it needs a decision about
    who reviews a machine-opened bump against an embedder whose output must stay
    comparable, and the v1.73.1 cycle showed such a review has something to catch.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `huggingface_hub==1.30.0`, with no other pin
    changed in the same commit.
  - A fresh RAG provision on each supported interpreter installs the pinned set with
    no resolver conflict, and an embed of known text returns the documented 768-dim
    vector, bit-identical to the previous pinned set's.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: a one-line mechanical bump with accepted precedents in
this file's own history — no design-review pass. The provision-and-embed check has
been run across the whole documented range; ship it so consumer vaults receive it on
their next update.
