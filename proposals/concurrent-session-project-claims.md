---
slug: concurrent-session-project-claims
outcome: partially-accepted
received: 2026-07-29
reason: "the presence half is ACCEPTED and shipped as `vault-worktree.sh claim` — per-project, acquired by the context-loading skill, naming the holder and its activity age, stale-not-deleted — but recorded on the EXISTING lease rather than in a new store with a PreToolUse heartbeat: liveness, staleness and the provably-finished evidence are already decided in one place there, and a second presence mechanism can disagree with the first about who is live, which is worse than no answer. The mutation-deny tier is REJECTED for now, on three grounds: the hook surface is machine-global, so a deny gate fires in sessions that have nothing to do with the vault; the proposal's own open question 2 has no sound answer, because state-changing is not a property of a tool (the same Bash tool is also the read-only surface) and a command-shape deny-list is guessable and leaks, as the proposal says itself; and its recommended answer to open question 3 — allow-with-notice when the store is unreadable — means the hard edge disappears exactly when the mechanism breaks, which makes it a notice claiming to be a gate. Ship visibility first; a hard edge should be designed from evidence that visibility was insufficient. Cross-machine claims declined as the reporter suggested — the record is per-machine and says so"

HANDOFF — engine improvement proposal
slug: concurrent-session-project-claims
boundary: generic (engine-domain; contains no consumer-private context)

Title: Per-project session claims so concurrent sessions don't converge on the same project work

Problem: A vault's project pages are its unit of work, but nothing in the engine
tells a session that another live session is already working the same project.
Two collision classes are already covered: vault-content edits collide as git
merge conflicts (fail-closed, nothing lost), and repo working-tree collisions are
solved by a per-session worktree. The uncovered class is the work a session
performs *outside* version control — investigative reads, and especially
state-changing actions issued against external systems via API or CLI. That work
has no coordination surface at all, so two concurrent sessions can converge on
one project, duplicate the investigation, and contend over the side effects,
with neither able to see the other. The human discovers the overlap from the
consequences.

Motivating use case (generic): A consumer vault runs several concurrent sessions
on one machine (separate terminals). Two of them independently load context for
the same project page. One begins investigating; the other begins issuing
state-changing commands against the external systems that project targets.
Nothing surfaces the overlap to either session or to the human.

Proposed shape: A *claim* — advisory presence with one hard edge — not a lock.

  - Unit: the project page slug. It is already the vault's unit of work, and
    project frontmatter already carries a `repos:` list, which gives a later
    overlap-detection refinement for free.
  - Acquisition happens where the project is already resolved: the context-loading
    skill claims the project slug it loads. No new user-facing step.
  - Liveness by activity mtime, not a heartbeat process: a deterministic
    PreToolUse hook touches the holder's claim on every tool call. A session that
    dies by interrupt or a closed terminal simply stops touching it, so staleness
    is self-evident and expressible as "last activity N minutes ago". There is no
    release step to forget and no PID, which would be meaningless across machines.
  - Release on SessionEnd. Both hooks are deterministic and terminating and spawn
    no `claude`, so the engine's hard safety rule is untouched.
  - Two-tier semantics — the substance of the proposal:
      * read-only / investigative work while a live foreign claim exists →
        fail OPEN, with a prominent notice naming the holder and its activity age.
      * state-changing actions while a live foreign claim exists →
        fail CLOSED: deny, name the holder and age, and let the human override
        deliberately.
  - A claim whose activity age exceeds a threshold is treated as absent and
    reported as stale; it is never silently deleted, so the human can see that a
    session died mid-work.
  - The record carries identity and timing only — no credentials, no content.

Alternatives considered:
  - A true mutual-exclusion lock. Rejected: it is advisory against an agent whose
    instruction to check it can be compacted out of context; stale locks are the
    normal outcome rather than the edge case, because sessions end by interrupt
    and not by clean release; so it blocks at the wrong moments and trains the
    human to force-break it, which removes the gate entirely. Multi-project
    sessions additionally introduce lock-ordering.
  - Git-committed claims in the vault. Rejected as the enforcement layer: a claim
    must be pushed to be visible and pulled to be seen, so acquisition itself
    races and the record is least trustworthy exactly when contention is highest.
    It also adds a commit per session. Viable only as best-effort informational
    presence.
  - A heartbeat daemon or timer. Rejected: a process to supervise, and it reports
    the liveness of the heartbeat rather than of the work. Tool-call mtime costs
    nothing and measures the thing that matters.
  - Per-project remote branch names as the claim. Rejected as insufficient alone:
    it says nothing about work performed outside version control, which is
    precisely the gap. Still a reasonable zero-machinery stopgap.
  - Status quo (the human remembers). This is the current behavior and the reason
    for the proposal.

Open questions for intake (design input, not settled):
  1. Topology. Recommendation is local-only enforcement — a per-machine,
     git-ignored claim store — which covers concurrent sessions on one machine.
     Cross-machine concurrency would require published claims, reintroducing the
     push/pull race above; suggest at most best-effort informational presence
     there, and intake should decide whether it is in scope at all.
  2. What defines the state-changing tool surface. A deny-list of command shapes
     is guessable and will leak. Intake should decide whether the gate keys on
     tool identity, on a declared per-project resource scope (the frontmatter
     `repos:` list is one candidate), or on something narrower still.
  3. The mechanism's own failure, stated as a tension rather than resolved: if the
     claim store is unreadable or absent, does the mutation gate deny or allow?
     Denying is the conservative reading but bricks every state-changing action in
     every session on a filesystem problem, which ends with the hook disabled and
     no gate at all. Recommendation is therefore allow-with-loud-notice, i.e. the
     mechanism's absence returns exactly today's behavior — but this trades a
     fail-open failure mode for availability, and it is intake's call.

Acceptance criteria:
  - Two concurrent sessions on one machine resolve the same project; the second
    reports the first's claim, including its activity age.
  - A session killed by interrupt leaves a claim that a later session reports as
    stale and proceeds past: no manual cleanup, no permanent block.
  - A state-changing tool call from a non-holder while a live foreign claim exists
    is denied, and the denial names the holder and the activity age.
  - A read-only tool call in the same situation proceeds and emits the notice.
  - Two sessions on two different projects never gate each other.
  - No hook in the mechanism spawns `claude`; each is deterministic and terminates.
  - The claim record contains no credentials and no work content.
  - With the claim store removed, sessions behave as they do today (subject to
    question 3 above).

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
