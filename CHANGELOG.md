# Changelog

All notable changes to the wiki-engine. Versioned with [SemVer](https://semver.org/): **MAJOR** = a breaking framework change (node removed/renamed, frontmatter-schema change) that needs a migration; **MINOR** = additive (new node/tool/skill/convention), adopt with `bin/adopt.sh`; **PATCH** = fixes/docs. `bin/engine-version.sh` reports the delta and flags MAJOR bumps.

## [1.5.2] — 2026-07-16

Patch — docs + license for the now-public repo.

### Added
- `LICENSE` — MIT.
- `README` **Prerequisites** section: what to have in place before adopting — Claude Code installed + signed in, git, a POSIX/symlink-capable shell (required); a git-host account + authenticated `gh` for remote creation (recommended; `--remote <url>` or none otherwise); Python 3.9+ for the optional RAG layer; and the up-front boundary/identity decision.

### Changed
- Dropped the specific personal vault name from the README intro now that the repo is public (the engine holds no identity by design). Swept the tree: no identity/account references remain in committed content.

## [1.5.1] — 2026-07-16

Patch — fix the cold-start bootstrap for `/wiki-adopt`.

### Fixed
- **`/wiki-adopt` was undiscoverable on a fresh machine.** Claude Code discovers skills only from `~/.claude/skills/` and `<project>/.claude/skills/`, never a cloned repo's bare `skills/` dir — so `git clone` + `cd wiki-engine` did *not* expose the skill (the `v1.5.0` README instruction was wrong for the first run). Added **`bin/link-skills.sh`**: idempotent symlinker of the engine's skills into `~/.claude/skills/`, non-destructive (an existing link to this engine is kept; a foreign slot is warn+skipped, `--force` to repoint), never calls `claude`. `new-wiki.sh` now calls it instead of its own inline `ln` loop (one implementation, and it no longer silently hijacks a foreign symlink).
- Docs corrected: the adoption flow is now `clone → bin/link-skills.sh → claude (any folder) → /wiki-adopt`, documented in `README`, `USAGE`, and the `wiki-adopt` skill.

## [1.5.0] — 2026-07-16

Additive — one-shot adoption on a fresh machine; adopt with `bin/adopt.sh` (no vault changes required).

### Added
- `skills/wiki-adopt/` — the adoption front door: run once from a standalone engine clone (you start the session, so no recursive `claude` spawn) to drive scaffold → wire the machine → seed. Gathers the vault's boundary/identity/remote, runs `new-wiki.sh` full-auto, points the session at the vault, then chains into `wiki-onboard`. Guarded for **single-vault machines only** (the wiring is global); a dual-boundary machine scaffolds without wiring and scopes activation per-directory.
- `bin/new-wiki.sh` — now **prompts** for the required args (`--path`/`--boundary`/`--email`/`--git-name`) when run interactively, and gained opt-in machine-wiring flags: `--wire-shell [RC]` (append `export WIKI_PATH` to the shell rc), `--wire-claude-md` (append the always-on `@…/CLAUDE.md` import), and `--remote URL` / `--create-remote OWNER/NAME` (+`--visibility`) to add and push the git remote (`gh`). All wiring is idempotent — a pre-existing `WIKI_PATH` export or import line is left untouched with a warning. The closing summary lists what was auto-wired and prints only the steps still left manual.

Design: the deterministic scaffold + wiring stays in `new-wiki.sh`; the skill adds conversational prompting and the in-session onboarding a bare script can't safely do (no `claude` spawn from a script/hook).

## [1.4.2] — 2026-07-15

Patch — docs.

### Added
- `USAGE.md` — day-to-day guide: the loop mental-model, a day in the loop, the skills, a full `bin/` command table, setup/activation (RAG + the capture hook), keeping-current, boundary/safety, and the env knobs. Complements `SCHEMA.md` (spec) and `README.md` (setup).
- `README.md` refreshed (current tool list incl. RAG/capture/doctor/update; points at `USAGE.md`); scaffold README template links `engine/USAGE.md`.

## [1.4.1] — 2026-07-15

Patch — sharper dependency signal + security.

### Changed
- `bin/rag_deps_check.py` (new, shared by `doctor.sh` + the freshness cron): dep freshness now separates **actionable** from **informational**. Actionable (drives exit 1 / opens an issue): a *pinned* dep drifted from or is behind `rag-requirements.txt`, **or** `pip-audit` finds a vulnerability in the RAG requirements closure. Transitive "newer available" is **informational only** — so `doctor`'s exit and the weekly issue stop firing on routine transitive drift (no alert fatigue), while real risk (a CVE, incl. in transitive deps) still alerts.
- `freshness.yml` uses the shared checker + `pip-audit`; opens/updates an issue only when actionable.
- Security audit is scoped to the requirements closure (`pip-audit -r`), so it reports vulns in what the vault runs, never in the audit tool's own deps.

## [1.4.0] — 2026-07-15

Additive — new freshness/update tooling; adopt with `bin/adopt.sh` (no vault changes required).

### Added — keep consumed components current
- `scaffold/rag-requirements.txt` — **pins** the RAG CPU-embedder stack (fastembed/onnxruntime/numpy/tokenizers/huggingface_hub) so `.rag/venv` is reproducible, not floating. `rag-setup.sh` now installs from it (with `RAG_PIP_PKG` as an unpinned override).
- `bin/doctor.sh` — one-shot freshness report: pinned engine vs latest tag + RAG venv drift from the requirements + newer PyPI releases + the embedding model. Deterministic; reports only.
- `bin/update.sh` — apply engine + dep updates in one step: bump the engine to the latest tag *within the same MAJOR*, `adopt`, re-sync the RAG venv. **Refuses a MAJOR bump**; leaves the pin staged, never auto-commits.
- `.github/dependabot.yml` — weekly bumps for the CI's GitHub Actions.
- `.github/workflows/freshness.yml` — weekly cron that flags newer releases of the pinned RAG deps by opening/updating an issue (no `claude`).
- `wiki-context` step 0 now offers `update.sh` (one-step) and points at `doctor.sh` for the fuller check.

Design: *checking* can be automatic (session check, CI cron, Dependabot); *applying* to a vault stays opt-in.

## [1.3.2] — 2026-07-15

Patch — opt-in addition.

### Added
- `rag-capture.sh`: opt-in **transcript path pointer**. With `RAG_CAPTURE_TRANSCRIPT_PATH=1`, records the session's `transcript_path` (from the hook JSON or `--transcript`) as a `Transcript: <path>` line — a **pointer only, never content** — so review-and-promote can open the `.jsonl` in-session to distill from the real conversation, with the boundary/secret gate. Off by default; chat content still never enters the vault or index. `wiki-context` review-and-promote documents the safe use of the pointer.

## [1.3.1] — 2026-07-15

Patch — fix.

### Fixed
- `rag-capture.sh` now handles a **workspace root** (a parent dir of several repos, the common "launch at the parent" pattern). Previously that dir isn't itself a git repo, so capture recorded nothing useful. It now scans immediate child dirs and captures each repo **touched** this session — dirty working tree, or a commit within `RAG_CAPTURE_SINCE` hours (default 12) — one `##` chunk per repo, skipping untouched ones. A single-repo cwd still captures just that repo.

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
