# wiki-engine

Reusable machinery for an LLM-Wiki / Karpathy-pattern vault, maintained **in-session by Claude Code** (first-party, plan-covered — no orchestrator). Extracted from `pleejr-wiki` so the engine can be managed once and pinned per wiki — engine updates never silently drift across vaults. Together a vault + this engine form **the wiki-engine loop** (capture → recall → review-and-promote): a curated-memory engine for coding agents.

**Day-to-day usage: `USAGE.md`.** Full spec: `SCHEMA.md`. Releases: `CHANGELOG.md`.

## What's here

- `skills/` — the Claude Code skills: `wiki-repo`, `wiki-context`, `checkpoint`, `wiki-onboard`, `wiki-adopt`.
- `SCHEMA.md` — node model, three layers, page conventions, memory lifecycle.
- `CLAUDE.md` — generic context router a wiki imports from its own thin `CLAUDE.md`.
- `bin/` — deterministic maintenance tools (no LLM):
  - `new-wiki.sh` + `scaffold/` — scaffold a new consuming wiki in one command (node folders from `scaffold/node-dirs.txt`).
  - `adopt.sh` — ensure an existing vault has the engine's current node folders (run after bumping the pin).
  - `engine-version.sh` · `doctor.sh` · `update.sh` — freshness of consumed components: pinned vs latest engine; full health report (engine + RAG deps + security + model); one-step update (same-MAJOR).
  - `rag-setup.sh` · `rag-build.sh` · `recall.sh` · `rag-capture.sh` (+ `rag_embed.py`, `rag_deps_check.py`) — the optional, self-contained semantic-recall + auto-capture layer.
  - `lint.sh` — umbrella lint (memory + frontmatter-property + soft-wrap + catalog); `checkpoint` runs it.
  - `gen-skills-index.sh` · `lint-memory.sh` · `reflow.sh` — catalog generation, memory validation, soft-wrap normalization.

## New wiki — one-shot adoption (recommended)

On a machine with no vault yet, clone this engine and let the `wiki-adopt` skill drive the whole flow (scaffold → wire the machine → seed) in a single session:

```
git clone <this-repo-url> ~/Documents/repos/wiki-engine
cd ~/Documents/repos/wiki-engine && claude
> /wiki-adopt
```

It prompts for the vault's boundary/identity/remote, runs the scaffolder, wires the machine, and then runs `wiki-onboard` to seed the vault — usable in the very next session. Because *you* start the session there is no recursive `claude` spawn (the hard safety rule holds). This assumes a **single-vault machine** (one boundary); on a machine that hosts both a `personal` and a `work` vault, scaffold without the wiring flags and scope activation per-directory instead.

### Or run the scaffolder directly

```
~/Documents/repos/wiki-engine/bin/new-wiki.sh \
  --path ~/Documents/repos/work-wiki --boundary work --email you@company.com --git-name "Your Name"
```

It creates the vault repo, pins this engine as the `engine/` submodule, renders the `scaffold/` templates (thin `CLAUDE.md`, `index.md`, `log.md`, node folders), symlinks the skills into `~/.claude/skills`, and provisions `.rag`. Run interactively (no flags) and it prompts for the required args. By default it prints the manual next steps — `$WIKI_PATH`, the `~/.claude/CLAUDE.md` import, the git remote — but the opt-in `--wire-shell`, `--wire-claude-md`, and `--remote`/`--create-remote` flags automate each (idempotent; single-vault machines only). Run `new-wiki.sh --help` for all options.

Then **seed the empty vault** — run the `wiki-onboard` skill in a Claude Code session (with `$WIKI_PATH` set) to distill existing native memories, ingest the repos you work in, and stub project pages. It's a one-time bootstrap; `checkpoint` keeps the vault current thereafter.

## Doing it by hand

1. `git submodule add <this-repo-url> engine` in the wiki repo; commit the pinned SHA.
2. Point `~/.claude/skills/{wiki-repo,wiki-context,checkpoint}` symlinks at this engine's `skills/*`.
3. Set `$WIKI_PATH` to the wiki root (the skills resolve every path from it).
4. Give the wiki a thin `CLAUDE.md`: its boundary/identity, then import `engine/CLAUDE.md`.
5. Bump the submodule pointer to adopt a newer engine — opt-in, per wiki.

## Boundary note

The engine holds no content, identity, or secrets — it's safe to share across a `personal` and a `work` vault. **Content never crosses:** each vault keeps its own `boundary`, and any personal↔work move is a deliberate manual export. Reuse the engine; never reuse a vault's content.

See `USAGE.md` for day-to-day use and `SCHEMA.md` for the full spec.
