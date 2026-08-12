---
slug: update-writes-a-page-canonical-refuses-when-no-worktree-is-live
outcome: accepted
received: 2026-08-12
---

HANDOFF — engine defect report
slug: update-writes-a-page-canonical-refuses-when-no-worktree-is-live
boundary: generic (engine-domain; contains no consumer-private context)

Title: update.sh defers the repo-page write only when a worktree is already live, so on an isolation-enabled vault with none open it writes tracked content into canonical and the guard then refuses the only commit that would land it

Engine version: v1.54.0
Still live at that pin: hit while adopting v1.54.0 into a real vault, on the first `update.sh` run after the release.

Observed: v1.52.0's `update-writes-canonical-against-the-worktree-convention` fix split the pin from the page — the pin is a gitlink so it can only be staged in canonical, while the page is ordinary tracked content that belongs in the caller's worktree. The deferral test is:

    linked_worktrees="$(git -C "$WIKI" worktree list --porcelain | grep -c '^worktree ')"
    if [ "$PAGE_TREE" = "$WIKI" ] && [ "${WIKI_WORKTREE:-1}" != "0" ] && [ "${linked_worktrees:-1}" -gt 1 ]; then
      defer_page=1
    fi

The third clause requires a worktree to ALREADY EXIST. Isolation being enabled and a worktree being live are different states, and between sessions the second is false while the first stays true. In that state `defer_page` is 0, the page is written and staged in canonical, and `vault-worktree.sh guard` — which permits a submodule-pointer-only commit and refuses anything staged beside it — then refuses to commit it. The tool produces a change in the one tree that cannot commit it.

Measured on a clean vault, isolation on, zero worktrees:

    ./engine/bin/update.sh
    -> "Staged: engine -> v1.54.0" and "Also staged: repos/<repo>.md provenance -> v1.54.0"
    git commit engine -m "Bump engine to v1.54.0"
    -> ALLOWED: "allowing a submodule-pointer-only commit in canonical"
    git commit repos/<repo>.md -m "..."
    -> REFUSED: "refusing a commit in the CANONICAL checkout"

The printed remedy is `WIKI_WORKTREE=0`, which is precisely the workaround v1.52.0 removed for the pin, reappearing one component over for the page.

Expected: the deferral keyed on whether the CALLER will be able to commit what is written, not on whether some other session happens to have a worktree open. A vault with isolation on has the same guard whether or not a worktree exists at that moment.

Reproduction (generic):

  1. A vault with `vault-worktree.sh guard` wired via `core.hooksPath` and `WIKI_WORKTREE` unset.
  2. `git worktree list` shows only canonical.
  3. Run `update.sh` with a new engine tag available.
  -> the repo page is written and staged in canonical; the pin commit is allowed and the page
     commit is refused.
  4. Repeat with one session worktree open.
  -> the page is correctly deferred and only printed. The two runs differ solely in whether an
     unrelated worktree existed.

Failure shape: **fail-closed, and the refusal is correct** — nothing is lost or corrupted, and the guard is doing its job. The defect is that the engine's own tool created the state its own gate exists to refuse, and then recommended turning the gate off. The comment above the test says the deferral is "keyed on worktrees actually existing, so the common single-session case never has to read an explanation", which reads as deliberate; the case it did not anticipate is isolation-on-with-none-open, where canonical is NOT the caller's working tree even though no worktree is listed.

Already ruled out:

  - Not a mis-wired guard: the pointer-only commit was allowed in the same run, which is the guard behaving exactly as v1.52.0 specified.
  - Not `WIKI_WORKTREE` being set to something odd: it is unset, so the `:-1` default applies and isolation is on.
  - Not the page content being wrong: the provenance rewrite itself is correct and committed cleanly once moved to a worktree.
  - Not unique to the engine's own page — any `repos/*.md` documenting the engine takes the same path.

Suggested fix (HOLD LOOSELY — may be wrong): drop the `linked_worktrees > 1` clause, so the deferral follows the isolation setting alone — if isolation is on, the page is printed for the caller to apply on a branch, whether or not one is open yet. That makes the two runs above behave identically, which is the property that is missing. The weaker alternative is to keep the clause and have `update.sh` take a worktree itself, but that puts a tool that is documented as "stages, no commit" in the business of creating branches, which is a larger change than the defect warrants.

Please do not resolve it by widening what `guard` permits. The page is ordinary tracked content and staging it in a shared tree is the exact clobber the guard exists to prevent; the fix belongs on the writer's side.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
