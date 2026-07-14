# wiki-engine — the engine (generic router)

Shared machinery for an LLM-Wiki / Karpathy-pattern brain: the node model, page conventions, and skills. A wiki vault pins this as a submodule and imports this file from its own thin `CLAUDE.md`. This file is boundary-agnostic — the consuming wiki declares its own `brain`/identity.

## How to use a wiki — context router (do this; do NOT inhale everything)

1. Read the wiki's **`index.md`** first — it's the map.
2. Follow only the `[[links]]` relevant to the current task; load those pages on demand.
3. For a repo's context, check the page's provenance freshness before trusting it (see `SCHEMA.md`); refresh only if the repo's `ref`/`sha` moved.
4. Never load the whole wiki into context.

## Working style

- Terse; no filler. Push back on destructive actions and anti-patterns — ask rather than guess.
- No embeddings — retrieval is the link graph + frontmatter.

## Hard safety rule

- **NEVER invoke `claude` from a hook or any background/recursive spawn.** The `.ai-os` SessionEnd hook did this and fork-bombed (~13.7k sessions). Ingest / refresh / checkpoint / distill are **in-session, on-demand** actions only. See [[lesson-no-claude-in-hooks]].

Full conventions + node model: **`SCHEMA.md`** (in this engine). The vault's history: its **`log.md`**.
