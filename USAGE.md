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
- **`wiki-adopt`** — idempotent adoption: scaffold a new vault **or** wire an already-cloned one, then seed. The front door on any new machine; safe to re-run.
- **`update`** — engine-only machine catch-up: report + offer an engine version bump (`doctor`/`update.sh`), converge wiring (`wire-machine`), relink the engine's own skills. Generic — it never touches a consumer's separate skill repos; a consumer surfaces its own catch-up via a `session-checks.d` drop-in (below).
- **`crossover`** — migrate pages to a vault on another machine over a copy-paste channel (export → import → finalize), with sha256-verified soft-delete + tombstone reference sweep. The deliberate manual boundary crossing; nothing is deleted at the origin until a returned receipt's hash matches.

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
| `adopt.sh` | Ensure the vault has the engine's current node folders + run feature-adoption (after a pin bump). |
| `wire-machine.sh` | Idempotent converge — make THIS machine ready for the vault at `$WIKI_PATH`: submodule, skill links, `WIKI_PATH`, CLAUDE.md import, `.rag`, feature-adopt. `--check` previews. The "wire an existing clone" verb behind `wiki-adopt`. |
| `lint.sh` | Umbrella lint + write-time **gate** (memory + frontmatter + soft-wrap + catalog + boundary-present + provenance-present); `checkpoint`, a pre-commit hook, and vault CI all run it. |
| `verify-status.sh` | Report the `verified:` correctness signal across repo pages (verified / stale / unverified); `--todo` emits the drainable work-list, `--check` gates. |
| `upkeep.sh` | Drainable maintenance queue (`.upkeep/queue.tsv`): `scan` builds it (stale repo pages + un-verified pages), `next`/`done` drain it one item per iteration. In-session/human-driven — no `claude` spawn; re-entry sentinel + lock guard any future automated driver. |
| `reflow.sh` · `gen-skills-index.sh` · `gen-projects-index.sh` · `lint-memory.sh` | Soft-wrap normalize · skills-catalog · projects-catalog · memory validation. |
| `new-wiki.sh` | Scaffold a brand-new vault (see README). |
| `link-skills.sh` | Symlink the engine's skills into `~/.claude/skills` so Claude Code discovers them. The bootstrap that makes `/wiki-adopt` available on a fresh machine (idempotent; warn+skips a foreign slot, `--force` to repoint). |
| `skill-sources.sh` | Clone + link a machine's declared **external** skill repos (`~/.claude/skill-sources`, `<git-remote> [dir]` lines); `--check` reports missing (no network). Generic — the machine declares repos; the engine names none. `wiki-adopt` seeds the file; the session banner offers to run this when a declared source is missing (the cold-machine "install my skills" path). |

## Setup & activation

- **New machine (idempotent adoption):** clone the engine standalone, run `bin/link-skills.sh` (so Claude Code can discover the skills), start Claude from any folder, run the **`wiki-adopt`** skill. It detects state and converges: **no vault** → scaffold + wire + seed; **vault already cloned** (a second/Nth machine) → just wire this machine — `bin/wire-machine.sh --wiki DIR --wire-shell --wire-claude-md` (preview with `--check`). Re-run-safe. Single-vault machines only.
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

`session-preflight.sh` reports Claude Code + engine staleness at session start and writes a compact cache (`${CLAUDE_CONFIG_DIR:-~/.claude}/.wiki-engine-status`; empty = all current). A hook's *plain* stdout only reaches the assistant's context, so two **user-visible** surfaces read that cache instead — both network-free, and they always agree:

- **Banner** (`session-banner.sh`) — the default. A one-shot `systemMessage` line shown to the user at session start (`wiki-engine <ver> ✓ · claude code <ver> ✓`, or a `⚠` line when stale). Auto-wired by `adopt.d/40-session-banner-hook.sh`.
- **Status line** (`statusline.sh`) — **opt-in**. A persistent bottom row (`dir · model` + a color-coded `⚠` — amber for a normal update, red for MAJOR). Not auto-wired; enable it yourself with `ensure-statusline.sh` (add-only — sets it only when no status line exists, self-heals the path, never clobbers a status line you configured yourself).

## Extending the session-start banner (`session-checks.d`)

The SessionStart banner reports engine freshness. A machine can fold in **its own** checks — e.g. a consumer skill repo reporting "first run / catch up" — without the engine knowing anything about them: drop an executable script in `~/.claude/session-checks.d/`. `session-preflight.sh` runs each (deterministic, **must not call `claude`**) and folds the output into the one banner — first stdout line = a compact banner fragment, remaining lines = action/notes for the assistant. Empty output = nothing to report. This keeps the engine generic while letting each layer surface its own state in a single banner.

## Boundary & safety (non-negotiable)

- Every vault declares `boundary: personal|work`. **No secrets** (keys, tokens, credentials) in any page. **Content never crosses vaults** — personal↔work is a deliberate manual export.
- **NEVER invoke `claude` from a hook or any background/recursive spawn** — that was the `.ai-os` fork bomb. Skills are in-session, on-demand only. The lone exception that may run from a hook is `rag-capture.sh`, precisely because it is deterministic and never calls `claude`.

## Config knobs (environment)

- `WIKI_PATH` — the vault root the skills/tools resolve from.
- Embedding: `RAG_LOCAL_MODEL`, `RAG_PIP_PKG`, `RAG_REQUIREMENTS`; or an endpoint via `RAG_EMBED_API` (`ollama`|`openai`) + `RAG_EMBED_URL` / `RAG_API_KEY`.
- Recall: `RAG_RAW_WEIGHT` (curated-over-raw penalty, default `0.80`).
- Capture: `RAG_CAPTURE_TRANSCRIPT_PATH`, `RAG_CAPTURE_FILES`, `RAG_CAPTURE_COMMITS`, `RAG_CAPTURE_SINCE`.
