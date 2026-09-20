#!/usr/bin/env bash
# update.sh — bring a vault up to the engine release that is running, in one step:
#   1. record that release in the vault's .engine-version (the tag its CI checks out)
#   2. run adopt.sh (node folders + adopt.d steps)
#   3. re-sync the RAG venv to the engine's pinned deps (rag-setup.sh, if provisioned)
#   4. advance the engine's own repo page provenance, and regenerate the skills catalog
#
# The plugin marketplace already moved the engine; this moves the vault's record of it.
# Refuses a MAJOR difference — those need a reviewed migration (see CHANGELOG) — and refuses
# to record a release OLDER than the one the vault already needs. Stages what it writes;
# never commits (adoption is a human gate). Deterministic; no `claude`. doctor.sh reports;
# this applies.
#
# WHICH TREE. Everything written here is ordinary tracked vault content, and writing it into
# a shared canonical checkout is the clobber worktrees exist to prevent. So it is written in
# the caller's own worktree when they stand in one; when a commit in canonical would be
# refused (canonical_commit_gated), nothing is written and the command to rerun from a
# worktree is printed. A vault that can commit in canonical is unaffected.
#
# Usage: update.sh [--wiki DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/wiki-root-lib.sh" || exit 1
. "$SCRIPT_DIR/plugin-lib.sh"
WIKI="${WIKI_PATH:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --wiki) WIKI="$2"; shift 2;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$WIKI" ] || { echo "error: set \$WIKI_PATH or pass --wiki DIR" >&2; exit 1; }
[ -d "$WIKI" ] || { echo "error: no vault at $WIKI" >&2; exit 1; }
WIKI="$(cd "$WIKI" && pwd)"
core_major() { printf '%s' "$1" | sed -E 's/^v//; s/[.-].*$//'; }

# A 1.x vault pins the engine as a submodule. Recording .engine-version beside it would give
# two answers to "which engine does this vault need", while its import, gate and CI kept
# running the submodule copy. The migration drops the submodule first.
if vault_has_engine_submodule "$WIKI"; then
  echo "update: $WIKI still carries the 1.x engine/ submodule, which 2.x does not use." >&2
  echo "update:   Drop it first: engine CHANGELOG, 2.0.0, \"Dropping the vault's submodule\"." >&2
  exit 1
fi

latest="$(engine_release "$ENGINE")"
case "$latest" in unknown|"") echo "update: cannot tell which release is running from $ENGINE" >&2; exit 1;; esac

# The tree the caller stands in: an explicit argument would be returned as-is. Resolved
# BEFORE the guards, because the record they judge must be the one in the tree the caller
# can commit from. Reading it from canonical instead made the MAJOR refusal unclearable: a
# migration is recorded by hand in a worktree, canonical still said the old release, and the
# next run refused again — with no way forward that the message named.
PAGE_TREE="$(WIKI_PATH="$WIKI" resolve_wiki_root "" 2>/dev/null)" || PAGE_TREE="$WIKI"
required="$(vault_engine_required "$PAGE_TREE")"
[ -n "$required" ] || required="$(vault_engine_required "$WIKI")"

if [ -n "$required" ] && [ "$(core_major "$latest")" != "$(core_major "$required")" ]; then
  echo "update: ⚠ the running engine $latest and the vault's $required differ in MAJOR — review the CHANGELOG migration; not applied." >&2
  echo "update:   Once the migration is done, record the release in the tree you commit from:" >&2
  echo "update:     printf '%s\\n' \"$latest\" > \"$PAGE_TREE/.engine-version\"" >&2
  echo "update:   then rerun this to adopt the rest." >&2
  exit 1
fi
if [ -n "$required" ] && engine_version_lt "$latest" "$required"; then
  echo "update: the running engine $latest is older than the vault's $required — run: claude plugin update wiki-engine@wiki-engine" >&2
  exit 1
fi

# --- adoption and the recall runtime, FIRST: adoption may install the vault's gate, and
# whether canonical is gated decides where everything below is written.
"$SCRIPT_DIR/adopt.sh" --wiki "$WIKI"
if [ -x "$WIKI/.rag/venv/bin/python" ]; then
  "$SCRIPT_DIR/rag-setup.sh" --wiki "$WIKI" >/dev/null && echo "update: RAG deps in sync"
fi

defer=0
if [ "$PAGE_TREE" = "$WIKI" ] && [ -n "$(canonical_commit_gated "$WIKI")" ]; then
  defer=1
fi

# --- .engine-version --------------------------------------------------------------------
recorded=""
if [ "$required" = "$latest" ]; then
  echo "update: .engine-version already records $latest"
elif [ "$defer" = "1" ]; then
  recorded="deferred"
else
  printf '%s\n' "$latest" > "$PAGE_TREE/.engine-version"
  git -C "$PAGE_TREE" add .engine-version 2>/dev/null || true
  recorded="staged"
  echo "update: .engine-version ${required:-<none>} -> $latest (staged in $PAGE_TREE)"
fi

# --- the engine's own repo page: provenance, NOT its verified stamp -----------------
# A vault that documents the engine re-stales that page on every release. Advancing
# `sources.ref`/`sha` removes that churn without losing the signal: `refresh` compares
# provenance to the repo, `verify` compares `verified.against` to `sources.sha`, so the page
# now reads VERIFIED-STALE — the pointer is current, the content unconfirmed. `verified:` is
# never written here; that would fabricate the one signal the vault refuses to fabricate.
#
# The commit the release names. A plugin cache is not a git repo, so ask the checkout when
# there is one, else the engine's public remote (bounded); without either the page is left
# as it was, and the run says so.
engine_url="$(sed -nE 's/^[[:space:]]*"repository"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENGINE/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
engine_repo="$(basename "${engine_url:-wiki-engine}" .git)"
new_sha=""
if git -C "$ENGINE" rev-parse --git-dir >/dev/null 2>&1; then
  new_sha="$(git -C "$ENGINE" rev-parse --short HEAD 2>/dev/null || true)"
elif [ -n "$engine_url" ]; then
  # THE PEELED LINE, chosen by NAME. An annotated tag's own object is not the commit, and
  # `ls-remote` answers in REFNAME order — `refs/tags/vX` sorts before `refs/tags/vX^{}` —
  # so asking for both and taking the first line records the tag object. That sha is in no
  # branch, so the page can never match `HEAD` again and reads stale forever. A lightweight
  # tag has no peeled line, hence the fallback.
  ls_out="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 \
    ls-remote "$engine_url" "refs/tags/$latest^{}" "refs/tags/$latest" 2>/dev/null || true)"
  new_sha="$(printf '%s\n' "$ls_out" | awk '$2 ~ /\^\{\}$/ { print substr($1,1,7); exit }')"
  [ -n "$new_sha" ] || new_sha="$(printf '%s\n' "$ls_out" | awk 'NF { print substr($1,1,7); exit }')"
fi

bumped="" deferred_page=""
if [ -z "$new_sha" ]; then
  echo "update: could not resolve $latest to a commit (offline?) — any $engine_repo repo page is left as it was"
elif [ -d "$WIKI/repos" ]; then
  for page in "$WIKI/repos"/*.md; do
    [ -f "$page" ] || continue
    # only a page that actually documents THIS repo (sources.repo), never by filename
    page_repo="$(awk '
      NR==1 && $0=="---" { infm=1; next }
      infm && $0=="---"  { exit }
      infm && /^sources:/ { blk=1; next }
      infm && /^[A-Za-z_]+:/ { blk=0 }
      infm && blk && /^[ \t]+(- )?repo:/ { sub(/^[^:]*:[ \t]*/,""); gsub(/[" \t]/,""); print; exit }
    ' "$page")"
    [ "$page_repo" = "$engine_repo" ] || continue
    if [ "$defer" = "1" ]; then deferred_page="${page#$WIKI/}"; continue; fi
    page="$PAGE_TREE/${page#$WIKI/}"
    [ -f "$page" ] || continue
    tmp="$(mktemp)"
    awk -v newref="$latest" -v newsha="$new_sha" -v today="$(date +%Y-%m-%d)" '
      NR==1 && $0=="---" { infm=1; print; next }
      infm && $0=="---"  { infm=0; print; next }
      infm && /^sources:/ { blk="sources"; print; next }
      infm && /^verified:/ { blk="verified"; print; next }
      infm && /^[A-Za-z_]+:/ { blk=""; print; next }
      # rewrite ONLY inside the sources block; the verified block passes through untouched
      infm && blk=="sources" && /^[ \t]+(- )?ref:/      { sub(/ref:.*/, "ref: " newref);      print; next }
      infm && blk=="sources" && /^[ \t]+(- )?sha:/      { sub(/sha:.*/, "sha: " newsha);      print; next }
      infm && blk=="sources" && /^[ \t]+(- )?ingested:/ { sub(/ingested:.*/, "ingested: " today); print; next }
      { print }
    ' "$page" > "$tmp" && mv "$tmp" "$page"
    git -C "$PAGE_TREE" add "${page#$PAGE_TREE/}" 2>/dev/null || true
    bumped="${page#$PAGE_TREE/}"
  done
fi

# --- the skills catalog -------------------------------------------------------------
# index.md's catalog is generated from the engine's skills, so a release that adds or
# removes one leaves it stale. Same tree rule as everything above.
catalog=""
if [ -x "$SCRIPT_DIR/gen-skills-index.sh" ] && [ -f "$PAGE_TREE/index.md" ] \
   && ! "$SCRIPT_DIR/gen-skills-index.sh" --check --wiki "$PAGE_TREE" >/dev/null 2>&1; then
  if [ "$defer" = "1" ]; then
    catalog="deferred"
  elif "$SCRIPT_DIR/gen-skills-index.sh" --wiki "$PAGE_TREE" >/dev/null 2>&1; then
    git -C "$PAGE_TREE" add index.md 2>/dev/null || true
    catalog="staged"
  fi
fi

# --- what to do next --------------------------------------------------------------------
if [ "$recorded" = "deferred" ] || [ "$catalog" = "deferred" ] || [ -n "$deferred_page" ]; then
  cat <<MSG

NOT written: this vault gates commits in its canonical checkout, and what this release
changes (.engine-version${deferred_page:+, $deferred_page}${catalog:+, the index.md skills catalog}) is
tracked content. Rerun from a worktree, where it is written and staged for you:

  WORK="\$($SCRIPT_DIR/vault-worktree.sh ensure)" && (cd "\$WORK" && $SCRIPT_DIR/update.sh --wiki "$WIKI")

Then review the CHANGELOG, commit in the worktree, and integrate.
MSG
  exit 0
fi

if [ -n "$recorded$catalog$bumped" ]; then
  echo
  echo "Staged in $PAGE_TREE — review the CHANGELOG, then commit together:"
  [ "$recorded" = "staged" ] && echo "  .engine-version -> $latest"
  [ "$catalog" = "staged" ]  && echo "  index.md skills catalog, regenerated for $latest"
  if [ -n "$bumped" ]; then
    echo "  $bumped provenance -> $latest ($new_sha)"
    echo "    Its verified: stamp was left alone, so the page reads VERIFIED-STALE until someone"
    echo "    re-reads the repo; \`upkeep scan\` queues that verify pass."
  fi
fi
exit 0
