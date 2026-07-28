#!/usr/bin/env bash
# 50-normalize-repo-refs.sh — adoption step: rewrite git-describe refs on repo pages
# to their base tag, so the v1.39.0 `repo ref is a clean tag` gate lands at ZERO.
#
# WHY THIS EXISTS AT ALL. The engine's gates are held at zero — a violation fails the
# write, so there is no backlog of known violations to normalise. Shipping the gate
# alone would have violated that on arrival: a vault carrying describe-form refs would
# adopt the release and immediately be unable to commit, with a backlog it did not
# create and no tool to clear. The incoming proposal sequenced tolerance first and
# enforcement second for this reason, but sequencing does not fix it — the tolerance
# makes the refs harmless, which is exactly why nobody would ever rewrite them. So the
# migration ships WITH the gate, not before or after it.
#
# Rewriting a provenance field on a repo page is precedented, not novel: update.sh
# already advances repos/<engine>.md's ref/sha when it bumps the pin, and leaves the
# change for the operator to review and commit. Same contract here — adoption never
# commits into a consumer's vault.
#
# NARROW AND REVERSIBLE. Only a trailing `-<N>-g<hex>` is removed, only from a `ref:`
# line inside a repos/ page. `sources.sha` is untouched, so nothing is lost: the commit
# offset the suffix encoded is precisely what sha already records, and the verify axis
# (verified.against vs sources.sha) is unaffected. Idempotent — a second run is a no-op.
#
# Run by apply-adopt.sh with WIKI / ENGINE exported (ADOPT_CHECK set when only reporting).
set -uo pipefail

: "${WIKI:?}"; : "${ENGINE:?}"
. "${ADOPT_LIB:?}" || exit 3

CHECK="${ADOPT_CHECK:-}"

# CONSUMER STATE — a vault with no repos/ has nothing to normalise. Genuine no-op.
[ -d "$WIKI/repos" ] || exit 0

changed=0
for f in "$WIKI/repos"/*.md; do
  [ -f "$f" ] || continue
  # only inside frontmatter's sources block: a ref: line. Match the describe suffix.
  grep -qE '^[[:space:]]*-?[[:space:]]*ref:[[:space:]]*[^[:space:]]*-[0-9]+-g[0-9a-f]{7,}[[:space:]]*$' "$f" || continue
  old="$(awk '/^[[:space:]]*-?[[:space:]]*ref:/{sub(/^[^:]*:[[:space:]]*/,""); gsub(/[[:space:]]/,""); print; exit}' "$f")"
  new="$(printf '%s' "$old" | sed -E 's/-[0-9]+-g[0-9a-f]{7,}$//')"
  if [ -n "$CHECK" ]; then
    echo "adopt: would normalise ${f#$WIKI/} ref $old -> $new"
  else
    tmp="$f.tmp.$$"
    sed -E "s/^([[:space:]]*-?[[:space:]]*ref:[[:space:]]*)$old[[:space:]]*$/\1$new/" "$f" > "$tmp" && mv "$tmp" "$f"
    echo "adopt: normalised ${f#$WIKI/} ref $old -> $new"
  fi
  changed=$((changed+1))
done

if [ "$changed" -gt 0 ] && [ -z "$CHECK" ]; then
  echo "adopt:   $changed repo page(s) rewritten — review and commit them (a describe ref"
  echo "adopt:   could never equal a clean tag, so those pages were flagged stale forever)."
fi
exit 0
