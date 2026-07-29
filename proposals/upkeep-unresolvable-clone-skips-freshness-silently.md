---
slug: upkeep-unresolvable-clone-skips-freshness-silently
outcome: accepted
received: 2026-07-29
reason: "accepted as reported, with the suggested shape — an unresolvable: row rather than a silent continue, and both rejected alternatives (remote-matching search, hard error) rejected here for the reasons given. Extended in two ways the report did not ask for: scan counts the unassessed pages separately, since folded into the total they read as ordinary work; and sync-clones now names a clone it cannot find, which was the same silence one verb over"

HANDOFF — engine defect report
slug: upkeep-unresolvable-clone-skips-freshness-silently
boundary: generic (engine-domain; contains no consumer-private context)

Title: upkeep scan silently skips the freshness check for any repo page whose clone directory name differs from its sources.repo value

Engine version: v1.46.0
Still live at that pin: read `engine/bin/upkeep.sh` at the pinned checkout and reproduced against a
real repo page whose clone directory does not match its `sources.repo`. The page stayed absent from
every `refresh:` row across repeated `sync-clones` + `scan` cycles while being four commits behind
its upstream. Confirmed by hand-diffing the recorded sha against the clone HEAD, which the queue
never did.

Observed:
  In the repo-page loop of the scan, the clone is resolved purely by joining the repos root to the
  page's declared repo name, and a miss is swallowed:

      repo="$(page_repo "$f")"; [ -n "$repo" ] || repo="$slug"
      clone="$REPOS_ROOT/$repo"
      [ -d "$clone/.git" ] || continue        # <-- silent skip; nothing is emitted

  So when a clone exists on disk under a directory name that differs from the page's `sources.repo`
  value — a rename, a disambiguating prefix, a second checkout of the same upstream — the page is
  dropped from the freshness comparison entirely and **no row of any kind is emitted about it**.
  There is no warning, no `unresolvable:` row, no note in the scan summary.

  The failure is disguised rather than merely quiet: such a page can still appear in the queue via
  the `verify:` path, which needs no clone. So the operator sees the page listed, drains the verify,
  and reasonably concludes the page has been attended to — while the freshness question was never
  asked and cannot be asked. A page in this state can go stale indefinitely.

  This also silently changes what a clean queue means. "No refresh rows" is read as "every repo page
  matches its clone", when it actually means "every repo page whose clone I could find matches".

Expected:
  An unresolvable clone is a different answer from "up to date", and should be reported as its own
  state rather than skipped. The scan already holds exactly this principle a few dozen lines away,
  for project pages with an unrecognized status, and states the reasoning in a comment:

      "An unknown or missing status is not silently skipped: it is exactly the page most likely to
       be wrong, and skipping it would recreate the invisible failure this whole queue exists to
       remove."

  A repo page whose clone cannot be located is the same category — the page most likely to be wrong
  is the one the tool could not examine. The defect is that this rule is applied to one page type
  and not the other.

Reproduction (generic):
  1. Take any repo page under `repos/<page-slug>.md` with valid `sources.repo`/`ref`/`sha`.
  2. Ensure its clone exists on disk but under a directory name that is NOT the value of
     `sources.repo` — e.g. clone it to `<repos-root>/<some-other-name>`.
  3. Move the clone's upstream forward (or record an older sha on the page) so it is genuinely stale.
  4. Run: `engine/bin/upkeep.sh sync-clones` then `engine/bin/upkeep.sh scan` then `upkeep.sh list`
  -> No `refresh:<page-slug>` row appears, and no other row mentions the page's clone being
     unresolvable. `sync-clones` likewise never mentions it. The page reads as up to date.
     Contrast with a page whose clone IS resolvable and stale, which correctly yields a refresh row.

Failure shape: fail-open

  It proceeds while looking correct. Nothing surfaces the gap, the queue reports success, and the
  operator's confidence in "the queue is clean" is exactly what is misplaced. The staleness it hides
  compounds silently, and the `verify:` path actively camouflages it.

Already ruled out:
  - Not a `sync-clones` bug. `sync-clones` reports a dirty clone as an explicit `skip` row, so it
    already distinguishes "could not act" from "nothing to do" — the scan is where the distinction
    is lost. The two verbs disagree about whether an unactionable clone deserves a mention.
  - Not the tagged-vs-untagged comparison branch. Both branches sit *after* the `continue`, so
    neither is ever reached for these pages.
  - Not the deliberate self-page guard. That is a separate, intentional check further down
    (comparing the resolved clone path against the vault path) and it correctly emits nothing for a
    genuine self-page; this defect fires before that branch and for unrelated reasons.
  - Not a missing-provenance case. `[ -n "$rec_sha" ] || continue` above it already handles a page
    with no recorded sha; this is specifically a page with good provenance and an unfindable clone.

Suggested fix (HOLD LOOSELY — may be wrong):
  Emit a row instead of `continue`-ing, so the state is visible and drainable, e.g. an
  `unresolvable:<slug>` row reading "clone not found at <repos-root>/<repo> — freshness unknown".
  That preserves the fail-closed-by-visibility property without guessing where the clone went.

  Two things I would NOT do, offered as reasoning rather than instruction. Searching the repos root
  for a directory whose git remote matches the page is tempting but guesses at operator intent and
  would silently bind a page to an unrelated second checkout of the same upstream. Making the scan
  hard-error would punish a legitimately-not-cloned-on-this-machine page, which is a normal state on
  a multi-machine vault — the point is that it should be *reported*, not that it should fail.

  A page-level way to declare the clone directory when it differs would remove the cause rather than
  report it, but that is a design question with a wider blast radius than this report should decide.

Redactions:
  Concrete identifiers replaced with placeholders throughout, consistently: the vault's repos root is
  `<repos-root>`, the affected page is `<page-slug>`, the mismatched directory is `<some-other-name>`.
  The real page/clone/upstream names and the consumer's host paths are omitted — the defect does not
  depend on which page triggered it, only on the name mismatch. Code excerpts are verbatim from the
  pinned engine and carry no consumer values.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a
hypothesis, not a specification — the observation (a silent skip that disguises unknown as clean) is
what I am confident about.
