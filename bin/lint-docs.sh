#!/usr/bin/env bash
# lint-docs.sh — keep the usage docs honest so new users adopt with the lowest friction.
# Four cheap, deterministic checks (no LLM, never `claude`):
#   1. every skill (skills/*/) is mentioned in USAGE.md  — nothing user-facing goes undocumented
#   2. every `bin/<name>.sh` USAGE.md references actually exists — no stale pointers to deleted tools
#   3. no shipped skill or tool STAMPS a specific boundary value — the engine is
#      boundary-agnostic (SCHEMA.md), so it must ask the vault, never name one
#   4. a worktree-taking skill must name CANONICAL where it touches git-ignored state (v1.51.0)
#      — see the section comment below; the count above and this list have both been wrong
#      before, so keep all three in step: this header, the numbered sections, and the
#      success line at the bottom that names each check to the reader.
# Run in CI (engine-ci) and before cutting a release. Exit 1 on any gap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USAGE="$ROOT/USAGE.md"
[ -f "$USAGE" ] || { echo "lint-docs: no USAGE.md at $USAGE" >&2; exit 1; }

fail=0

# 1. every skill documented in USAGE.md
for d in "$ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  if ! grep -q "$name" "$USAGE"; then
    echo "lint-docs: skill '$name' is not documented in USAGE.md (add it to the Skills section)" >&2
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

if [ "$fail" -eq 0 ]; then
  echo "lint-docs: all skills documented; no stale command references; no hardcoded boundary values; worktree skills name canonical for ignored state"
fi
exit "$fail"
