---
slug: update-applies-the-pre-update-copy-of-itself
outcome: accepted
received: 2026-08-12
---

HANDOFF — engine defect report
slug: update-applies-the-pre-update-copy-of-itself
boundary: generic (engine-domain; contains no consumer-private context)

Title: update.sh advances the pin and then keeps running its own PRE-UPDATE text, so a change to update.sh never applies to the run that adopts it, and the operator is not told which version acted

Engine version: observed adopting v1.54.1 over v1.54.0
Still live at that pin: reproduced deliberately with a two-tag fixture at HEAD (below), which is the same shape and does not depend on either release's contents.

Observed: update.sh checks out the new tag from the very checkout it is executing from —

    git -C "$ENGINE" checkout -q "$latest"

— and then continues for another ~250 lines: adopt, the RAG re-sync, the repo-page provenance rewrite, the deferral decision, and every printed remedy. All of that is the OLD file's text. `git checkout` writes a temporary file and renames it, so the path gets a NEW inode while the running shell keeps its descriptor on the old one; the shell therefore reads the pre-update script to the end, whatever its length.

Measured, adopting a release whose only relevant change was inside update.sh's own second half: the run behaved exactly as the previous version, and printed nothing to say so. The operator sees the new version number in the first line of output and the old version's behaviour in every line after it.

Expected: either the newly-adopted copy performs the rest of the work, or the run states plainly that it applied the previous version's behaviour and the change lands from the next run.

Reproduction (generic), no engine content needed:

  1. In a scratch repo, commit a script that (a) prints a version marker, (b) runs
     `git checkout -q <other-tag>` over itself, (c) is padded past 8 KiB, and (d) prints a
     second marker naming its version. Tag it vA.
  2. Commit a longer version B of the same script, pointing at vA. Tag it vB.
  3. `git checkout vA && ./s.sh`
  -> "start: version A", "checked out vB", then "MARKER: this statement came from version A".
     Exit 0. The second half of the run is version A's text although version B is on disk.

Failure shape: **fail-open.** Nothing is corrupted and the exit status is 0, but the run reports adopting a version whose behaviour it did not use. The class it hides is specific and self-referential: a defect *in update.sh* is not exercised by the run that installs its fix, so an operator adopting the fix meets the bug one more time — with the release notes in hand saying it was fixed. That is the state this report came from.

Already ruled out:

  - NOT a mid-run splice. A tool that rewrites the file IN PLACE does splice — a control fixture using `cp` over the running script died with `unexpected EOF while looking for matching '"'` — but `git checkout` replaces the inode, so no statement is skipped and no text is garbled. Verified in both directions rather than assumed; the two cases look identical from the output and are not.
  - Not the read-block size: reproduced with scripts both under and over 8 KiB. The descriptor, not the buffer, is what decides this.
  - Not specific to the page-provenance block; it applies to everything after the checkout line, including adopt and the RAG re-sync.
  - Not fixed by re-running update.sh, which is the natural operator reaction: the second run reports "already at <tag>" and exits before reaching any of the deferred work.

Suggested fix (HOLD LOOSELY — may be wrong): the cheap and honest option is to SAY IT — one line after the checkout naming which version's logic is doing the remaining work, so a behaviour change is attributable instead of invisible. The stronger option is a single bounded re-exec of the new copy immediately after the checkout, guarded by a sentinel environment variable that the child refuses to re-enter, so it cannot recurse; that makes the adopted version the one that acts. Re-exec is the larger change and needs care about work already done in the first pass (the fetch and the checkout are idempotent; adopt is add-only), which is why it is offered second rather than first.

Please do not resolve it by moving the checkout to the end of the script. The pin bump has to precede adopt and the dependency re-sync, which are what a release exists to deliver.

Redactions: paths, tags and repository names in the measurement above are described rather than quoted; the reproduction stands alone and needs no vault.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
