---
slug: projects-index-other-bucket-order-is-awk-dependent
outcome: open
received: 2026-10-27
---

HANDOFF — engine defect report
slug: projects-index-other-bucket-order-is-awk-dependent
boundary: generic (engine-domain; contains no consumer-private context)

Title: gen-projects-index.sh orders the "### Other" bucket by awk hash order, so --check passes on macOS and fails on Linux CI

Engine version: v3.7.0
Still live at that release: v3.7.0 bin/gen-projects-index.sh line 95 still reads `for (s in seen)` to emit statuses outside planned/active/paused/done.

Observed: a consumer vault had project pages with three non-standard statuses (three distinct values outside the known four). gen-projects-index.sh run on macOS (BSD awk 20200816) wrote index.md, and `--check` passed locally. The vault's CI (ubuntu runner, engine checked out at the same tag) failed the umbrella lint with "drift: ./index.md projects catalog is stale — run gen-projects-index.sh". Changing one page's status to `active`, leaving two non-standard statuses, made CI pass. No other file differed between the two runs.

Expected: the generated catalog is byte-identical on every awk, since `--check` is a CI gate and the file is committed from a developer machine.

Reproduction (generic):
  1. in a vault, give three project pages three different statuses outside planned/active/paused/done (e.g. backlog, wont-do, current)
  2. run bin/gen-projects-index.sh on macOS and commit index.md
  3. run bin/gen-projects-index.sh --check under mawk or gawk (Linux)
  -> drift reported. Not reproduced side by side on one machine: no mawk/gawk was available locally, so the evidence is the CI run against the local pass.

Failure shape: fail-closed (CI refuses the merge; nothing is lost).

Already ruled out: locale (LC_ALL=C regeneration on macOS gave no diff); stale engine (CI and local both at the tag); a racing commit on main (none between push and run); an untracked page (tracked and on-disk project files matched).

Suggested fix (HOLD LOOSELY — may be wrong): collect the unknown statuses into an array, sort them (asort is gawk-only, so a small portable insertion sort or a pre-sort in the shell pipeline, which already sorts rows by status with LC_ALL=C), and emit Other in that order; add a test with three unknown statuses.

Redactions: the consumer's vault, page slugs, and CI run identifiers are omitted; status values given are illustrative.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
