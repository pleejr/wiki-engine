---
slug: rag-capture-aborts-silently-when-wiki-path-is-not-a-vault
outcome: accepted
received: 2026-08-12
---

**Intake note (engine-dev).** Reproduced at HEAD; all five cases behaved exactly as reported. Shipped the refusal as asked, and honoured the hard constraint against defaulting — the engine already has a gate (`lint-docs.sh`) built on the same reasoning, because a guessed boundary produces a page that `rag-build`'s cross-boundary filter drops from recall silently. That constraint turned out to be load-bearing in a way the report could not see: a dead `BOUND="personal"` fallback sat on the next line, unreachable only because `set -e` killed the script first, so the minimal repair (just silence the abort) would have *activated* the mis-stamp instead of fixing anything.

Implemented slightly wider than the suggested fix and for a reason worth knowing: the boundary is now read via `bin/vault-boundary.sh`, the engine's single place for asking a vault its boundary, rather than by a fourth private `grep`. Two corrections to the report: the sweep of `bin/` was not clean — `bin/lint-memory.sh` has the same shape (a possibly-no-match `grep` in a command substitution under `set -euo pipefail`), and a memory note with zero `[[wikilinks]]` aborts that linter silently mid-run; it is a separate defect with a different remedy and is being filed on its own. And the operator-visibility half of the failure shape — that a SessionEnd hook's stderr reaches nobody — is real but out of scope here; refusing loudly is its prerequisite, and the surfacing belongs at *session start*, in `doctor.sh`, as its own proposal.

HANDOFF — engine defect report
slug: rag-capture-aborts-silently-when-wiki-path-is-not-a-vault
boundary: generic (engine-domain; contains no consumer-private context)

Title: rag-capture aborts with no message when the vault directory exists but has no readable boundary declaration, so a hook pointed at the wrong directory captures nothing forever and says nothing

Engine version: v1.53.0 (pinned; the line is unchanged in v1.52.0)
Still live at that pin: reproduced five ways from scratch against the pinned checkout, immediately after wiring the capture hook at v1.53.0.

Observed: `bin/rag-capture.sh` reads the vault's boundary at line 73:

    BOUND="$(grep -m1 'boundary:' "$WIKI/CLAUDE.md" 2>/dev/null | sed -E '...')"

Three things combine. `grep` exits non-zero when the file is absent (2) or when no line matches (1); `2>/dev/null` discards the only human-readable explanation; and the script runs under `set -euo pipefail`, so `pipefail` propagates grep's status out of the pipeline and `set -e` aborts on the assignment. The result is an exit with **no output on either stream** and nothing written.

The validation immediately above it covers the neighbouring case and misses this one:

    WIKI_PATH=<nonexistent>   -> exit 1, `error: no vault at <path>`     (explicit, good)
    WIKI_PATH=<real dir, not a vault> -> exit 2, no output at all         (silent)

The second is the likelier mistake in practice. The hook carries an absolute path, so a vault that is moved, renamed, or cloned to a different location on a second machine leaves a hook pointing at a directory that still exists — a parent, a stale copy, an empty replacement — and capture then does nothing on every session end, permanently, with no signal in any log, no file to notice missing, and a hook whose exit status nobody reads.

Expected: the same treatment the nonexistent-path case already gets — refuse with a message naming what was looked for and where. The distinction the script is trying to draw is "is this a vault", and a directory with no readable `boundary:` fails that test just as surely as a directory that does not exist.

Reproduction (generic):

  1. `mkdir -p <dir>/raw/sessions` and write no `CLAUDE.md`.
     `echo '{"cwd":"<any git repo>"}' | WIKI_PATH=<dir> bin/rag-capture.sh`
     -> exit 2, stdout empty, stderr empty, nothing written.
  2. Same, but with a `CLAUDE.md` present that contains no `boundary:` line.
     -> exit 1, stdout empty, stderr empty, nothing written.
  3. Same, with a `CLAUDE.md` declaring a boundary.
     -> exit 0, the monthly file is created and appended. Correct.
  4. `WIKI_PATH=<a plain directory with no vault structure at all>`
     -> exit 2, silent.
  5. `WIKI_PATH=<a path that does not exist>`
     -> exit 1, and `error: no vault at <path>` on stderr. The contrast in 4 vs 5 is the defect.

Failure shape: **fail-closed in mechanism, fail-open in effect.** Nothing is written and nothing is corrupted, which is the benign half. But the caller this script is documented for is a session-end hook, whose exit status and stderr no operator reads — so the observable is identical to a correctly-wired capture on a quiet session. An operator who wired the hook, saw it work once, and later moved the vault has no way to discover that capture stopped; the buffer simply stops growing, and a buffer that grows slowly is exactly what a low-activity period looks like.

Already ruled out:

  - Not the `2>/dev/null` alone: removing it would surface the underlying tool's warning, but the abort itself comes from `pipefail` + `set -e`, and a raw grep warning is not the error a caller needs.
  - Not a general engine pattern. Swept every script under `bin/`: exactly one other command substitution uses the same possibly-no-match grep with suppressed stderr, and that script runs under `set -uo pipefail` **without** `-e` and immediately defaults its result, so it is unaffected. This report is one line in one script, not a family.
  - Not caused by a missing `raw/sessions` directory — case 1 has it and still aborts, because the boundary read happens first.
  - Not a scaffolding gap: the scaffold template always writes a `boundary:` line, so a freshly created vault is unaffected. The exposed states are a relocated or mistyped `WIKI_PATH` and a hand-edited `CLAUDE.md` that lost its declaration.

Suggested fix (HOLD LOOSELY — may be wrong): treat "no readable boundary" as a validation failure beside the existing directory check, and print a message naming both the file it looked in and the declaration it wanted — so the fix is one more explicit refusal rather than a change in behaviour. Please do **not** make it default the boundary and continue: a block stamped with a guessed boundary is worse than no block, because the cross-boundary filter and the lint both key on that value, and a wrong one either drops the page from recall silently or trips an error far from its cause. If a lenient path is wanted at all, an opt-in flag is the place for it. The observation stands independently of any of this.

Redactions: absolute paths, the vault name, and the boundary value are replaced by `<dir>`, `<path>` and placeholders; the `sed` expression is elided as `'...'` because its detail is irrelevant to the mechanism. Exit codes, the stream each is silent on, and the line's structure are unmodified. The reproduction is runnable as written.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
