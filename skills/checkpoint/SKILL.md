---
name: checkpoint
description: End-of-session wrap-up ritual. Updates the active project's page (Current state + Next steps) and appends a log.md entry, distills durable facts from this session into memory/ notes, then ends by OFFERING the `skill-candidates` mining pass rather than running it inline — deferring writes nothing, and accepting starts it as a separate session instead of printing instructions for starting one. Use when finishing or pausing work on a project, or when a keeper fact/decision/lesson emerged. In-session, on demand — never from a session-lifecycle hook.
status: active
summary: "end-of-session: update project page + `log.md`, distill memory, then offer the skill-mining pass — declined it writes nothing, accepted it starts elsewhere. In-session only."
updated: 2026-09-03
---

# checkpoint — capture where I left off + distill memory

Run this deliberately at the end of a work session. **Vault**: `$WIKI_PATH` — the vault root; must be set. Two jobs (§0 is setup):

## 0. Isolate writes in a worktree (concurrency safety)

Two sessions otherwise share one working tree, where simultaneous writes are silent last-writer-wins. Before editing any vault file:

- `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)" || { echo "not isolated — resolve before writing"; }` — creates or reuses a per-session worktree on its own `wt/<session>` branch off `origin/main` and prints its path. **Check the exit status**: non-zero means it could not isolate and printed canonical instead. **Read its stderr** — it is the only place a stale base is mentioned, and the returned path looks identical either way: a reattached branch behind `origin/main`, or canonical `main` holding unpushed commits the fresh cut lacks. **Rebase before you survey, not just before you write** — a stale base corrupts *reads*, so a `grep` for work that already exists prints nothing and exits 0. Idempotent within a session; opt out with `WIKI_WORKTREE=0`.
- Make **all edits to TRACKED vault content** — and every commit and lint run — against `$WORK`, never `$WIKI_PATH` directly.
- **Carve-out: git-ignored per-machine state is edited in canonical `$WIKI_PATH`.** A worktree checks out tracked files only, so that state is not there, and its absence looks exactly like "nothing to do". The two are `raw/sessions/*.md` (§3) and `.rag/` (§5); any step added here that touches an ignored path must name canonical the same way.
- Run engine tooling from canonical — the `engine/` submodule is not checked out inside a worktree: `$WIKI_PATH/engine/bin/lint.sh --wiki "$WORK"`.
- **Stage explicit paths, never `git add -A`** — it is exactly how one session swept a peer's uncommitted work into its own commit.
- Optional: `vault-worktree.sh lease projects/ memory/` declares what you will touch and warns if a live peer declared the same area.
- When the writes are committed, `$WIKI_PATH/engine/bin/vault-worktree.sh integrate` (from inside `$WORK`) rebases your branch onto `main` in your worktree and fast-forwards `main` under a lock — exit **3**: resolve the conflict and re-run; **4**: another session holds the lock. Then `$WIKI_PATH/engine/bin/vault-worktree.sh gc "$WORK"` retires this worktree (clean only; never discards uncommitted work or an unmerged branch).

## 1. Project state (if a project is active)
- Open/create `$WIKI_PATH/projects/<slug>.md` (frontmatter `type: project`, `status: active|paused|done`, `repos: [[...]]`).
- **Overwrite** the **Current state** section with where things stand; update **Next steps**.
- **Append** (never overwrite) to **Key decisions** if a decision was made.
- Keep the page's frontmatter `status:` (`active|paused|done`) and one-line `summary:` current — these drive the generated `index.md` Projects buckets (§4). Closing a project = flip `status: done`.
- Append one dated line to `$WIKI_PATH/log.md`, tagged with the project.

## 2. Distill memory (raw → curated)
- Review what emerged this session — Claude Code's native per-project memory **and** any `$WIKI_PATH/raw/sessions/` entries auto-captured by `rag-capture.sh` — as raw input.
- Promote **durable** facts into `$WIKI_PATH/memory/` notes with the right `type`: `preference` (how I work) · `decision` (a chosen path + why) · `lesson` (a hard-won rule).
- Give each ≥2 `[[wikilinks]]`; mark any note it supersedes as `status: superseded`.
- Add/refresh the `$WIKI_PATH/index.md` memory entry. For **project** pages, don't hand-edit the index Projects buckets — regenerate them from frontmatter: `$WIKI_PATH/engine/bin/gen-projects-index.sh --wiki "$WORK"` (splices between the `<!-- projects:start/end -->` sentinels, same pattern as the skills catalog).
- **The notes this step writes are the evidence base for `skill-candidates`** (§6), which reads them back out to find procedures repeated often enough to deserve a skill. Nothing here needs to anticipate that — just date the notes and keep them specific about what was *done*, since a note recording only a conclusion cannot later be counted as an occurrence.

## 3. Prune the raw source (keep the vault authoritative)
- **Only after** a native note's durable content is captured in the vault, remove it from native memory (`~/.claude/projects/*/memory/*.md`) and drop its line from that dir's `MEMORY.md` index.
- Same for **auto-captured `raw/sessions/` entries** — prune them **in canonical `$WIKI_PATH`, not in `$WORK`** (`raw/sessions/*.md` is git-ignored per-machine state, so it lives only in the canonical checkout). Once a session's keeper is promoted, prune that block so `raw/sessions` stays a short disposable buffer. No commit and no integrate: the buffer is untracked. **An empty `raw/sessions` in `$WORK` is what the wrong tree looks like, not evidence there is nothing to prune** — check with `git check-ignore`.
- **Never delete native content you haven't first promoted.** Anything that must load *every* session belongs in `CLAUDE.md`, not left in native as a workaround — move it there, then prune.
- **The confirm is for discarding, not for pruning** — three states, and only one of them is a decision. (a) Content **already promoted**: prune it in the same turn without asking. Promotion *was* the judgement; deleting the spent copy destroys nothing and decides nothing. (b) Content **worth keeping but not yet promoted**: promote it, which turns it into case (a) — never a confirm, because the answer is not "delete?" but "capture it first". (c) Content **not worth keeping at all**: that is a discard, it is unrecoverable, and it is the one thing here to confirm before doing. So: no question for an already-promoted `raw/sessions` block; report the prune in one clause alongside the rest of the checkpoint, and note it in the buffer file itself — a one-line `_(pruned <date>: <what and why it was spent>)_` marker in place of the removed block, so the buffer records its own history and a future reader can tell a prune from a capture that never happened.
- **The two prune targets differ in how mechanically you can tell**, so they get different defaults. A `raw/sessions` block is promoted when its keeper is visibly in `log.md`/`memory/`/a project page — near enough to a lookup, so decide it yourself. A **native memory note** is promoted only when its *content* is captured, which is a judgement about equivalence rather than a lookup: prune it unasked when you wrote the vault note yourself this session and can see both texts, and confirm when you are relying on an earlier session's claim that it was captured.
- **Report a backlog; it is a symptom, not a decision.** Many blocks, or blocks spanning several sessions, means the prune stopped running — state the count.
- Pruning is **in-session and human-initiated** — never a hook, never an unattended sweep; no sentinel or concurrency bound makes an unattended delete correct.

## 4. Lint before finishing
- Run `$WIKI_PATH/engine/bin/lint.sh --wiki "$WORK"` (the umbrella: memory notes + frontmatter-property validity + soft-wrap drift + skills-catalog drift + projects-catalog drift), pointing it at the worktree from §0. Fix any failures before you consider the checkpoint done — don't commit a vault that fails lint.

## 5. Refresh semantic recall (if enabled)
- If the vault has a `.rag` index (`$WIKI_PATH/.rag/index.jsonl` exists), run `$WIKI_PATH/engine/bin/rag-build.sh` **against canonical `$WIKI_PATH` after the §0 worktree is integrated** — the `.rag/` index is untracked and lives only in the canonical checkout — so this session's notes are recallable next session (incremental; only changed files re-embed). Skip if there is no index or the embedder is down; recall is optional. `rag-build.sh` is deterministic and hook-safe on its own; it is `checkpoint` that must stay in-session.

## 6. Offer the mining pass — do not run it

`skill-candidates` reads the notes §2 just wrote and reports the procedures that have repeated often enough to deserve a skill. **End the checkpoint by offering it, and stop there.** Two outcomes:

- **Defer** — the default; it writes nothing. The evidence is the committed notes, so a later run re-derives every candidate.
- **Accept** — start it as its own unit of work rather than describing how to:

  ```bash
  $WIKI_PATH/engine/bin/spawn-session.sh --cwd "$WIKI_PATH" --what 'the skill-mining pass' \
    --prompt 'Run the skill-candidates mining pass over this vault: report the procedures whose dated evidence shows them repeating, and record the verdicts.'
  ```

  Relay what it prints and stop — it names a handle for the session it started, or prints by-hand instructions and why. Never wait on or read the spawned session; it records its own verdicts.

Offer it *here*: mining reads the notes this pass just committed, and §0's worktree is retired, so a run opens its own. An offer, not a run: a `develop` verdict implies authoring and an eval, a chain the operator starts deliberately. Nothing started here may reach `checkpoint`; the start stays gated on an explicit accept, never a lifecycle event.

## Rules
- **In-session, on demand; never from a lifecycle hook** (engine `CLAUDE.md`, Hard safety rule).
- `boundary:` **must match what the vault declares in its own `CLAUDE.md`** — the engine names no value. No secrets; commit under the vault's declared git identity. `lint.sh` errors on a mismatch, because a mis-stamped page is dropped from semantic recall.
- Prefer few high-signal notes over many; this is curation, not logging.
