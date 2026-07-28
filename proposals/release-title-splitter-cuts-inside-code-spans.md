---
slug: release-title-splitter-cuts-inside-code-spans
outcome: accepted
received: 2026-07-28
reason: "accepted as reported, with the mechanism the report identified — the strip ran before the split, destroying the markers the split needed. Shape (a), a code-span-aware pass; also extracted to bin/release-title.sh so CI can exercise logic that previously ran only on a tag push"
---

HANDOFF — engine defect report
slug: release-title-splitter-cuts-inside-code-spans
boundary: generic (engine-domain; contains no consumer-private context)

Title: The release-title clause splitter cuts at punctuation inside a code span, because
the step that strips code markers runs before the step that needs them

Engine version: v1.42.1

Still live at that pin: confirmed by re-running the workflow's own pipeline verbatim
against the v1.42.1 CHANGELOG summary at that tag — it reproduces the mangled title
exactly. Not inferred: v1.42.1 published to the releases page with the wrong title and was
retitled by hand afterwards.

Observed:
  The release title is derived in `.github/workflows/release.yml` from the CHANGELOG
  section's first prose line, through a four-stage `sed` pipeline. Stage 2 strips markdown
  emphasis and backticks; stage 3 truncates at the first `.`, `;` or `:` followed by
  whitespace. For a summary whose first clause contains an inline code token ending in a
  colon, the published title is cut at that colon:

      summary: "Patch — the `Proposal:` citation convention required a placement that
                the project's own workflow made impossible, so following the ..."

      stage 1 (strip Minor/Patch/Major prefix):
        the `Proposal:` citation convention required a placement ...
      stage 2 (strip * and `):
        the Proposal: citation convention required a placement ...      <- markers gone
      stage 3 (cut at [.;:] + whitespace):
        the Proposal:
      stage 4 (strip trailing punctuation):
        the Proposal

      published title: "<vX.Y.Z> — the Proposal"

Expected:
  Punctuation *inside* a code span is not a clause boundary and should not end the title.
  The intended behaviour — take the headline clause, cap at 80 chars on a word boundary —
  is right; only the boundary detection is wrong.

Reproduction (generic):
  1. Write a CHANGELOG section whose first prose line contains an inline code token that
     ends in a colon, e.g. a trailer or field name in backticks, inside the first clause.
  2. Tag and push, or run the title-derivation pipeline from `release.yml` directly
     against that line.
  -> the title is truncated at the code token's colon.

Failure shape: fail-open

  The release publishes successfully and reports success; only the title is wrong, and
  nothing in the workflow can tell a correctly-derived title from a mangled one. The cost
  is cosmetic but permanent-looking on a public releases page, and it is silent — it was
  noticed by a human reading the page, not by any check. Note this is the SECOND defect in
  this same derivation: a prior fix addressed `cut -c1-60` slicing mid-word and leaving raw
  markdown in the title. The pipeline has now been wrong twice in the same place, which is
  itself evidence about the approach rather than about either bug.

Already ruled out:
  - Not the length cap: the mangled title is far under the 80-char limit, so the word-
    boundary back-off never ran.
  - Not the emphasis strip on its own: removing `*` is harmless here; it is specifically
    the backtick strip preceding the clause split that matters.
  - Not a CHANGELOG formatting error: the summary is well-formed and renders correctly
    everywhere else (the release *body* is fine — only the derived title is affected).
  - Not fixable by reordering alone in the obvious direction: splitting BEFORE stripping
    markers would leave a stray backtick in the title, so the ordering is load-bearing in
    both directions and needs an actual code-span-aware pass.

Suggested fix (HOLD LOOSELY — may be wrong):
  The root shape is that stage 2 destroys the information stage 3 depends on. Options, in
  the order I'd weigh them:

  (a) Make the split code-span aware: mask inline code spans (and their contents) before
      the clause split, then unmask after — so punctuation inside backticks is never a
      candidate boundary, and the markers are still stripped from the final output.
  (b) Drop `:` from the boundary set, keeping `.` and `;`. Much smaller, but it is a guess
      about which punctuation authors use for real clause breaks, and a colon genuinely
      does end a clause in ordinary prose.
  (c) Stop deriving the title from prose. Let the CHANGELOG section carry an explicit
      title field the workflow reads verbatim, falling back to derivation. Removes the
      class rather than this instance, at the cost of a new convention authors must follow
      — and an unfollowed convention silently returns to the derived path.

  Worth deciding explicitly whether the derived title is the right design at all, given
  this is the second failure in it. A mechanical check is also possible independent of the
  fix: assert the derived title is not a strict prefix of the summary cut mid-phrase, or
  simply that it exceeds some minimum word count, so the next instance fails loudly in CI
  rather than being spotted by eye on the releases page.

Redactions: repository and vault names, absolute paths, and the concrete version numbers
of the affected release replaced with `<vX.Y.Z>` placeholders. The example summary text is
reproduced verbatim apart from that, because the defect depends on its exact punctuation
and redacting it would remove the evidence. Nothing else omitted.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
