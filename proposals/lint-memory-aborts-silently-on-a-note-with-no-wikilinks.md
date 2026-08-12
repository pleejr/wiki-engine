---
slug: lint-memory-aborts-silently-on-a-note-with-no-wikilinks
outcome: accepted
received: 2026-08-12
---

HANDOFF — engine defect report
slug: lint-memory-aborts-silently-on-a-note-with-no-wikilinks
boundary: generic (engine-domain; contains no consumer-private context)

Title: lint-memory.sh stops mid-run on the first note that has no wikilinks, so every note sorting after it goes unchecked and the truncated report looks like a clean one

Engine version: v1.53.0, and unchanged in v1.54.0
Still live at that pin: reproduced at v1.53.0 with two fixture notes, then re-confirmed against v1.54.0. Found while intaking `rag-capture-aborts-silently-when-wiki-path-is-not-a-vault`, whose reporter swept `bin/` and concluded the pattern was "one line in one script, not a family". That conclusion was wrong; this is the second instance.

Observed: `bin/lint-memory.sh` runs under `set -euo pipefail` (line 21). At line 91 it assigns from a pipeline whose first command may legitimately match nothing:

    links="$(grep -oE '\[\[[^]]+\]\]' "$f" 2>/dev/null \
      | sed -e 's/^\[\[//' -e 's/\]\]$//' -e 's/[|#].*//' | LC_ALL=C sort -u)"

`grep` exits 1 when a note contains no wikilinks. `pipefail` propagates that out of the pipeline, `set -e` aborts on the assignment, and the loop over notes stops there. The very next line already handles the zero case — `nlinks="$(printf '%s' "$links" | grep -c . || true)"` carries `|| true`, and the line below it emits `only $nlinks outbound [[wikilink]](s) (need >=2)` — so the intended behaviour is plainly to REPORT a linkless note, not to die on it. The guard was put on the second grep and omitted on the first.

Reproduction (generic), two notes in `$WIKI/memory`, the linkless one sorting first:

  1. Write two valid notes. Give the first no `[[wikilinks]]` and the second two.
  2. `WIKI_PATH=<dir> bash bin/lint-memory.sh`

  Measured, both notes linked (control):
     both notes checked, then `memory lint: 2 notes, 2 error(s), 4 warning(s)`, exit 1
  Measured, first note linkless:
     first note's other findings printed, second note ABSENT, NO summary line, exit 1,
     stderr empty

The summary line is the only thing that states how many notes were checked, and it is exactly what the abort suppresses. There is no partial-run marker.

Failure shape: **fail-open.** The command exits non-zero, but it already exits non-zero whenever it finds an error, so the status carries no new information. Nothing is written and nothing is corrupted; the loss is coverage. An operator sees a shorter report with fewer findings and no message, which is indistinguishable from a vault that got cleaner — and the note that silenced the linter is itself a note the linter wanted to complain about, so the notes most likely to trigger it are the ones least likely to be noticed missing.

Already ruled out:

  - Not the `2>/dev/null`: removing it changes nothing, because `grep` prints nothing to stderr on a no-match. The abort is `pipefail` + `set -e`, as in the sibling report.
  - Not specific to sort order beyond the obvious: the run stops at the FIRST linkless note, so a vault whose only linkless note sorts last loses nothing and the defect stays invisible there.
  - Not the `nlinks` line, which is correctly guarded and is the evidence that zero links is a handled state.
  - Not a malformed note: the fixtures carry valid frontmatter and the error the linter reports on the first note proves it parsed fine.

Suggested fix (HOLD LOOSELY — may be wrong): the remedy is NOT the sibling's remedy. There, "no declaration" meant "not a vault" and refusing was right. Here, zero wikilinks is a valid state the script already knows how to report, so it wants the assignment to survive — `|| true`, or an empty default — and then the existing `-ge 2` check does its job. Do not turn this into a refusal.

Worth deciding separately, and the reason this is filed rather than fixed in passing: whether a truncated lint should be able to end quietly at all. Both instances of this pattern ended a run early while every step reported success, so a check that the run reached its own summary would catch the class rather than the instance.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
