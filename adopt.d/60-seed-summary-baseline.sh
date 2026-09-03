#!/usr/bin/env bash
# 60-seed-summary-baseline.sh — adoption step: seed the summary-volatility baseline once,
# so a vault adopting this engine goes green instead of red.
#
# The gate is ENFORCED, not advisory, because lint.sh is the pre-commit gate and CI: a
# warn-by-default check with pre-existing offenders prints on every commit forever, and
# standing noise is the failure this engine keeps re-learning. But enforcing outright
# would fail an existing vault's lint for pages unrelated to whatever it is committing.
# The ratchet resolves both: today's offenders are grandfathered, anything NEW errors.
#
# ADD-ONLY, and that matters here. If a baseline already exists this step does nothing —
# it must never re-seed, because re-seeding would silently re-grandfather violations the
# vault introduced after adoption, turning the ratchet back into a rubber stamp. Shrinking
# the baseline is the vault's own work; growing it is a deliberate, manual act.
#
# Run by apply-adopt.sh with WIKI / ENGINE exported (ADOPT_CHECK set when only reporting).
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"
# shellcheck source=bin/adopt-lib.sh
. "${ADOPT_LIB:?}" || exit 3

# ENGINE ASSETS — unconditional, above every consumer-state guard (see adopt-lib.sh).
require_engine_asset "$ENGINE/bin/lint-summary-volatility.sh" file "the summary-volatility gate"
require_engine_asset "$ENGINE/scaffold/summary-volatility-markers.txt" file "the volatility marker list"

# CONSUMER STATE — nothing to baseline without a projects/ dir.
[ -d "$WIKI/projects" ] || exit 0

# Honour the vault's configured baseline path if it declares one.
BASE_FILE="$(awk -F= '/^[ \t]*#/{next} { k=$1; gsub(/^[ \t]+|[ \t]+$/,"",k); if (k=="summary_baseline") { sub(/^[^=]*=/,""); gsub(/^[ \t]+|[ \t]+$/,"",$0); print; exit } }' "$WIKI/.wiki-gates.conf" 2>/dev/null)"
[ -n "$BASE_FILE" ] || BASE_FILE=".wiki-gates-summary-baseline"

# Already seeded — never re-seed (see above).
[ -f "$WIKI/$BASE_FILE" ] && exit 0

if [ -n "${ADOPT_CHECK:-}" ]; then
  if "$ENGINE/bin/lint-summary-volatility.sh" --wiki "$WIKI" --quiet >/dev/null 2>&1; then
    exit 0     # already clean; seeding would create an empty file for nothing
  fi
  echo "PENDING: adopt: would seed $BASE_FILE to grandfather existing project summaries"
  exit 0
fi

# Whether a clean vault gets a file is decided ONCE, inside --seed-baseline (it writes
# nothing when there is nothing to grandfather). This step deliberately does not re-test
# it: a second copy of the same rule is how the two drift apart.
out="$("$ENGINE/bin/lint-summary-volatility.sh" --wiki "$WIKI" --seed-baseline 2>&1)" || {
  echo "FAILED: adopt: could not seed $BASE_FILE — $out" >&2; exit 1; }
[ -f "$WIKI/$BASE_FILE" ] || exit 0     # nothing to grandfather; stay silent
echo "ADOPTED: adopt: seeded $BASE_FILE — existing project summaries grandfathered; new ones are enforced"
