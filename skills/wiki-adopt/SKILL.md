---
name: wiki-adopt
description: Idempotent adoption of the wiki-engine on a machine — bring up a vault whether or not one exists yet. No vault present → scaffold it (new-wiki.sh, recording this engine's release) then wire + seed; vault already cloned (a second/Nth machine) → just wire the machine. Either path converges through wire-machine.sh (WIKI_PATH in settings + always-on CLAUDE.md import + status line + recall runtime + vault adoption), and is safe to re-run. Runs from the installed wiki-engine plugin; the human starts the session, so there is no `claude` spawn. One-time and interactive — in-session, not a hook.
status: active
summary: idempotent: scaffold a new vault OR wire an already-cloned one, then seed — safe to re-run.
updated: 2026-09-19
---

# wiki-adopt — stand up a vault on a new machine in one session

The front door for adopting **the wiki-engine loop** on a machine. It **converges** the machine to a working vault from whatever state it's in: scaffold a brand-new vault, or wire an already-cloned one (a second/Nth machine). **Safe to re-run** — the wiring step (`wire-machine.sh`) is add-only and reports "already converged" when there's nothing to do. `checkpoint` keeps the vault's *content* current thereafter.

**Bootstrap:** if you can invoke this skill, the `wiki-engine` plugin is installed. On a cold machine that is the one manual prerequisite, two commands and a restart:
```sh
claude plugin marketplace add pleejr/wiki-engine
claude plugin install wiki-engine@wiki-engine --scope user
```
The plugin carries the engine's hooks and skills; nothing is linked or hooked by hand. Engine scripts are at `ENGINE="${CLAUDE_SKILL_DIR}/../.."` below.

**Precondition:** this is a *single-vault machine* (one boundary only). The wiring step points `WIKI_PATH` and the always-on `CLAUDE.md` import at the vault globally — correct here, unsafe on a machine that also hosts the other boundary's vault (there, scaffold without `--wire-*` and scope activation per-directory).

## Boundary first (non-negotiable)
- The vault's `boundary` (`personal` | `work`) is chosen below and stamped into its `CLAUDE.md`. Onboarding imports **only matching material** — never pull work data into a personal vault or vice versa.
- No secrets (keys, tokens, credentials) ever land in a page.

## Steps

1. **Detect the machine's state.** **No vault dir yet** → scaffold + wire (step 3a); **vault already cloned** here (a second machine that ran `git clone`) → wire it (step 3b); **vault present and already wired** → `wire-machine.sh --check` reports it converged, so re-running is a safe no-op. Confirm the machine is single-vault (one boundary) before using the `--wire-*` flags.

2. **Gather identity, proposing defaults from the environment.** Ask for anything not obvious; read `git config user.email`/`user.name` as default suggestions. Collect: `boundary`, vault `--path` (default `~/Documents/repos/<name>`), `name`, git `--email` and `--git-name`, and the git remote (an `OWNER/NAME` slug for `gh` **or** an existing URL, plus visibility). Echo the resolved plan back and get a yes before touching disk.

3a. **No vault yet — scaffold + wire in one command.** `new-wiki.sh` delegates all machine wiring to `wire-machine.sh`, so scaffold and wire share one code path:
   ```
   "$ENGINE"/bin/new-wiki.sh --path <path> --name <name> --boundary <b> \
     --email <email> --git-name <name> \
     --wire-env --wire-claude-md --wire-statusline \
     --create-remote <OWNER/NAME> --visibility <private|public|internal>
   ```
   Use `--remote <url>` instead of `--create-remote` when the remote already exists; drop both to skip the remote. Creates the repo, records this engine's release in `.engine-version`, renders the templates, then wires the machine. Idempotent — a pre-existing `WIKI_PATH`, import or foreign status line is left untouched.

3b. **Vault already cloned — just wire this machine (idempotent converge).**
   ```
   "$ENGINE"/bin/wire-machine.sh --wiki <path> --wire-env --wire-claude-md --wire-statusline
   ```
   Sets `WIKI_PATH` in `settings.json` `env` (it reaches hooks, the Bash tool and the status line), adds the always-on import and the status line, provisions `.rag`, and runs vault adoption — every step add-only and re-run-safe. Preview first with `--check`. It flags a vault still carrying the 1.x `engine/` submodule; that vault needs the CHANGELOG 2.0.0 migration first. Then **skip onboarding (step 5)** — an existing vault is already seeded.

4. **Point this session at the vault.** `export WIKI_PATH=<path>` for the remainder of the session (settings `env` applies from the next session). Confirm `"$ENGINE"/bin/doctor.sh --wiki <path>` is clean.

4b. **Offer other plugins.** The engine ships only its own skills. If the user has other skill plugins (e.g. their own marketplace), they add and install them the same way as the engine; there is nothing to clone or link.

5. **Seed it — run `wiki-onboard`.** Invoke the `wiki-onboard` skill now (same session) to distill existing native memories, ingest the repos you work in, and stub in-flight project pages against the chosen boundary. That skill owns the curation; don't duplicate it here.

6. **Report.** Summarize what was created and wired, and tell the user the vault is live from the next session (settings `env` supplies `WIKI_PATH`; the always-on import loads the router).

## Rules
- **In-session, on demand; never from a lifecycle hook** (engine `CLAUDE.md`, Hard safety rule). Adoption is a one-time interactive bring-up, so there is nothing here worth automating.
- **Idempotent — safe to re-run.** Scaffolding is create-new (`new-wiki.sh` refuses over an existing vault); wiring converges via `wire-machine.sh` (add-only, `--check`-able). For ongoing *content* curation use `checkpoint`/`wiki-repo`.
- The `--wire-*` flags assume a single-vault machine; never run them where the other boundary's vault also lives.
- Respect the boundary and the no-secrets rule at every step.
