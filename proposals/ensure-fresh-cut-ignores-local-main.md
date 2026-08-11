---
slug: ensure-fresh-cut-ignores-local-main
outcome: partially-accepted
received: 2026-08-01
reason: "defect reproduced at HEAD and fixed as the reporter's low-risk half — a fresh cut now names the commits canonical <main> holds that its base lacks, and the wording says READS are affected, since the collision wording that already existed describes the failure mode that does not apply here. Extended beyond the reported path to reattach and reuse, which are the same blind spot: both measure against origin/<main>, the ref that is behind by construction, and reattach makes the positive claim 'level with $base'. The larger option — cutting off local <main> when origin/<main> is an ancestor — is DECLINED, as the reporter flagged rather than recommended it: it would put never-pushed commits on every wt/* branch, changing what ensure promises and what gc's containment test and every wt/*-versus-remote assumption are reasoning about, to buy nothing the warning does not. integrate already reconciles local <main>, so committed work was never at risk; the loss was to reads, and a warning is the whole of that remedy"

HANDOFF — engine defect report
slug: ensure-fresh-cut-ignores-local-main
boundary: generic (engine-domain; contains no consumer-private context)

Title: `ensure` reports plain success on the CREATE path while the base it cut omits commits local `<main>` already holds

Engine version: v1.50.0 (submodule at fe15e49)

Still live at that pin: read at the pinned sha rather than assumed. `ensure` sets `base="origin/main"` and fetches (bin/vault-worktree.sh:337-338); the create path is `worktree add -q "$wt" -b "$branch" "$base"` followed by `log "vault-worktree: created $wt (branch $branch off $base)"` (:384-386) — there is no `behind_count` call on that path at all. The check added for the reattach fail-open (:368-377) is unreachable here (it is in the `show-ref` branch, :366) and would report 0 regardless, since it measures `behind_count "$branch" "$base"` and `$base` IS the ref that is behind. Reproduced live during a session at this pin.

Observed: a vault checkout whose canonical `<main>` was 2 commits ahead of `origin/<main>` — an earlier session's work committed but not pushed. A later session called `ensure`, which fetched, cut a fresh branch off `origin/<main>`, and printed:

    vault-worktree: created <wt> (branch wt/<slug> off origin/main)

exit 0, isolation genuinely intact, working tree clean. The returned worktree silently lacked both commits. The session's opening move was a survey — grep the vault for prior coverage of the topic about to be written up — which returned **zero hits, exit 0**. One of the two missing commits was the earlier session's write-up of that exact topic. Nothing in the tool output, the exit status, or the tree state distinguished this from a vault that genuinely had no prior coverage.

Expected: `ensure` should not hand back a base that omits committed work present in canonical `<main>`, without saying so. The reattach path already treats exactly this as a fail-open worth three lines of warning plus a rebase command; the create path makes the same promise ("off origin/main") and does not check whether that promise leaves the caller behind.

Reproduction (generic):

    1. In a vault checkout, commit to `<main>` and do NOT push
       (the natural case: any session that committed and left the push for later).
    2. From a new session slug, run:  bin/vault-worktree.sh ensure
       -> vault-worktree: created <wt> (branch wt/<slug> off origin/main)
       -> exit 0
    3. In the returned worktree, search for content introduced by that commit:
         grep -rl '<a string only the unpushed commit added>' <wt>
       -> no output, exit 0
    4. Confirm the base is actually behind:
         git -C <wt> rev-list --left-right --count main...HEAD
       -> 2	0

Failure shape: fail-open. Not data-loss — `integrate` rebases the session branch onto local `<main>` (:637), so committed content reconciles correctly at the end. The damage is to everything the session *read* in between, and it lands as duplicated content rather than as a conflict.

Why this is the dangerous half of a known problem: the staleness failure the engine already guards is a COLLISION — a conflict on an appended-to page, an edit whose anchor will not match. Those are loud; the tool refuses and the base gets questioned. A stale base corrupts SEARCHES the opposite way: `grep` exits 0 and prints nothing, and "nothing has been written about this yet" is an entirely ordinary thing for a vault to be true about. There is no anomaly, so the base is never suspected, and the session writes a duplicate of work that already exists — which is precisely the outcome the worktree exists to prevent. A first-thing-in-the-session survey is load-bearing for every decision after it, since it decides whether the work is new.

Aggravator, and the reason this is not rare: any workflow that leaves `<main>` ahead of `origin/<main>` for a while re-arms it on every subsequent `ensure`. That includes the ordinary "commit now, push at the end" habit, and any session that ends without pushing. It is also self-perpetuating — the session that hits it commits more unpushed work, so the next fresh cut is further behind.

Already ruled out (so these need not be walked again):

  - "`ensure` does not fetch" — false, it does (:338). This is not a fetch-freshness bug; `origin/<main>` was current. The missing commits were local-only, which no fetch can surface.
  - "the reattach behind-check covers it" — it does not, on two counts: it lives in the `show-ref`/reattach branch and never runs on a fresh cut, AND it compares against `$base`, the ref that is by construction behind. Even wired onto the create path unchanged it would print 0.
  - "`gc`/`branch_contained` is implicated" — no branch existed; this is the first cut for the slug.
  - "the fallback path (:389+) fired" — no, it did not; the create path succeeded and exited 0.
  - data-loss — ruled out by reading `integrate`, which reconciles local `<main>` before rebasing (:585-635). Committed work survives.

Note for whoever picks this up: `integrate` already encodes the invariant this is missing. It explicitly reconciles canonical `<main>` against `origin/<main>` before choosing a rebase base, with a comment explaining that using the local ref naively is what produced an earlier defect. So the engine already knows the two refs diverge routinely — `ensure` is simply not consulting local `<main>` at cut time, on the one path where nothing else will.

Suggested fix (HOLD LOOSELY — may be wrong): the low-risk half is to reuse the reporting that already exists — after a successful fresh cut, compute the distance to local `<main>` (not `$base`) and, when non-zero, emit the same shape of warning the reattach path emits, naming the rebase command. That is additive and changes no base selection.

The larger option — cutting off local `<main>` when `origin/<main>` is an ancestor of it — is offered with less confidence, and is flagged rather than recommended: it would change what `ensure` promises, and the session branch would then carry commits that have never been pushed, which may interact with assumptions elsewhere (`gc`'s containment test, and anything that reasons about `wt/*` relative to the remote). Please judge it against the observation, not against my preference between the two.

One more thing worth deciding on, which is not code: a consumer following the documented flow has no reason to run a distance check of their own, because the tool reported success. If the fix is warn-only, the warning is the entire remedy and its wording is load-bearing — it needs to say that READS are affected, not only that merges will conflict. The existing reattach warning speaks only of merge-time conflicts, which is the failure mode that does not apply here.

Redactions: the vault name, its repository slug, absolute paths, the git identity, and the session UUID are replaced by `<vault>`, `<wt>`, `<slug>`, `<main>`. The searched-for string was a note added by one of the unpushed commits; its content is consumer-domain and irrelevant to the mechanism, so it is given as `<a string only the unpushed commit added>`. Line numbers and quoted output are from the engine's own source at the pinned sha and are unmodified. Nothing else was removed.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
