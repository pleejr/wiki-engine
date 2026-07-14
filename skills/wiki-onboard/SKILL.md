---
name: wiki-onboard
description: Seed a freshly-scaffolded (or newly-adopted) wiki vault from what already exists in the environment — distill Claude Code native memories into curated memory/ notes, ingest the repos you work in as repo pages, stub project pages for in-flight work, and regenerate the skills catalog. One-time bootstrap; the inverse of checkpoint. In-session only — never a hook.
status: active
summary: seed a freshly-scaffolded vault from existing memories, repos, and skills.
updated: 2026-07-14
used_by: []
---

# wiki-onboard — seed an empty vault from what already exists

Run **once**, right after `new-wiki.sh` (or after adopting the engine in an existing setup), to fill the empty node folders from the environment instead of starting cold. `checkpoint` keeps a vault current session-to-session; **this is the initial bulk seed**. Curation, not a dump — prefer a few high-signal pages over importing everything.

**Vault**: `$WIKI_PATH` — the vault root; must be set (scaffolded, with `engine/` pinned).

## Boundary first (non-negotiable)
- Read the vault's `brain` (`personal` | `work`) from its `CLAUDE.md`. **Import only matching material.** Never pull work data into a personal vault or vice versa — crossover is a deliberate manual export.
- No secrets (keys, tokens, credentials) ever land in a page. See [[lesson-no-claude-in-hooks]].

## Steps

1. **Inventory, then confirm.** Survey the sources below and present a short proposed manifest (memories to distill, repos to ingest, projects to stub). **Ask before creating many pages.**

2. **Memories → `memory/`.** Read Claude Code native memory (`~/.claude/projects/*/memory/*.md` and its `MEMORY.md` index) plus any preferences in `~/.claude/CLAUDE.md`. Distill **durable** facts into curated notes with the right `type` (`preference` · `decision` · `lesson` · `memory`), each with frontmatter (`title, created, updated, type, status, tags, sources, brain`) and **≥2 `[[wikilinks]]`**. Native memory is raw scratch — promote the keepers, drop the transient. Same distillation as `checkpoint`, done in bulk.
   - **Then prune the raw source.** Once a native note's durable content is in the vault, remove it from native memory and drop its `MEMORY.md` index line, so the vault is the single authority. **Never delete native content you haven't first captured.** Anything that must load *every* session (core behavioral guidance) belongs in `CLAUDE.md`, not left in native — move it there, then prune. Deletion is a guided in-session action; confirm before removing, never hook it. See [[lesson-no-claude-in-hooks]].

3. **Repos → `repos/`.** For each repo you actively work in, invoke **`wiki-repo`** (one per run) to create its page with git-ref provenance. Don't hand-write repo pages here.

4. **Projects → `projects/`.** For in-flight work, stub `projects/<slug>.md` (`type: project`, `status: active|paused`, `repos: [[...]]`) with Goal · Linked repos · Key decisions · Current state · Next steps. Link each to its repo pages.

5. **Skills.** The engine's `skills/` are already linked by the scaffolder. Inventory any other `~/.claude/skills/*`; note user-authored ones worth promoting into the engine (a manual add — don't copy them into the vault). Then regenerate the catalog: `engine/bin/gen-skills-index.sh`.

6. **Finalize.** Refresh `$WIKI_PATH/index.md` sections for the new pages, run `engine/bin/lint-memory.sh` and fix any errors, and append a dated `log.md` line summarizing the seed.

## Rules
- **In-session, on demand only. NEVER wire to a hook or a background/recursive `claude` spawn** — that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- One-time bootstrap: if the vault already has substantial content, prefer `checkpoint`/`wiki-repo` for incremental updates instead of re-onboarding.
- Respect the boundary and the no-secrets rule above at every step.
