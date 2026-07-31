---
slug: bump-pinned-huggingface-hub-1-26-0
outcome: open
received: 2026-07-31
---

HANDOFF — engine improvement proposal
slug: bump-pinned-huggingface-hub-1-26-0
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bump the pinned RAG embedder dep huggingface_hub 1.25.1 -> 1.26.0

Problem:

`scaffold/rag-requirements.txt` pins `huggingface_hub==1.25.1`. A newer release,
`1.26.0`, is available, and `doctor.sh` reports it on every consumer session as
"pinned deps with newer releases (bump rag-requirements.txt)".

Nothing automates this. `.github/dependabot.yml` declares only the
`github-actions` ecosystem, not `pip`, so Dependabot does not see this file; and
`freshness.yml` *reports* drift rather than acting on it. The file's own header
says to bump these deliberately, and the repository history shows exactly that
pattern — recent commits bump this same pin and a sibling one, one dep at a time.
So the standing advice is correct and simply needs someone to act on it; a
persistent advisory that nobody owns eventually reads as background noise, which
is the state it is drifting toward.

Motivating use case (generic):

A consumer vault runs `doctor.sh` (directly, or via the session banner and the
`update` verb). Engine freshness reports clean, then a RAG-deps section reports a
newer release for a pin the consumer cannot change — the file lives in the engine
and the submodule is pinned, so a local edit is discarded by the next update. The
consumer's only correct action is to hand it upstream, which is this block.

Compatibility checked before proposing, so intake does not have to re-derive it:

  - `1.26.0` ships a pure-Python `py3-none-any` wheel with `requires_python
    >=3.10.0`. There is no compiled-wheel-lag risk on a newer interpreter — the
    hazard that applies to this stack's *other* pins does not apply here.
  - The pinned `fastembed` requires `huggingface-hub<2.0,>=0.20`, so `1.26.0` is
    comfortably inside its range and the resolver will not fight the pin.
  - It is a MINOR bump within the pinned major, so it is the same class of change
    the two most recent bumps to this file already were.

Verified on a consumer running Python 3.14.6 with the current pinned set
installed (`fastembed`, `onnxruntime`, `numpy`, `tokenizers`, `huggingface_hub`
all matching the file).

Proposed shape:

Bump the single pin in `scaffold/rag-requirements.txt` to
`huggingface_hub==1.26.0`, matching the existing `chore(rag): bump pinned <dep>
<old> -> <new>` commit convention, and confirm the embedder still provisions and
produces a correct-dimension embedding on the supported interpreter range the
file documents. No other pin moves in the same change — one dep at a time is
what makes a bad bump trivially bisectable, and it is the pattern already in use.

Alternatives considered:

  - **Leave it.** Defensible in isolation — there is no functional driver, only
    currency. Rejected because the advisory is emitted to every consumer on every
    session, and an advisory that is never actioned trains people to ignore the
    whole freshness section, including the entries that will matter.
  - **Add `pip` to Dependabot for this file so it self-proposes.** Plausibly the
    better long-term answer, and deliberately NOT bundled here: it changes how
    the engine manages its own dependencies, needs a decision about who reviews
    machine-opened bumps against an embedder that must keep producing the same
    vector dimension, and would be a second idea in one block. Worth its own
    proposal if the manual cadence proves annoying.
  - **Unpin and let the resolver choose.** Rejected outright; the file's stated
    purpose is a reproducible venv rather than "whatever pip resolved that day",
    and an embedder silently changing version is exactly what would corrupt a
    vector store without any error.

Acceptance criteria:

  - `scaffold/rag-requirements.txt` pins `huggingface_hub==1.26.0`, with no other
    pin changed in the same commit.
  - A fresh RAG provision on a supported interpreter installs the pinned set
    without resolver conflict, and an embed of known text returns the documented
    768-dim vector.
  - `doctor.sh` no longer reports a newer release for this dep on a consumer whose
    installed set matches the file.
  - Boundary: the change is a version string in an engine-owned file; it carries no
    consumer identifiers.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update. This is
a one-line mechanical bump with an established precedent in this file's own
history — it does not need the full design-review pass, only the provision-and-embed
check named above.
