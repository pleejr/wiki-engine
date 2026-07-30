# Proposals — the round-trip ledger

Every `engine-proposal` handoff block carries a `slug:`. This file is where that slug comes back, so a consumer vault can ask **"what happened to mine?"** and get a deterministic answer instead of keyword-grepping this repo's git log.

## Why a ledger and not just the CHANGELOG

A proposal that **ships** leaves a trace either way — a commit, a release note. A proposal that is **declined** leaves nothing. Intake records accepted and rejected findings in the engine-dev vault, which a consumer cannot read and must not need to; the only surface both ends share is this repository. So without a row here, a considered-and-rejected proposal looks identical, forever, to one nobody started: *"not in the CHANGELOG"* — and the consumer's only rational response is to keep re-sending it.

**A row is therefore written when a proposal ARRIVES, not when it resolves.** Intake's first action is appending an `open` row; a terminal outcome is an *edit* of that row. Writing at resolution would put the rejection case on the one path with no commit, no trailer, no release and thus no mechanical trigger — exactly the discipline that already failed.

That ordering also makes **`unknown` meaningful**: a slug with no row means the engine has no record of receiving it, which is a different answer from `open` and calls for a different action (re-send, versus wait).

## Reading a row

| column | meaning |
|---|---|
| `slug` | the proposal's slug, verbatim from the handoff block. Flat and topical — **never** namespaced by consumer, which would leak the reporter into release notes. |
| `outcome` | `open` · `shipped` · `partially-accepted` · `rejected` · `alias` |
| `detail` | for `rejected` / `partially-accepted`, the reason. For `alias`, the canonical slug. For `shipped`, either an explicit `vX.Y.Z` (pre-convention backfill) or `derived` — see below. For `open`, when it arrived. |

**`shipped` + `derived` means the release is read from git, not stored here.** The trailer lands on the feature commit, but the version is only decided at the separate `Release vX.Y.Z` commit that follows it — so at the moment the trailer is written, the version does not exist. Storing it here would mean either a check that cannot pass at PR time or a second thing to keep in sync. `engine-proposal.sh status` resolves it with `git tag --contains`. Rows predating this convention carry an explicit version instead, since they have no trailer to derive from.

## Intake must not silently rename a slug

The slug is the only correlation key the reporter has. Renaming it to fit engine vocabulary breaks their ability to ever match the result back — and they will never learn why. If a rename is genuinely necessary, keep the incoming slug as an `alias` row pointing at the canonical one; `status` follows it.

## The trailer

An implementing commit carries `Proposal: <slug>` on its own line. **Placement does not matter** — `bin/lint-proposals.sh` and `engine-proposal.sh status` read the literal line wherever it appears in the message.

It used to have to sit in the final paragraph, so git's own trailer parser would see it. That requirement was removed because the documented workflow *produced* the state it rejected: merges here are squashed, and GitHub appends its own `---------` + `Co-authored-by:` footer after the PR body, displacing whatever the author put last. Following the instructions guaranteed the failure, and it surfaced only after the merge — when the only fix is rewriting published history.

Putting it beside `Co-authored-by:` is still the tidiest habit (it keeps `git log --format='%(trailers:key=Proposal)'` working), and lint says so as a note rather than an error. A `Proposal:` line inside a ``` fence or indented as a quoted example is deliberately ignored.

## Ledger

<!-- proposals:start -->
| slug | outcome | detail |
|---|---|---|
| `adopt-reconcile-gitignore` | shipped | derived |
| `adopt-step-asset-resolution` | shipped | v1.32.0 |
| `bare-status-ignores-submitted-markers` | shipped | derived |
| `concurrent-session-project-claims` | partially-accepted | the presence half is ACCEPTED and shipped as `vault-worktree.sh claim` — per-project, acquired by the context-loading skill, naming the holder and its activity age, stale-not-deleted — but recorded on the EXISTING lease rather than in a new store with a PreToolUse heartbeat: liveness, staleness and the provably-finished evidence are already decided in one place there, and a second presence mechanism can disagree with the first about who is live, which is worse than no answer. The mutation-deny tier is REJECTED for now, on three grounds: the hook surface is machine-global, so a deny gate fires in sessions that have nothing to do with the vault; the proposal's own open question 2 has no sound answer, because state-changing is not a property of a tool (the same Bash tool is also the read-only surface) and a command-shape deny-list is guessable and leaks, as the proposal says itself; and its recommended answer to open question 3 — allow-with-notice when the store is unreadable — means the hard edge disappears exactly when the mechanism breaks, which makes it a notice claiming to be a gate. Ship visibility first; a hard edge should be designed from evidence that visibility was insufficient. Cross-machine claims declined as the reporter suggested — the record is per-machine and says so |
| `crossover-export-split-default` | shipped | v1.24.0 |
| `engine-proposal-file-queue` | partially-accepted | transport diagnosis kept whole; submit split from push because the repo is public and the scan cannot see semantic leakage, the submitted-vs-local criterion re-specified on local evidence since status is offline, the banner return path replaced by pin-bump delivery, and PROPOSALS.md generated rather than retired to avoid rewriting the trailer gate |
| `gate-inert-relative-hookspath` | shipped | derived |
| `gc-containment-squash-merge` | shipped | derived |
| `project-page-staleness-queue` | partially-accepted | shape and status-gating kept; the signal is derived from git rather than the hand-maintained updated: field, which was measured drifting three days on two of three active pages, and a reviewed: marker was added — the alternative the proposal rejected — because without a clock reset the queue can never be drained to zero |
| `project-summary-volatility-gate` | partially-accepted | shape kept; warn-by-default inverted to an enforced content-hashed ratchet, slug allowlist replaced by summary hashing, and the `live` marker dropped as unreproduced |
| `proposal-slug-roundtrip` | shipped | derived |
| `push-verb-omits-git-push` | shipped | derived |
| `queue-cannot-see-unmerged-proposal-prs` | shipped | derived |
| `rag-capture-dirties-canonical-blocks-integrate` | shipped | derived |
| `rag-model-cache-durable-path` | shipped | v1.26.0 |
| `release-title-splitter-cuts-inside-code-spans` | shipped | derived |
| `session-banner-pending-proposal-nudge` | alias | engine-proposal-file-queue |
| `skills-hardcode-boundary-value` | shipped | derived |
| `statusline-composable-segments` | shipped | derived |
| `statusline-ctx-healthy-band-bold-green` | shipped | derived |
| `submit-branches-from-head-not-main` | shipped | derived |
| `submit-rejects-submodule-engine-checkout` | shipped | derived |
| `upkeep-sync-clones` | shipped | derived |
| `upkeep-tolerate-describe-refs` | shipped | derived |
| `upkeep-unresolvable-clone-skips-freshness-silently` | shipped | derived |
| `vault-worktree-integrate-rebases-onto-stale-local-main` | partially-accepted | defect confirmed and fixed; the suggested one-word change was tested and REJECTED — rebasing onto origin/<main> makes local <main> no longer an ancestor of the rebased branch, so the final merge --ff-only refuses and the divergence remains, trading a silent success for a misleading 'did main move mid-integrate?'. The local ref has to move instead: integrate now fast-forwards canonical to origin/<main> when behind, ADOPTS origin when the divergence is content-equal (the squash-merge signature, guarded by a clean-canonical check because reset --hard would discard uncommitted work), and refuses with exit 3 on real divergence. The two open design questions are deferred, not adopted: integrate still moves canonical <main>, and the success message still does not distinguish integrated-locally from published. |
| `worktree-reattach-returns-stale-base` | shipped | derived |
<!-- proposals:end -->
