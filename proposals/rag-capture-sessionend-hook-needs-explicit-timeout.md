---
slug: rag-capture-sessionend-hook-needs-explicit-timeout
outcome: open
received: 2026-08-13
---

HANDOFF — engine defect report
slug: rag-capture-sessionend-hook-needs-explicit-timeout
boundary: generic (engine-domain; contains no consumer-private context)

Title: The documented SessionEnd wiring for rag-capture.sh carries no `timeout`, and the host aborts a timeout-less SessionEnd hook after ~1s, so every capture from a multi-repo workspace root is lost

Engine version: v1.57.0

Still live at that pin: reproduced today against the v1.57.0 checkout. The hook
snippet in `USAGE.md` (the "Turn on auto-capture" block) and the identical one in
`SCHEMA.md` both set only `type` and `command`. `bin/ensure-hook.sh` accepts
`--event`, `--matcher`, `--command`, `--status` and `--settings`, and has no
timeout option at all, so a vault that adopts this hook by tool cannot set one
either.

Observed:
  A session ended from a workspace root holding roughly 70 child repos printed

    SessionEnd hook [<command>] failed: Hook cancelled

  and appended NOTHING to `raw/sessions/<YYYY-MM>.md`. The same script run
  directly against the same vault from the same directory exits 0 in 3.14s and
  appends its blocks correctly. The host aborts the hook at about one second;
  `rag-capture.sh` needs about three, because `touched()` runs git over every
  child repo. The script appends in a single block at its END, so an abort
  discards the whole capture rather than truncating it.

  The controlled test isolates the cause to the missing field. Two hooks in one
  SessionEnd group, differing only in `timeout`:

    { "command": "sleep 3; touch <marker-A>", "timeout": 30 }  -> completed, marker written, no error
    { "command": "sleep 3; touch <marker-B>" }                 -> "failed: Hook cancelled", no marker

  The grace window was bracketed the same way: `sleep 1.0` completes, `sleep 1.5`
  is cancelled. Adding `"timeout": 30` to the real hook fixed it — the next
  session end from the same workspace root printed no error and wrote its blocks.

Expected:
  A deterministic capture hook that the engine itself documents as safe to wire
  should either complete or say what it lost. Two things are wrong. First, the
  documented snippet omits a field the hook needs to survive. Second, and worse,
  the engine's own surfaces cannot tell the two outcomes apart afterwards: an
  empty buffer reads as a quiet period, and review-and-promote sees nothing to
  promote. `rag-capture.sh`'s own comments already name this hazard for the
  boundary refusal — "a hook's exit status is read by nobody, so a quiet refusal
  is indistinguishable from a quiet session" — and the abort reintroduces exactly
  that ambiguity through a different door. The host prints one line at process
  exit, which is the moment an operator is least likely to be reading.

Reproduction (generic):
  1. Wire the SessionEnd hook exactly as `USAGE.md` documents it, with no
     `timeout` field.
  2. Start a session whose working directory is a WORKSPACE ROOT — the parent of
     many sibling repos — so the workspace-scan path runs. Roughly 70 repos here;
     any count that pushes the script past ~1s will do.
  3. End the session.
  -> stderr: `SessionEnd hook [<command>] failed: Hook cancelled`
  -> `raw/sessions/<YYYY-MM>.md` is unchanged.

  A session whose directory is a SINGLE repo takes the fast path, finishes inside
  the window, and captures normally — which is why the defect hides: the buffer
  keeps gaining entries, just never from the workspace root.

Failure shape: fail-open

  It proceeds while looking correct. The wiring reports itself wired, the tool
  reports nothing, the buffer simply stays empty, and the only signal is a host
  message at exit. Not data-loss in the destructive sense — nothing already
  written is damaged — but every capture the hook exists to take is dropped.

Already ruled out:
  - Not the script's own bounded stdin read. The reproduction was run with stdin
    at `/dev/null`, and a plain `sleep 3` hook that touches stdin not at all fails
    identically.
  - Not a non-zero exit or a script error. Run directly, the script exits 0 in
    3.14s and writes correctly.
  - Not the boundary refusal path. The vault declares a boundary, and direct runs
    stamp it correctly.
  - Not hook duplication. The command appears in exactly one SessionEnd entry.
  - Detaching the work is NOT a portable workaround: `setsid` is absent on macOS,
    and a `setsid nohup ... &` wrapper wrote nothing there. Tested.

Suggested fix (HOLD LOOSELY — may be wrong):
  1. Add an explicit `timeout` to the snippet in `USAGE.md` and `SCHEMA.md`. A
     value near 30 leaves wide margin over the measured three seconds.
  2. Give `bin/ensure-hook.sh` a `--timeout N` option, so any adoption step that
     wires a slow deterministic hook can set one. Without it the tool cannot
     express the field, and every wired hook inherits whatever default the host
     applies on abort.
  3. Consider whether the script should say what it costs. The runtime scales
     with the number of sibling repos, and nothing in the docs connects workspace
     size to a hook budget.

  A different axis is available and may be better: make the capture cheap enough
  that no timeout is needed, by bounding the workspace scan. I did not measure
  which part of `touched()` dominates, so I am not proposing it — only naming it.

Redactions:
  - The vault path, its slug, the machine name and the operator identity are
    replaced by `<command>`, `<vault>` and `<marker-A>` / `<marker-B>`. The
    substitution is consistent, so the steps remain runnable.
  - The exact child-repo count is given as "roughly 70"; the names of those repos
    are omitted. Neither is load-bearing — the only property that matters is that
    the scan exceeds the abort window.

Host observed on: Claude Code 2.1.231, macOS. The abort window is the host's
behaviour, not the engine's, which is precisely why the engine's documented
wiring has to state a timeout rather than rely on a default.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the
suggested fix as a hypothesis, not a specification.
