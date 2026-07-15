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
2. **Semantic recall (if the vault has a `.rag` index).** If `$WIKI_PATH/.rag/index.jsonl` exists, run `$WIKI_PATH/engine/bin/recall.sh --json "<the user's task/prompt>"` and treat the returned `file:line` hits as candidate pages to load — so the user can **just start prompting** without naming pages. This finds pages by *meaning* (e.g. a query about "cooling" surfaces a note that only says "thermals") that the index map or a keyword scan would miss. The index map (step 1) stays authoritative for *what exists*; recall just points at the relevant slice. If the endpoint is unreachable or no index exists, skip silently and rely on the map. Keep the index fresh with `engine/bin/rag-build.sh` (run by `checkpoint`).
3. **Select** the pages to load — union of the recall hits and any `[[links]]` from the map relevant to the task (the repo you're in, the active project, related decisions/preferences). Prefer a focused set over breadth.
4. **Freshness-check any repo page** you're about to rely on:
   - Compare the page's frontmatter `ref`/`sha` to `git -C <repo> describe --tags --always` / `git -C <repo> rev-parse --short HEAD`.
   - **On a mismatch**, invoke **`wiki-repo`** to refresh that page, then use the refreshed content.
   - Project and memory pages have no git signal — use as-is (they're refreshed by `checkpoint`/lint).
5. **Load** the selected pages into context and proceed with the task.
6. **Review & promote (raw → curated).** If `$WIKI_PATH/raw/sessions/` has entries newer than the last `log.md` line (i.e. auto-captured by `rag-capture.sh` since the last checkpoint), skim them and **propose** durable promotions — a `decision`/`lesson`/`preference` in `memory/`, or a project-page update — then **ask before writing**. This is the curation gate: raw is already recallable (see step 2), but promotion is what makes a fact canonical, linked, and eligible for the always-on `CLAUDE.md`. Respect the boundary and drop anything sensitive rather than promoting it. After a promotion lands in the vault, you may prune the promoted `raw/sessions` lines (guided, confirmed). **In-session only — never a hook or background spawn.** If there are no new raw entries, skip silently.

## Rules
- Do not load pages you don't need. Do not preload all repos.
- In-session only; no hooks/background spawns. See [[lesson-no-claude-in-hooks]].
- Promotion and pruning are judgment calls made **with** the user — never automate them into a hook. Only `rag-capture.sh` (deterministic, no `claude`) may run from a hook.
