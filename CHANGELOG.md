# Changelog

All notable changes to the wiki-engine. Versioned with [SemVer](https://semver.org/): **MAJOR** = a breaking framework change (node removed/renamed, frontmatter-schema change) that needs a migration; **MINOR** = additive (new node/tool/skill/convention), adopt with `bin/adopt.sh`; **PATCH** = a backwards-compatible fix to a consumed component. `bin/engine-version.sh` reports the delta and flags MAJOR bumps.

**What gets a tag:** the engine is consumed by *pinning a tag* (a vault's `engine/` submodule; `update.sh` advances tag→tag), so tag + release **only** when a change touches what a pinned consumer runs — `skills/`, `bin/`, `SCHEMA.md`, `scaffold/`, the `CLAUDE.md` router (`LICENSE`/legal too). **Docs-only** changes (`README`, `USAGE`, comments, this file's prose) land on `main` **untagged** — consumers read those from `HEAD`/their clone, never through the pin — and ride along under `## [Unreleased]` into the next functional release.

## [1.45.0] — 2026-07-28

Minor — project pages get the decay signal repo pages already had, drainable through the existing queue. Adopt with `bin/adopt.sh` or `update.sh`; no migration. Reported through the file queue as `project-page-staleness-queue`.

### Added
- **`upkeep scan` queues stale project pages.** A repo page carries `ref`/`sha` provenance and a `verified:` stamp, both feeding the queue; a project page had **neither**, so one nobody had touched in weeks rendered identically to one confirmed accurate yesterday and every gate passed on both. Status-gated: `active` on a short horizon, `paused`/`planned` on a much longer one asking *should this still be paused?*, `done` exempt outright, and an unknown or missing status reported **unassessable** rather than skipped.
- **`reviewed:` on a project page** — an explicit "I read this and it is still right". Thresholds are vault knobs (`UPKEEP_STALE_ACTIVE_DAYS` default 14, `UPKEEP_STALE_PAUSED_DAYS` default 90).

### Notes — what the intake review changed
- **The signal is derived from git, not read from `updated:` as proposed.** Measured against a real vault before deciding: **two of three active project pages disagreed with git by three days**, drifting toward *looking stale* — so a queue built on that field fires on pages that were in fact touched. This is the engine's own rule applied to the proposal: hand-maintained status drifts and a derived answer cannot. Age is now the newest of `reviewed:`, git's last-commit date, and `updated:`, and `scan` reports which one answered.
- **`reviewed:` exists because otherwise the queue could never reach zero.** Confirming a page is still accurate changes nothing, so the item re-fires on every scan — the always-red failure this engine keeps re-learning. The proposal **rejected** a `verified:`-style stamp as adding no information over `updated:`; right about information, wrong about function. Its job here is resetting the clock without fabricating a content edit.
- **The honest limit is documented rather than assumed away:** a bulk reflow or index regeneration bumps the git date with nobody having read the page. Git still beats `updated:` — it cannot be *forgotten*, only spuriously satisfied — but only `reviewed:` cannot be satisfied mechanically.
- **The threshold default was deferred until the reset mechanism existed**, since without one *any* threshold yields permanent entries.
- **Two assertions from v1.44.1 were silently unhooked, and CI caught it here.** That release reworded the citation error to *"has no proposal in proposals/ **and** no row in PROPOSALS.md"*, so two steps grepping for `"has no row in PROPOSALS.md"` stopped matching — they would have passed against a genuinely broken gate. v1.44.1 was merged on local evidence while GitHub Actions was down for several hours; the local proxy ran `lint-proposals` itself but not the step that asserts its *messages*, which is precisely the gap. Both now match the stable clause only. **Worth stating plainly: merging without CI had a real cost, and this was it.**
- **A malformed date parsed on macOS and was rejected on Linux, so a test passed locally and failed in CI.** `days_since` handed its input straight to `date(1)`: BSD `date -j -f` parses a leading date and ignores trailing garbage, GNU `date -d` does not. It now validates the shape first — a check whose answer depends on which `date(1)` is installed is not a check. (The malformed value came from a fixture using `printf %s` on a field carrying an escape; `%b` now.)
- Two CI assertions initially failed for arithmetic reasons rather than defects — after committing the fixture every page is age 0, so a `0` threshold cannot fire and the drained item is no longer queued. Corrected to assert the knob and the verb where each is actually observable.

## [1.44.1] — 2026-07-28

Patch — four defects in the v1.44.0 proposal queue, all found by **using it**: the first real consumer submission could not publish, the second carried the first's file, and merging one turned `main` red. Adopt with `bin/adopt.sh` or `update.sh`; no migration. Reported through the queue itself as `push-verb-omits-git-push` and `submit-branches-from-head-not-main`.

### Fixed
- **`push` never pushed the branch.** `do_push` called `gh pr create --head <branch>` without a preceding `git push`, so the head ref did not exist and GitHub rejected it — *"Head sha can't be blank … No commits between main and proposal/<slug>"*. `gh` pushes a current branch in some invocations but **not** when the target repo is pinned with `--repo`. Found on the verb's first real use; nothing had ever exercised the publish half, because the CI fixture deliberately has no remote. The branch is now pushed first, and a failure *after* the push says so explicitly rather than repeating "nothing was published", which would be false at that point.
- **`submit` branched from `HEAD`, not `main`.** `submit` leaves its own branch checked out, so a second proposal was cut from the first one's branch and its pull request carried **both** files. It now branches from `origin/main` (falling back to `main`) and **prints the base it used** — the reporter noticed only because the discard hint named the wrong branch, so the base is now stated rather than inferred.
- **An arrival turned `main` red.** Merging a proposal PR *is* the arrival record by design — and it necessarily makes the generated `PROPOSALS.md` stale, which `lint-proposals.sh` treated as an error. So every arrival failed the build until someone regenerated by hand: **the remembered manual step the queue was built to remove, reappearing one layer down.** The trailer gate now resolves a citation against the **queue** (the source of truth), falling back to the table for a repo without one, and ledger drift is a **note**. The table is a rendering; failing the build for its staleness punishes the merge that records arrival.

### Notes
- **Also folded in from the untagged `[Unreleased]` entry (CI only): a queue assertion was coupled to the repo's own contents and went red with no code change.** It grepped the live queue for the drain instructions, which `queue` prints only when something is open — and the commit immediately after recorded that proposal's outcome, draining the queue. Green to red on ordinary work. Re-pointed at a **fixture** queue, and widened while there: an open proposal is listed, a resolved one is hidden without `--all` and revealed with it, a drained queue says so, and drain instructions are **not** printed when there is nothing to drain. An assertion whose truth depends on ordinary repo state is not testing the code.
- **A fourth, found while draining: the soft-wrap gate rejected the incoming proposal files themselves.** They are consumer-authored payloads written in someone else's vault, so the submitter has no reason to know this repo's wrap convention — and applying it made every arrival redden `main` for a rule that should not govern incoming content. `proposals/` is now excluded from that gate. Exactly the ledger-staleness shape again: **the merge that records arrival must not be the thing that breaks the build.**
- **All three are seam defects**, the shape distilled the day before: each component behaved as written, and the failures lived in `submit`→`submit`, `push`→`gh`, and merge→lint. None was reachable by reviewing a single part.
- **The consumer-side reports were unusually good and are worth the pattern**: each reproduced at the pinned version, named the mechanism rather than the symptom, and *independently verified the tool's own claim* — `git ls-remote` confirmed the "nothing was published" abort was truthful rather than taking it at face value.
- **Self-inflicted, recorded rather than buried:** a `git reset --hard` used to drop a scratch commit also discarded all three uncommitted fixes, and a second stray `--hard` dropped a ledger commit from the branch (its content survived in the next commit; `origin/main` was unaffected). Nothing was lost, but the habit is wrong — commit or stash before resetting, and the repo has prior history with exactly this.

## [1.44.0] — 2026-07-28

Minor — proposals become **files in a versioned queue directory**, submitted by pull request, replacing the copy-paste channel. Adopt with `bin/adopt.sh` or `update.sh`; the existing ledger migrates automatically and every recorded slug resolves identically before and after. Reported through `engine-proposal` as `engine-proposal-file-queue`.

### Added
- **`proposals/<slug>.md` — the queue, and the source of truth.** The filename is the correlation key. Frontmatter carries only what git cannot answer: `outcome:` (`open` | `accepted` | `partially-accepted` | `rejected` | `alias`), `received:`, `reason:` (required for a decline), `alias:`. **`shipped` stays derived** from `git tag --contains` on the trailer commit — the release does not exist when the trailer is written, and this engine already rejected storing it once.
- **`submit` and `push`, deliberately two verbs.** `submit` runs the fail-closed boundary scan first, prepares a branch locally, and prints the exact text that will become public; `push` performs the irreversible act and forks on demand for a consumer without write access.
- **`bin/gen-proposals-ledger.sh`** renders `PROPOSALS.md` from the queue between sentinels, and `lint-proposals.sh` gained a drift check so a hand-edit is caught at pre-commit rather than in review.
- **`bin/engine-proposal.sh queue`** — the **engine-dev work-list**: open proposals oldest-first (`--all` for resolved), with the drain procedure printed beside the list. It is the one subcommand that does not take `--vault`, because it runs in the engine repo. Added during review when the question "can an engine-dev session actually process this queue?" turned out to have the answer *no*: every verb was consumer-oriented, so draining meant `ls` plus grep — the storage format existed but the work-list the proposal asked for did not.
- **`status` distinguishes three local states** — never written, written-locally, submitted-pending — from local evidence alone.

### Changed
- **`outcome` and `shipped` are now orthogonal.** The old single-column table could say only one, so a proposal that was *partially accepted* and *shipped* had to pick. `project-summary-volatility-gate` is exactly that case and is now recorded as both.

### Notes — what the intake review changed
The transport diagnosis was right and is kept whole. Four decisions were changed before building.

- **`submit` does not push.** The proposal specified scan → branch → commit → open PR as one verb. But the repo is **public** (verified, not assumed), and the scan matches only *derived* identifiers — it cannot see **semantic** leakage, where a private workflow is described in generic-sounding prose. Copy-paste was doing unglamorous safety work: a human necessarily read the text at the moment of publication. Automating end-to-end would have deleted the only review of *meaning* while claiming to improve safety. Splitting the verbs keeps that review without restoring the clipboard.
- **Acceptance criterion 4 had no mechanism.** "Written locally" vs "submitted" cannot be distinguished by a tool that is offline by design — `status` resolves against `origin/main` only when something already fetched it, and an open-but-unmerged PR is in neither the pin nor `origin/main`. Now derived from local markers written at prepare and push time, with the per-machine limitation stated in the output rather than left to imply "nothing outstanding".
- **The banner return path was dropped as specified.** `session-boot.sh` and `session-preflight.sh` make **zero** network calls, so a nudge would report stale outcomes indefinitely on a machine that never runs `update.sh` — observed live the same day, where a shipped proposal read `unknown` until an explicit fetch. Outcomes arrive at **pin-bump time** instead: honest, offline, and already a moment the operator is paying attention. A return channel that silently lags is this project's own failure mode relocated one layer down.
- **`PROPOSALS.md` is generated, not retired.** Retiring it in this change would also rewrite the `Proposal:` trailer contract, `lint-proposals.sh` (which hard-errors on a trailer with no row), and the CI job — including the literal-citation reading shipped hours earlier in v1.42.1. The objection to keeping it was *two sources that can disagree*; a generated file cannot disagree with what generated it. Retiring it is a separate, safe change once nothing reads it.

### Fixed in the same change — two contradictions the rewrite introduced
- **The skill told the engine dev to hand-edit a file this PR made generated.** §6 still said "append a row to `PROPOSALS.md`", which would now trip the drift check added here — the documented intake step would have failed the gate shipped alongside it. Intake now records the outcome in the proposal's own frontmatter and regenerates.
- **`stash` was still described as "required, not optional".** True when copy-paste was the only channel: a forward-only handoff that was not kept could not be re-sent. `submit` makes the block a committed file, so the durability the stash provided is now the transport's own property. Demoted to the fallback for a vault that cannot reach the engine repo.

### Notes — build
- **`received:` for migrated rows is the date the row entered the ledger, not necessarily the arrival date**, and the files say so. For three rows the release demonstrably predates it; the true date was never recorded, so it is stated rather than back-filled with a guess.
- **The generator emptied `PROPOSALS.md` on its first run** — `awk -v` cannot carry a multi-line string, and the failure was silent enough that `mv` installed the empty result. It now splices from a file and **refuses to write an empty ledger**, because a generator that empties its target has failed regardless of what awk's exit status said.
- **A CI assertion was testing the fixture's limits, not the code**: it required a *derived* release to resolve inside a fixture engine that has no `Proposal:` trailers in history. Re-pointed at a back-filled row, which resolves without trailers. Same family as the v1.43.0 fixture note.
- The step's `sed -i` was GNU-only. Made portable so the step can still be extracted and run on a workstation, which is how several real defects surfaced this week.

## [1.43.0] — 2026-07-28

Minor — a project page's one-line index hook must now name **identity** rather than current state, enforced by a deterministic gate through a content-hashed ratchet. Adopt with `bin/adopt.sh` or `update.sh`; adoption seeds a baseline so an existing vault goes green rather than red. Reported through `engine-proposal` as `project-summary-volatility-gate`.

*(First clause deliberately avoids an inline `summary:` token — `release.yml` cuts the release title at the first `.`, `;` or `:` followed by whitespace, so a colon inside a code span truncates it. Queued as `release-title-splitter-cuts-inside-code-spans`; this is the workaround until that ships.)*

### Added
- **`SCHEMA.md`: `summary:` names identity, not state.** The Projects buckets are generated from `status:`/`summary:`, so `summary:` is the machine-read surface of a project page — yet it lives in frontmatter, away from the `Current state` section SCHEMA already marks "overwritten each session". Authors fill it with current standing ("built, not deployed", "still on v1.2"), which goes **false through the passage of time with no edit to the page at all**; the generated index then advertises a state the page's own body contradicts, and every existing gate passes because every existing gate is structurally sound. It is also duplication — the index already renders standing as the bucket heading. **This is the part that retires the class:** a summary naming no decaying fact cannot decay.
- **`bin/lint-summary-volatility.sh`**, wired as `lint.sh` section 8. Marker list (versions, dates, fractions, state verbs), **status-gated**: a `done` project's claim is frozen and warning about it is pure false positive, while the same claim on active/paused/planned decays.
- **`adopt.d/60-seed-summary-baseline.sh`** — seeds the ratchet once, so a vault adopts green. Strictly add-only: if a baseline exists the step does nothing, because re-seeding would silently re-grandfather violations introduced *after* adoption, turning the ratchet into a rubber stamp.
- **`scaffold/summary-volatility-markers.txt`** plus two `.wiki-gates.conf` keys — `summary_volatility_markers` (override the list) and `summary_baseline` (relocate the ratchet).

### Changed
- **`SCHEMA.md` settles the `status:` enum at `planned|active|paused|done`.** It documented three values while `gen-projects-index.sh` has always rendered a fourth `planned` bucket. A gate keyed on "not `done`" would have inherited that ambiguity.

### Notes — what the intake review changed
The proposal arrived well-formed and its diagnosis was right; three of its specified decisions were still overturned before anything was built.

- **Enforced, not warn-by-default — the proposal's central mechanism, inverted.** It specified warning so existing vaults would not fail lint on adoption. But `lint.sh` is the pre-commit gate *and* CI, so a warn on pre-existing offenders prints on **every commit forever** — the standing-noise failure this engine has now fixed repeatedly, and a direct contradiction of holding gates at zero. The **ratchet** dissolves the trade-off the proposal was navigating: grandfather today's offenders, error on anything new. Its acceptance criterion "exits 0 on a vault with pre-existing offenders *without the strict flag*" was therefore rewritten, not satisfied — the criterion encoded the decision being overturned.
- **The baseline keys on `sha256(summary)`, not the page slug.** The proposal proposed a slug allowlist on the precedent of the external-refs file — but that allowlists *link targets*, which are stable. A slug-keyed exemption outlives the text it excused: rewrite the summary into something genuinely decaying and the page stays exempt forever. Hashing makes the ratchet one-way, and CI asserts both halves (a rewritten summary loses its exemption; an untouched one keeps it).
- **The bare marker `live` was dropped, because the reported precision did not reproduce.** The proposal measured "26 project pages, 5 status-gated hits, all 5 genuine". The vault available here has **23** pages and yields **2**, and *both are false positives* — `live` used adjectivally ("a **live** artifact IS the work queue", "first **live** candidate"). Different sample or different regex; either way the precision claim was re-derived locally rather than inherited, and `live` now requires a state phrase. The marker list also became **data** with a per-vault override, since which words are volatile is a property of how a vault writes, not of the engine.
- **An unknown or missing `status:` flags rather than skips** — fail closed, so `status: activo` cannot buy a silent exemption. Not raised in the proposal.
- **The gate says what it is not.** It detects volatile *vocabulary*, not staleness; recall is unbounded ("awaiting the lender's callback" decays as hard and matches nothing). Both SCHEMA and the gate's own success output state that a clean run means "no listed marker", never "these summaries are stable" — a green proxy must not read as a proof.
- **The pre-push diff review caught one thing the design pass could not.** `--seed-baseline` on an already-clean vault wrote a baseline containing zero entries, while the adoption step carried its own separate cleanliness test to avoid exactly that. Two places deciding one thing is how they drift — and worse, the empty file would make a later seed look already-run to the add-only adoption step. The decision now lives once, in the tool: nothing to grandfather, no file written.
- **Kept from the proposal as correct:** the identity/state split itself, the status gate (it cut the candidate set 13 → 2 on the measured vault), and the rejection of an LLM-judged consistency check on the grounds that the lint layer is deliberately deterministic and offline — CI asserts this gate runs with network tools disabled and references no model.

## [1.42.1] — 2026-07-28

Patch — the `Proposal:` citation convention required a placement that the project's own workflow made impossible, so following the instructions produced a state CI rejected. Placement is no longer required. Adopt with `bin/adopt.sh` or `update.sh`; no migration. Closes [#60](https://github.com/pleejr/wiki-engine/issues/60).

### Fixed
- **A citation is now read wherever it appears, instead of only in the final paragraph.** The convention was `Proposal: <slug>` in the commit's last block, so git's trailer parser would see it — and for a squashed merge, that meant the **pull request description's** final paragraph. But GitHub appends its own `---------` + `Co-authored-by:` footer to the squash body, which then *becomes* the last block. The slug the author put last stops being last, `%(trailers:key=Proposal)` returns nothing, and `lint-proposals.sh` hard-fails.
  - **The instruction and the check disagreed, and GitHub decided the outcome.** This is not an edge case: it fires on every PR whose body ends as the skill instructs. v1.42.0 hit it, and `main` went red on merge.
  - **Detected at the worst possible moment.** The failure is only visible *after* the squash, when the sole remedy is amending the tip of a published branch and force-pushing. v1.42.0 required exactly that.
  - **Placement was never what the slug is for.** It is a correlation key; git-parseability bought nothing except compatibility with `%(trailers)` — an implementation detail of the two scripts this repo owns. `bin/lint-proposals.sh` and `bin/engine-proposal.sh status` now both read the literal line, and are kept in step deliberately: if only one had changed, a shipped proposal would read as `unknown` to the reporter.
  - The old placement error has nothing left to protect — an unparsed line is no longer read as untagged — so it is now a **note**, not a failure. It still tells you `git log --format='%(trailers:key=Proposal)'` will not show what lint found.
- **Quoted examples are skipped rather than rejected.** Under the old count-mismatch scheme, a commit quoting the convention at column 0 tripped a loud error, fixable by indenting. Reading literally would instead have *silently credited* the quote as a real citation, so quote-handling had to move from "error out" to "don't look there": lines inside a ``` fence are ignored by both scripts. CI asserts both directions — a fenced slug with no ledger row must not fail lint, and **the same slug unfenced must still fail**, so the skip cannot quietly widen into swallowing real citations.

### Notes
- **The regression test carries its own fixture guard.** It asserts that git genuinely *cannot* parse the constructed footer shape before asserting that lint can — otherwise a fixture that accidentally kept the trailer parseable would pass while proving nothing. Same class as the v1.42.0 fixture that created the capture file fresh and erased the condition under test.
- Two earlier rows shipped `derived` before this surfaced, so the convention had been holding on the shape of those particular PR bodies rather than on anything guaranteed.

## [1.42.0] — 2026-07-28

Minor — the SessionEnd capture hook and the concurrency guard were each correct and jointly deadlocked the vault's most-travelled path: every session ended by dirtying canonical, and the next session's `integrate` refused. Fixed at both the cause and the over-breadth. Adopt with `bin/adopt.sh` or `update.sh`; existing vaults need the one-line migration under **Migration**.

### Fixed
- **`rag-capture.sh`'s buffer no longer dirties canonical, because it is no longer tracked.** The hook runs at SessionEnd and appends to `raw/sessions/YYYY-MM.md` in the **canonical** checkout — necessarily, since by SessionEnd the session's worktree has already been `gc`'d, so there is nowhere else to write. That file was tracked, so **every session that ended left canonical dirty**, and the next session's `integrate` hit the categorical `status --porcelain -uno` check and refused — while `guard` refused the commit that would clear it. Two correct guards, jointly a deadlock.
  - **Untracking is right on content grounds, independent of the deadlock**, which is why it was preferred over having the hook commit itself. The blocks hold this machine's **absolute transcript paths** and local repo HEADs — meaningless on another machine, and a mild boundary smell in a synced repo. `SCHEMA.md` already called the buffer disposable per-machine scratch; tracking it contradicted that.
  - Both consumers already read it from `$WIKI_PATH` (canonical), not from a worktree — `checkpoint` §2/§3 and `wiki-context`'s review-and-promote step — so nothing needed it in git. `raw/sessions/.gitkeep` stays tracked, so the node folder still ships.
  - Propagates to existing vaults through the add-only `adopt.d/40-vault-gitignore.sh` reconciler; no new adoption step.
- **`integrate`'s canonical dirty-check is now path-precise instead of categorical.** It refused on *any* tracked modification anywhere in canonical, which is strictly broader than the danger: a fast-forward can only clobber an uncommitted edit to a path it actually **changes**. The check now runs after the rebase — the first point where `main..branch` is exact — and refuses only on the intersection, **naming the offending files** instead of git's generic message.
  - **Narrower is not less safe here**: `git merge --ff-only` refuses to overwrite a locally-modified file on its own, and still runs immediately after. Git keeps the veto; this check exists to fail earlier and more legibly.
  - **This is the half that rescues already-tracked buffers.** Gitignore does not untrack an existing file, so every vault that adopts this still has a tracked buffer until it runs the migration — and path-precision is what keeps those vaults working in the meantime.
  - Same failure the `-uno` flag was introduced to fix for **untracked** files, one notch deeper: a check that is always red is a check that gets bypassed. The engine's own hook was what guaranteed the tracked half would be red too.

### Migration
Existing vaults carry the buffer as a tracked file. One line, from the vault root, retires it without deleting anything on disk:

```sh
git rm --cached --quiet raw/sessions/*.md && git commit -m "untrack the per-machine capture buffer"
```

Deliberately **not** automated: `adopt.d/` steps are add-only and must never remove or rewrite what a vault tracks. Skipping it is safe — path-precise `integrate` handles a tracked buffer — it just leaves canonical permanently dirty in `git status`.

### Notes
- **Found by running `checkpoint`, not by inspection** — the second consecutive release whose defect surfaced that way (see v1.41.0). The ritual is the only thing that exercises `ensure` → `integrate` → `gc` against a vault that has actually had sessions end on it.
- **The narrowing is a deliberate contract change, and CI asserted the old one.** The concurrency-model step required `integrate` to refuse a tracked modification in canonical — with a fixture whose dirty path (`notes/seed.md`) was *not* one the fast-forward touched, so it was asserting the over-breadth itself. Updated to the precise contract, and split so the assertion cannot be weakened by accident: non-overlapping dirt must proceed **and leave the edit intact**; overlapping dirt must still refuse **and still not clobber**.
- **My own new test aborted under `bash -e` and would have silently skipped its last checks.** CI runs steps with `-e`, where `out="$(cmd)"; rc=$?` aborts on the expected non-zero before the status can be read; verifying locally under a plain `bash` hid it, because the harness was *more permissive* than production. The existing step already carried a comment warning about exactly this. Fixed to `|| rc=$?` and re-verified under `-e`. Third distinct instance this release of a check that could not fail.
- **The first regression fixture was wrong in the way the engine keeps rediscovering.** It let the hook create the monthly file fresh — which is **untracked**, invisible to `-uno` — so the deadlock could not reproduce and the test passed against the bug. Split into two fixtures: a fresh vault (buffer must be untracked *and* ignored) and a legacy vault with the buffer pre-committed (the reported case). Another instance for the consumer-side `tests-inherit-the-design-blind-spot` note.
- **One claim in the incoming report was rejected on reproduction.** It flagged that the refusal "leaves the index staged" as a secondary defect of `guard`. It is not: the caller's own `git add` staged the file, and every failed pre-commit hook leaves the index as the caller left it. `guard` mutates nothing.
- The report also said there was **no sanctioned exit**. Overstated — `git stash` was always available and the refusal message named it. The real defect was the over-breadth, not the absence of an escape.
- Reported through `engine-proposal` from the consumer side of this machine's own vault.

## [1.41.0] — 2026-07-27

Patch-shaped — `gc` could never reap a `wt/*` branch whose worktree was already gone, because a branch was only ever evaluated as a *side effect* of retiring its worktree. Third route to the same unbounded accumulation. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **An orphan `wt/*` branch was unreapable by any invocation.** Branch deletion lived inside `retire_worktree`, so it ran only when a worktree was being retired; the bare `gc` sweep looks for stale *worktrees* and therefore never reached a branch whose worktree had already been removed — by a crashed session, or by `git worktree remove` called directly. Such a branch accumulated forever, which is the same growth v1.28.2 and v1.38.0 were each cut to stop, arrived at by a third route.
  - **Found in the wild, not by inspection**: retiring this session's own worktree left one behind that was provably contained by **both** the ancestry and the v1.38.0 content test, held zero commits ahead of `main`, and still had to be deleted by hand.
  - The containment logic is now `retire_branch`, called by **both** paths — so the worktree route and the sweep can no longer disagree about what "contained" means, and a future change to one is a change to both.
  - **A branch checked out anywhere is excluded by decision, not by accident.** It belongs to a live session (or to canonical). `git branch -D` would refuse regardless, but relying on that would make the skip incidental; CI asserts the *assessed* count excludes it rather than only checking the outcome.
  - Fail-safe direction unchanged throughout: an orphan holding real work is kept, named as `UNINTEGRATED CONTENT`, and asserted still readable afterwards.

### Notes
- Found while running `checkpoint` — the ritual exercised `ensure` → `integrate` → `gc` and surfaced a gap that no test covered because no test had ever left a branch without its worktree.

## [1.40.0] — 2026-07-27

Minor — a new **`upkeep sync-clones`** verb: a guarded, fast-forward-only clone refresh, so a drain reflects true upstream instead of whatever the local clones happen to be at. The detector stays offline. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/upkeep.sh sync-clones [--check]`.** `upkeep scan` and `verify-status` measure freshness against the **local clone's HEAD** — offline and deterministic by design, and that design is right. But it means a drain is only as current as the clones on that machine: when a clone lags, the drain refreshes the page and stamps `verified:` against a sha behind the real release.
  - **The asymmetry is what makes this worth engine support rather than a documented habit.** A lagging clone produces a **false negative** — the page looks verified and current, so nothing flags it. The failure is invisible in exactly the output that exists to surface staleness, and the cost is a second full drain once someone notices, because the first has written a misleading signal the second must overwrite.
  - **Conservative by construction: every state is decided before anything is touched.** Only a proven fast-forward is applied — `git merge --ff-only` runs solely after `merge-base --is-ancestor` has already established the case. No force, no stash, no rebase. **`git pull` is deliberately not used**: it consults `pull.rebase` and friends, so what it actually did would depend on the operator's config rather than on this code. CI asserts the absence of all four **at the command level**, by reading the verb's own source, not merely by observing outcomes.
  - **A skip is a reported outcome, not an error.** A dirty tree, a detached HEAD, a branch tracking no upstream, a diverged branch, and a failed fetch are each named in the output. Silence about a clone the tool refuses to touch would recreate the original bug one level up, with the operator again believing everything was current.
  - **The vault's own checkout is never pulled** — a point the proposal did not raise. A vault that documents itself has one page whose clone *is* the tree a session is working in, possibly with a live worktree holding uncommitted work; pulling it from underneath is the exact hazard the concurrency model exists to prevent, and no freshness benefit could justify it. Matched by physical path, as `scan`'s self-page suppression already does.
  - **It stays a separate, deliberate step, and the detector stays offline.** Folding a fetch into a "just tell me what is stale" command would trade away the determinism that lets `scan` run anywhere — including with no network, and on intentionally pinned clones — and would add latency and failure modes to a read-only-sounding verb. CI proves it by running `scan` and `verify-status` under a `git` that dies on any network verb.

### Notes
- **`--check` is deliberately hedged.** It reports what it *would attempt*, not what would happen: divergence is only knowable after a fetch, so promising the fast-forward would be a claim `--check` cannot make without doing the thing it exists to avoid.
- **This block was a reconstruction, and was weighted as one.** The original was handed off ~2026-07-24 before `stash` was mandatory; no copy survived, and it was rebuilt from a consumer lesson note covering the same ground. The reporter flagged that explicitly rather than passing it off as the original. The underlying gap — `stash` being optional — was closed in v1.34.0, so this failure mode does not recur.
- Second consecutive proposal whose original never arrived; both were re-sent only because v1.34.0's `status` could distinguish "unknown" from "queued". This one closes the six-block backlog that discovery produced.
- Reported upstream from a consumer vault through `engine-proposal`.

## [1.39.0] — 2026-07-27

Minor — `upkeep`'s tag-aware detector compared a page's recorded `ref` against the clone's **clean** tag, while ingest commonly recorded the full `git describe` form. Those can never be equal, so every such page was flagged stale forever and the one genuinely-stale page was buried among them. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **A `git describe` ref false-flagged a repo page for refresh, permanently.** SCHEMA's convention is `ref: <latest release tag>` and nothing enforced it, so pages commonly carried `vX.Y.Z-<N>-g<sha>`. `upkeep scan` compares against `git describe --tags --abbrev=0`, which the describe form never equals — reported by a consumer as **29 false refresh items out of 30**, with exactly one genuine drift. A queue whose real item is one line in thirty is not a queue anyone drains: the same "a signal that always fires stops being read" failure as the always-kept `gc` branch (v1.38.0) and the always-red `integrate` check.
  - The detector now normalises a recorded ref to its base tag before comparing. **Nothing is lost by normalising**: the commit offset and sha the suffix encodes are already carried by `sources.sha`, and the two staleness axes stay independent — `refresh` compares provenance to the clone, `verify` compares `verified.against` to `sources.sha`.

### Added
- **`lint.sh` — `repo ref is a clean tag`.** Prevents ingest from reintroducing the form. **Deliberately a negative check**: asserting a ref *is* a clean tag is not something lint can do, because tags are arbitrary strings (`stable`, `release-2024-01`) and the only real test is "does this tag exist in the clone?" — which would make a write-time gate depend on every documented repo being cloned at a particular path on whatever machine is committing. A gate that cannot run everywhere gets loosened until it cannot fail. Rejecting the describe *form* needs no clone and cannot false-positive on a legitimate tag.
- **`adopt.d/50-normalize-repo-refs.sh`, and it ships WITH the gate rather than after it.** The engine's gates are held **at zero**; shipping enforcement alone would have violated that on arrival, handing every affected vault a backlog it did not create, could not commit past, and had no tool to clear. The incoming proposal sequenced tolerance first and enforcement second for this reason — but sequencing does not fix it, because the tolerance makes the refs harmless, which is exactly why nobody would ever rewrite them. Narrow (only a trailing `-<N>-g<hex>`, only on a `ref:` line in `repos/`), reversible, idempotent, and `sha:` is untouched. Precedented, not novel: `update.sh` already rewrites the engine page's provenance and leaves it for review; adoption never commits into a consumer's vault.

### Changed
- **`wiki-repo` and `SCHEMA.md` now say which command to use** — `git describe --tags --abbrev=0`, not `git describe --tags` — and why, so the convention is stated where it is acted on rather than only where it is defined.

### Notes
- **This proposal was originally handed off ~2026-07-24 and never arrived.** The consumer recorded it as "handed off, engine-dev owns it" and waited three days on nothing. It was re-sent after v1.34.0's `engine-proposal.sh status` reported the slug as **`unknown` — no row in the engine ledger**, which under that convention means the engine has no record of receiving it. First real use of the round-trip, and the first case where "handed off" and "never arrived" were separable at all — the exact ambiguity `proposal-slug-roundtrip` was built to remove. Its arrival row here was written before any code was.
- The reporter's 29:1 measurement does **not** reproduce on the reference vault, whose four repo pages carry clean refs — the defect is real by mechanism and confirmed on a fixture, but the ratio is a property of how a given vault's pages were ingested.
- CI pins that the fix is not merely a mute button: a page genuinely behind the latest tag is asserted **still flagged**, before and after migration.
- Reported upstream from a consumer vault through `engine-proposal`.

## [1.38.0] — 2026-07-27

Minor — `gc` judged branch containment by **ancestry**, which is only equivalent to "merged" for the fast-forward `integrate` performs. A vault whose workflow is branch → PR → **squash-merge** therefore accumulated `wt/*` branches forever, and the "delete by hand" line fired on every session until it stopped being read. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`gc` never reaped a squash-merged session branch.** `merge-base --is-ancestor <branch> <main>` asks the right question only if the branch reached `main` by fast-forward. A squash-merge lands the work as a **new commit with a different sha**, so the branch tip is not an ancestor, and `gc` kept it — reported across **seven** consecutive worktree cycles in one session, each needing a manual diff-and-delete. Exactly the unbounded accumulation v1.28.2 was cut to stop.
  - **When ancestry says no, `gc` now asks a content question**: does merging this branch into `main` *change* `main`? If the merge result tree **is** `main`'s own tree, the branch contributes nothing and is contained however it got there. `git merge-tree --write-tree`, no working tree touched.
  - **v1.28.2 made the question right; this makes it the right question.** That release fixed containment being judged against the *upstream* rather than local `main`. This is the adjacent case: containment judged by *ancestry* rather than by content.
- **The genuinely stranded branch was worded identically to the noise.** On the same run, `gc` also surfaced a real unintegrated branch holding a session's stranded checkpoint — a correct and valuable keep, indistinguishable in the output from dozens of false ones. Keeps are now three distinct reports: `deleted … (already contained)`, `deleted … (content already in main — squash-merged or equivalent)`, `kept … — UNINTEGRATED CONTENT (N file(s) not in main)`, and `kept … — could not determine containment`.

### Notes
- **The fail-safe asymmetry is preserved, deliberately and by construction.** Deleting an unmerged branch costs work; keeping a merged one costs a stale ref. Only an *exact* match against `main`'s own tree deletes, so anything the branch still adds keeps it. A conflicting merge still writes a tree, which differs from `main`'s and so reports as unintegrated — correct, since a branch that conflicts does hold content `main` lacks. A git older than 2.38 writes no tree and reports "could not determine". **Every uncertain path keeps.**
- **Letting the vault declare its integration style through the config seam was rejected.** Inferring by content is strictly better: it needs no configuration, cannot be set wrong, and is correct for a vault that uses both styles — which is the normal case, since `integrate` fast-forwards locally while the same vault's pull requests squash.
- **CI pins all four arms, including the two that must not change.** The fast-forward path is asserted still reaped *and* the fixture asserts `integrate` actually fast-forwarded first — without that, the test proves nothing, which is how the first version of it passed while `integrate` had silently no-opped. The stranded branch is asserted both kept *and* still readable, and the old-git path is asserted to keep rather than guess.
- Reported upstream from a consumer vault through `engine-proposal` as a defect report, strengthened by the reporter from "observed once" to a counted seven-cycle recurrence before sending — which is what moved it from an anecdote to a per-session tax.

## [1.37.0] — 2026-07-27

Minor — adoption never reconciled an existing vault's `.gitignore`, and the template omitted three artifacts the engine itself creates. A vault got **dirtier the more of the engine it adopted**, and one missing entry carried a safety property outright. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`scaffold/gitignore.tmpl` was scaffold-only — nothing ever revisited it.** It is applied once, by `new-wiki.sh`; `adopt.d/` had steps for the boot hook, the skill links and the git hooks, but none for `.gitignore`. So every entry added to the template after a vault was scaffolded never reached that vault, and the artifact the entry exists to hide stayed untracked forever.
- **The template omitted three paths the engine creates**, so a **freshly scaffolded and adopted vault started dirty** — reproduced: `?? .engine-adopted` and `?? .githooks/` on a brand-new vault.
  - **`.engine-adopted`** — `apply-adopt.sh`'s own header has always described this file as "per-machine, **gitignored**". The engine asserted a property that nothing provided: the belief was written down, only the mechanism was missing. Committing it publishes one machine's adoption state to every other machine, where the fast path would then read a marker describing a different checkout.
  - **`.githooks/`** — now ignored, **and the template states why**, because this is a genuine decision rather than an oversight and leaving it unstated meant each vault resolved it by accident. Installation stays per-machine and add-only; a vault that tracked its hook would keep whatever template it first adopted, forever, with no upgrade path. Gate *correctness* does not depend on it either way — that is exactly what v1.35.0's absolute `core.hooksPath` bought.
  - **`.worktrees/`** — was hidden only via `.git/info/exclude`, which is per-checkout and **never cloned**, and only written on first use of a worktree verb. So a second machine's clone showed it untracked until that machine happened to run one. The exclude write is kept as a belt for vaults that have not yet reconciled.

### Added
- **`adopt.d/40-vault-gitignore.sh` — add-only `.gitignore` reconciliation.** Appends the entries a vault is missing, **carrying each entry's explanatory comment across** (the reason an entry exists is the part a reader needs — `.wiki-gates.local`'s comment *is* its safety rationale). Never reorders, never removes, never rewrites an entry the vault added itself: a `.gitignore` is the vault's file and adoption may only append. Matching is on **normalized** entry text, so a vault already ignoring `.upkeep` is not handed a `.upkeep/` next to it.
- **`adopt.sh` now says that node folders must be committed.** They are the one thing adoption creates that is *vault content* — everything else it writes is per-machine and ignored — so their `.gitkeep` files otherwise sit untracked indefinitely. It also names the specific trap, because `git commit -am` does not stage them.

### Notes
- **Why this is not cosmetic, in the engine's own terms.** A check that is always red is one that gets bypassed — stated here when fixing the always-dirty `integrate` and the always-passing adoption guard. A `git status` that permanently lists engine artifacts is that same failure at the human layer: it trains the operator to skim untracked paths. **That is not hypothetical, and it happened while this was being built** — standing noise from adopt-created `.gitkeep` files hid three uncommitted pages that `git commit -am` had silently not staged, in a vault whose index already referenced them.
- **One entry is a safety property, not tidiness.** `.wiki-gates.local` names the *other* boundary's identifiers; a vault that adopts the foreign-boundary gate without receiving that ignore line is one `git add -A` away from committing precisely what the gate exists to keep out. That property was carried entirely by a file the vault never received.
- **The `.githooks/` question was the shared hinge with v1.35.0, and it was settled there**: tracking it is not a repair the engine can perform, since adoption never commits into a consumer vault, so it would have fixed newly scaffolded vaults while leaving every existing one broken. Both releases fall out of that one decision rather than resolving it twice.
- The end-to-end assertion is the one that would have caught the whole class: **a freshly scaffolded and adopted vault must have a clean `git status`.**
- Reported upstream from a consumer vault through `engine-proposal` as a defect report.

## [1.36.0] — 2026-07-27

Minor — the engine named a **specific boundary value** in four places, including a copy-me frontmatter template and one line of executable code, contradicting `SCHEMA.md`'s own boundary-agnosticism rule. A page mis-stamped as a result passed every gate and then vanished from semantic recall with no message. Adds the gate that was missing and a check so the class cannot return. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **Four sites named a boundary the engine cannot know.** `SCHEMA.md` states that each consuming wiki declares its own boundary and the engine is boundary-agnostic; `skills/checkpoint` and `skills/wiki-repo` asserted a literal in their Rules, `wiki-repo` also put one **inside the frontmatter template it tells the model to write into every new repo page**, and `skills/crossover` described the behaviour in prose. All four now defer to the vault's declaration.
  - **The template was the dangerous one.** The prose is something a reader can weigh against the vault's own `CLAUDE.md`; a copy-me block reads as "reproduce this verbatim". Whether a vault got correctly-stamped pages rested on the model noticing that the skill and the vault disagreed, and choosing the vault every time — a judgement call standing in for a guarantee.
- **`bin/crossover.sh` rewrote every imported page to a hardcoded literal** — `sed … /\1personal/`. Found by the systematic sweep the report asked for rather than in the report itself, and materially worse than the three known sites, because it is *executable code*: importing into a vault on any other boundary stamped every page with a value that vault does not use. Now asks the destination (`vault-boundary.sh`) and rewrites to **its** declared value; a destination with no parseable declaration has the tag **left alone** rather than guessed at, since fabricating one is precisely how the original did its damage.

### Added
- **`bin/lint.sh` — the boundary-MATCH gate, and it is the more valuable half.** The existing gate asked whether a page carries a `boundary:` field; nothing ever asked whether it is *right*. The consequence chain was silent at every step: a mis-stamped page passes boundary-present, passes the foreign-boundary gate (which reads EREs, not this field), gets committed and indexed — and is then dropped from recall by `rag-build`'s cross-boundary skip, which is correct behaviour there. The page simply stops answering and nothing says why. A write-time error turns an invisible failure into an obvious one, and covers mis-stamps from **any** source, not just the templates. Reports `not armed` when the vault declares nothing, rather than passing silently.
- **`bin/vault-boundary.sh`** — the one place that answers "what boundary does this vault declare?", so the rule is not re-implemented three subtly different ways. **Accepts any well-formed token, deliberately not a fixed pair**: matching against a hardcoded `(personal, work)` is exactly what made `rag-build`'s filter fail *open* on a vault using a third value.
- **`bin/lint-docs.sh` — a mechanical check that no shipped skill or tool stamps a boundary literal.** This defect was found by reading one line; nothing could have caught it, so the search had never been done systematically. Deliberately narrow — it matches the *stamping* form only, so the scaffolder's `--boundary personal|work` enum, prose enumerating the choice, the `{{BOUNDARY}}` placeholder and the handoff block's own `generic` marker all keep passing. A broader rule would flag every one of those or be loosened until it could never fail, which is the same defect class facing the other way.

### Changed
- **`rag-build.sh` reports the cross-boundary filter always, including zero.** The skip is right; its silence is what hid this. Three states have to be distinguishable and only one of them used to print: a steady nonzero is normal for a vault legitimately holding foreign pages, a newly nonzero one on a vault that should hold none is the signal, and **"not armed" must never look like "armed and clean"**.

### Notes
- **Reported as latent, not observed, and that is the reason to fix it.** On the reference vault all content-node pages carried the vault's declared value. The mechanism preventing the failure was a model resolving a contradiction correctly on every single page, and the failure it prevents reports nothing when it occurs — a guard that works by luck reads identically to one that works by design.
- **Load-bearing proven by reinstatement**, as with the previous two releases: the literal is put back at each of the three sites that carried it and `lint-docs.sh` must go red for each. The boundary-match gate is asserted in both directions on a vault whose declared boundary is **not** the value the templates used to name — the case that would actually have broken.
- The reporter noted the awkward interaction with v1.34.0: `PROPOSALS.md` documents that a proposal slug must never be namespaced by consumer, for the same boundary-agnosticism reason these lines violated. Stating a rule in one place while contradicting it in another is what made the sweep worth doing rather than patching the three known sites.
- Reported upstream from a consumer vault through `engine-proposal` as a defect report.

## [1.35.0] — 2026-07-27

Patch-shaped but minor by impact — the vault's write-time gate was **inert in every linked worktree**, which is the only place the workflow permits commits. Third instance of the same class; this release fixes the instance and adds the test that would have caught all three. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`core.hooksPath` was relative, so the gate ran nowhere commits are actually made.** `adopt.d/30-vault-git-hooks.sh` wrote `core.hooksPath=.githooks`. Git resolves a relative hooks path against the working tree of the checkout making the commit, so inside a linked worktree it means `<worktree>/.githooks` — which does not exist, because `.githooks/` is created by adoption and **never committed** (the engine does not commit into a consumer's vault), so it lives only in the canonical checkout. Git reports a missing hooks directory as "no hooks" and commits without a word.
  - **The gate was present exactly where commits are FORBIDDEN and absent exactly where they are REQUIRED.** In the canonical checkout the hook was found and the concurrency guard correctly refused; in a worktree no hook was found, so neither the guard nor `lint.sh` ran. Every vault invariant — link integrity, the foreign-boundary gate — was skipped on precisely the commits the workflow tells you to make. Reproduced at v1.34.0 in both directions on a scaffolded vault.
  - **Fixed by writing an absolute path**, which resolves identically from every checkout. Machine-specificity costs nothing here: `core.hooksPath` is per-checkout local config that adoption re-derives on every machine anyway.
  - **Tracking `.githooks/` instead was rejected, and not on taste.** The engine cannot commit into a consumer's vault — adoption is deliberately a human gate — so tracking would fix newly scaffolded vaults while leaving every existing one broken forever. It is not a repair the engine is able to perform.
  - **Upgrade path, because the old value is set rather than absent.** Adoption previously wrote `core.hooksPath` only when *unset*; on an already-adopted vault it is set, to exactly the wrong value, so a naive fix would have repaired nothing. The step now rewrites the literal `.githooks` — provably the value this step itself used to write — and a stale absolute path that no longer resolves (the vault was moved or re-cloned, which disarms an absolute path the same way). A `hooksPath` aimed anywhere else is still never stolen.

### Added
- **`gate_wiring_status` in `bin/adopt-lib.sh` — assert EXECUTION, not installation.** Installing a hook and pointing config at it are two claims; whether a commit is actually gated is a third, and it is the only one that matters. All three instances of this bug passed the first two while failing the third, and every reporting surface said "adopted". The helper resolves `core.hooksPath` the way git does, **per checkout** — asking each worktree separately, since that is where relative and absolute diverge — and reports `gate ARMED` / `gate INERT` per line. Adoption runs it after wiring and warns loudly if any checkout would commit ungated.

### Notes
- **The existing regression test could not see this, and its fixture is why — for the second time.** The v1.28.1 test's first version passed with the bug reinstated because the fixture created `engine/` as *tracked* content, so the worktree got a copy. This release's discovery is the same shape one layer up: the fixture also left `.githooks/` tracked, so a relative `hooksPath` resolved inside the worktree and the test stayed green for two releases while the shipped wiring was inert. The fixture now untracks both, which is what a real adopted vault looks like.
- **Load-bearing is proven, not asserted.** CI reinstates each of the three historical bugs in turn — relative `hooksPath` (this release), the hook resolving `engine/` from the worktree root (v1.28.1), and no hook installed at all (v1.32.0) — and requires a worktree commit to succeed ungated for each. A test for this class is worth nothing unless it goes red for the bugs that actually happened.
- **The hook's "engine not initialized — skipping" branch was left as `exit 0`,** against the reporter's suggestion. By the engine's own rule (`adopt-lib.sh`) a missing `engine/` is *consumer state* — a fresh clone before `submodule update --init` — not an engine asset, and blocking that clone's first commit offers no remedy discoverable from inside a hook. It was the branch that hid the v1.28.1 instance, but it hid it *in worktrees*, which this fix makes unreachable; the inertness class is now covered by a detector that can run at any time rather than by a branch that only fires once things are already broken.
- The sibling question of whether `.githooks/` should be tracked is answered here for the gate's purposes: **the gate's correctness must not depend on it either way.** That is what the absolute path buys.
- Reported upstream from a consumer vault through `engine-proposal` as a defect report; reproduced before any shape was chosen.

## [1.34.0] — 2026-07-27

Minor — a proposal's slug now **round-trips**: the engine records every arriving proposal in `PROPOSALS.md`, cites it as a `Proposal:` commit trailer when it ships, and `engine-proposal.sh status` answers "what happened to mine?" from the engine checkout alone. Closes the one outcome a consumer could never observe — a **decline**. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`PROPOSALS.md` — the round-trip ledger, written on ARRIVAL rather than at resolution.** Every handoff block already carried a `slug:` and nothing used it as a correlation key: zero slugs appear anywhere in this file's history, so releases credited *the channel* (`engine-proposal`, seven mentions) while never identifying *the proposal*. A consumer's only recourse was keyword-grepping this repo's commit subjects with guessed terms.
  - **The decline is the half that forced an engine-side artifact.** Intake records accepted and rejected findings in the engine-dev vault, which a consumer cannot read and must not need to; the only surface both ends share is this repository. So a proposal considered and declined looked identical, forever, to one nobody had started — "not in the CHANGELOG" — and the reporter's only rational behaviour was to keep re-sending it.
  - **Row on arrival, edit on resolution.** The incoming proposal put the ledger write at resolution, where a rejection has no branch, no commit, no trailer and no release — so the CI check it specified could never fire on the single case the whole feature exists for, leaving it to a human remembering. That is the discipline that already failed. Writing first also makes **`unknown` mean something**: no row = the engine never received it (re-send), which is a different instruction than `open` (received, in progress — don't).
  - Outcomes are `open` / `shipped` / `partially-accepted` / `rejected` / `alias`; a decline **must** carry its reason or lint rejects the row.
- **`Proposal: <slug>` commit trailer**, in the final paragraph beside `Co-authored-by:`. Prose gets reworded; a trailer is grep-stable and lands in *this* repo rather than only in the engine-dev vault.
- **`bin/lint-proposals.sh`**, and one check in it is the load-bearing one: **a `Proposal:` line that git's trailer parser cannot see is a HARD failure, not "no trailer".** Git parses trailers only in a message's last paragraph, so a line written mid-body yields nothing — reproduced: `%(trailers:key=Proposal,valueonly)` returns empty. CI would then demand no ledger row, pass, and the reporter would read `open` forever on a proposal that shipped. Fail-open and invisible from both ends. Grep-based detection has the opposite failure: a commit body already in this history contains `Verified: leaky block -> exit 1`, which is trailer-shaped prose.
  - Also: rows well-formed and unique, aliases resolvable and unchained, `shipped | derived` backed by a real trailer, an explicit `vX.Y.Z` naming a real tag.
  - **A shallow clone is a FAILURE, not a skip.** The trailer checks walk history, so on `fetch-depth: 1` every one of them sees zero commits and goes green — the "check that can never be red" class this repo has now shipped three fixes for. The tool refuses instead, and CI pins that both ways.
- **`engine-proposal.sh status`** — the manual grep, made deterministic. Reports each stashed block as shipped (with the release, *and* whether your pin already has it), merged-not-yet-released, rejected with the reason, partially accepted, open, or unknown. No network.
  - **Resolves against `origin/main`, not the pinned tag.** The submodule is checked out detached at the pin, so a proposal that shipped in a later release is invisible from the worktree and would read as still open — the exact failure being removed. `update.sh` already fetches `origin/main --tags`, so any vault that has ever updated has the refs; `status` prints the horizon it used, so "no record" is never confused with "your refs are stale".
  - **The release is derived, not stored** (`git tag --contains`). The trailer lands on the feature commit but the version is decided at the separate `Release vX.Y.Z` commit that follows, so at trailer-writing time it does not exist — storing it would mean a CI check that cannot pass at PR time. Same principle as `.engine-adopted` being keyed to `git describe`.
  - Two states beyond the four proposed, both real: **merged but unreleased**, and **shipped in a release newer than your pin** — the latter being the trigger to run `update.sh`.
  - Ledger seeded with the three proposals that shipped before the convention existed (v1.24.0, v1.26.0, v1.32.0). Without the backfill, `status`'s first run would have reported all three as unrecorded and invited the consumer to re-send them — the tool's debut reproducing the bug it was built to prevent.

### Changed
- **`stash` is no longer optional, and the skill says why.** A forward-only handoff cannot be re-sent if the block was not kept: of two proposals needing a nudge, only the stashed one could be, and the other had to be reconstructed from an unrelated note that happened to cover the same ground. `stash` now also **rejects a `--slug` that disagrees with the block's own `slug:` line** — they are one key, and letting them diverge means every later lookup silently asks about a different proposal.
- **`status` does not treat the outbox as the source of truth.** `.engine-proposal/` is git-ignored by construction and therefore per-machine, while a vault runs on N machines — so deriving the answer *only* from local files makes an empty outbox look like "nothing outstanding". It says what it actually scanned, and `--slug` queries the ledger for a proposal drafted on another machine.
- **Intake must not rename an incoming slug** to fit engine vocabulary — it is the reporter's only correlation key and renaming severs it silently. A genuinely necessary rename keeps the incoming slug as an `alias` row, which `status` follows; lint asserts targets exist and do not chain.

### Notes
- **The identifier stays flat and consumer-anonymous.** Namespacing it `<consumer>/<slug>` would put the reporter's identity into engine release notes, defeating the scrub the channel exists for. Collisions are therefore possible and are handled by the alias row, never by a silent rename.
- **One acceptance criterion was rejected as unverifiable**: "the identifier carries no consumer-identifying information" cannot be mechanically checked — `scan` catches identifiers *derived from the vault*, but a topical slug can still be identifying. Restated as what is actually checkable (the existing scan passes on a block containing the slug); the rest stays with the skill's genericization pass, where it already lived.
- CI runs the ledger job separately, at `fetch-depth: 0`, so the main job does not pay for full history on every run. Both lint failures were confirmed load-bearing by introducing them and watching them go red.
- Reported upstream from a consumer vault through `engine-proposal`; the intake design-review pass is what moved the ledger write to arrival and replaced the stored release with a derived one.

## [1.33.0] — 2026-07-27

Minor — two fail-open defects found by running the engine: containing one machine-shared surface silently licensed writing the other, and `peers` reported finished sessions as live. Adds the `CLAUDE_SKILLS_DIR` seam. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **Containing one machine-shared surface silently licensed writing the other.** Redirecting `--settings` is the documented way to contain a throwaway vault, and it flipped a single shared "may wire this machine" flag — which authorised the skills step to repoint the machine's **real** `~/.claude/skills` at the throwaway engine. The settings redirect isolates `settings.json`; nothing about it isolates the skills directory. Those symlinks are what Claude Code loads, so aiming them at a directory that later gets cleaned breaks every engine skill on the machine, and they keep resolving until then — nothing announces it.
  - **One flag per surface** (`ADOPT_WIRE_SETTINGS`, `ADOPT_WIRE_SKILLS`), each gated on *its own* redirect, still decided once in `apply-adopt.sh` and never re-derived by a step. A single flag was the bug: it conflated two surfaces that are contained by two different knobs. Skills now redirect via **`CLAUDE_SKILLS_DIR`**.
  - **Hit on a developer machine, not in CI, and the fixture is why.** The existing containment test overrides `$HOME` *and* redirects settings, so it is more isolated than any real invocation and the gap could not appear. The new step deliberately leaves the real skills path in place. Same shape as the earlier guard that enumerated macOS-shaped temp prefixes and passed everywhere except the runner.
  - Also fixes a latent inconsistency across all three skill-linking call sites. The adoption step and `link-skills.sh` both hardcoded `$HOME/.claude/skills` while `skill-sources.sh` honoured `CLAUDE_CONFIG_DIR` — so on a machine setting that variable, the cold-start bootstrap and adoption wrote to *different directories*, and neither matched where the third tool looked. One rule now: `${CLAUDE_SKILLS_DIR:-${CLAUDE_CONFIG_DIR:-~/.claude}/skills}`.
- **`peers` reported finished sessions as live, and `gc` counted them as not dead.** Lease liveness was purely time-based, so a session that had cleanly integrated and been garbage-collected still appeared as a live peer for up to `WIKI_LEASE_STALE_MIN` (default two hours) — with `gc` reporting `reaped 0 dead lease(s)` while a provably dead lease sat on disk. A registry that shows ghosts stops being read, and it looks *more* authoritative as the stale age climbs.
  - **Structural evidence first, clock second.** A session that finished leaves proof: `integrate` merged its branch and `gc` removed both the worktree and the branch. When both are gone the lease cannot describe a live writer, whatever its heartbeat says. Deliberately conservative — a worktree still on disk (a *crashed* session), a branch that still exists (unintegrated commits), or a lease recorded against the canonical checkout are all "not proven" and fall through to the existing heartbeat test, so crashed sessions are still reaped exactly as before. CI pins both directions.
  - **`lease` recorded the wrong worktree when run from outside the vault.** It took the CWD's git toplevel, which is an unrelated repo if the verb is called from elsewhere. Harmless while the field was decorative; not harmless once liveness depends on it, so it now prefers the worktree `ensure` keyed to the session. Found by the new test, not by inspection.

## [1.32.0] — 2026-07-27

Minor — the pre-commit gate shipped in v1.28.0 **never installed on any vault**: its adoption step resolved its own bundled template one directory too high, found nothing, and exited 0. Fixes the path, and makes the silent-skip class it belongs to impossible. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **An adoption step's own bundled asset could go missing and the step reported success.** `adopt.d/30-vault-git-hooks.sh` resolved its template as `$ENGINE/../scaffold/pre-commit`, but `apply-adopt.sh` sets `ENGINE` to the engine **root** and the template ships at `$ENGINE/scaffold/pre-commit`. One directory too high, so the step probed the *consumer's* vault root, matched its `[ -f "$TMPL" ] || exit 0` guard, and exited 0 with no output.
  - **Effect: the v1.28.0 write-time gate has been inert on every vault for four minor releases.** No `.githooks/pre-commit` was written and `core.hooksPath` was left unset, so the concurrency guard, the link-integrity gate and the foreign-boundary gate were all absent at the pre-commit call site — on precisely the vaults that adopted the releases advertising them. CI still enforced; the pre-commit leg did not exist. Wider than first reported: `new-wiki.sh` does not install the hook either, so vaults **scaffolded** since v1.28.0 were ungated too, not only updated ones.
  - **`4aa3b95` fixed the template's own worktree-inert bug without anyone noticing the template was never being copied anywhere.** Two silent failures stacked: a gate that would have skipped in a worktree, inside a step that never installed it.
- **The reporting behaviour was the class, and it is the half that mattered.** `apply-adopt.sh` cannot distinguish "did nothing because nothing was pending" from "did nothing because its own precondition misresolved" — `rc=0` with empty stdout is the correct and common result for an idempotent step on a converged machine. It then stamped `.engine-adopted`, so the fast path engaged; `--check` said "nothing pending", and `wire-machine.sh --check` reported the machine converged. Every available signal said adopted; nothing was.

### Added
- **`bin/adopt-lib.sh` — `require_engine_asset`, and the rule it encodes.** Two kinds of missing thing need opposite responses, and both used to be written `|| exit 0`:
  - **consumer state** (a git repo, a settings file, a hook the vault wrote itself) → `|| exit 0`; absence is information, a legitimate no-op.
  - **engine asset** (a scaffold template, the skills dir, one of the engine's own scripts) → hard fail naming the **resolved** path; absence is a packaging or path bug and there is no correct silent response.
  - The step knows which guard it is; the adopter never can — so the distinction lives at the call site, not in `apply-adopt.sh`. Rejected making the adopter treat empty output as suspicious: it would be noise on every converged run and still could not tell the two cases apart.
  - **Requires run unconditionally, at the top of a step, above every consumer-state guard.** Ordering is load-bearing, not incidental: below the git-repo check or below the ephemeral-vault guard, a mispackaged engine goes unreported on every vault that isn't a git repo and on every throwaway run — narrowing the detector to exactly the machines least likely to run CI. All three shipped steps now require their assets this way, including two (`session-boot.sh`, `ensure-hook.sh`) that had no guard at all and would have wired a hook command pointing at nothing.
  - The helper lives in `bin/`, not `adopt.d/`, because `apply-adopt.sh` globs `adopt.d/*.sh` — a helper there would run as a step, print phantom `ADOPTED:` lines, and a non-zero exit from it would block the marker forever. Steps source it as `. "${ADOPT_LIB:?}" || exit 3`; the `|| exit 3` is not decoration, since steps run without `set -e` and a failed `source` would otherwise let the step carry on — reintroducing the silent skip at the root of the mechanism.
- **`bin/lint-adopt-paths.sh` — mechanical backstop.** Two narrow checks over `adopt.d/`: no path derived **above** the engine root (`$ENGINE/..` is the consumer's vault), and every **literal** `$ENGINE/<path>` resolves in the checkout. The first rule alone catches the original bug. Deliberately narrow: a "smart" version chasing dynamic paths like `$SRC/$name` would either false-positive on every one of them or be loosened until it could no longer fail — a check that can never be red is decoration, which is the same defect class. The limit is stated in the script rather than left to be discovered.
- **A failed adoption step now reaches the USER, not only the model.** `apply-adopt.sh` always exits 0 (it must never block session start) and its output lands in `additionalContext` under `suppressOutput` — model-only. So a broken engine still rendered the ordinary green `wiki-engine vX ✓` banner, and whether a human heard about it depended on the assistant choosing to mention it. `session-boot.sh` now folds `⚠ engine adopt: N step(s) FAILED` into the `systemMessage` banner. Shipping a fail-loud path whose loudness is model-only would have been half a fix.

### Notes
- **No marker/epoch machinery was added, because the self-healing property already holds.** The incoming proposal asked for one, fearing a vault marked with an affected version would fast-path past the corrected step forever. It cannot: `.engine-adopted` is keyed to `git describe` of the pinned engine, and the only way to *receive* the corrected step is to move the pin — which makes `adopted != pinned` and busts the fast path. Independently, `update.sh` checks out the new tag and then re-execs the **new** `adopt.sh`, which calls `apply-adopt.sh --force` and ignores the marker outright. Verified behaviourally and pinned by a regression test in CI (stale marker must re-run · current marker must fast-path · `adopt.sh` must force), so a future "adopt once ever" optimisation cannot quietly remove the property.
- **This is *not* the "self-updating tool applies one release late" case** (see the v1.31.0 entry). A change to `update.sh`'s own body lands one release late; a change to `adopt.d/` does not, because `update.sh` checks out the new tag *first* and re-execs `adopt.sh` from the updated checkout. This fix takes effect on the release that carries it.
- **Add-only is unchanged, and both halves are now pinned in CI**: an existing `.githooks/pre-commit` is never overwritten, and a `core.hooksPath` aimed elsewhere is never stolen. A consequence to be aware of: a vault therefore keeps whatever template it adopted, forever. The two content greps that report a hook predating the guard are the current compensation; a version-stamped template with a drift notice is the follow-up.
- **CI gained three steps, and the load-bearing ones were confirmed by reinstating the bug** and watching them go red — the path checker and the behavioural install test both fail with the original `$ENGINE/..` restored. The negative direction is asserted too: with the template renamed, the step must exit non-zero, name the path it looked for, and leave `.engine-adopted` unwritten so the next session retries.
- Reported upstream from a consumer vault through `engine-proposal`, whose intake design-review pass is what rejected the marker machinery before it was built.

## [1.31.0] — 2026-07-27

Minor — `update.sh` advances the engine repo page's provenance when it bumps the pin, converting a perpetual `refresh` item into an honest `verify` one while never touching the `verified:` stamp; plus a fix for adoption guards that let throwaway vaults wire themselves into the machine's real settings and skill symlinks. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`update.sh` now advances the engine repo page's provenance when it bumps the pin.** A vault that documents the engine it consumes re-stales that page on *every* release, so the `refresh` item reappeared immediately and reliably — three times in one session. The bump removes the churn **without losing the signal**, because the two staleness axes are independent: `refresh` compares provenance to the clone, `verify` compares `verified.against` to `sources.sha`. Advancing provenance alone silences the first and **trips the second** — the page's pointer is current, its content is unconfirmed, which is a more precise description than "refresh" and exactly what verified-stale means. Verified empirically before building on it.
  - **`verified:` is deliberately not touched.** That field asserts a human or agent read the repo and confirmed the page; writing it mechanically would fabricate the one signal the vault refuses to fabricate, converting an honest *unconfirmed* into a false *confirmed*. The content pass stays manual and stays queued. `update.sh` says so explicitly rather than leaving it to be inferred.
  - Matches pages by `sources.repo`, never by filename, and derives the repo name from the submodule's remote — so the engine hardcodes no consumer's naming.

### Fixed
- **Ephemeral vaults were wiring themselves into the machine's real config, because the guard could never fire.** `adopt.d/10` skipped a throwaway vault only when `CLAUDE_SETTINGS` was set — but `apply-adopt.sh` *exports that variable unconditionally*, defaulting it to the real settings path. The test was therefore always true and the guard always passed: every scaffold-and-adopt against a temp vault left a permanent `SessionStart` hook in the real `settings.json`. Isolation now means **"points somewhere other than the real file"**, not "is set".
  - **`adopt.d/20` had no guard at all, and its failure is worse.** It repoints `~/.claude/skills/*` — the symlinks Claude Code actually loads — so adopting a throwaway vault aimed every engine skill at a directory that later gets cleaned. They keep resolving until then, so nothing announces the breakage; the skills simply vanish at some later date.
  - **The decision now lives in `apply-adopt.sh` (`ADOPT_WIRE_MACHINE`), not in the steps.** Two in-step attempts each failed silently and differently: the first could never be false, and the replacement enumerated *macOS-shaped* temp prefixes that did not match a CI runner's `…/work/_temp/…` — so it passed locally and let the runner wire itself. One decision, one place, consulted by both steps; adding a third machine-touching step now inherits it instead of re-deriving it.
  - Third instance in one session of a check whose result could not vary (see the entries for the worktree gate and the always-red `integrate`). CI now drives `apply-adopt.sh` itself and pins both directions: an ephemeral vault must not touch the real settings or symlinks, **and** genuinely isolated wiring must still work — the second half matters, because a guard that is merely broad is the same defect facing the other way. The runner's own path shape is what exposed the second bug; it is now part of the test.

## [1.30.0] — 2026-07-27

Minor — `engine-proposal` gains the **defect path**: a bug hit while running the engine in a consumer vault now has a documented route and a block shape of its own, and the skill fires on bug phrasing rather than only on "improvement". Skill text only; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`engine-proposal` now documents the DEFECT path, not just the improvement path** (`§1b`, plus intake guidance in `§6`). A consumer vault is where engine bugs actually surface — it runs the engine all day — and it is the one place that cannot fix them: editing the pinned `engine/` submodule in place is not a fix but a time bomb, since the next `update.sh` moves the pointer straight past it. The channel already existed; nothing told a reader that a *bug* travels down it, and every trigger phrase said "improvement" or "idea", so the skill would not fire on "I found a bug in the engine". It does now.
  - **Separate the observation from the prescription.** A reporter's suggested fix can be wrong while the bug is entirely real, so the block carries them as different fields and the intake side is told to treat the fix as a hypothesis. The worked example is this engine's own issue #19: it correctly identified that a dropped terminator lost the last item, and prescribed treating the missing terminator as an integrity failure — which would have **rejected payloads whose hash matched**, forcing another paste over exactly the lossy channel the tool exists to survive.
  - **Failure shape sets urgency, not adjectives** — `fail-closed` (refuses, loses nothing) · `fail-open` (proceeds while looking correct) · `data-loss`. Fail-open is the severe one precisely because nothing surfaces it; three separate defects of that shape shipped in this engine, and each looked exactly like success.
  - **Confirm the bug is still live at the pinned version.** A defect can be fixed *incidentally* by unrelated work and stay open on paper for days, because the change that fixed it never cited it — which is what happened to #19. Intake is correspondingly told that "no longer reproduces" is not a close: find the commit that fixed it and pin it with a regression test first, since a fix nobody aimed at is the one no test covers.
  - **The scrub is harder for a defect, and skimping is tempting**, because the material that makes a report useful — error output, stack traces, command lines, paths — is exactly the material carrying absolute paths, vault and org names, and usernames. The guidance is to scrub while keeping the reproduction *runnable* (consistent placeholders) and to **declare redactions**, so a gap reads as deliberate rather than forgotten. Verified against the real gate: a defect block quoting a reproduction path fails the scan closed on three findings, and passes once genericized.

## [1.29.1] — 2026-07-27

Patch — `ensure` could silently hand back the shared working tree and report success, switching the concurrency isolation off unobserved. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`ensure` could silently hand back the canonical checkout and report success — turning the isolation off without anyone noticing.** Three linked defects, found by the tool failing on the reference vault immediately after the concurrency work shipped:
  - **`.gitkeep` placeholders made every worktree permanently un-retirable.** `retire_worktree` treated *any* `git status` output as uncommitted work, but `adopt.sh` drops a `.gitkeep` into each empty node folder — in every worktree, always. So `gc` refused forever, and worktree directories accumulated. The dirty check now ignores those placeholders (and expands directories with `-uall`, since an empty folder is invisible to git anyway) while still refusing on real untracked content, which it now *names* instead of merely counting.
  - **An orphaned directory then blocked `worktree add`.** Once a checkout survived while its gitdir went away, the path was occupied but untracked by git, `add` failed on "already exists", and `ensure` fell through. It now detects that state — path present, absent from `worktree list` — and **moves the directory aside** (`…orphaned-<timestamp>`) rather than deleting it, because it may hold untracked work and no path is worth losing files to free.
  - **The fallback now exits non-zero.** It still prints the canonical path so an existing caller degrades rather than breaks, but returning the *shared working tree* while reporting success is precisely how isolation disables itself unobserved. `checkpoint` now checks the status. The commit `guard` remains the backstop and is not a substitute: the filesystem race happens while **editing**, long before anything reaches a commit.
  - Pinned by CI in all four directions — placeholder must not block retirement, real untracked work must, an orphan must be recovered with its files preserved, and a genuine failure must exit non-zero while still printing a usable path.

## [1.29.0] — 2026-07-27

Minor — the status line gains a **context-usage gauge that names the action** (`ctx 88% — checkpoint now`), so compaction is something to get ahead of rather than discover mid-task; plus two fixes to recipes and defaults that reached further than their job. Additive; the status line remains opt-in. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **The status line reports context-window usage, and names the action rather than the number.** `ctx 42%` while there is room, `ctx 72% — checkpoint soon` in amber, `ctx 88% — checkpoint now` in red. Compaction is a thing to get *ahead* of: once `checkpoint` has run the session is disposable and a fresh one starts with the vault as its handoff, so the expensive case is discovering the ceiling mid-task with uncommitted state. Read from `context_window.used_percentage`, which Claude Code pre-calculates, and **truncated rather than rounded** so 84.9% never escalates a band. The 5-hour rate limit appears only past 80% — a number that is always on screen and never actionable is one people stop reading.
  - Degrades to the previous row on a client that does not send the field, with no `jq`, and on null / non-numeric / non-JSON input; always exits 0, because a status line that breaks is worse than one that is absent. CI asserts the bands *and* every degradation path.

### Fixed
- **CI recipes no longer write the developer's real global git config.** These `run` blocks are deliberately extracted and executed locally to verify them — that practice caught four real bugs the same day — but `git config --global` then targets the **workstation's** `~/.gitconfig`, not a disposable runner's. It silently replaced a machine's git identity, and two release commits were authored as `CI <ci@example.com>` before anyone noticed; git never announces whose name it is about to use. Steps now redirect to a throwaway `GIT_CONFIG_GLOBAL` first, mirroring the existing `CLAUDE_SETTINGS` isolation. **A CI guard enforces it**: any step calling `git config --global` without redirecting first fails the build, so the mistake cannot return by way of a newly added step.
  - The guard scans executable lines only — comments legitimately *discuss* the forbidden command, including the ones explaining why it is forbidden — and exempts itself by marker. Both exclusions were found the honest way: the first draft failed on a clean tree, which is precisely the always-red failure mode it exists alongside.
- **`new-wiki.sh` no longer needs a machine-wide `protocol.file.allow=always`.** Scaffolding from a local `--engine-url` requires git's file transport for submodules, disabled by default because of **CVE-2022-39253** (a hostile `.gitmodules` can make cloning an untrusted repo read arbitrary local paths). The documented workaround was to set it **globally**, which then applies to every clone of every repo on that machine, forever, to serve one scaffold command. The exception is now scoped to the single `submodule add`, and only when the URL really is a local path; the global setting has been dropped from CI and is no longer needed anywhere.

## [1.28.2] — 2026-07-27

Patch — `gc` no longer leaves a `wt/*` branch behind after every successfully integrated session. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`gc` judged branch containment against the wrong reference, so it kept every branch it should have deleted.** It used `git branch -d`, which compares against the branch's **upstream** (`origin/main`) rather than local `main`. A session branch that `integrate` had just fast-forwarded into local `main` therefore reported *"not fully merged"* whenever `main` had not been pushed yet — which is the normal state mid-session. The result was a `wt/*` branch accumulating after **every** session, harmless once and untenable at the session counts this concurrency work exists to support. Containment is now asked directly (`merge-base --is-ancestor <branch> <main>`), which is the actual question, and only then is the branch removed. Verified both directions: an integrated branch is deleted with `main` unpushed and no remote configured at all; an unintegrated branch is still kept.

## [1.28.1] — 2026-07-27

Patch — the vault gate was **silently inert inside a worktree**, which is where `checkpoint` commits, so it skipped exactly the commits it was meant to cover; and `integrate` counted untracked files as dirty, refusing on essentially every real vault. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **The vault gate was silently inert inside a worktree — so it skipped exactly the commits `checkpoint` makes.** A `pre-commit` that resolves `engine/bin/lint.sh` from `git rev-parse --show-toplevel` finds nothing in a linked worktree, because `git worktree add` never populates submodules. The hook then took its "engine not initialized, skipping" branch and exited 0. Since `checkpoint` has committed from a worktree by design since v1.8.0, every one of those commits bypassed the gate entirely — while the canonical checkout, where almost nothing is committed, was faithfully gated. `scaffold/pre-commit` now derives the **canonical** root from the shared git common dir and runs both the guard and the lint from there. Adoption warns any vault whose existing hook still resolves from the worktree root.
  - Found by dogfooding the v1.28.0 guard: the hook announced "submodule not initialized" from inside a worktree that was working perfectly.
  - **The first regression test for this was false and passed with the bug reinstated.** The fixture created `engine/` as ordinary tracked content, so the worktree received a copy and the gate ran — hiding the one condition that matters. It now ignores `engine/`, reproducing the submodule's absence, and was confirmed to fail when the old resolution is restored. A second instance of a fixture inheriting the implementation's blind spot.
- **`integrate` treated untracked files in canonical as "dirty" and refused.** Adoption leaves empty node folders (`queries/`, `raw/assets/`, …) and the RAG index untracked there **by design**, so the check was red on essentially every real vault — and a check that is always red is one that gets bypassed. It now inspects tracked modifications only (`status --porcelain -uno`), which is the correct semantic: a fast-forward can clobber uncommitted edits to tracked files and cannot touch untracked ones. CI now asserts both directions.

## [1.28.0] — 2026-07-27

Minor — a **concurrency model for vaults with more than one writer**: per-session isolation is now enforced by a pre-commit guard rather than merely offered, sessions can declare and see each other's intended paths, and integration to `main` is serialized under a lock. Additive; existing single-session vaults are unaffected (`WIKI_WORKTREE=0` opts out entirely). Adopt with `bin/adopt.sh` or `update.sh` — adoption installs the vault's pre-commit hook if it has none.

### Added
- **A concurrency model for more than one session (or agent) writing a vault at once.** `vault-worktree.sh` gains `guard`, `lease`, `peers` and `integrate`, and the isolation it already provided is now enforced rather than merely offered. Motivated by a real incident: two sessions worked one vault, one ran `git add -A`, and it swept the other's finished-but-uncommitted work into an unrelated commit — then a `reset` intended to repair that removed the peer's *next* commit, because the tree had moved between checking and acting.
  - **The failure needs four layers, because each one is blind to what the next catches.** Isolation (`ensure`) is the only thing that stops the *filesystem* race — two sessions editing one file is last-writer-wins on disk **before git is involved**, so no commit-time lock can help. But isolation that is merely available gets skipped, so `guard` refuses a commit made in the canonical checkout, wired from the vault's `pre-commit`. Canonical is distinguished from a worktree by asking git (`--git-dir` vs `--git-common-dir` resolve alike only in the main checkout), never by matching paths.
  - **`lease` / `peers` are advisory on purpose.** A lease that *refused* overlap would block the common, harmless case of two sessions touching one index file, and git already adjudicates real conflicts correctly at merge. Their job is to make a collision course visible while re-planning is still cheap. The session banner reports live peers, because `guard` only fires at *commit* time — by then the editing has already happened somewhere.
  - **`integrate` serializes the one genuinely shared step.** Under an atomic lock it rebases the session branch onto `main` **inside the session's own worktree**, so a conflict lands where it can be resolved instead of leaving canonical mid-merge for everyone, then fast-forwards `main`. Distinct exit codes let a loop or agent branch: **1** dirty, **2** not in a worktree, **3** conflict, **4** lock timeout. A lock whose owner stopped refreshing is broken after 30 min so one crashed session cannot wedge the rest.
  - **Liveness is heartbeat-based, not pid-based** — the recorded pid belongs to the helper script, which exits immediately; only a session continuing to touch its lease proves it is alive. `gc` reaps dead leases so `peers` never accumulates ghosts.
- **`scaffold/pre-commit.tmpl` + `adopt.d/30-vault-git-hooks.sh`** — the guard is *installed* rather than remembered. **Add-only:** an existing `.githooks/pre-commit` is never overwritten (a vault may have customized it, and silently replacing someone's hook is how hooks get disabled); when one exists without the guard, adoption reports the line to add. `core.hooksPath` is set only when unset, never stolen from a vault that aimed it elsewhere.

### Fixed
- **`vault-worktree.sh peers` exited 1 when it succeeded.** A trailing `[ "$n" -eq 0 ] && echo ...` became the branch's exit status, so finding peers — the normal case — looked like a failure to any caller. The kind of bug that only surfaces once something scripts against it.
- **The pre-commit gate reported the wrong vault.** It preferred an inherited `$WIKI_PATH` over the repo actually being committed to, so a commit refused in vault A was announced as a refusal in vault B. It now derives the canonical root from the shared git common dir. Caught by dogfooding: the guard correctly blocked a scratch vault while naming the real one.

## [1.27.1] — 2026-07-27

Patch — `lint-links.sh` no longer reads a multi-backtick code span as a real link, so documentation *about* the wikilink syntax stops being reported as a stub. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`lint-links.sh` no longer mistakes a multi-backtick code span for a real link.** The stripper handled only single-backtick spans, but CommonMark lets a code span use N backticks so it can contain runs of fewer — and ``` ``[[wikilink]]`` ``` is the natural way to write a *literal* link in prose. A single-backtick-only pass ate the delimiters and left `[[wikilink]]` looking like a genuine link, so documentation about the link syntax was reported as a stub. Runs of three, two, and one are now stripped longest-first.
  - **Found by dogfooding within minutes:** the first project page written *after* the gate shipped tripped it, which is as good an argument as any that a gate has to be run against real prose and not only against fixtures.
  - Pinned by a new CI step asserting the gate in **both** directions — a near-miss must fail, a genuine stub must not, and a link inside a 1/2/3-backtick span must be invisible. Confirmed load-bearing by removing the double-backtick handling and watching the step fail.

## [1.27.0] — 2026-07-27

Minor — the gates-at-zero set is complete: a **link-integrity gate** that errors only on links which were *meant* to resolve, and an opt-in **foreign-boundary gate**, both reading consumer-specific values from a new vault seam (`$WIKI/.wiki-gates.conf`). Additive — the link gate ships enforced at zero on an existing vault, and the boundary gate is inactive until a vault supplies patterns. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/lint-links.sh` — the link-integrity gate, plus the vault seam both consumer-specific gates read from.** Completes the gates-at-zero set: `lint.sh` now runs link-integrity and foreign-boundary alongside the boundary/provenance presence checks it already enforced.
  - **It does not error on dangling links, and that is the design.** Per `SCHEMA.md` a dangling `[[link]]` *is* a legitimate stub marker, so a gate failing on all of them would be permanently red or would demand an allowlist edit for every forward reference — which is how a gate stops being read. The defect worth catching is narrower: a link that was **meant** to resolve. A dangling target that nearly matches a real slug is an **error**; one resembling nothing stays a warning.
  - **Near-miss is three tests, because no single one covers the real failures.** Normalized equality catches case/punctuation drift; edit distance ≤2 catches ordinary typos; a **component-run** test catches the rename shape. The third is not redundant — the vault's own historical break, `[[project-pi-cluster]]` against `pi-cluster`, scores only ~0.71 similarity and is missed by *any* edit-distance threshold safe enough to enforce. Verified against all three shapes plus a genuine stub as a negative control.
  - **Links inside code spans and fenced blocks are skipped** — `` `[[wikilink]]` `` is documentation about the syntax, not a link. On the reference vault this alone removed 8 of 19 dangling targets with no allowlist involved, including `[[a]]`, `[[links]]`, and `[[slug]]`.
  - **Scope is the flat non-raw node folders.** Root hubs and `raw/` are excluded: `log.md` is append-only history that legitimately cites pages since renamed or tombstoned, so gating it would make history un-writable. Note this is strictly wider than `lint-memory.sh`, which only ever saw `memory/` — the vault-wide dangling population was roughly double what that reported.
- **The vault seam, `$WIKI/.wiki-gates.conf`** — optional, `key = value`, **parsed and never sourced** (a config file that can execute code is a config file that can own the machine running the gate). `external_refs` names targets that must never resolve here — another boundary's pages, engine files, skill names — so a permanent cross-boundary reference reads as deliberate instead of as rot a later session tries to "fix". `foreign_boundary_patterns` names the denylist file. Absent config means engine defaults; the engine names no consumer's strings, per the generic-seam rule.
- **The foreign-boundary gate** — the motivating case for the whole project: a personal-boundary vault mechanically rejecting work-org identifiers rather than relying on a human noticing during an import.
  - **Its patterns file is git-ignored by design**, and `scaffold/gitignore.tmpl` now ships that entry. Naming the forbidden strings in a *tracked* file would write the other boundary's identifiers into this vault's permanent history — committing precisely what the gate exists to keep out. The cost is real and is handled rather than hidden: a fresh clone starts unarmed, so an unarmed gate reports **`not armed`** instead of passing silently, because otherwise "no patterns configured" and "no violations found" are indistinguishable.
  - Matches report the file, the line number, and the **pattern** — never the matched text, which would put the foreign string straight into CI logs.

## [1.26.3] — 2026-07-27

Patch — the upkeep queue no longer parks the vault's self-page as perpetually stale; `huggingface_hub` advances to 1.25.1, and a CI smoke test pins `crossover`'s fail-closed contract against regression. Adopt with `bin/adopt.sh` or `update.sh`; `update.sh` re-syncs the vault's `.rag/venv` to the new pin automatically.

### Changed
- **`huggingface_hub` pinned 1.24.0 → 1.25.1** in `scaffold/rag-requirements.txt`, clearing the update `doctor.sh` had been flagging (engine issue #2). Verified by **install *and* use** across the **whole supported range**, per the pinned-deps rule: fresh venvs on Python 3.12.13, 3.13.14 and 3.14.6 each installed the full pinned set and produced real 768-dim, fully non-degenerate `bge-base` embeddings offline. Cosine was **identical on all three and identical to the 1.24.0 baseline measured the same way**, which is the result that matters here — the bump does not perturb embedding output, so vaults keep their existing `.rag` index instead of silently drifting into vectors that no longer compare against what was already built.
  - **Both 1.25.0 and 1.25.1 were published the same day this bump was taken**, with the `.1` arriving hours after the `.0` — the shape that usually means the `.0` was hot-fixed. That is the reason for measuring against a baseline rather than only checking that the install succeeded.
  - Also confirmed the one internal this repo now depends on: `constants.HF_HUB_CACHE` resolves to the same documented path under both versions, so the model-cache resolution added in v1.26.0 (`rag_embed.hf_default_cache`) is unaffected. The offline re-run read the durable cache and wrote **zero** bytes back, and no legacy temp cache was recreated.
  - The header comment in `rag-requirements.txt` still claimed the stack was verified on 3.13 alone; it now records the range actually exercised.

### Fixed
- **`upkeep.sh scan` no longer parks the vault's self-page in the queue forever.** A vault that documents its own repo has one `repos/` page whose clone *is* the vault. Its sha-vs-HEAD staleness test is structurally unsatisfiable: recording the fresh sha is itself a commit, which advances the very HEAD the page is compared against, so the page re-stales the instant it is refreshed. The item could never be drained — permanent noise in a queue whose whole point is draining to empty, and the kind of always-there row that trains a reader to skim past the queue. Only the **sha branch** is suppressed, and only for that page: a **tagged** self-page still compares tags, which do not move on every commit, so real drift is still reported. Matched by resolved physical path rather than by name, so nothing consumer-specific is baked in and a symlinked vault still matches. `verify` needed no change — its staleness keys off `sources.sha`, which the refresh commit updates in the same breath, so the stamp stays current.
- **`crossover`'s fail-closed contract is now pinned by a CI smoke test.** Issue #19 reported that an export block missing its trailing `##END` dropped its last item and then aborted under `set -u` on an empty hash array. Both halves were already fixed *incidentally* by the v1.25.0 split-export rework — which moved the last-item flush to EOF and gave the bundle computation an explicit empty guard — but nothing had been written to close the issue, so nothing stopped the regression. The test pins the property rather than the flush: **integrity rides on the per-item sha256 and the batch bundle hash, never on the block's framing.** That is exactly what the original bug violated, by making the last record's fate depend on the single line most likely to be lost over the copy-paste channel the tool exists to survive. Three assertions — an intact block verifies; the same block with `##END` stripped **still** verifies (unchanged payload ⇒ unchanged verdict); a truncated payload fails **closed** with `status incomplete`, the item named `hash-mismatch`, and nothing written to the destination. Confirmed load-bearing rather than assumed: the `run` block was extracted from `ci.yml` itself and executed, then the EOF flush was removed to recreate the pre-rework defect, which fails the second assertion with the exact issue symptom.
  - CI-only — nothing a pinned consumer runs, so this lands untagged and rides along in this release.

## [1.26.2] — 2026-07-26

Patch — pinned `onnxruntime` advanced to 1.28.0; verified by install *and* embed across the supported Python range, alongside a release-tooling fix. Adopt with `bin/adopt.sh` or `update.sh`; `update.sh` re-syncs the vault's `.rag/venv` to the new pin automatically.

### Changed
- **`onnxruntime` pinned 1.27.0 → 1.28.0** in `scaffold/rag-requirements.txt`, clearing the update `doctor.sh` had been flagging every session. Wheels exist for the whole supported range (cp312/cp313/cp314), so this is not the wheel-propagation lag that makes a fresh bump look like an incompatibility. Verified by **install *and* use**, not install alone, across the **whole supported range**: fresh venvs on Python 3.12.13, 3.13.14 and 3.14.6 each installed the full pinned set and produced real 768-dim embeddings offline from the durable model cache, with identical cosine on all three — so the vectors agree across interpreters and are not zeros. The floor matters and is easy to skip when it isn't installed locally: `uv venv --python 3.12` fetches a standalone interpreter without touching the system Python. CI still does not install the RAG stack, so this coverage is local-only.

### Fixed
- **The release workflow no longer truncates its title mid-word or leaks markdown into it.** `cut -c1-60` produced `v1.26.0 — local model weights now live in a **durable, engine-chosen c` and `v1.26.1 — two backwards-compatible fixes to consumed components: \`rag-`. Every release before v1.26.0 happened to open with a short clause, so the bug shipped unnoticed for a dozen tags. The title is now the summary's first clause as plain text: markdown stripped, split on punctuation **followed by whitespace** (so `rag-build.sh` doesn't split at its own dot), length capped at a word boundary with an ellipsis, and headings/bullets skipped so a section with no lead summary can't title the release `### Added`. Verified by executing the workflow's own block against the existing CHANGELOG sections for v1.22.0–v1.26.1 plus empty/heading-only/fallback inputs.
  - CI/release infrastructure only — nothing a pinned consumer runs, so this lands untagged and rides along in the next functional release.

## [1.26.1] — 2026-07-26

Patch — two backwards-compatible fixes to consumed components: `rag-build.sh`'s cross-boundary skip no longer **fails open** on a boundary outside the old hardcoded pair, and the engine no longer points at a consumer memory note that a freshly-scaffolded vault does not have. Adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`rag-build.sh`'s cross-boundary skip no longer fails open on an unrecognized boundary.** `vault_boundary()` matched the vault's declared boundary against a hardcoded `("personal", "work")`; anything else fell through to `None`, and `None` switches the skip off entirely. So the one automated cross-boundary guard was disabled on precisely the vaults that had adopted a new boundary — a page carrying a *foreign* `boundary:` got embedded into recall instead of skipped. Demonstrated before/after on a throwaway vault: a `boundary: work` page indexed into an `engine-wiki` vault (3 files, 0 skipped) now skips correctly (2 files, 1 skipped), with `personal` unchanged. Any well-formed token is now accepted; an unparseable declaration is reported on stderr and scanned past rather than silently accepted, and a genuinely absent boundary still means "no filter" since there is nothing to compare against.
- **The engine no longer points at a vault node that need not exist.** `CLAUDE.md`, `SCHEMA.md`, and seven skills cited `[[lesson-no-claude-in-hooks]]` — a *consumer* memory note. `scaffold/` seeds no lessons, so in every freshly-scaffolded vault that link resolved to nothing, and the always-on router handed the model a dangling pointer for its most important safety rule. `lint-memory.sh` never caught it because it only scans `$WIKI/memory`, not `engine/`. Engine files now reference **the Hard safety rule in the engine's own `CLAUDE.md`**, which states the rule in full — so the guidance is self-contained, per the generic-seam rule that the engine composes behaviour rather than depending on consumer content. A vault may still keep a fuller write-up; nothing in the engine depends on one.
  - Also corrects two outright mis-citations: `wiki-adopt` and `wiki-onboard` cited the *hooks* lesson to support a **secrets** rule.

## [1.26.0] — 2026-07-26

Minor — local model weights now live in a **durable, engine-chosen cache** instead of OS-reaped temp, so recall stops breaking on the reaper's schedule; `engine-proposal` gains a **pre-push diff review**; and every skill's automation caveat now states its actual reason instead of a blanket hook ban. Additive — existing vaults migrate their cache automatically and offline on the next `rag-setup.sh`. Adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`skills/engine-proposal/SKILL.md` §6 — review the diff before you push.** Intake gained a design-review pass in v1.25.0, but the lifecycle then ran straight from "build" to "ship", so nothing reviewed the *implementation*. The design pass and the acceptance criteria it produces are both derived from the design, as are the tests written from those criteria — so a defect outside the design's frame is invisible to all three. First use of the gate proved it: the RAG cache fix below had a sound reviewed design and passed every acceptance criterion, while running its migration side effect during a *probe* for a library that wasn't installed.
  - Points at the **host's diff-review tool** (`/code-review`) rather than the design-critique skill, which by its own positioning redirects narrow diffs elsewhere; **gated** on the same conditions as the design pass (on-disk contract, safety gate, default flip, filesystem/network side effects), since CI already covers the mechanical layer.
  - The skill's automation note now matches the engine's actual safety rule: **in-session by default, automate behind the recursion guards** (re-entry sentinel, concurrency bound, termination) rather than a blanket ban on headless spawns. The target is runaway agent generation, not `claude -p`.

### Changed
- **Every skill's automation caveat now states its actual reason.** Seven skills carried some variant of "in-session only — never a hook", which read as a blanket ban on headless `claude` and contradicted the engine's own rule: the target is *runaway agent generation*, not `claude -p`, and a deliberately-initiated spawn is legitimate when it carries a re-entry sentinel, is concurrency-bounded, and terminates. Blanket phrasing also flattened three genuinely different constraints into one, so a reader could not tell which applied — or, worse, would refuse a sound bounded-loop design by citing the wrong rule. Each site now names its own:
  - **Structural / recursion** (`checkpoint`, `crossover`, `wiki-repo`, `wiki-adopt`, `wiki-onboard`, `engine-proposal`) — the ban is on a hook firing on an event its own child can re-trigger, which is exactly what made a SessionEnd hook running `checkpoint` a fork-bomb. Bounded, deliberately-initiated runs are fine; `wiki-repo` now names a scheduled staleness refresh as a legitimate example.
  - **Consent** (`checkpoint` pruning, `wiki-context` promotion, `wiki-onboard` native-memory deletion) — these need a human judgement about what is worth keeping, so no sentinel or concurrency bound makes them safe to automate. A *stronger* constraint than the recursion one, and previously indistinguishable from it.
  - **Deterministic and therefore already hook-safe** (`rag-build.sh` in `checkpoint` §5, the engine tools in `update`) — both previously claimed they must never be hooked while stating in the same breath that they never spawn `claude`. Per the engine's rule, deterministic tools may be wired freely; it is the surrounding LLM skill that stays in-session, and for `update` the real reason is that advancing a pin is a confirmed judgement call.

### Fixed
- **Local model weights now land in a durable, engine-chosen cache instead of OS-reaped temp.** `rag-setup.sh` provisioned two artifacts with two different lifetimes and pinned only one: the venv at `$WIKI/.rag/venv` is durable, but the weights went wherever the installed library defaulted — for `fastembed`, `tempfile.gettempdir()/fastembed_cache`. When the OS reaps temp (macOS clears per-user `/var/folders/.../T`; systemd-tmpfiles reaps `/tmp`), the weights vanish while the venv survives, and the next `rag-build.sh` fails closed on a missing model. Failing closed was correct; recurring on the OS's schedule was not — and it surfaced at the worst moment, at the end of `checkpoint` with the session's notes already committed, recoverable only by a network download.
  - **Resolved in one place.** `rag_embed.py` now picks the cache and sets the backend's env var before the library is imported. That module is the single seam `rag-setup.sh`, `rag-build.sh`, and `recall.sh` all share — three separate processes, so setting it per-caller would have left one of them on the old default and re-created the same failure on the query path.
  - **`RAG_MODEL_CACHE`**, default `${XDG_CACHE_HOME:-$HOME/.cache}/wiki-engine/models`. Machine-global because the weights are machine-scoped and identical across vaults; set the variable for vault-local (`$WIKI/.rag/models`). Precedence `env > .rag/config.json > default`, mirroring how `model`/`lib` already resolve, so a forgotten env var is recovered from config rather than silently resolving elsewhere than the prefetch did.
  - **Upgrades adopt, they don't re-download.** An existing vault's weights are moved from the legacy temp location into the durable cache. `rag-build.sh`/`recall.sh` force `HF_HUB_OFFLINE=1`, so re-fetching would have broken recall for anyone who upgraded offline while perfectly good weights sat in temp.
  - **Only `fastembed` is relocated.** The HF-backed libs (`model2vec`, `sentence-transformers`) already default to a documented durable path that is shared with every other HF tool on the machine — relocating them would *reduce* sharing and force a redundant download. They move only on an explicit `RAG_MODEL_CACHE`, via `HF_HUB_CACHE` (not `HF_HOME`, which also relocates the token file), and their effective path is recorded either way.
  - **Inspectable.** The resolved path is written to `.rag/config.json` as `model_cache` and reported by `doctor.sh`, which now flags a missing or empty cache instead of letting it first surface mid-checkpoint. An unwritable cache fails naming the path — the engine never falls back to temp, which would restore the original bug while appearing fixed.

## [1.25.0] — 2026-07-24

Minor — `engine-proposal` gains the **intake** half: what the engine-dev end does with an arriving proposal, starting with a design-review pass *before* a shape is chosen. Additive (skill text only); adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`skills/engine-proposal/SKILL.md` §6 Intake (engine-dev session)** — the skill previously documented only the authoring half, so intake was ad hoc: the receiving session went straight from a `HANDOFF` block to building. A proposal *is* the design input for the build, and a gap found at intake costs a paragraph while the same gap found mid-build costs a format change with artifacts already in flight. The v1.24.0 crossover work is the worked example: the proposal never named how a destination holding one block learns the batch's shape (→ the `##MANIFEST`), nor that a re-paste of a landed block must be idempotent (the naive accumulator regresses a verified item to `exists-skipped` — a repair path that degrades on retry), nor what happens when the new metadata is itself damaged. All three change the wire format.
  - **Gated, not universal** — run the pass when a proposal touches a wire/file format, a protocol, an on-disk contract, or a safety gate, or when it flips a default; skip it for additive doc/skill-text.
  - **Named skill, generic fallback** — it points at a rigorous critique skill by name (`scrutinize`) behind an existence check (`~/.claude/skills/scrutinize`), and carries an inline, engine-generic checklist for vaults that install no such skill. The engine therefore *composes* the review without *depending* on a consumer skill (cf. the generic-seam rule) — a named hint, never a hard requirement.
  - Findings, **accepted and rejected**, are recorded in the resulting project's Key decisions; the description gained intake triggers ("act on this proposal", "here is a HANDOFF block") so the skill fires on the receiving end too.

## [1.24.0] — 2026-07-24

Minor — **`crossover export` now emits one transport block per item by default**, so the reliable copy-paste path is the default one. Backwards-compatible on import (blocks from older engines still import); adopt with `bin/adopt.sh` or `update.sh`.

### Changed
- **`bin/crossover.sh export` splits transport, one block per item.** The copy-paste channel drops content by **total paste volume**, not per-item size: in a real multi-item migration every 3-item block lost 1–2 items — including its two *smallest* (37 and 44 base64 lines) — while every single-item block survived, and the v1.19.1 column-wrapping that rescued large *single* items did nothing for multi-item blocks. The batch stays the unit of integrity: every block carries the same batch id + bundle hash plus a `##MANIFEST` of the batch's ordered `(sha256, path)` pairs, so one block is enough to know the whole batch. **`--bundle`** reproduces the old single-block output (a default flip, not a capability removal) and warns when it bundles more than one item; **`--block N`** re-emits just one block of the same batch — pass the same full path list — to repair a single lossy paste without re-sending the rest. Rejected alternatives: a `--split` flag defaulting off (leaves the failing path as the default, discovered only after the failures it prevents) and a size-threshold auto-split (the evidence is volume-per-paste, so the lost items would have fallen under any per-item threshold).
- **`import` accumulates blocks into the batch.** Blocks may arrive in any order, across separate pastes and sessions; `.crossover/<id>.inbound` is the accumulator and `.crossover/<id>.manifest` persists the batch shape, so the receipt always covers the **whole batch** — never-received items are reported `missing` — and prints the outstanding items on stderr. A re-paste of a block that already landed byte-identically is **idempotent** (previously it would have flipped a verified item to `exists-skipped`). A single stream containing several blocks is fine; blocks from two different batches in one paste are refused. `finalize` is unchanged: still gated on one `all-verified` receipt whose bundle matches what was sent, so a partial arrival still cannot authorize a delete.

### Fixed
- **`export` no longer truncates a batch's outbound ledger before validating its arguments** — a bad `--block` argument would otherwise wipe the origin's record of what the batch is. `finalize` now fails with a clear message on an empty outbound ledger instead of a bash unbound-variable error.
- **`import` tolerates a uniformly indented or space-padded paste** — markers and header keys are matched after trimming surrounding whitespace, not only inside the base64 payload (a chat client that indents the block no longer hides `##ITEM`/`bundle`). A block whose `##MANIFEST` is shorter than its declared `count` is warned about and ignored rather than trusted, and the bundle hash remains the gate.

## [1.23.0] — 2026-07-24

Minor — a new **`engine-proposal`** skill (a boundary-safe channel for a *consumer* vault to propose an engine improvement upstream to the engine-dev vault), plus a fix so ephemeral vaults no longer pollute a machine's real `settings.json`. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`engine-proposal` skill** — genericizes + boundary-scrubs a consumer vault's engine-improvement idea into a self-contained, copy-pastable kickoff block the engine-dev session can act on with **zero** consumer-vault access, and creates **no node** in the consumer vault. Solves the recurring leak: a consumer keeps discovering engine ideas soaked in private/domain context, and hand-scrubbing them for handoff is inconsistent and misses identifiers. Forward-only — it *originates* a new idea that never was a consumer node — so unlike `crossover` there is no integrity handshake and nothing is deleted; the two skills share only the boundary gate, and both descriptions carry a mutual disambiguation clause.
- **`bin/engine-proposal.sh`** — the deterministic gate the skill leans on. `scan` derives the consumer's own identifiers from the vault (git remote slug, directory name, git `user.name`/`user.email`) and flags any literal appearance in a drafted block, plus universal private-shaped patterns (home paths, emails, a non-generic `boundary:` tag, and secret assignments — reusing the `crossover` secret-scan shape); it **fails closed** (exit 1) so a scrub the model believed clean can't silently ship a leak. `stash` writes an optional git-ignored `.engine-proposal/<slug>.outbox` scratch copy for traceability (self-heals the vault's `.gitignore`). No `claude`, no network, no node creation; in-session only.
- **`scaffold/gitignore.tmpl`** — ignores the transient `.engine-proposal/` outbox on new vaults (the `stash` subcommand appends it to an existing vault's `.gitignore`).

### Fixed
- **Ephemeral vaults no longer pollute a machine's real `~/.claude/settings.json`.** The `SessionStart` boot path self-installs its own hook through the add-only `ensure-hook.sh`, whose dedup keys on the *exact* command string — and that command embeds `WIKI_PATH=<vault>`. So scaffolding/adopting a *throwaway* vault (test, CI, scratchpad) against the default settings target wrote a **unique, un-reapable** boot hook into the user's live settings; each such run left a permanent extra entry, and every one fired its own preflight banner at session start (six-plus duplicate banners observed). `adopt.d/10-session-boot-hook.sh` now **skips wiring** when the vault lives under an ephemeral root (`$TMPDIR`, `/private/tmp`, `/tmp`, `/var/folders`, `*/scratchpad/*`) **unless** the caller isolated `CLAUDE_SETTINGS` to its own file — so a real vault still wires, an isolated test still writes to its temp file, and an un-isolated throwaway wires nothing. The CI smoke test now exports `CLAUDE_SETTINGS="$RUNNER_TEMP/settings.json"` so the recipe is safe to copy-paste locally. See [[lesson-ephemeral-vault-settings-pollution]].

## [1.22.1] — 2026-07-24

Patch — `bin/upkeep.sh` stale-detection is now **tag-aware**, plus a latent frontmatter-parse fix. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **Tag-aware refresh detection** — a *tagged* repo page (`sources.ref` != `sources.sha`) now compares its recorded ref against the clone's latest tag (`git describe --tags --abbrev=0`), so a clone sitting a commit past the release tag (e.g. a docs-only commit) is no longer flagged as a false-positive `refresh`. *Untagged* pages (`ref == sha`) still compare sha vs `HEAD`. Fixes the spurious `refresh:wiki-engine` the drainable-upkeep loop surfaced.
- **`sources.repo`/`ref`/`sha` extraction handles the block-list dash form** (`  - repo: x` with the key on the list-item line), not only a key on its own indented line. Previously a page whose slug differed from its repo name resolved to the wrong clone (or none) — masked only because every current page's slug equals its repo name.

## [1.22.0] — 2026-07-24

Minor — a **`verify`** skill that packages the verification-pass procedure the v1.21.0 tools (`verify-status.sh`, `upkeep.sh`) enabled. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`skills/verify/SKILL.md`** — run a *correctness* pass on `repos/` pages: find the work (`verify-status.sh --todo` / the upkeep queue), confirm the page against the real repo at its recorded sha, fix any drift **and the source repo if the drift originated there** (fix-at-source), then stamp the `verified:` block — only after genuine confirmation. Distinct from `wiki-repo` (freshness re-ingest when the sha moved) and `checkpoint` (session curation): `verify` confirms correctness at the current sha. Documented in `USAGE.md`.

## [1.21.0] — 2026-07-24

Minor — the two remaining legs of the vault-upkeep trilogy: a **`verified:` correctness signal** (*engine-evidence-verified*) and a **drainable upkeep queue** (*engine-drainable-upkeep-loop*). Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`verified:` frontmatter convention** (SCHEMA.md) — an optional block (`date` / `by` / `against`) asserting a human or agent confirmed a page's content correct, separate from freshness (`sources.sha` vs `HEAD`). A page can be fresh-but-unverified or verified-but-stale. **Invalidation is by provenance, not a clock:** a repo page's stamp is *current* only while `verified.against == sources.sha`, so a `wiki-repo` refresh auto-demotes it to stale — the signal can't outlive the content it vouched for, and the check stays offline/deterministic.
- **`bin/verify-status.sh`** — reports verified / stale / unverified across `repos/` pages (plus any opt-in non-repo page carrying a `verified:` block). `--todo` emits the slugs needing a pass (the drainable work-list the upkeep loop consumes); `--check` exits 1 if any repo page is unverified or stale. No network, no `claude`.
- **`bin/upkeep.sh`** — a drainable maintenance queue where a live artifact (`.upkeep/queue.tsv`) IS the work-list: `scan` (re)builds it from vault state — stale repo pages (recorded `sources.sha` ≠ local clone HEAD) + un-verified pages (via `verify-status.sh --todo`); `next`/`done` drain it one item per iteration until empty. **Honors the no-`claude`-in-hooks rule structurally:** increment 1 has no spawn (the in-session agent or a human drives next→act→done), and a re-entry sentinel (`UPKEEP_DEPTH`) + an atomic mkdir lock are in place to bound any future automated driver, which must stay human/cron-initiated, sentinel-guarded, and terminating (never self-requeue). `.upkeep/` is git-ignored (derived, rebuildable).

## [1.20.0] — 2026-07-24

Minor — `bin/lint.sh` gains two **vault-invariant gates** so the umbrella lint doubles as an enforced write-time gate (the first increment of the pleejr-wiki *engine-gates-at-zero* project: hold invariants at zero, no warn-baseline). Additive and backwards-compatible for any vault that already satisfies them; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/lint.sh`** — two new checks, both hard errors (exit 1):
  - **boundary present** — every content-node page (the non-`raw/` node folders enumerated in `scaffold/node-dirs.txt`) must declare a `boundary:` in frontmatter. Generalizes the memory-only boundary check to projects/repos/concepts/entities/notes/comparisons/queries; root hubs (`CLAUDE.md`/`index.md`/`log.md`/`README.md`) and `raw/` captures are exempt (not nodes).
  - **provenance present** — every `repos/` page must carry a `sources:` block with `ref:` + `sha:`, so freshness (recorded vs live `HEAD`) stays checkable.
  - Both are universal invariants (no consumer-specific values), so they ship engine-default-on. Consumer-specific gates — a foreign-boundary denylist and link-integrity with a stub allowlist — are deferred behind a vault seam (they need per-vault config + a stub-vs-broken-link rule).

## [1.19.2] — 2026-07-24

Patch — make the `crossover` payload survive real copy-paste. v1.19.0 emitted each file's base64 as one multi-thousand-character line, which terminals/chat clients mangle or truncate. Backwards-compatible on import; adopt with `bin/adopt.sh` or `update.sh`.

### Changed
- **`bin/crossover.sh`** — export now writes the payload as **64-column wrapped base64** between a `##DATA` marker and the next item marker, instead of one long `data <b64>` line. Import accumulates the wrapped lines and **strips any stray whitespace/CR** before decoding, so a reflowed or re-indented paste still reconstructs the exact bytes (verified: a deliberately whitespace-mangled block decodes identically). The legacy single-line `data` form is still accepted on import for any block already in flight.

## [1.19.1] — 2026-07-24

Patch — tighten the `crossover` export secret-scan, which was too broad: it matched the bare words `secret`/`token`/`password` anywhere, so a workflow note that merely *discusses* secrets in prose (e.g. "secrets are never synced") was wrongly refused. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Changed
- **`bin/crossover.sh`** — the export scan now flags secret *assignments* (`key : value` / `key = value` with a ≥6-char value) plus literal key material (`AKIA…`, PEM `BEGIN … PRIVATE KEY`), not bare keyword mentions. Real leaks (`api_key: sk-…`) are still blocked; prose about secrets passes. Added a **`--reviewed`** flag to skip the scan after a human has confirmed a file, for the rare genuine false positive. Documented in `skills/crossover/SKILL.md`.

## [1.19.0] — 2026-07-23

Minor — a new **`crossover`** skill + `bin/crossover.sh` tool for migrating vault pages to another vault that never shares a machine (the deliberate manual boundary crossing), over a copy-paste text channel with end-to-end integrity. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`skills/crossover/SKILL.md`** — three-mode handshake (export → import → finalize) with a scope-classification gate (move / copy / stay) so consumption machinery is never moved, and a copy mode for dual-purpose pages that must stay at the origin.
- **`bin/crossover.sh`** — deterministic transport: `export` emits a base64 paste block (single-line, fence-safe) with a per-item sha256 + a batch bundle hash, secret-scanning each file first; `import` re-verifies every hash, writes files, flips `boundary:` to the destination's, and emits a receipt; `finalize` **soft-deletes only on a bundle-hash match** and sweeps `[[links]]` to dated tombstones (never a silent deletion). Per-batch `.crossover/` ledgers make a migration resumable; a lossy paste fails closed so it can never authorize a wipe. No `git`, no `claude` — the calling session commits removals through the normal branch→PR flow (git history is the recovery path).
- Documented in `USAGE.md` (Skills) and listed in `README.md`.

## [1.18.1] — 2026-07-22

Patch — bump the pinned RAG embedder deps and collapse the numpy environment-marker split by raising the supported Python floor to 3.12. Backwards-compatible for the vault (node model / frontmatter unchanged); a vault whose `.rag/venv` is on Python 3.11 or below must recreate it on 3.12+ (`rag-setup.sh --force`). Adopt with `bin/adopt.sh` or `update.sh`.

### Changed
- **`scaffold/rag-requirements.txt`** — single `numpy==2.5.1` (was a 3.10–3.11 `2.2.6` / ≥3.12 `2.5.1` marker split; the old `<3.12` line carried a stale numpy `doctor.sh` kept flagging as a pending bump). `huggingface_hub` 1.23.0 → 1.24.0. Now targets Python 3.12–3.14 (verified install + bge-base 768-dim embed on 3.13); 3.11 and below are dropped because numpy 2.5.x requires >=3.12.
- **`bin/rag-setup.sh`** — the self-healing interpreter floor `MIN_PY` is 3.10 → 3.12; the `choose_python` candidate list and the out-of-range hint/message strings are updated to 3.12–3.14 to match.
- **`README.md`** — the RAG prerequisite is updated to Python 3.12–3.14.

## [1.18.0] — 2026-07-22

Minor — a generic **external skill-source** mechanism so a machine can declare (and be offered) skill repos beyond the engine's own. Closes the cold-machine gap: a fresh machine with no skills cloned now gets offered to install them. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/skill-sources.sh`** — clone + link a machine's declared external skill repos from `~/.claude/skill-sources` (`<git-remote> [dir]` lines; `<dir>` defaults to `~/Documents/repos/<basename>`). `--check` reports missing (no network). Generic — the engine names no repo; the machine declares them.
- **`bin/session-preflight.sh`** now checks `~/.claude/skill-sources` (local, dir-existence only — no fetch) and, when a declared source isn't cloned, adds a banner fragment + an ACTION telling the assistant to offer `skill-sources.sh`. This is what offers to pull a consumer's skills on a cold machine.
- **`skills/wiki-adopt`** gains step 4b — ask for external skill repos, record them in `~/.claude/skill-sources`, and install them via `skill-sources.sh` — seeding the mechanism at adoption so a cold machine self-serves.

## [1.17.0] — 2026-07-22

Minor — a generic engine-only `update` skill, and a `session-checks.d` extension seam so a consumer surfaces its own session-start checks in the one banner. Replaces v1.16.0's skills-specific nudge with a generic drop-in mechanism (keeps the engine boundary-agnostic). Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`skills/update`** — engine-only "catch up this machine's engine": `doctor` freshness → offer `update.sh` (on confirmation) → `wire-machine --check` → converge → relink the engine's own skills. Distributed by `link-skills.sh`. Generic — it never touches a consumer's separate skill repos or their tag system.
- **`bin/session-preflight.sh` — `session-checks.d` seam:** runs executable drop-ins in `~/.claude/session-checks.d/` (deterministic; must not call `claude`) and folds each into the SessionStart banner (first stdout line = compact fragment, rest = action/notes). Lets a consumer skill repo surface its own "first run / catch up" beside engine freshness without the engine hardcoding it.

### Changed
- **`bin/session-preflight.sh`** — the v1.16.0 skills-specific catch-up block (which read `~/.claude/skill-tags`/`.wiki-catchup` and assumed a consumer `update` skill) is **replaced** by the generic `session-checks.d` seam. A consumer now ships that check as a drop-in; the engine stays generic.
- **`USAGE.md` / `README.md`** document the `update` skill and the `session-checks.d` seam.

## [1.16.0] — 2026-07-22

Minor — the session-start banner now nudges toward the `update` skill: a first-run "pick your skills" prompt and a staleness "catch up" hint, both computed **locally** (no fetch — offline-safe, no startup latency). Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/session-preflight.sh`** gains a deterministic skills catch-up nudge, active only when the `update` skill is installed (`~/.claude/skills/update`). Two local signals: **first run** (no `~/.claude/skill-tags`) → prompt the user to pick a skill set via `/update`; **staleness** (last catch-up older than `WIKI_CATCHUP_DAYS`, default 7) → suggest `/update`. No network — it reads two markers the `update` skill maintains (`skill-tags`, `.wiki-catchup`), so session start stays instant and works offline. Surfaces in the session banner (via the existing status cache) and as an ACTION/NOTE line for the assistant.



Minor — adoption is now **idempotent**: a new `wire-machine.sh` converge verb wires a machine to an already-cloned vault (the second/Nth-machine path), and `wiki-adopt` is reframed from one-shot to re-run-safe. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/wire-machine.sh`** — idempotent "make THIS machine ready for the vault at `$WIKI_PATH`": engine-submodule init, skill links, `WIKI_PATH`, the always-on `CLAUDE.md` import, `.rag` runtime, and feature-adoption (via `adopt.sh`). Add-only and re-run-safe; `--check` previews and exits 0 when already converged. This is the previously-missing "wire an existing clone" verb — the second-machine case `wiki-adopt` used to dead-end on ("if a vault exists, stop").
- **`bin/lint-docs.sh`** — usage-doc coverage gate (run in `engine-ci`): every skill is documented in `USAGE.md`, and every `bin/*.sh` `USAGE.md` references actually exists. Keeps adoption docs from drifting as verbs are added.
- **`bin/link-skills.sh --check`** — dry-run reporting what would link/repoint (exit 1 if pending), so `wire-machine --check` reports skill-link state accurately instead of always "pending".

### Changed
- **`skills/wiki-adopt`** reframed one-shot → idempotent converge: it detects state and either scaffolds+wires (no vault yet) or just wires an existing clone (new step 3b), and is safe to re-run. Removed the "if a vault exists, stop" dead-end.
- **`bin/new-wiki.sh`** delegates all machine wiring (skills, `WIKI_PATH`, `CLAUDE.md` import, `.rag`) to `wire-machine.sh` — one source of wiring truth shared by scaffold and adopt — and now also runs feature-adoption, so a freshly scaffolded vault gets the SessionStart boot hook wired.
- **`.github/workflows/ci.yml`** runs `lint-docs.sh`.
- **`USAGE.md` / `README.md`** document `wire-machine.sh`, the second-machine flow, and idempotent adoption.

## [1.14.0] — 2026-07-22

Minor — the `index.md` Projects buckets are now generated from project-page frontmatter instead of hand-maintained, closing the drift gap that left three closed projects sitting under **Active**. Additive; adopt with `bin/adopt.sh` or `update.sh`.

### Added
- **`bin/gen-projects-index.sh`** — regenerate the `index.md` Projects catalog (Planned/Active/Paused/Done) from `projects/*.md` frontmatter (`status`, `summary`), spliced between `<!-- projects:start -->` / `<!-- projects:end -->` sentinels — the same deterministic scan pattern as `gen-skills-index.sh`. `--check` fails on drift, `--stdout` prints the block, `--wiki DIR` targets another vault. An empty/fresh vault renders the four `_none_` buckets rather than erroring. An unknown `status:` value is surfaced under an `### Other` bucket rather than silently dropped.

### Changed
- **Project pages gain a `summary:` frontmatter field** (the one-line index hook) alongside `status:`; `SCHEMA.md` documents both as the source of the generated buckets. Closing a project is now just flipping `status: done` — the index follows on the next `checkpoint`/lint.
- **`bin/lint.sh`** gains a 5th check — projects-catalog drift (`gen-projects-index.sh --check`) — so a stale index fails lint the same way a stale skills catalog does.
- **`skills/checkpoint/SKILL.md`** now instructs regenerating the Projects buckets from frontmatter (§1 keep `status`/`summary` current, §4 run the generator) instead of hand-editing the index.
- **`scaffold/index.md.tmpl`** ships the `<!-- projects:start/end -->` sentinels with empty buckets so a freshly scaffolded vault is generator-ready and passes lint out of the box.

## [1.13.4] — 2026-07-21

Patch — drop the Claude Code version from the SessionStart banner; v1.13.2 removed the *check* from `session-preflight.sh` but left the *display* in `session-banner.sh`, so `claude code …` kept rendering. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/session-banner.sh`** no longer computes or prints the `claude code <version>` segment. v1.13.2 dropped the Claude Code staleness *check* from `session-preflight.sh`, but the banner is rendered separately and independently read `$CLAUDE_CODE_EXECPATH` to append `· claude code <ver> ✓` — so the version the removal was meant to retire kept appearing every session. The banner now reports **only** wiki-engine (`wiki-engine <ver> ✓`, or `wiki-engine <ver> · ⚠ <frag>` when stale). Stale comments in `bin/session-boot.sh` that still named "Claude Code + wiki-engine" were corrected to match.

## [1.13.3] — 2026-07-21

Patch — `vault-worktree.sh gc` can now retire a *specific* worktree on demand, and `ensure` is idempotent per session, so `checkpoint` stops leaking a worktree every run. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/vault-worktree.sh gc` never retired the current session's worktree.** `gc` age-gates on `WIKI_WT_STALE_HOURS` (default 48h), so a worktree `checkpoint` had just created was always "too fresh" to reap — the skill's §0 "integrate then `gc` to retire it" step was a silent no-op, and every checkpoint left its worktree (and branch) behind to accumulate until some run ≥48h later happened to sweep it. `gc` now accepts explicit target paths — `gc <path>…` retires exactly those **now**, regardless of age (clean-only; refuses paths outside `$WIKI_WORKTREE_ROOT`). Bare `gc` keeps the age-gated orphan sweep for crashed-session leftovers. `checkpoint` §0 now calls `gc "$WORK"`.
- **`ensure` spawned a duplicate worktree when called more than once per session.** With no `WIKI_WT_SESSION`, each `ensure` minted a fresh `date-$$` slug, so a second call from `$WIKI_PATH` (rather than from inside the first worktree) created a second, orphaned worktree. `ensure` now defaults the session slug to `$CLAUDE_CODE_SESSION_ID`, so repeat calls within one session reuse a single worktree. Reattaches to an existing session branch (never resetting it) if a prior worktree was retired while holding unmerged commits.

### Changed
- **Branch deletion on retire is now merged-safe.** Retiring a worktree deletes its `wt/*` branch with `git branch -d` (merged-only) instead of `-D` (force), and logs+keeps the branch when it still holds unmerged commits — so committed-but-unintegrated work is no longer silently discarded, matching the "never discard uncommitted work" guarantee already applied to the working tree.

## [1.13.2] — 2026-07-21

Patch — drop the Claude Code version check from `session-preflight.sh`; it crashed the SessionStart banner and duplicated the harness's own update prompt. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/session-preflight.sh`** no longer checks the Claude Code binary's installed-vs-latest version (section 1). That block crashed the SessionStart banner with `line 58: installed�: unbound variable` and duplicated Claude Code's own built-in update prompt. Preflight now reports **only** wiki-engine staleness. Also drops the now-unused `CC_ENDPOINT` variable and the `curl` dependency — the script is git-only. The shared `summary` status-line var still composes correctly from the wiki-engine fragment alone.

## [1.13.1] — 2026-07-20

Patch — `engine-version.sh` measures staleness **tag-to-tag**, not against `origin/main`'s HEAD, so untagged commits past the latest tag no longer read as a phantom update. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/engine-version.sh`** compared the pinned commit against `origin/main`'s HEAD, so an untagged docs/CI commit sitting past the latest tag (e.g. the `release.yml` workflow) reported `pinned v1.13.0, latest v1.13.0-1-g<sha> — update available` — a phantom `⚠` the `v1.13.0` banner then surfaced every session, with nothing to adopt (`update.sh` only advances tag→tag). It now compares the pinned tag against the **latest release tag reachable on origin/main** (`git tag -l 'v*' --merged FETCH_HEAD | sort -V | tail -1`): equal ⇒ up to date even when untagged commits sit ahead; strictly newer tag ⇒ the real update; higher pinned tag ⇒ ahead/no action. The staleness the banner/status line show now matches what `update.sh` would actually adopt.

## [1.13.0] — 2026-07-20

Minor — fold the version banner into `session-boot.sh` so it reflects the **current** session's check, and retire the separate banner hook. Additive/behavioral (a `bin/` change + removed `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration — but see the note on removing the old standalone banner hook.

The v1.12.0 banner was its own SessionStart hook that read the staleness cache `session-preflight.sh` writes. Claude Code runs SessionStart hooks without ordering guarantees, so the banner raced the preflight that feeds it and could read a cache a sibling was still writing — showing a **stale verdict** (e.g. `✓ up to date` when a newer tag already existed). Folding the two into one process fixes it at no extra latency (preflight runs every start regardless).

### Changed
- **`bin/session-boot.sh`** now runs `apply-adopt.sh` → `session-preflight.sh` → banner render in one pass and emits a single hook-JSON: `systemMessage` (the banner, to the user) + `hookSpecificOutput.additionalContext` (the adopt/preflight detail, to the model). Because preflight writes the cache immediately before the banner reads it, the banner always reflects this session's check. Falls back to plain stdout (model context) without `jq`.
- **`bin/session-banner.sh`** is now a **pure renderer** — prints the banner text to stdout, no JSON, no hook semantics. `session-boot.sh` calls it and wraps the result in `systemMessage`.

### Removed
- **`adopt.d/40-session-banner-hook.sh`** — the banner is no longer a separate hook; `session-boot.sh` (already the single entrypoint) emits it. Removing the step stops new/bumped vaults from wiring a standalone banner hook.

### Note — removing the old standalone banner hook
A vault that adopted v1.12.0–v1.12.1 has a standalone `session-banner.sh` SessionStart hook wired. Adopt is add-only and won't remove it, but it no longer double-surfaces: `session-banner.sh` now prints plain text, and SessionStart routes a hook's plain stdout to the *model's* context, not the user — so the stale hook degrades to harmless context noise, not a visible second banner. Remove it from `settings.json` for tidiness (the `session-boot` hook now owns the banner).

## [1.12.1] — 2026-07-20

Patch — the status line is now **opt-in**, not auto-wired. With the `v1.12.0` banner as the default user-visible surface, auto-wiring the `v1.11.0` status line too double-surfaced the same verdict. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Removed
- **`adopt.d/30-statusline.sh`** — the step that auto-wired `statusline.sh` as a `statusLine`. Removing it stops new/bumped vaults from getting a status line by default; the **banner** (`session-banner.sh`, `adopt.d/40`) remains the auto-wired default. `statusline.sh` and `ensure-statusline.sh` **stay shipped** — a vault that wants the persistent row wires it manually (`ensure-statusline.sh`). This only stops *auto-adoption*; an existing status line a vault already wired is untouched (adopt is add-only and never removes).

### Changed
- **`USAGE.md`** now documents both surfaces — banner (default) vs status line (opt-in) — and drops the stale "a hook can't reach the UI" framing (a hook *can*, via `systemMessage`; see `v1.12.0`). **`ensure-statusline.sh`** header notes it is opt-in tooling, not an adoption step.

## [1.12.0] — 2026-07-20

Minor — a **user-visible** version banner at session start via the hook `systemMessage` channel, so the verdict reaches the user cleanly without the statusLine. Additive (new `bin/` tool + an `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

The v1.11.0 statusLine surfaced the verdict on a persistent row, but the statusLine can be suppressed in a session (e.g. workspace-trust gating) and never renders for some setups. This adds a second, more robust surface that doesn't depend on the statusLine at all. It resolves the long-standing constraint that a SessionStart hook's plain stdout goes only to the model's context (invisible to the user) and its stderr is only user-visible via a non-zero exit that Claude Code renders under a `SessionStart hook error` heading: the **`systemMessage`** JSON field is shown to the user on **exit 0**, with no error heading — the sanctioned clean channel.

### Added
- **`bin/session-banner.sh`** — emits `{"suppressOutput":true,"systemMessage":"…"}` on stdout and exits 0, so Claude Code shows the user a one-line version banner (`wiki-engine <ver> ✓ · claude code <ver> ✓`, or a `⚠` line when stale) in-session at start, with no interaction. Instant and network-free: engine version from `git describe`, Claude Code version from `$CLAUDE_CODE_EXECPATH`, staleness from the cache `session-preflight.sh` writes (empty cache = all current). Degrades to plain stdout without `jq`. Deterministic; never runs `claude`; always exits 0.
- **`adopt.d/40-session-banner-hook.sh`** — adoption step that wires `session-banner.sh` as a `SessionStart` hook (matcher `startup|resume`) via `ensure-hook.sh`, so a fresh install or pin bump surfaces the banner with no manual `settings.json` edit.

### Notes
- Complements, does not replace, the v1.11.0 statusLine: the statusLine is a *persistent* indicator; the banner is a *one-shot* start-of-session announcement. Both read the same `session-preflight.sh` cache, so they always agree. A vault can wire either or both.

## [1.11.1] — 2026-07-20

Patch — `ensure-hook.sh` no longer duplicates a hook when the user's matcher is *broader* than the one being wired. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/ensure-hook.sh`** matched an existing hook only by an *exact* matcher string, so wiring the engine's canonical `startup|resume` into a vault whose `session-boot.sh` hook used a broader `startup|resume|clear` added a **second** entry — running the boot hook (and its preflight) twice per startup. It is now **coverage-aware**: a hook counts as already wired when the exact command is present under a matcher whose event-token set (split on `|`; empty/absent = match-all) is a **superset of, or equal to**, the requested one. Still strictly add-only — the inverse case (an existing matcher *narrower* than the request) can't be collapsed without editing the user's hook, so it still appends; broaden the request instead.

## [1.11.0] — 2026-07-20

Minor — the version preflight's verdict is now **user-visible** via a Claude Code status line, not just fed to the assistant's context. Additive (new `bin/` tools + an `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

A SessionStart hook can only surface `session-preflight.sh`'s staleness report by adding it to the assistant's context (Claude Code never draws hook stdout in the UI), so whether the user ever hears "an update is available" depends on the assistant choosing to relay it — and it may not. The status line closes that gap with a persistent, always-drawn surface.

### Added
- **`bin/statusline.sh`** — the engine's status-line renderer. Prints one bottom row (working dir · model · a color-coded `⚠` when stale — **amber** for a normal update, **red** for a MAJOR/breaking one). Reads its staleness text from a cache `session-preflight.sh` writes, so it does **no network** on the hot path and stays cheap enough to re-render constantly. Degrades gracefully without `jq` or a cache, honors `NO_COLOR`, and always exits 0 (a failing status-line command must not disrupt the session). Deterministic; never runs `claude`.
- **`bin/ensure-statusline.sh`** — the status-line sibling of `ensure-hook.sh`. Because Claude Code allows exactly **one** status line, this can't be additive like hooks; it is conservative instead: sets ours when none exists, self-heals ours if the script path drifts (matched by `--marker`), and **never clobbers a foreign status line** the user configured themselves. Backs the file up before any write; `--check` dry-runs. Deterministic; never runs `claude`.
- **`adopt.d/30-statusline.sh`** — adoption step that wires `statusline.sh` as the status line via `ensure-statusline.sh`, so a fresh install or pin bump surfaces the version verdict with no manual `settings.json` edit.

### Changed
- **`session-preflight.sh`** now also writes a compact one-line staleness summary to a per-machine cache (`${CLAUDE_CONFIG_DIR:-~/.claude}/.wiki-engine-status`; empty file = all current) for `statusline.sh` to read. Always (re)written each run, so resolving a stale pin clears the warning on the next session. Unchanged otherwise — still deterministic, still never runs the `claude` binary.

### Fixed
- **`engine-version.sh`** no longer reports "update available" when the pinned engine is *ahead* of `origin/main` (SHAs differ but `HEAD..origin/main` is empty — e.g. developing on an unpushed branch). It now reports "ahead — no action" and exits 0, instead of a spurious differ-with-0-behind downgrade. Latent before (a pin is normally never ahead), but the new status line made the false `⚠` persistent.

## [1.10.0] — 2026-07-20

Minor — skills now track the pinned submodule, not the cold-start clone. Additive (new `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

### Added
- **`adopt.d/20-link-skills-submodule.sh`** — an adoption step that repoints `~/.claude/skills/*` at the vault's **pinned submodule** (`$ENGINE/skills`) whenever a slot doesn't already resolve there. Closes the skills-vs-pin drift: `link-skills.sh` (the cold-start bootstrap) symlinks skills at whatever clone it ran from — a standalone clone, before a vault exists — and nothing repointed them afterward, so `update.sh` (which bumps only the pin) left the *live* skills lagging the pinned engine. Now, because `session-boot.sh` runs `apply-adopt.sh` each session, a pin bump updates tooling **and** skills in lockstep. Idempotent and add-only: only the engine's own skills are touched (a foreign skill symlinked from another repo — e.g. `redteam` — is left alone), a real dir/file in a slot is never clobbered, and it prints only what it changed. Deterministic; never runs `claude`.

## [1.9.0] — 2026-07-20

Minor — engine features that need hook wiring now **auto-adopt into the next session** instead of waiting on a manual `settings.json` edit. Additive (new `bin/` tools + an `adopt.d/` convention); adopt with `bin/adopt.sh` or `update.sh`. This closes the gap that left v1.7.0's `session-preflight.sh` shipped-but-unwired: the engine now owns a single durable entrypoint, and every later feature wires itself through it.

The model: wire **one** SessionStart hook — `session-boot.sh` — and the engine owns the rest. On each session start it auto-applies any adoption steps the pinned engine introduced since this machine last adopted, then runs the version preflight. `adopt.sh`/`update.sh` wire that one hook (and self-heal it), so a fresh install or a pin bump needs no manual hook surgery.

### Added
- **`adopt.d/`** — versioned, **idempotent, add-only** adoption steps (one per feature that needs more than a folder — e.g. a hook). `apply-adopt.sh` runs them in filename order; each prints only what it changed. This is the general mechanism by which a shipped engine feature takes effect in the next session without manual wiring.
- **`bin/ensure-hook.sh`** — the reusable primitive behind adoption: idempotently ensure a hook command is present in a `settings.json` (jq). **Add-only** — matches by exact command string (no dupes), co-locates into an existing matcher entry, backs the file up before any write, and never edits or removes an existing hook. `--check` dry-runs (reports, writes nothing, never creates the file). Deterministic; never runs `claude`.
- **`bin/apply-adopt.sh`** — runs the `adopt.d/` steps against a vault/machine. Version-gated by a per-machine marker (`$WIKI/.engine-adopted`, gitignored) so it's a no-op once the current pin is adopted; `--force` re-runs, `--check` reports pending steps (exit 1 if any). Because every step is idempotent, the marker is only an optimization — a marker-less machine simply runs them once. Deterministic; always exits 0 (a hook must not block session start); a partial failure leaves the marker unset so the next session retries.
- **`bin/session-boot.sh`** — the engine's single SessionStart entrypoint. Runs `apply-adopt.sh` (auto-wire pending features) then `session-preflight.sh` (report Claude Code + wiki-engine staleness). Wire **this one hook** and the engine owns everything after. Deterministic; never runs `claude`; always exits 0.
- **`adopt.d/10-session-boot-hook.sh`** — the first adoption step: self-heals the `session-boot.sh` SessionStart hook (matcher `startup|resume`), so it is put back if ever missing (fresh machine, reset settings).

### Changed
- **`bin/adopt.sh`** now runs `apply-adopt.sh` after ensuring node folders, so "adopting" wires shipped features too — not just folders. `--check` reports pending feature-adoption steps alongside missing folders. **`update.sh` inherits this** (it calls `adopt.sh`), so a `tag→tag` bump both stages the pin and wires the new tag's features.
- **`session-preflight.sh`** is now invoked *by* `session-boot.sh` rather than wired as its own hook. **Wiring `session-boot.sh` supersedes the v1.7.0 manual `session-preflight.sh` hook line** — the boot hook runs preflight for you. A vault that already wired preflight directly can keep it, or replace it with the boot hook (which also carries auto-adoption).
- **Adopt the marker into `.gitignore`** — `$WIKI/.engine-adopted` is per-machine adoption state (settings.json is per-machine), so it should not be committed.

## [1.8.0] — 2026-07-20

Minor — concurrent-session write isolation via git worktrees. Additive (new `bin/` tool + `checkpoint`/`wiki-context` behavior + a `SCHEMA.md` convention); adopt with `bin/adopt.sh`, no migration.

### Added
- **`bin/vault-worktree.sh`** — gives a vault-writing session its own `git worktree` on a `wt/<session>` branch off `origin/main` (own dir + own HEAD, shared `.git`), so two Claude Code sessions pointed at one `$WIKI_PATH` can't clobber each other's edits or move HEAD out from under one another. Two sessions otherwise share one working tree, where simultaneous page edits are silent last-writer-wins on disk *before* git sees them — a filesystem race a lockfile/`pull --rebase` doesn't fix. `ensure` (idempotent, prints the path to write in), `gc` (retire stale/orphaned worktrees, clean ones only), `list`. Deterministic (plain git, no `claude`). Measured cost ~0.4 s / <1 MB — only tracked text is checked out.

### Changed
- **`checkpoint`** now isolates writes first (new §0): `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)"`, make all edits/commits/lint against `$WORK`, run engine tooling from canonical (`lint.sh --wiki "$WORK"`) since the submodule isn't checked out in a worktree, then integrate the branch (merge/PR per the vault's convention) and `gc`. RAG rebuilds against canonical `$WIKI_PATH` after integration (the `.rag/` index is untracked, canonical-only).
- **`wiki-context`** documents that reads stay on canonical `$WIKI_PATH` (read-only, no worktree needed).
- **`SCHEMA.md`** — new "Concurrent-session isolation" note + a `vault-worktree.sh` tooling entry.
- Isolation is **always-on** (opt out per vault with `WIKI_WORKTREE=0`), deliberately not gated on detecting a second session: a missed detection would reintroduce the exact clobber, and the cost is negligible.

## [1.7.0] — 2026-07-20

Minor — add `bin/session-preflight.sh`, a version check for a SessionStart hook. Additive (new `bin/` tool); adopt with `bin/adopt.sh` and wire the hook per below.

### Added
- **`bin/session-preflight.sh`** — run from a vault's `SessionStart` hook; deterministic and **never runs the `claude` binary** (version from install metadata, not `claude --version`, so it satisfies the no-`claude`-in-a-hook rule) and always exits 0 so it can't block session start. It reports two things and, when either is stale, prints an ACTION-REQUIRED block telling the assistant to **ask the user before updating** (the hook never prompts or changes anything):
  1. **Claude Code** — installed vs latest stable (official release endpoint), best-effort by install method (Homebrew cask · npm global); on confirm the assistant runs the matching upgrade + advises a restart.
  2. **wiki-engine** — pinned submodule vs `origin/main`, delegated to the sibling `engine-version.sh`; on confirm the assistant runs `update.sh` and commits the bump.

  Wire it:
  ```json
  "SessionStart": [{ "matcher": "startup", "hooks": [
    { "type": "command", "command": "WIKI_PATH=/path/to/vault /path/to/vault/engine/bin/session-preflight.sh" }
  ]}]
  ```

## [1.6.0] — 2026-07-17

Minor — narrow the `claude`-spawn safety rule from a blanket ban to recursion guards. Touches the `CLAUDE.md` router and `SCHEMA.md`, so it ships as a pinned bump; adopt with `bin/adopt.sh`.

### Changed
- **Hard safety rule (`CLAUDE.md`)** reframed around the actual failure mode — *recursion and runaway agent generation* — rather than fearing headless `claude`. Unguarded `claude` spawn from a **lifecycle hook** stays a hard no (the structural fork-bomb trap the `.ai-os` SessionEnd incident hit, ~13.7k sessions). Deliberate headless spawns (human/cron `claude -p` one-shots, subagents) are now permitted **when bounded**: a re-entry sentinel (`CLAUDE_SPAWN_DEPTH`, refuse above a small N), a concurrency cap (lockfile / count), and guaranteed termination (no self-requeuing watch loop). Deterministic hooks (git/file/`curl`, e.g. `rag-capture.sh`) are unchanged — no guard needed, since they can't recurse into `claude`.
- **`SCHEMA.md`** — `rag-capture.sh` note aligned to the revised framing: it runs from a hook with no guard at all, and a guarded `claude` spawn is now the other permitted hook case.

## [1.5.4] — 2026-07-16

Patch — extend the RAG layer to Python 3.14 and make interpreter selection self-healing.

### Fixed
- **RAG couldn't provision on Python 3.14** (a fresh machine's default `python3`). `onnxruntime`/`fastembed`/`tokenizers` already had 3.14 wheels; only numpy blocked it — no single release spans 3.10–3.14 (`2.2.6` has no 3.14 wheels, `2.5.x` requires ≥3.12). Split numpy with an environment marker (`numpy==2.2.6; python_version < "3.12"` / `numpy==2.5.1; python_version >= "3.12"`), so the pinned stack now installs + embeds bge-base (768-dim) on **3.11, 3.13, and 3.14** (all verified).
- `rag_deps_check.py` (doctor + the freshness cron) now **evaluates the `python_version` marker**, so it only checks the numpy pin matching the venv's Python — no spurious "drift" on the bucket that doesn't apply.

### Added
- `rag-setup.sh` **self-heals the interpreter**: when the default `python3` is outside the supported 3.10–3.14 range, it auto-selects an in-range interpreter from PATH or pyenv (what you'd otherwise do by hand on a Python-3.14 machine) before creating the venv; if none exists it prints the model2vec fallback instead of aborting. Ceiling raised 3.13 → 3.14; README prereqs updated.
- Rolls up the untagged `main` hygiene fix since v1.5.3: `bin/__pycache__/*.pyc` is no longer tracked (it re-dirtied the submodule in consuming vaults). Bumping a vault to v1.5.4 clears that noise.

## [1.5.3] — 2026-07-16

Patch — make the optional RAG layer install on current Python (fixes adoption-time recall on 3.13).

### Fixed
- **Semantic recall couldn't provision on Python 3.13.** The pinned embedder stack (`onnxruntime==1.19.2`, `numpy==2.0.2`, …) predated 3.13 and had no wheels, so `rag-setup.sh` failed and the vault fell back to lexical recall. Bumped the pinned set to **fastembed 0.8.0 / onnxruntime 1.27.0 / numpy 2.2.6 / tokenizers 0.23.1 / huggingface_hub 1.23.0** — verified to install and embed bge-base (768-dim) on **both Python 3.11 and 3.13**.
- `rag-setup.sh` now **guides on failure** instead of aborting opaquely: a proactive warning when the venv Python is < 3.10, and on a failed pinned install it prints the remedies (use Python 3.10–3.13, or the onnxruntime-free `model2vec`/potion fallback, whose choice persists in `.rag/config.json`). Recall is optional, so this stays a guided, non-fatal skip.

### Changed
- **Minimum Python for the (optional) RAG layer is now 3.10** — Python 3.9 is EOL (2025-10) and `numpy>=2.1` dropped it. Documented in README Prerequisites and `rag-requirements.txt`. The rest of the engine (skills, `bin/`, scaffolding) is unaffected — it needs only `bash` + `git`.

## [1.5.2] — 2026-07-16

Patch — docs + license for the now-public repo.

### Added
- `LICENSE` — MIT.
- `README` **Prerequisites** section: what to have in place before adopting — Claude Code installed + signed in, git, a POSIX/symlink-capable shell (required); a git-host account + authenticated `gh` for remote creation (recommended; `--remote <url>` or none otherwise); Python 3.9+ for the optional RAG layer; and the up-front boundary/identity decision.

### Changed
- Dropped the specific personal vault name from the README intro now that the repo is public (the engine holds no identity by design). Swept the tree: no identity/account references remain in committed content.

## [1.5.1] — 2026-07-16

Patch — fix the cold-start bootstrap for `/wiki-adopt`.

### Fixed
- **`/wiki-adopt` was undiscoverable on a fresh machine.** Claude Code discovers skills only from `~/.claude/skills/` and `<project>/.claude/skills/`, never a cloned repo's bare `skills/` dir — so `git clone` + `cd wiki-engine` did *not* expose the skill (the `v1.5.0` README instruction was wrong for the first run). Added **`bin/link-skills.sh`**: idempotent symlinker of the engine's skills into `~/.claude/skills/`, non-destructive (an existing link to this engine is kept; a foreign slot is warn+skipped, `--force` to repoint), never calls `claude`. `new-wiki.sh` now calls it instead of its own inline `ln` loop (one implementation, and it no longer silently hijacks a foreign symlink).
- Docs corrected: the adoption flow is now `clone → bin/link-skills.sh → claude (any folder) → /wiki-adopt`, documented in `README`, `USAGE`, and the `wiki-adopt` skill.

## [1.5.0] — 2026-07-16

Additive — one-shot adoption on a fresh machine; adopt with `bin/adopt.sh` (no vault changes required).

### Added
- `skills/wiki-adopt/` — the adoption front door: run once from a standalone engine clone (you start the session, so no recursive `claude` spawn) to drive scaffold → wire the machine → seed. Gathers the vault's boundary/identity/remote, runs `new-wiki.sh` full-auto, points the session at the vault, then chains into `wiki-onboard`. Guarded for **single-vault machines only** (the wiring is global); a dual-boundary machine scaffolds without wiring and scopes activation per-directory.
- `bin/new-wiki.sh` — now **prompts** for the required args (`--path`/`--boundary`/`--email`/`--git-name`) when run interactively, and gained opt-in machine-wiring flags: `--wire-shell [RC]` (append `export WIKI_PATH` to the shell rc), `--wire-claude-md` (append the always-on `@…/CLAUDE.md` import), and `--remote URL` / `--create-remote OWNER/NAME` (+`--visibility`) to add and push the git remote (`gh`). All wiring is idempotent — a pre-existing `WIKI_PATH` export or import line is left untouched with a warning. The closing summary lists what was auto-wired and prints only the steps still left manual.

Design: the deterministic scaffold + wiring stays in `new-wiki.sh`; the skill adds conversational prompting and the in-session onboarding a bare script can't safely do (no `claude` spawn from a script/hook).

## [1.4.2] — 2026-07-15

Patch — docs.

### Added
- `USAGE.md` — day-to-day guide: the loop mental-model, a day in the loop, the skills, a full `bin/` command table, setup/activation (RAG + the capture hook), keeping-current, boundary/safety, and the env knobs. Complements `SCHEMA.md` (spec) and `README.md` (setup).
- `README.md` refreshed (current tool list incl. RAG/capture/doctor/update; points at `USAGE.md`); scaffold README template links `engine/USAGE.md`.

## [1.4.1] — 2026-07-15

Patch — sharper dependency signal + security.

### Changed
- `bin/rag_deps_check.py` (new, shared by `doctor.sh` + the freshness cron): dep freshness now separates **actionable** from **informational**. Actionable (drives exit 1 / opens an issue): a *pinned* dep drifted from or is behind `rag-requirements.txt`, **or** `pip-audit` finds a vulnerability in the RAG requirements closure. Transitive "newer available" is **informational only** — so `doctor`'s exit and the weekly issue stop firing on routine transitive drift (no alert fatigue), while real risk (a CVE, incl. in transitive deps) still alerts.
- `freshness.yml` uses the shared checker + `pip-audit`; opens/updates an issue only when actionable.
- Security audit is scoped to the requirements closure (`pip-audit -r`), so it reports vulns in what the vault runs, never in the audit tool's own deps.

## [1.4.0] — 2026-07-15

Additive — new freshness/update tooling; adopt with `bin/adopt.sh` (no vault changes required).

### Added — keep consumed components current
- `scaffold/rag-requirements.txt` — **pins** the RAG CPU-embedder stack (fastembed/onnxruntime/numpy/tokenizers/huggingface_hub) so `.rag/venv` is reproducible, not floating. `rag-setup.sh` now installs from it (with `RAG_PIP_PKG` as an unpinned override).
- `bin/doctor.sh` — one-shot freshness report: pinned engine vs latest tag + RAG venv drift from the requirements + newer PyPI releases + the embedding model. Deterministic; reports only.
- `bin/update.sh` — apply engine + dep updates in one step: bump the engine to the latest tag *within the same MAJOR*, `adopt`, re-sync the RAG venv. **Refuses a MAJOR bump**; leaves the pin staged, never auto-commits.
- `.github/dependabot.yml` — weekly bumps for the CI's GitHub Actions.
- `.github/workflows/freshness.yml` — weekly cron that flags newer releases of the pinned RAG deps by opening/updating an issue (no `claude`).
- `wiki-context` step 0 now offers `update.sh` (one-step) and points at `doctor.sh` for the fuller check.

Design: *checking* can be automatic (session check, CI cron, Dependabot); *applying* to a vault stays opt-in.

## [1.3.2] — 2026-07-15

Patch — opt-in addition.

### Added
- `rag-capture.sh`: opt-in **transcript path pointer**. With `RAG_CAPTURE_TRANSCRIPT_PATH=1`, records the session's `transcript_path` (from the hook JSON or `--transcript`) as a `Transcript: <path>` line — a **pointer only, never content** — so review-and-promote can open the `.jsonl` in-session to distill from the real conversation, with the boundary/secret gate. Off by default; chat content still never enters the vault or index. `wiki-context` review-and-promote documents the safe use of the pointer.

## [1.3.1] — 2026-07-15

Patch — fix.

### Fixed
- `rag-capture.sh` now handles a **workspace root** (a parent dir of several repos, the common "launch at the parent" pattern). Previously that dir isn't itself a git repo, so capture recorded nothing useful. It now scans immediate child dirs and captures each repo **touched** this session — dirty working tree, or a commit within `RAG_CAPTURE_SINCE` hours (default 12) — one `##` chunk per repo, skipping untouched ones. A single-repo cwd still captures just that repo.

## [1.3.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh` (creates `raw/sessions/`).

### Added — auto-capture (the memory design's "axis 1") + review-and-promote
- `bin/rag-capture.sh` — deterministic session auto-capture: appends metadata (timestamp, repo/branch/HEAD, changed file names, recent commit subjects, optional `--note`) to `raw/sessions/YYYY-MM.md`. **Never file contents/diffs/secrets.** Reads a SessionEnd hook's `cwd` from stdin. **The one script safe to run from a hook** — it never invokes `claude`, spawns an agent, or recurses (the safe inverse of the `.ai-os` fork bomb). Example SessionEnd hook in SCHEMA.
- `wiki-context` gains a **review-and-promote** step: skim new `raw/sessions/` entries and propose (human-gated) promotions to `memory/`, then prune the promoted raw. In-session only.
- `checkpoint` treats `raw/sessions/` as a distill input and prunes promoted session blocks.
- `recall.sh` weights curated notes above raw: `raw/` chunks get a `RAG_RAW_WEIGHT` (default `0.80`) penalty so the auto-captured pile never drowns curated hits.
- `raw/sessions/` added to `node-dirs.txt` (disposable scratch, distinct from the immutable `raw/articles|papers|transcripts`).

## [1.2.2] — 2026-07-15

Patch — fix.

### Fixed
- `lint.sh` and `lint-memory.sh` now prune the git-ignored `.rag/` dir (like `engine`/`.git`/`.obsidian`). Without this, a RAG-provisioned vault's `.rag/venv` vendored package markdown tripped the soft-wrap and dead-link checks, failing `checkpoint`'s lint. Derived sidecar is never linted.

## [1.2.1] — 2026-07-15

Patch — quality tune + fix. Existing vaults: `rag-setup.sh --force` to adopt the new default model, then `rag-build.sh` (the index re-embeds automatically when the model changes).

### Changed
- Default local embedder is now **`fastembed` + `BAAI/bge-base-en-v1.5`** (contextual, 768-dim, ~210 MB) instead of static `model2vec` — markedly better recall (test scores ~0.3 → ~0.6–0.7). model2vec/potion remains a lighter opt-in via `RAG_PIP_PKG`/`RAG_LOCAL_MODEL`.
- `rag_embed.py` honors a pinned library (`RAG_LOCAL_LIB` or `.rag/config.json` `lib`) so build and query never probe the wrong backend; auto-detects otherwise.

### Fixed
- Chunk line pointers now skip leading blank lines — a page's intro chunk points at its real first line (e.g. the `# Title`), not the blank above it. `##` sections were already exact.
- Incremental reuse is keyed on `(file sha, model)`, so changing the embedding model correctly invalidates and re-embeds the index (no mixed-dimension corruption).

## [1.2.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh`; existing vaults gain the runtime via `bin/rag-setup.sh`.

### Added — self-contained, packaged semantic recall
- `bin/rag-setup.sh` — provision a **git-ignored venv at `$WIKI/.rag/venv`** with a small CPU embedder (default `model2vec` + `minishlab/potion-base-8M`, ~30 MB, pure-numpy, offline), prefetch the model, write `.rag/config.json`. Idempotent.
- `new-wiki.sh` runs `rag-setup.sh` + an initial `rag-build.sh` automatically (skip with `--no-rag`), so *clone engine → generate vault → recall works* with **no server, no GPU, nothing external** after one install. Non-fatal if pip/network is restricted.
- `bin/rag_embed.py` — one shared embedding backend for build + query: in-process `local` (model2vec / fastembed / sentence-transformers, auto-detected) plus `ollama` / `openai` endpoints. Config precedence: env > `.rag/config.json` > default. Default backend is now **local**, not an endpoint.
- `rag-build.sh` / `recall.sh` use the vault's `.rag/venv` python and the shared module; batch-embed per file.
- CI: `py_compile bin/*.py`; scaffolder smoke test runs `--no-rag` (stays hermetic).

## [1.1.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh`; no migration.

### Added — semantic recall (optional RAG layer)
- `bin/rag-build.sh` — chunk every page by `##` heading, embed via a **local** endpoint (default Ollama `nomic-embed-text`; no cloud, no secrets), write a git-ignored, rebuildable `$WIKI/.rag/index.jsonl`. Boundary-filtered; incremental (only changed files re-embed).
- `bin/recall.sh` — embed a query, return nearest chunks as `file:line` pointers into the real pages (`--json` for machine use). Never replaces the markdown.
- `wiki-context` now auto-runs `recall.sh` so the user can **just prompt** without naming pages; `checkpoint` re-runs `rag-build.sh` after distilling, closing the distill→index→recall loop. Both degrade silently if no index / endpoint.
- `scaffold/gitignore.tmpl` ignores `.rag/`.
- All optional: a vault with no embedding endpoint never builds an index and falls back to the index-first map.

## [1.0.0] — 2026-07-14

First tagged release — the V1 framework.

### Node model
- Four lifecycle nodes (`repo`, `project`, `skill`, `memory`) + general knowledge (`entities`, `concepts`, `comparisons`, `queries`) + freeform **`notes/`** (domains via `tags:`, graduates to a structured node) + immutable `raw/`.
- Boundary law: every page carries `boundary: personal|work`; no secrets; content never crosses vaults.

### Skills (in-session only, never a hook)
- `wiki-repo` — ingest/refresh one repo page with git-ref provenance.
- `wiki-context` — session-start context router; runs the engine-version check (step 0).
- `checkpoint` — end-of-session project update + memory distill + native-memory prune + lint.
- `wiki-onboard` — one-time bulk seed of a fresh vault from existing native memory/repos/projects.

### Deterministic tooling (`bin/`, no LLM)
- `new-wiki.sh` (+ `scaffold/`, `scaffold/node-dirs.txt`) — one-command new-vault scaffold.
- `adopt.sh` — ensure a vault has the engine's current node folders (additive; run after a pin bump).
- `engine-version.sh` — report pinned vs latest engine by semver tag; flags MAJOR bumps.
- `lint.sh` — umbrella lint (memory + frontmatter-property + soft-wrap + skills-catalog); run by `checkpoint`.
- `gen-skills-index.sh` · `lint-memory.sh` · `reflow.sh` — catalog generation, memory validation, soft-wrap normalization.

### Conventions
- Soft-wrap: one physical line per paragraph/list item (renders in every Obsidian view; no per-machine setting).
- Wikilink-valued frontmatter (e.g. `repos`) must be a quoted YAML block list.
- Vocabulary: "vault" (the store) and "engine" (the shell); the boundary key is `boundary:`.

### Known gaps (see SCHEMA → Versioning & migration)
- `adopt.sh` is additive-only; a future MAJOR (node removal/rename, schema change) needs a dedicated `bin/migrate-*` + this MAJOR-version signal.
