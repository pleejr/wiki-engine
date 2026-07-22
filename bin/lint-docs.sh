#!/usr/bin/env bash
# lint-docs.sh — keep the usage docs honest so new users adopt with the lowest friction.
# Two cheap, deterministic checks (no LLM, never `claude`):
#   1. every skill (skills/*/) is mentioned in USAGE.md  — nothing user-facing goes undocumented
#   2. every `bin/<name>.sh` USAGE.md references actually exists — no stale pointers to deleted tools
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

if [ "$fail" -eq 0 ]; then
  echo "lint-docs: all skills documented; no stale command references"
fi
exit "$fail"
