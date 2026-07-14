# wiki-engine

Reusable machinery for an LLM-Wiki / Karpathy-pattern second brain, maintained **in-session by Claude
Code** (first-party, plan-covered — no orchestrator). Extracted from `pleejr-wiki` so the engine can be
managed once and pinned per wiki — engine updates never silently drift across vaults.

## What's here

- `skills/` — the three Claude Code skills: `wiki-repo`, `wiki-context`, `checkpoint`.
- `SCHEMA.md` — node model, three layers, page conventions, memory lifecycle.
- `CLAUDE.md` — generic context router a wiki imports from its own thin `CLAUDE.md`.

## Using it in a wiki

1. `git submodule add <this-repo-url> engine` in the wiki repo; commit the pinned SHA.
2. Point `~/.claude/skills/{wiki-repo,wiki-context,checkpoint}` symlinks at this engine's `skills/*`.
3. Set `$WIKI_PATH` to the wiki root (the skills resolve every path from it).
4. Give the wiki a thin `CLAUDE.md`: its boundary/identity, then import `engine/CLAUDE.md`.
5. Bump the submodule pointer to adopt a newer engine — opt-in, per wiki.

See `SCHEMA.md` for the full spec.
