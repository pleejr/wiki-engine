---
name: skill-candidates
description: Mine the vault's durable record — `memory/` notes, `log.md`, the session buffer — for procedures repeated often enough to deserve a skill, and report ranked CANDIDATES with dated evidence. A candidate needs 3+ dated occurrences spread over weeks with stable steps and a varying subject, never the session that just ended. Reports name, procedure, evidencing notes, and an overlap check against the installed catalog, then puts EVERY candidate to the operator as a develop / discard / defer choice — it recommends, never decides — and records those verdicts itself as `type: decision` notes tagged `skill-candidate`, in its own worktree and commit. First run on an un-mined vault is a backlog drain (expect many); later runs sweep forward from the newest verdict (expect zero or one). Never writes a `SKILL.md` and invokes nothing. Triggers: "mine the vault for skill candidates", "should this be a skill", "what should I turn into a skill", "have I done this enough times to encode it", "find the skills hiding in my notes", "catch up on the skills I never wrote", or when `checkpoint` offers it. Distinct from `checkpoint` (distills facts INTO `memory/`; offers this pass, never runs it) — this reads those notes back out. NOT for writing or debugging a skill, and NOT for a one-off procedure — one session is a feeling, not evidence.
status: active
summary: mine `memory/`, `log.md` and the session buffer for procedures proven to repeat; report ranked skill candidates with dated evidence and record the verdicts, never a SKILL.md.
updated: 2026-09-03
---

# skill-candidates — find the procedures the vault already proved you repeat

A skill is worth writing when a procedure **repeats**, and the end of a session is the worst moment to judge that. The vault settles it: `checkpoint` distils every session into dated `memory/` notes and a `log.md` line, and this skill reads that record back out and reports **candidates with their evidence**.

## Where it runs

**Two halves, in different places.** §1–§6 (bar, evidence, shapes, overlap, report) are **read-only and subagent-safe** — a host subagent may run them over canonical `$WIKI_PATH` and return the report as text. §6a–§7 (questions and verdict notes) **need the operator and a worktree**: the questions need the host's interactive question facility, which its subagents lack (measured: a subagent's tool set has none), so they run in the session that offered the pass; a host whose subagents can ask may run the whole pass there. A report returned to the offering session is data flowing back, not an invocation edge into `checkpoint`.

**Reads canonical `$WIKI_PATH`; writes its verdicts through a worktree of its own**, taken at the start of the verdict half:

- `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)" || { echo "not isolated — resolve before writing"; }` — **check the exit status** and read its stderr for a stale base; the full contract is `checkpoint` §0.
- **Read the evidence from canonical `$WIKI_PATH`, write the verdicts to `$WORK`.** The session buffer is git-ignored, so it exists only in canonical; a worktree's empty copy is indistinguishable from a quiet month.
- Commit, `vault-worktree.sh integrate`, then `gc "$WORK"`.

This skill invokes nothing; writing its own notes is not an invocation.

Inputs, all read from canonical `$WIKI_PATH`:

- `memory/*.md` — the curated notes; the primary evidence.
- `log.md` (and rotated `log/*.md`) — one dated entry per session; the recurrence signal.
- `raw/sessions/` — the auto-captured buffer, **canonical `$WIKI_PATH` only** (git-ignored). Weak and disposable: a *pattern forming*, never a candidate's justification.

## Two modes: backlog, then steady state

**The first run on a vault is a backlog drain, and it should return many candidates** — trimming the list to look disciplined is the under-reporting this skill exists to prevent. **If no `skill-candidate` verdict note exists, this is a first run.** Ask that of the **frontmatter**, never the file text:

```sh
grep -l '^type: decision' "$WIKI_PATH"/memory/*.md \
  | xargs grep -lE '^tags:.*(\[|, )skill-candidate(,|\])' 2>/dev/null
```

A bare `grep -l 'skill-candidate'` is wrong in the costly direction: every note *about* this skill contains its name, so a mention counts as a verdict and a never-mined vault reads as steady state. The `type:` test and the delimited tag are both load-bearing.

- **Backlog mode** — sweep the entire record, oldest to newest. Expect many; rank hard (§4).
- **Steady state** — sweep forward from the newest verdict note's date, and re-check anything marked *defer*. Expect zero or one; zero is the run working.

The bar (§1) is the same in both modes; only the expected count changes, so a first run returning nothing means the queries are wrong. **Report every candidate that clears the bar; recommend a small number to build first** — the rest keep their evidence for the next run.

## 1. The bar

A candidate must clear all three:

- **Three or more occurrences**, each with a date, in `memory/` or `log.md`. Two is a coincidence; the third is what distinguishes a procedure from a pair of similar afternoons.
- **Spread over time.** Three occurrences inside one day is one piece of work with three parts. Look for recurrence across weeks.
- **Stable steps, varying subject.** The procedure must be the constant and the target the variable. If the steps changed every time, what repeated was the *problem*, and the answer is a lesson note, not a skill.

State the count and the dates for every candidate you report. A candidate whose evidence you cannot enumerate is one you invented while reading, which is the exact failure this skill exists to prevent.

## 2. Gather the evidence

Run these against canonical `$WIKI_PATH`; start with the clusters, then read the notes behind the interesting ones.

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
grep -in '<phrase>' "$WIKI_PATH"/log.md "$WIKI_PATH"/log/*.md 2>/dev/null | tail -20
```

**Count `created:`, never `updated:`** — `updated:` migrates toward the present as notes are amended, so counting it makes every subject look like it recurred this week; a note created weeks ago and amended recently is itself a second occurrence. Recall is a **second lens, not a replacement**: `"$WIKI_PATH"/engine/bin/recall.sh "did this the same way again"` points at pages to open. Read the prior verdicts (§7) before reporting.

## 3. What a candidate looks like in the record

Four recognisable shapes, roughly in descending order of how often they turn out to be real:

- **A repeated loop.** Several `log.md` entries narrating the same sequence of steps against different subjects. The strongest signal, because the log records what you *did* rather than what you concluded.
- **A cluster of lessons with one root.** Several `type: lesson` notes that, read together, are one rule you keep re-learning in different disguises. The re-learning is the evidence: a rule that stuck would have been written once.
- **A "How to apply" that is really a checklist.** A note whose apply-block is an ordered procedure someone could execute. It is already a skill body; it is just filed as a memory note.
- **A preference restated constantly.** A `type: preference` note you find yourself re-explaining per session. Often the right answer here is **not** a skill — an always-on preference belongs in the vault's `CLAUDE.md`, which loads every session, where a skill only fires when its description matches. Say so when that is the better home.

## 4. Rank

Order by **frequency × cost of getting it wrong**. A procedure done twenty times that is hard to get wrong is worth less than one done four times that has already caused a documented failure — and if a `lesson` note exists about it going wrong, that is the strongest argument in the report. Encode where the record shows both repetition and consequence.

## 5. Overlap check

Every installed skill is linked into one place, so check them all at once:

```sh
grep -h '^description:' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/skills/*/SKILL.md
```

For each candidate: **already covered** — drop it and say which skill (the common, useful outcome); **nearly covered** — propose a section or trigger phrase there, not a new skill; **genuinely new** — it survives, naming the neighbours it must be distinguished from.

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

**`Recommend` is advisory, not a decision** (§6a). `defer` is first-class and in steady state usually honest; report near-misses with their count. Finish with one line naming what you searched, which mode, and what you found nothing for — an empty steady-state report is ordinary; an empty **first** run is a result to distrust.

## 6a. Ask, one candidate at a time

**Every candidate that clears the bar goes to the operator as a choice** — the obvious discards included; a detection skill that also decides is an authoring skill with a filter. Use the host's interactive question facility and offer exactly three outcomes: **Develop** (hand it to a skill-authoring skill; no `SKILL.md` is written here, the verdict is), **Discard** (never propose again — **capture the operator's reason in one line**, which is the entire value of the record), **Defer** (keep it with its current count).

Practical shape: these facilities cap the number of questions per call — commonly four — so **batch, never truncate**. Six candidates is two rounds. Silently dropping the tail would report a filtered list as the whole list, which is the failure this skill exists to avoid.

The discard reason is where your recommendation is most likely wrong: recurrence and cost measure whether the *evidence* is real, not whether a **skill is the right form** — on-demand notes or an always-on `CLAUDE.md` preference may be the better home. Record the reason they give.

## 7. Close the loop — record the verdicts here

**Do not write the `SKILL.md`** — authoring is a different job. **Record the verdicts yourself**, into the worktree from *Where it runs*: one commit, `integrate`, `gc`. The verdict note is the only thing that persists: a run that decides and writes nothing leaves the vault indistinguishable from one never mined.

Each verdict becomes a `type: decision` note tagged `skill-candidate`:

- **Discarded** — the operator's reason, and the count it was discarded at. Without this the candidate is rediscovered every run and the reason is lost while the evidence keeps accumulating.
- **Developed** — what it was built from, so the skill's provenance points back at the notes that justified it.
- **Deferred** — the count, which is the only thing that makes it reconsiderable rather than merely rediscoverable.

Read those notes at the start of the next run (the frontmatter query from **Two modes**); skip anything declined unless its evidence count has grown past the count in the decline.

## Rules

- **In-session, on demand; never from a lifecycle hook** (engine `CLAUDE.md`, Hard safety rule).
- **Never invoke `checkpoint`, and never be invoked by it** — zero edges, in either direction.
- **Never propose a skill from the current session alone.**
- **Recommend; never decide** — every candidate clearing the bar goes to the operator.
- **Query the frontmatter, never the prose; filter on the bar, never on the count.**
