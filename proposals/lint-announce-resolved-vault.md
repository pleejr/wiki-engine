---
slug: lint-announce-resolved-vault
outcome: partially-accepted
received: 2026-08-13
reason: "defect confirmed exactly as observed, and reproduced at HEAD: from inside a linked worktree carrying a real violation, a bare lint.sh printed `lint: all checks passed`, exit 0, ZERO stderr, while the same tool with --wiki pointed at that worktree exited 1 on the violation. The SUGGESTED FIX was declined for a technical reason the report could not have had. It asks for `the same unprompted stderr announcement gen-projects-index.sh already emits` — but that sibling does not merely announce, it RETARGETS, and its message literally reads `targeting <worktree> — the working tree cwd is in, not $WIKI_PATH`. That message is only true of a tool that switched trees, so the report's stated Expected output cannot be produced by an announcement alone; announcing `targeting canonical` would be a different message and would leave the hand-run and the pre-commit hook still answering about two trees. The report's own alternative — that a bin/ tool run from a worktree should target that worktree — is not a new convention: wiki-root-lib.sh already states the rule ('only tools whose target is TRACKED VAULT CONTENT should resolve this way'), lint.sh's seam reads already go through resolve_seam_file with a comment saying pre-commit lints the worktree, and the hook already passes --wiki $ROOT. lint.sh was built to lint a worktree; only its root resolution was never converted. Blast radius measured, not asserted: explicit --wiki, cwd in canonical, and cwd in an unrelated repo are all byte-identical and silent. The sweep for siblings found four more, one of them worse than the reported one: lint-summary-volatility.sh binds $WIKI_PATH while `--seed-baseline` WRITES, and the comment beside that write cited resolve_wiki_root as its protection without ever calling it — pre-fix, a seed run from a worktree wrote into canonical, demonstrated live in the new gate. lint-links.sh, lint-memory.sh and verify-status.sh had the same read-side gap. Not touched, per the library's own exclusion list: the RAG family and the machine/engine-wiring family, including upkeep."
---

HANDOFF — engine defect report
slug: lint-announce-resolved-vault
boundary: generic (engine-domain; contains no consumer-private context)

Title: lint.sh does not announce which vault it resolved to, so a bare run from a linked worktree returns a confident verdict about a different tree

Engine version: v1.64.0
Still live at that pin: reproduced today at v1.64.0. Ran `engine/bin/lint.sh` with stderr and stdout separated; stderr carries only section headers, and no line anywhere states which vault was selected. By contrast `gen-projects-index.sh` at the same pin prints an unprompted stderr line naming its target and telling the operator to pass `--wiki` to override.

Observed: cwd-based vault resolution is intended behaviour and `--wiki <path>` overrides it correctly — that part is not the defect. The defect is that `lint.sh` alone among the tools that resolve this way does not say what it resolved to. Its only tell is an absolute path embedded in one `ok:` line among roughly 300 lines of normal output:

    ok: <vault-root>/index.md skills catalog is up to date

So a bare `lint.sh` run from inside a linked worktree prints `lint: all checks passed` — a verdict about the canonical checkout, presented with no indication that the worktree the operator is standing in was never examined.

Expected: the same unprompted stderr announcement its sibling already emits, on the one tool whose entire output is a verdict the operator will act on.

Reproduction (generic):
  1. In a vault with the engine pinned, create a linked worktree: `engine/bin/vault-worktree.sh ensure`
  2. `cd` into that worktree and introduce a lint failure in a tracked page there
  3. From inside the worktree, run `engine/bin/lint.sh`
  -> prints `lint: all checks passed`. The failure is in the worktree; the tool linted canonical and said nothing about which it chose.
  4. For contrast, run `engine/bin/gen-projects-index.sh` from the same place
  -> prints an unprompted stderr line naming the tree it targeted and how to override it

Failure shape: fail-open. The run reports success, the exit status is 0, and nothing distinguishes "this tree is clean" from "a different tree is clean". A pre-commit hook that lints the correct tree then fails while the hand-run tool reports green, which reads as a broken hook rather than as two tools answering about two trees.

Already ruled out:
  - `--wiki <path>` being broken. It is not; pointed at a worktree it lints that worktree correctly.
  - `$WIKI_PATH` being ignored as an oversight. That is documented, deliberate, and consistent across these tools.
  - A missing announcement across the board. At least one sibling already emits exactly the line proposed here, so this is an inconsistency within `bin/`, not a new convention.

Suggested fix (HOLD LOOSELY — may be wrong): emit the same stderr announcement `gen-projects-index.sh` uses, naming the resolved vault root and mentioning `--wiki`, whenever the resolved root is not the cwd's own repository root. Printing it unconditionally would also be defensible and is simpler. A reviewer may reasonably conclude the better fix is the inverse — that a `bin/` tool run from inside a linked worktree should target that worktree by default — but that is a behaviour change with a wider blast radius than a reporting change, and this report does not argue for it.

Redactions: the vault root path is written as `<vault-root>` in the sample output above; it was an ordinary absolute path under the operator's home directory and carried no meaning beyond identifying the checkout. Nothing else was removed.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
