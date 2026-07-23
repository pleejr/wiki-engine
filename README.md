# wiki-engine

Reusable machinery for an LLM-Wiki / Karpathy-pattern vault, maintained **in-session by Claude Code** (first-party, plan-covered — no orchestrator). The engine is extracted from the vault it serves so it can be managed once and pinned per wiki — engine updates never silently drift across vaults. Together a vault + this engine form **the wiki-engine loop** (capture → recall → review-and-promote): a curated-memory engine for coding agents.

**Day-to-day usage: `USAGE.md`.** Full spec: `SCHEMA.md`. Releases: `CHANGELOG.md`.

## What's here

- `skills/` — the Claude Code skills: `wiki-repo`, `wiki-context`, `checkpoint`, `wiki-onboard`, `wiki-adopt`, `update`, `crossover`.
- `SCHEMA.md` — node model, three layers, page conventions, memory lifecycle.
- `CLAUDE.md` — generic context router a wiki imports from its own thin `CLAUDE.md`.
- `bin/` — deterministic maintenance tools (no LLM):
  - `new-wiki.sh` + `scaffold/` — scaffold a new consuming wiki in one command (node folders from `scaffold/node-dirs.txt`).
  - `adopt.sh` — ensure an existing vault has the engine's current node folders + run feature-adoption (run after bumping the pin).
  - `wire-machine.sh` — idempotently make a machine ready for an existing vault (submodule init, skill links, `WIKI_PATH`, CLAUDE.md import, `.rag`, feature-adopt); `--check` previews. The "wire an existing clone" converge verb behind `wiki-adopt`, and the shared wiring path `new-wiki.sh` calls after scaffolding.
  - `link-skills.sh` — symlink the engine's skills into `~/.claude/skills` so Claude Code discovers them (the bootstrap that makes `/wiki-adopt` available on a fresh machine; idempotent, `--check`-able, warn+skips a foreign slot).
  - `skill-sources.sh` — clone + link a machine's declared **external** skill repos (`~/.claude/skill-sources`); `--check` reports missing. The cold-machine "install my skills" path — seeded by `wiki-adopt`, offered by the session banner. Generic: the machine declares the repos, the engine names none.
  - `engine-version.sh` · `doctor.sh` · `update.sh` — freshness of consumed components: pinned vs latest engine; full health report (engine + RAG deps + security + model); one-step update (same-MAJOR).
  - `session-preflight.sh` — SessionStart-hook version check: Claude Code (installed vs latest stable) + the pinned engine; on staleness prints an ACTION-REQUIRED block telling the assistant to ask before updating. Deterministic, never runs `claude`.
  - `rag-setup.sh` · `rag-build.sh` · `recall.sh` · `rag-capture.sh` (+ `rag_embed.py`, `rag_deps_check.py`) — the optional, self-contained semantic-recall + auto-capture layer.
  - `lint.sh` — umbrella lint (memory + frontmatter-property + soft-wrap + catalog); `checkpoint` runs it.
  - `gen-skills-index.sh` · `gen-projects-index.sh` · `lint-memory.sh` · `reflow.sh` — catalog generation (skills + projects), memory validation, soft-wrap normalization.

## Prerequisites

Have these in place on the machine *before* adopting:

**Required**
- **Claude Code** — installed and signed in (the skills run inside it; `claude --version` should work). The vault is driven from Claude Code sessions.
- **git** — the vault is a git repo and pins this engine as a submodule. Any recent 2.x. macOS ships an old but workable `bash` 3.2; the scripts are 3.2-compatible.
- **A POSIX shell environment** — macOS or Linux. The `bin/` tools are bash; skills are wired via symlinks into `~/.claude/skills/`, so a filesystem that supports symlinks.

**For pushing the vault to a remote (recommended)**
- **A git host account** (GitHub, GitLab, …) where the vault repo will live, and network access to it.
- **The [`gh`](https://cli.github.com/) CLI, authenticated** (`gh auth status`) — only if you want `wiki-adopt` / `new-wiki.sh --create-remote` to *create and push* the remote for you. Authenticate `gh` against the org/account that should own the vault. Without `gh` you can still adopt and add a remote by hand (`--remote <url>`), or skip the remote entirely.
- Cloning *this* engine needs no auth (the repo is public); auth is only for your own vault's remote.

**Optional — semantic recall + auto-capture (the RAG layer)**
- **Python 3.12–3.14 with `venv`/`pip`** and one-time network access — `rag-setup.sh` provisions a self-contained `.rag/venv` CPU embedder (no server, GPU, or cloud). The pinned default stack (fastembed + bge, verified on 3.13) needs Python **3.12–3.14**; Python 3.11 and below are unsupported (numpy 2.5.x requires >=3.12). If your default `python3` is outside that range, `rag-setup.sh` **auto-selects an in-range interpreter** from PATH or pyenv — so you don't need to juggle it by hand. If none is available, use the lightweight, onnxruntime-free embedder instead: `RAG_PIP_PKG=model2vec RAG_LOCAL_MODEL=minishlab/potion-base-8M engine/bin/rag-setup.sh` (the choice persists in `.rag/config.json`). Skip RAG entirely with `--no-rag`; the vault and its link-graph still work fully — you just lose *semantic* recall (lexical + link-graph recall remains) until you run `rag-setup.sh` later.

**Boundary reminder:** decide the vault's boundary (`personal` | `work`) and the git identity (name/email) it should commit under up front — `wiki-adopt` will ask, and they get stamped into the vault. Keep work and personal on separate vaults (ideally separate machines); the engine holds no identity, so it's safe to share, but **content never crosses**.

## New machine — idempotent adoption (recommended)

On any new machine, clone this engine, link its skills so Claude Code can discover them, then let the `wiki-adopt` skill drive the flow — it **detects state and converges**: no vault yet → scaffold → wire → seed; a vault already cloned (a second/Nth machine) → just wire this machine, no re-scaffold. Safe to re-run.

```
git clone <this-repo-url> ~/Documents/repos/wiki-engine
~/Documents/repos/wiki-engine/bin/link-skills.sh   # bootstrap: ~/.claude/skills/* -> engine skills
claude                                              # from ANY folder
> /wiki-adopt
```

The `link-skills.sh` step is required and easy to miss: Claude Code discovers skills only from `~/.claude/skills/` and `<project>/.claude/skills/`, **never** a cloned repo's bare `skills/` dir — so cloning the engine alone does not make `/wiki-adopt` available. After the one-time link the skill is global (folder-independent); thereafter `new-wiki.sh` keeps the links current on every scaffold.

`/wiki-adopt` then prompts for the vault's boundary/identity/remote, runs the scaffolder, wires the machine, and runs `wiki-onboard` to seed the vault — usable in the very next session. Because *you* start the session there is no recursive `claude` spawn (the hard safety rule holds). This assumes a **single-vault machine** (one boundary); on a machine that hosts both a `personal` and a `work` vault, scaffold without the wiring flags and scope activation per-directory instead.

**Second machine (the vault already exists):** clone the vault, then converge the machine idempotently — either run `/wiki-adopt` (it detects the clone and only wires) or directly:

```
git clone <vault-remote> ~/Documents/repos/<vault>
~/Documents/repos/<vault>/engine/bin/wire-machine.sh --wiki ~/Documents/repos/<vault> --wire-shell --wire-claude-md
```

`wire-machine.sh` initializes the `engine/` submodule, links skills, sets `WIKI_PATH` + the always-on import, provisions `.rag`, and runs feature-adoption — all add-only. Preview with `--check`; re-running is a safe no-op.

### Or run the scaffolder directly

```
~/Documents/repos/wiki-engine/bin/new-wiki.sh \
  --path ~/Documents/repos/work-wiki --boundary work --email you@company.com --git-name "Your Name"
```

It creates the vault repo, pins this engine as the `engine/` submodule, renders the `scaffold/` templates (thin `CLAUDE.md`, `index.md`, `log.md`, node folders), symlinks the skills into `~/.claude/skills`, and provisions `.rag`. Run interactively (no flags) and it prompts for the required args. By default it prints the manual next steps — `$WIKI_PATH`, the `~/.claude/CLAUDE.md` import, the git remote — but the opt-in `--wire-shell`, `--wire-claude-md`, and `--remote`/`--create-remote` flags automate each (idempotent; single-vault machines only). Run `new-wiki.sh --help` for all options.

Then **seed the empty vault** — run the `wiki-onboard` skill in a Claude Code session (with `$WIKI_PATH` set) to distill existing native memories, ingest the repos you work in, and stub project pages. It's a one-time bootstrap; `checkpoint` keeps the vault current thereafter.

## Doing it by hand

1. `git submodule add <this-repo-url> engine` in the wiki repo; commit the pinned SHA.
2. Run `bin/link-skills.sh` to symlink `~/.claude/skills/*` at this engine's `skills/*` (or do it by hand).
3. Set `$WIKI_PATH` to the wiki root (the skills resolve every path from it).
4. Give the wiki a thin `CLAUDE.md`: its boundary/identity, then import `engine/CLAUDE.md`.
5. Bump the submodule pointer to adopt a newer engine — opt-in, per wiki.

## Boundary note

The engine holds no content, identity, or secrets — it's safe to share across a `personal` and a `work` vault. **Content never crosses:** each vault keeps its own `boundary`, and any personal↔work move is a deliberate manual export. Reuse the engine; never reuse a vault's content.

See `USAGE.md` for day-to-day use and `SCHEMA.md` for the full spec.

## License

MIT — see `LICENSE`.
