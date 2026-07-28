#!/usr/bin/env bash
# lint-docs.sh — keep the usage docs honest so new users adopt with the lowest friction.
# Two cheap, deterministic checks (no LLM, never `claude`):
#   1. every skill (skills/*/) is mentioned in USAGE.md  — nothing user-facing goes undocumented
#   2. every `bin/<name>.sh` USAGE.md references actually exists — no stale pointers to deleted tools
#   3. no shipped skill or tool STAMPS a specific boundary value — the engine is
#      boundary-agnostic (SCHEMA.md), so it must ask the vault, never name one
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

if [ "$fail" -eq 0 ]; then
  echo "lint-docs: all skills documented; no stale command references; no hardcoded boundary values"
fi
exit "$fail"
