---
slug: bump-pinned-numpy-2-5-3
outcome: open
received: 2026-09-20
---

HANDOFF — engine improvement proposal
slug: bump-pinned-numpy-2-5-3
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep numpy 2.5.2 -> 2.5.3

Problem:

`scaffold/rag-requirements.txt` pins `numpy==2.5.2`. `2.5.3` was released to PyPI on
2026-09-06, and `doctor.sh` reports it on every consumer session under "pinned deps with
newer releases". This is the first bump proposed for this pin — the file's history carries
accepted precedents for `huggingface_hub`, `onnxruntime` and `tokenizers`, and this one
has simply never moved since the single-pin consolidation that dropped the 3.10–3.11
environment-marker split.

Nothing automates it: `.github/dependabot.yml` declares only the `github-actions`
ecosystem, so it never sees this file, and the freshness cron reports drift rather than
acting on it.

Motivating use case (generic):

Under plugin delivery the consumer's copy of this file is the installed plugin's, which the
next plugin update replaces — so a local edit has no durable home and reaches no other
machine. `doctor.sh` at v2.0.2 says exactly that and names routing it upstream as the
remedy; this block is that route.

Compatibility checked before proposing, so intake need not re-derive it:

  - `2.5.3` ships compiled wheels tagged `cp312`, `cp313`, `cp314` and `cp315`, covering
    the whole documented 3.12–3.14 range with no interpreter left on an sdist build.
  - `requires_python >=3.12`, which is exactly the floor the file's header argues for — the
    property that made the single-pin consolidation possible is unchanged by this bump.
  - The pinned `fastembed==0.8.0` requires `numpy>=1.26` on 3.12, `>=2.1.0` on 3.13 and
    `>=2.3.0` on 3.14; `2.5.3` satisfies every marker branch in the supported range.
  - PATCH bump within the pinned MINOR.

Verified across the whole documented 3.12–3.14 range, with only this pin moved and every
other pin held at the file's current value. Twelve fresh `uv` venvs in total for this and
the two sibling proposals filed alongside it: the file's current set on each interpreter
first (the baseline, measured BEFORE any pin advanced), then the set with only `numpy` at
`2.5.3`:

  - Install of the whole pinned set succeeded on 3.12.13, 3.13.14 and 3.14.6; `uv pip check`
    reported "All installed packages are compatible" on every venv (28 packages).
  - An embed of three known texts through `BAAI/bge-base-en-v1.5` returned 768-dim vectors,
    every component non-zero, on every venv.
  - The `2.5.3` vectors are **bit-identical** to the `2.5.2` baseline on every interpreter
    (cosine 1.0000000, max component delta 0.0, on all three texts). Worth stating rather
    than assuming: `numpy` is compiled, so it belongs to the same risk class as
    `onnxruntime` a priori, and the sibling proposal filed today measures that class
    perturbing vectors. This bump does not. The result is a measurement, not an inference
    from "it is only a PATCH".
  - The baseline itself agrees across interpreters (3.12 vs 3.13 and 3.12 vs 3.14 both max
    delta 0.0), so the comparison is not confounded by the interpreter.

Gap in the verification, stated rather than left implicit: all twelve venvs ran on macOS
arm64, and this dep ships per-platform compiled wheels, so a Linux consumer installs a
different artifact than the one measured here. The wheels exist on the index for every
supported interpreter, which is the necessary condition; an install-and-embed on Linux is
the sufficient one, and engine CI is the right place to run it.

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to `numpy==2.5.3`, matching the
existing `chore(rag): bump pinned <dep> <old> -> <new>` commit convention. No other pin
moves in the same COMMIT — the two sibling proposals' pins land in their own commits, per
the v1.73.1 precedent for pins reported together.

Alternatives considered:

  - **Leave it.** Weaker for a compiled dep than for the pure-Python one: falling behind on
    the dep that carries interpreter-support risk is what makes a future forced bump land
    on an untested jump. Rejected.
  - **Bundle it with the two siblings reported in the same `doctor.sh` run.** Rejected —
    bundling a vector-perturbing bump with two bit-identical ones destroys the attribution
    that makes the perturbation readable.
  - **Unpin and let the resolver choose.** Rejected outright, for the reason the file's
    header already gives.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `numpy==2.5.3`, with no other pin changed in the
    same commit.
  - A fresh RAG provision on each supported interpreter installs the pinned set with no
    resolver conflict, and an embed of known text returns the documented 768-dim vector.
  - The embedding dimension is unchanged at 768. Bit-identical vectors ARE a reasonable
    criterion for this pin specifically — this reporter measured them bit-identical on
    three interpreters — but only on the same platform; a Linux CI run measuring a
    difference is a finding to record, not necessarily a reason to reject.
  - `rag_deps_check.load_pins()` still parses the file.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: a one-line mechanical bump, first of its kind for this pin. The
provision-and-embed check has been run across the whole documented range on one platform;
the part worth a glance rather than a rubber stamp is whether engine CI should assert
bit-identity for this dep on Linux, now that one platform's measurement exists.
