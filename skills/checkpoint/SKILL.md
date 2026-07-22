---
name: checkpoint
description: End-of-session wrap-up ritual. Updates the active project's page (Current state + Next steps) and appends a log.md entry, then distills durable facts from this session into memory/ notes. Use when finishing or pausing work on a project, or when a keeper fact/decision/lesson emerged. In-session only — never a hook.
status: active
summary: "end-of-session: update project page + `log.md`, distill memory. In-session only."
updated: 2026-07-21
used_by: []
---

# checkpoint — capture where I left off + distill memory

Run this deliberately at the end of a work session. **Vault**: `$WIKI_PATH` — the vault root; must be set. Two jobs (§0 is setup):

## 0. Isolate writes in a worktree (concurrency safety)

Before editing any vault file, take an isolated working copy so a second concurrent session can't clobber your edits or move HEAD under you — two sessions otherwise share one `$WIKI_PATH` working tree (one HEAD, one set of files on disk), where `git checkout -b` in one disrupts the other and simultaneous writes to a page are silent last-writer-wins.

- `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)"` — creates (or reuses) a per-session `git worktree` on its own `wt/<session>` branch off `origin/main` and prints its path; cheap (~0.4s, <1 MB, since only tracked text is checked out). Idempotent within a session — it keys the worktree on `$CLAUDE_CODE_SESSION_ID`, so calling `ensure` again returns the *same* worktree instead of spawning a duplicate. Opt out with `WIKI_WORKTREE=0` (writes then go straight to `$WIKI_PATH`, the legacy behavior).
- Make **all** edits, commits, and lint runs against `$WORK`, never `$WIKI_PATH` directly.
- Run engine tooling from canonical (the `engine/` submodule is not checked out inside a worktree): e.g. `$WIKI_PATH/engine/bin/lint.sh --wiki "$WORK"`.
- When this session's writes are committed, **integrate** the `wt/<session>` branch per the vault's git convention (fast-forward/merge to `main`, or push + open a PR), then retire the worktree with `$WIKI_PATH/engine/bin/vault-worktree.sh gc "$WORK"` — passing the path retires *this* worktree immediately (the bare, argument-less `gc` only sweeps orphans older than `WIKI_WT_STALE_HOURS`, so it can never retire the one you just created). Both forms retire clean worktrees only — never discarding uncommitted work, and keeping the branch if it still holds unmerged commits. Run a bare `gc` too if you want to sweep orphans from crashed sessions.

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

## 3. Prune the raw source (keep the vault authoritative)
- **Only after** a native note's durable content is captured in the vault, remove it from native memory (`~/.claude/projects/*/memory/*.md`) and drop its line from that dir's `MEMORY.md` index — so the vault is the single source of truth and native can't drift into a competing authority.
- Same for **auto-captured `raw/sessions/` entries**: once a session's keeper is promoted to `memory/`/a project page, prune that session block so `raw/sessions` stays a short disposable buffer, not an ever-growing pile that dilutes recall. (Unlike immutable `raw/articles|papers|transcripts`, `raw/sessions` is disposable scratch.)
- **Never delete native content you haven't first promoted.** If a native note isn't worth keeping, dropping it is fine; if it's worth keeping, it must land in the vault before you prune it.
- Exception — the always-on layer: native `MEMORY.md` is auto-loaded every session, the vault is on-demand. Anything that must be present *every* session (core behavioral guidance) belongs in `CLAUDE.md`, not left in native as a workaround. Move it there, then prune.
- Deletion is a **guided in-session action** — confirm before removing. Never wire pruning to a hook or background spawn. See [[lesson-no-claude-in-hooks]].

## 4. Lint before finishing
- Run `$WIKI_PATH/engine/bin/lint.sh --wiki "$WORK"` (the umbrella: memory notes + frontmatter-property validity + soft-wrap drift + skills-catalog drift + projects-catalog drift), pointing it at the worktree from §0. Fix any failures before you consider the checkpoint done — don't commit a vault that fails lint.

## 5. Refresh semantic recall (if enabled)
- If the vault has a `.rag` index (`$WIKI_PATH/.rag/index.jsonl` exists), run `engine/bin/rag-build.sh` **against canonical `$WIKI_PATH` after the §0 worktree branch is integrated** (the `.rag/` index is untracked and lives only in the canonical checkout, not the worktree) so this session's new/updated notes are recallable next session. This closes the loop: `checkpoint` distills markdown → `rag-build` re-indexes it (incremental; only changed files re-embed) → `wiki-context` auto-recalls it. Skip if the vault has no index or the embedding endpoint is down — recall is optional; the map still works. Deterministic (a local embedding model, never `claude`), so it's safe here, but like everything else this is **in-session, never a hook**.

## Rules
- **In-session, on demand only. NEVER wire this to a hook or a background/recursive `claude` spawn** — that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- `boundary: personal`; no secrets; personal git identity.
- Prefer few high-signal notes over many; this is curation, not logging.
