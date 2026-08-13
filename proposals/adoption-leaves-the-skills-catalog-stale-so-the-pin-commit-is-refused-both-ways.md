---
slug: adoption-leaves-the-skills-catalog-stale-so-the-pin-commit-is-refused-both-ways
outcome: open
received: 2026-08-13
---

HANDOFF — engine defect report
slug: adoption-leaves-the-skills-catalog-stale-so-the-pin-commit-is-refused-both-ways
boundary: generic (engine-domain; contains no consumer-private context)

Title: Adopting a release that ADDS A SKILL leaves index.md's skills catalog stale and reconciles it nowhere, so the pin-bump commit fails lint as gitlink-only and fails the guard once index.md is staged beside it

Engine version: v1.57.0
Still live at that pin: reproduced at v1.57.0 while adopting v1.54.3 -> v1.57.0, which adds the `drain` skill. Both refusals were observed in one session, in order, and the mechanism was then read at the pinned tag rather than inferred: `grep -n "gen-skills-index" bin/update.sh bin/adopt.sh` returns NOTHING, so no code path in the adoption route reconciles the catalog that `adopt.sh` has just invalidated by linking a new skill.

Observed:
  Following the remedy `update.sh` prints — `git -C <vault> commit engine -m "Bump engine"`,
  pointer only, which v1.52.0 made legal in canonical on purpose — fails:

    vault-worktree: allowing a submodule-pointer-only commit in canonical (a worktree cannot hold one).
    drift: <vault>/index.md skills catalog is stale — run gen-skills-index.sh
    lint: FAILURES above
    pre-commit: vault gate FAILED (see above).

  So `guard` allows it and `lint.sh` refuses it. Regenerating the catalog and staging the
  one file that fixes lint then inverts which gate refuses:

    vault-worktree: refusing a commit in the CANONICAL checkout (<vault>).

  Neither staged set can be committed in canonical. Measured both directions:

    | staged set        | guard                  | lint                  | result   |
    | engine            | allows (gitlink-only)  | FAILS (catalog stale) | refused  |
    | engine + index.md | REFUSES (canonical)    | not reached           | refused  |

  The pre-commit hook's own header states the order — "two independent checks, in the
  order that fails cheapest first" — so guard runs first and lint second, and the two
  staged sets fail at different stages.

Expected:
  Adopting a release should leave the vault in a committable state. Two specific
  expectations, either of which alone would close this:
  (a) `adopt.sh`/`update.sh` should reconcile any generated region their own actions
      invalidate. Linking a skill is what makes the catalog stale; nothing else in the
      session did it, so nothing else should have to notice.
  (b) The commit the engine instructs the operator to make should pass the engine's own
      gates. v1.52.0's carve-out exists precisely so the pin can be committed in
      canonical; a release that adds a skill makes that carve-out unreachable in exactly
      the case it was built for.

Reproduction (generic):
  1. Take a vault with the write-time gate armed: `core.hooksPath` points at a pre-commit
     that runs `vault-worktree.sh guard` and then `lint.sh`. No worktree need be open.
  2. Pin `engine/` to any tag EARLIER than a release that adds a skill.
  3. Run `engine/bin/update.sh`. It advances the pin, runs `adopt.sh` (which prints
     `ADOPTED: link skill <name> -> <vault>/engine/skills/<name>`), and prints the
     pointer-only commit as the next step.
  4. Run that printed command verbatim, in canonical.
     -> guard prints its gitlink-only allow; lint fails with `skills catalog is stale`;
        the commit is refused.
  5. Run `engine/bin/gen-skills-index.sh --wiki <vault>`, `git add index.md`, commit again.
     -> guard refuses the commit as canonical. The commit is refused.

Failure shape: fail-closed

  Nothing is corrupted, both refusals print their reasons, and the exit statuses are
  non-zero. The cost is a detour, not data. It is filed anyway for one reason: the
  remedies still on offer in canonical are `WIKI_WORKTREE=0` and `--no-verify`, and the
  v1.52.0 source comment names that outcome itself — "turning isolation off for the whole
  command to land one legitimate commit, which is how a gate trains its user to bypass
  it." The carve-out was built to stop training that bypass; a skill-adding release
  re-arms it one component over.

Already ruled out:
  - NOT the generator resolving the wrong tree. `generators-resolve-wiki-path-not-session-worktree`
    (accepted, v1.49.0) already fixed that, and I confirmed the fix holds: from a session
    worktree, `gen-skills-index.sh --wiki <worktree>` finds the skills (it resolves
    `engine/skills/*/SKILL.md` relative to its OWN location in canonical, not relative to
    `--wiki`) and writes the spliced region into the worktree's own `index.md`. The write
    side is correct; nothing calls it.
  - NOT the guard being too strict about `index.md`. Staging ordinary tracked content in a
    shared tree is the exact clobber the guard exists to refuse, and a concurrent session
    may legitimately be editing `index.md`. I do not think the carve-out should be widened
    to admit it — see the suggested fix.
  - NOT specific to a stale or dirty vault. The tree was clean and level with
    `origin/main` at step 3, and `wire-machine.sh --check` reported the machine converged.
  - NOT the repo-page path from `update-writes-a-page-canonical-refuses-when-no-worktree-is-live`
    (v1.54.1). That deferral worked correctly here; no repo page was written. This is the
    same SHAPE one component over — a generated region rather than a tracked page.

Suggested fix (HOLD LOOSELY — may be wrong):
  Reuse the machinery `update.sh` already has, rather than touching either gate.
  `update.sh` lines ~147-151 resolve `PAGE_TREE="$(resolve_wiki_root "$WIKI")"` and set
  `defer_page=1` when `canonical_commit_gated "$WIKI"` is non-empty — deferring the repo
  page instead of writing it where it cannot be committed. The skills catalog wants the
  same treatment and no new concept:
    - regenerate it into `PAGE_TREE` (the caller's worktree when they are in one), so the
      file lands in the branch that will carry the pin; and
    - when a canonical commit would be refused, do not write it — print the same kind of
      "apply this on your branch" notice already used for the deferred page.
  That leaves the gitlink-only carve-out useful for a PATCH bump, which genuinely is a
  pointer-only change, and stops a MINOR-with-a-skill from being a two-file change that
  neither gate will accept.

  A second, smaller option if the above is unwanted: have `lint.sh`'s catalog check name
  the worktree route in its remedy line, so the operator is not left with only the two
  bypasses. That is wording, not a fix, and I flag that the same engine has already
  declined a wording-only fix on this exact code path for good reason
  (`update-writes-canonical-against-the-worktree-convention`, part 1).

Redactions:
  - The vault's filesystem path, name, org and remote are replaced by `<vault>` throughout,
    consistently, so the reproduction remains runnable by substitution.
  - The skill named in the `ADOPTED:` line is `drain` in the real transcript; it is the
    engine's own v1.57.0 skill, so it is left unredacted as evidence. `<name>` is used in
    the generic reproduction because any added skill should do.
  - Nothing else was removed. No credentials, tokens or key material were present in any
    of the quoted output.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification. Note that I adopted nine commits at
once, so I did not isolate which release first made this reachable — only that it
reproduces at v1.57.0 with a skill-adding release. A PATCH-only bump should still commit
pointer-only in canonical, and I did not test that path.
