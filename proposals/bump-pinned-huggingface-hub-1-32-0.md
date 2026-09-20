---
slug: bump-pinned-huggingface-hub-1-32-0
outcome: open
received: 2026-09-20
---

HANDOFF — engine improvement proposal
slug: bump-pinned-huggingface-hub-1-32-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep huggingface_hub 1.30.0 -> 1.32.0

Problem:

`scaffold/rag-requirements.txt` pins `huggingface_hub==1.30.0`. `1.32.0` was released
to PyPI on 2026-09-17, and `doctor.sh` reports it on every consumer session under
"pinned deps with newer releases". The file's own header says to bump these
deliberately, and the accepted precedents in its history set both the cadence and the
shape: one pin, one commit, verified by install AND embed across the whole documented
3.12–3.14 range before the pin moves.

Nothing automates it: `.github/dependabot.yml` declares only the `github-actions`
ecosystem, so it never sees this file, and the freshness cron reports drift rather than
acting on it. A standing advisory nobody owns trains consumers to skim past the whole
freshness section, including the entries that will matter.

Motivating use case (generic):

Under plugin delivery the consumer's copy of this file is the installed plugin's, which
the next plugin update replaces — so a local edit has no durable home and reaches no
other machine. `doctor.sh` at v2.0.2 says exactly that and names routing it upstream as
the remedy; this block is that route.

Compatibility checked before proposing, so intake need not re-derive it:

  - `1.32.0` ships a pure-Python `py3-none-any` wheel. No compiled-wheel-lag risk on a
    newer interpreter — the hazard that applies to this stack's `onnxruntime` pin does
    not apply here.
  - `requires_python >=3.10.0`, inside the file's documented 3.12–3.14 range.
  - The pinned `fastembed==0.8.0` requires `huggingface-hub<2.0,>=0.20`, which `1.32.0`
    satisfies on every marker branch; the resolver reported no conflict.
  - MINOR bump within the pinned major. `1.31.0` is skipped rather than stepped through,
    as the accepted `1.26.0` and `1.30.0` precedents did with their own intermediate
    releases.

Verified across the whole documented 3.12–3.14 range, with only this pin moved and every
other pin held at the file's current value. Twelve fresh `uv` venvs in total for this and
the two sibling proposals filed alongside it: the file's current set on each interpreter
first (the baseline, measured BEFORE any pin advanced, so the comparison exists), then the
set with only `huggingface_hub` at `1.32.0`:

  - Install of the whole pinned set succeeded on 3.12.13, 3.13.14 and 3.14.6; `uv pip
    check` reported "All installed packages are compatible" on every venv (28 packages).
  - An embed of three known texts through `BAAI/bge-base-en-v1.5` returned 768-dim
    vectors, every component non-zero, on every venv.
  - The `1.32.0` vectors are **bit-identical** to the `1.30.0` baseline on every
    interpreter (cosine 1.0000000, max component delta 0.0, on all three texts). This dep
    does not touch numeric output, as every prior bump to it measured. An existing vector
    store stays valid and no reindex is implied.
  - The baseline itself agrees across interpreters (3.12 vs 3.13 and 3.12 vs 3.14 both max
    delta 0.0), so the comparison is not confounded by the interpreter.

Platform gap, stated rather than left implicit: all twelve venvs ran on macOS arm64. The
wheel here is pure Python, so the platform cannot change what is installed; engine CI on
Linux is still the place that closes it for the compiled sibling.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to `huggingface_hub==1.32.0`,
matching the existing `chore(rag): bump pinned <dep> <old> -> <new>` commit convention. No
other pin moves in the same COMMIT — the two sibling proposals' pins land in their own
commits, which is what the v1.73.1 precedent did for two pins reported together: one dep
per commit keeps a bad bump trivially bisectable.

Alternatives considered:

  - **Leave it.** No functional driver, only currency. Rejected for the reason the
    precedents gave — an advisory emitted to every consumer on every session, never
    actioned, devalues the section it sits in.
  - **Bundle all three reported pins into one commit.** Rejected. The `onnxruntime` sibling
    perturbs vectors and these two do not; bundling would destroy the attribution that
    makes that finding readable.
  - **Add `pip` to Dependabot for this file so it self-proposes.** Still the right long-term
    question and still deliberately not bundled: it needs a decision about who reviews a
    machine-opened bump against an embedder whose output must stay comparable.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `huggingface_hub==1.32.0`, with no other pin
    changed in the same commit.
  - A fresh RAG provision on each supported interpreter installs the pinned set with no
    resolver conflict, and an embed of known text returns the documented 768-dim vector,
    bit-identical to the previous pinned set's.
  - `rag_deps_check.load_pins()` still parses the file.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: a one-line mechanical bump with accepted precedents in this
file's own history — no design-review pass. The provision-and-embed check has been run
across the whole documented range; ship it so consumer vaults receive it on their next
update.
