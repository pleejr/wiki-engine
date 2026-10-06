---
slug: checkpoint-becomes-distill
outcome: open
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
