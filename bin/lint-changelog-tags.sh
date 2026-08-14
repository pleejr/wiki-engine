#!/usr/bin/env bash
# lint-changelog-tags.sh — a released CHANGELOG heading must have its tag.
#
# THE DEFECT THIS CLOSES. `1.44.1` reached `main` carrying a `## [1.44.1]` section, its own
# "Adopt with `bin/adopt.sh` or `update.sh`" line, and no tag — the only version in sixty-odd
# releases to do so. Nothing here could see it: `lint-docs.sh` and `lint-proposals.sh` never
# read CHANGELOG.md, and `release.yml` runs only BECAUSE a tag was pushed, so the one case it
# structurally cannot observe is the tag that was never cut. It surfaced three weeks later,
# from a verify pass reading a consuming vault's engine page against `git tag`.
#
# No content was lost — the fixes rode into v1.45.0 hours later — but the RECORD was wrong: a
# consumer pinned at v1.44.0 had no v1.44.1 to advance to, so `update.sh` stepped them over a
# PATCH straight to a MINOR, and `git tag --contains` credited those fixes to the release that
# did not make them.
#
# WHEN A HEADING IS ALLOWED TO HAVE NO TAG — the whole difficulty of this gate. Writing the
# section always PRECEDES pushing the tag, so the entry being released legitimately has no tag
# for as long as the release takes. A gate blind to that would redden the merge that RECORDS a
# release — the exact shape this repo has already shipped twice: a generated ledger going stale
# failing the arrival that staled it, and the soft-wrap gate rejecting the very proposal files
# it exists to receive. "The merge that records arrival must not be the thing that breaks the
# build" is the rule both of those produced, and it governs here.
#
# So the rule is neither "every heading" nor "every heading except the top one":
#
#     If a version's entry was ALREADY ON MAIN when the newest tag was cut, it must be tagged.
#
# Cutting any tag is the moment every entry already in the file had its chance. That test is
# independent of two things this file cannot rely on:
#   - WHERE the entry sits. `1.66.1` is placed ABOVE `1.67.0`, so "topmost" is not "newest".
#   - VERSION ORDER. A patch line can land between minors, so "highest version" is not
#     "in flight" either — and a tag cut retroactively (v1.44.1 was) is newest by DATE while
#     oldest by line, which is why the comparison below picks the newest tag by VERSION.
#
# Consequence worth stating: a skipped tag is caught on the NEXT release, not at the moment it
# is skipped. That latency is inherent — until something else ships, "not tagged yet" and
# "never tagged" are the same observation. One release cycle is the earliest a gate can
# honestly tell them apart.
#
# Usage: lint-changelog-tags.sh [--repo DIR]
# Deterministic: no network, no `claude`. Exit 1 on any gap.
set -uo pipefail

REPO=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$REPO" ] || REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CL="$REPO/CHANGELOG.md"
[ -f "$CL" ] || { echo "lint-changelog-tags: no CHANGELOG.md at $CL" >&2; exit 1; }

# History IS the instrument here. A shallow clone walks nothing, finds nothing, and would
# report a clean pass over an empty history — decoration rather than a gate, and the class
# this repo has now shipped fixes for three times. Refuse out loud instead.
if [ "$(git -C "$REPO" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
  echo "lint-changelog-tags: SHALLOW clone — cannot walk history, so this gate cannot run." >&2
  echo "lint-changelog-tags:   CI must check out with fetch-depth: 0. Refusing rather than" >&2
  echo "lint-changelog-tags:   passing vacuously, which is what a silent skip would be." >&2
  exit 1
fi

newest_tag="$(git -C "$REPO" tag -l 'v[0-9]*' | sort -V | tail -1)"
if [ -z "$newest_tag" ]; then
  echo "lint-changelog-tags: no version tags exist — nothing has been released, so no heading is due one"
  exit 0
fi
newest_commit="$(git -C "$REPO" rev-list -1 "$newest_tag" 2>/dev/null)"
[ -n "$newest_commit" ] || { echo "lint-changelog-tags: cannot resolve $newest_tag" >&2; exit 1; }

fail=0
checked=0
exempt=0

while read -r v; do
  [ -n "$v" ] || continue
  checked=$((checked + 1))
  git -C "$REPO" rev-parse -q --verify "refs/tags/v$v" >/dev/null && continue

  # Untagged. Find the commit that introduced this heading. No pipe into `head`: a reader
  # closing early sends SIGPIPE, and under `pipefail` that reads as a failed command — the
  # trap this repo documents elsewhere. Capture whole, then take the first line.
  intro="$(git -C "$REPO" log --format=%H --reverse -S"## [$v]" -- CHANGELOG.md 2>/dev/null)"
  intro="${intro%%$'\n'*}"

  # In the working tree but in no commit: the entry is being written right now.
  [ -n "$intro" ] || { exempt=$((exempt + 1)); continue; }

  if git -C "$REPO" merge-base --is-ancestor "$intro" "$newest_commit" 2>/dev/null; then
    echo "lint-changelog-tags: $v has a CHANGELOG section but no v$v tag" >&2
    echo "lint-changelog-tags:   its entry (${intro:0:9}) was already on main when $newest_tag was cut," >&2
    echo "lint-changelog-tags:   so the release ritual was SKIPPED for it, not merely pending." >&2
    echo "lint-changelog-tags:   A consumer pinned below it cannot adopt it, and 'git tag --contains'" >&2
    echo "lint-changelog-tags:   credits its content to whichever release shipped next." >&2
    echo "lint-changelog-tags:   Cut it at the commit carrying its content:  git tag -a v$v <sha>" >&2
    fail=1
  else
    # Newer than the newest release: this is the entry currently being shipped.
    exempt=$((exempt + 1))
  fi
done < <(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CL" | tr -d '#[] ')

if [ "$fail" -eq 0 ]; then
  echo "lint-changelog-tags: $checked version heading(s) checked against $newest_tag; every entry that predates it has its tag${exempt:+ ($exempt in flight)}"
fi
exit "$fail"
