---
name: wiki-adopt
description: One-shot adoption of the wiki-engine on a fresh machine — gather the vault's boundary/identity/remote, scaffold the vault with new-wiki.sh (pinning this engine), wire the machine (WIKI_PATH + always-on CLAUDE.md import + git remote), then run onboarding to seed it. Run once from a standalone wiki-engine clone; the human starts the session, so there is no `claude` spawn. In-session only — never a hook.
status: active
summary: one-shot: scaffold a new vault, wire the machine, and seed it — run once per machine.
updated: 2026-07-16
used_by: []
---

# wiki-adopt — stand up a vault on a new machine in one session

The front door for adopting **the wiki-engine loop** on a machine that has none yet. Drives the whole flow: scaffold → wire the machine → seed. Run it **once**, in a Claude Code session started from a standalone clone of this engine (e.g. `cd wiki-engine && claude`, then invoke this skill). Because *you* start the session, onboarding runs in-session with no recursive `claude` spawn — the hard safety rule holds. `checkpoint` keeps the vault current thereafter.

**Bootstrap:** if you can invoke this skill, it is already linked into `~/.claude/skills/`. On a truly cold machine that link is the one manual prerequisite — `git clone` the engine, then `bin/link-skills.sh` (Claude Code discovers skills only from `~/.claude/skills/` and `<project>/.claude/skills/`, never a repo's bare `skills/` dir). After that first link the skill is global and `new-wiki.sh` keeps the links current on every scaffold.

**Precondition:** this is a *single-vault machine* (one boundary only). The wiring step points `WIKI_PATH` and the always-on `CLAUDE.md` import at the new vault globally — correct here, unsafe on a machine that also hosts the other boundary's vault (there, scaffold without `--wire-*` and scope activation per-directory).

## Boundary first (non-negotiable)
- The vault's `boundary` (`personal` | `work`) is chosen below and stamped into its `CLAUDE.md`. Onboarding imports **only matching material** — never pull work data into a personal vault or vice versa.
- No secrets (keys, tokens, credentials) ever land in a page. See [[lesson-no-claude-in-hooks]].

## Steps

1. **Confirm the machine is single-vault** and locate the engine. This skill runs from a standalone clone; resolve `ENGINE=<that clone>` (the dir holding `bin/new-wiki.sh`). If a vault already exists here (`$WIKI_PATH` set and populated), stop — use `checkpoint`/`wiki-repo` incrementally instead.

2. **Gather identity, proposing defaults from the environment.** Ask for anything not obvious; read `git config user.email`/`user.name` as default suggestions. Collect: `boundary`, vault `--path` (default `~/Documents/repos/<name>`), `name`, git `--email` and `--git-name`, and the git remote (an `OWNER/NAME` slug for `gh` **or** an existing URL, plus visibility). Echo the resolved plan back and get a yes before touching disk.

3. **Scaffold + wire in one command.** Run `new-wiki.sh` full-auto:
   ```
   ENGINE/bin/new-wiki.sh --path <path> --name <name> --boundary <b> \
     --email <email> --git-name <name> \
     --wire-shell --wire-claude-md \
     --create-remote <OWNER/NAME> --visibility <private|public|internal>
   ```
   Use `--remote <url>` instead of `--create-remote` when the remote already exists;
   drop both to skip the remote. This creates the repo, pins this engine as
   `engine/`, renders the templates, symlinks the skills, provisions `.rag`, appends
   `WIKI_PATH` to the shell rc, adds the always-on import to `~/.claude/CLAUDE.md`,
   and pushes. All wiring is idempotent — a pre-existing `WIKI_PATH` export is left
   untouched with a warning (reconcile by hand if so).

4. **Point this session at the vault.** `export WIKI_PATH=<path>` for the remainder of the session (the shell-rc line only affects new shells). Confirm `ENGINE/bin/doctor.sh --wiki <path>` is clean.

5. **Seed it — run `wiki-onboard`.** Invoke the `wiki-onboard` skill now (same session) to distill existing native memories, ingest the repos you work in, and stub in-flight project pages against the chosen boundary. That skill owns the curation; don't duplicate it here.

6. **Report.** Summarize what was created and wired, and tell the user the vault is live for the next session (new shell picks up `WIKI_PATH`; the always-on import loads the router automatically).

## Rules
- **In-session, on demand only. NEVER wire to a hook or a background/recursive `claude` spawn** — that was the `.ai-os` fork-bomb. See [[lesson-no-claude-in-hooks]].
- One-shot per machine. If a vault already exists, use `checkpoint`/`wiki-repo`.
- The `--wire-*` flags assume a single-vault machine; never run them where the other boundary's vault also lives.
- Respect the boundary and the no-secrets rule at every step.
