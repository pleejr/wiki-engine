# wiki-engine — the engine (generic router)

Shared machinery for an LLM-Wiki / Karpathy-pattern vault: the node model, page conventions, and skills. A wiki vault pins this as a submodule and imports this file from its own thin `CLAUDE.md`. This file is boundary-agnostic — the consuming wiki declares its own `boundary`/identity.

## How to use a wiki — context router (do this; do NOT inhale everything)

1. Read the wiki's **`index.md`** first — it's the map.
2. Follow only the `[[links]]` relevant to the current task; load those pages on demand.
3. For a repo's context, check the page's provenance freshness before trusting it (see `SCHEMA.md`); refresh only if the repo's `ref`/`sha` moved.
4. Never load the whole wiki into context.

## Working style

- Terse; no filler. Push back on destructive actions and anti-patterns — ask rather than guess.
- No embeddings — retrieval is the link graph + frontmatter.

## Hard safety rule

- **Never spawn `claude` from a lifecycle hook without a re-entry guard — that is the fork-bomb trap.** The `.ai-os` SessionEnd hook ran `claude -p`; each child re-fired SessionEnd on exit → another `claude`, and so on (~13.7k sessions before it was caught). The danger is *structural*: the hook's trigger and its spawn are the same event. The real target is **detecting recursion and runaway agent generation**, not fearing headless `claude`.
- **Deliberate headless spawns are fine when bounded.** A human- or cron-initiated `claude -p` one-shot, or a subagent, is legitimate provided it: (1) carries a re-entry sentinel (e.g. increment `CLAUDE_SPAWN_DEPTH` and refuse above a small N); (2) is concurrency-bounded (lockfile / count cap); and (3) terminates — no self-requeuing watch loop. A hook may spawn `claude` **only** if it also cannot fire on an event its child can re-trigger *and* carries the sentinel.
- **Deterministic hooks need no guard** — git, file writes, `curl` (e.g. `rag-capture.sh`) can't recurse into `claude`, so wire them freely. Ingest / refresh / checkpoint / distill still default to **in-session, on-demand**; automate them headlessly only with the guards above. See [[lesson-no-claude-in-hooks]].

Full conventions + node model: **`SCHEMA.md`** (in this engine). The vault's history: its **`log.md`**.
