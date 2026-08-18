---
slug: bump-pinned-onnxruntime-1-29-0
outcome: open
received: 2026-08-18
---

HANDOFF — engine improvement proposal
slug: bump-pinned-onnxruntime-1-29-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep onnxruntime 1.28.0 -> 1.29.0

Problem:

`scaffold/rag-requirements.txt` pins `onnxruntime==1.28.0`. `1.29.0` is available,
and `doctor.sh` reports it on every consumer session under "pinned deps with newer
releases". The file's own header says to bump these deliberately; nothing automates
it, because `.github/dependabot.yml` declares only the `github-actions` ecosystem
and `freshness.yml` reports drift rather than acting on it.

This dep is the riskier half of the pair `doctor.sh` currently reports, for two
reasons that the pure-Python pins in this file do not have — see the verification
below. It is filed separately from the `huggingface_hub` bump for exactly that
reason.

Motivating use case (generic):

A consumer vault runs `doctor.sh` (directly, or via the session banner and the
`update` verb) and is told a pin it cannot change is behind — the file lives in the
engine and the submodule is pinned, so a local edit is either refused by the next
`update.sh` or carried forward silently while the consumer's pins stop matching the
engine's. Handing it upstream is the consumer's only correct action.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.29.0` ships compiled wheels for `cp311`, `cp312`, `cp313` and `cp314`, so it
    covers the whole Python 3.12–3.14 range this file documents. This is the pin
    where compiled-wheel lag on a newer interpreter is a real hazard, and here it
    does not bite.
  - The pinned `fastembed==0.8.0` requires `onnxruntime>=1.24.2` on Python >= 3.14
    and `onnxruntime!=1.24.0,!=1.24.1,>1.21.0` on 3.13, so `1.29.0` satisfies every
    marker branch in the supported range.
  - MINOR bump within the pinned major.

Verified, with only this pin moved and every other pin held at the file's current
value:

  - Fresh venv install of the whole pinned set succeeded; `pip check` reported
    "No broken requirements found".
  - An embed of known text through `BAAI/bge-base-en-v1.5` returned a 768-dim
    vector.

**One finding intake should weigh rather than take on trust: this bump changes the
embedder's numeric output.** Across three known texts, comparing the current pinned
set against this one on the same interpreter and the same cached model weights:

    cosine similarity 0.9999997, max |per-component delta| 1.2e-04

Attribution is clean, because each pin was moved on its own: with only
`huggingface_hub` bumped the vectors were bit-identical, so the entire drift comes
from `onnxruntime` — floating-point differences in the ONNX runtime's own kernels,
not a model or tokenizer change. The dimension is unchanged at 768.

Read that as "negligible, and disclose it", not as "no change". A cosine of
0.9999997 will not reorder retrieval results in any realistic index, so no reindex
is implied. But this file's stated purpose is a reproducible venv precisely because
"an embedder silently changing version is exactly what would corrupt a vector store
without any error", and a bump that perturbs vectors at all is the shape that
argument was written about. A consumer whose store was embedded under `1.28.0` and
whose queries are embedded under `1.29.0` is mixing two numerically-different
embedders in one similarity space — harmless at this magnitude, and worth being a
known fact rather than a discovered one.

Gap in the verification, stated rather than left implicit: the file documents a
Python 3.12–3.14 target range and only **3.14.6** was available on the machine that
ran these checks. 3.12 and 3.13 are unverified here, not verified-clean. The `cp312`
and `cp313` wheels exist on the index, which is the necessary condition; the
sufficient one is an install-and-embed on each, which engine CI is the right place
to run. If CI covers only one interpreter, 3.12 is the more informative choice —
the oldest supported one is where a compiled dep drops support first.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to `onnxruntime==1.29.0`,
matching the existing `chore(rag): bump pinned <dep> <old> -> <new>` commit
convention. No other pin moves in the same change — one dep at a time is what keeps
a bad bump trivially bisectable, and it is the criterion the accepted
`bump-pinned-huggingface-hub-1-26-0` precedent set.

Held loosely, and offered rather than asked for: if intake agrees the numeric drift
is worth recording where a consumer will meet it, the natural home is a line in this
file's header noting that an `onnxruntime` bump can perturb embeddings without
changing their dimension. That is a second idea and a wording call, so it is stated
here rather than built into the acceptance criteria.

Alternatives considered:

  - **Leave it.** Weaker here than for the pure-Python pins: this is the dep whose
    currency carries the compiled-wheel and interpreter-support risk, so falling
    several releases behind is what makes a future forced bump land on an untested
    jump. Rejected.
  - **Bundle it with the `huggingface_hub` bump reported in the same `doctor.sh`
    run.** Rejected. They are different risk classes, and bundling would have hidden
    the finding above — the attribution of the vector drift to this dep alone only
    exists because the two were moved separately.
  - **Unpin and let the resolver choose.** Rejected outright, for the reason the
    file's header already gives.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `onnxruntime==1.29.0`, with no other pin
    changed in the same commit.
  - A fresh RAG provision on a supported interpreter installs the pinned set with no
    resolver conflict, and an embed of known text returns the documented 768-dim
    vector.
  - The embedding dimension is unchanged at 768. Bit-identical vectors are
    explicitly NOT a criterion — this reporter measured that they differ, and a
    criterion requiring otherwise would fail on a correct bump.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update. The bump
itself is one line with an established precedent; the part that deserves a decision
rather than a rubber stamp is whether the measured numeric drift needs recording
anywhere a consumer reads.
