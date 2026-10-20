---
slug: canonical-commit-refusal-names-integrate-on-a-pr-route-vault
outcome: open
received: 2026-10-20
---

HANDOFF — engine defect report
slug: canonical-commit-refusal-names-integrate-on-a-pr-route-vault
boundary: generic (engine-domain; contains no consumer-private context)

Title: The canonical-commit refusal names `integrate` as the landing step even on a `publish = pr` vault

Engine version: 3.6.1
Still live at that release: yes. `bin/vault-worktree.sh` at engine origin/main still prints the line unconditionally (the `log "  Integrate when done: ..."` line in the canonical-commit refusal branch); reproduced in a consumer session on 3.6.1.

Observed: a commit attempted in the canonical checkout of a vault whose `.wiki-gates.conf` declares `publish = pr` is refused, and the refusal ends with
  Integrate when done:  <engine>/bin/vault-worktree.sh integrate
Following that hint fast-forwards the canonical checkout's local `main` to the session commit and prints `integrated wt/<session> -> main`, which reads as landed. Nothing is pushed. The session then pushes the branch, opens the pull request and squash-merges it; local `main` now holds the pre-squash commit and diverges from `origin/main` (content-equal), so the merge helper's fast-forward of the canonical checkout fails with `fatal: Not possible to fast-forward`. Recovery is a manual `git reset --keep origin/main`.

Expected: on a `publish = pr` vault, the refusal names the step that actually lands work by that route — `distill-finish.sh` (push the branch and open its pull request) — and does not name `integrate`, because `integrate` is the `publish = direct` route. The route is already declared in `.wiki-gates.conf` and read by `distill-finish.sh`, so the refusal can read the same key.

Reproduction (generic):
  1. Consumer vault with `publish = pr` in `.wiki-gates.conf`.
  2. Stage a change in the canonical checkout and `git commit`.
  3. Follow the printed carry steps, commit in the worktree, run `vault-worktree.sh integrate` as the hint says.
  4. Push the session branch, open and squash-merge its pull request.
  -> canonical `main` is ahead of `origin/main` by the pre-squash commit; `git diff main origin/main` is empty.

Failure shape: fail-open — `integrate` exits 0 with a success line, and the work looks published when it is local only; the divergence surfaces one step later.

Already ruled out:
  - The earlier fix to `integrate` (adopting origin when the divergence is content-equal) does not cover this: the divergence is created after `integrate` runs, by the squash-merge it preceded.
  - Operator error alone: the hint is the only remedy the refusal prints, so following it is the expected path; this consumer recorded the same sequence several times.

Suggested fix (HOLD LOOSELY — may be wrong): in the refusal, read `publish` from `.wiki-gates.conf`; for `pr`, print `Land when done: <engine>/bin/distill-finish.sh` (or "push the branch and open its pull request") instead of the `integrate` line; keep the `integrate` line for `direct` and when the key is absent. Optionally, have `integrate` itself warn or refuse on a `publish = pr` vault.

Redactions: absolute paths replaced by `<engine>`; session branch id by `<session>`; the consumer vault's name, repository and pull-request numbers omitted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
