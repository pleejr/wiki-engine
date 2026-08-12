---
slug: rag-capture-blocks-forever-when-stdin-is-an-open-pipe
outcome: open
received: 2026-08-12
---

HANDOFF — engine defect report
slug: rag-capture-blocks-forever-when-stdin-is-an-open-pipe
boundary: generic (engine-domain; contains no consumer-private context)

Title: rag-capture.sh reads hook JSON from stdin with no guard, so it hangs indefinitely when stdin is an open pipe rather than a closed one or a terminal

Engine version: v1.53.0, and unchanged in v1.54.0
Still live at that pin: hit while building CI fixtures for `rag-capture-touched-heuristic-is-not-session-scoped`; the invocation had to be killed by a timeout after two minutes.

Observed: the script reads its hook payload from stdin unconditionally. When stdin is a terminal or is already at end-of-file, the read returns and the script proceeds. When stdin is an open pipe with no writer that ever closes it — the ordinary state inside a script that inherits its parent's stdin, or a supervisor that holds the descriptor open — the read never returns and the process waits forever. Nothing times out and nothing is printed.

This does not reproduce on GitHub's runners, which hand a step's shell an stdin that reaches EOF, so the existing capture CI step passes without redirecting. That is why it is invisible to the test suite: the environment the tests run in is the environment that cannot show it.

Reproduction (generic):

  1. From inside a git repo, invoke the script so that stdin is an open pipe held by a
     process that does not write and does not close it. A `sleep` feeding the pipe is enough:
        sleep 300 | WIKI_PATH=<vault> bin/rag-capture.sh
  -> the script never returns; no output on either stream, nothing written.
  2. Same invocation with stdin closed at EOF:
        WIKI_PATH=<vault> bin/rag-capture.sh </dev/null
  -> returns normally.
  3. Same, from a terminal with no redirection.
  -> returns normally, which is why interactive testing never surfaces it.

Failure shape: **hang, which is worse than either open or closed** — the caller neither succeeds nor fails, and there is no exit status to read because there is no exit. In the documented SessionEnd hook path the harness supplies the payload and closes the pipe, so the wired case is unaffected today. The exposure is any wrapper that invokes capture from a context holding an open stdin: a supervisor, a cron wrapper, a script that pipes something unrelated into a block containing the call, or a test harness. A hook that hangs rather than failing can also hold up whatever waits on it.

Already ruled out:

  - Not the boundary read or the vault validation: the hang precedes any of that, and it happens with a fully valid `WIKI_PATH`.
  - Not the workspace scan: it reproduces in single-repo mode too.
  - Not specific to the v1.54.0 changes; the stdin read is older than both fixes that landed in it.
  - Not a slow capture being mistaken for a hang: two minutes against a repo that captures in well under a second.

Suggested fix (HOLD LOOSELY — may be wrong): read stdin only when there is reason to believe a payload is coming — test that stdin is not a terminal AND that data is available within a short bounded wait (`read -t`), treating the timeout as "no payload" and falling back to the `--repo`/`$PWD` path the script already has. A plain `[ -t 0 ]` test is NOT sufficient on its own, because the failing case is a pipe, not a terminal, and a pipe fails that test exactly as a real hook payload does.

Worth weighing against a simpler option: document that callers must redirect, and add `</dev/null` at the wiring sites the engine controls. That is cheaper and honest, but it leaves the hazard armed for every caller the engine does not write, and the failure it produces is a hang rather than an error — the hardest kind to attribute back to its cause.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
