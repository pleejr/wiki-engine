---
name: drain
description: Drive the engine's proposal queue to empty and keep going until nothing is outstanding — intake each report, reproduce it, fix the CLASS, test red-before-green, ship, release, adopt into the consuming vault, and re-verify what the release just made stale. Runs the whole loop autonomously and stops only for decisions that genuinely need direction (a breaking change, destroying unrecoverable work, or a taste call the code cannot settle). Use when the user says "drain the queue", "work the queue until it's empty", "intake everything outstanding", "keep going until there's nothing left", or hands over a batch of reports. Distinct from `engine-proposal` (which files ONE report or intakes ONE arrival) and from `verify` / `update` (single passes this loop calls): drain is the outer loop that runs them until the work-list is empty and says so with evidence.
status: active
summary: the engine-dev outer loop — intake, fix the class, ship, release, adopt, re-verify, repeat until nothing is outstanding.
updated: 2026-08-12
---

# drain — run the engine-dev loop until nothing is outstanding

Engine work arrives as a queue: reports from consumer vaults, defects found while verifying, pull requests nobody merged. Handling them one at a time, with a check-in between each, turns a day of work into a day of questions. This skill is the **outer loop**: it holds the work-list, runs each item to *released and adopted*, and only interrupts for a decision the code cannot settle.

**Where it runs**: the engine repository (engine-dev side), with `gh` authenticated and `main` clean. `$WIKI_PATH` should point at a consuming vault, because a release is not finished until a consumer has it.

## 1. Build the work-list — "the queue" is not only proposals

Outstanding means all of these, and the loop is not done while any is non-empty:

```sh
bin/engine-proposal.sh queue              # open (awaiting intake) AND awaiting-merge
gh pr list --state open                   # fix branches, including ones from weeks ago
gh run list --branch main --limit 3       # is main itself green?
bin/lint-docs.sh && bin/lint-proposals.sh # the gates, before adding to them
"$WIKI_PATH"/engine/bin/doctor.sh         # is the consumer behind the latest tag?
"$WIKI_PATH"/engine/bin/verify-status.sh  # pages a release made verified-stale
"$WIKI_PATH"/engine/bin/upkeep.sh next    # the consumer's own queue
```

**An old pull request is work-list, not debt.** Read its diff before deciding its fate — it can hold a *better* answer than what shipped since. Check its closing comment before calling anything abandoned: a rebase-and-squash under another branch closes the original exactly the way a rejection does.

## 2. Per item: reproduce → shape → class → test → ship → adopt

Run this to completion for one item before starting the next. Half-finished items are how a loop loses track of what it proved.

1. **Reproduce at HEAD first.** A defect can be fixed incidentally and stay open on paper. If it no longer reproduces, find the commit that fixed it and pin it with a regression test rather than closing it quietly.
2. **Separate the observation from the prescription.** The reporter's fix can be wrong while the bug is entirely real. Judge it against the *mechanism* you just reproduced.
3. **Sweep for siblings before designing.** If one tool has the defect, ask which other tools share the pattern; fixing the instance leaves the class armed, and the class is usually four lines of grep away.
4. **Write the test so it fails first.** Then make it pass. A gate that has never been red proves nothing — and a gate that asserts *your implementation's shape* rather than the property will fail a better implementation later.
5. **Fold this cycle's own drift into this cycle.** A release changes counts, docs, and the consumer's repo page. Update them now. Leaving them to be "found" next round is what turns one loop into five.
6. **Ship it**: pull request, wait for CI *by run status* (a `gh pr checks` "no checks reported" is often dispatch lag, not a missing run), merge, tag, release.
7. **Adopt into the vault** with `update.sh`, commit the pin, apply any deferred page edit in a worktree, and re-verify what the release just made stale.

## 3. What the loop decides for itself

Decide and record the reason; do not ask:

- **Release level**, using the CHANGELOG's own SemVer rules — PATCH for a backwards-compatible fix, MINOR when a consumed component changes what it *does* or gains a knob.
- **Which shape to build**, including declining the reporter's suggestion. State the technical reason in the proposal's `reason:` field so it travels back to them. Taste is not a technical reason — see the vault's own preference on shipping a proposal as proposed.
- **Outcome**: `accepted` / `partially-accepted` / `rejected`, with the required reason.
- **Whether a finding is worth filing at all** — see §5.
- **Cleanup** that is provably reversible: branches whose pull requests merged, stale local refs, worktree retirement.

## 4. What stops the loop

Stop, report, and wait — these are the only ones:

- **A MAJOR/breaking change**, or anything needing a migration a consumer must run by hand.
- **Destroying work that has no other copy** — deleting an unmerged branch with no pull request, force-pushing over someone else's commits, rewriting published history.
- **A taste call the code cannot settle**: wording the user will read every day, a default that encodes how they like to work, a scope question where two readings produce materially different deliverables.
- **A gate that would have to be weakened to pass.** Never widen a guard to make your own change land; that is the one shortcut this engine keeps finding in its own history.
- **Anything outside the engine and its vault** — another repository, a remote system, anything that spends money.

Inbound proposals that arrive *mid-drain* are new work, not a reason to stop: finish the current item, then decide whether to continue into them or report and hand back.

## 5. Before filing a new finding, establish it

The loop generates its own findings, and an unestablished one costs more than it saves.

- **Reproduce it.** A symptom is not a defect until you have the mechanism.
- **Check the timeline.** A condition reported at session start may have been resolved since by an unattended hook or a concurrent session; a no-op is a timestamp question before it is a bug report.
- **Read what the forge already says** — a closing comment, a merged-PR list, a CHANGELOG entry — before characterising something as missing or abandoned.
- **Prefer fixing it in the current cycle** when it is contained and you are already in the code. File it separately when it needs its own design pass, and say which you chose.

## 6. Loop hygiene — the mistakes this skill exists to prevent

- **Measure before you change state.** Capture the before-number first; rebuilding an index or re-running a tool destroys the comparison you will want.
- **A fixture proves nothing until you assert its precondition.** If output is *missing*, suspect the fixture never emitted it — run the same fixture with the mechanism disabled as a control.
- **Age a fixture whose subject is time.** One built seconds ago stamps every file "now", so a fix that dates something backwards is indistinguishable from no fix.
- **`cmd | grep -q` under `set -o pipefail` can report failure via SIGPIPE.** Capture the output, then test it.
- **Never `git add -A`.** Stage explicit paths; a stray file in the working tree becomes a commit on `main`.
- **Do not move a correctness stamp further than you actually read.** `verified:` asserts the whole page at that sha.
- **Say which copy acted** when a tool replaces itself mid-run, and remember the ADVANCE half of a self-updating tool is always the old code.

## 7. Done means measured, not felt

The loop ends when every list in §1 is empty, and the report says so with the commands' own output — proposal queue drained, zero open pull requests, main green, lints OK, consumer on the latest tag with `verify-status` clean and `upkeep` drained. Then summarise: what shipped and at which versions, what was declined and why, what remains outstanding and whose call it is.

## Rules

- **In-session and human-initiated.** Never wire this to a lifecycle hook: the loop merges, tags and releases, and a hook whose trigger its own child can re-fire is the fork-bomb structure the engine's `CLAUDE.md` forbids.
- **Deterministic tools do the mechanics; judgement stays here.** `engine-proposal.sh`, `lint*.sh`, `update.sh`, `verify-status.sh` and `upkeep.sh` find and record the work — deciding *is it correct?* is this skill's job.
- **One item at a time, to completion.** Parallel intake belongs to a peer fleet, not to this loop.
