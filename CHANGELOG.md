# Changelog

All notable changes to the wiki-engine. Versioned with [SemVer](https://semver.org/): **MAJOR** = a breaking framework change (node removed/renamed, frontmatter-schema change) that needs a migration; **MINOR** = additive (new node/tool/skill/convention), adopt with `bin/adopt.sh`; **PATCH** = fixes/docs. `bin/engine-version.sh` reports the delta and flags MAJOR bumps.

## [1.3.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh` (creates `raw/sessions/`).

### Added — auto-capture (the memory design's "axis 1") + review-and-promote
- `bin/rag-capture.sh` — deterministic session auto-capture: appends metadata (timestamp, repo/branch/HEAD, changed file names, recent commit subjects, optional `--note`) to `raw/sessions/YYYY-MM.md`. **Never file contents/diffs/secrets.** Reads a SessionEnd hook's `cwd` from stdin. **The one script safe to run from a hook** — it never invokes `claude`, spawns an agent, or recurses (the safe inverse of the `.ai-os` fork bomb). Example SessionEnd hook in SCHEMA.
- `wiki-context` gains a **review-and-promote** step: skim new `raw/sessions/` entries and propose (human-gated) promotions to `memory/`, then prune the promoted raw. In-session only.
- `checkpoint` treats `raw/sessions/` as a distill input and prunes promoted session blocks.
- `recall.sh` weights curated notes above raw: `raw/` chunks get a `RAG_RAW_WEIGHT` (default `0.80`) penalty so the auto-captured pile never drowns curated hits.
- `raw/sessions/` added to `node-dirs.txt` (disposable scratch, distinct from the immutable `raw/articles|papers|transcripts`).

## [1.2.2] — 2026-07-15

Patch — fix.

### Fixed
- `lint.sh` and `lint-memory.sh` now prune the git-ignored `.rag/` dir (like `engine`/`.git`/`.obsidian`). Without this, a RAG-provisioned vault's `.rag/venv` vendored package markdown tripped the soft-wrap and dead-link checks, failing `checkpoint`'s lint. Derived sidecar is never linted.

## [1.2.1] — 2026-07-15

Patch — quality tune + fix. Existing vaults: `rag-setup.sh --force` to adopt the new default model, then `rag-build.sh` (the index re-embeds automatically when the model changes).

### Changed
- Default local embedder is now **`fastembed` + `BAAI/bge-base-en-v1.5`** (contextual, 768-dim, ~210 MB) instead of static `model2vec` — markedly better recall (test scores ~0.3 → ~0.6–0.7). model2vec/potion remains a lighter opt-in via `RAG_PIP_PKG`/`RAG_LOCAL_MODEL`.
- `rag_embed.py` honors a pinned library (`RAG_LOCAL_LIB` or `.rag/config.json` `lib`) so build and query never probe the wrong backend; auto-detects otherwise.

### Fixed
- Chunk line pointers now skip leading blank lines — a page's intro chunk points at its real first line (e.g. the `# Title`), not the blank above it. `##` sections were already exact.
- Incremental reuse is keyed on `(file sha, model)`, so changing the embedding model correctly invalidates and re-embeds the index (no mixed-dimension corruption).

## [1.2.0] — 2026-07-15

Additive — adopt with `bin/adopt.sh`; existing vaults gain the runtime via `bin/rag-setup.sh`.

### Added — self-contained, packaged semantic recall
- `bin/rag-setup.sh` — provision a **git-ignored venv at `$WIKI/.rag/venv`** with a small CPU embedder (default `model2vec` + `minishlab/potion-base-8M`, ~30 MB, pure-numpy, offline), prefetch the model, write `.rag/config.json`. Idempotent.
- `new-wiki.sh` runs `rag-setup.sh` + an initial `rag-build.sh` automatically (skip with `--no-rag`), so *clone engine → generate vault → recall works* with **no server, no GPU, nothing external** after one install. Non-fatal if pip/network is restricted.
- `bin/rag_embed.py` — one shared embedding backend for build + query: in-process `local` (model2vec / fastembed / sentence-transformers, auto-detected) plus `ollama` / `openai` endpoints. Config precedence: env > `.rag/config.json` > default. Default backend is now **local**, not an endpoint.
- `rag-build.sh` / `recall.sh` use the vault's `.rag/venv` python and the shared module; batch-embed per file.
- CI: `py_compile bin/*.py`; scaffolder smoke test runs `--no-rag` (stays hermetic).

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
