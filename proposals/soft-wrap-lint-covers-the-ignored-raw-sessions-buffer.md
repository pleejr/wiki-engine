---
slug: soft-wrap-lint-covers-the-ignored-raw-sessions-buffer
outcome: accepted
reason: "accepted — observation reproduced at HEAD in a scaffolded fixture exactly as reported (reflow --check exits 1 on the ignored buffer alone; lint.sh prints `would reflow:` for it while link integrity reports 0 content-node pages in the same run), and the suggested fix taken as proposed: the soft-wrap section now reads `vault_pages "$WIKI" raw`, so the whole of raw/ is exempt rather than only git-ignored files. The reporter's own reservation decided it: raw/articles, raw/papers and raw/transcripts are tracked verbatim sources and a reflow of a transcript is corruption, not normalization; skipping only ignored files would have kept linting them and put a git query inside a walk that has none. The frontmatter-properties check deliberately keeps its unpruned population — that footgun applies to any page Obsidian renders, raw/ pages carry engine-written frontmatter, and the capture buffer carries none, so it cannot refuse over the buffer. The second, smaller item was taken too: the verdict line now names the failing sections (`lint: FAILURES above — in: soft-wrap`), and the near-miss control asserts it. CI pins all of it with the two controls that separate this fix from a blanket exemption: a hard-wrapped tracked raw/transcripts file passes and a hard-wrapped notes/ page is still refused by name; every assertion was proven red against the previous lint.sh."
received: 2026-09-02
---

HANDOFF — engine defect report
slug: soft-wrap-lint-covers-the-ignored-raw-sessions-buffer
boundary: generic (engine-domain; contains no consumer-private context)

Title: lint.sh's soft-wrap check covers raw/, so drift in the git-ignored raw/sessions buffer refuses an unrelated commit

Engine version: v1.73.4 (pinned; reproduced immediately after adopting it)
Still live at that pin: reproduced in a throwaway fixture vault at v1.73.4 — see Reproduction. Not inferred from the live incident, which was cleared before it could be preserved (see Redactions).

Observed:
  A pointer-only commit advancing the engine submodule was refused by the vault's
  pre-commit hook. `vault-worktree.sh guard` allowed it, naming the reason
  ("allowing a submodule-pointer-only commit in canonical"); `lint.sh` then failed,
  with exactly one failing section:

    === soft-wrap ===
    would reflow: <vault>/raw/sessions/<YYYY-MM>.md

  That file is git-ignored (`.gitignore` carries `raw/sessions/*.md`) per-machine
  state. It cannot be staged, cannot enter the commit, and cannot reach any other
  machine — yet it refuses commits of unrelated tracked content.

  The inconsistency is inside lint.sh itself. Its page set comes from `vault_pages`
  (bin/wiki-root-lib.sh), a `find` pruning a fixed directory list — `.git engine
  .obsidian .rag .worktrees` — which never consults git, so `raw/` is in scope. Its
  own content-node walk, a few lines below in bin/lint.sh, prunes `raw/*` explicitly.
  So the same script treats raw/ as not-vault-content for boundary, provenance and
  link integrity, and as vault content for soft-wrap.

  Two things made the failure expensive to read, and both are lint.sh's output rather
  than the defect:
    - `lint: FAILURES above` names no section. The failing one is ~130 lines above the
      verdict.
    - Link integrity prints 50 stub WARNINGS (and `0 error(s)`) immediately before that
      line, so the warnings read as the failure.

Expected:
  A file the vault ignores does not gate a commit to the vault. Concretely: soft-wrap
  should apply to the same population every other content-node check in this script
  applies to — which already excludes raw/, in this script, deliberately.

  The convention soft-wrap enforces is stated in reflow.sh's own header as a RENDERING
  concern: "so pages render as flowing prose in every Obsidian view". A disposable
  capture buffer whose documented lifecycle is promote-then-prune has no rendering
  contract to protect.

Reproduction (generic), at v1.73.4:
  1. mkdir -p <fixture>/vault/raw/sessions, with a CLAUDE.md declaring a boundary.
  2. bin/rag-capture.sh --wiki <fixture>/vault --repo <any git repo>
     -> appends a capture block; `reflow.sh --check` on it exits 0. The hook's OWN
        output does not drift: its payload is fenced, so reflow leaves it alone.
  3. Add a hard-wrapped `_(pruned <date>: ...)_` marker to that buffer — three short
     lines, the shape a checkpoint session writes when it prunes a spent block.
  4. bin/lint.sh --wiki <fixture>/vault
     -> === soft-wrap ===
        would reflow: <fixture>/vault/raw/sessions/<YYYY-MM>.md
        ...
        link lint: 0 content-node page(s), 0 error(s), 0 stub warning(s)
        lint: FAILURES above

  Step 4 is the whole report in one screen: soft-wrap fails on the file while link
  integrity, in the same run, reports the vault has ZERO content-node pages.

Failure shape: fail-closed. Nothing is lost or corrupted; both gates printed their
  reasons. It costs a detour — but the remedy still on offer in that situation is
  `--no-verify`, and this is a gate refusing over a file the operator cannot commit
  even if they wanted to, which is the shape that teaches the bypass.

Already ruled out:
  - NOT rag-capture.sh's output. Fixture step 2 above: its blocks are fenced, and
    reflow --check exits 0 on a freshly captured file. The drifting prose is written
    by a session following the checkpoint skill's prune step, not by the hook.
  - NOT a stale-pin artifact. Reproduced at v1.73.4 in a fixture, not carried over
    from the version the incident happened on.
  - NOT the worktree guard. It allowed the commit explicitly and by name; only lint
    refused.
  - NOT specific to a pin-bump commit. Any commit to the vault runs the same hook, so
    any commit is refusable by drift in this buffer.

Suggested fix (HOLD LOOSELY — may be wrong):
  Give the soft-wrap check the population the rest of lint.sh already uses — pass
  `raw` as an extra skip to `vault_pages` for that section. `vault_pages` already
  accepts extra skips, and its own comment cites the verified-status report as a
  caller that skips `raw`, so the precedent and the mechanism both exist.

  Consider whether that is too broad before taking it: raw/articles, raw/papers and
  raw/transcripts are TRACKED immutable sources. Excluding them from soft-wrap seems
  right for the same reason — they are captured verbatim, and reflowing a transcript
  would be a corruption rather than a normalization — but that is the engine's call,
  not the reporter's, and it is the one part of this I would expect to be revised.

  A narrower alternative, offered and not preferred: skip git-ignored files. It targets
  the actual property, but it puts a git query inside a filesystem walk that currently
  has none, and it would still lint the tracked raw/ sources this note argues against.

  A third option is to change nothing in lint.sh and reflow the buffer on write. I
  raise it only to decline it: it makes every writer of that file responsible for a
  convention that exists for pages nobody renders.

  Separately, and independent of whichever fix is chosen: `lint: FAILURES above` could
  name the failing sections. The verdict currently costs a scroll past ~570 lines of
  passing output and 50 warnings to find one line. That is a second, smaller thing and
  should not hold up the first.

Redactions: absolute paths replaced with <vault> / <fixture>; the consumer vault's
  name, org and the buffer's month filename removed. One genuine gap, deliberate: the
  live incident's buffer was git-ignored and was repaired in place by reflow.sh before
  anyone thought to copy it, so the exact drifting line from the real failure is
  UNRECOVERABLE and is not reported here. Nothing above depends on it — the fixture
  reproduces the mechanism from scratch.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
