---
slug: distill-finish-pr-route-reads-null-as-a-pr-number
outcome: accepted
reason: "accepted as suggested. Reproduced with real gh: `gh pr list --head <no-pr-branch> --json number,state -q '.[0] | ...'` prints `null null`, exit 0; `.[0] // empty` prints nothing. The CI stub had printed nothing for `pr list`, which is not what gh prints, so the create path was never exercised; the stub now runs the caller's -q through jq over the JSON list, and the existing pr-route assertion goes red against 3.3.0. The suggested stderr surfacing is also taken: a failed create now reports gh's last line, with a CI case. Sibling sweep: this was the only `.[0]` interpolation in bin/."
received: 2026-10-06
---

HANDOFF — engine defect report
slug: distill-finish-pr-route-reads-null-as-a-pr-number
boundary: generic (engine-domain; contains no consumer-private context)

Title: distill-finish.sh on a `publish = pr` vault never opens the pull request; it reports "pull request #null"

Engine version: v3.3.0
Still live at that release: reproduced 2026-10-06 against the installed v3.3.0 `bin/distill-finish.sh`, on a session branch that had just been pushed and had no pull request.

Observed: the first `distill-finish.sh` run on a freshly pushed session branch printed

    distill-finish: pushed wt/<session>
    VAULT OUTSTANDING — 1 item(s):
      - pull request #null is not merged: merge it, then rerun distill-finish.sh

and `gh pr list --head wt/<session> --state all` returned `[]`, so no pull request had been opened.
The lookup in the `pr` route is

    gh pr list --head "$BRANCH" --state all --json number,state -q '.[0] | "\(.number) \(.state)"'

On an empty list, jq evaluates `.[0]` to `null` and the string interpolation renders it, so the command prints `null null` and exits 0.
`pr` becomes `null`, `[ -z "$pr" ]` is false, the `gh pr create` branch is skipped, and the `elif [ -n "$pr" ]` arm reports `#null`.

Expected: when the branch has no pull request, the script opens one (its own `gh pr create` path) and reports `pull request #<n> is not merged`, naming a real number the operator can merge.
That is the behaviour the existing create branch is written to produce; the defect is only that it is unreachable.

Reproduction (generic):
  1. In any repository with a GitHub remote, run
     `gh pr list --head some-branch-with-no-pr --state all --json number,state -q '.[0] | "\(.number) \(.state)"'; echo "rc=$?"`
     -> `null null` / `rc=0`
  2. In a `publish = pr` vault, start a session worktree, commit, and run `bin/distill-finish.sh` before any pull request exists for the branch.
     -> branch pushed, no pull request opened, VAULT line names `#null`.

Failure shape: fail-closed — nothing lands on main and the commit is safe on the pushed branch, but the remedy the VAULT line names ("merge #null") cannot be carried out, and the operator has to open the pull request by hand.

Already ruled out:
  - Not a `gh` auth or availability problem: the same `gh` pushed and later opened the pull request by hand, and the lookup itself exits 0.
  - Not a route-declaration problem: `publish = pr` was read correctly (the branch was pushed, `main` was not integrated).
  - The CI fixture for the `pr` route evidently passes; I think it either stubs `gh` or pre-creates the pull request, so it never sees an empty list — not verified.

Suggested fix (HOLD LOOSELY — may be wrong): make the empty case produce empty output, e.g. `-q '.[0] // empty | "\(.number) \(.state)"'`, so `pr` is empty and the create branch runs.
That would produce the Expected above. Separately, `gh pr create ... 2>/dev/null` hides why a create failed, and the fallback message then guesses "gh unavailable?"; surfacing gh's stderr would make that arm accurate.
A regression test that runs the `pr` route against a `gh` stub returning `[]` for `pr list` should fail against v3.3.0.

Redactions: the session branch name is `wt/<session>`; the vault, organisation and repository are omitted; no paths beyond the engine's own `bin/` are quoted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
