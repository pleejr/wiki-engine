---
slug: proposal-submit-branches-from-an-unfetched-origin-main
outcome: accepted
reason: "accepted. Reproduced at HEAD with a bare origin moved one commit (a workflow file) past the clone: submit cut the branch from the stale tip and printed no warning. submit now fetches origin/main before choosing the start point and warns, without refusing, when the fetch fails. The optional push guard is shaped as a diagnosis rather than a pre-push refusal: a stale base that does not touch a workflow file pushes fine and GitHub diffs the pull request from the merge-base, so the unverified fail-open case shows no reverts and refusing it would block a working push. Instead a REFUSED push checks the base and names it, replacing the write-access message that misdirected the reporter. Sibling sweep: vault-worktree.sh already fetches before creating a branch; no other bin/ tool cuts a branch."
received: 2026-10-27
---

HANDOFF — engine defect report
slug: proposal-submit-branches-from-an-unfetched-origin-main
boundary: generic (engine-domain; contains no consumer-private context)

Title: engine-proposal submit cuts the proposal branch from origin/main without fetching it, so a stale clone yields a branch push can't publish

Engine version: v3.7.0
Still live at that release: bin/engine-proposal.sh submit picks `origin/main` when the ref exists (the "Prefer origin/main" block) and never runs `git fetch` first; nothing else in submit or push fetches.

Observed: on a reporter's engine clone whose last fetch was 25 commits behind the remote, `submit` prepared the branch on the stale `origin/main` (a 3.6.1 commit; the remote was at 3.7.0). `push` then failed for both proposals with:
  ! [remote rejected] proposal/<slug> -> proposal/<slug> (refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope)
The branch touched only `proposals/<slug>.md` and `PROPOSALS.md` against its own base, but against the remote's main its tree reverted later changes, including the CI workflow, which GitHub refuses from a token without `workflow` scope. After `git fetch`, deleting the branches, and re-running submit, both pushed and opened pull requests.

Expected: submit bases the branch on the remote's current main, so the pull request diff is only the proposal and push succeeds with an ordinary `repo`-scoped token. The script's own comment states this intent ("a proposal based on stale main is a needless rebase").

Reproduction (generic):
  1. in an engine clone, leave origin/main behind the remote by at least one commit that edits .github/workflows/
  2. engine-proposal.sh submit --vault <vault> --slug <slug> --file <draft>
  3. engine-proposal.sh push --vault <vault> --slug <slug> with a token lacking `workflow` scope
  -> remote rejected, as above. Without a workflow change in the gap, I expect push to succeed and the pull request to show reverts of the newer engine files (not verified).

Failure shape: fail-closed when the gap touches a workflow file (push refused, with an error that points at token scopes rather than the stale base); otherwise I think it is fail-open, since the pull request would silently carry reverts for intake to catch. The second case is not verified.

Already ruled out: uncommitted changes in the clone (porcelain status was empty); the token itself (`repo` scope pushed fine once the base was current); the local `main` branch (submit uses origin/main, which was the stale ref).

Suggested fix (HOLD LOOSELY — may be wrong): `git fetch origin main` in submit before choosing the start point, warning rather than failing when offline; optionally have push refuse when the branch's merge-base is not the remote's main tip.

Redactions: the clone's path is replaced by <engine clone>, and the vault by <vault>; the slug placeholder stands for the two proposals that hit it.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
