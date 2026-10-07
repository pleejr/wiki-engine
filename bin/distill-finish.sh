#!/usr/bin/env bash
# distill-finish.sh — every mechanical step that ends a `distill`, in fixed order, then a
# close check. The skill keeps the judgement (what is durable, where it goes, the commit);
# this keeps the steps whose defects were all "which tree" and "which route" mistakes.
#
#   1. refuse unless run from this session's own vault worktree, with everything committed
#   2. regenerate the projects catalog and lint the worktree (a failing lint stops here)
#   3. land the session branch by the vault's DECLARED route (.wiki-gates.conf `publish`):
#        direct — vault-worktree.sh integrate, then push canonical main
#        pr     — push the branch and open (or find) its pull request; never integrate
#      A vault that declares no route is refused, naming the setting: guessing the route is
#      how a pull-request vault once had canonical main diverge from its own squash-merge.
#   4. rebuild the semantic-recall index in canonical, once the commit is on canonical main
#   5. age out the capture buffer in canonical: delete a raw/sessions/YYYY-MM.md whose
#      newest block is older than the window (default 60 days), under rag-capture's own lock,
#      and never the current month's file. Replaces the per-block prune: a block only held
#      repo, HEAD and commit subjects, all recoverable from git and the transcript.
#   6. retire this session's worktree once its commits are on main (never a peer's)
#   7. close check — what this session still owes before it is safe to close
#
# Output ends with exactly one verdict line for the VAULT:
#   VAULT DONE — <what landed>
#   VAULT OUTSTANDING — <k> item(s):   followed by one line per item with the command that clears it
# and, for every --repo given, REVIEW lines: facts about that repository (uncommitted files,
# unpushed branches, extra worktrees, open pull requests) that this script cannot attribute to
# a session. The skill decides which are this session's before it says the session is safe
# to close; running shells and subagents are visible only to the session itself.
#
# Parallel sessions: everything acted on is keyed by this session's worktree and branch.
# Peers' worktrees, branches, leases and buffer files are read, never changed.
#
# Usage: distill-finish.sh [--repo DIR]... [--window-days N] [--no-push]
#   run from inside the session worktree that `vault-worktree.sh ensure` printed.
# Exit: 0 vault done · 1 vault outstanding · 2 refused (wrong tree, no route declared, usage)
# In-session and operator-initiated only; never from a lifecycle hook. Deterministic: no `claude`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=() WINDOW_DAYS=60 PUSH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPOS+=("$2"); shift 2;;
    --window-days) WINDOW_DAYS="$2"; shift 2;;
    --no-push)     PUSH=0; shift;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "distill-finish: unknown arg: $1" >&2; exit 2;;
  esac
done

OUT=()                                   # outstanding vault items, one line each
owe() { OUT+=("$1"); }
say() { printf 'distill-finish: %s\n' "$1"; }

WORK="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "distill-finish: not inside a git checkout" >&2; exit 2; }
CANON="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
if [ "$WORK" = "$CANON" ] && [ "${WIKI_WORKTREE:-1}" != "0" ]; then
  echo "distill-finish: refusing — this is the canonical checkout ($CANON)." >&2
  echo "distill-finish:   run from the session worktree printed by vault-worktree.sh ensure." >&2
  exit 2
fi
export WIKI_PATH="$CANON"
BRANCH="$(git -C "$WORK" rev-parse --abbrev-ref HEAD)"

# --- 1. everything committed ------------------------------------------------------------
if [ -n "$(git -C "$WORK" status --porcelain)" ]; then
  echo "distill-finish: refusing — $WORK has uncommitted changes. Commit them (stage explicit paths), then rerun." >&2
  git -C "$WORK" status --short >&2
  exit 1
fi

# --- route ------------------------------------------------------------------------------
# The route is read from the tree being LANDED first, then canonical: a vault that declares
# its route in the same commit (its first distill) would otherwise be refused for a setting
# it is in the act of landing — the pre-commit skew note had the same canonical-first shape.
route=""
for conf in "$WORK/.wiki-gates.conf" "$CANON/.wiki-gates.conf"; do
  [ -f "$conf" ] || continue
  route="$(awk -F= '/^[ \t]*#/{next} {k=$1; gsub(/[ \t]/,"",k); if (k=="publish") {v=$2; gsub(/[ \t]/,"",v); print v; exit}}' "$conf")"
  [ -n "$route" ] && break
done
case "$route" in
  direct|pr) ;;
  *) echo "distill-finish: refusing — the vault declares no publish route." >&2
     echo "distill-finish:   add ONE line to $CANON/.wiki-gates.conf:" >&2
     echo "distill-finish:     publish = direct   (commits land on main by integrate, then push)" >&2
     echo "distill-finish:     publish = pr       (commits land by pull request; main moves only by the merge)" >&2
     exit 2;;
esac

# --- 2. catalog + lint ------------------------------------------------------------------
"$SCRIPT_DIR/gen-projects-index.sh" --wiki "$WORK" >/dev/null 2>&1 || true
if [ -n "$(git -C "$WORK" status --porcelain)" ]; then
  echo "distill-finish: the projects catalog was stale and is now regenerated in $WORK — commit index.md, then rerun." >&2
  exit 1
fi
# Lint what this session changed against canonical's main; lint.sh widens to the whole vault
# itself when a page was deleted or renamed.
if ! "$SCRIPT_DIR/lint.sh" --wiki "$WORK" --changed "$(git -C "$CANON" rev-parse --abbrev-ref HEAD)" > "${TMPDIR:-/tmp}/distill-finish-lint.$$" 2>&1; then
  tail -25 "${TMPDIR:-/tmp}/distill-finish-lint.$$" >&2; rm -f "${TMPDIR:-/tmp}/distill-finish-lint.$$"
  echo "distill-finish: lint failed in $WORK — fix it, commit, rerun. Nothing was landed." >&2
  exit 1
fi
rm -f "${TMPDIR:-/tmp}/distill-finish-lint.$$"
say "lint passed"

# --- 3. land ----------------------------------------------------------------------------
git -C "$CANON" fetch -q origin 2>/dev/null || true
main="$(git -C "$CANON" rev-parse --abbrev-ref HEAD)"
ahead="$(git -C "$WORK" rev-list --count "$main..HEAD" 2>/dev/null || echo 0)"
landed=0
if [ "$ahead" = "0" ]; then
  say "nothing on $BRANCH that $main lacks"; landed=1
elif [ "$route" = "direct" ]; then
  ( cd "$WORK" && "$SCRIPT_DIR/vault-worktree.sh" integrate ) >/dev/null 2>&1; rc=$?
  case "$rc" in
    0) landed=1; say "integrated $BRANCH into $main";;
    3) owe "integrate hit a conflict: resolve it in $WORK, then rerun distill-finish.sh";;
    4) owe "another session holds the integrate lock: rerun distill-finish.sh in a minute";;
    *) owe "integrate failed (rc=$rc): run vault-worktree.sh integrate from $WORK and read its output";;
  esac
  if [ "$landed" = 1 ] && [ "$PUSH" = 1 ] && git -C "$CANON" remote get-url origin >/dev/null 2>&1; then
    if git -C "$CANON" push -q origin "$main" 2>/dev/null; then say "pushed $main"
    else owe "push of $main was refused: git -C \"$CANON\" pull --rebase && git -C \"$CANON\" push origin $main"; fi
  fi
else
  if git -C "$WORK" push -q -u origin "$BRANCH" 2>/dev/null; then say "pushed $BRANCH"
  else owe "push of $BRANCH failed: git -C \"$WORK\" push -u origin $BRANCH"; fi
  pr=""; state=""; create_err=""
  if command -v gh >/dev/null 2>&1; then
    # Only the pull request whose head is THIS branch tip counts. A session reuses its branch
    # name (wt/<session>) for every landing, so `--state all` also lists earlier, merged pull
    # requests for that name; taking the first one declared a new commit landed that never
    # reached main. `--state all` stays so a rerun after the operator merges is recognised.
    # `// empty`: no match must print nothing, not "null null", or the create below is skipped.
    tip="$(git -C "$WORK" rev-parse HEAD)"
    pr="$(cd "$WORK" && gh pr list --head "$BRANCH" --state all --json number,state,headRefOid \
          -q "map(select(.headRefOid == \"$tip\")) | .[0] // empty | \"\\(.number) \\(.state)\"" 2>/dev/null)"
    state="${pr#* }"; pr="${pr%% *}"
    if [ -z "$pr" ]; then
      subj="$(git -C "$WORK" log -1 --format=%s)"
      created="$(cd "$WORK" && gh pr create --head "$BRANCH" --title "$subj" --body "Session branch $BRANCH, landed by distill-finish.sh." 2>&1)" || true
      pr="$(sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p' <<<"$created" | head -1)"
      state="OPEN"
      [ -n "$pr" ] || create_err="$(tail -1 <<<"$created")"
    fi
  fi
  if [ "$state" = "MERGED" ]; then
    git -C "$CANON" pull -q --ff-only 2>/dev/null && landed=1 && say "pull request #$pr is merged; $main fast-forwarded"
    [ "$landed" = 1 ] || owe "#$pr is merged but $main did not fast-forward: git -C \"$CANON\" pull --ff-only"
  elif [ -n "$pr" ]; then
    owe "pull request #$pr is not merged: merge it, then rerun distill-finish.sh"
  else
    if command -v gh >/dev/null 2>&1; then owe "opening the pull request for $BRANCH failed (${create_err:-no output from gh}): open it by hand, merge it, then rerun"
    else owe "no pull request for $BRANCH: gh is not installed — open one, merge it, then rerun"; fi
  fi
fi

# --- 4. recall index --------------------------------------------------------------------
if [ "$landed" = 1 ] && [ -f "$CANON/.rag/index.jsonl" ]; then
  if "$SCRIPT_DIR/rag-build.sh" >/dev/null 2>&1; then say "recall index rebuilt"
  else say "recall index rebuild failed (optional; recall is a derived lens) — run rag-build.sh to see why"; fi
fi

# --- 5. age out the capture buffer --------------------------------------------------------
CAP_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/wiki-engine/capture"
now_month="$(date +%Y-%m)"
cutoff="$(date -v-"${WINDOW_DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "-${WINDOW_DAYS} days" +%Y-%m-%d 2>/dev/null)"   # BSD, then GNU
for f in "$CANON"/raw/sessions/[0-9][0-9][0-9][0-9]-[0-9][0-9].md; do
  [ -f "$f" ] || continue
  [ "$(basename "$f" .md)" = "$now_month" ] && continue
  newest="$(sed -n 's/^## \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p' "$f" | sort | tail -1)"
  [ -n "$newest" ] || newest="$(basename "$f" .md)-31"
  [ -n "$cutoff" ] && [ "$newest" \< "$cutoff" ] || continue
  lock="$CAP_STATE/lock-$(printf '%s' "$f" | cksum | cut -d' ' -f1)"
  mkdir -p "$CAP_STATE"
  if mkdir "$lock" 2>/dev/null; then
    rm -f "$f"; rmdir "$lock"
    say "aged out $(basename "$f") (newest block $newest, older than $WINDOW_DAYS days)"
  else
    say "left $(basename "$f") — its capture lock is held; the next distill retries"
  fi
done

# --- 6. retire this session's worktree ----------------------------------------------------
if [ "$landed" = 1 ] && [ "$WORK" != "$CANON" ]; then
  if ( cd "$CANON" && "$SCRIPT_DIR/vault-worktree.sh" gc "$WORK" ) >/dev/null 2>&1 && [ ! -d "$WORK" ]; then
    say "retired worktree $WORK"
  else
    owe "worktree $WORK is still there: (cd \"$CANON\" && vault-worktree.sh gc \"$WORK\")"
  fi
fi

# --- 7. close check: repositories the session says it touched -----------------------------
for r in ${REPOS[@]+"${REPOS[@]}"}; do
  [ -d "$r/.git" ] || [ -f "$r/.git" ] || { printf 'REVIEW %s: not a git checkout\n' "$r"; continue; }
  n="$(git -C "$r" status --porcelain | wc -l | tr -d ' ')"
  [ "$n" = 0 ] || printf 'REVIEW %s: %s uncommitted path(s) — yours? commit or discard; a peer'"'"'s? leave it\n' "$r" "$n"
  git -C "$r" for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:track)' refs/heads | while read -r b up track; do
    case "$track" in *ahead*) printf 'REVIEW %s: branch %s is %s %s — push it if it is yours\n' "$r" "$b" "$track" "$up";; esac
    if [ -z "$up" ]; then
      def="$(git -C "$r" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
      [ -n "$def" ] && [ "$(git -C "$r" rev-list --count "$def..$b" 2>/dev/null || echo 0)" != 0 ] \
        && printf 'REVIEW %s: branch %s has commits not on %s and no upstream\n' "$r" "$b" "$def"
    fi
  done
  git -C "$r" worktree list --porcelain | awk -v main="$(cd "$r" && pwd -P)" '/^worktree /{p=substr($0,10)} /^branch /{if (p!=main) print p " " substr($0,8)}' \
    | while read -r p b; do printf 'REVIEW %s: extra worktree %s (%s) — remove it if it is yours\n' "$r" "$p" "${b#refs/heads/}"; done
  if command -v gh >/dev/null 2>&1; then
    (cd "$r" && gh pr list --author @me --state open --json number,headRefName -q '.[] | "\(.number) \(.headRefName)"' 2>/dev/null) \
      | while read -r num head; do printf 'REVIEW %s: open pull request #%s (%s) — merge it if it is yours\n' "$r" "$num" "$head"; done
  fi
done

if [ "${#OUT[@]}" -eq 0 ]; then
  echo "VAULT DONE — $([ "$ahead" = 0 ] && echo "nothing new to land" || echo "$ahead commit(s) landed by the $route route")"
  exit 0
fi
echo "VAULT OUTSTANDING — ${#OUT[@]} item(s):"
for o in "${OUT[@]}"; do printf '  - %s\n' "$o"; done
exit 1
