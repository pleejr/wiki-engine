---
name: update
description: This skill should be used to bring the wiki-engine on THIS machine current — report engine freshness (doctor.sh), offer to advance the pinned engine (update.sh, on confirmation only), converge machine wiring (wire-machine.sh), and re-link the engine's own skills. Engine-only and generic: it never touches a consumer's separate skill repos or their tag system. Run it at session start when the banner flags the engine stale, or any time to verify. Triggers: "/update", "catch up the engine", "am I on the latest engine", "converge this machine", "update the engine". Distinct from `checkpoint` (which curates vault *content*) and from any consumer skills-sync (e.g. a `sync-skills` skill) — this converges the engine loop only.
status: active
summary: engine-only machine catch-up — report/offer engine version bump, converge wiring, relink engine skills. Generic; never touches consumer skill repos.
updated: 2026-07-22
used_by: []
---

# update — bring this machine's wiki-engine current

Converge the wiki-engine loop on this machine, low-friction and safe. Everything here is **deterministic** — `doctor.sh`, `update.sh`, `wire-machine.sh` — and **never** spawns `claude`. **Engine-only by design:** a consumer's separate skill collection (with its own tags/versioning) is converged by *that* consumer's own sync, not here — the session banner may nudge you toward it separately (see `session-checks.d`). Requires `$WIKI_PATH`.

## 1. Report freshness
Run `"$WIKI_PATH"/engine/bin/doctor.sh` — pinned engine vs latest tag, RAG deps, embedding model. Reports only.

## 2. Offer an engine version bump (only if behind)
If `doctor` shows the pin behind, **ask the user** before advancing. On confirmation:
```sh
"$WIKI_PATH"/engine/bin/update.sh
```
It advances the submodule pin to the latest same-MAJOR tag and stages it (it refuses a MAJOR bump — that needs a reviewed migration). Then remind the user to review the CHANGELOG and commit the pin.

## 3. Converge machine wiring
```sh
"$WIKI_PATH"/engine/bin/wire-machine.sh --wiki "$WIKI_PATH" --check
```
If it reports pending, run it again without `--check`. Add-only and idempotent — it initializes the submodule, re-links the engine's own skills to the (possibly newly-bumped) pin, ensures `WIKI_PATH` / the `CLAUDE.md` import / `.rag`, and runs feature-adoption.

## 4. Report + hand off
Summarize what changed (engine pin, wiring). Remind: session *content* is `checkpoint`'s job; a consumer's extra skills are converged by their own sync. This verb keeps the **engine** current.

## Rules
- Deterministic engine tools only; never spawn `claude`; in-session / on-demand (or banner-nudged) — **never wired to a hook**.
- **Ask before advancing the pin** (`update.sh`); the wiring converge is add-only and safe to just run.
- **Engine-only** — never reach into a consumer's skill repos or their tag vocabulary; that separation is what keeps the engine generic and shareable.
