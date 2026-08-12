---
slug: rag-capture-touched-heuristic-is-not-session-scoped
outcome: open
received: 2026-08-12
---

HANDOFF — engine defect report
slug: rag-capture-touched-heuristic-is-not-session-scoped
boundary: generic (engine-domain; contains no consumer-private context)

Title: rag-capture's workspace-root "touched this session" test is a persistent property, so it captures repos nobody opened and misses the repo the session was actually about

Engine version: v1.53.0 (pinned)
Still live at that pin: measured on the first capture run after wiring the session-end hook at v1.53.0, then re-derived by inspecting the working-tree state and last-commit age of every repo in the workspace root.

Observed: at a workspace root, capture selects a child repo when its working tree is dirty **or** it holds a commit within `RAG_CAPTURE_SINCE` hours (default 12). "Dirty working tree" is not a session-scoped signal — it is a state a repo can sit in indefinitely — so the two failure directions appear together in a single capture:

  - **Captured but untouched.** Two repos were recorded whose only working-tree entry is an untracked directory that a tool creates and nobody commits (in this workspace, an editor/agent config directory). Their last commits are 2 days and 9 days old, so the commit clause did not select them. They were selected purely by being permanently dirty, and they will be selected by **every** capture from now until that directory is committed or ignored — the same two blocks, every session, forever.
  - **Touched but not captured.** The repo the session was entirely about — many `git fetch` calls, a diff read end to end, and a code review posted against a pull request — was **not** recorded. Its tree is clean and its newest commit is ten weeks old, so neither clause fires. Read-only work leaves no trace this heuristic can see, and reviewing is ordinary work.

The net effect on that capture: three repos recorded, two of which the session never opened, and the one it was about absent. A later session recalling that block would conclude the work happened somewhere it did not.

Expected: what the documentation promises. `SCHEMA.md`'s auto-capture section says it "captures each repo you **touched** this session ... skipping untouched repos, so it stays signal not noise", and the script's own header repeats it. A permanently-dirty repo is not a repo touched this session, and the noise it contributes is unbounded in time rather than incidental.

Reproduction (generic):

  1. In a workspace root holding several repos, pick one you will not touch and leave an untracked
     path in it (`mkdir <repo>/.some-tool-dir`). Ensure its newest commit is older than
     `RAG_CAPTURE_SINCE` hours.
  2. Pick a second repo and do only read-only work in it: `git fetch`, `git diff`, `git show`.
     Ensure its tree is clean and its newest commit is older than `RAG_CAPTURE_SINCE` hours.
  3. Run the capture at the workspace root (hook JSON on stdin, or directly).
  -> the untouched repo from step 1 is present in the capture; the repo from step 2 is absent.
  4. Run it again the next day, having touched neither.
  -> the step-1 repo is present again, identically.

Failure shape: **fail-open.** The capture succeeds, prints that it appended an entry, and produces a well-formed block. Nothing in the output distinguishes a repo selected because work happened there from one selected because a stale untracked directory exists. The content is then indexed for semantic recall, so the misleading association is what a later session retrieves — and the buffer is per-machine scratch outside version control, so no diff or gate ever shows the growth.

Already ruled out:

  - Not the commit clause misfiring: both wrongly-captured repos have last commits far outside the
    default 12-hour window, so the dirty-tree clause is the sole selector.
  - Not a tracked-file modification: the dirt in both is a single untracked directory
    (`?? <dir>/` in `git status --porcelain`), nothing staged and nothing modified.
  - Not `RAG_CAPTURE_SINCE` being too small for the missed repo — enlarging it cannot help, since
    that repo's newest commit is ten weeks old. No value of the existing knob captures read-only work.
  - Not a boundary or filter skip: the omitted repo is the same boundary as the captured ones, and
    the run reported no skips.
  - Not the single-repo mode, which is unaffected — this is specific to the workspace-root scan.

Suggested fix (HOLD LOOSELY — may be wrong): the cheap half is to stop letting *untracked-only*
dirt select a repo, which removes the unbounded-in-time noise without changing anything else; a repo
with modified tracked files is at least plausibly mid-work, whereas an untracked tool directory is
a permanent fixture. The harder half — capturing read-only work — probably wants a signal that
records *access* rather than *state*: the mtime of `FETCH_HEAD` or of the index, or `git reflog`
activity within the window, all of which a fetch or a checkout updates while leaving the tree clean.
That is a hypothesis and I have not tested which of them is reliable across the operations a review
session actually performs. A third option, weaker but honest, is to leave the heuristic alone and
correct the documentation so a consumer does not read "touched this session" as a claim the tool
makes good on. The two observations above stand independently of any of these.

Redactions: repo names, the workspace-root path, the untracked directory's real name, and the
boundary value are all replaced by placeholders (`<repo>`, `<dir>`); counts and commit ages are
real and unmodified, since the argument rests on them. The reproduction is runnable as written with
any repos in any workspace root.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a
hypothesis, not a specification.
