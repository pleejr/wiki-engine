---
name: distill
description: End-of-session wrap-up. Records what this session made durable — the active project's Current state and Next steps, decisions, and preference/decision/lesson notes in memory/ — then runs distill-finish.sh, which lints, lands the commit by the vault's declared route, ages out the capture buffer and retires the session worktree, and ends with an explicit SAFE TO CLOSE or NOT SAFE TO CLOSE verdict naming every outstanding item (running shells or subagents, unmerged pull requests, unpushed branches, leftover worktrees). Use when finishing or pausing work, or when a keeper fact, decision or lesson emerged. It never offers or runs the `mine` pass. In-session, on demand — never from a lifecycle hook.
status: active
summary: "end-of-session: record project state and durable notes, run distill-finish.sh, then say SAFE TO CLOSE or what is still owed. Never offers the mining pass."
updated: 2026-10-06
---

# distill — record what lasts, then say whether the session can close

**Vault**: `$WIKI_PATH`, set. The judgement is here; every mechanical step is `distill-finish.sh`.

## 0. Isolate
`WORK="$(${CLAUDE_SKILL_DIR}/../../bin/vault-worktree.sh ensure)"` — check its exit status (non-zero: not isolated, resolve first) and read its stderr (the only place a stale base is reported). Make every edit and commit in `$WORK`. Stage explicit paths, never `git add -A`.

## 1. Project state (if a project is active)
In `projects/<slug>.md`: **overwrite** Current state, update Next steps, **append** to Key decisions when a decision was made. Keep `status:` (`active|paused|done`) and the one-line `summary:` current — they generate the index's Projects buckets.

## 2. Durable notes
- Promote what will still matter in a month into `memory/` as `preference` (how the operator works), `decision` (a path chosen, and why) or `lesson` (a rule learned the hard way). Few, specific notes.
- Each note gets ≥2 `[[wikilinks]]`, `created:` and `updated:`; mark a note it replaces `status: superseded` with `superseded_by:`; add its line to `index.md`.
- Record what was *done*, not only the conclusion — `mine`, the operator-invoked mining skill, can count a done procedure as an occurrence and cannot count a conclusion.
- Inputs: this conversation, and the capture buffer `raw/sessions/` in **canonical** `$WIKI_PATH` (git-ignored, so absent from `$WORK`). The buffer is never pruned by hand; step 4 ages it out.

## 3. Log line — only if nothing else logged this work
Append one dated line to `log.md` (`- **YYYY-MM-DD (tag)** — …`, linking the notes from step 2) **only** when no other skill (`drain`, `update`, `verify`, `ingest`) already logged this session's work. The project page and notes are the record; the log is the index to them.

## 4. Commit, then finish
Commit the edits in `$WORK`, then run from `$WORK`:

```sh
${CLAUDE_SKILL_DIR}/../../bin/distill-finish.sh --repo <each other repository this session changed>
```

It refuses an uncommitted tree, refuses a vault with no declared route (`publish = direct` or `publish = pr` in `.wiki-gates.conf` — ask the operator which; never guess), lints, lands the session branch (a direct vault integrates and pushes; a pull-request vault pushes the branch and opens its pull request, and never integrates), rebuilds recall, ages out old capture-buffer months, and retires this worktree. It prints `VAULT DONE` or `VAULT OUTSTANDING` with the command that clears each item, and `REVIEW` lines for the other repositories.

## 5. Say whether the session can close
The verdict is yours, from three sources:
1. The script's `VAULT` line.
2. Each `REVIEW` line: outstanding if this session made it (its branch, its pull request, its worktree, its edits); a peer session's work is reported as `info`, never cleared.
3. This session's own running work, which no script can see: background shells, monitors, subagents and scheduled wakeups still active. Check your task list.

End with exactly one of:

- `SAFE TO CLOSE — distilled <n> note(s); <project>; nothing outstanding.`
- `NOT SAFE TO CLOSE — <k> outstanding:` then one line per item with the command that clears it.

## Rules
- In-session and operator-initiated; never from a lifecycle hook (engine `CLAUDE.md`).
- Never offer or start the `mine` pass; the operator runs it.
- Touch only this session's worktree, branches and pull requests; never a peer's.
- `boundary:` matches what the vault declares; no secrets; commit under the vault's git identity.
