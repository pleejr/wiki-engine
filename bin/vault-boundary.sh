#!/usr/bin/env bash
# vault-boundary.sh — print the boundary a vault declares in its own CLAUDE.md.
#
# The engine is boundary-agnostic: SCHEMA.md says each consuming wiki declares its own
# boundary and the engine knows none of them. Anything in the engine that needs to KNOW
# a vault's boundary — to compare a page against it, or to rewrite one — must therefore
# ask the vault rather than name a value. This is that question, in one place, so the
# rule cannot be re-implemented three subtly different ways.
#
# ACCEPTS ANY WELL-FORMED TOKEN, deliberately not a fixed pair. Matching against a
# hardcoded ("personal", "work") is what made rag-build's cross-boundary skip fail OPEN:
# a vault on any other boundary fell through to "no declaration", which switches the
# filter off entirely — disabling the one automated guard on exactly the vaults that had
# adopted a new boundary. Kept in sync with rag-build.sh's vault_boundary() by intent.
#
# Exit 0 + the token on stdout when a declaration is found; exit 1 and print nothing
# when there is none to find. A caller must decide what an absent declaration means for
# IT — that is not a decision this script can make on the caller's behalf.
#
# Usage: vault-boundary.sh [--wiki DIR]
set -uo pipefail

WIKI="${WIKI_PATH:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "vault-boundary: unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$WIKI" ] || { echo "vault-boundary: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 2; }

CM="$WIKI/CLAUDE.md"
[ -f "$CM" ] || exit 1

# First well-formed token after a `boundary:` on any line. Prose that merely mentions
# "boundary:" yields a non-token and is skipped rather than accepted — the same reason
# rag-build reports and keeps looking instead of taking the first match blindly.
while IFS= read -r line; do
  case "$line" in *boundary:*) ;; *) continue;; esac
  after="${line#*boundary:}"
  # strip leading space and markdown emphasis/backticks, then take the first word
  after="$(printf '%s' "$after" | sed -E 's/^[[:space:]`*_]+//')"
  tok="${after%%[![:alnum:]-]*}"
  if printf '%s' "$tok" | grep -qE '^[a-z][a-z0-9-]*$'; then
    printf '%s\n' "$tok"; exit 0
  fi
done < "$CM"
exit 1
