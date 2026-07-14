# wiki-engine

Reusable machinery for an LLM-Wiki / Karpathy-pattern vault, maintained **in-session by Claude Code** (first-party, plan-covered — no orchestrator). Extracted from `pleejr-wiki` so the engine can be managed once and pinned per wiki — engine updates never silently drift across vaults.

## What's here

- `skills/` — the Claude Code skills: `wiki-repo`, `wiki-context`, `checkpoint`, `wiki-onboard`.
- `SCHEMA.md` — node model, three layers, page conventions, memory lifecycle.
- `CLAUDE.md` — generic context router a wiki imports from its own thin `CLAUDE.md`.
- `bin/` — deterministic maintenance tools (no LLM):
  - `new-wiki.sh` + `scaffold/` — scaffold a new consuming wiki in one command.
  - `gen-skills-index.sh` — regenerate a wiki's `index.md` skills catalog from `SKILL.md` frontmatter.
  - `lint-memory.sh` — validate a wiki's `memory/` notes (frontmatter, wikilinks, drift).

## New wiki (recommended)

Clone this engine standalone, then run the scaffolder:

```
git clone <this-repo-url> ~/Documents/repos/wiki-engine
~/Documents/repos/wiki-engine/bin/new-wiki.sh \
  --path ~/Documents/repos/work-wiki --boundary work --email you@company.com --git-name "Your Name"
```

It creates the vault repo, pins this engine as the `engine/` submodule, renders the `scaffold/` templates (thin `CLAUDE.md`, `index.md`, `log.md`, node folders), and symlinks the skills into `~/.claude/skills`. It then prints the manual next steps it deliberately does **not** automate: setting `$WIKI_PATH`, wiring `~/.claude/CLAUDE.md`, and adding a git remote. Run `new-wiki.sh --help` for options.

Then **seed the empty vault** from your existing environment — run the `wiki-onboard` skill in a Claude Code session (with `$WIKI_PATH` set) to distill existing native memories, ingest the repos you work in, and stub project pages. It's a one-time bootstrap; `checkpoint` keeps the vault current thereafter.

## Doing it by hand

1. `git submodule add <this-repo-url> engine` in the wiki repo; commit the pinned SHA.
2. Point `~/.claude/skills/{wiki-repo,wiki-context,checkpoint}` symlinks at this engine's `skills/*`.
3. Set `$WIKI_PATH` to the wiki root (the skills resolve every path from it).
4. Give the wiki a thin `CLAUDE.md`: its boundary/identity, then import `engine/CLAUDE.md`.
5. Bump the submodule pointer to adopt a newer engine — opt-in, per wiki.

## Boundary note

The engine holds no content, identity, or secrets — it's safe to share across a `personal` and a `work` vault. **Content never crosses:** each vault keeps its own `boundary`, and any personal↔work move is a deliberate manual export. Reuse the engine; never reuse a vault's content.

See `SCHEMA.md` for the full spec.
