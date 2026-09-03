---
name: skill-candidates
description: Mine the vault's durable record — `memory/` notes, `log.md`, the session buffer — for procedures repeated often enough to deserve a skill, and report ranked CANDIDATES with dated evidence. A candidate needs 3+ dated occurrences spread over weeks with stable steps and a varying subject, never the session that just ended. Reports name, procedure, evidencing notes, and an overlap check against the installed catalog, then puts EVERY candidate to the operator as a develop / discard / defer choice — it recommends, never decides — and records those verdicts itself as `type: decision` notes tagged `skill-candidate`, in its own worktree and commit. First run on an un-mined vault is a backlog drain (expect many); later runs sweep forward from the newest verdict (expect zero or one). Never writes a `SKILL.md` and invokes nothing. Triggers: "mine the vault for skill candidates", "should this be a skill", "what should I turn into a skill", "have I done this enough times to encode it", "find the skills hiding in my notes", "catch up on the skills I never wrote", or when `checkpoint` offers it. Distinct from `checkpoint` (distills facts INTO `memory/`; offers this pass, never runs it) — this reads those notes back out. NOT for writing or debugging a skill, and NOT for a one-off procedure — one session is a feeling, not evidence.
status: active
summary: mine `memory/`, `log.md` and the session buffer for procedures proven to repeat; report ranked skill candidates with dated evidence and record the verdicts, never a SKILL.md.
updated: 2026-09-03
used_by: []
---

# skill-candidates — find the procedures the vault already proved you repeat

A skill is worth writing when a procedure **repeats**. The trouble is that the moment you most want to write one — the end of a long session — is the moment you can least judge that, because the session you just finished always feels like the most significant one you have had. Novelty and recurrence feel identical from inside a single session.

The vault already settles it. `checkpoint` distils every session into dated `memory/` notes and appends a `log.md` line, so the record of what you actually did, repeatedly, over weeks, is sitting there in a queryable form. This skill reads that record back out and reports **candidates with their evidence**. It is the inverse direction of `checkpoint`: that skill writes durable facts in, this one reads them out and asks what they collectively imply about tooling.

The engine's own `drain` skill is the worked example. It was not designed; it was *noticed* — several `log.md` entries described the same intake → reproduce → fix-the-class → release → adopt loop, and the loop got written down. That is the shape to look for.

## Where it runs

**Reads canonical `$WIKI_PATH`; writes its verdicts through a worktree of its own.** The mining itself is read-only, and for most of a run there is nothing to isolate — but §7 records what the operator decided, and that is tracked vault content like any other. Take the worktree up front rather than at the end, so the run cannot discover halfway through that it has verdicts and nowhere safe to put them:

- `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)" || { echo "not isolated — resolve before writing"; }` — **check the exit status**, and read its stderr for a stale base. Same contract as every other writing skill here; see `checkpoint` §0 for the full account of what `ensure` guarantees and what a non-zero exit costs you.
- **Read the evidence from canonical `$WIKI_PATH`, write the verdicts to `$WORK`.** The two trees differ in exactly the way that matters to this skill: the session buffer below is git-ignored, so it exists only in canonical, and a worktree's empty copy is indistinguishable from a quiet month.
- Commit, `vault-worktree.sh integrate`, then `gc "$WORK"` — a standalone run is a complete unit of work, not half of someone else's.

**This skill still invokes nothing** — not `checkpoint`, not a skill-authoring skill. Writing its own notes is not an invocation and does not reintroduce the cycle: the ban is on the two calling each other, and nothing here calls anything.

Inputs, all read from canonical `$WIKI_PATH`:

- `memory/*.md` — the curated notes. The primary evidence.
- `log.md` — one dated line per session. The recurrence signal.
- `raw/sessions/` — the auto-captured buffer. **Canonical `$WIKI_PATH` only**: it is git-ignored per-machine state, so it does not exist in a worktree, and its absence there looks exactly like an empty buffer.

The buffer is a weak, recent, disposable source — a session captured there may never have been curated. Use it to notice a *pattern forming*, never to justify a candidate on its own.

## Two modes: backlog, then steady state

**The first run on a vault is a backlog drain, and it should return many candidates.** A vault that has been checkpointing for months without ever mining those notes has accumulated every procedure it repeated in that time. Finding eight is the correct result there, and reporting two because a long list felt undisciplined is the same under-reporting failure this skill exists to prevent, arriving from the other direction.

Detecting which mode you are in is free, and needs no new state: **if no `skill-candidate` verdict note exists, this is a first run.** The vault has never been mined, so the whole record is unexamined.

Ask that question of the **frontmatter**, never of the file text:

```sh
grep -l '^type: decision' "$WIKI_PATH"/memory/*.md \
  | xargs grep -lE '^tags:.*(\[|, )skill-candidate(,|\])' 2>/dev/null
```

A bare `grep -l 'skill-candidate'` over the notes is wrong in the direction that costs most. Every note *about* this skill contains its name — including the ones written the day it shipped — so a mention counts as a verdict, the run reports steady state on a vault that has never been mined, and it then expects none-or-one where the honest answer is a backlog. That is the under-reporting this whole section exists to prevent, re-entering through the query rather than through the rule. The `type:` test and the delimited tag are both load-bearing: the first rejects a lesson that discusses the skill, the second rejects a near-miss tag that merely starts with the same letters.

- **Backlog mode** — sweep the entire record, oldest to newest. Expect many. Rank hard, because with a long list the ranking carries the whole value (§4).
- **Steady state** — sweep forward from the date of the newest verdict note, and re-check anything previously marked *not yet*. Expect zero or one. Zero is the run working, not the run failing.

**The bar does not relax in backlog mode, and it does not tighten in steady state.** It is the same three tests either way (§1). What changes is only how many candidates clearing it you should expect to see, and therefore what an unusual result looks like: a first run returning nothing means the queries are wrong, and a steady-state run returning six means either the vault has been left un-mined for a long stretch, or the bar is being applied loosely.

**Separate what you report from what you recommend building.** Report every candidate that clears the bar — that inventory is the honest output, and suppressing it loses work the record actually earned. Recommend a **small number to build first**, because skills are written one at a time and eight authored in one sitting are eight thin ones. The rest keep their evidence and wait; nothing is lost, since the next run re-derives them from the same notes.

Convergence is the intended shape: the backlog drains once, and running this regularly thereafter keeps each later pass near zero. A steady state of nothing-to-report is this skill succeeding. **Regularly is now the operator's choice** — `checkpoint` offers this pass rather than running it — so the interval between passes is whatever they accept, and a long gap shows up honestly as a bigger sweep rather than as a first run.

## 1. The bar

A candidate must clear all three:

- **Three or more occurrences**, each with a date, in `memory/` or `log.md`. Two is a coincidence; the third is what distinguishes a procedure from a pair of similar afternoons.
- **Spread over time.** Three occurrences inside one day is one piece of work with three parts. Look for recurrence across weeks.
- **Stable steps, varying subject.** The procedure must be the constant and the target the variable. If the steps changed every time, what repeated was the *problem*, and the answer is a lesson note, not a skill.

State the count and the dates for every candidate you report. A candidate whose evidence you cannot enumerate is one you invented while reading, which is the exact failure this skill exists to prevent.

## 2. Gather the evidence

Run these against canonical `$WIKI_PATH`. Start with the clusters, then read the notes behind the interesting ones — do not read 100 notes.

```sh
# Tag clusters — a tag carried by many notes is a subject you keep returning to.
grep -h '^tags:' "$WIKI_PATH"/memory/*.md | sed 's/^tags: *\[//; s/\]$//' \
  | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort | uniq -c | sort -rn | head -25

# The notes behind one cluster, by the date each was FIRST written — the recurrence test.
# Match the TAGS LINE, not the file: a bare grep for a short tag matches it inside ordinary
# words (`ci` inside "decision"), which silently inflates every count and date span.
grep -lE '^tags:.*(\[|, )<tag>(,|\])' "$WIKI_PATH"/memory/*.md | xargs grep -H '^created:'

# Notes amended long after they were written: a rule re-learned, which is an occurrence too.
grep -H '^created:\|^updated:' "$WIKI_PATH"/memory/*.md | paste - - | awk '$2 != $4'

# Procedures already written out longhand: the "How to apply" blocks.
grep -A6 '^\*\*How to apply' "$WIKI_PATH"/memory/*.md

# How often a kind of work reached the log at all.
grep -in '<phrase>' "$WIKI_PATH"/log.md | tail -20
```

**Count `created:`, never `updated:`.** They answer different questions: `created:` is when the thing happened, `updated:` is when the note was last touched. Because amending an existing note is the normal way a rule gets refined, `updated:` migrates toward the present — on a mature vault the recent dates hold a large share of every cluster, so **every** subject looks like it recurred this week and the spread-over-time test passes for all of them. That is a fail-open reading: it manufactures the evidence rather than finding it.

The gap between the two dates is itself worth reading, in the other direction. A note created weeks ago and amended recently is a rule that came back — a genuine second occurrence, recorded inside one file where a per-note count cannot see it.

Then use recall as a **second lens, not a replacement**: `"$WIKI_PATH"/engine/bin/recall.sh "did this the same way again"` finds notes whose wording differs from your grep. It points at pages to open; the tag graph and the dates remain the evidence.

Read the prior verdicts before you report anything (§7) so a candidate already declined does not resurface every session.

## 3. What a candidate looks like in the record

Four recognisable shapes, roughly in descending order of how often they turn out to be real:

- **A repeated loop.** Several `log.md` entries narrating the same sequence of steps against different subjects. The strongest signal, because the log records what you *did* rather than what you concluded.
- **A cluster of lessons with one root.** Several `type: lesson` notes that, read together, are one rule you keep re-learning in different disguises. The re-learning is the evidence: a rule that stuck would have been written once.
- **A "How to apply" that is really a checklist.** A note whose apply-block is an ordered procedure someone could execute. It is already a skill body; it is just filed as a memory note.
- **A preference restated constantly.** A `type: preference` note you find yourself re-explaining per session. Often the right answer here is **not** a skill — an always-on preference belongs in the vault's `CLAUDE.md`, which loads every session, where a skill only fires when its description matches. Say so when that is the better home.

## 4. Rank

Order by **frequency × cost of getting it wrong**. A procedure done twenty times that is hard to get wrong is worth less than one done four times that has already caused a documented failure — and if a `lesson` note exists about it going wrong, that is the strongest argument in the report. Encode where the record shows both repetition and consequence.

## 5. Overlap check

Every installed skill is linked into one place regardless of which repo ships it, so check them all at once:

```sh
grep -h '^description:' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/skills/*/SKILL.md
```

For each surviving candidate, decide which is true:

- **An existing skill already covers it** — drop the candidate, and say which skill. This is the common outcome and reporting it is useful, not a failure.
- **An existing skill nearly covers it** — the right change is usually a section or a trigger phrase added to that skill, not a new one. Propose the edit.
- **Genuinely new** — it survives, and its report must name the neighbours it will have to be distinguished from, because whoever writes it will need exactly that.

A new skill overlapping an existing description degrades both: they compete for the same prompts and each fires less reliably. Killing a candidate here is cheaper than debugging the collision later.

## 6. Report

One block per surviving candidate, ranked, no prose preamble:

```
<proposed-name>
  Procedure   one sentence: the steps, with the varying subject named
  Evidence    N occurrences — [[note-slug]] (date) · log.md (date) · …
  Cost        what went wrong when it was done ad hoc, if the record says
  Overlap     the nearest installed skill, and why this is not it
  Recommend   develop | discard (<why>) | defer at N — and one line of reasoning
```

**`Recommend` is advisory, not a decision.** The operator chooses; see §6a. Say what you would do and why, because a recommendation with no reasoning is not reviewable — but never write it up as settled, and never act on your own recommendation without the answer.

`defer` is a first-class outcome, and in steady state it is usually the honest one. Report near-misses with their current count so the next run can see the pattern building rather than starting over.

In backlog mode, order the report by rank and mark the small set you recommend building first, so a long list stays actionable instead of becoming a wish-list nobody works through.

Finish with one line naming what you searched, what mode you were in, and what you found nothing for. A run that surfaces no candidate should say so plainly — in steady state that is the ordinary case, and a skill invented to justify the run is worse than an empty report. On a **first** run, though, an empty report is a result to distrust: a vault with months of notes has almost certainly repeated something, so check the queries before concluding the record is clean.

## 6a. Ask, one candidate at a time

**Every candidate that clears the bar goes to the operator as a choice. You do not get to settle any of them yourself** — not the obvious discards, not the folds, not the ones you are confident about. A detection skill that also decides has quietly become an authoring skill with a filter, and the operator finds out what it chose only by reading the vault afterwards.

Use the host's interactive question facility, and offer exactly three outcomes per candidate:

- **Develop** — hand it to a skill-authoring skill (§7). No `SKILL.md` is written here; the verdict itself is, so the provenance survives even if the authoring never happens.
- **Discard** — never propose this again. **Capture the operator's reason in one line**; that reason is the entire value of the record, because the evidence will keep growing and a future run will otherwise re-derive the same candidate and re-ask.
- **Defer** — keep it with its current count, to be reconsidered when the count grows past it.

Practical shape: these facilities cap the number of questions per call — commonly four — so **batch, never truncate**. Six candidates is two rounds. Silently dropping the tail would report a filtered list as the whole list, which is the failure this skill exists to avoid.

**A discard reason is not a formality, and it is where your recommendation is most likely to be wrong.** The axes you rank on — recurrence and cost — measure whether the *evidence* is real. They cannot see whether a **skill is the right form**: notes that already load on demand may cover the ground without anything needing to fire, and an always-on preference belongs in the vault's `CLAUDE.md` instead. The operator can see that and you often cannot, so record the reason they give rather than the one you would have guessed.

## 7. Close the loop — record the verdicts here

**Do not write the `SKILL.md`.** Authoring is a different job with its own conventions, trigger design and eval loop; hand a *develop* candidate to whichever skill-authoring skill the machine has. Keeping this skill to detection is what keeps it cheap enough to run often.

**Record the verdicts yourself**, into the worktree taken in *Where it runs* — one commit, then `integrate`, then `gc`. This skill used to write nothing and hand its verdicts back to `checkpoint`, which ran it and owned the commit. That edge is gone: `checkpoint` now only *offers* this pass, so handing verdicts back would hand them to a caller that is no longer there, and a standalone run would end by printing decisions the operator had just made alongside a note that they are unrecorded — the shape of a pass that did not happen.

**Recording is not invoking, and the cycle stays broken.** The rule was never "the callee must not write"; it was that the two must not call each other. Nothing here calls `checkpoint`, and `checkpoint` no longer calls this. There are now zero edges between them, which is a stronger guarantee than the one-way edge it replaces — and it is why the write can move here without reopening the question.

**The verdict note is the only thing that persists, so writing it is not bookkeeping.** The mode check in *Two modes* keys on whether any `skill-candidate` verdict note exists. A run that decides and writes nothing leaves the vault indistinguishable from one that has never been mined: the next run reports backlog mode over the whole record and re-asks every candidate the operator already settled, and a *defer* loses the count that was the entire reason to record it. Declining the pass at `checkpoint`'s offer costs nothing, because no decision was made. Making the decisions and not writing them down costs the decisions.

Each verdict becomes a `type: decision` note tagged `skill-candidate`:

- **Discarded** — the operator's reason, and the count it was discarded at. Without this the candidate is rediscovered every run and the reason is lost while the evidence keeps accumulating.
- **Developed** — what it was built from, so the skill's provenance points back at the notes that justified it.
- **Deferred** — the count, which is the only thing that makes it reconsiderable rather than merely rediscoverable.

Read those notes at the start of the next run — with the frontmatter query from **Two modes**, not a bare name grep — and skip anything already declined — unless its evidence count has grown past the count in the decline, which is precisely when a previous "not yet" becomes a "yes".

## Rules

- **In-session, on demand.** Never wire this to a session-lifecycle hook. It runs after `checkpoint`, reads the notes checkpoint just wrote, and now commits notes of its own — running it from a hook re-fires the event that spawned it, which is the structure the engine's `CLAUDE.md` bans, and it would do so while holding a worktree.
- **Never invoke `checkpoint`, and never be invoked by it.** `checkpoint` offers this pass and stops; this one records its own verdicts and stops. Zero edges, in either direction — an edge added back either way is the cycle both files were written to prevent.
- **Never propose a skill from the current session alone.** The session in progress is the one input with no dated history behind it, and it is the one that always feels sufficient.
- **Recommend; never decide.** Every candidate clearing the bar goes to the operator as a develop/discard/defer choice, including the ones you are sure about. Deciding on their behalf turns a detection skill into an authoring skill with a filter, and they discover what it chose by reading the vault later.
- **Query the frontmatter, never the prose.** Every note *about* a subject contains its name, so a bare `grep` for a tag or a slug counts discussion as evidence — and short tags additionally match inside ordinary words. Both directions fail toward a confident wrong answer: the mode check reads a mention as a verdict, and a cluster count inflates. Anchor on `^tags:` / `^type:` with the tag delimited.
- **Filter on the bar, never on the count.** A catalogue full of thinly-justified skills triggers worse than a small one, so nothing that fails §1 is reported — but a long list of candidates that each *clear* §1 is a real backlog, not a filter that stopped working. Trimming it to look disciplined discards evidence the record earned. Control the number you recommend **building**, not the number you report.
