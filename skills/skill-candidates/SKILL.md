---
name: skill-candidates
description: Mine the vault's own durable record — `memory/` notes, `log.md`, `raw/sessions/` — for procedures repeated often enough to deserve a skill, and report ranked CANDIDATES with the dated evidence behind each. Evidence is the whole point: a candidate is justified by several dated notes or log lines showing the same procedure done more than once, never by the session that just ended. Reports a name, the repeated procedure, the notes evidencing it, an overlap check against the installed catalog, and a verdict — and never writes a `SKILL.md`, which is a separate job for a skill-authoring skill. Use when the user says "mine the vault for skill candidates", "should this be a skill", "what should I turn into a skill", "have I done this enough times to encode it", "find the skills hiding in my notes", or at the end of a session once `checkpoint` has written its notes. Distinct from `checkpoint` (which distills facts INTO `memory/` and owns the end-of-session ritual): this reads those notes back out and proposes tooling, so it runs AFTER checkpoint, never instead of it. NOT for writing, fixing or debugging a skill, and NOT for a procedure with a single occurrence — one session is a feeling, not evidence.
status: active
summary: mine `memory/`, `log.md` and the session buffer for procedures proven to repeat; report ranked skill candidates with dated evidence, never a SKILL.md.
updated: 2026-08-13
used_by: []
---

# skill-candidates — find the procedures the vault already proved you repeat

A skill is worth writing when a procedure **repeats**. The trouble is that the moment you most want to write one — the end of a long session — is the moment you can least judge that, because the session you just finished always feels like the most significant one you have had. Novelty and recurrence feel identical from inside a single session.

The vault already settles it. `checkpoint` distils every session into dated `memory/` notes and appends a `log.md` line, so the record of what you actually did, repeatedly, over weeks, is sitting there in a queryable form. This skill reads that record back out and reports **candidates with their evidence**. It is the inverse direction of `checkpoint`: that skill writes durable facts in, this one reads them out and asks what they collectively imply about tooling.

The engine's own `drain` skill is the worked example. It was not designed; it was *noticed* — several `log.md` entries described the same intake → reproduce → fix-the-class → release → adopt loop, and the loop got written down. That is the shape to look for.

## Where it runs

Read-only, against canonical `$WIKI_PATH`. It writes nothing to tracked vault content, so unlike its neighbours it takes **no worktree** — there is no edit for a concurrent session to clobber, and nothing to integrate. Verdicts worth keeping go back through `checkpoint` (§7), which owns vault writes.

Inputs, all in canonical `$WIKI_PATH`:

- `memory/*.md` — the curated notes. The primary evidence.
- `log.md` — one dated line per session. The recurrence signal.
- `raw/sessions/` — the auto-captured buffer. **Canonical `$WIKI_PATH` only**: it is git-ignored per-machine state, so it does not exist in a worktree, and its absence there looks exactly like an empty buffer.

The buffer is a weak, recent, disposable source — a session captured there may never have been curated. Use it to notice a *pattern forming*, never to justify a candidate on its own.

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
grep -l '<tag>' "$WIKI_PATH"/memory/*.md | xargs grep -H '^created:'

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
  Verdict     build | fold into <skill> | CLAUDE.md instead | not yet — needs more occurrences
```

`not yet` is a first-class outcome and usually the honest one. Report near-misses with their current count so the next run can see the pattern building rather than starting over.

Finish with one line naming what you searched and what you found nothing for. A run that surfaces no candidate should say so plainly — the record not yet showing a repeat is the ordinary case, and a skill invented to justify the run is worse than an empty report.

## 7. Close the loop

**Do not write the `SKILL.md`.** Authoring is a different job with its own conventions, trigger design and eval loop; hand an accepted candidate to whichever skill-authoring skill the machine has. Keeping this skill to detection is what keeps it cheap enough to run every session.

Record the verdict so it is not re-litigated. This skill writes nothing itself — hand the decision to `checkpoint`, which owns vault writes, as a `type: decision` note tagged `skill-candidate`:

- **Declined** — record it with the reason and the count it was declined at. Without this, the same candidate is rediscovered every run, and the reason it was rejected is lost while the evidence for it keeps accumulating.
- **Accepted** — record what it was built from, so the skill's own provenance points back at the notes that justified it.

Read those notes at the start of the next run (`grep -l 'skill-candidate' "$WIKI_PATH"/memory/*.md`) and skip anything already declined — unless its evidence count has grown past the count in the decline, which is precisely when a previous "not yet" becomes a "yes".

## Rules

- **In-session, on demand.** Never wire this to a session-lifecycle hook. It runs after `checkpoint`, and it reads the notes checkpoint just wrote — running it from a hook re-fires the event that spawned it, which is the structure the engine's `CLAUDE.md` bans.
- **Never propose a skill from the current session alone.** The session in progress is the one input with no dated history behind it, and it is the one that always feels sufficient.
- Prefer few strong candidates over a long list. A run that proposes six skills has stopped filtering, and a catalogue full of thinly-justified skills triggers worse than a small one.
