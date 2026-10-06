---
slug: checkpoint-becomes-distill
outcome: partially-accepted
reason: "shipped across 3.0.0-3.3.0: the rename (3.0.0, with no alias, per the 2026-10-06 amendment); the mining offer removed (3.1.0, step 7, shipped first at the operator's request); linear lint-links and lint-memory (3.1.1, scaling requirements b and c); bin/distill-finish.sh, the declared publish route, buffer age-out and a judgement-only distill ending in SAFE TO CLOSE / NOT SAFE TO CLOSE (3.2.0); dogfood fixes for the route read and concurrent log.md appends (3.2.1) and for adoption writing canonical (3.2.2); changed-file lint and procedure keys (3.3.0). DECLINED: (d) the generated memory index, by operator choice (it would backfill ~180 notes and replace a hand-ordered section); the session manifest, replaced by --repo REVIEW lines the session attributes itself, because no script can tell a peer's branch from its own; and the acceptance bound written as a wall-clock ratio, replaced by a process-count assertion after the ratio proved unable to tell the old lints from the new on a CI-sized fixture."
received: 2026-10-06
---

HANDOFF — engine improvement proposal
slug: checkpoint-becomes-distill
boundary: generic (engine-domain; contains no consumer-private context)

Title: Replace `checkpoint` with `distill` — judgement in the skill, mechanics in one script, and an explicit "safe to close this session" verdict

Engine version: v2.8.1

Problem:
  - `skills/checkpoint/SKILL.md` is ~2,200 words. §0 (worktree isolation) and §3 (prune rules) are about two-thirds of it, and both are mechanics the model has to execute correctly by hand: which tree (worktree vs canonical) each step runs in, and whether to `integrate` or go by pull request.
  - Most of checkpoint's defect history is in those mechanics, not in its judgement: `checkpoint-prune-reads-a-tree-that-cannot-hold-the-buffer` (wrong tree), `checkpoint-integrate-step-diverges-a-pr-bound-vault` (wrong landing route), `checkpoint-prune-confirm-scope` (prune ceremony). Each fix added more prose rules; none removed the hand-executed step.
  - Part of its original purpose is now handled elsewhere: `rag-capture.sh` captures session metadata automatically, `recall-hook.sh` surfaces pages on every prompt, and `drain` / `update` / `verify` / `wiki-repo` write their own `log.md` lines and commits. In one consumer vault, a day with a drain and a checkpoint produced three log lines for the same work. What only checkpoint does is the judgement: what from this session is durable, and where it goes.
  - The `raw/sessions` prune asks for a promoted-or-not judgement on every block, but a block only holds repo, HEAD, recent commit subjects and a transcript path — all recoverable from git and the transcript. That judgement is expensive for what it protects.
  - Native-memory prune (§3) is close to a no-op in a vault that has already migrated native memory.
  - §6 ends every checkpoint by offering the `skill-candidates` pass. Mining and session wrap-up run on different schedules: mining needs weeks of record, and wrap-up happens every session. The offer is ritual at the end of every session.
  - Nothing in checkpoint answers the question the operator actually has at session end: **is it safe to close this session?** Background shells, open PRs, unmerged branches and undeleted worktrees all outlive a "checkpoint done" with no signal.

Motivating use case (generic): an operator runs several Claude Code sessions in parallel against one consumer vault and its repos. At the end of each, they want one invocation that records what was durable and then gives an explicit yes/no on closing the session — without disturbing peer sessions' worktrees, branches, PRs or leases.

Proposed shape:

  1. **Rename `checkpoint` → `distill`.** Keep `checkpoint` as a deprecated alias for one minor release, then remove it; the alias body says only "renamed to `distill`". Update every cross-reference (other skills, SCHEMA.md, README, lint-docs fixtures).

  2. **`distill` SKILL.md holds judgement only**, in this order:
     a. Project page: overwrite Current state, update Next steps, append Key decisions; keep `status:`/`summary:` current.
     b. Memory notes: promote durable facts as `preference` / `decision` / `lesson`, ≥2 wikilinks, supersede where needed.
     c. Procedure tagging (see 4).
     d. `log.md`: write a line **only if no other skill already logged this session's work**; otherwise amend nothing. The project page and notes are the record; the log is the index.
     e. Run `distill-finish.sh` (see 3) and relay its verdict.
     Target: under 700 words. No tree-selection or landing-route prose remains in the skill.

  3. **New `bin/distill-finish.sh` — every mechanical step, session-scoped, in fixed order:**
     - `lint.sh --wiki "$WORK"`; non-zero → stop, report, verdict NOT SAFE.
     - Land: read the vault's declared publish route (direct-to-main → `vault-worktree.sh integrate`; pull request → push `wt/<session>`, open the PR, report it as outstanding until merged, then `pull --ff-only`). The route is declared in the vault's config, not left for the model to infer from CLAUDE.md prose; missing declaration → fail-closed with a message naming the setting.
     - `gen-projects-index.sh` before lint, so index drift is never a lint failure the model fixes by hand.
     - `rag-build.sh` against canonical once the commit is on canonical `main`; skip silently if no `.rag/`.
     - `raw/sessions` **age-out** in canonical: delete month files whose newest block is older than a configured window (default 60 days). No per-block judgement. This is in-session and operator-initiated (inside `distill`), never a hook, so it stays within the Hard safety rule. Native-memory prune is dropped from the default path.
     - `vault-worktree.sh gc "$WORK"` for **this session's** worktree only; release this session's leases.
     - Then the **close check** (see 5). Exit 0 only if SAFE.

  4. **Procedure tagging, so mining counts instead of guesses.** Today `skill-candidates` finds repetition by clustering free `tags:` and reading prose, and a note that records only a conclusion cannot be counted as an occurrence. Add one optional frontmatter field to memory notes and project-page Key decisions entries written by `distill`:
       `procedure: <verb-object-kebab>` (e.g. `procedure: adopt-engine-release`)
     Rules: set it only when the note records a procedure that was *carried out* (steps done, not just a conclusion); before minting a new key, `distill` lists existing keys (`grep -h '^procedure:' memory/*.md | sort | uniq -c`) and reuses one when the steps match, so keys converge instead of fragmenting. `lint-memory.sh` validates the shape (kebab, single value). `skill-candidates` gains a first-pass count over `procedure:` keys (≥3 occurrences by `created:` across ≥2 weeks = candidate), keeping its existing tag/prose lens as the second pass for untagged history.

  5. **The close check — "safe to close this session".** `distill` ends with exactly one of:
       `SAFE TO CLOSE — distilled <n> notes, <project>; nothing outstanding.`
       `NOT SAFE TO CLOSE — <k> outstanding:` followed by one line per item with the command that clears it.
     Outstanding items, each **scoped to this session** so a parallel peer's work never blocks or gets touched:
       - **Running work in this session**: background shells, monitors, subagents still running. A script cannot see these — the skill text tells the model to check its own task list and report each running item. This is the one check the script can't do.
       - **Unmerged PRs this session opened**: in every repo the session touched, open PRs whose head branch this session created (session-id branch prefix, or recorded at creation). Open PRs from other sessions are listed as `info`, not blockers.
       - **Worktrees this session created** that still exist (vault `wt/<session>` and any repo worktree this session entered), and their branches if unmerged.
       - **Uncommitted or unpushed changes** in repos this session touched (session's own worktrees/branches; canonical checkouts only for paths this session wrote).
       - **Leases this session still holds.**
       - **Vault commit not yet on canonical `main`** (integrate failed with exit 3/4, or PR not merged).
     Which repos "this session touched" comes from a session manifest that `vault-worktree.sh ensure` / `lease` and the finish script append to (keyed by session id, in canonical per-machine state), not from scanning every repo on disk.

  6. **Parallel-session safety** (must hold throughout):
     - Every write and cleanup is keyed by session id; the script never removes, gcs, pushes or closes anything another live session owns. Leases are already shared state — read them to exclude peers, don't clear them.
     - `integrate` keeps its existing lock (exit 4 = another session holds it → report NOT SAFE with "re-run `distill-finish.sh`", don't spin).
     - Age-out takes the existing per-buffer lock from `rag-capture.sh` (v2.8.0) so it can't race a peer's SessionEnd append, and never deletes the current month's file.
     - `log.md` appends land through the worktree + rebase path like any tracked edit; the finish script retries a rebase conflict confined to `log.md` by re-appending, and reports any other conflict.

  7. **Remove the mining offer.** `distill` neither offers nor mentions running `skill-candidates`. `skill-candidates` stays the separate, manually-invoked mining skill: drop "or when `checkpoint` offers it" from its triggers, drop the `checkpoint` disambiguation's "offers this pass" clause, and delete the subagent/`spawn-session.sh` accept path that existed only for the offer (keep `spawn-session.sh` itself if anything else uses it; otherwise retire it). Optional, operator's call at intake: rename `skill-candidates` → `mine` for symmetry with `distill`.

Alternatives considered:
  - Trim checkpoint's prose and leave the scope as is (option B): fewer changes, but mechanics stay hand-executed and the per-block prune and duplicate log lines remain. Rejected; the defect history is in the hand-executed mechanics.
  - Keep the per-block `raw/sessions` prune: protects only data that git and the transcript already hold. Rejected for age-out.
  - Close check as a separate skill: the operator wants one end-of-session invocation; splitting it recreates the "done but not safe" gap. Rejected.
  - Free `tags:` for procedures instead of a dedicated field: tags already mix subject and type, which is why mining has to cluster them. Rejected for a single-valued `procedure:` key.
  - Detect "this session's" PRs by author alone: in a solo setup every PR has the same author, so peers' PRs would block. Rejected for session-scoped branch/manifest.

Acceptance criteria:
  - `skills/distill/SKILL.md` exists, under 700 words, contains no worktree-vs-canonical routing prose; `checkpoint` is a one-release alias.
  - `bin/distill-finish.sh` exists with tests: lint failure → NOT SAFE; integrate exit 4 → NOT SAFE naming the lock; PR-route vault never calls `integrate`; age-out never deletes the current month and holds the buffer lock.
  - Close check red-before-green tests: an open PR from this session's branch → NOT SAFE; an open PR from a peer session's branch → SAFE with an `info` line; a leftover own worktree → NOT SAFE; a peer's worktree → untouched and not reported as a blocker.
  - Two concurrent `distill-finish.sh` runs against one vault fixture both finish, neither touches the other's worktree/lease, and `main` contains both sessions' commits.
  - `lint-memory.sh` accepts a well-formed `procedure:` and rejects a malformed one; `skill-candidates` reports a candidate from three `procedure:`-tagged notes spread over ≥2 weeks with no other signal.
  - `distill` and `skill-candidates` reference each other only in disambiguation text; neither invokes nor offers the other.
  - Nothing new runs from a lifecycle hook (Hard safety rule); age-out runs only inside an operator-invoked `distill`.
  - Scan clean; no consumer identifiers.

Instruction to engine-dev: create the project in the engine-dev vault, build it, ship it in the engine so consumer vaults receive it on their next update. This flips defaults (renamed skill, prune → age-out, offer removed) and adds a frontmatter field, so run the design pass at intake.

---

AMENDMENT 2026-10-06 — scope after the 3.0.0 rename, plus measured scaling requirements

Status: the rename in "Proposed shape" step 1 shipped as v3.0.0, and the proposal's remaining scope is the `distill` redesign.

Corrections to the filed text:
  - Step 1: no deprecation alias. v3.0.0 removed `checkpoint` outright. An alias is a second description competing for the same prompts, and trigger evals measured routing loss on exactly that kind of overlap. Delete "one-release alias" from the plan and from the first acceptance criterion; `distill` is already the name.
  - Step 7 and the last two acceptance criteria say `skill-candidates`; the skill is now `mine`. Its triggers and disambiguation read `distill` where they read `checkpoint`.
  - Step 3 names `lint.sh` as the first finish step. Read it with the next section: it must not be the full-vault form.

Scaling requirements (added). The finish script and the pre-commit gate are the two places a session pays for vault size, and both run the full-vault lint today. Measured on one consumer vault of 187 memory notes and 82 projects, the full lint takes 17.6 s, of which `lint-links.sh` is 9.2 s and `lint-memory.sh` 6.8 s. On a synthetic copy three times the size, `lint-links.sh` took 81.9 s (about 9x) and `lint-memory.sh` 42.7 s (about 6x), so cost grows faster than the vault. A larger vault is where the speedup the redesign promises is wanted most.

  a. Changed-file lint. `distill-finish.sh` and the pre-commit gate lint only the files the session's branch changed against its base (`git diff --name-only <base>...HEAD`) and run the per-file gates on that set. Gates that are inherently whole-vault (link resolution of changed files' targets, catalog drift) read only what they need. The full-vault lint stays as `lint.sh` with no file list, and runs in CI and on the freshness schedule.
  b. `lint-links.sh` resolves each link against a page-name set built once, by sorting and joining, not by one `grep` over the name list per link. It must not need bash 4 features (associative arrays); the machines this runs on ship bash 3.2.
  c. `lint-memory.sh` makes one pass per note (or per vault) instead of spawning a subprocess for each frontmatter field it reads.
  d. The memory entries in `index.md` are generated from frontmatter, like the Projects and skills catalogs, from a one-line field each note carries (`summary:` if memory notes already have it, else added by `lint-memory.sh`'s rules). `distill` then stops hand-editing a file that reached 90 KB, and a drift check covers it like the other catalogs.

Acceptance criteria (added):
  - A fixture vault three times the baseline fixture's size lints in at most 4x the baseline's time, for `lint-links.sh` and for `lint-memory.sh` separately, taking the median of three runs of each. The measured ratios against v3.0.0 are about 9x and 6x, so the gap to the bound is wide enough to survive CI noise, and the test must be shown red against v3.0.0 before the fix. Do not assert on subprocess counts: `lint-links.sh` spawns a number of `grep` processes that grows only 3x here, and the 9x comes from each one scanning the whole name list, so a count passes against the defect.
  - Changed-file lint of a one-note branch on the 3x fixture takes at most 1.5x the time it takes on the baseline fixture.
  - The memory section of `index.md` regenerates byte-identically from frontmatter, and a hand edit to it fails the drift check.
  - Full-vault lint output is unchanged byte for byte on the baseline fixture.

Out of scope here, to be proposed separately: a check that new skills' names start with a verb (an engine `lint-docs.sh` rule, and the same rule for skills authored outside the engine).
