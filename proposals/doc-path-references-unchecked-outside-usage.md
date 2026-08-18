---
slug: doc-path-references-unchecked-outside-usage
outcome: accepted
reason: "Accepted as reported, including the reporter's own doubt about the prefix allow-list, which is recorded in the CHANGELOG rather than resolved: a new engine top-level directory falls outside the set silently, and that is the same gap one level up. Both shapes and all three docs are now checked; tokens carrying `$`, `~` or `*` are skipped so consumer-side and templated paths are not failed closed. Two things the fix surfaced are worth the reporter knowing: the new check rejected the release's own CHANGELOG-adjacent prose for naming the deleted step as a path (reworded, not exempted), and a CI fixture that copies a partial tree had to be completed with `adopt.d/` — teaching the check to skip a missing directory would have re-created the original failure exactly. Shipped in v1.73.0."
received: 2026-08-18
---

# doc-path-references-unchecked-outside-usage

Found in the engine-dev vault during the v1.72.0 drain, not handed over by a consumer — filed here so the ledger carries it like any other arrival.

Title: `lint-docs.sh` rule 2 checks bare script names in `USAGE.md` only, so a doc reference written as a PATH, or living in `SCHEMA.md`, is never checked at all

Engine version: v1.71.0 (still live at v1.72.0 for everything except the one instance that release fixed)

Observed: `USAGE.md` credited the banner to `adopt.d/40-session-banner-hook.sh`, a step **deleted at v1.13.0** when `session-boot.sh` took over the banner. It survived 58 releases with the docs gate green on every one of them, and was found by reading the file rather than by the check whose stated purpose is "catch stale doc pointers".

  Two independent gaps produce that. `bin/lint-docs.sh:50-52` extracts candidates with `grep -oE '`[a-z0-9_-]+\.sh`'` and resolves each under `bin/`:

  1. **The pattern cannot match a path.** `/` and `.` are outside the character class and the leading backtick is anchored, so `` `adopt.d/40-session-banner-hook.sh` `` yields no match — and neither does `` `bin/reflow.sh` ``, a reference to a file the rule is *specifically* meant to check, merely written with its directory. A reference escapes by being more precise.
  2. **Only `USAGE.md` is read.** `SCHEMA.md` documents the same `bin/` surface in more depth and `README.md` names tools too; neither is looked at.

  Measured at v1.72.0, by the rule's own convention (backticked, `.sh`): `USAGE.md` 35 references checked and 8 path-prefixed ones not; `SCHEMA.md` 22 + 14, none of either checked; `README.md` 20 + 2, none checked. So 44 of 101 references are unreachable by the pattern, and 58 more are in files the rule never opens.

Expected: a backticked reference to an engine-shipped file is checked wherever the engine's own docs write it, and however they write it. I am citing what the rule SAYS it does — its comment is "every bin command referenced in USAGE.md exists (catch stale doc pointers)" — and the observation is that the second half of that sentence is much narrower than the first half implies to a reader adding a reference.

Reproduction (generic):
  1. In `USAGE.md`, write a backticked reference to a file that does not exist, using a directory prefix: `` `adopt.d/99-not-a-step.sh` ``.
  2. Run `bin/lint-docs.sh`.
  -> exits 0, reporting "no stale command references".
  3. Write the same non-existent name bare in `SCHEMA.md`: `` `not-a-step.sh` ``.
  -> exits 0 again.

Failure shape: fail-open, and self-concealing. The gate reports success in the same words whether it checked a reference or never saw it, so a stale pointer reads as an audited one. The cost is that the docs a consumer reads to learn the engine name things that no longer exist, and the drift is only ever found by a human reading the prose — which is what the gate was added to stop being necessary.

Already ruled out:
  - Not a missing-file problem. Every reference in the three docs resolves correctly TODAY (swept at v1.72.0); the instance that did not was fixed in that release. This is about the gate's reach, not a backlog of broken links.
  - Not `lint-links.sh`'s job. That gate walks `[[wiki-links]]` between vault nodes, not backticked paths into the engine's own tree.
  - Not solvable by checking every backticked token. Docs legitimately name paths that do not exist in this repo — consumer-side ones (`~/.claude/spawn-session`), variable-bearing ones (`$WIKI/.wiki-gates.conf`), and globs. Any fix has to bound itself to engine-shipped prefixes, or it fails closed on correct prose.

Suggested fix (HOLD LOOSELY — may be wrong): read all three docs, and match two shapes — a bare `<name>.sh` resolved under `bin/` as today, plus a path-shaped token whose first segment is one of the engine's own top-level directories (`bin/`, `skills/`, `scaffold/`, `adopt.d/`, `.github/`), resolved from the repo root. Skip any token containing `$`, `~`, or `*`, which is what keeps the consumer-side and templated paths out.

  The part I am least sure of is the prefix allow-list: it is a closed set that a new top-level directory would silently fall outside of, which is the same shape of gap as the one being fixed, one level up.
