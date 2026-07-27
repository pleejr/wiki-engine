#!/usr/bin/env bash
# lint-adopt-paths.sh — assert that adoption steps reference engine assets that actually
# exist in this checkout. Mechanical backstop for the bug that made it necessary: a step
# resolved its bundled template as "$ENGINE/../scaffold/pre-commit", one directory too
# high, and so probed the CONSUMER's vault root. It found nothing, exited 0, and reported
# as adopted for four minor releases. One run of this check would have caught it.
#
# TWO CHECKS, deliberately narrow — see the LIMIT note below:
#
#   (a) ESCAPE — a step must never derive a path ABOVE the engine root. `$ENGINE/..` is
#       the consumer's vault, whose contents the engine may not assume. This single rule
#       catches the original bug on its own.
#
#   (b) RESOLUTION — every LITERAL "$ENGINE/<path>" must exist in this checkout.
#
# LIMIT (stated here rather than left to be discovered): (b) can only see literal paths.
# A step that builds "$SRC/$name" from a variable is invisible to it, and making the
# check "smart" enough to chase those would mean either false positives on every dynamic
# path or a loosening until it stops being able to fail — a check that can never be red
# is decoration, which is the same defect class this file exists to prevent. The
# guarantee is: no escapes, and every hardcoded engine path resolves.
#
# Usage:
#   lint-adopt-paths.sh                 # check the engine this script lives in
#   lint-adopt-paths.sh --engine DIR    # check another engine tree (CI uses this to run
#                                       # the checker against a fixture it must REJECT)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE_ROOT="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "lint-adopt-paths: unknown arg: $1" >&2; exit 2;;
  esac
done

ADOPT_D="$ENGINE_ROOT/adopt.d"
[ -d "$ADOPT_D" ] || { echo "lint-adopt-paths: no adopt.d/ in $ENGINE_ROOT — nothing to check"; exit 0; }

fail=0
checked=0

code="$(mktemp)"; trap 'rm -f "$code"' EXIT

for step in "$ADOPT_D"/*.sh; do
  [ -e "$step" ] || continue
  name="$(basename "$step")"

  # Blank out whole-line comments (a comment cannot misresolve anything, and the fixed
  # step DESCRIBES the old bad path in one). Blanked, not deleted, so reported line
  # numbers still match the real file. Only full-line comments — heredocs and code are
  # left intact, so a bad path hiding in emitted text is still caught.
  sed -E 's/^[[:space:]]*#.*$//' "$step" > "$code"

  # (a) escape above the engine root — matches $ENGINE/.. and ${ENGINE}/..
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    echo "lint-adopt-paths: ERROR $name:${hit%%:*} derives a path ABOVE the engine root"
    echo "    ${hit#*:}"
    echo "    \$ENGINE is the engine ROOT; \$ENGINE/.. is the consumer's vault."
    fail=1
  done < <(grep -nE '\$\{?ENGINE\}?/\.\.' "$code" | sed 's/[[:space:]]*$//')

  # (b) literal "$ENGINE/<path>" must resolve. The character class stops at the first
  # quote, space or '$', so a dynamic segment truncates the match rather than producing
  # a bogus one; segments still containing '$' are skipped outright below.
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in *'$'*|*'..'*) continue;; esac
    checked=$((checked+1))
    if [ ! -e "$ENGINE_ROOT/$rel" ]; then
      echo "lint-adopt-paths: ERROR $name references \$ENGINE/$rel — no such path in the engine"
      echo "    resolved: $ENGINE_ROOT/$rel"
      fail=1
    fi
  done < <(grep -oE '\$\{?ENGINE\}?/[A-Za-z0-9_./-]+' "$code" \
             | sed -E 's#^\$\{?ENGINE\}?/##' | sort -u)
done

if [ "$fail" -ne 0 ]; then
  echo "lint-adopt-paths: FAILED"
  exit 1
fi
echo "lint-adopt-paths: ok ($checked literal engine path(s) resolve; no escapes)"
