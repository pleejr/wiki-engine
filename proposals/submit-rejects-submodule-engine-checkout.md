---
slug: submit-rejects-submodule-engine-checkout
outcome: open
received: 2026-07-29
---

HANDOFF — engine defect report
slug: submit-rejects-submodule-engine-checkout
boundary: generic (engine-domain; contains no consumer-private context)

Title: `engine-proposal.sh submit` rejects the submodule engine checkout it defaults to

Engine version: v1.46.0
Still live at that pin: reproduced at the pinned v1.46.0, and `origin/main` is
currently the same commit as that tag with the guard line unchanged — so it is
live at HEAD too, not merely at an old pin.

Observed: From a consumer vault whose engine is a pinned git submodule, `submit`
passes the boundary scan and then dies:

    no engine checkout at <vault>/engine (set ENGINE_REPO to a clone you can branch in)

The guard is a directory test on the checkout's `.git`. In a git submodule, `.git`
is a *file* containing a `gitdir:` pointer, not a directory, so the test is false
for every consumer that uses the documented default path. The resolver's own
comment states that the vault's pinned submodule is the engine checkout every
consumer already has — so the default the code chooses and the guard that
validates it contradict each other. Nothing about the checkout is actually
deficient: it is a complete work tree (`rev-parse --is-inside-work-tree` is true,
and it has the upstream remote), so branching, committing and pushing all work
there.

Expected: `submit` proceeds against the pinned submodule with no `ENGINE_REPO`
set, because that is both the documented default and a usable checkout.

Reproduction (generic):
  1. In a consumer vault whose engine is a pinned submodule at `<vault>/engine`,
     with `ENGINE_REPO` unset.
  2. Run `submit --vault <vault> --slug <slug> --file <boundary-clean block>`.
  -> scan reports clean, then: `no engine checkout at <vault>/engine (set
     ENGINE_REPO to a clone you can branch in)`
  3. Confirm the checkout is fine and only the test is wrong:
     `file <vault>/engine/.git` -> ASCII text (`gitdir: ...`)
     `git -C <vault>/engine rev-parse --is-inside-work-tree` -> true

Failure shape: fail-closed — it refuses and nothing is lost.

  One note on urgency despite the shape: what it closes is the *only* sanctioned
  upstream channel, and its printed remedy points at a separate clone that a
  consumer vault by definition does not have. The natural next move for someone
  who wants to get unblocked is to edit the pinned submodule in place — precisely
  the time bomb the skill exists to warn against. So the cost is not the refusal
  itself but the workaround it invites.

Already ruled out:
  - Not detached HEAD. The submodule sits on a detached HEAD, but `submit`
    deliberately branches from `origin/main` rather than HEAD, so that is not the
    obstacle; the guard fails before any branching is attempted.
  - Not permissions or a missing remote. The checkout has the upstream remote and
    is readable/writable.
  - Pointing `ENGINE_REPO` at the submodule does not help — the same directory
    test runs against whatever path is supplied.
  - A separate full clone with `ENGINE_REPO` set does work; that is how the
    accompanying proposal was submitted.

Suggested fix (HOLD LOOSELY — may be wrong): Test the property actually required
— that the path is a git work tree that can be branched in — rather than the
shape of its `.git` entry, e.g. `git -C "$eng" rev-parse --is-inside-work-tree`.
Accepting a `.git` file as well as a directory would also clear the symptom but
keeps a test that is coupled to git's storage layout.

Separate, smaller observation from the same run: the `To publish:` command that
`submit` prints omits the `ENGINE_REPO` that the invocation required, so a
consumer who used the workaround and then follows the printed line verbatim gets
the same rejection at push time. Whatever fix lands, the printed remedy should
reproduce the environment the prepared branch actually lives in.

Redactions: absolute filesystem paths were replaced with `<vault>` consistently
throughout; the vault name, its owning organization, the remote URL, and the
local username were removed. No error text was dropped — only path-substituted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
