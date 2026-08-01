---
slug: per-machine-gate-config-resolved-from-worktree
outcome: accepted
received: 2026-08-01
---

HANDOFF — engine defect report
slug: per-machine-gate-config-resolved-from-worktree
boundary: generic (engine-domain; contains no consumer-private context)

Title: The foreign-boundary gate reports "not armed" on every worktree commit, because
its patterns file is git-ignored per-machine state and `lint.sh` resolves it from the
content tree

Engine version: v1.49.0 (found at intake of `generators-resolve-wiki-path-not-session-worktree`)
Still live at that pin: reproduced at that pin against a real adopted vault — the file
is present in the canonical checkout and absent from `<vault>/.worktrees/<session-id>/`,
and `lint.sh --wiki <worktree>` prints the "no patterns file" form of the message while
`lint.sh --wiki <canonical>` does not.

Observed:
  `lint.sh` gate 10 resolves `GATES_CONF="$WIKI/.wiki-gates.conf"` and then the
  patterns file as `"$WIKI/$fb_file"` (default `.wiki-gates.local`). That patterns
  file is **git-ignored by design** — the engine's own seam documentation says so,
  because committing the foreign identifiers a personal-boundary vault must reject
  would write those identifiers into permanent history, which is the exact thing the
  gate exists to prevent.

  A git-ignored file is, structurally, never present in a linked worktree: `git
  worktree add` populates tracked content only. So:

    - `scaffold/pre-commit` invokes `"$ENGINE/lint.sh" --wiki "$ROOT"`, where `$ROOT`
      is the worktree being committed from;
    - `vault-worktree.sh guard`, wired from the same hook, REFUSES a commit made in
      the canonical checkout;
    - therefore every commit in an adopted vault is a worktree commit, and gate 10
      reads its patterns from a tree that structurally cannot contain them.

  The gate is not bypassed loudly — it prints `not armed: no .wiki-gates.local
  (declare foreign-boundary patterns there to enable)` and `lint.sh` continues to
  exit 0. A consumer who deliberately armed the gate sees the identical outcome to a
  consumer who never configured it.

  Vault CI is not a backstop here: the file is git-ignored, so a fresh clone has no
  copy either. The gate is effectively armed only for a hand-run
  `lint.sh --wiki <canonical>`, which is not a path anything invokes.

Expected:
  Machine-local gate configuration should be read from the canonical checkout — the
  only tree that can hold it — while the pages being scanned continue to come from
  the tree being committed. `lint.sh` needs two roots, not one. Failing that, a gate
  whose patterns file is absent *while the vault has one in canonical* should refuse
  rather than report itself unarmed, since "unarmed" and "armed and clean" must not
  be indistinguishable — a rule the engine already states for this very gate.

Reproduction (generic):
  1. In an adopted vault with the worktree concurrency model wired, declare at least
     one pattern in `<vault>/.wiki-gates.local` (git-ignored).
  2. WORK="$(<vault>/engine/bin/vault-worktree.sh ensure)"
  3. <vault>/engine/bin/lint.sh --wiki "$WORK"   # what the pre-commit hook runs
  -> === foreign boundary ===
     not armed: no .wiki-gates.local (declare foreign-boundary patterns there to enable)
     ...while `--wiki <vault>` arms it.
  4. Commit a page carrying a declared foreign identifier from "$WORK". It passes.

Failure shape: fail-open
  On a boundary gate, which is the severe case: the write succeeds, the gate prints a
  line that reads as configuration state rather than as a failure, and nothing
  downstream re-checks. It is the same shape as the engine's previously-fixed "a
  boundary filter that silently disabled itself on an unrecognized value".

Already ruled out:
  - Not a mis-set `$WIKI_PATH`, and not the same bug as
    `generators-resolve-wiki-path-not-session-worktree`. That one is about the tree a
    generator WRITES; this is about a per-machine input a linter READS, and the two
    want OPPOSITE roots. Fixing the generators does not touch this, and naively
    extending worktree resolution to the linters would make it permanent.
  - Not specific to `foreign_boundary_patterns`. Any seam value naming a git-ignored,
    per-machine file inherits it; `external_refs` escapes only because the vault
    observed happens to track its target.
  - Not fixed by committing the patterns file — that is precisely what the seam's
    design forbids.

Suggested fix (HOLD LOOSELY — may be wrong):
  Give `lint.sh` a canonical root derived the way `scaffold/pre-commit` already
  derives one (`git rev-parse --git-common-dir`/..), and read `.wiki-gates.conf` plus
  any per-machine file it names from THAT, while every page scan keeps using
  `--wiki`. Alternatively, keep one root but have the gate consult the canonical
  checkout only when its patterns file is missing from the content tree. I have not
  worked through what either does when `--wiki` names a vault unrelated to cwd (a
  cross-vault lint), which is the part most likely to be wrong.

Redactions: vault name, machine home path and session UUID replaced consistently with
`<vault>` and `<session-id>`; quoted output is otherwise verbatim. The vault's actual
foreign-boundary patterns were not read and are not reproduced here.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested
fix as a hypothesis, not a specification.
