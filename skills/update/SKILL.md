---
name: update
description: This skill should be used to bring the wiki-engine current on THIS machine and in its vault — report engine freshness (doctor.sh), offer to update the plugin and record the new release in the vault (update.sh, on confirmation only), and converge machine wiring (wire-machine.sh). Engine-only and generic: it never touches a consumer's separate skill plugins. Run it at session start when the banner flags the engine stale, or any time to verify. Triggers: "/update", "catch up the engine", "am I on the latest engine", "converge this machine", "update the engine". Distinct from `checkpoint` (which curates vault *content*) and from updating any other plugin — this converges the engine loop only.
status: active
summary: engine-only catch-up — report freshness, offer the plugin update and record the release in the vault, converge wiring.
updated: 2026-09-19
---

# update — bring this machine's wiki-engine current

Converge the wiki-engine loop on this machine, low-friction and safe. The engine arrives as the `wiki-engine` Claude Code plugin; the vault records the release it needs in `.engine-version`, which its CI checks out. Everything here is **deterministic** — `doctor.sh`, `update.sh`, `wire-machine.sh` — and **never** spawns `claude`. Requires `$WIKI_PATH`.

## 1. Report freshness
Run `"${CLAUDE_SKILL_DIR}"/../../bin/doctor.sh` — the running release vs the latest tag, RAG deps, embedding model. Reports only.

## 2. Offer the update (only if behind)
If `doctor` shows a newer release, **ask the user** before updating. On confirmation, the plugin first — the user runs it, then restarts Claude Code so the new release loads:
```sh
claude plugin update wiki-engine@wiki-engine
```
Then, in the restarted session, record the release in the vault:
```sh
"${CLAUDE_SKILL_DIR}"/../../bin/update.sh
```
It writes `.engine-version`, runs adoption, re-syncs the RAG venv, advances the engine's repo page provenance and regenerates the skills catalog, staging what it writes (in your worktree; a gated canonical checkout gets the rerun command instead). It refuses a MAJOR difference — that needs the reviewed migration in the CHANGELOG. Then remind the user to review the CHANGELOG and commit.

## 3. Converge machine wiring
```sh
"${CLAUDE_SKILL_DIR}"/../../bin/wire-machine.sh --wiki "$WIKI_PATH" --check
```
If it reports pending, run it again without `--check`. Add-only and idempotent — it checks the plugin is enabled and the vault is on 2.x, ensures the wiring flags you pass (`--wire-env`, `--wire-claude-md`, `--wire-statusline`), provisions `.rag`, and runs vault adoption.

## 4. Report + hand off
Summarize what changed (release, `.engine-version`, wiring). Remind: session *content* is `checkpoint`'s job. This verb keeps the **engine** current.

## Rules
- Deterministic engine tools only; never spawns `claude`. The *skill* stays **in-session / on-demand** (or banner-nudged): updating is a judgement call the operator confirms, and `doctor.sh`'s report is advice, not an instruction to apply.
- **Ask before updating** (the plugin and `update.sh`); the wiring converge is add-only and safe to just run.
- **Engine-only** — never touch a consumer's other plugins; that separation keeps the engine generic and shareable.
