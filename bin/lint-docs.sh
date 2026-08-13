#!/usr/bin/env bash
# lint-docs.sh — keep the usage docs honest so new users adopt with the lowest friction.
# Six cheap, deterministic checks (no LLM, never `claude`):
#   1. every skill (skills/*/) is mentioned in USAGE.md  — nothing user-facing goes undocumented
#   2. every `bin/<name>.sh` USAGE.md references actually exists — no stale pointers to deleted tools
#   3. no shipped skill or tool STAMPS a specific boundary value — the engine is
#      boundary-agnostic (SCHEMA.md), so it must ask the vault, never name one
#   4. a worktree-taking skill must name CANONICAL where it touches git-ignored state (v1.51.0)
#   5. every vault WALK goes through the shared exclusion, never its own prune list (v1.54.3)
#   6. every documented hook SNIPPET states a `timeout` — a hook the host cancels is silent,
#      and the snippet is what people copy into a real settings.json
#      — see the section comments below; the count above and this list have both been wrong
#      before, so keep all three in step: this header, the numbered sections, and the
#      success line at the bottom that names each check to the reader.
# Run in CI (engine-ci) and before cutting a release. Exit 1 on any gap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# VAULT_SCAN_SKIP_DIRS lives here; check 5 asserts the Python indexer agrees with it.
. "$SCRIPT_DIR/wiki-root-lib.sh" || { echo "lint-docs: missing wiki-root-lib.sh" >&2; exit 1; }
USAGE="$ROOT/USAGE.md"
[ -f "$USAGE" ] || { echo "lint-docs: no USAGE.md at $USAGE" >&2; exit 1; }

fail=0

# 1. every skill documented in USAGE.md
for d in "$ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  # MATCH THE DOCUMENTED FORM, not the bare word. This was an unanchored `grep -q "$name"`,
  # so a skill whose name is an ordinary word passed on any incidental mention: `drain`
  # matched "drainable" in an unrelated table row, and the gate reported full coverage for
  # a skill nobody had documented. Every skill is listed as a backticked name, so require
  # that — a substring match on a common word is the same class of false pass the engine
  # keeps finding elsewhere.
  if ! grep -qF -- "\`$name\`" "$USAGE"; then
    echo "lint-docs: skill '$name' is not documented in USAGE.md (add it to the Skills section)" >&2
    echo "lint-docs:   looked for the backticked name; an incidental mention of the bare" >&2
    echo "lint-docs:   word does not count as documentation." >&2
    fail=1
  fi
done

# 2. every bin command referenced in USAGE.md exists (catch stale doc pointers)
while read -r cmd; do
  [ -n "$cmd" ] || continue
  [ -f "$ROOT/bin/$cmd" ] || { echo "lint-docs: USAGE.md references bin/$cmd, which does not exist" >&2; fail=1; }
done < <(grep -oE '`[a-z0-9_-]+\.sh`' "$USAGE" | tr -d '`' | sort -u)

# 3. no engine-shipped skill or tool names a specific boundary VALUE ---------------
# SCHEMA.md: each consuming wiki declares its own boundary and the engine is
# boundary-agnostic. Two skills contradicted that by naming one — including inside a
# copy-me frontmatter template — and bin/crossover.sh rewrote every imported page to a
# hardcoded literal. The consequence was silent: a mis-stamped page passes the
# boundary-present gate, is committed and indexed, and is then dropped from semantic
# recall by rag-build's cross-boundary skip, with no message anywhere.
#
# DELIBERATELY NARROW: it matches the STAMPING form only — a `boundary:` key immediately
# followed by a bare token. Prose that enumerates the choice ("boundary (`personal` |
# `work`)"), the scaffolder's own --boundary enum, and the {{BOUNDARY}} placeholder are
# all legitimate and must keep passing. `boundary: generic` is excluded too: that is the
# engine-proposal handoff block's own domain marker, not a vault's boundary, and it has
# its own gate in engine-proposal.sh's scan. A broader rule would either flag every one of
# those or be loosened until it could no longer fail — which is the same defect class
# facing the other way. The limit is stated here rather than left to be discovered.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "lint-docs: $hit" >&2
  echo "lint-docs:   the engine must ask the vault for its boundary (bin/vault-boundary.sh)," >&2
  echo "lint-docs:   never name a value — a mis-stamped page vanishes from recall silently." >&2
  fail=1
done < <(cd "$ROOT" && grep -rnE '(^|[^a-zA-Z-])boundary:[[:space:]]*`?[a-z][a-z0-9-]*' \
           skills/ bin/ scaffold/ 2>/dev/null \
         | grep -vE '\{\{BOUNDARY\}\}|boundary:[[:space:]]*<' \
         | grep -vE 'boundary:[[:space:]]*generic' \
         | grep -vE '^bin/(vault-boundary|lint-docs|lint)\.sh:' || true)

# 4. a worktree-taking skill must name CANONICAL where it touches git-ignored state ------
# A worktree checks out TRACKED files only. So a step aimed at git-ignored per-machine
# state from inside `$WORK` finds an empty directory, correctly reports nothing to do, and
# exits clean — fail-open, and invisible: the state is git-ignored, so its growth never
# appears in `git status`, a diff, or any gate. checkpoint's `raw/sessions` prune ran that
# way for five weeks after the buffer was untracked, pruning nothing, while the section
# one below it (`.rag/`) named canonical explicitly and stayed correct.
#
# "Missing" is exactly what the wrong tree looks like, so no presence test can catch this;
# the only mechanical signal is whether the step NAMES the tree it means. Scoped to skills
# that actually take a worktree — elsewhere there is no second tree to be wrong about.
ignored_tokens="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/scaffold/gitignore.tmpl" 2>/dev/null \
  | sed 's#/\*\.md$#/#' \
  | grep -vE '^(\.worktrees/?|\.DS_Store)$' || true)"
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  grep -q 'vault-worktree\.sh ensure' "$f" || continue
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      case "$hit" in *'$WIKI_PATH'*) continue ;; esac
      echo "lint-docs: skills/$(basename "$(dirname "$f")")/SKILL.md:${hit%%:*} names '$tok' without naming canonical \$WIKI_PATH" >&2
      echo "lint-docs:   that path is git-ignored, so it exists ONLY in canonical — a step" >&2
      echo "lint-docs:   pointed at \$WORK finds it empty and reports success having done nothing." >&2
      fail=1
    done < <(grep -nF -- "$tok" "$f" || true)
  done <<< "$ignored_tokens"
done

# 5. every vault walk uses the shared exclusion ------------------------------------------
# THE DEFECT THIS CLOSES was four private copies of one prune list: `.git`, `engine`,
# `.obsidian`, `.rag` — and, in one of five, `.worktrees`. The four that omitted it walked
# every page of every live session worktree as vault content, so the verified-status report
# double-counted repo pages, the umbrella lint ran its per-page gates against another
# branch's checkout, a memory `[[link]]` resolved because some OTHER branch had the target,
# and the migration sweep would have rewritten files in a checkout its session did not
# author. None of it reproduces in a quiet vault, which is why it survived.
#
# Adding the missing name to four lists would leave the fifth tool — the one nobody has
# written yet — to copy whichever list it happens to see. So the list moved into
# wiki-root-lib.sh and this gate keeps it the only one: a walk rooted at a vault must call
# vault_pages / vault_grep_excludes, not hand-roll a prune.
while IFS= read -r hit; do
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  case "$f" in */wiki-root-lib.sh) continue;; esac        # the definition itself
  echo "lint-docs: ${f#$ROOT/}:$ln walks a vault with its own prune list" >&2
  echo "lint-docs:   use vault_pages (or vault_grep_excludes for a recursive grep) from" >&2
  echo "lint-docs:   wiki-root-lib.sh — a private copy is how .worktrees went unexcluded in" >&2
  echo "lint-docs:   four of five walks, silently, for as long as no session was open." >&2
  fail=1
done < <(grep -rn -- '-name \.obsidian' "$ROOT/bin" 2>/dev/null || true)

while IFS= read -r hit; do
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  echo "lint-docs: ${f#$ROOT/}:$ln greps a vault recursively without the shared excludes" >&2
  echo "lint-docs:   add \$(vault_grep_excludes) — a bare grep -r descends into .worktrees," >&2
  echo "lint-docs:   and a sweep that WRITES would edit another session's checkout." >&2
  fail=1
done < <(grep -rn -- 'grep -r[a-z]* --include=.\*\.md.\+"\$\(VAULT\|WIKI\)"' "$ROOT/bin" 2>/dev/null \
         | grep -v 'vault_grep_excludes' || true)

# The Python indexer skips the CLASS rather than a list — every name in
# VAULT_SCAN_SKIP_DIRS is either `engine` or a dot-directory, and python's own walk plus an
# explicit dot-prefix test covers the second group without enumerating it. That is stronger
# than list-equality (it cannot miss the next dot-directory), so assert the RULE: the walk
# must skip `engine` and anything dot-prefixed. Asserting the old list here would fail a
# correct implementation, which is its own kind of broken gate.
py_walk="$(grep -n 'SKIP_NAMES' "$ROOT/bin/rag-build.sh" 2>/dev/null || true)"
[ -n "$py_walk" ] \
  || { echo "lint-docs: rag-build.sh has no SKIP_NAMES — the indexer's skip rule is gone" >&2; fail=1; }
printf '%s' "$py_walk" | grep -q 'startswith(".")' \
  || { echo "lint-docs: rag-build.sh does not skip dot-directories by class" >&2; \
       echo "lint-docs:   an enumerated list is how .worktrees/ went unskipped — a full" >&2; \
       echo "lint-docs:   checkout of every page, indexed a second time under paths that" >&2; \
       echo "lint-docs:   vanish when the worktree is retired." >&2; fail=1; }
case " $VAULT_SCAN_SKIP_DIRS " in
  *" engine "*) ;;
  *) echo "lint-docs: VAULT_SCAN_SKIP_DIRS no longer names 'engine'; the two walks have diverged" >&2; fail=1;;
esac

# 6. every documented hook snippet states a timeout -------------------------------------
# A hook that names no `timeout` inherits the HOST's window, which the engine does not
# choose and does not learn about: a SessionEnd hook was observed cancelled at about one
# second, and `rag-capture.sh` at a workspace root takes seconds. The failure is fail-open
# and silent — the hook stays wired, the script never reaches its own output, and the empty
# buffer reads as a quiet month. Copy-paste is how a snippet becomes a machine's real
# wiring, so the snippet is the artifact that has to be right.
#
# Scoped to the LIVE docs only: CHANGELOG.md is history and must never be rewritten to suit
# a later rule, and proposals/ quote a reporter's observed settings verbatim, which is
# evidence rather than a recommendation.
timeout_hits="$(
  for f in "$ROOT"/*.md "$ROOT"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    # Leading `(` on purpose: a case pattern's bare `)` is unbalanced to bash's parser
    # INSIDE a `$( )`, which makes everything after it read as unquoted — the fence
    # backticks below then look like a command substitution nobody closed.
    case "$(basename "$f")" in (CHANGELOG.md) continue;; esac
    # A fence must START the line. USAGE.md quotes a fence mid-sentence inside a table
    # cell, and counting that one flips the open/closed state for the whole rest of the
    # file — which is how the first version of this gate read the real hook snippet as
    # prose and passed a doc that had no timeout at all.
    awk -v file="${f#$ROOT/}" '
      /^[[:space:]]*```/ {
        if (inblk && blk ~ /"type"[[:space:]]*:[[:space:]]*"command"/ && blk !~ /"timeout"/) print file ":" start
        inblk = !inblk; blk = ""; if (inblk) start = NR + 1; next }
      inblk { blk = blk $0 "\n" }
    ' "$f"
  done
)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "lint-docs: $hit documents a hook command with no \"timeout\"" >&2
  echo "lint-docs:   the host cancels a hook that outruns its own default window, and a" >&2
  echo "lint-docs:   cancelled hook is silent — an empty capture buffer looks like a quiet" >&2
  echo "lint-docs:   month. State the budget in the snippet people copy." >&2
  fail=1
done <<< "$timeout_hits"

if [ "$fail" -eq 0 ]; then
  echo "lint-docs: all skills documented; no stale command references; no hardcoded boundary values; worktree skills name canonical for ignored state; every vault walk uses the shared exclusion; every documented hook states a timeout"
fi
exit "$fail"
