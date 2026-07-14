---
name: wiki-repo
description: Ingest or refresh ONE repo's wiki page in the wiki vault ($WIKI_PATH) with git-ref provenance. Use when documenting a repository for the brain, or when a repo's existing wiki page is stale (its recorded ref/sha differs from HEAD). Single repo only — no cross-repo synthesis.
status: active
summary: ingest/refresh one repo's wiki page with git-ref provenance.
updated: 2026-07-13
used_by: []
---

# wiki-repo — ingest or refresh one repo

Generate or update `$WIKI_PATH/repos/<name>.md` so a session can load a repo's context cheaply instead of re-deriving it. **One repo per run.** Never synthesize across repos (fragile, drops stale).

## Inputs
- Target repo path (default: current working repo).
- **Vault**: `$WIKI_PATH` — the vault root; must be set. Every wiki file below lives under it — `$WIKI_PATH/repos/<name>.md`, `$WIKI_PATH/index.md`, `$WIKI_PATH/log.md`.

## Steps
1. **Read provenance signals** from the target repo:
   - `git -C <repo> describe --tags --always` → latest release tag (primary signal).
   - `git -C <repo> rev-parse --short HEAD` → HEAD sha (fallback for untagged drift).
2. **If a page already exists** (`$WIKI_PATH/repos/<name>.md`) and its frontmatter `ref`/`sha` **match** current → report "fresh, no change" and stop. Otherwise continue (ingest or refresh are the same op).
3. **Read the repo** enough to characterize it: purpose, stack, entry points, key modules, external interfaces (APIs, IaC/Terraform inputs/outputs), and how a new consumer integrates. Read `README`, manifests, and top-level structure; sample deeper only as needed. Do NOT dump file contents.
4. **Write `$WIKI_PATH/repos/<name>.md`** with frontmatter:
   ```yaml
   title: <name>
   created: <existing or today>
   updated: <today>
   type: repo
   tags: [repo, ...]
   sources:
     - repo: <name>
       ref: <tag>
       sha: <sha>
       ingested: <today>
   brain: personal
   ```
   Body sections: **Purpose · Stack · Structure/entry points · Interfaces · How to extend/integrate · Gotchas**.
   Add **≥2 `[[wikilinks]]`** (to related repos/concepts). Keep it a *map*, not a transcript.
5. **Update navigation**: add/refresh the `repos/` entry in `$WIKI_PATH/index.md`; append a dated `$WIKI_PATH/log.md` line.
6. Report what changed and the new `ref`/`sha`.

## Rules
- `brain: personal`; **no secrets** copied into the page (no `.env` values, keys, tokens).
- In-session only. Do not schedule, hook, or background-spawn anything. See [[lesson-no-claude-in-hooks]].
