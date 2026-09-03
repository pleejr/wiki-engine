---
slug: checkpoint-mining-offer-can-use-native-agent
outcome: open
received: 2026-09-03
---

HANDOFF — engine improvement proposal slug: checkpoint-mining-offer-can-use-native-agent boundary: generic (engine-domain; contains no consumer-private context)

Title: `checkpoint` §6's accepted branch should run the mining pass through the host's native subagent tool, with the adapter as fallback — the adapter is the common-case failure today

Engine version: v1.73.4 — the tag this vault is pinned to. Re-read 2026-09-03: every line reference and count below was re-measured at the pinned commit on that date. The pin moved v1.73.3 -> v1.73.4 after this block was first drafted; `git diff --stat v1.73.3..<pin>` touched only `CHANGELOG.md`, `PROPOSALS.md`, `proposals/`, and `scaffold/rag-requirements.txt`, so no subject file of this proposal changed, and the line numbers below are the re-measured ones (the first draft's were consistently one high). The pin is one commit BEHIND the engine's `origin/main` (a proposals-ledger stamp), not equal to it.

Related proposals (both in `proposals/`, both `outcome: partially-accepted`, received 2026-08-17):
  - `accepting-the-mining-offer-should-spawn-the-session` — built the adapter seam (`bin/spawn-session.sh`), the thin contract, the fail-closed fallback, and the no-edge-back rule that §6 now carries.
  - `decouple-skill-mining-from-checkpoint` — moved the offer to the last step, after commit and integrate; overrode the criterion that `skill-candidates` hand verdicts back, so it now records them itself (§7). This proposal sits on the same seam and should be filed with both cited in Key decisions, so the history of the edge is in one place.

Problem (observed):
  - `skills/checkpoint/SKILL.md` §6 (lines 57-77, ~600 words) runs, on accept, `engine/bin/spawn-session.sh --cwd "$WIKI_PATH" --what … --prompt …` (line 65). `spawn-session.sh` requires a per-machine adapter at `${WIKI_ENGINE_SPAWN_ADAPTER:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/spawn-session}` (lines 12, 110). On a machine with no adapter installed every accept lands on the exit-3 printed fallback (lines 84-95) — the by-hand instructions §6 was written to eliminate, as line 69 concedes ("A machine with no adapter installed lands on the printed instructions, which is what this bullet used to be on every machine"). A freshly wired machine has no adapter, so the fallback is the default experience, not the edge case.
  - Lines 71-77 are four paragraphs re-arguing why offering is not calling, why the graph has no return edge, and what the section does not license. The recursion question is already settled by the always-loaded `engine/CLAUDE.md` Hard safety rule.
  - Line 65 uses a relative `engine/bin/…` path where every other command in the file uses `$WIKI_PATH/engine/bin/…`; §0 line 22 says engine tooling runs from canonical because the submodule is absent in a worktree, which is exactly the case where a relative path fails.

Host change that motivates this: the host (Claude Code) now has a native `Agent` tool — a fresh general-purpose subagent, or a `fork` subagent that inherits the parent's full context — that runs to completion and returns its final report to the parent. That shape satisfies all three guard clauses of the Hard safety rule on its own: it is started by an explicit operator accept, never by a lifecycle hook (re-entry); it is one agent (concurrency bound); it terminates and returns text (no self-requeue). The "no return edge" prose becomes moot: the return edge is a report, not an invocation.

Assumption, now measured rather than assumed: a subagent cannot pose `AskUserQuestion` to the operator. Confirmed 2026-09-03 from inside a running subagent on this host — the tool set it is given contains no `AskUserQuestion`, and no other channel back to the operator mid-run. Scope of that measurement: one host version, one subagent type; it does not cover every host a consumer vault may run under. If a host does expose it, the split in (e) below is unnecessary and the whole pass can run in the subagent, so keep (e) conditional on the host rather than hard-coded.

Motivating use case (generic): an operator finishes `checkpoint`, accepts the mining offer, and wants the ranked candidate report in front of them without installing a per-machine adapter or opening a second pane — while the develop/discard/defer questions still go to a human and the verdict notes are still written by the skill that owns them.

Proposed shape: (a) Native branch ahead of the adapter. On accept, `checkpoint` starts the host's `Agent` (fresh, or `fork` to inherit what this session just wrote) with a prompt of the form: "Run the `skill-candidates` mining pass read-only over `$WIKI_PATH`: return the ranked candidate report with dated evidence and the catalog-overlap check. Ask no questions; write nothing." The parent then runs `skill-candidates` §6a (the develop/discard/defer questions, `AskUserQuestion`, batches of ≤4) and §7 (record verdicts in its own worktree and commit) in-session. (b) `spawn-session.sh` stays as the fallback for hosts with no native agent tool, or when the operator explicitly wants a separate *interactive* session; its adapter contract stays in `USAGE.md`. It is already fail-closed in the right direction (exit 0 with no handle is treated as not started, lines 167-169) — keep it, do not delete it. (c) Cut §6 to ≤150 words: the offer, the two outcomes (defer writes nothing; accept starts the pass), the one-line why-here ("mining reads the notes this pass just committed; the worktree is retired so a run opens its own"), and the one-clause rule "never from a lifecycle hook (engine `CLAUDE.md`)". (d) Fix the relative path at line 65 to `$WIKI_PATH/engine/bin/…`. (e) Split `skill-candidates` into a read-only mining mode (§1-§6: bar, evidence queries, candidate shapes, overlap check, report — subagent-safe) and an in-session verdict mode (§6a-§7: questions, record). §7's assertions "This skill still invokes nothing" and "never be invoked by it" need one sentence of adjustment: a subagent returning a report to the session that offered it is data flowing back, not an invocation edge into `checkpoint`.

Alternatives considered:
  - Keep adapter-only — rejected: the fallback is the common case on a fresh machine and the adapter is a second thing to install and keep in sync.
  - Let the subagent record verdicts too — rejected under the stated assumption: it cannot ask the operator, and the questions are the part that needs a human; recording without asking would settle candidates the skill says it must never settle.
  - Run the mining pass inline in the `checkpoint` session — rejected by `decouple-skill-mining-from-checkpoint` already: the notes must be committed first, the worktree is retired, and the verdicts are their own unit of work.

Acceptance criteria:
  - On a machine with no adapter file, accepting the offer produces the ranked candidate report in the same session and the operator is then asked develop/discard/defer per candidate. Control: today the same accept prints by-hand instructions and `spawn-session.sh` exits 3.
  - Nothing spawned can reach `checkpoint`: the subagent prompt forbids writes and its only output is text; a grep of the new §6 for `checkpoint` invocation inside the accept branch is empty.
  - `checkpoint` §6 ≤150 words (`awk` over the section); no relative `engine/bin` path remains in `checkpoint` (`grep -n '[^$/]engine/bin' skills/checkpoint/SKILL.md` returns no line inside §6; control: today lines 55 and 65 match, and 65 is the one in §6).
  - `skill-candidates` states which sections are subagent-safe and which require the operator.
  - `spawn-session.sh` still passes its existing behaviour: exit 0 with no handle → treated as not started.
  - The two related slugs are cited in the project's Key decisions.

Redactions: none — the only machine-specific fact (adapter absent) is stated as a condition, not a path.

Instruction to engine-dev: this flips a default (native before adapter) on a safety-adjacent seam, so run the design pass. The `AskUserQuestion`-from-subagent question is already measured (see above — a subagent's tool set has none), so (e) is needed on this host; re-measure it on yours rather than trusting a consumer's reading of one host version. Then create the project under this slug, build, ship.
