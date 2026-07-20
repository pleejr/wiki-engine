# Changelog

All notable changes to the wiki-engine. Versioned with [SemVer](https://semver.org/): **MAJOR** = a breaking framework change (node removed/renamed, frontmatter-schema change) that needs a migration; **MINOR** = additive (new node/tool/skill/convention), adopt with `bin/adopt.sh`; **PATCH** = a backwards-compatible fix to a consumed component. `bin/engine-version.sh` reports the delta and flags MAJOR bumps.

**What gets a tag:** the engine is consumed by *pinning a tag* (a vault's `engine/` submodule; `update.sh` advances tag→tag), so tag + release **only** when a change touches what a pinned consumer runs — `skills/`, `bin/`, `SCHEMA.md`, `scaffold/`, the `CLAUDE.md` router (`LICENSE`/legal too). **Docs-only** changes (`README`, `USAGE`, comments, this file's prose) land on `main` **untagged** — consumers read those from `HEAD`/their clone, never through the pin — and ride along under `## [Unreleased]` into the next functional release.

## [1.13.1] — 2026-07-20

Patch — `engine-version.sh` measures staleness **tag-to-tag**, not against `origin/main`'s HEAD, so untagged commits past the latest tag no longer read as a phantom update. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/engine-version.sh`** compared the pinned commit against `origin/main`'s HEAD, so an untagged docs/CI commit sitting past the latest tag (e.g. the `release.yml` workflow) reported `pinned v1.13.0, latest v1.13.0-1-g<sha> — update available` — a phantom `⚠` the `v1.13.0` banner then surfaced every session, with nothing to adopt (`update.sh` only advances tag→tag). It now compares the pinned tag against the **latest release tag reachable on origin/main** (`git tag -l 'v*' --merged FETCH_HEAD | sort -V | tail -1`): equal ⇒ up to date even when untagged commits sit ahead; strictly newer tag ⇒ the real update; higher pinned tag ⇒ ahead/no action. The staleness the banner/status line show now matches what `update.sh` would actually adopt.

## [1.13.0] — 2026-07-20

Minor — fold the version banner into `session-boot.sh` so it reflects the **current** session's check, and retire the separate banner hook. Additive/behavioral (a `bin/` change + removed `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration — but see the note on removing the old standalone banner hook.

The v1.12.0 banner was its own SessionStart hook that read the staleness cache `session-preflight.sh` writes. Claude Code runs SessionStart hooks without ordering guarantees, so the banner raced the preflight that feeds it and could read a cache a sibling was still writing — showing a **stale verdict** (e.g. `✓ up to date` when a newer tag already existed). Folding the two into one process fixes it at no extra latency (preflight runs every start regardless).

### Changed
- **`bin/session-boot.sh`** now runs `apply-adopt.sh` → `session-preflight.sh` → banner render in one pass and emits a single hook-JSON: `systemMessage` (the banner, to the user) + `hookSpecificOutput.additionalContext` (the adopt/preflight detail, to the model). Because preflight writes the cache immediately before the banner reads it, the banner always reflects this session's check. Falls back to plain stdout (model context) without `jq`.
- **`bin/session-banner.sh`** is now a **pure renderer** — prints the banner text to stdout, no JSON, no hook semantics. `session-boot.sh` calls it and wraps the result in `systemMessage`.

### Removed
- **`adopt.d/40-session-banner-hook.sh`** — the banner is no longer a separate hook; `session-boot.sh` (already the single entrypoint) emits it. Removing the step stops new/bumped vaults from wiring a standalone banner hook.

### Note — removing the old standalone banner hook
A vault that adopted v1.12.0–v1.12.1 has a standalone `session-banner.sh` SessionStart hook wired. Adopt is add-only and won't remove it, but it no longer double-surfaces: `session-banner.sh` now prints plain text, and SessionStart routes a hook's plain stdout to the *model's* context, not the user — so the stale hook degrades to harmless context noise, not a visible second banner. Remove it from `settings.json` for tidiness (the `session-boot` hook now owns the banner).

## [1.12.1] — 2026-07-20

Patch — the status line is now **opt-in**, not auto-wired. With the `v1.12.0` banner as the default user-visible surface, auto-wiring the `v1.11.0` status line too double-surfaced the same verdict. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Removed
- **`adopt.d/30-statusline.sh`** — the step that auto-wired `statusline.sh` as a `statusLine`. Removing it stops new/bumped vaults from getting a status line by default; the **banner** (`session-banner.sh`, `adopt.d/40`) remains the auto-wired default. `statusline.sh` and `ensure-statusline.sh` **stay shipped** — a vault that wants the persistent row wires it manually (`ensure-statusline.sh`). This only stops *auto-adoption*; an existing status line a vault already wired is untouched (adopt is add-only and never removes).

### Changed
- **`USAGE.md`** now documents both surfaces — banner (default) vs status line (opt-in) — and drops the stale "a hook can't reach the UI" framing (a hook *can*, via `systemMessage`; see `v1.12.0`). **`ensure-statusline.sh`** header notes it is opt-in tooling, not an adoption step.

## [1.12.0] — 2026-07-20

Minor — a **user-visible** version banner at session start via the hook `systemMessage` channel, so the verdict reaches the user cleanly without the statusLine. Additive (new `bin/` tool + an `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

The v1.11.0 statusLine surfaced the verdict on a persistent row, but the statusLine can be suppressed in a session (e.g. workspace-trust gating) and never renders for some setups. This adds a second, more robust surface that doesn't depend on the statusLine at all. It resolves the long-standing constraint that a SessionStart hook's plain stdout goes only to the model's context (invisible to the user) and its stderr is only user-visible via a non-zero exit that Claude Code renders under a `SessionStart hook error` heading: the **`systemMessage`** JSON field is shown to the user on **exit 0**, with no error heading — the sanctioned clean channel.

### Added
- **`bin/session-banner.sh`** — emits `{"suppressOutput":true,"systemMessage":"…"}` on stdout and exits 0, so Claude Code shows the user a one-line version banner (`wiki-engine <ver> ✓ · claude code <ver> ✓`, or a `⚠` line when stale) in-session at start, with no interaction. Instant and network-free: engine version from `git describe`, Claude Code version from `$CLAUDE_CODE_EXECPATH`, staleness from the cache `session-preflight.sh` writes (empty cache = all current). Degrades to plain stdout without `jq`. Deterministic; never runs `claude`; always exits 0.
- **`adopt.d/40-session-banner-hook.sh`** — adoption step that wires `session-banner.sh` as a `SessionStart` hook (matcher `startup|resume`) via `ensure-hook.sh`, so a fresh install or pin bump surfaces the banner with no manual `settings.json` edit.

### Notes
- Complements, does not replace, the v1.11.0 statusLine: the statusLine is a *persistent* indicator; the banner is a *one-shot* start-of-session announcement. Both read the same `session-preflight.sh` cache, so they always agree. A vault can wire either or both.

## [1.11.1] — 2026-07-20

Patch — `ensure-hook.sh` no longer duplicates a hook when the user's matcher is *broader* than the one being wired. Backwards-compatible; adopt with `bin/adopt.sh` or `update.sh`.

### Fixed
- **`bin/ensure-hook.sh`** matched an existing hook only by an *exact* matcher string, so wiring the engine's canonical `startup|resume` into a vault whose `session-boot.sh` hook used a broader `startup|resume|clear` added a **second** entry — running the boot hook (and its preflight) twice per startup. It is now **coverage-aware**: a hook counts as already wired when the exact command is present under a matcher whose event-token set (split on `|`; empty/absent = match-all) is a **superset of, or equal to**, the requested one. Still strictly add-only — the inverse case (an existing matcher *narrower* than the request) can't be collapsed without editing the user's hook, so it still appends; broaden the request instead.

## [1.11.0] — 2026-07-20

Minor — the version preflight's verdict is now **user-visible** via a Claude Code status line, not just fed to the assistant's context. Additive (new `bin/` tools + an `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

A SessionStart hook can only surface `session-preflight.sh`'s staleness report by adding it to the assistant's context (Claude Code never draws hook stdout in the UI), so whether the user ever hears "an update is available" depends on the assistant choosing to relay it — and it may not. The status line closes that gap with a persistent, always-drawn surface.

### Added
- **`bin/statusline.sh`** — the engine's status-line renderer. Prints one bottom row (working dir · model · a color-coded `⚠` when stale — **amber** for a normal update, **red** for a MAJOR/breaking one). Reads its staleness text from a cache `session-preflight.sh` writes, so it does **no network** on the hot path and stays cheap enough to re-render constantly. Degrades gracefully without `jq` or a cache, honors `NO_COLOR`, and always exits 0 (a failing status-line command must not disrupt the session). Deterministic; never runs `claude`.
- **`bin/ensure-statusline.sh`** — the status-line sibling of `ensure-hook.sh`. Because Claude Code allows exactly **one** status line, this can't be additive like hooks; it is conservative instead: sets ours when none exists, self-heals ours if the script path drifts (matched by `--marker`), and **never clobbers a foreign status line** the user configured themselves. Backs the file up before any write; `--check` dry-runs. Deterministic; never runs `claude`.
- **`adopt.d/30-statusline.sh`** — adoption step that wires `statusline.sh` as the status line via `ensure-statusline.sh`, so a fresh install or pin bump surfaces the version verdict with no manual `settings.json` edit.

### Changed
- **`session-preflight.sh`** now also writes a compact one-line staleness summary to a per-machine cache (`${CLAUDE_CONFIG_DIR:-~/.claude}/.wiki-engine-status`; empty file = all current) for `statusline.sh` to read. Always (re)written each run, so resolving a stale pin clears the warning on the next session. Unchanged otherwise — still deterministic, still never runs the `claude` binary.

### Fixed
- **`engine-version.sh`** no longer reports "update available" when the pinned engine is *ahead* of `origin/main` (SHAs differ but `HEAD..origin/main` is empty — e.g. developing on an unpushed branch). It now reports "ahead — no action" and exits 0, instead of a spurious differ-with-0-behind downgrade. Latent before (a pin is normally never ahead), but the new status line made the false `⚠` persistent.

## [1.10.0] — 2026-07-20

Minor — skills now track the pinned submodule, not the cold-start clone. Additive (new `adopt.d/` step); adopt with `bin/adopt.sh` or `update.sh`, no migration.

### Added
- **`adopt.d/20-link-skills-submodule.sh`** — an adoption step that repoints `~/.claude/skills/*` at the vault's **pinned submodule** (`$ENGINE/skills`) whenever a slot doesn't already resolve there. Closes the skills-vs-pin drift: `link-skills.sh` (the cold-start bootstrap) symlinks skills at whatever clone it ran from — a standalone clone, before a vault exists — and nothing repointed them afterward, so `update.sh` (which bumps only the pin) left the *live* skills lagging the pinned engine. Now, because `session-boot.sh` runs `apply-adopt.sh` each session, a pin bump updates tooling **and** skills in lockstep. Idempotent and add-only: only the engine's own skills are touched (a foreign skill symlinked from another repo — e.g. `redteam` — is left alone), a real dir/file in a slot is never clobbered, and it prints only what it changed. Deterministic; never runs `claude`.

## [1.9.0] — 2026-07-20

Minor — engine features that need hook wiring now **auto-adopt into the next session** instead of waiting on a manual `settings.json` edit. Additive (new `bin/` tools + an `adopt.d/` convention); adopt with `bin/adopt.sh` or `update.sh`. This closes the gap that left v1.7.0's `session-preflight.sh` shipped-but-unwired: the engine now owns a single durable entrypoint, and every later feature wires itself through it.

The model: wire **one** SessionStart hook — `session-boot.sh` — and the engine owns the rest. On each session start it auto-applies any adoption steps the pinned engine introduced since this machine last adopted, then runs the version preflight. `adopt.sh`/`update.sh` wire that one hook (and self-heal it), so a fresh install or a pin bump needs no manual hook surgery.

### Added
- **`adopt.d/`** — versioned, **idempotent, add-only** adoption steps (one per feature that needs more than a folder — e.g. a hook). `apply-adopt.sh` runs them in filename order; each prints only what it changed. This is the general mechanism by which a shipped engine feature takes effect in the next session without manual wiring.
- **`bin/ensure-hook.sh`** — the reusable primitive behind adoption: idempotently ensure a hook command is present in a `settings.json` (jq). **Add-only** — matches by exact command string (no dupes), co-locates into an existing matcher entry, backs the file up before any write, and never edits or removes an existing hook. `--check` dry-runs (reports, writes nothing, never creates the file). Deterministic; never runs `claude`.
- **`bin/apply-adopt.sh`** — runs the `adopt.d/` steps against a vault/machine. Version-gated by a per-machine marker (`$WIKI/.engine-adopted`, gitignored) so it's a no-op once the current pin is adopted; `--force` re-runs, `--check` reports pending steps (exit 1 if any). Because every step is idempotent, the marker is only an optimization — a marker-less machine simply runs them once. Deterministic; always exits 0 (a hook must not block session start); a partial failure leaves the marker unset so the next session retries.
- **`bin/session-boot.sh`** — the engine's single SessionStart entrypoint. Runs `apply-adopt.sh` (auto-wire pending features) then `session-preflight.sh` (report Claude Code + wiki-engine staleness). Wire **this one hook** and the engine owns everything after. Deterministic; never runs `claude`; always exits 0.
- **`adopt.d/10-session-boot-hook.sh`** — the first adoption step: self-heals the `session-boot.sh` SessionStart hook (matcher `startup|resume`), so it is put back if ever missing (fresh machine, reset settings).

### Changed
- **`bin/adopt.sh`** now runs `apply-adopt.sh` after ensuring node folders, so "adopting" wires shipped features too — not just folders. `--check` reports pending feature-adoption steps alongside missing folders. **`update.sh` inherits this** (it calls `adopt.sh`), so a `tag→tag` bump both stages the pin and wires the new tag's features.
- **`session-preflight.sh`** is now invoked *by* `session-boot.sh` rather than wired as its own hook. **Wiring `session-boot.sh` supersedes the v1.7.0 manual `session-preflight.sh` hook line** — the boot hook runs preflight for you. A vault that already wired preflight directly can keep it, or replace it with the boot hook (which also carries auto-adoption).
- **Adopt the marker into `.gitignore`** — `$WIKI/.engine-adopted` is per-machine adoption state (settings.json is per-machine), so it should not be committed.

## [1.8.0] — 2026-07-20

Minor — concurrent-session write isolation via git worktrees. Additive (new `bin/` tool + `checkpoint`/`wiki-context` behavior + a `SCHEMA.md` convention); adopt with `bin/adopt.sh`, no migration.

### Added
- **`bin/vault-worktree.sh`** — gives a vault-writing session its own `git worktree` on a `wt/<session>` branch off `origin/main` (own dir + own HEAD, shared `.git`), so two Claude Code sessions pointed at one `$WIKI_PATH` can't clobber each other's edits or move HEAD out from under one another. Two sessions otherwise share one working tree, where simultaneous page edits are silent last-writer-wins on disk *before* git sees them — a filesystem race a lockfile/`pull --rebase` doesn't fix. `ensure` (idempotent, prints the path to write in), `gc` (retire stale/orphaned worktrees, clean ones only), `list`. Deterministic (plain git, no `claude`). Measured cost ~0.4 s / <1 MB — only tracked text is checked out.

### Changed
- **`checkpoint`** now isolates writes first (new §0): `WORK="$($WIKI_PATH/engine/bin/vault-worktree.sh ensure)"`, make all edits/commits/lint against `$WORK`, run engine tooling from canonical (`lint.sh --wiki "$WORK"`) since the submodule isn't checked out in a worktree, then integrate the branch (merge/PR per the vault's convention) and `gc`. RAG rebuilds against canonical `$WIKI_PATH` after integration (the `.rag/` index is untracked, canonical-only).
- **`wiki-context`** documents that reads stay on canonical `$WIKI_PATH` (read-only, no worktree needed).
- **`SCHEMA.md`** — new "Concurrent-session isolation" note + a `vault-worktree.sh` tooling entry.
- Isolation is **always-on** (opt out per vault with `WIKI_WORKTREE=0`), deliberately not gated on detecting a second session: a missed detection would reintroduce the exact clobber, and the cost is negligible.

## [1.7.0] — 2026-07-20

Minor — add `bin/session-preflight.sh`, a version check for a SessionStart hook. Additive (new `bin/` tool); adopt with `bin/adopt.sh` and wire the hook per below.

### Added
- **`bin/session-preflight.sh`** — run from a vault's `SessionStart` hook; deterministic and **never runs the `claude` binary** (version from install metadata, not `claude --version`, so it satisfies the no-`claude`-in-a-hook rule) and always exits 0 so it can't block session start. It reports two things and, when either is stale, prints an ACTION-REQUIRED block telling the assistant to **ask the user before updating** (the hook never prompts or changes anything):
  1. **Claude Code** — installed vs latest stable (official release endpoint), best-effort by install method (Homebrew cask · npm global); on confirm the assistant runs the matching upgrade + advises a restart.
  2. **wiki-engine** — pinned submodule vs `origin/main`, delegated to the sibling `engine-version.sh`; on confirm the assistant runs `update.sh` and commits the bump.

  Wire it:
  ```json
  "SessionStart": [{ "matcher": "startup", "hooks": [
    { "type": "command", "command": "WIKI_PATH=/path/to/vault /path/to/vault/engine/bin/session-preflight.sh" }
  ]}]
  ```

## [1.6.0] — 2026-07-17

Minor — narrow the `claude`-spawn safety rule from a blanket ban to recursion guards. Touches the `CLAUDE.md` router and `SCHEMA.md`, so it ships as a pinned bump; adopt with `bin/adopt.sh`.

### Changed
- **Hard safety rule (`CLAUDE.md`)** reframed around the actual failure mode — *recursion and runaway agent generation* — rather than fearing headless `claude`. Unguarded `claude` spawn from a **lifecycle hook** stays a hard no (the structural fork-bomb trap the `.ai-os` SessionEnd incident hit, ~13.7k sessions). Deliberate headless spawns (human/cron `claude -p` one-shots, subagents) are now permitted **when bounded**: a re-entry sentinel (`CLAUDE_SPAWN_DEPTH`, refuse above a small N), a concurrency cap (lockfile / count), and guaranteed termination (no self-requeuing watch loop). Deterministic hooks (git/file/`curl`, e.g. `rag-capture.sh`) are unchanged — no guard needed, since they can't recurse into `claude`.
- **`SCHEMA.md`** — `rag-capture.sh` note aligned to the revised framing: it runs from a hook with no guard at all, and a guarded `claude` spawn is now the other permitted hook case.

## [1.5.4] — 2026-07-16

Patch — extend the RAG layer to Python 3.14 and make interpreter selection self-healing.

### Fixed
- **RAG couldn't provision on Python 3.14** (a fresh machine's default `python3`). `onnxruntime`/`fastembed`/`tokenizers` already had 3.14 wheels; only numpy blocked it — no single release spans 3.10–3.14 (`2.2.6` has no 3.14 wheels, `2.5.x` requires ≥3.12). Split numpy with an environment marker (`numpy==2.2.6; python_version < "3.12"` / `numpy==2.5.1; python_version >= "3.12"`), so the pinned stack now installs + embeds bge-base (768-dim) on **3.11, 3.13, and 3.14** (all verified).
- `rag_deps_check.py` (doctor + the freshness cron) now **evaluates the `python_version` marker**, so it only checks the numpy pin matching the venv's Python — no spurious "drift" on the bucket that doesn't apply.

### Added
- `rag-setup.sh` **self-heals the interpreter**: when the default `python3` is outside the supported 3.10–3.14 range, it auto-selects an in-range interpreter from PATH or pyenv (what you'd otherwise do by hand on a Python-3.14 machine) before creating the venv; if none exists it prints the model2vec fallback instead of aborting. Ceiling raised 3.13 → 3.14; README prereqs updated.
- Rolls up the untagged `main` hygiene fix since v1.5.3: `bin/__pycache__/*.pyc` is no longer tracked (it re-dirtied the submodule in consuming vaults). Bumping a vault to v1.5.4 clears that noise.

## [1.5.3] — 2026-07-16

Patch — make the optional RAG layer install on current Python (fixes adoption-time recall on 3.13).

### Fixed
- **Semantic recall couldn't provision on Python 3.13.** The pinned embedder stack (`onnxruntime==1.19.2`, `numpy==2.0.2`, …) predated 3.13 and had no wheels, so `rag-setup.sh` failed and the vault fell back to lexical recall. Bumped the pinned set to **fastembed 0.8.0 / onnxruntime 1.27.0 / numpy 2.2.6 / tokenizers 0.23.1 / huggingface_hub 1.23.0** — verified to install and embed bge-base (768-dim) on **both Python 3.11 and 3.13**.
- `rag-setup.sh` now **guides on failure** instead of aborting opaquely: a proactive warning when the venv Python is < 3.10, and on a failed pinned install it prints the remedies (use Python 3.10–3.13, or the onnxruntime-free `model2vec`/potion fallback, whose choice persists in `.rag/config.json`). Recall is optional, so this stays a guided, non-fatal skip.

### Changed
- **Minimum Python for the (optional) RAG layer is now 3.10** — Python 3.9 is EOL (2025-10) and `numpy>=2.1` dropped it. Documented in README Prerequisites and `rag-requirements.txt`. The rest of the engine (skills, `bin/`, scaffolding) is unaffected — it needs only `bash` + `git`.

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
