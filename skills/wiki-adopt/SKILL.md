---
name: wiki-adopt
description: Idempotent adoption of the wiki-engine on a machine — bring up a vault whether or not one exists yet. No vault present → scaffold it (new-wiki.sh, pinning this engine) then wire + seed; vault already cloned (a second/Nth machine) → just wire the machine. Either path converges through wire-machine.sh (engine submodule + skill links + WIKI_PATH + always-on CLAUDE.md import + recall runtime + feature-adoption), and is safe to re-run. Run from a standalone wiki-engine clone; the human starts the session, so there is no `claude` spawn. In-session only — never a hook.
status: active
summary: idempotent: scaffold a new vault OR wire an already-cloned one, then seed — safe to re-run.
updated: 2026-07-16
used_by: []
---

# wiki-adopt — stand up a vault on a new machine in one session

The front door for adopting **the wiki-engine loop** on a machine. It **converges** the machine to a working vault from whatever state it's in: scaffold a brand-new vault, or wire an already-cloned one (a second/Nth machine). Run it from a Claude Code session started at a standalone clone of this engine (e.g. `cd wiki-engine && claude`, then invoke this skill). Because *you* start the session, onboarding runs in-session with no recursive `claude` spawn — the hard safety rule holds. **Safe to re-run** — the wiring step (`wire-machine.sh`) is add-only and reports "already converged" when there's nothing to do. `checkpoint` keeps the vault's *content* current thereafter.

**Bootstrap:** if you can invoke this skill, it is already linked into `~/.claude/skills/`. On a truly cold machine that link is the one manual prerequisite — `git clone` the engine, then `bin/link-skills.sh` (Claude Code discovers skills only from `~/.claude/skills/` and `<project>/.claude/skills/`, never a repo's bare `skills/` dir). After that first link the skill is global and `new-wiki.sh` keeps the links current on every scaffold.

**Precondition:** this is a *single-vault machine* (one boundary only). The wiring step points `WIKI_PATH` and the always-on `CLAUDE.md` import at the new vault globally — correct here, unsafe on a machine that also hosts the other boundary's vault (there, scaffold without `--wire-*` and scope activation per-directory).

## Boundary first (non-negotiable)
- The vault's `boundary` (`personal` | `work`) is chosen below and stamped into its `CLAUDE.md`. Onboarding imports **only matching material** — never pull work data into a personal vault or vice versa.
- No secrets (keys, tokens, credentials) ever land in a page. See [[lesson-no-claude-in-hooks]].

## Steps

1. **Detect the machine's state** and locate the engine. This skill runs from a standalone clone; resolve `ENGINE=<that clone>` (the dir holding `bin/new-wiki.sh`). Then pick the path: **no vault dir yet** → scaffold + wire (step 3a); **vault already cloned** here (e.g. a second machine that ran `git clone`) → wire it (step 3b); **vault present and already wired** → `wire-machine.sh --check` reports it converged, so re-running is a safe no-op. Confirm the machine is single-vault (one boundary) before using the `--wire-*` flags.

2. **Gather identity, proposing defaults from the environment.** Ask for anything not obvious; read `git config user.email`/`user.name` as default suggestions. Collect: `boundary`, vault `--path` (default `~/Documents/repos/<name>`), `name`, git `--email` and `--git-name`, and the git remote (an `OWNER/NAME` slug for `gh` **or** an existing URL, plus visibility). Echo the resolved plan back and get a yes before touching disk.

3a. **No vault yet — scaffold + wire in one command.** Run `new-wiki.sh` full-auto (it delegates all machine wiring to `wire-machine.sh`, so scaffold and wire share one code path):
   ```
   ENGINE/bin/new-wiki.sh --path <path> --name <name> --boundary <b> \
     --email <email> --git-name <name> \
     --wire-shell --wire-claude-md \
     --create-remote <OWNER/NAME> --visibility <private|public|internal>
   ```
   Use `--remote <url>` instead of `--create-remote` when the remote already exists;
   drop both to skip the remote. Creates the repo, pins this engine as `engine/`,
   renders the templates, then wires the machine (skills, `WIKI_PATH`, the always-on
   import, `.rag`, feature-adoption). Idempotent — a pre-existing `WIKI_PATH`/import
   is left untouched.

3b. **Vault already cloned — just wire this machine (idempotent converge).** The vault already exists on the remote and you `git clone`d it here; make the machine ready without re-scaffolding:
   ```
   ENGINE/bin/wire-machine.sh --wiki <path> --wire-shell --wire-claude-md
   ```
   Initializes the `engine/` submodule, links the skills, sets `WIKI_PATH` + the
   always-on import, provisions `.rag`, and runs engine feature-adoption — every step
   add-only and re-run-safe. Preview first with `--check`. Then **skip onboarding
   (step 5)** — an existing vault is already seeded.

4. **Point this session at the vault.** `export WIKI_PATH=<path>` for the remainder of the session (the shell-rc line only affects new shells). Confirm `ENGINE/bin/doctor.sh --wiki <path>` is clean.

4b. **Offer to install external skill repos (this is what a cold machine needs).** The engine ships only its own skills; a consumer's extra skills live in a separate repo. Ask the user whether they have one to install on this machine (e.g. their personal skills repo). For each git remote they give, append a line `<git-remote> [<dir>]` to `~/.claude/skill-sources`, then run `ENGINE/bin/skill-sources.sh` — it clones each declared source and runs its `bin/link.sh` (which links that repo's skills and any session-check drop-in it ships). Recording the source is also what lets the session-start banner offer to (re)install it later if it's ever missing. Skip if they have none.

5. **Seed it — run `wiki-onboard`.** Invoke the `wiki-onboard` skill now (same session) to distill existing native memories, ingest the repos you work in, and stub in-flight project pages against the chosen boundary. That skill owns the curation; don't duplicate it here.

6. **Report.** Summarize what was created and wired, and tell the user the vault is live for the next session (new shell picks up `WIKI_PATH`; the always-on import loads the router automatically).

## Rules
- **In-session, on demand only. NEVER wire to a hook or a background/recursive `claude` spawn** — that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- **Idempotent — safe to re-run.** Scaffolding is create-new (`new-wiki.sh` refuses over an existing vault); wiring converges via `wire-machine.sh` (add-only, `--check`-able). For ongoing *content* curation use `checkpoint`/`wiki-repo`.
- The `--wire-*` flags assume a single-vault machine; never run them where the other boundary's vault also lives.
- Respect the boundary and the no-secrets rule at every step.
