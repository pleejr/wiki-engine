---
slug: bump-pinned-onnxruntime-1-30-0
outcome: open
received: 2026-09-20
---

HANDOFF — engine improvement proposal
slug: bump-pinned-onnxruntime-1-30-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep onnxruntime 1.29.0 -> 1.30.0

Problem:

`scaffold/rag-requirements.txt` pins `onnxruntime==1.29.0`. `1.30.0` was released to PyPI
on 2026-09-10, and `doctor.sh` reports it on every consumer session under "pinned deps
with newer releases". The file's own header says to bump these deliberately; nothing
automates it, because `.github/dependabot.yml` declares only the `github-actions`
ecosystem and the freshness cron reports drift rather than acting on it.

This is the riskier of the three pins `doctor.sh` currently reports, for the reason the
file's header now records in its own words after the accepted `1.29.0` bump: an
`onnxruntime` step can perturb embeddings without changing their dimension. It is filed
separately from the two sibling proposals for exactly that reason.

Motivating use case (generic):

Under plugin delivery the consumer's copy of this file is the installed plugin's, which the
next plugin update replaces — so a local edit has no durable home and reaches no other
machine. `doctor.sh` at v2.0.2 says exactly that and names routing it upstream as the
remedy; this block is that route.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.30.0` ships compiled wheels tagged `cp311`, `cp312`, `cp313` and `cp314`, covering
    the whole documented 3.12–3.14 range. This is the pin where compiled-wheel lag on a
    newer interpreter is a real hazard, and here it does not bite.
  - `requires_python >=3.11`.
  - The pinned `fastembed==0.8.0` requires `onnxruntime>=1.24.2` on 3.14 and
    `onnxruntime!=1.24.0,!=1.24.1,>1.21.0` on 3.13, so `1.30.0` satisfies every marker
    branch in the supported range.
  - MINOR bump within the pinned major.

Verified across the whole documented 3.12–3.14 range, with only this pin moved and every
other pin held at the file's current value. Twelve fresh `uv` venvs in total for this and
the two sibling proposals filed alongside it: the file's current set on each interpreter
first (the baseline, measured BEFORE any pin advanced), then the set with only
`onnxruntime` at `1.30.0`:

  - Install of the whole pinned set succeeded on 3.12.13, 3.13.14 and 3.14.6; `uv pip check`
    reported "All installed packages are compatible" on every venv (28 packages).
  - An embed of three known texts through `BAAI/bge-base-en-v1.5` returned 768-dim vectors,
    every component non-zero, on every venv. The dimension is unchanged at 768.

**The header's warning holds for this step too, and at the same magnitude.** Against the
baseline, on the same interpreter and the same cached model weights:

    cosine similarity 0.9999996, max |per-component delta| 1.293e-04

Identical to three significant figures on 3.12.13, 3.13.14 and 3.14.6, so this is a
deterministic one-time version step rather than per-machine noise. Attribution is clean,
because each pin moved on its own: with only `huggingface_hub` or only `numpy` bumped the
vectors were bit-identical on all three interpreters, so the entire drift comes from this
dep's kernels. The baseline also agrees across interpreters (max delta 0.0), so the
comparison is not confounded by the interpreter.

That is the same class and nearly the same magnitude the accepted `1.28.0 -> 1.29.0` bump
measured (0.9999997, 1.5e-04), which is itself the useful finding: **two consecutive
`onnxruntime` steps each perturb the embedder by ~1e-04, so the drift accumulates across
releases rather than being a one-off of that upgrade.** A cosine of 0.9999996 will not
reorder retrieval results in any realistic index and no reindex is implied; a consumer
whose store spans several `onnxruntime` generations is mixing more than two
numerically-different embedders in one similarity space, which is worth being a known fact
rather than a discovered one.

Held loosely, and offered rather than asked for: the header currently records the
`1.28.0 -> 1.29.0` figure as a single measured instance. If intake agrees the accumulation
above is the more durable claim, the natural edit is to generalise that paragraph — "each
minor step measures ~1e-04, so treat drift as cumulative" — rather than to append a second
figure. That is a wording call, so it is stated here rather than built into the acceptance
criteria.

Gap in the verification, stated rather than left implicit: all twelve venvs ran on macOS
arm64, and this dep ships per-platform compiled wheels, so a Linux consumer installs a
different artifact. The wheels exist on the index for every supported interpreter, which is
the necessary condition; an install-and-embed on Linux is the sufficient one, and engine CI
is the right place to run it.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to `onnxruntime==1.30.0`, matching
the existing `chore(rag): bump pinned <dep> <old> -> <new>` commit convention. No other pin
moves in the same COMMIT — the two sibling proposals' pins land in their own commits, per
the v1.73.1 precedent.

Alternatives considered:

  - **Leave it.** Weakest here of the three: this is the dep whose currency carries the
    compiled-wheel and interpreter-support risk, so falling several releases behind is what
    makes a future forced bump land on an untested jump — and, per the accumulation above,
    a deferred bump does not avoid the drift, it only defers and concentrates it. Rejected.
  - **Bundle it with the two siblings reported in the same `doctor.sh` run.** Rejected. They
    are different risk classes, and bundling would have hidden the finding above — the
    attribution of the drift to this dep alone only exists because all three were moved
    separately.
  - **Unpin and let the resolver choose.** Rejected outright, for the reason the file's
    header already gives.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `onnxruntime==1.30.0`, with no other pin changed in
    the same commit.
  - A fresh RAG provision on a supported interpreter installs the pinned set with no
    resolver conflict, and an embed of known text returns the documented 768-dim vector.
  - The embedding dimension is unchanged at 768. Bit-identical vectors are explicitly NOT a
    criterion — this reporter measured that they differ, and a criterion requiring otherwise
    would fail on a correct bump.
  - `rag_deps_check.load_pins()` still parses the file.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose installed
    set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no consumer
    identifiers.

Instruction to engine-dev: the bump itself is one line with an established precedent; the
part that deserves a decision rather than a rubber stamp is whether the header's
drift paragraph should now state accumulation across releases, given two consecutive steps
measuring the same order of magnitude.
