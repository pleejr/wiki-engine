---
slug: rag-deps-remedy-tells-consumers-to-edit-the-pinned-submodule
outcome: partially-accepted
received: 2026-08-11
reason: "defect confirmed and fixed as reported — the remedy is now context-aware, detected rather than configured: `rag_deps_check.py` asks git for the requirements file's superproject, so a pinned submodule gets the upstream route and an engine checkout (including the CI cron) keeps the bump-it-here wording, with no caller passing a flag and no regression to the engine-dev reading. The reporter's OPEN QUESTION is answered, and it revises their severity in both directions rather than confirming it: a local edit is NOT silently reverted by the pin advance. Measured — when the new release touches the file, `git checkout` REFUSES ('local changes would be overwritten') and update.sh aborts under `set -e`, so the edit blocks the consumer's next engine update instead of vanishing; when the release does not touch it, the edit is carried across intact and the consumer's pins then quietly disagree with the engine's. Both are named in the new wording, because 'it will be reverted' would have been a false explanation of a real problem. DECLINED: `engine_is_checkout()` as the predicate, which the reporter offered with the caveat that it tests a different property — it asks 'is this a work tree I can branch in', which is true of a consumer's submodule too, so it cannot separate the two audiences; `--show-superproject-working-tree` asks the actual question. Also declined putting the decision in `doctor.sh`: the caller knowing the vault does not help the CI cron, and two callers deciding separately is how the two readings drift apart again"

HANDOFF — engine defect report
slug: rag-deps-remedy-tells-consumers-to-edit-the-pinned-submodule
boundary: generic (engine-domain; contains no consumer-private context)

Title: the pinned-dep remedy line instructs an edit that a consumer vault's pin silently discards

Engine version: v1.51.0
Still live at that pin: read the source at the pinned tag. `bin/rag_deps_check.py`
line 120 prints the remedy unconditionally, and neither that file nor `bin/doctor.sh`
contains any consumer-versus-engine-dev distinction (grepped for one; none exists).

Observed:
  `bin/rag_deps_check.py` prints, whenever a PINNED dep is behind:

      pinned deps with newer releases (bump rag-requirements.txt):
        <pkg>: <old> -> <new>

  It has two callers, and they run in different places:

    - `bin/doctor.sh` — runs in ANY vault, including a consumer vault that only
      consumes the engine as a pinned submodule.
    - `.github/workflows/freshness.yml` — runs in the engine repository itself,
      where the remedy is exactly right.

  In a consumer vault the file lives at `<vault>/engine/scaffold/rag-requirements.txt`
  — inside the pinned submodule. So the tool's own printed remedy directs the reader
  to edit a file whose contents the next `update.sh` replaces wholesale when it
  advances the pin.

  The engine already treats that specific edit as a hazard, in its own source. From
  the comment above `engine_is_checkout()` in `bin/engine-proposal.sh`:

      "...the natural next move — editing the pinned submodule in place — is the
       time bomb the skill exists to warn against."

  So one tool guards against the edit while another instructs it, from the same run
  of the same doctor report.

Expected:
  A remedy printed in a consumer vault should be one the reader can actually carry
  out durably. Either route the wording by context, or — if context is not cheap to
  determine — name both routes so neither audience is misled. The engine-dev reading
  must not regress: there the current wording is correct and should stay.

Reproduction (generic):
  1. In a vault that consumes the engine as a pinned submodule, ensure at least one
     PINNED dep in `scaffold/rag-requirements.txt` is behind its latest release.
  2. Run `<vault>/engine/bin/doctor.sh`.
  -> The report prints "pinned deps with newer releases (bump rag-requirements.txt)".
     The named file is inside the pinned submodule; the consumer has no durable way
     to act on the instruction.

Failure shape: fail-open

  Nothing refuses. A consumer who follows the instruction edits the file, re-provisions,
  and sees the deps report current — a success at every step. The pin advance later
  reverts it with no diagnostic, and the same staleness reappears with no trace of why.
  The reader's most likely conclusion is that the report is flaky rather than that their
  edit was discarded.

  Severity is bounded and I want to be accurate about it: the edit is not wholly
  invisible while it exists — an uncommitted change inside a submodule surfaces as a
  dirty submodule in the parent's `git status`. What is silent is its DISAPPEARANCE.
  NOT VERIFIED: exactly how `update.sh` behaves against a dirty submodule (refuse,
  stash, or overwrite) — I did not dirty a live engine checkout to find out, and the
  answer changes the severity, so it is worth the engine-dev end checking rather than
  taking my word.

Already ruled out:
  - Not a stale report — confirmed against the source at the current tag, not from memory.
  - Not already solved by audience detection — no consumer/engine-dev distinction exists
    in `rag_deps_check.py` or `doctor.sh`.
  - Not a complaint about dependency currency itself. The engine's weekly freshness cron
    already detects behind-pins and opens/refreshes an issue, and it works — an open issue
    from it exists. This report is only about who the remedy line addresses, and the cron's
    own issue body carries the same wording, which is correct in that context.
  - Not the same as the already-shipped `submit-rejects-submodule-engine-checkout`. That
    one was a guard rejecting the consumer's checkout (fail-closed). This is guidance
    steering the consumer into the hazard that guard's comment describes (fail-open).

Suggested fix (HOLD LOOSELY — may be wrong):
  Make the remedy context-aware, or state both routes in one line, e.g.:

      pinned deps with newer releases:
        <pkg>: <old> -> <new>
        engine checkout: edit scaffold/rag-requirements.txt
        consumer vault:  the file is inside the pinned engine submodule — a local edit
                         is discarded by the next update; raise it upstream instead

  `engine_is_checkout()` in `bin/engine-proposal.sh` is prior art for detecting the
  situation, though it tests a different property ("a git work tree I can branch in")
  and should not be assumed to be the right predicate here. The caller may be the better
  place to decide, since `doctor.sh` knows which vault it was invoked for and already
  passes `--requirements` — but that is a design call for the engine-dev end, not a
  specification from me.

Redactions:
  Absolute paths replaced with `<vault>`; package names and versions replaced with
  `<pkg>`/`<old>`/`<new>` in the illustrative output. Nothing else was removed — the
  quoted source line, file paths relative to the engine, and the code comment are
  verbatim from the engine itself, which is public.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested
fix as a hypothesis, not a specification. The `update.sh`-against-a-dirty-submodule
question above is the one unknown that could change how urgent this is.
