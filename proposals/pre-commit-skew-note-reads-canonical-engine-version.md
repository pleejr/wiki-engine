---
slug: pre-commit-skew-note-reads-canonical-engine-version
outcome: accepted
reason: "accepted as suggested. Reproduced at HEAD with a fixture that commits a staged release from a worktree while canonical records the old one: the NOTE fired and named canonical. The template now reads `git show :.engine-version`, then the committing tree, then canonical; a near-miss pins that a staged record disagreeing with the running release is still reported. The fixture first passed for the wrong reason (a relative hooksPath meant no hook ran in the worktree), so it now asserts the hook ran. Class sweep: no other script reads canonical's record where the caller's tree is meant; update.sh already resolved the caller's tree. Added: vault hooks are adopted add-only and never overwritten, so the fix alone reaches no existing vault; adopt.d/30 now NOTEs a hook that reads canonical without the staged record."
received: 2026-10-06
---

HANDOFF — engine defect report
slug: pre-commit-skew-note-reads-canonical-engine-version
boundary: generic (engine-domain; contains no consumer-private context)

Title: pre-commit release-skew note compares against canonical's .engine-version, not the tree being committed

Engine version: v3.0.0 (plugin); also present at engine origin/main v3.0.0-2.
Still live at that release: read scaffold/pre-commit lines 55-56 at both refs; both read "$CANON/.engine-version".

Observed: in a session worktree, a commit that changes .engine-version from v2.8.1 to v3.0.0 (the MAJOR migration commit) printed:
  pre-commit: NOTE — running engine v3.0.0, but this vault records v2.8.1.
  pre-commit:   To gate with the release this vault records:
  pre-commit:     WIKI_ENGINE=<plugin cache>/wiki-engine/2.8.1 git commit ...
The staged file in the worktree said v3.0.0; only the canonical checkout still said v2.8.1. The commit passed; exit status was unaffected.

Expected: the skew note compares the running engine against the release recorded by the commit being made, so this commit prints no skew note. update.sh already earns this behaviour for its MAJOR guard: it resolves the caller's tree before reading the record (its comment explains that reading canonical made the refusal unclearable during a migration).

Reproduction (generic):
  1. In <consumer vault> with vN-1 recorded, run the plugin at vN.
  2. vault-worktree.sh ensure; in the worktree, write vN to .engine-version and stage it.
  3. Commit.
  -> the NOTE above, naming the canonical record and advising WIKI_ENGINE=<vN-1 cache path>.

Failure shape: none of the three strictly — report-only, nothing refused or lost. Its remedy, if followed, gates the migration commit with the release being migrated away from, which can then refuse content the new release generated (fail-closed on a healthy tree).

Already ruled out: a stale plugin pointer (the note said "running engine v3.0.0", the correct release); a stale worktree (it was cut from origin/main that session); a modified hook (the vault's .githooks/pre-commit is byte-identical to scaffold/pre-commit at v3.0.0).

Suggested fix (HOLD LOOSELY — may be wrong): read the staged record first, `git show :.engine-version` from $ROOT, falling back to "$ROOT/.engine-version", then "$CANON/.engine-version". That yields Expected for this commit and for an ordinary commit that leaves the record untouched.

Redactions: the vault path is <consumer vault>; the plugin cache path is <plugin cache>.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
