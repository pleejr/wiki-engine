# Using the wiki-engine loop

Day-to-day guide for **the wiki-engine loop** — a curated-memory engine for coding agents. A git-versioned personal wiki (your **vault**) plus this **engine** (pinned per vault as `engine/`) that gives it skills, deterministic tools, and a capture → recall → promote memory loop.

For the *spec* (node model, conventions, lifecycle) see `SCHEMA.md`. For *first-time setup* see `README.md`. This doc is how you drive it once it exists.

## The mental model — one loop

```
   auto-capture ──▶ raw/sessions ──▶ semantic recall ──▶ review & promote ──▶ memory/
   (SessionEnd hook)   (metadata)      (bge-base RAG)      (you approve)      (curated)
        ▲                                                                        │
        └──────────────────────  next session recalls it  ◀─────────────────────┘
```

- **Capture** is cheap, deterministic, automatic (a hook). **Curation** (promote) is judgment, in-session, human-gated. **Recall** makes both findable so you *just prompt*.
- Curated `memory/` outranks raw in recall, so the auto-captured pile never drowns the good stuff.

## A day in the loop

**Session start** — the `wiki-context` skill runs: checks engine freshness, reads `index.md`, **semantically recalls** the pages relevant to your prompt (no need to name them), and offers to **review-and-promote** any raw captured since last time. You just start describing the task.

**While working** — recall surfaces the relevant curated pages. To pull a repo's context in, invoke `wiki-repo` (it ingests/refreshes one repo page with git-ref provenance). Otherwise just work.

**Session end** — if the SessionEnd hook is wired, `rag-capture.sh` auto-records session metadata to `raw/sessions/`. When a durable fact/decision/lesson emerged, run the `checkpoint` skill: it distills keepers into `memory/`, updates the active project page + `log.md`, prunes promoted raw, lints, and re-indexes for recall.

## Skills (in-session; run in a Claude Code session with `$WIKI_PATH` set)

- **`wiki-context`** — session-start router: freshness check → recall → review-and-promote. The token-saver; load only what's relevant.
- **`wiki-repo`** — ingest or refresh ONE repo page with git provenance.
- **`checkpoint`** — end-of-session: distill memory, update project + log, prune raw, lint, re-index.
- **`wiki-onboard`** — one-time bulk seed of a fresh vault from existing native memory / repos / projects.
- **`wiki-adopt`** — one-shot adoption on a fresh machine: scaffold + wire the machine + run onboarding, in one session. The front door on a new laptop.

## Commands (`bin/` — deterministic, no LLM; set `$WIKI_PATH` or pass `--wiki DIR`)

| Command | What it does |
| --- | --- |
| `recall.sh "query"` | Semantic search → `file:line` pointers into the real pages (`--json` for tools). |
| `rag-build.sh` | (Re)build the `.rag` index from the markdown. Incremental; run after big edits (`checkpoint` does it). |
| `rag-setup.sh` | Provision the self-contained `.rag/venv` CPU embedder (once per vault). `--force` to rebuild/change model. |
| `rag-capture.sh` | Deterministic session auto-capture → `raw/sessions/`. Safe to run from a SessionEnd hook. |
| `doctor.sh` | Freshness/health report: engine + RAG deps (+ security) + model. Reports only. |
| `update.sh` | One-step apply: bump engine to latest tag (same-MAJOR), adopt, re-sync deps. Refuses MAJOR; stages, no commit. |
| `engine-version.sh` | Pinned vs latest engine tag (run by `wiki-context`). |
| `adopt.sh` | Ensure the vault has the engine's current node folders (after a pin bump). |
| `lint.sh` | Umbrella lint (memory + frontmatter + soft-wrap + catalog); `checkpoint` runs it. |
| `reflow.sh` · `gen-skills-index.sh` · `lint-memory.sh` | Soft-wrap normalize · skills-catalog · memory validation. |
| `new-wiki.sh` | Scaffold a brand-new vault (see README). |
| `link-skills.sh` | Symlink the engine's skills into `~/.claude/skills` so Claude Code discovers them. The bootstrap that makes `/wiki-adopt` available on a fresh machine (idempotent; warn+skips a foreign slot, `--force` to repoint). |

## Setup & activation

- **New machine (one-shot):** clone the engine standalone, run `bin/link-skills.sh` (so Claude Code can discover the skills), start Claude from any folder, run the **`wiki-adopt`** skill — it scaffolds, wires the machine (`WIKI_PATH` + `~/.claude/CLAUDE.md` import + remote), and seeds via `wiki-onboard`. Single-vault machines only.
- **New vault (scaffolder):** `bin/new-wiki.sh --path … --boundary personal|work --email …` (prompts for anything omitted; auto-provisions RAG unless `--no-rag`; add `--wire-shell --wire-claude-md --create-remote OWNER/NAME` to automate activation), then run `wiki-onboard` to seed it.
- **Turn on semantic recall (existing vault):** `engine/bin/rag-setup.sh && engine/bin/rag-build.sh`. Then just prompt — `wiki-context` recalls automatically.
- **Turn on auto-capture:** add a SessionEnd hook to `~/.claude/settings.json` pointing at `rag-capture.sh` (deterministic — never calls `claude`). Add `RAG_CAPTURE_TRANSCRIPT_PATH=1` to also record the transcript *path* (pointer, not content):

  ```json
  { "hooks": { "SessionEnd": [ { "hooks": [ {
      "type": "command",
      "command": "WIKI_PATH=/path/to/vault RAG_CAPTURE_TRANSCRIPT_PATH=1 /path/to/vault/engine/bin/rag-capture.sh"
  } ] } ] } }
  ```

## Keeping it current

`doctor.sh` reports what's behind; `update.sh` applies engine + dep updates in one step (same-MAJOR only — a MAJOR bump needs a reviewed migration). Automatic *checking* runs in CI (Dependabot for actions, a weekly `freshness.yml` cron that opens an issue only on actionable dep/security drift); *applying* to a vault always stays opt-in. RAG deps are pinned in `scaffold/rag-requirements.txt` — bump deliberately, then `rag-setup.sh --force`.

`session-preflight.sh` reports Claude Code + engine staleness at session start, but a SessionStart hook can only feed that to the assistant's context (the UI never draws it), so it may go unspoken. The **status line** surfaces it directly: `statusline.sh` renders a persistent bottom row (working dir · model · a color-coded `⚠` when an update is pending — amber for a normal update, red for a MAJOR/breaking one), reading a cache the preflight writes so it never touches the network on the hot path. Auto-wired by `adopt.d/30-statusline.sh` (add-only via `ensure-statusline.sh`: it sets ours when no status line exists and self-heals the path, but never clobbers a status line you configured yourself).

## Boundary & safety (non-negotiable)

- Every vault declares `boundary: personal|work`. **No secrets** (keys, tokens, credentials) in any page. **Content never crosses vaults** — personal↔work is a deliberate manual export.
- **NEVER invoke `claude` from a hook or any background/recursive spawn** — that was the `.ai-os` fork bomb. Skills are in-session, on-demand only. The lone exception that may run from a hook is `rag-capture.sh`, precisely because it is deterministic and never calls `claude`.

## Config knobs (environment)

- `WIKI_PATH` — the vault root the skills/tools resolve from.
- Embedding: `RAG_LOCAL_MODEL`, `RAG_PIP_PKG`, `RAG_REQUIREMENTS`; or an endpoint via `RAG_EMBED_API` (`ollama`|`openai`) + `RAG_EMBED_URL` / `RAG_API_KEY`.
- Recall: `RAG_RAW_WEIGHT` (curated-over-raw penalty, default `0.80`).
- Capture: `RAG_CAPTURE_TRANSCRIPT_PATH`, `RAG_CAPTURE_FILES`, `RAG_CAPTURE_COMMITS`, `RAG_CAPTURE_SINCE`.
