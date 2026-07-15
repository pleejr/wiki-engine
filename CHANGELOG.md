# Changelog

All notable changes to the wiki-engine. Versioned with [SemVer](https://semver.org/): **MAJOR** = a breaking framework change (node removed/renamed, frontmatter-schema change) that needs a migration; **MINOR** = additive (new node/tool/skill/convention), adopt with `bin/adopt.sh`; **PATCH** = fixes/docs. `bin/engine-version.sh` reports the delta and flags MAJOR bumps.

## [1.1.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh`; no migration.

### Added — semantic recall (optional RAG layer)
- `bin/rag-build.sh` — chunk every page by `##` heading, embed via a **local** endpoint (default Ollama `nomic-embed-text`; no cloud, no secrets), write a git-ignored, rebuildable `$WIKI/.rag/index.jsonl`. Boundary-filtered; incremental (only changed files re-embed).
- `bin/recall.sh` — embed a query, return nearest chunks as `file:line` pointers into the real pages (`--json` for machine use). Never replaces the markdown.
- `wiki-context` now auto-runs `recall.sh` so the user can **just prompt** without naming pages; `checkpoint` re-runs `rag-build.sh` after distilling, closing the distill→index→recall loop. Both degrade silently if no index / endpoint.
- `scaffold/gitignore.tmpl` ignores `.rag/`.
- All optional: a vault with no embedding endpoint never builds an index and falls back to the index-first map.

## [1.0.0] — 2026-07-14

First tagged release — the V1 framework.

### Node model
- Four lifecycle nodes (`repo`, `project`, `skill`, `memory`) + general knowledge (`entities`, `concepts`, `comparisons`, `queries`) + freeform **`notes/`** (domains via `tags:`, graduates to a structured node) + immutable `raw/`.
- Boundary law: every page carries `boundary: personal|work`; no secrets; content never crosses vaults.

### Skills (in-session only, never a hook)
- `wiki-repo` — ingest/refresh one repo page with git-ref provenance.
- `wiki-context` — session-start context router; runs the engine-version check (step 0).
- `checkpoint` — end-of-session project update + memory distill + native-memory prune + lint.
- `wiki-onboard` — one-time bulk seed of a fresh vault from existing native memory/repos/projects.

### Deterministic tooling (`bin/`, no LLM)
- `new-wiki.sh` (+ `scaffold/`, `scaffold/node-dirs.txt`) — one-command new-vault scaffold.
- `adopt.sh` — ensure a vault has the engine's current node folders (additive; run after a pin bump).
- `engine-version.sh` — report pinned vs latest engine by semver tag; flags MAJOR bumps.
- `lint.sh` — umbrella lint (memory + frontmatter-property + soft-wrap + skills-catalog); run by `checkpoint`.
- `gen-skills-index.sh` · `lint-memory.sh` · `reflow.sh` — catalog generation, memory validation, soft-wrap normalization.

### Conventions
- Soft-wrap: one physical line per paragraph/list item (renders in every Obsidian view; no per-machine setting).
- Wikilink-valued frontmatter (e.g. `repos`) must be a quoted YAML block list.
- Vocabulary: "vault" (the store) and "engine" (the shell); the boundary key is `boundary:`.

### Known gaps (see SCHEMA → Versioning & migration)
- `adopt.sh` is additive-only; a future MAJOR (node removal/rename, schema change) needs a dedicated `bin/migrate-*` + this MAJOR-version signal.
