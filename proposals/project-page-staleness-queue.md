---
slug: project-page-staleness-queue
outcome: partially-accepted
received: 2026-07-28
reason: "shape and status-gating kept; the signal is derived from git rather than the hand-maintained updated: field, which was measured drifting three days on two of three active pages, and a reviewed: marker was added — the alternative the proposal rejected — because without a clock reset the queue can never be drained to zero"
---

HANDOFF — engine improvement proposal slug: project-page-staleness-queue boundary: generic (engine-domain; contains no consumer-private context)

Title: Project pages have no staleness signal, so a decayed `Current state` is undetectable

Problem: the engine gives **repo** pages two independent decay signals — `ref`/`sha` provenance (freshness: has the source moved?) and a `verified:` stamp (correctness: did someone confirm the content was right, and when?) — and `bin/upkeep.sh` turns both into a drainable queue. **Project pages have neither.** Their volatile content lives in prose sections that SCHEMA marks as overwritten each session, and prose cannot be diffed against an external source the way a repo page can be diffed against a sha. `upkeep.sh` scans repo pages only; its own header notes that a project's status is "prose, not a machine-drainable list", which is an accurate description of why it was left out rather than an argument that it should stay out.

The consequence is a gap in coverage, not merely a missing convenience: a project page nobody has touched in weeks is indistinguishable from one confirmed accurate yesterday. Both render identically in the generated index, and every existing gate passes on both. This is the same **false-negative** shape that makes stale-clone drift worth engine support — the artifact that exists to surface project state is the one place the staleness is invisible.

Motivating use case (generic): a consumer vault's active project page went six days without its machine-read summary field being reconciled against reality, while the underlying system continued to change (a deployment completed, an alarm fired for the first time, a bake window elapsed). Nothing in the vault flagged the page for attention during that window. A companion proposal (`project-summary-volatility-gate`) addresses the specific case where the *frontmatter* holds a decaying fact, and it should be built first because it removes a whole class cheaply. But it cannot cover prose: a `Current state` section that is simply out of date contains no marker a deterministic gate can key on. Only elapsed time can flag that.

Proposed shape: extend `upkeep.sh scan` to enqueue project pages by `updated:` age, so they join the existing drainable queue (`next` -> act -> `done`) rather than introducing a parallel mechanism.

  **Gate on `status:`, and treat the statuses differently — this is the crux.** A
  naive age check over all project pages would be mostly noise, because for some
  statuses staleness is the *correct* state and flagging it is a false positive:
    - `paused` — a paused project is *supposed* to sit untouched; that is what the status means. Age carries no signal. Either exempt it, or give it a much longer threshold reflecting "should this still be paused?" rather than "is this current?" — a distinct and less urgent question.
    - `done` — exempt outright; a closed project is expected never to move again.
    - `planned` — arguably exempt for the same reason as `paused`, though an indefinitely-planned project may deserve its own much-longer horizon.
    - `active` — **the real target.** A project asserted to be active whose page has not been touched in N days is either not actually active (status is wrong) or is active with an unreconciled page (content is wrong). Both are findings worth queueing, and the distinction is exactly what draining the item resolves.

  The threshold should be a vault-level knob with a conservative default, not a
  hardcoded constant, since "how often should an active project move?" is a
  property of the consumer's cadence, not of the engine.

Alternatives considered:
  - **A `verified:`-style stamp on project pages.** Rejected as the primary shape: `verified:` works for a repo page because it records correctness *at a specific sha* — a point-in-time fact with an external referent. A project's `Current state` has no equivalent anchor, so the stamp would attest only "a human read this on date D", which is what `updated:` already conveys. It would add a field without adding information.
  - **Flag on the generated index instead** (e.g. render an age marker beside stale entries). Rejected: it makes the staleness visible but not *drainable*, and the queue mechanism for exactly this already exists — a second pattern for the same job invites the two to disagree.
  - **Calendar / external reminders.** Rejected: outside the engine's boundary, and per-machine rather than per-vault, so it would not travel with the vault.
  - **Do nothing; rely on the end-of-session ritual.** Rejected: the ritual only runs on projects the session actually touched, which is precisely the set that is *not* stale. The pages at risk are the ones no session has visited.

Design notes for the build:
  - **Sequence after `project-summary-volatility-gate`.** That proposal removes the frontmatter case cheaply and deterministically; this one should target only the residue it cannot reach. Building this first would generate items whose correct resolution is "apply the other convention".
  - **Reuse the existing queue's item shape** so `next`/`done` need no new verbs, and so a drain mixing repo-page and project-page items stays uniform.
  - **Keep `scan` offline.** The existing detector is deterministic and network-free by design; an `updated:` age check needs only the frontmatter and a date, so this adds no network surface — worth an explicit assertion, since the value of that property is that it never quietly erodes.
  - **A skip must be reported, not silent** — a project page missing `updated:` should be named as unassessable rather than passed over, or the tool recreates the original invisible-failure bug one level up.

Acceptance criteria:
  - `upkeep scan` enqueues `active` project pages whose `updated:` exceeds the configured threshold, and does not enqueue `done` pages.
  - `paused`/`planned` handling is explicit and documented (exempt or long-horizon), not an accident of the default.
  - The threshold is configurable per vault with a documented default.
  - Enqueued project items drain through the existing `next` -> `done` verbs with no new subcommands.
  - `scan` performs no network access (assertable the way the existing offline behavior is).
  - A project page lacking `updated:` is reported as unassessable rather than silently skipped.

Instruction to engine-dev: create the project in the engine-dev vault, build it, ship it in the engine so consumer vaults receive it on their next update. Sequence after `project-summary-volatility-gate`.
