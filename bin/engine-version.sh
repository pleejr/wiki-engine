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
# `--latest-tag` prints ONLY the newest release tag on the remote and exits, so a caller
# that wants to cache the lookup and decide for itself (session-preflight.sh) does not
# have to parse a sentence written for a human. The comparison itself lives in ONE place,
# `engine_bump_level` in plugin-lib.sh, which this script and the banner both read.
#
# WIKI_ENGINE_NET_TIMEOUT — seconds git may spend below the low-speed floor before giving
# up (default 10). The SessionStart path passes a smaller budget; a hook must never be the
# slow thing in a boot.
#
# Usage: engine-version.sh [--latest-tag]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/plugin-lib.sh"

running="$(engine_release "$ENGINE")"
# the release tag at or behind what runs (no -N-g suffix)
running_tag="$(printf '%s' "$running" | sed -E 's/-[0-9]+-g[0-9a-f]+$//')"

MODE=""
case "${1:-}" in
  --latest-tag) MODE=tag;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  "") ;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac

remote=""
if git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1; then
  remote="$(git -C "$ENGINE" remote get-url origin 2>/dev/null || true)"
fi
[ -n "$remote" ] || remote="$(sed -nE 's/^[[:space:]]*"repository"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENGINE/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
if [ -z "$remote" ]; then
  # stdout stays EMPTY in --latest-tag mode: a caller reads "no answer" from the exit
  # status and an empty capture, never from a sentence it would have to recognise.
  [ "$MODE" = tag ] || echo "engine: running $running — no remote to compare against"
  exit 2
fi

NET="${WIKI_ENGINE_NET_TIMEOUT:-10}"
case "$NET" in ''|*[!0-9]*) NET=10;; esac
tags="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c "http.lowSpeedTime=$NET" \
  ls-remote --tags --refs "$remote" 'v*' 2>/dev/null)" \
  || { [ "$MODE" = tag ] || echo "engine: running $running — could not reach $remote (offline?); skipping update check"; exit 2; }
latest_tag="$(printf '%s\n' "$tags" | sed -nE 's#.*refs/tags/(v[0-9]+\.[0-9]+\.[0-9]+)$#\1#p' | sort -V | tail -1)"

if [ "$MODE" = tag ]; then
  [ -n "$latest_tag" ] || exit 2
  printf '%s\n' "$latest_tag"
  exit 0
fi

if [ -z "$latest_tag" ]; then
  echo "engine: running $running — no release tags on $remote; skipping update check"
  exit 0
fi
case "$running_tag" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "engine: running $running (not a release) — latest tag $latest_tag"; exit 1;;
esac

level="$(engine_bump_level "$running_tag" "$latest_tag")"
case "$level" in
  same)  echo "engine: up to date ($running)"; exit 0;;
  ahead) echo "engine: running $running is ahead of the latest tag ($latest_tag) — no action"; exit 0;;
esac

if [ "$level" = "MAJOR" ]; then
  echo "engine: running $running, latest $latest_tag — ⚠ MAJOR bump: review the CHANGELOG migration BEFORE adopting"
else
  echo "engine: running $running, latest $latest_tag — $level update; safe to adopt"
fi
echo "  to update: $(engine_update_remedy), then update.sh --wiki <vault> (same session), then restart"
exit 1
