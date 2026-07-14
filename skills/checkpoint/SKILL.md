---
name: checkpoint
description: End-of-session wrap-up ritual. Updates the active project's page (Current state + Next steps) and appends a log.md entry, then distills durable facts from this session into memory/ notes. Use when finishing or pausing work on a project, or when a keeper fact/decision/lesson emerged. In-session only — never a hook.
status: active
summary: "end-of-session: update project page + `log.md`, distill memory. In-session only."
updated: 2026-07-13
used_by: []
---

# checkpoint — capture where I left off + distill memory

Run this deliberately at the end of a work session. **Vault**: `$WIKI_PATH` — the vault root; must be
set. Two jobs:

## 1. Project state (if a project is active)
- Open/create `$WIKI_PATH/projects/<slug>.md` (frontmatter `type: project`,
  `status: active|paused|done`, `repos: [[...]]`).
- **Overwrite** the **Current state** section with where things stand; update **Next steps**.
- **Append** (never overwrite) to **Key decisions** if a decision was made.
- Append one dated line to `$WIKI_PATH/log.md`, tagged with the project.

## 2. Distill memory (raw → curated)
- Review what emerged this session (and Claude Code's native per-project memory as raw input).
- Promote **durable** facts into `$WIKI_PATH/memory/` notes with the right `type`:
  `preference` (how I work) · `decision` (a chosen path + why) · `lesson` (a hard-won rule).
- Give each ≥2 `[[wikilinks]]`; mark any note it supersedes as `status: superseded`.
- Add/refresh the `$WIKI_PATH/index.md` entry.

## Rules
- **In-session, on demand only. NEVER wire this to a hook or a background/recursive `claude` spawn** —
  that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- `brain: personal`; no secrets; personal git identity.
- Prefer few high-signal notes over many; this is curation, not logging.
