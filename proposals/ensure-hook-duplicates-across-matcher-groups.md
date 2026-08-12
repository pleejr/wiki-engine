---
slug: ensure-hook-duplicates-across-matcher-groups
outcome: open
received: 2026-08-12
---

HANDOFF — engine defect report
slug: ensure-hook-duplicates-across-matcher-groups
boundary: generic (engine-domain; contains no consumer-private context)

Title: ensure-hook.sh adds the command to EVERY matcher entry that matches the request, so a settings file with two same-matcher entries for one event gets the hook wired twice

Engine version: v1.53.0 (pinned; the same code is present unchanged in v1.52.0)
Still live at that pin: reproduced from scratch in three throwaway fixture files via `--settings`, immediately after `update.sh` advanced the pin to v1.53.0 and `wire-machine.sh --check` reported the machine converged. Also observed in the real wiring it was invoked for, before the fixtures were built.

Observed: wiring one command into an event whose settings already hold **two** entries sharing the requested matcher appends the command to **both**. The hook then runs twice per event. For an append-to-a-file hook such as the session-capture tool, that means two identical blocks per session end; for any hook with side effects it means the side effect happens twice.

The guard and the writer disagree in `bin/ensure-hook.sh`. The already-satisfied test asks `any(.hooks[$ev][]; ...)` — existence, correctly. The write then does:

```
| .hooks[$ev] |= map(
    if (.matcher // "") == $m then
      .hooks = (.hooks // [])
      | (if any(.hooks[]; .command == $cmd) then . else .hooks += [newhook] end)
    else . end)
```

`map` visits every entry, so every entry whose matcher equals the request receives the command. With `$m == ""` that is every entry that omits `.matcher`, which is the ordinary shape for events that take no matcher.

Expected: the command lands in exactly one entry. The tool documents itself as "ADD-ONLY, never edits or removes an existing hook" and "Matches the target hook by exact command string, so re-running is a no-op once wired" — the second promise holds, and it is what conceals the first write's duplicate.

Reproduction (generic):

  1. Write a settings file whose event holds two entries that both omit `.matcher`:

     {"hooks":{"<EventName>":[
       {"hooks":[{"type":"command","command":"echo group-one"}]},
       {"hooks":[{"type":"command","command":"echo group-two"}]}
     ]}}

  2. `bin/ensure-hook.sh --event <EventName> --command 'echo NEW' --settings <fixture>`
  -> prints `wired <EventName>[] -> echo NEW`; the file now contains `echo NEW` **twice**:
       ["echo group-one","echo NEW"]
       ["echo group-two","echo NEW"]

  3. Re-run the identical command.
  -> silent, exit 0. The duplicate persists. `--check` also prints nothing, so the tool's own
     verification reports the duplicated state as correctly wired.

  4. Same fixture with one entry only -> `echo NEW` appears once. Correct.

  5. Not specific to matcher-less events: two entries both carrying `matcher: "<token>"`, wired
     with `--matcher <token>`, also receive the command twice.

Failure shape: **fail-open.** Every step succeeds and reports success. The duplicate is not visible in the tool's output, is not visible to `--check` afterwards, and re-running — the natural way to confirm wiring — is a silent no-op that looks like confirmation. What surfaces it downstream is the hook's own effect happening twice, which for a capture-style hook reads as duplicated content rather than as duplicated wiring.

Already ruled out:

  - Not caused by `--check` writing. `--check` was run first in the real case; the file was verified to contain zero occurrences afterwards, so the two entries came from the single real write.
  - Not a pre-existing duplicate in the settings file. Both fixture files were authored for the test, and the real case's file held zero occurrences of the command beforehand.
  - Not the coverage/superset logic in the already-satisfied test, which behaves as documented — the mismatch is between that test's `any` and the writer's `map`.
  - Not malformed input: the fixtures are the shape the engine's own documentation shows for a matcher-less event, one entry per hook group.

Suggested fix (HOLD LOOSELY — may be wrong): make the writer target one entry rather than all of them — resolve the index of the first entry whose matcher equals the request and modify only that index, leaving the guard as it is. A separate and arguably more valuable half: give `--check` something to say about a count greater than one, so a duplicate created by any means (this defect, a hand edit, two tools wiring the same command) is reportable rather than indistinguishable from correct wiring. Both are hypotheses; the observation above stands on its own.

Redactions: the real invocation's `--command` string, the settings path, and the wired tool's absolute path are replaced by `echo NEW` and `<fixture>`. The event name is replaced by `<EventName>` throughout, and `<token>` stands for an arbitrary matcher token — the defect reproduces on any event and any matcher value, so no real name is load-bearing. The fixtures above are complete and runnable as written; nothing was dropped because it was awkward to scrub.

Instruction to engine-dev: reproduce first, then decide the shape. Treat the suggested fix as a hypothesis, not a specification.
