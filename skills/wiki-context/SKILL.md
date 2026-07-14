---
name: wiki-context
description: Load relevant context from the wiki vault ($WIKI_PATH) for the current task — index-first, lazy, with a repo freshness check. Use at the start of a work session or whenever you need context about a repo, project, prior decision, or preference. Loads only what's relevant; never the whole wiki.
status: active
summary: index-first, lazy context router with repo freshness check.
updated: 2026-07-13
used_by: []
---

# wiki-context — the context router

Pull in just-enough context without inhaling the vault. This is the token-saver.

**Vault**: `$WIKI_PATH` — the vault root; must be set.

## Steps
0. **Engine freshness (session start).** Run `$WIKI_PATH/engine/bin/engine-version.sh`. If it reports *update available*, tell the user the pinned vs latest SHA and **offer** to update — `git -C $WIKI_PATH submodule update --remote engine && $WIKI_PATH/engine/bin/adopt.sh && git -C $WIKI_PATH commit -am 'Bump engine'` — but **do not auto-apply**; it's the user's call. If up to date or offline, say nothing and continue.
1. **Read `$WIKI_PATH/index.md`** (the map) and, if useful, recent `$WIKI_PATH/log.md` entries.
2. **Select** only the `[[links]]` relevant to the current task (the repo you're in, the active project, related decisions/preferences). Prefer 1–3 pages over breadth.
3. **Freshness-check any repo page** you're about to rely on:
   - Compare the page's frontmatter `ref`/`sha` to `git -C <repo> describe --tags --always` / `git -C <repo> rev-parse --short HEAD`.
   - **On a mismatch**, invoke **`wiki-repo`** to refresh that page, then use the refreshed content.
   - Project and memory pages have no git signal — use as-is (they're refreshed by `checkpoint`/lint).
4. **Load** the selected pages into context and proceed with the task.

## Rules
- Do not load pages you don't need. Do not preload all repos.
- In-session only; no hooks/background spawns. See [[lesson-no-claude-in-hooks]].
