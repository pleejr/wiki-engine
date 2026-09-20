---
slug: lint-links-pipefail-sigpipe-false-dead-links
outcome: open
received: 2026-09-19
---

HANDOFF — engine defect report
slug: lint-links-pipefail-sigpipe-false-dead-links
boundary: generic (engine-domain; contains no consumer-private context)

Title: Under `pipefail`, `has_slug`/`is_external` read a page that EXISTS as missing when `grep -q` exits before the writer finishes

Engine version: v1.81.0, run as the plugin.
Still live at that pin: read `bin/lint-links.sh` and `bin/lint-memory.sh` in the running
v1.81.0 tree (both still carry the shape), and reproduced the mechanism with that exact
function body under `set -uo pipefail` (see Reproduction).

Observed: a consumer vault's first CI run of `scaffold/vault-gate.yml` (ubuntu-latest,
`./engine/bin/lint.sh --wiki .`) failed section "link integrity" with 40+ errors of the
form `✗ [[a-page]] does not resolve, but [[another-page]] does — typo or a slug left
behind by a rename`, plus hundreds of `! [[x]] is a stub (no such page …)` warnings, for
pages that EXIST as `<node-dir>/<slug>.md` and are tracked in the very commit CI checked
out. Nearly every wikilink in the vault was reported. Every single finding was preceded
on stderr by:

    <checkout>/engine/bin/lint-links.sh: line 171: printf: write error: Broken pipe

Line 171 is `has_slug()`. `lint-memory.sh:82` (identical function) emitted the same error.
The same tree, same engine release, lints clean on macOS — so the report is
platform-dependent, not a property of the vault's content.

Expected: a `[[link]]` whose page exists resolves, on every platform. The gate's own
doc comment says an ERROR means "a link that was MEANT to resolve and doesn't"; a page
that is present must never produce one. I believe this because the resolution test is a
pure lookup in a list the script itself just built — nothing about it is platform- or
timing-dependent by design.

Mechanism (this part is observation, not hypothesis): the lookup is

    has_slug() { printf '%s\n' "$SLUGS" | grep -qxF "$1"; }

under `set -uo pipefail` (lint-links.sh:29, lint-memory.sh:46). `grep -q` exits at the
FIRST match, closing the read end; the writer then takes EPIPE, bash's `printf` returns
non-zero, and `pipefail` promotes that to the pipeline's status. So the pipeline reports
FAILURE precisely when the slug was found early, and the caller reads "not present".
Whether the writer loses the race depends on the platform and on how far into the sorted
list the match sits, which is why one OS is clean and the other is red on the same tree.

Reproduction (generic), no vault required:

  1. bash -c '
       set -uo pipefail
       BIG=$(seq 1 200000 | sed "s/^/slug-/")
       has_slug() { printf "%s\n" "$BIG" | grep -qxF "$1"; }
       has_slug slug-1 && echo PRESENT || echo "MISSING (wrong)"
       set +o pipefail
       has_slug slug-1 && echo PRESENT || echo "MISSING (wrong)"
     '
  -> MISSING (wrong)
     PRESENT

  The list is oversized only to make the race deterministic on any platform; a real
  vault's ~800 slugs / ~32 KB is enough to lose it on a Linux CI runner.

  2. Equivalently, on Linux: run `bin/lint.sh --wiki <a vault whose pages link to each
     other>` and observe resolvable links reported as stubs, with the `line 171: printf:
     write error: Broken pipe` line beside each finding.

Failure shape: fail-closed — the gate goes red and exits 1, nothing is lost or silently
accepted. Urgency is low by that measure, but it is worth treating as more than cosmetic
for two reasons: it makes a vault's FIRST CI run red with findings that are all false,
which is the shape that teaches an operator to stop reading the gate; and it is the same
function that decides `is_external`, so an allowlisted target can be reported too.

Already ruled out:
  - Vault link debt. The named pages exist and are present in the checked-out commit
    (`git cat-file -e <sha>:<node-dir>/<slug>.md`).
  - A relative `--wiki .` (what the scaffold workflow passes) versus an absolute path:
    both lint clean locally, so the argument form is not the trigger.
  - `engine/` polluting the page list in CI, where the workflow checks the engine out
    INTO the vault: `VAULT_SCAN_SKIP_DIRS` prunes `engine`, and the slugs reported are
    vault pages, not engine files.
  - A short/truncated `$SLUGS`: the near-miss suggestions name real vault pages, so the
    list was built correctly — only the lookup's exit status is wrong.

Suggested fix (HOLD LOOSELY — may be wrong): remove the pipe from the lookup rather than
the `pipefail`, e.g. `grep -qxF -- "$1" <<<"$SLUGS"` (a here-string has no reader to
close early), or hold the slugs in an associative array and test membership directly,
which also drops one process per link. `lint-memory.sh`'s identical `has_slug` needs the
same change, and it would be worth grepping the engine for other `printf … | grep -q`
pairs under `pipefail`, since the defect is in the shape, not in this one call site.
A regression test would need to fail before the fix: assert that a slug matching the
FIRST line of a large list reports present.

Redactions: the consumer vault's name, its org/repo slug, absolute paths, and the real
page slugs were replaced with `<checkout>`, `<node-dir>/<slug>.md`, `[[a-page]]` and
`[[another-page]]`. The CI log line is verbatim apart from the leading path. Nothing
else was removed; the reproduction above is complete and runnable as written.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
