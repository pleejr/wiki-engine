---
slug: bare-status-ignores-submitted-markers
outcome: open
received: 2026-07-29
---

HANDOFF — engine defect report
slug: bare-status-ignores-submitted-markers
boundary: generic (engine-domain; contains no consumer-private context)

Title: Bare `engine-proposal.sh status` reports nothing for proposals submitted through `submit`/`push`

Engine version: v1.46.0
Still live at that pin: confirmed at the pinned v1.46.0 and at `origin/main`,
which is currently the same commit as that tag, with the slug-collection loop
unchanged. Not a stale report.

Observed: A bare `status` (no `--slug`) reports no proposals at all and prints

    no handoff blocks stashed on THIS machine (.engine-proposal/).

while `<vault>/.engine-proposal/` contains **six** `*.submitted` markers — four of
them written that same day by `submit`/`push` themselves. Querying any one of
those slugs with `--slug` correctly returns `SUBMITTED, not yet merged`, so the
state is present, correctly named, and readable; only the bare listing cannot see
it.

Mechanism: the slug-collection loop in `do_status` globs
`"$VAULT"/.engine-proposal/*.outbox` and nothing else. `.outbox` is the *legacy*
copy-paste artifact, which the current channel no longer produces — so the bare
listing enumerates exactly the artifact class that has been retired and ignores
the one the supported path writes. The skill documentation states the opposite:
that a bare status sees "legacy outbox blocks, **and** the prepared/submitted
markers `submit`/`push` leave behind." Code and documented contract disagree.

Expected: A bare `status` lists every proposal this machine has a local record
of, including `.submitted` markers, as documented.

Reproduction (generic):
  1. From a consumer vault, `submit` then `push` a proposal.
  2. Confirm the marker exists: `ls <vault>/.engine-proposal/` -> `<slug>.submitted`
  3. `engine-proposal.sh status --vault <vault>`
     -> reports no proposals; prints the "no handoff blocks stashed" line
  4. `engine-proposal.sh status --vault <vault> --slug <slug>`
     -> `SUBMITTED, not yet merged`

Failure shape: **fail-open.** It does not refuse or error — it returns a
well-formed, confident answer that is wrong, which is the shape nothing surfaces.
The specific harm is the duplicate-resend trap this subcommand exists to prevent:
a consumer asks "is anything outstanding?", is shown nothing, and re-sends work
that is already a live pull request. The printed caveat ("the outbox is
git-ignored and per-machine, so this is not evidence that nothing is
outstanding") partially mitigates it, but it explains the *legacy* limitation and
reads naturally as "the outbox is empty" rather than "this command cannot see
submitted proposals at all" — so it points away from the real cause.

Worth noting the `unknown`-vs-`open` distinction is what this silently degrades.
That distinction is documented as the thing telling a consumer whether re-sending
is correct, and it is only reachable via `--slug` — which requires already knowing
the slug you are trying to look up.

Already ruled out:
  - Not a ledger or resolution-horizon problem: `--slug` resolves correctly
    against the same `origin/main` ref in the same invocation style, and prints
    the horizon it used.
  - Not missing or malformed markers: all six exist with correct names and
    plausible timestamps, and `--slug` reads them.
  - Not an artifact of pointing `ENGINE_REPO` at a separate clone to work around
    the submodule-guard defect: markers are written under the vault directory
    either way, and `--slug` finds them there.
  - Not permissions: the same process wrote and later read those files.

Suggested fix (HOLD LOOSELY — may be wrong): include `*.submitted` (and any
`*.prepared`) in the bare-listing glob, de-duplicated by slug so a proposal with
both markers reports once. Whichever way it is resolved, the documented contract
and the code should be made to agree — a doc promising a guarantee the code does
not provide is how this went unnoticed, since the caveat made an empty result look
expected.

Redactions: absolute paths replaced with `<vault>` consistently; the vault name,
its organization, and the local username removed. Marker filenames are described
by count rather than listed, as the slugs are not needed to reproduce.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
