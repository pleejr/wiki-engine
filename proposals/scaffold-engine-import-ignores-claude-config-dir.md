---
slug: scaffold-engine-import-ignores-claude-config-dir
outcome: partially-accepted
reason: "The wire-machine half is built as suggested: under a CLAUDE_CONFIG_DIR, --wire-claude-md writes the router import from the config dir's stable pointer, and --check reports it missing. The session-preflight warning is not built. Telling whether an @-import resolves means walking CLAUDE.md import chains at every session start, and wire-machine --check --wire-claude-md already reports the gap on demand and through adopt. The template line is kept, because it is correct under the default config dir. Shipped in v3.10.2."
received: 2026-11-23
---

HANDOFF — engine defect report
slug: scaffold-engine-import-ignores-claude-config-dir
boundary: generic (engine-domain; contains no consumer-private context)

Title: The scaffolded vault CLAUDE.md imports the engine router from a hardcoded ~/.claude path, which does not exist when CLAUDE_CONFIG_DIR is set

Engine version: v3.10.1
Still live at that release: read scaffold/CLAUDE.md.tmpl at the v3.10.1 tag (line 15) and in the installed v3.10.1 plugin cache; both carry the same hardcoded import.

Observed: scaffold/CLAUDE.md.tmpl line 15 is
  @~/.claude/plugins/data/wiki-engine-wiki-engine/engine/CLAUDE.md
On a machine where Claude Code runs with CLAUDE_CONFIG_DIR=<config dir> (a per-boundary launcher), the plugin's data lives at <config dir>/plugins/data/wiki-engine-wiki-engine/, and ~/.claude/plugins/data does not exist. The import resolves to nothing and no error is shown. The vault's CLAUDE.md loads without the engine's generic router and its hard safety rule (no unguarded `claude` spawn from a lifecycle hook). A consumer noticed only because the router text was missing from context. They worked around it with a second, absolute import in <config dir>/CLAUDE.md.

Expected: a scaffolded vault loads the engine router whether or not CLAUDE_CONFIG_DIR is set. The engine's own code already resolves paths as ${CLAUDE_CONFIG_DIR:-~/.claude}: wire-machine.sh step 5 writes the vault import into "$CFG/CLAUDE.md", and ensure-statusline.sh and apply-adopt.sh use the same rule (CHANGELOG entries for the settings.json and skills-dir fixes). The template is the remaining place that does not.

Reproduction (generic):
  1. export CLAUDE_CONFIG_DIR=<an alternate config dir>; install the wiki-engine plugin under it.
  2. Scaffold a vault with new-wiki.sh and wire it with wire-machine.sh --wire-claude-md.
  3. Start a session and look for the engine router ("wiki-engine — the engine (generic router)") in the loaded CLAUDE.md context.
  -> The vault CLAUDE.md loads; the engine router does not, and nothing reports the failed import.

Failure shape: fail-open. The session starts and looks normal, but the engine's always-on safety rule is not loaded.

Already ruled out:
  - The plugin data dir exists under <config dir>/plugins/data/, so the plugin itself is installed correctly.
  - CLAUDE.md @-imports do not expand environment variables (no ${CLAUDE_CONFIG_DIR} form is available), so the template cannot just name the variable.

Suggested fix (HOLD LOOSELY — may be wrong): have wire-machine.sh write the engine-router import with the resolved absolute path ($CFG/plugins/data/wiki-engine-wiki-engine/engine/CLAUDE.md) into $CFG/CLAUDE.md, next to the vault import it already writes there, and drop the hardcoded line from the template (or keep it only when CLAUDE_CONFIG_DIR is unset). Add a session-preflight check that warns when the router import resolves to a missing file.
  Expected vs this fix: the fix produces the Expected for machines wired through wire-machine.sh. A vault already scaffolded keeps its template line, which is harmless if the router is also imported from $CFG/CLAUDE.md, but the preflight warning is what makes an unwired machine visible.

Related doc drift (same root): bin/new-wiki.sh (header and --wire-claude-md help), bin/wire-machine.sh (--wire-claude-md help), skills/onboard/SKILL.md steps 2 and 5, and skills/propose/references/intake.md (the scrutinize check) still name ~/.claude paths. The code they describe uses ${CLAUDE_CONFIG_DIR:-~/.claude}.

Redactions: the consumer's config dir name, vault path, and home directory are replaced by <config dir> and <an alternate config dir>.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
