---
slug: bump-pinned-huggingface-hub-1-28-0
outcome: accepted
received: 2026-08-18
reason: "accepted as proposed and shipped as proposed — one pin, one commit, nothing else moved. The reporter's stated gap is closed rather than carried: install-and-embed was run on 3.12.13, 3.13.14 and 3.14.6, not 3.14 alone, with pip check clean and 768-dim unit vectors on all three. The bit-identical claim reproduced on every interpreter, which is what makes this bump free for an existing index. The Dependabot-for-pip alternative stays unbuilt and stays the right next question, for the reason both reporters gave: it needs a decision about who reviews a machine-opened bump against an embedder whose output must stay comparable, and this cycle produced the evidence that such a review has something to catch — see the sibling proposal."
---

HANDOFF — engine improvement proposal
slug: bump-pinned-huggingface-hub-1-28-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep huggingface_hub 1.27.0 -> 1.28.0

Problem:

`scaffold/rag-requirements.txt` pins `huggingface_hub==1.27.0`. `1.28.0` is
available, and `doctor.sh` reports it on every consumer session under "pinned deps
with newer releases". The file's own header says to bump these deliberately, and
`bump-pinned-huggingface-hub-1-26-0` (accepted) established both the cadence and
the shape for exactly this dep.

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
engine's. Handing it upstream is the consumer's only correct action.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.28.0` ships a pure-Python `py3-none-any` wheel with `requires_python
    >=3.10.0`. No compiled-wheel-lag risk on a newer interpreter — the hazard that
    applies to this stack's `onnxruntime` pin does not apply here.
  - The pinned `fastembed==0.8.0` requires `huggingface-hub<2.0,>=0.20`, so
    `1.28.0` sits comfortably inside its range and the resolver will not fight it.
  - MINOR bump within the pinned major — the same class as the two prior bumps to
    this pin.

Verified, with only this pin moved and every other pin held at the file's current
value:

  - Fresh venv install of the whole pinned set succeeded; `pip check` reported
    "No broken requirements found".
  - An embed of known text through `BAAI/bge-base-en-v1.5` returned a 768-dim
    vector.
  - The returned vector is **bit-identical to the current pinned set's**, to the
    5 decimal places compared. This dep does not touch numeric output, so an
    existing vector store stays valid and no reindex is implied.

Gap in that verification, stated rather than left implicit: the file documents a
Python 3.12–3.14 target range, and only **3.14.6** was available on the machine
that ran these checks — 3.12 and 3.13 are unverified here, not verified-clean. A
pure-Python wheel with `requires_python >=3.10.0` makes an interpreter-specific
failure very unlikely, but the check that would settle it is an install-and-embed
on each of the three, which engine CI is the right place to run.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to
`huggingface_hub==1.28.0`, matching the existing `chore(rag): bump pinned <dep>
<old> -> <new>` commit convention. No other pin moves in the same change — one dep
at a time is what keeps a bad bump trivially bisectable, and it is the criterion
the accepted precedent already set.

Alternatives considered:

  - **Leave it.** Defensible in isolation; there is no functional driver, only
    currency. Rejected for the reason the precedent gave — an advisory emitted to
    every consumer on every session, never actioned, devalues the section it sits
    in.
  - **Bundle it with the `onnxruntime` bump reported in the same `doctor.sh` run.**
    Rejected, and deliberately filed as a separate block: the two are not the same
    risk class (one is pure-Python, the other is a compiled wheel that changes
    numeric output), and bundling them defeats the one-dep-at-a-time criterion.
  - **Add `pip` to Dependabot for this file so it self-proposes.** Plausibly the
    better long-term answer and deliberately not bundled here — it changes how the
    engine manages its own dependencies and needs a decision about who reviews
    machine-opened bumps against an embedder that must keep producing a stable
    vector dimension. Worth its own proposal; the precedent already flagged it.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `huggingface_hub==1.28.0`, with no other
    pin changed in the same commit.
  - A fresh RAG provision on a supported interpreter installs the pinned set with
    no resolver conflict, and an embed of known text returns the documented 768-dim
    vector.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update. This is a
one-line mechanical bump with an established precedent in this file's own history —
it does not need the full design-review pass, only the provision-and-embed check
named above, ideally across the documented interpreter range this reporter could
only cover at 3.14.
