---
slug: distill-finish-pr-route-counts-an-earlier-merged-pr-as-this-landing
outcome: open
received: 2026-10-06
---

HANDOFF — engine defect report
slug: distill-finish-pr-route-counts-an-earlier-merged-pr-as-this-landing
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill-finish.sh on a `publish = pr` vault reports VAULT DONE for a commit that never reached main, when the session's branch name already had a merged pull request

Engine version: v3.3.1
Still live at that release: reproduced 2026-10-06 with the installed v3.3.1 `bin/distill-finish.sh`, immediately after adopting 3.3.1.

Observed: one session landed three vault changes in turn. Each time `vault-worktree.sh ensure` recreated the worktree on the same session-keyed branch `wt/<session>`, because the branch name is derived from the session id. The first two landed through pull requests that were merged (squash), which retired the worktree. The third commit then ran `distill-finish.sh`, which printed

    distill-finish: pushed wt/<session>
    distill-finish: pull request #<previous> is merged; main fast-forwarded
    distill-finish: recall index rebuilt
    distill-finish: retired worktree <vault>/.worktrees/<session>
    VAULT DONE — 1 commit(s) landed by the pr route

`main` on the remote still lacked the commit: the recorded release in it was unchanged, and the new commit existed only on the pushed `wt/<session>` branch and its local ref. No pull request had been opened for it.
The lookup is

    gh pr list --head "$BRANCH" --state all --json number,state -q '.[0] // empty | "\(.number) \(.state)"'

With `--state all`, the first entry is the earlier, already-merged pull request for the same head branch name, so `state` reads MERGED, the create is skipped and the landing is declared done.

Expected: a commit counts as landed only when the pull request that carries THAT commit is merged. On a reused branch name whose earlier pull request is merged, the script should open a new pull request and report `VAULT OUTSTANDING — pull request #<new> is not merged`, and it should not retire the worktree.

Reproduction (generic):
  1. In a `publish = pr` vault, `vault-worktree.sh ensure`, commit, run `distill-finish.sh`; merge the opened pull request (squash) and rerun it so the worktree retires.
  2. In the same session, `vault-worktree.sh ensure` again (same branch name), commit a second change, run `distill-finish.sh`.
  -> `pull request #<first> is merged`, `VAULT DONE`, worktree retired; the second commit is not on main.

Failure shape: fail-open — it reports DONE (the signal an operator closes the session on) and removes the worktree while the change has not landed. No data was lost here only because the branch survived locally and on the remote; the commit was recovered by opening a pull request by hand and merging it.

Already ruled out:
  - Not the 3.3.0 `#null` defect: v3.3.1's `// empty` is present and working; the lookup returns a real, merged pull request.
  - Not a squash-merge ancestry confusion in canonical: the decision is made from the pull request's state alone, before any ancestry check.
  - I think `--state all` is there so a rerun after the operator merges is recognised as landed — that case must keep working; not verified against the tests.

Suggested fix (HOLD LOOSELY — may be wrong): select the pull request that carries the current branch tip, not the first one for the head name — e.g. add `headRefOid` to `--json` and keep only an entry whose `headRefOid` equals `git -C "$WORK" rev-parse HEAD`; with none, create. That still recognises the merged-rerun case (the merged pull request's head is the tip) and would produce the Expected above. Alternatively, `vault-worktree.sh ensure` could mint a fresh branch name when the previous one has a merged pull request, but that only hides the lookup's assumption.
A regression test: a `gh` stub whose `pr list` returns one MERGED entry with a different `headRefOid` than the branch tip; red against v3.3.1.

Redactions: the session id is `<session>`, the vault root `<vault>`, and pull request numbers `<previous>` / `<first>` / `<new>`; the organisation and repository are omitted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
