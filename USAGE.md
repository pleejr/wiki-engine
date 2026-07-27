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
- **`wiki-repo`** — ingest or refresh ONE repo page with git provenance (a *freshness* refresh when the sha moved).
- **`verify`** — run a *correctness* pass on repo pages: confirm the page against the real repo at its recorded sha, fix drift (and the source repo if it originated there), stamp the `verified:` signal. Complements `wiki-repo` (freshness) — a page can be fresh yet wrong.
- **`checkpoint`** — end-of-session: distill memory, update project + log, prune raw, lint, re-index.
- **`wiki-onboard`** — one-time bulk seed of a fresh vault from existing native memory / repos / projects.
- **`wiki-adopt`** — idempotent adoption: scaffold a new vault **or** wire an already-cloned one, then seed. The front door on any new machine; safe to re-run.
- **`update`** — engine-only machine catch-up: report + offer an engine version bump (`doctor`/`update.sh`), converge wiring (`wire-machine`), relink the engine's own skills. Generic — it never touches a consumer's separate skill repos; a consumer surfaces its own catch-up via a `session-checks.d` drop-in (below).
- **`crossover`** — migrate pages to a vault on another machine over a copy-paste channel (export → import → finalize), with sha256-verified soft-delete + tombstone reference sweep. The deliberate manual boundary crossing; nothing is deleted at the origin until a returned receipt's hash matches. Exports **one block per page** (paste them separately — total paste volume is what the channel drops); `import` accumulates the blocks into the batch.
- **`engine-proposal`** — genericize + boundary-scrub a *consumer* vault's engine-improvement idea **or defect report** into a self-contained, scan-verified handoff block for the engine-dev vault. **The route for a bug you hit while running the engine:** a consumer vault is where engine bugs surface and the one place that cannot fix them — editing the pinned `engine/` submodule in place is discarded by the next `update.sh`. A defect block separates the *observation* from the *suggested fix* (a reporter's fix can be wrong while the bug is real), names the failure shape — **fail-closed / fail-open / data-loss**, where fail-open is the severe one because it looks like success — and states the pinned version it still reproduces at, since a bug can be fixed incidentally and stay open on paper; and, at the engine-dev end, **intake**: design-review an arriving proposal before choosing a shape, then file the project with the accepted/rejected findings. Forward-only: originates a new idea (never a consumer node), so unlike `crossover` there is no integrity handshake and nothing is deleted — the only shared surface is the boundary gate.

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
| `lint.sh` | Umbrella lint + write-time **gate** (memory + frontmatter + soft-wrap + catalog + boundary-present + provenance-present + link-integrity + foreign-boundary); `checkpoint`, a pre-commit hook, and vault CI all run it. |
| `vault-worktree.sh` | Concurrency machinery for multi-session/agent writing: `ensure` (per-session worktree), `guard` (refuse a commit in canonical — wire from `pre-commit`), `lease`/`peers` (advisory path declarations + live sessions), `integrate` (locked rebase + fast-forward to `main`), `gc`/`list`. See the Concurrency section below. |
| `lint-links.sh` | Link-integrity gate over content-node pages. A dangling `[[link]]` that **nearly** matches a real slug is an **error** (typo, or a slug left behind by a rename); one that matches nothing is a stub per `SCHEMA.md` and stays a warning. Links inside code spans/fences are documentation about the syntax, not links, and are ignored; targets listed in the vault's external-refs file (things that must never resolve here) are silent. |
| `lint-adopt-paths.sh` | Assert `adopt.d/` steps reference engine assets that exist: no path derived above the engine root (`$ENGINE/..` is the *consumer's* vault), and every literal `$ENGINE/<path>` resolves in the checkout. Catches the class where a step's own bundled asset misresolves, so the step exits 0 and reports as adopted. `--engine DIR` checks another tree. |
| `verify-status.sh` | Report the `verified:` correctness signal across repo pages (verified / stale / unverified); `--todo` emits the drainable work-list, `--check` gates. |
| `upkeep.sh` | Drainable maintenance queue (`.upkeep/queue.tsv`): `scan` builds it (stale repo pages + un-verified pages), `next`/`done` drain it one item per iteration. In-session/human-driven — no `claude` spawn; re-entry sentinel + lock guard any future automated driver. |
| `crossover.sh` | Deterministic transport for the `crossover` skill: `export`/`import`/`finalize` a batch of pages between vaults with sha256 integrity + a secret-scan; only a hash-matched receipt authorizes the origin soft-delete. `export` splits one block per item by default (`--bundle` for one block, `--block N` to re-emit one); `import` accumulates blocks and names what is still outstanding. |
| `engine-proposal.sh` | Boundary gate for the `engine-proposal` skill: `scan` a drafted handoff block against the consumer vault's own identifiers (slug/dir/git user), home paths, emails, non-generic boundary tags, and secret assignments (fail-closed); `stash` writes a git-ignored `.engine-proposal/<slug>.outbox` scratch copy. No `claude`, no node creation. |
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
- **Status line** (`statusline.sh`) — **opt-in**. A persistent bottom row: `dir · model · ctx N%`, plus a color-coded `⚠` when the engine is stale (amber for a normal update, red for MAJOR) and the 5-hour rate limit once it passes 80%. Not auto-wired; enable it yourself with `ensure-statusline.sh` (add-only — sets it only when no status line exists, self-heals the path, never clobbers a status line you configured yourself).
  - **The context figure names an action, not just a number**: `ctx 72% — checkpoint soon` (amber) and `ctx 88% — checkpoint now` (red). Compaction is a thing to get *ahead* of — once `checkpoint` has run, the session is disposable and a fresh one starts with the vault as its handoff, so the expensive case is discovering the ceiling mid-task. Read from `context_window.used_percentage`, which Claude Code pre-calculates; truncated rather than rounded, so 84.9% never reads as the higher band. A client that does not send the field, a missing `jq`, or malformed input all degrade to the plain row rather than showing a wrong number.

## Extending the session-start banner (`session-checks.d`)

The SessionStart banner reports engine freshness. A machine can fold in **its own** checks — e.g. a consumer skill repo reporting "first run / catch up" — without the engine knowing anything about them: drop an executable script in `~/.claude/session-checks.d/`. `session-preflight.sh` runs each (deterministic, **must not call `claude`**) and folds the output into the one banner — first stdout line = a compact banner fragment, remaining lines = action/notes for the assistant. Empty output = nothing to report. This keeps the engine generic while letting each layer surface its own state in a single banner.

## Boundary & safety (non-negotiable)

- Every vault declares `boundary: personal|work`. **No secrets** (keys, tokens, credentials) in any page. **Content never crosses vaults** — personal↔work is a deliberate manual export.
- **NEVER invoke `claude` from a hook or any background/recursive spawn** — that was the `.ai-os` fork bomb. Skills are in-session, on-demand only. The lone exception that may run from a hook is `rag-capture.sh`, precisely because it is deterministic and never calls `claude`.

## Concurrency — more than one session (or agent) writing at once

Two sessions pointed at one `$WIKI_PATH` share **one working tree, one index, and one HEAD**. That is enough to lose work even when they never touch the same file: `git add -A` in either stages the other's in-progress edits, and `git reset`/`checkout` moves the other's HEAD. Simultaneous edits to one file are last-writer-wins **on disk, before git is involved at all**, so no commit-time lock can help.

`bin/vault-worktree.sh` layers four defences, each covering what the one below cannot:

| Layer | Command | What it prevents |
| --- | --- | --- |
| **Isolation** | `ensure` | The filesystem race. Each session gets its own worktree (own dir + own HEAD, shared `.git`) on a `wt/<session>` branch. ~0.4 s, <1 MB. |
| **Enforcement** | `guard` | Isolation being skipped. Refuses a commit made in the canonical checkout, so the unsafe path can't be taken out of habit. Wired from the vault's `pre-commit`. |
| **Visibility** | `lease` / `peers` | Surprise. A session declares the paths it intends to write; `peers` lists live sessions. **Advisory** — git decides real conflicts at merge, and refusing overlap would block the common harmless case of two sessions touching one index file. The job is to make a collision course visible while re-planning is still cheap. |
| **Serialization** | `integrate` | HEAD races at the one genuinely shared step. Rebases your branch onto `main` **inside your worktree** (so a conflict lands in your tree, not in canonical mid-merge), then fast-forwards `main` under an atomic lock. |

The session-start banner reports live peers, because the guard only fires at *commit* time — by then the editing has already happened somewhere.

Exit codes from `integrate`, so a loop or agent can branch on them: **1** dirty worktree, **2** not in a worktree, **3** rebase conflict (resolve in your worktree, re-run), **4** lock wait timed out.

Single-session machine, or a deliberate direct-to-main flow: `WIKI_WORKTREE=0` turns isolation and the guard off together.

## Gate seam (`$WIKI/.wiki-gates.conf`)

Optional, `key = value`, **parsed and never sourced** — a config file that can execute code is a config file that can own the machine running the gate. Absent means engine defaults. The engine composes the seam; the vault supplies the values, so no consumer's strings live in the engine.

| Key | Default | What it names |
| --- | --- | --- |
| `external_refs` | `.wiki-gates-external-refs` | A file of link targets that must **never** resolve in this vault — another boundary's pages, engine files, skill names. Listed targets are silent instead of warning as stubs, so a permanent cross-boundary reference is not mistaken for rot a future session should "fix". |
| `foreign_boundary_patterns` | `.wiki-gates.local` | A file of EREs this vault's pages must not match — the foreign-boundary denylist. **Keep it git-ignored:** naming the forbidden strings in a tracked file commits the other boundary's identifiers into this vault's permanent history, which is the thing the gate exists to prevent. The trade-off is that a fresh clone starts unarmed, so an unarmed gate reports `not armed` rather than passing silently. Matches print the file, line, and the *pattern* — never the matched text, which would put the foreign string in CI logs. |

## Config knobs (environment)

- `WIKI_PATH` — the vault root the skills/tools resolve from.
- Embedding: `RAG_LOCAL_MODEL`, `RAG_PIP_PKG`, `RAG_REQUIREMENTS`, `RAG_MODEL_CACHE` (where weights live; default `${XDG_CACHE_HOME:-~/.cache}/wiki-engine/models`, machine-global — set it to `$WIKI/.rag/models` for vault-local); or an endpoint via `RAG_EMBED_API` (`ollama`|`openai`) + `RAG_EMBED_URL` / `RAG_API_KEY`.
- Recall: `RAG_RAW_WEIGHT` (curated-over-raw penalty, default `0.80`).
- Capture: `RAG_CAPTURE_TRANSCRIPT_PATH`, `RAG_CAPTURE_FILES`, `RAG_CAPTURE_COMMITS`, `RAG_CAPTURE_SINCE`.
