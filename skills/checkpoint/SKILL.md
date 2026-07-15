---
name: checkpoint
description: End-of-session wrap-up ritual. Updates the active project's page (Current state + Next steps) and appends a log.md entry, then distills durable facts from this session into memory/ notes. Use when finishing or pausing work on a project, or when a keeper fact/decision/lesson emerged. In-session only — never a hook.
status: active
summary: "end-of-session: update project page + `log.md`, distill memory. In-session only."
updated: 2026-07-13
used_by: []
---

# checkpoint — capture where I left off + distill memory

Run this deliberately at the end of a work session. **Vault**: `$WIKI_PATH` — the vault root; must be set. Two jobs:

## 1. Project state (if a project is active)
- Open/create `$WIKI_PATH/projects/<slug>.md` (frontmatter `type: project`, `status: active|paused|done`, `repos: [[...]]`).
- **Overwrite** the **Current state** section with where things stand; update **Next steps**.
- **Append** (never overwrite) to **Key decisions** if a decision was made.
- Append one dated line to `$WIKI_PATH/log.md`, tagged with the project.

## 2. Distill memory (raw → curated)
- Review what emerged this session — Claude Code's native per-project memory **and** any `$WIKI_PATH/raw/sessions/` entries auto-captured by `rag-capture.sh` — as raw input.
- Promote **durable** facts into `$WIKI_PATH/memory/` notes with the right `type`: `preference` (how I work) · `decision` (a chosen path + why) · `lesson` (a hard-won rule).
- Give each ≥2 `[[wikilinks]]`; mark any note it supersedes as `status: superseded`.
- Add/refresh the `$WIKI_PATH/index.md` entry.

## 3. Prune the raw source (keep the vault authoritative)
- **Only after** a native note's durable content is captured in the vault, remove it from native memory (`~/.claude/projects/*/memory/*.md`) and drop its line from that dir's `MEMORY.md` index — so the vault is the single source of truth and native can't drift into a competing authority.
- Same for **auto-captured `raw/sessions/` entries**: once a session's keeper is promoted to `memory/`/a project page, prune that session block so `raw/sessions` stays a short disposable buffer, not an ever-growing pile that dilutes recall. (Unlike immutable `raw/articles|papers|transcripts`, `raw/sessions` is disposable scratch.)
- **Never delete native content you haven't first promoted.** If a native note isn't worth keeping, dropping it is fine; if it's worth keeping, it must land in the vault before you prune it.
- Exception — the always-on layer: native `MEMORY.md` is auto-loaded every session, the vault is on-demand. Anything that must be present *every* session (core behavioral guidance) belongs in `CLAUDE.md`, not left in native as a workaround. Move it there, then prune.
- Deletion is a **guided in-session action** — confirm before removing. Never wire pruning to a hook or background spawn. See [[lesson-no-claude-in-hooks]].

## 4. Lint before finishing
- Run `engine/bin/lint.sh` (the umbrella: memory notes + frontmatter-property validity + soft-wrap drift + skills-catalog drift). Fix any failures before you consider the checkpoint done — don't commit a vault that fails lint.

## 5. Refresh semantic recall (if enabled)
- If the vault has a `.rag` index (`$WIKI_PATH/.rag/index.jsonl` exists), run `engine/bin/rag-build.sh` so this session's new/updated notes are recallable next session. This closes the loop: `checkpoint` distills markdown → `rag-build` re-indexes it (incremental; only changed files re-embed) → `wiki-context` auto-recalls it. Skip if the vault has no index or the embedding endpoint is down — recall is optional; the map still works. Deterministic (a local embedding model, never `claude`), so it's safe here, but like everything else this is **in-session, never a hook**.

## Rules
- **In-session, on demand only. NEVER wire this to a hook or a background/recursive `claude` spawn** — that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- `boundary: personal`; no secrets; personal git identity.
- Prefer few high-signal notes over many; this is curation, not logging.
