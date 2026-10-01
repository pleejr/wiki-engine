---
slug: checkpoint-integrate-step-diverges-a-pr-bound-vault
outcome: accepted
reason: "accepted as suggested. Reproduced at v2.6.0 with a bare remote and a squash-merge from a second clone: ahead 1, behind 1, ff refused, trees identical. Skipping integrate (push, squash-merge, pull --ff-only, gc) left main even with origin and gc retired the branch as squash-merged. checkpoint §0 now routes by how the vault publishes, and §5 waits for the commit to reach canonical main by either route. The sibling sweep found skill-candidates prescribing the same unconditional integrate in two places; both fixed. The class is now mechanical: lint-docs check 12 fails any line in a worktree-taking skill that prescribes integrate without naming the pull-request route. DECLINED for now: the alternative of integrate refusing or warning when the session branch has a remote upstream. Pushing before integrate is also normal in a direct-to-main vault that backs branches up, so the signal does not separate the two flows; the written route closes all three reported occurrences"
received: 2026-09-30
---

HANDOFF — engine defect report
slug: checkpoint-integrate-step-diverges-a-pr-bound-vault
boundary: generic (engine-domain; contains no consumer-private context)

Title: checkpoint §0 prescribes `integrate` unconditionally, which diverges canonical main in a vault that ships through squash-merged PRs

Engine version: v2.6.0
Still live at that release: read `skills/checkpoint/SKILL.md` at v2.6.0 — §0's last bullet ("When the writes are committed, `vault-worktree.sh integrate` …") carries no condition, and §5 says to run `rag-build.sh` "after the §0 worktree is integrated". Reproduced on 2026-09-30 by following §0 literally.

Observed: in a consumer vault whose convention is branch → pull request → squash-merge, following §0 in order (commit in `$WORK`, `integrate`, then push the branch and merge its PR) leaves canonical `main` one ahead and one behind `origin/main`. `integrate` fast-forwards local `main` to the unsquashed session commit; the squash-merge lands a different SHA with the same tree; the consumer's post-merge local fast-forward then fails with `fatal: Not possible to fast-forward, aborting.` Trees are byte-identical (`git diff --stat main origin/main` is empty), so the fix is a manual `git reset --keep origin/main` (or `--hard` on a clean tree). Hit three times in five days in one consumer vault, each time by an agent following the written step. A later checkpoint pass that skipped `integrate` (commit → push → PR → merge → `gc`) left nothing to reconcile, and `gc` correctly reported the branch "content already in main — squash-merged or equivalent".

Expected: §0 should not route a PR-bound change through `integrate`, because in that flow the merge is the only thing that should move `main`. The precedent is `vault-worktree.sh` itself: its integrate step already detects content-equal divergence on a clean canonical and adopts `origin/main` (`bin/vault-worktree.sh` around the "adopted origin/<main> (same content, republished history — squash-merge)" log line) — which shows the engine already treats this state as a known squash-merge artefact, but only on the *next* `integrate`, not when the consumer's own merge step hits it.

Reproduction (generic):
  1. In a consumer vault that merges vault changes by squash-merged PR, run `vault-worktree.sh ensure`, edit a note in `$WORK`, commit.
  2. Run `vault-worktree.sh integrate` from `$WORK` (as §0 says).
  3. Push the session branch, open a PR, squash-merge it.
  4. In canonical: `git fetch && git status -sb`
  -> `## main...origin/main [ahead 1, behind 1]`; any `git merge --ff-only origin/main` or `pull --ff-only` fails.

Failure shape: fail-closed — nothing is lost (trees identical), but every pass costs a manual reset and a reader who does not first check tree equality may resolve it with a rebase or merge that duplicates history.

Already ruled out:
  - Not the "real divergence" case (canonical holding unpublished work): here the local commit is content-identical to the squash.
  - Not a `gc` defect: `gc` recognises the squash-merged branch and retires it.
  - `integrate`'s adopt branch does heal it, but only if `integrate` runs again later; it does not help the merge step that just failed.

Suggested fix (HOLD LOOSELY — may be wrong): make §0's last bullet conditional — "If the change ships through a pull request, do not `integrate`: push the session branch, open the PR, let the merge move `main`, fast-forward canonical, then `gc`. `integrate` is for vaults (or changes) that land on `main` directly." Adjust §5's "after the §0 worktree is integrated" to "after the change is on canonical `main` (integrated or merged)". An alternative is for `integrate` to refuse or warn when the session branch has an upstream on the remote, but the doc fix alone would have prevented all three occurrences.

Redactions: consumer vault name, org, PR numbers, and the consumer's merge-helper script path replaced with generic wording; command output is verbatim.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
