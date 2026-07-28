#!/usr/bin/env bash
#
# engine-proposal.sh — deterministic boundary gate + transient outbox for the
# `engine-proposal` skill.
#
# The skill (an LLM session) genericizes a consumer vault's engine-improvement
# idea and drafts a kickoff block for the engine-dev vault. This script does the
# one part that must be mechanical rather than trusted to a model: it SCANS the
# drafted block for consumer-private leakage relative to the consumer vault and
# fails closed if it finds any — so a scrub the model believed was clean can
# never silently ship an identifier, path, email, or secret upstream.
#
# It deliberately does NOT generate the block (genericizing prose is a judgement
# task, not a transform) and never creates a curated node. Its whole job is the
# fail-closed gate plus an optional git-ignored scratch copy for traceability.
#
# Subcommands:
#   scan   --vault DIR [--file F]   block on stdin (or F) -> findings; exit 1 if any leak
#   stash  --vault DIR --slug ID    block on stdin -> $VAULT/.engine-proposal/ID.outbox (git-ignored)
#   status --vault DIR [--slug ID]  what happened to a proposal, read from the engine checkout
#
# `status` closes the round trip. A handoff is forward-only, so the engine has no way to
# tell a reporter anything — the shared surface is the engine repository itself, and that
# is what this reads: PROPOSALS.md for the outcome, the `Proposal:` commit trailers plus
# `git tag --contains` for the release. Nothing is stored on the consumer side, because
# hand-maintained status drifts and a derived answer cannot.
#
# It resolves against `origin/main` when the submodule has it (update.sh fetches), NOT the
# detached pin — otherwise a proposal that shipped after your pin reads as still open. It
# prints the horizon it resolved against, so "no record" is never confused with "your refs
# are stale". No network: it reads only what the checkout already has.
#
# `scan` derives the consumer's OWN identifiers from the vault (git remote slug,
# directory name, git user name/email) and flags any literal appearance in the
# block, plus universal private-shaped patterns (home paths, emails, a non-generic
# `boundary:` tag, secret assignments). A clean block exits 0. The scan is a
# backstop for the skill's genericization, not a replacement — it can only catch
# identifiers it can derive, so the skill still owns the actual scrub.
#
# Usage:
#   engine-proposal.sh scan   --vault DIR [--file draft.md]   < block
#   engine-proposal.sh stash  --vault DIR --slug my-idea       < block
#   engine-proposal.sh status --vault DIR [--slug my-idea]

set -uo pipefail

die() { printf 'engine-proposal: %s\n' "$*" >&2; exit 1; }

CMD="${1:-}"; shift || true
VAULT=""; FILE=""; SLUG=""
while (( $# )); do
  case "$1" in
    --vault) VAULT="${2:-}"; shift 2 ;;
    --file)  FILE="${2:-}"; shift 2 ;;
    --slug)  SLUG="${2:-}"; shift 2 ;;
    -*) die "unknown flag: $1" ;;
    *)  die "unexpected argument: $1" ;;
  esac
done
[[ -n "$VAULT" ]] || die "--vault is required"
[[ -d "$VAULT" ]] || die "vault not found: $VAULT"
VAULT="$(cd "$VAULT" && pwd)"

read_input() {
  if [[ -n "$FILE" ]]; then
    [[ -f "$FILE" ]] || die "no such file: $FILE"
    cat "$FILE"
  else
    cat
  fi
}

# ============================================================ scan ============
do_scan() {
  local block; block="$(read_input)"
  [[ -n "$block" ]] || die "empty input — nothing to scan"

  # --- derive the consumer's own identifiers from the vault ------------------
  local -a needles=()
  local slug org repo base gname gemail
  base="$(basename "$VAULT")"
  needles+=("$base")
  slug="$(git -C "$VAULT" remote get-url origin 2>/dev/null \
          | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')"
  if [[ -n "$slug" && "$slug" == */* ]]; then
    org="${slug%%/*}"; repo="${slug##*/}"
    needles+=("$slug" "$org" "$repo")
  fi
  gname="$(git -C "$VAULT" config user.name  2>/dev/null || true)"
  gemail="$(git -C "$VAULT" config user.email 2>/dev/null || true)"
  needles+=("$gname" "$gemail")

  # de-dup; drop empties and needles too short to be a meaningful identifier
  # (a 1-2 char token would flood the report with noise)
  local -a uniq=(); local n seen
  for n in "${needles[@]}"; do
    [[ -n "$n" ]] || continue
    [[ ${#n} -ge 3 ]] || continue
    seen=0; local u
    for u in "${uniq[@]:-}"; do [[ "$u" == "$n" ]] && { seen=1; break; }; done
    [[ $seen -eq 0 ]] && uniq+=("$n")
  done

  local findings=0
  printf 'engine-proposal: scanning block against consumer vault "%s"\n' "${slug:-$base}"

  # report grep "N:text" hits under a category label; truncate long lines
  report() {
    local label="$1" line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf '  [%s] line %s: %s\n' "$label" "${line%%:*}" "$(printf '%s' "${line#*:}" | cut -c1-100)"
      findings=$((findings+1))
    done
  }

  # 1. literal consumer identifiers
  for n in "${uniq[@]:-}"; do
    [[ -n "$n" ]] || continue
    report "consumer-id:$n" < <(printf '%s\n' "$block" | grep -nF -- "$n" || true)
  done
  # 2. absolute home paths (any user)
  report "home-path" < <(printf '%s\n' "$block" | grep -nE '/(Users|home)/[A-Za-z0-9._-]+' || true)
  # 3. email addresses
  report "email" < <(printf '%s\n' "$block" | grep -nE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' || true)
  # 4. a leaked non-generic boundary tag (frontmatter-style key only)
  report "non-generic-boundary" < <(printf '%s\n' "$block" \
    | grep -nE '^[[:space:]]*boundary:[[:space:]]*' | grep -viE 'boundary:[[:space:]]*generic\b' || true)
  # 5. secret assignments / literal key material (same shape crossover blocks)
  report "secret" < <(printf '%s\n' "$block" | grep -nEi \
    -e '(api[_-]?key|client[_-]?secret|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'BEGIN [A-Z ]*PRIVATE KEY' || true)

  if [[ $findings -eq 0 ]]; then
    printf 'engine-proposal: scan clean — no consumer identifiers, home paths, emails, non-generic boundary tags, or secrets found. Block is boundary-safe to hand off.\n'
    return 0
  fi
  printf 'engine-proposal: %d potential leak(s) above — REVISE (genericize/scrub) and re-scan; do NOT hand off until clean.\n' "$findings"
  return 1
}

# ============================================================ stash ===========
do_stash() {
  [[ -n "$SLUG" ]] || die "--slug is required for stash"
  [[ "$SLUG" =~ ^[A-Za-z0-9._-]+$ ]] || die "slug must be [A-Za-z0-9._-]: $SLUG"
  local block; block="$(read_input)"
  [[ -n "$block" ]] || die "empty input — nothing to stash"

  # The filename is what `status` keys off, and the block's own `slug:` is what the engine
  # ledger will carry. If they diverge, every later lookup silently asks about the wrong
  # proposal — so reject it here rather than at the far end, where nobody can see both.
  local inblock
  inblock="$(printf '%s\n' "$block" | grep -m1 -E '^slug:[[:space:]]*' | sed -E 's/^slug:[[:space:]]*//; s/[[:space:]]+$//')"
  if [[ -n "$inblock" && "$inblock" != "$SLUG" ]]; then
    die "--slug '$SLUG' does not match the block's 'slug: $inblock' — the slug is the only correlation key; make them identical"
  fi

  local dir="$VAULT/.engine-proposal"
  mkdir -p "$dir"
  # self-heal: keep the transient outbox out of git even on an existing vault
  local gi="$VAULT/.gitignore"
  if [[ -f "$gi" ]] && ! grep -qxF '.engine-proposal/' "$gi"; then
    printf '\n# Transient engine-proposal outbox (scratch, not a vault node)\n.engine-proposal/\n' >> "$gi"
  fi
  local out="$dir/$SLUG.outbox"
  printf '%s\n' "$block" > "$out"
  printf 'engine-proposal: stashed kickoff block to %s (transient, git-ignored — not a vault node).\n' \
    ".engine-proposal/$SLUG.outbox"
}

# ============================================================ status ==========
do_status() {
  local engine="$VAULT/engine"
  [[ -d "$engine" ]] || die "no engine at $engine — status reads the engine checkout"
  git -C "$engine" rev-parse --git-dir >/dev/null 2>&1 || die "engine at $engine is not a git checkout"

  # Resolve against fetched history, not the detached pin: a proposal that shipped in a
  # release NEWER than this vault's pin is invisible from the worktree, and reading it as
  # "open" is the exact failure this subcommand exists to remove.
  local ref horizon pinned
  if git -C "$engine" rev-parse -q --verify origin/main >/dev/null 2>&1; then ref="origin/main"; else ref="HEAD"; fi
  horizon="$(git -C "$engine" describe --tags --always "$ref" 2>/dev/null || echo "$ref")"
  pinned="$(git -C "$engine" describe --tags --always HEAD 2>/dev/null || echo "?")"

  # ledger, read at the resolution ref (falls back to the worktree on an old ref)
  local ledger
  ledger="$(git -C "$engine" show "$ref:PROPOSALS.md" 2>/dev/null || true)"
  [[ -n "$ledger" ]] || ledger="$(cat "$engine/PROPOSALS.md" 2>/dev/null || true)"

  local -a l_slug=() l_out=() l_det=()
  if [[ -n "$ledger" ]]; then
    local row
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      IFS='|' read -r -a f <<<"$row"
      [[ ${#f[@]} -eq 4 ]] || continue
      local s o d
      s="$(printf '%s' "${f[1]}" | tr -d ' `')"
      o="$(printf '%s' "${f[2]}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      d="$(printf '%s' "${f[3]}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^`//; s/`$//')"
      [[ -n "$s" ]] || continue
      l_slug+=("$s"); l_out+=("$o"); l_det+=("$d")
    done < <(printf '%s\n' "$ledger" | awk '
      /^## Ledger[[:space:]]*$/ { inl=1; next } /^## / { inl=0 }
      inl && /^\|/ { if ($0 ~ /^\|[[:space:]]*slug[[:space:]]*\|/) next; if ($0 ~ /^\|[[:space:]]*-+/) next; print }')
  fi

  ledger_find() {
    local w="$1" i
    [[ ${#l_slug[@]} -gt 0 ]] || return 1
    for i in "${!l_slug[@]}"; do [[ "${l_slug[$i]}" == "$w" ]] && { printf '%s' "$i"; return 0; }; done
    return 1
  }

  # slugs to report -----------------------------------------------------------
  local -a want=(); local -a src=()
  if [[ -n "$SLUG" ]]; then
    want+=("$SLUG"); src+=("--slug")
  else
    local ob
    for ob in "$VAULT"/.engine-proposal/*.outbox; do
      [[ -e "$ob" ]] || continue
      local base inb
      base="$(basename "$ob" .outbox)"
      inb="$(grep -m1 -E '^slug:[[:space:]]*' "$ob" 2>/dev/null | sed -E 's/^slug:[[:space:]]*//; s/[[:space:]]+$//')"
      want+=("${inb:-$base}"); src+=("$base.outbox")
    done
  fi

  printf 'engine-proposal: resolving against %s (%s); this vault is pinned at %s\n' "$ref" "$horizon" "$pinned"
  if [[ ${#want[@]} -eq 0 ]]; then
    # an empty outbox is NOT "nothing outstanding" — the outbox is git-ignored and
    # per-machine, so say what was actually scanned rather than implying a clean slate.
    printf '\n  no handoff blocks stashed on THIS machine (%s).\n' ".engine-proposal/"
    printf '  The outbox is git-ignored and per-machine, so this is not evidence that nothing is\n'
    printf '  outstanding. Query a specific proposal with: engine-proposal.sh status --vault DIR --slug ID\n'
    return 0
  fi

  local i
  for i in "${!want[@]}"; do
    # separate declarations: `local a=x b=$a` expands $a before the builtin assigns it
    local slug="${want[$i]}"
    local canon="$slug"
    local idx note=""
    printf '\n  %s  (%s)\n' "$slug" "${src[$i]}"

    if idx="$(ledger_find "$canon")" && [[ "${l_out[$idx]}" == "alias" ]]; then
      note="    (recorded upstream under '${l_det[$idx]}' — intake renamed it)"
      canon="${l_det[$idx]}"
    fi
    if ! idx="$(ledger_find "$canon")"; then
      # NOT in the engine's ledger. Three different situations used to collapse into one
      # "unknown", which told the reporter to re-send even when a submission was already
      # open. They are distinguishable from LOCAL evidence alone — no network, which
      # matters because `status` is offline by design and resolves against origin/main
      # only when something already fetched it.
      local pmark="$VAULT/.engine-proposal/$canon.prepared"
      local smark="$VAULT/.engine-proposal/$canon.submitted"
      if [[ -f "$smark" ]]; then
        printf '    SUBMITTED, not yet merged — branch %s was pushed from this machine.\n' "$(cat "$smark")"
        printf '    Do NOT re-send; the pull request is the record. It becomes "open" here once merged.\n'
      elif [[ -f "$pmark" ]]; then
        printf '    WRITTEN LOCALLY, never submitted — prepared on branch %s, still unpushed.\n' "$(cat "$pmark")"
        printf '    Nothing has reached the engine and nothing is public yet. Run `push` to submit.\n'
      else
        printf '    unknown — no row in the engine ledger at %s, and nothing prepared here.\n' "$horizon"
        printf '    The engine has no record of receiving this. Re-sending is the right move.\n'
      fi
      # The markers are per-machine: a proposal submitted from ANOTHER machine has no
      # marker here and reads as unknown. Say so rather than let the silence imply
      # "nothing outstanding" — the same trap the empty-outbox message already warns about.
      [[ -f "$smark" || -f "$pmark" ]] || printf '    (local markers are per-machine; a submission from another machine leaves none here)\n'
      [[ "$ref" == "HEAD" ]] && printf '    (resolved against the pin only — no origin/main fetched; run update.sh first)\n'
      continue
    fi
    [[ -n "$note" ]] && printf '%s\n' "$note"

    case "${l_out[$idx]}" in
      open)
        printf '    open — received and recorded upstream (%s). Do not re-send.\n' "${l_det[$idx]}" ;;
      rejected)
        printf '    REJECTED — %s\n' "${l_det[$idx]}" ;;
      partially-accepted)
        printf '    partially accepted — %s\n' "${l_det[$idx]}" ;;
      shipped)
        local rel=""
        if [[ "${l_det[$idx]}" != "derived" ]]; then
          rel="${l_det[$idx]}"
        else
          local sha
          # Match the LITERAL `Proposal:` line anywhere in the message, not git's trailer
          # parser. GitHub appends a `---------` + `Co-authored-by:` footer to a squash
          # body, which displaces the slug out of the final paragraph and makes
          # %(trailers) return nothing — so a shipped proposal read as never-shipped.
          # Fenced/indented lines are skipped so a quoted example is not mistaken for a
          # citation. Kept in step with bin/lint-proposals.sh, which decides the same thing.
          sha="$(git -C "$engine" log "$ref" --format='%H%x1f%B%x1e' 2>/dev/null \
                 | awk -v RS=$'\x1e' -v FS=$'\x1f' -v s="$canon" '
                     {
                       h = $1; sub(/^\n+/, "", h)
                       n = split($2, L, "\n"); fence = 0
                       for (i = 1; i <= n; i++) {
                         if (L[i] ~ /^[[:space:]]*```/) { fence = !fence; continue }
                         if (fence) continue
                         if (L[i] ~ ("^Proposal:[[:space:]]*" s "[[:space:]]*$")) { print h; exit }
                       }
                     }')"
          if [[ -n "$sha" ]]; then
            rel="$(git -C "$engine" tag --contains "$sha" 2>/dev/null | grep -E '^v[0-9]' | sort -V | head -1)"
            if [[ -z "$rel" ]]; then
              printf '    merged, not yet released — %s is on %s but carries no version tag.\n' "${sha:0:9}" "$ref"
              printf '    It will arrive in the next release.\n'
              continue
            fi
          fi
        fi
        if [[ -z "$rel" ]]; then
          printf '    shipped upstream, but no release could be resolved from %s.\n' "$horizon"
          continue
        fi
        # `pinned` is a `git describe`, so it may read v1.33.0-3-gabc1234 on a vault whose
        # submodule sits past a tag; sort -V still orders that after the bare tag, which is
        # the answer we want. A pin we cannot parse gets no have-it/need-it claim at all.
        if [[ ! "$pinned" =~ ^v[0-9] ]]; then
          printf '    SHIPPED in %s (could not read this vault'\''s pin to compare).\n' "$rel"
        elif [[ "$(printf '%s\n%s\n' "$rel" "$pinned" | sort -V | tail -1)" == "$pinned" ]]; then
          printf '    SHIPPED in %s — you already have it (pinned %s). Safe to drop the block.\n' "$rel" "$pinned"
        else
          printf '    SHIPPED in %s — NEWER than your pin (%s). Run update.sh to get it.\n' "$rel" "$pinned"
        fi ;;
      *)
        printf '    unrecognised outcome "%s" — the ledger is newer than this tool; update the engine.\n' "${l_out[$idx]}" ;;
    esac
  done
  printf '\n'
  return 0
}


# --- submit / push -------------------------------------------------------------
# The proposal channel becomes files in the engine's `proposals/` queue, submitted by PR.
# SPLIT DELIBERATELY INTO TWO VERBS, and this is the safety-critical decision in the whole
# design: `submit` prepares locally and stops; `push` performs the irreversible act.
#
# WHY NOT ONE VERB. The engine repository is PUBLIC, so a committed proposal and its pull
# request are permanently public — a leak is a git object that force-push cannot reliably
# retract once forks, clones and cached views exist. The boundary scan is fail-closed and
# runs first, but it only matches identifiers it can DERIVE from the vault (slug, git
# identity, home paths). It cannot see SEMANTIC leakage: a private workflow described in
# generic-sounding prose passes every pattern and still discloses. Under the old
# copy-paste channel a human necessarily read the text at the moment of publication — the
# only review of *meaning* anywhere in the chain. Collapsing prepare and push into one
# unattended verb would delete that review while claiming to improve safety.
#
# There is NO --force on the scan. Whatever it would mean, the failure it enables is
# unrecoverable; an override worth having would require the scan to have run and PASSED on
# a prior revision, not to be skipped.
ENGINE_REPO="${ENGINE_REPO:-}"

engine_repo_path() {
  [[ -n "$ENGINE_REPO" ]] && { printf '%s' "$ENGINE_REPO"; return; }
  # the vault's pinned submodule is the engine checkout every consumer already has
  printf '%s' "$VAULT/engine"
}

submit_marker_dir() { printf '%s' "$VAULT/.engine-proposal"; }

do_submit() {
  local block; block="$(read_input)"
  [[ -n "$block" ]] || die "empty input — nothing to submit"
  [[ -n "${SLUG:-}" ]] || die "--slug is required: it is the correlation key and the filename"

  # FAIL-CLOSED, FIRST. Nothing is branched, committed or written on this path if the
  # scan finds anything.
  if ! printf '%s\n' "$block" | do_scan; then
    die "boundary scan FAILED — nothing prepared. Fix the block and re-run; there is no bypass."
  fi

  local eng; eng="$(engine_repo_path)"
  [[ -d "$eng/.git" ]] || die "no engine checkout at $eng (set ENGINE_REPO to a clone you can branch in)"

  local br="proposal/$SLUG"
  git -C "$eng" rev-parse --verify "$br" >/dev/null 2>&1 \
    && die "branch $br already exists in $eng — a proposal is already prepared; push it or delete the branch"

  local base; base="$(git -C "$eng" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  git -C "$eng" checkout -q -b "$br" || die "could not create $br"
  mkdir -p "$eng/proposals"
  local f="$eng/proposals/$SLUG.md"
  {
    printf -- '---\nslug: %s\noutcome: open\nreceived: %s\n---\n\n' "$SLUG" "$(date +%Y-%m-%d)"
    printf '%s\n' "$block"
  } > "$f"
  git -C "$eng" add "proposals/$SLUG.md"
  git -C "$eng" -c core.hooksPath=/dev/null commit -q -m "proposal: $SLUG" \
    || { git -C "$eng" checkout -q "$base"; die "commit failed"; }

  mkdir -p "$(submit_marker_dir)"
  printf '%s\n' "$br" > "$(submit_marker_dir)/$SLUG.prepared"

  cat <<EOF

engine-proposal: PREPARED on branch $br in $eng
  scan: clean (fail-closed; it ran before anything was written)

  ┌─ THIS TEXT BECOMES PERMANENTLY PUBLIC WHEN YOU PUSH ────────────────────────
$(sed 's/^/  │ /' "$f")
  └─────────────────────────────────────────────────────────────────────────────

  The scan matches identifiers it can derive from this vault. It CANNOT judge whether
  the prose itself discloses something private. Read the block above as the reviewer,
  because after the push there is no retraction that works.

  To publish:  engine-proposal.sh push --vault "$VAULT" --slug $SLUG
  To discard:  git -C "$eng" checkout $base && git -C "$eng" branch -D $br
EOF
}

do_push() {
  [[ -n "${SLUG:-}" ]] || die "--slug is required"
  local eng; eng="$(engine_repo_path)"
  local marker="$(submit_marker_dir)/$SLUG.prepared"
  [[ -f "$marker" ]] || die "nothing prepared for '$SLUG' — run submit first (it scans; push does not)"
  local br; br="$(cat "$marker")"
  git -C "$eng" rev-parse --verify "$br" >/dev/null 2>&1 || die "branch $br is gone — re-run submit"

  command -v gh >/dev/null 2>&1 || die "gh CLI not found — needed to open the pull request"

  # No write access is assumed: gh forks on demand. The fork is PUBLIC too, which the
  # consumer is told rather than left to discover.
  echo "engine-proposal: pushing $br and opening a pull request (forking if you lack write access)."
  echo "  Note: if a fork is created it is public, like the upstream repository."
  if ! gh pr create --repo "$(git -C "$eng" remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')" \
        --head "$br" --title "proposal: $SLUG" --body-file "$eng/proposals/$SLUG.md" 2>&1; then
    die "pull request failed — the branch is still local at $br, nothing was published"
  fi
  printf '%s\n' "$br" > "$(submit_marker_dir)/$SLUG.submitted"
  rm -f "$marker"
  echo "engine-proposal: submitted. status will now report it as submitted-pending until merged."
}

case "$CMD" in
  scan)   do_scan ;;
  stash)  do_stash ;;
  submit) do_submit ;;
  push)   do_push ;;
  status) do_status ;;
  *) die "usage: engine-proposal.sh {scan|stash|submit|push|status} --vault DIR [...]  (got '${CMD:-}')" ;;
esac
