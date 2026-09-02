---
slug: bump-pinned-huggingface-hub-1-29-0
outcome: accepted
received: 2026-09-02
release: v1.73.4
reason: "accepted as proposed and shipped as proposed — one pin, one commit, nothing else moved. The block arrived with the whole 3.12–3.14 range already covered, so intake re-ran nothing it could not check: the file-level claims (pure-Python wheel, fastembed range, one pin per commit) were confirmed against PyPI metadata and the diff, and rag_deps_check.load_pins() still parses the file. The Dependabot-for-pip alternative stays unbuilt for the reason every prior bump to this pin gave: it needs a decision about who reviews a machine-opened bump against an embedder whose output must stay comparable."
---

HANDOFF — engine improvement proposal
slug: bump-pinned-huggingface-hub-1-29-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep huggingface_hub 1.28.0 -> 1.29.0

Problem:

`scaffold/rag-requirements.txt` pins `huggingface_hub==1.28.0`. `1.29.0` was
released to PyPI on 2026-08-27, and `doctor.sh` reports it on every consumer
session under "pinned deps with newer releases (raise upstream)". The file's own
header says to bump these deliberately, and `bump-pinned-huggingface-hub-1-28-0`
(accepted, shipped in v1.73.1) established both the cadence and the shape for
exactly this dep.

Nothing automates it: `.github/dependabot.yml` declares only the `github-actions`
ecosystem, so Dependabot never sees this file, and `freshness.yml` reports drift
rather than acting on it. A standing advisory nobody owns trains consumers to skim
past the whole freshness section, including the entries that will matter.

Motivating use case (generic):

A consumer vault runs `doctor.sh` (directly, or via the session banner and the
`update` verb). Engine freshness reports clean, then the RAG-deps section names a
newer release for a pin the consumer cannot change — the file lives in the engine
and the submodule is pinned, so a local edit is either refused by the next
`update.sh` or carried forward silently while the consumer's pins stop matching the
engine's. `doctor.sh` now says so in its own output and tells the consumer to route
it upstream; this block is that route.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.29.0` ships a pure-Python `py3-none-any` wheel with `requires_python
    >=3.10.0`. No compiled-wheel-lag risk on a newer interpreter — the hazard that
    applies to this stack's `onnxruntime` pin does not apply here.
  - The pinned `fastembed==0.8.0` requires `huggingface-hub<2.0,>=0.20`, so
    `1.29.0` sits inside its range and the resolver will not fight it.
  - MINOR bump within the pinned major — the same class as the three prior bumps to
    this pin.

Verified across the whole documented 3.12–3.14 range, with only this pin moved and
every other pin held at the file's current value. Fresh `uv` venvs on each
interpreter, first with the file's current set (the baseline, measured BEFORE the
bump so the comparison exists), then with only `huggingface_hub` at 1.29.0:

  - Install of the whole pinned set succeeded on 3.12, 3.13 and 3.14; `pip check`
    reported "No broken requirements found" on all six venvs.
  - An embed of known text through `BAAI/bge-base-en-v1.5` returned a 768-dim
    vector on all six.
  - The 1.29.0 vector is bit-identical to the 1.28.0 baseline on every interpreter
    (cosine 1.0, max component delta 0.0). This dep does not touch numeric output,
    so an existing vector store stays valid and no reindex is implied.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to
`huggingface_hub==1.29.0`, matching the existing `chore(rag): bump pinned <dep>
<old> -> <new>` commit convention. No other pin moves in the same change — one dep
at a time is what keeps a bad bump trivially bisectable, and it is the criterion
the accepted precedents already set.

Alternatives considered:

  - **Leave it.** No functional driver, only currency. Rejected for the reason the
    precedents gave — an advisory emitted to every consumer on every session, never
    actioned, devalues the section it sits in.
  - **Add `pip` to Dependabot for this file so it self-proposes.** Still the right
    long-term question and still deliberately not bundled: it changes how the engine
    manages its own dependencies and needs a decision about who reviews a
    machine-opened bump against an embedder whose output must stay comparable. The
    v1.73.1 cycle produced the evidence that such a review has something to catch
    (an `onnxruntime` bump perturbed embeddings without changing their dimension).

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `huggingface_hub==1.29.0`, with no other
    pin changed in the same commit.
  - A fresh RAG provision on each supported interpreter installs the pinned set with
    no resolver conflict, and an embed of known text returns the documented 768-dim
    vector, bit-identical to the previous pinned set's.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: this is a one-line mechanical bump with three accepted
precedents in this file's own history — it does not need the full design-review
pass. The provision-and-embed check above has already been run across the whole
documented range; ship it in the engine so consumer vaults receive it on their next
update.
