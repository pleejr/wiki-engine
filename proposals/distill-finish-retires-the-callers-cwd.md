---
slug: distill-finish-retires-the-callers-cwd
outcome: open
received: 2026-11-17
---

HANDOFF — engine defect report
slug: distill-finish-retires-the-callers-cwd
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill-finish.sh deletes the directory its caller must be standing in, leaving a cwd-persisting harness in a deleted directory

Engine version: v3.8.0
Still live at that release: reproduced on v3.8.0; `origin/main` of the engine is at v3.8.0, `skills/distill/SKILL.md` step 4 still says "run from `$WORK`", and `bin/distill-finish.sh` still resolves the worktree from `git rev-parse --show-toplevel` of the current directory and retires it in step 6.

Observed: following the distill skill, the agent ran `cd <vault>/.worktrees/<session-id> && distill-finish.sh` in an agent harness whose shell keeps its working directory between tool calls. The script landed the commit and printed `retired worktree <vault>/.worktrees/<session-id>` and `VAULT DONE`. The next, unrelated shell call (a `tail` of a file under the scratch directory) was refused by the harness:

  Error: Working directory "<vault>/.worktrees/<session-id>" no longer exists, so this command was not run. Shell cwd recovered to "<start dir>": re-issue the command if it still makes sense there.

Expected: finishing a distill leaves the caller's shell in a directory that still exists, so the next command runs. The script's own contract requires the caller to be inside `$WORK` (step 1 refuses canonical) and then deletes `$WORK` (step 6), so any caller that obeys the skill literally in a persistent shell is guaranteed to hit this.

Reproduction (generic):
  1. In a harness whose shell cwd persists across calls, `WORK="$(vault-worktree.sh ensure)"`, edit, commit.
  2. `cd "$WORK" && distill-finish.sh` (as the skill says: "run from `$WORK`").
  3. Let the route land the branch so step 6 retires the worktree.
  4. Run any further shell command.
  -> the harness refuses it: working directory no longer exists. Nothing is lost; the command simply does not run.

Failure shape: fail-closed (refuses the next command; no data lost). It recurs on every successful distill in such a harness, and an agent that does not notice may drop the command it meant to run.

Already ruled out:
  - Not the PR-merge helper: it reported keeping the local branch because the worktree was still checked out, and did not remove the worktree.
  - Not a stale or peer worktree: the retired path was this session's own worktree, retired by distill-finish step 6 as designed.
  - The script itself cannot fix the caller's cwd: it runs as a child process and cannot change its parent shell's directory.

Suggested fix (HOLD LOOSELY — may be wrong):
  - SKILL.md step 4: run it in a subshell so the caller's cwd never moves into `$WORK`: `( cd "$WORK" && .../distill-finish.sh --repo ... )`. Smallest change; produces the Expected for any harness.
  - Optionally, `distill-finish.sh -C <worktree>` (or honouring a `WORK` env var) so it can run from canonical; step 1's "wrong tree" check would then test the named tree, not `$PWD`.
  - Optionally, have step 6 print a one-line warning when the invoking `$PWD` is inside the tree it is about to remove ("your shell is inside the retired worktree; cd to <canonical>").
  Either of the first two produces the Expected; the warning alone does not, it only explains the failure.

Redactions: the vault root is `<vault>`, the session worktree id `<session-id>`, the harness start directory `<start dir>`. No other detail was removed.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
