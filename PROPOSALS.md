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

An implementing commit carries `Proposal: <slug>` **in its final paragraph**, alongside `Co-authored-by:`. Git's trailer parser only looks at the last block of the message, so a `Proposal:` line written anywhere else is silently invisible — `bin/lint-proposals.sh` fails on that case rather than letting it pass as "no trailer". Merges here are squashed, so the surface that actually matters is the **pull request description's** final paragraph.

## Ledger

| slug | outcome | detail |
|---|---|---|
| `crossover-export-split-default` | shipped | v1.24.0 |
| `rag-model-cache-durable-path` | shipped | v1.26.0 |
| `adopt-step-asset-resolution` | shipped | v1.32.0 |
| `proposal-slug-roundtrip` | shipped | derived |
| `gate-inert-relative-hookspath` | shipped | derived |
| `skills-hardcode-boundary-value` | shipped | derived |
| `adopt-reconcile-gitignore` | shipped | derived |
| `gc-containment-squash-merge` | shipped | derived |
| `upkeep-tolerate-describe-refs` | shipped | derived |
| `upkeep-sync-clones` | shipped | derived |
