---
slug: checkpoint-prune-reads-a-tree-that-cannot-hold-the-buffer
outcome: partially-accepted
received: 2026-08-11
reason: "defect reproduced and fixed as reported — §3 now names canonical for `raw/sessions`, mirroring §5's wording, and §0's blanket 'all edits against $WORK' carries an explicit carve-out for git-ignored per-machine state, so the next step added does not inherit the wrong tree. The class sweep was run and came back narrow: `checkpoint` is the only skill that takes a worktree, and inside it §5 (`.rag/`) was already correct, so §3 was the single live instance. Rather than leave that as prose, the class is now MECHANICAL — lint-docs.sh fails any worktree-taking skill that names a path from scaffold/gitignore.tmpl without naming canonical, which is the only checkable signal available, since 'missing' is exactly what the wrong tree looks like and no presence test can tell them apart. The check-ignore suggestion is kept as the reader-facing warning in §3 rather than as a step, because naming the tree removes the need to test for it. DECLINED for now: the separable upkeep size report. It was proposed to close the no-signal half, but the signal it would add is only load-bearing while the prune is unreachable; with §3 corrected and the gate in place the growth has an owner again, and a second reminder mechanism should be designed from evidence that the corrected step is still being skipped"

HANDOFF — engine defect report
slug: checkpoint-prune-reads-a-tree-that-cannot-hold-the-buffer
boundary: generic (engine-domain; contains no consumer-private context)

Title: checkpoint's raw/sessions prune step names no tree, so §0's worktree rule sends it to a tree that structurally cannot contain the buffer — it silently no-ops

Engine version: v1.50.0
Still live at that pin: reproduced against v1.50.0. Also checked origin/main — `git log <pin>..origin/main -- skills/checkpoint bin/rag-capture.sh` returns no commits, and `git show origin/main:skills/checkpoint/SKILL.md` still shows §3 with no tree named. Not fixed incidentally.

Observed:
  Since v1.42.0 ("untrack the per-machine capture buffer"), `raw/sessions/*.md` is
  git-ignored and only `raw/sessions/.gitkeep` is tracked. That change is correct and
  should stand — it fixed a real deadlock, because rag-capture.sh writes at SessionEnd
  when the session worktree is already gc'd, so a tracked buffer left canonical
  permanently dirty and blocked the next session's integrate.

  But checkpoint §0 instructs: "Make **all** edits, commits, and lint runs against
  `$WORK`, never `$WIKI_PATH` directly." §3 then says to prune promoted `raw/sessions`
  blocks — and names no tree. So §0 governs, and the prune is aimed at the worktree.

  A worktree checks out tracked files only, so the buffer is not there. Probed on a
  clean worktree of HEAD:

    $ ls -1 <worktree>/raw/sessions/
    .gitkeep

    $ git check-ignore -v raw/sessions/<YYYY-MM>.md
    .gitignore:52:raw/sessions/*.md    raw/sessions/<YYYY-MM>.md

  From where the skill tells the agent to stand, the directory is empty. The step
  completes, correctly reports nothing to prune, and emits no error.

  Evidence it used to work and stopped: in this consumer vault, `git log --numstat --
  raw/sessions/` shows four checkpoints deleting capture blocks before v1.42.0
  (-513, -42, -39 and -14 lines). After the untracking commit, zero deletions —
  while the buffer kept growing. Nineteen blocks accumulated across five weeks.

Expected:
  §3 should prune the buffer where it actually lives — the canonical checkout — and say
  so, the way §5 already does for the other git-ignored per-machine artifact:

    "run `rag-build.sh` **against canonical `$WIKI_PATH` after the §0 worktree branch is
     integrated** (the `.rag/` index is untracked and lives only in the canonical
     checkout, not the worktree)"

  That is the same tree, the same reason, and the correct treatment, written one section
  below the defect. §2 also already reads `$WIKI_PATH/raw/sessions/` (canonical) for
  distillation input. So §3 is the only step touching git-ignored per-machine state that
  does not name its tree, and it inherits the wrong one by default.

  Note the prune needs no commit and no integrate: the buffer is untracked, so editing it
  in canonical produces no git change and cannot dirty the tree or deadlock a peer.

Reproduction (generic):
  1. Run any engine version >= v1.42.0 with the SessionEnd rag-capture hook wired, so
     `raw/sessions/<YYYY-MM>.md` exists in canonical and is git-ignored.
  2. Start a session; run `checkpoint`.
  3. At §0, take the worktree as instructed and honour §0's "all edits against $WORK".
  4. At §3, look for promoted `raw/sessions` blocks to prune.
  -> `ls $WORK/raw/sessions/` shows only `.gitkeep`. Nothing to prune, no error, step
     passes. The blocks remain in canonical and accumulate indefinitely.

Failure shape: fail-open

  It proceeds while looking correct. Nothing surfaces the growth: upkeep.sh does not
  assess `raw/`, no size cap exists, the buffer is git-ignored so it never appears in
  `git status` or a diff, and recall only de-weights raw chunks rather than reporting
  them. So "nothing to prune" and "the buffer is unreachable from here" are
  indistinguishable from the agent's chair, and stay that way for as long as it runs.

Already ruled out:
  - Not a rag-capture.sh bug. It writes to canonical at SessionEnd deliberately, because
    the session worktree is gone by then. Correct as designed.
  - Not the untracking change being wrong. It fixed a genuine integrate deadlock and the
    content is machine-local. It should stand; only checkpoint's assumption is stale.
  - Not a missing .gitignore rule, and not a permissions or path-resolution fault.
  - Not solely agent error. An agent obeying §0 strictly sees an empty directory and
    truthfully reports nothing to prune. The one that happens to read canonical out of
    habit sees the blocks — so the behaviour varies by luck, which is its own defect.
  - Not fixed by moving the prune later in the ritual. §5 already runs after integrate
    and still has to name canonical explicitly to be correct.

Suggested fix (HOLD LOOSELY — may be wrong):
  1. §3 names canonical for `raw/sessions`, mirroring §5's existing wording and rationale.
  2. Decide the tree by asking git whether the path is ignored (`git check-ignore`), not
     by testing whether the file is missing. "Missing" is exactly what the wrong tree
     looks like, so a presence test would pass in the worktree and hide the bug again.
  3. Consider whether §0's blanket "all edits against $WORK" should carry an explicit
     carve-out naming git-ignored per-machine state, so the next step added to this skill
     does not inherit the same wrong default.
  4. Worth sweeping the class rather than this instance: any other step, in any skill,
     that touches git-ignored per-machine state from inside a worktree has this shape.
     `.rag/` and `raw/sessions/` are the two known ones; a grep for paths that appear in
     both a skill body and .gitignore would find the rest.
  5. Optional and separable: nothing reports that the buffer is growing. A read-only
     upkeep item that reports raw/sessions size without deleting anything would close the
     "no signal" half without touching the human judgement the prune deliberately keeps.

Redactions:
  - The consumer vault's name, its absolute paths, and the machine's home directory are
    replaced with <worktree>, <consumer vault> and <YYYY-MM> throughout. Substitutions are
    consistent, so the reproduction still runs as written.
  - The .gitignore line number (52) is from this consumer vault and may differ elsewhere;
    the pattern `raw/sessions/*.md` is what matters.
  - Commit subjects and repo names from the capture blocks are omitted entirely; none are
    needed to reproduce.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix
as a hypothesis, not a specification.
