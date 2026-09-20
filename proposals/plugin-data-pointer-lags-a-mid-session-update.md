---
slug: plugin-data-pointer-lags-a-mid-session-update
outcome: accepted
received: 2026-09-20
reason: "Reproduced at HEAD with two releases installed side by side: the pre-commit resolves whichever one the session started with, and v1.81.0's `gen-skills-index.sh --check` reports drift on an index.md that v2.0.2 generated and calls up to date — two releases, opposite verdicts, nothing saying why. Built the report's THIRD option, not its first. (a) declined on mechanism: the pointer is written from `CLAUDE_PLUGIN_ROOT`, Claude Code holds that variable at the release the session started with (`claude plugin update` prints 'Restart to apply changes'), and `update.sh`/`wire-machine.sh` run mid-session ARE the old code — re-linking from them points the pointer at the release it already names, a no-op. (b) declined because the engine deliberately carries no plugin-cache layout knowledge (staleness is measured tag-to-tag via `git ls-remote`), and 'newest installed' is not 'the release this vault pins': with a newer MAJOR in the cache it would run an engine the vault has not migrated to. So the gate names the skew instead — `scaffold/pre-commit` compares the release it resolved with `.engine-version`, prints both, and names the `WIKI_ENGINE=<path>` invocation when that release is installed beside it, derived from the pointer's own target rather than a hardcoded cache path. Reported, never enforced: most releases do not change what the gates decide, and refusing every commit made on a lagging pointer is a worse failure than the one it prevents — CI asserts the exit status alongside the text, with controls for agreeing records and for an explicit `WIKI_ENGINE`. The sibling sweep found the pointer's other consumers (the router import, the status line, vault CI) either cosmetic or consistent with the session, so the gate is the only place the lag produces a wrong verdict. Existing vaults are not silently repaired — the hook is the vault's file and adoption is add-only — so `30-vault-git-hooks.sh` now reports the missing comparison against an installed hook."
---

# Defect — the plugin data pointer lags a mid-session update, so the vault gate runs the previous release

**Failure shape:** fail-closed. A correct commit is refused, with a message naming the wrong cause.

## Observed

Confirmed at v2.0.2, on a vault migrated to plugin delivery (no `engine/` submodule, `.engine-version` recorded).

1. `session-boot.sh:29-30` is the only thing that maintains the stable pointer: when running as a plugin it does `ln -sfn "$CLAUDE_PLUGIN_ROOT" "$CLAUDE_PLUGIN_DATA/engine"`. It is a SessionStart hook, so the pointer is refreshed once per session.
2. `claude plugin update wiki-engine@wiki-engine` mid-session moves the installed release and prints "Restart to apply changes." The cache gains the new versioned directory; the pointer keeps naming the OLD one until the next session starts.
3. `scaffold/`'s pre-commit template resolves the engine for a plugin-delivered vault through exactly that pointer (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/wiki-engine-*/engine/bin`), because a hook runs outside Claude Code and cannot read the plugin's own variables.
4. So after a mid-session update the write-time gate runs the PREVIOUS release's `lint.sh` against content the NEW release generated. Here the new release had changed one skill's description line, so `update.sh` regenerated the catalog, and the old `gen-skills-index.sh` then reported `drift: index.md skills catalog is stale` — while running `lint.sh` from the new release in the same tree reported `ok: skills catalog is up to date`.
5. The commit is refused twice over, and the two verdicts disagree with no indication that two different engine releases produced them. The remedies a user reaches for are `--no-verify` or `WIKI_WORKTREE=0`, i.e. bypassing the gate. `WIKI_ENGINE=<new cache dir> git commit` is the correct workaround, but nothing in the message points at it.

The same lag applies to anything else resolving through the pointer between the update and the next session start; the catalog is just the check most likely to notice, because a release that changes a skill description guarantees a difference.

## Suggested fix

Loosely held — the mechanism above is the report; any of these closes it.

- Refresh the pointer from `update.sh` (and/or `wire-machine.sh`) as well as from session boot. Both run in-session under the plugin, so `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` are available, and both are already the verbs a user runs right after updating.
- Or have the pre-commit template resolve the NEWEST installed release under the plugin cache rather than following a pointer that is only as fresh as the session.
- Or have the template compare the release it resolved against the vault's `.engine-version` and say so when they differ, so the refusal names the real cause instead of the catalog.

The first is smallest and matches where the knowledge already is.
