---
slug: summary-volatility-marker-matches-inside-words
outcome: open
received: 2026-10-27
---

HANDOFF — engine defect report
slug: summary-volatility-marker-matches-inside-words
boundary: generic (engine-domain; contains no consumer-private context)

Title: lint-summary-volatility flags a summary whose word merely contains a marker, e.g. "spending" for "pending"

Engine version: v3.7.0
Still live at that release: reproduced on a scratch vault with the installed v3.7.0 bin/lint-summary-volatility.sh and the scaffold marker list.

Observed: a project page with `summary: "track AWS spending per ticket"` fails the gate with "summary matches volatility marker /pending/". The summary states identity, not state; "pending" occurs only inside "spending".

Expected: a marker matches as a whole word, so "spending", "upending", or "impending" pass while "pending review" fails. The marker list holds words, and the failure message itself quotes the marker as the state word it found.

Reproduction (generic):
  1. mkdir -p <tmp>/projects
  2. write <tmp>/projects/x.md with frontmatter: title X, status active, summary "track AWS spending per ticket", boundary work
  3. bin/lint-summary-volatility.sh --wiki <tmp>
  -> "✗ projects/x.md (status: active) — summary matches volatility marker /pending/"; "summary-volatility: 1 finding(s)"

Failure shape: fail-closed (blocks a commit; the workaround is rewording the summary or grandfathering a hash).

Already ruled out: the consumer's gates config sets no marker override, so the scaffold list is in use; the summary had no other marker word.

Suggested fix (HOLD LOOSELY — may be wrong): anchor each marker on word boundaries when building the match (for example `(^|[^[:alnum:]])marker([^[:alnum:]]|$)` under grep -E), keeping multi-word markers working; add a test that "spending" passes and "pending" fails.

Redactions: the consumer's real summary and page slug are replaced by a minimal example; paths by <tmp>.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
