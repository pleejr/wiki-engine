#!/usr/bin/env bash
# engine-version.sh — report the running engine release vs the latest RELEASE TAG on the
# engine's remote. Staleness is measured tag-to-tag because the plugin marketplace pins
# release tags; untagged commits on main are not something a consumer can install.
# Deterministic (plain git, no LLM, no claude), bounded network — safe to run anytime.
#
# The plugin cache is not a git repo, so the remote comes from the plugin manifest's
# `repository` and is read with `git ls-remote`; a checkout (directory marketplace, dev
# clone) uses its own origin instead.
#
# Exit: 0 up to date (or ahead) · 1 update available · 2 error (no remote / offline).
# A MAJOR-version bump is flagged as breaking — review the migration before adopting.
#
# Usage: engine-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/plugin-lib.sh"

running="$(engine_release "$ENGINE")"
# the release tag at or behind what runs (no -N-g suffix)
running_tag="$(printf '%s' "$running" | sed -E 's/-[0-9]+-g[0-9a-f]+$//')"

remote=""
if git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1; then
  remote="$(git -C "$ENGINE" remote get-url origin 2>/dev/null || true)"
fi
[ -n "$remote" ] || remote="$(sed -nE 's/^[[:space:]]*"repository"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENGINE/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
[ -n "$remote" ] || { echo "engine: running $running — no remote to compare against"; exit 2; }

tags="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 \
  ls-remote --tags --refs "$remote" 'v*' 2>/dev/null)" \
  || { echo "engine: running $running — could not reach $remote (offline?); skipping update check"; exit 2; }
latest_tag="$(printf '%s\n' "$tags" | sed -nE 's#.*refs/tags/(v[0-9]+\.[0-9]+\.[0-9]+)$#\1#p' | sort -V | tail -1)"

if [ -z "$latest_tag" ]; then
  echo "engine: running $running — no release tags on $remote; skipping update check"
  exit 0
fi
case "$running_tag" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "engine: running $running (not a release) — latest tag $latest_tag"; exit 1;;
esac

if [ "$running_tag" = "$latest_tag" ]; then
  echo "engine: up to date ($running)"
  exit 0
fi
higher="$(printf '%s\n%s\n' "$running_tag" "$latest_tag" | sort -V | tail -1)"
if [ "$higher" = "$running_tag" ]; then
  echo "engine: running $running is ahead of the latest tag ($latest_tag) — no action"
  exit 0
fi

core() { printf '%s' "$1" | sed -E 's/^v//; s/-.*$//'; }
rc="$(core "$running_tag")"; lc="$(core "$latest_tag")"
rmaj="${rc%%.*}"; lmaj="${lc%%.*}"
rrest="${rc#*.}"; lrest="${lc#*.}"; rmin="${rrest%%.*}"; lmin="${lrest%%.*}"
if [ "$rmaj" != "$lmaj" ]; then level="MAJOR"
elif [ "$rmin" != "$lmin" ]; then level="minor"
else level="patch"; fi

if [ "$level" = "MAJOR" ]; then
  echo "engine: running $running, latest $latest_tag — ⚠ MAJOR bump: review the CHANGELOG migration BEFORE adopting"
else
  echo "engine: running $running, latest $latest_tag — $level update; safe to adopt"
fi
echo "  to update: claude plugin update wiki-engine@wiki-engine (restart), then update.sh --wiki <vault>"
exit 1
