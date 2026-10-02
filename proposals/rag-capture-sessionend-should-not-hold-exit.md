---
slug: rag-capture-sessionend-should-not-hold-exit
outcome: accepted
reason: "accepted as suggested. Reproduced at v2.7.0: 5.8s synchronous at a 90-repo fixture root; with the fix the wired hook returns in 0.05s and all 90 blocks land. The hook reads its payload and checks the vault in the foreground, then re-runs itself once in a new session (setsid, or python3/perl setsid(2) on macOS) and exits 0; RAG_CAPTURE_DETACHED=1 prevents a second hop and nothing invokes claude. The log lives at ${XDG_CACHE_HOME:-~/.cache}/wiki-engine/capture/rag-capture.log rather than under the vault, since raw/ only ignores *.md and a log there would show as an untracked vault file. A per-buffer mkdir lock serializes read-compare-append, which also stops the same-repo duplicate the repeat filter used to miss. Direct CLI stays synchronous. The faster-scan alternative was not taken: it shrinks the stall without removing it. Shipped in 2.8.0"
received: 2026-10-02
---

HANDOFF — engine improvement proposal
slug: rag-capture-sessionend-should-not-hold-exit
boundary: generic (engine-domain; contains no consumer-private context)

Title: rag-capture.sh holds session exit for ~10s at a large workspace root; detach the capture so exit returns at once

Problem:
  The accepted fix for `rag-capture-sessionend-hook-needs-explicit-timeout` gave the
  SessionEnd hook `"timeout": 30`, so the workspace-root scan now survives the
  host's grace window. But the host still WAITS for it before exiting, and the scan
  cost grows with the number of child repos (`touched()` runs git over each one).
  At ~90 child repos the hook takes ~10s, the longest SessionEnd hook by far, and
  every session end from that directory stalls for it.

  A stalled exit invites a second Ctrl+C or a closed pane. The host then aborts
  EVERY SessionEnd hook still running, not just this one, and prints
  `SessionEnd hook [...] failed: Hook cancelled` for each. Because rag-capture
  appends in one block at its end, the abort drops the capture entirely (the same
  fail-open shape the earlier proposal named), and sibling hooks from other
  plugins are cancelled with it.

Motivating use case (generic):
  A consumer starts sessions from a workspace root holding ~90 sibling repos.
  Measured with `claude -p ... --debug-file` on engine v2.7.0: the other four
  SessionEnd hooks finished within ~2.3s of session end; rag-capture.sh finished
  ~10s after session end. After an interactive exit, four SessionEnd hooks
  printed "Hook cancelled", rag-capture among them. Why the host aborted (a
  second interrupt is the likely cause) was not verified.

Proposed shape:
  Have the hook entrypoint read its stdin payload synchronously (it is small and
  already bounded by RAG_CAPTURE_STDIN_TIMEOUT), then re-exec the capture body
  detached from the host's process group (e.g. `nohup setsid`-style, stdin from
  /dev/null, output to a log under the vault's raw/ or $TMPDIR) and exit 0
  immediately. Opt in or out with an env var (e.g. RAG_CAPTURE_DETACH=1, default on
  for the documented hook, off for direct CLI use so interactive output still shows).
  Keep a lockfile so overlapping detached captures from concurrent sessions
  serialize rather than interleave appends.

Alternatives considered:
  - Make the scan faster (one `git for-each-ref`/`find -newer` pass instead of
    per-repo `git log`). Worth doing anyway, but cost still scales with repo count,
    so it shrinks the window rather than removing it.
  - Raise or document a longer timeout. Lengthens the stall; does not help an
    interrupted exit.
  - Leave as is. The cancel message recurs and workspace-root captures are lost
    whenever exit is interrupted.

Acceptance criteria:
  - With the documented hook wiring, the SessionEnd hook returns in under 1s at a
    workspace root of 90+ child repos, and the capture block still lands in
    raw/sessions/<YYYY-MM>.md afterwards.
  - Interrupting exit (second Ctrl+C) after the hook returns does not lose the
    capture.
  - Two sessions ending at the same moment produce two intact, non-interleaved blocks.
  - Detached run never invokes `claude` (hard safety rule unchanged); a failure in
    the detached body is visible in its log, not silent.
  - Direct CLI invocation without the env var keeps current synchronous behaviour
    and stdout messages.

Instruction to engine-dev: create the project in the engine-dev vault, build it,
ship it in the engine so consumer vaults receive it on their next update.
