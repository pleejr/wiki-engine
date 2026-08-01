---
slug: generators-resolve-wiki-path-not-session-worktree
outcome: open
received: 2026-08-01
---

HANDOFF — engine defect report
slug: generators-resolve-wiki-path-not-session-worktree
boundary: generic (engine-domain; contains no consumer-private context)

Title: Index generators resolve $WIKI_PATH (the canonical checkout) instead of the session worktree they are invoked from, so a regenerated index is written outside the branch that changed it

Engine version: v1.49.0
Still live at that pin: reproduced today at v1.49.0 by the steps below — `--check`,
which performs no write, reports on the canonical checkout's `index.md` while cwd is
inside a session worktree created by `vault-worktree.sh ensure` in the same session.

Observed:
  `gen-projects-index.sh` resolves its target as `WIKI="${WIKI_PATH:-}"` and never
  consults cwd. `$WIKI_PATH` is a machine-global constant pointing at the canonical
  vault checkout (set at session boot). So when a session is working inside
  `<vault>/.worktrees/<session-id>/` — which `vault-worktree.sh` exists to enforce —
  a bare invocation regenerates and writes `<vault>/index.md`, the shared canonical
  tree, not the worktree the session is committing from. Exit 0, and the success line
  names the canonical path, but it reads as ordinary success.

  Two consequences:
  1. The regenerated index lands OUTSIDE the branch whose page edit caused the
     regeneration, so the PR that changes a project's `summary:` can omit the index
     update that summary requires.
  2. The canonical checkout acquires an uncommitted modification nothing asked for.
     That tree is shared with other concurrent sessions, and a concurrent session
     committing with `git add -A` sweeps up the foreign edit — the exact clobber
     the worktree feature was introduced to prevent.

  The two features contradict each other: `vault-worktree.sh` exists so a session
  never writes the shared tree, and the generators default to precisely that tree.

Expected:
  Invoked from inside a session worktree with no explicit `--wiki`, a generator should
  target the worktree it is standing in — the checkout whose branch will carry the
  commit — rather than a machine-global path that names a different working tree.
  At minimum it should refuse rather than silently write a checkout the caller is
  not committing from.

Reproduction (generic):
  1. In a vault whose machine sets $WIKI_PATH to the canonical checkout:
       WORK="$(<vault>/engine/bin/vault-worktree.sh ensure)"
  2. cd "$WORK"                      # now inside <vault>/.worktrees/<session-id>
  3. bash engine/bin/gen-projects-index.sh --check
  -> ok: <vault>/index.md projects catalog is up to date        (exit 0)
     i.e. it reported on the CANONICAL checkout, not "$WORK".
     Drop `--check` and the same resolution performs a write there.

Failure shape: fail-open
  The write succeeds, exits 0, and looks like the operation the caller asked for.
  Partial backstop, worth knowing so the severity is not overstated: the pre-push
  lint invokes the generator with an explicit `--wiki <worktree>`, so when the
  generated content genuinely differs it fails `--check` and blocks the push. That
  catches consequence 1 at push time. Nothing catches consequence 2 — the stray
  modification in the shared canonical tree — at any time.

  That explicit-`--wiki` hook path is also what makes this hard to notice: two entry
  points to the same generator disagree about which `index.md` is "the" index, and
  the correct one is the one a human never invokes by hand.

Already ruled out:
  - Not a stale or misconfigured $WIKI_PATH. It correctly names the canonical
    checkout; that is its documented job. The bug is that a *worktree-aware* engine
    treats that value as the write target unconditionally.
  - Not the pre-push hook's behavior. The hook passes `--wiki` explicitly and
    resolves correctly; it is the bare/manual invocation that diverges.
  - Not specific to the projects generator. `WIKI="${WIKI_PATH:-}"` is the shared
    idiom across the generator/lint family (skills-index, lint-links, lint-summary-
    volatility, lint, doctor, session-banner), so the class is broader than one
    script even though only the two generators write files.

Suggested fix (HOLD LOOSELY — may be wrong):
  Resolve the target as: explicit `--wiki` > the git worktree root of cwd when cwd is
  inside a checkout of the same repository > `$WIKI_PATH`. A narrower variant that
  fixes the data-safety half without changing resolution: keep $WIKI_PATH as the
  default but refuse to WRITE when cwd is inside a different working tree of the same
  repo, directing the caller to pass `--wiki`. I have not thought through what either
  does to non-worktree callers (cron, a bare hook environment, a session started
  outside any checkout), and that is the part most likely to make this wrong.

Redactions:
  Vault name, machine home path, session UUID, org and account identifiers replaced
  with `<vault>` and `<session-id>` consistently throughout, so the reproduction
  remains runnable as written. Nothing else was removed; the quoted output line is
  otherwise verbatim.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
