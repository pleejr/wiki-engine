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
VAULT=""; FILE=""; SLUG=""; REPO_ARG=""; QUEUE_ALL=0
while (( $# )); do
  case "$1" in
    --vault) VAULT="${2:-}"; shift 2 ;;
    --repo)  REPO_ARG="${2:-}"; shift 2 ;;
    --all)   QUEUE_ALL=1; shift ;;
    --file)  FILE="${2:-}"; shift 2 ;;
    --slug)  SLUG="${2:-}"; shift 2 ;;
    -*) die "unknown flag: $1" ;;
    *)  die "unexpected argument: $1" ;;
  esac
done
# `queue` is the ENGINE-DEV verb and runs in the engine repo, not a consumer vault, so it
# is the one subcommand that must not demand --vault. Requiring it would have made the
# work-list unusable from the only place it is meant to be used.
if [[ "${CMD:-}" != "queue" ]]; then
  [[ -n "$VAULT" ]] || die "--vault is required"
  [[ -d "$VAULT" ]] || die "vault not found: $VAULT"
  VAULT="$(cd "$VAULT" && pwd)"
fi

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
  # RETIRED as of v1.46.0 — the copy-paste channel it served is no longer the way
  # proposals travel. `submit` + `push` put the block in the engine's queue as a committed
  # file, so the durability `stash` provided (a forward-only handoff cannot be re-sent if
  # the block was not kept) is now the transport's own property.
  #
  # The verb still WORKS, deliberately: deleting a documented subcommand from a consumed
  # component is a breaking change, and this engine reserves that for a MAJOR with a
  # reviewed migration. It warns instead, and nothing teaches it any more.
  cat >&2 <<'DEPRECATED'
engine-proposal: `stash` is RETIRED — proposals now travel as files in the engine's queue.
  Use:  engine-proposal.sh submit --vault DIR --slug ID   (scans, prepares, prints)
        engine-proposal.sh push   --vault DIR --slug ID   (publishes)
  A stashed block is invisible to the engine: nothing observes a git-ignored, per-machine
  outbox, so "sent" and "never arrived" look identical from here. Writing it anyway.
DEPRECATED

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
    # EVERY local record, not just the retired one. This globbed `*.outbox` alone — the
    # LEGACY copy-paste artifact, which the supported path no longer produces — so the bare
    # listing enumerated exactly the artifact class that had been retired and ignored the
    # markers `submit`/`push` write. Fail-open: it returned a confident, well-formed "no
    # proposals" while six submitted markers sat beside it, which is the duplicate-resend
    # trap this subcommand exists to prevent. The printed caveat explained the outbox's
    # per-machine limitation and so read as "the outbox is empty", pointing away from the
    # cause. The documented contract already promised markers were included; the code and
    # the doc disagreed, and the doc was right.
    #
    # Deduplicated by slug: a proposal normally leaves a marker at prepare and another at
    # push, and reporting it twice would make the listing look like two proposals.
    local ob base inb seen w
    for ob in "$VAULT"/.engine-proposal/*.outbox "$VAULT"/.engine-proposal/*.submitted "$VAULT"/.engine-proposal/*.prepared; do
      [[ -e "$ob" ]] || continue
      base="$(basename "$ob")"; base="${base%.*}"
      inb=""
      # only an outbox block carries the block itself, and thus a `slug:` line to prefer
      case "$ob" in
        *.outbox) inb="$(grep -m1 -E '^slug:[[:space:]]*' "$ob" 2>/dev/null | sed -E 's/^slug:[[:space:]]*//; s/[[:space:]]+$//')" ;;
      esac
      w="${inb:-$base}"
      seen=0
      for i in "${want[@]:-}"; do [[ "$i" == "$w" ]] && { seen=1; break; }; done
      [[ $seen -eq 1 ]] && continue
      want+=("$w"); src+=("$(basename "$ob")")
    done
  fi

  printf 'engine-proposal: resolving against %s (%s); this vault is pinned at %s\n' "$ref" "$horizon" "$pinned"
  if [[ ${#want[@]} -eq 0 ]]; then
    # an empty result is NOT "nothing outstanding" — these records are git-ignored and
    # per-machine, so say what was actually scanned rather than implying a clean slate.
    printf '\n  no local record on THIS machine (%s) — no submitted or prepared markers, and no legacy outbox blocks.\n' ".engine-proposal/"
    printf '  These records are git-ignored and per-machine, so this is not evidence that nothing is\n'
    printf '  outstanding: a proposal submitted from another machine leaves none here.\n'
    printf '  Query a specific proposal with: engine-proposal.sh status --vault DIR --slug ID\n'
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
        printf '    SUBMITTED, not yet merged — branch %s was pushed from this machine.\n' "$(marker_branch "$smark")"
        printf '    Do NOT re-send; the pull request is the record. It becomes "open" here once merged.\n'
      elif [[ -f "$pmark" ]]; then
        printf '    WRITTEN LOCALLY, never submitted — prepared on branch %s, still unpushed.\n' "$(marker_branch "$pmark")"
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

# The property `submit` actually needs is "a git work tree I can branch in" — NOT "`.git` is
# a directory". In a submodule `.git` is a FILE holding a `gitdir:` pointer, so the directory
# test was false for exactly the default path the resolver above chooses: the guard rejected
# the one checkout every consumer has. Reported as fail-closed, but its printed remedy sent
# consumers to a separate clone they do not have, and the natural next move — editing the
# pinned submodule in place — is the time bomb the skill exists to warn against.
engine_is_checkout() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }

submit_marker_dir() { printf '%s' "$VAULT/.engine-proposal"; }

# line 1 = branch, line 2 = the engine checkout it lives in. `push` used to re-derive the
# checkout from the environment, so a submission prepared with ENGINE_REPO set failed at push
# time if the variable was not still exported — and the `To publish:` line submit printed
# omitted it. Recording the path removes the dependency instead of documenting it.
marker_branch() { head -1 "$1"; }
marker_engine() { sed -n '2p' "$1"; }

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
  engine_is_checkout "$eng" || die "no engine checkout at $eng (set ENGINE_REPO to a clone you can branch in)"

  local br="proposal/$SLUG"
  git -C "$eng" rev-parse --verify "$br" >/dev/null 2>&1 \
    && die "branch $br already exists in $eng — a proposal is already prepared; push it or delete the branch"

  # Branch from MAIN, never from wherever HEAD happens to sit. `submit` leaves its own
  # branch checked out, so a second proposal cut from HEAD lands on the first one's branch
  # and its pull request carries BOTH files. Reported on the second submission ever made
  # through this channel; the first could not expose it, because the bug needs a prior
  # proposal branch to still be checked out.
  #
  # Prefer origin/main when it exists: the local main may itself be behind, and a proposal
  # based on stale main is a needless rebase for whoever intakes it.
  local base="main"
  git -C "$eng" rev-parse --verify -q main >/dev/null 2>&1 || base="$(git -C "$eng" symbolic-ref --short HEAD 2>/dev/null || echo main)"
  local start="$base"
  git -C "$eng" rev-parse --verify -q "origin/$base" >/dev/null 2>&1 && start="origin/$base"

  # Where the checkout sat before we touched it — a branch name in a clone, a detached sha
  # in a submodule. It is restored below, because in the submodule case the checkout IS the
  # vault's PINNED engine: leaving it parked on a branch cut from origin/main would silently
  # swap the version every skill, hook and lint in that vault runs at, and the vault would
  # read as having an unexpected submodule pointer. The branch survives as a ref either way;
  # nothing about push needs it checked out.
  local orig; orig="$(git -C "$eng" symbolic-ref -q --short HEAD 2>/dev/null || git -C "$eng" rev-parse HEAD 2>/dev/null || true)"

  git -C "$eng" checkout -q -b "$br" "$start" \
    || die "could not create $br from $start in $eng — if that checkout has uncommitted changes, commit or discard them first; nothing was written"
  mkdir -p "$eng/proposals"
  local f="$eng/proposals/$SLUG.md"
  {
    printf -- '---\nslug: %s\noutcome: open\nreceived: %s\n---\n\n' "$SLUG" "$(date +%Y-%m-%d)"
    printf '%s\n' "$block"
  } > "$f"
  git -C "$eng" add "proposals/$SLUG.md"

  # PROPOSALS.md is DERIVED from proposals/, so adding a queue file without regenerating it
  # leaves the committed ledger stale — and the drift gate then fails the reporter's own pull
  # request, for a step nothing had told them to run. Intake was doing this by hand on every
  # arriving proposal. The generator is deterministic and adds only the new `open` row.
  local gen="$eng/bin/gen-proposals-ledger.sh"
  if [[ -x "$gen" ]]; then
    if "$gen" --repo "$eng" >/dev/null 2>&1; then
      git -C "$eng" add PROPOSALS.md 2>/dev/null || true
    else
      echo "engine-proposal: WARNING — could not regenerate PROPOSALS.md; the drift gate will fail this pull request until intake regenerates it." >&2
    fi
  else
    echo "engine-proposal: WARNING — no gen-proposals-ledger.sh in $eng; the committed ledger will be stale for this proposal." >&2
  fi

  git -C "$eng" -c core.hooksPath=/dev/null commit -q -m "proposal: $SLUG" \
    || { git -C "$eng" checkout -q "$base"; die "commit failed"; }

  # Capture the block BEFORE restoring the checkout: the preview below is the only review of
  # MEANING anywhere in the chain, and reading it from the working tree after the restore
  # printed an empty box — a safety surface that fails silently is worse than none.
  local shown; shown="$(git -C "$eng" show "$br:proposals/$SLUG.md")"

  local restored=1
  if [[ -n "$orig" ]]; then
    if git -C "$eng" rev-parse --verify -q "refs/heads/$orig" >/dev/null 2>&1; then
      git -C "$eng" checkout -q "$orig" 2>/dev/null && restored=0   # a branch restores as a branch
    else
      git -C "$eng" checkout -q --detach "$orig" 2>/dev/null && restored=0
    fi
  fi

  mkdir -p "$(submit_marker_dir)"
  printf '%s\n%s\n' "$br" "$eng" > "$(submit_marker_dir)/$SLUG.prepared"

  local where
  if [[ $restored -eq 0 ]]; then
    where="  $eng is back on $orig — the branch is a ref there; push does not need it checked out."
  else
    where="  $eng is left on $br (its previous HEAD could not be restored)."
  fi

  cat <<EOF

engine-proposal: PREPARED on branch $br in $eng
  based on: $start   (one proposal per branch; not cut from whatever was checked out)
  scan: clean (fail-closed; it ran before anything was written)
$where

  ┌─ THIS TEXT BECOMES PERMANENTLY PUBLIC WHEN YOU PUSH ────────────────────────
$(printf '%s\n' "$shown" | sed 's/^/  │ /')
  └─────────────────────────────────────────────────────────────────────────────

  The scan matches identifiers it can derive from this vault. It CANNOT judge whether
  the prose itself discloses something private. Read the block above as the reviewer,
  because after the push there is no retraction that works.

  To publish:  engine-proposal.sh push --vault "$VAULT" --slug $SLUG
  To discard:  git -C "$eng" branch -D $br
EOF
}

do_push() {
  [[ -n "${SLUG:-}" ]] || die "--slug is required"
  local marker="$(submit_marker_dir)/$SLUG.prepared"
  [[ -f "$marker" ]] || die "nothing prepared for '$SLUG' — run submit first (it scans; push does not)"
  local br; br="$(marker_branch "$marker")"
  # The checkout the branch actually lives in, as recorded by submit. An explicit
  # ENGINE_REPO still wins, but push no longer depends on the environment being
  # re-created: a submission prepared with ENGINE_REPO set used to die here if the
  # variable was not still exported.
  local eng
  if [[ -n "$ENGINE_REPO" ]]; then eng="$ENGINE_REPO"; else eng="$(marker_engine "$marker")"; fi
  [[ -n "$eng" ]] || eng="$(engine_repo_path)"
  engine_is_checkout "$eng" || die "no engine checkout at $eng — the prepared branch lives there; set ENGINE_REPO if it moved"
  git -C "$eng" rev-parse --verify "$br" >/dev/null 2>&1 || die "branch $br is gone — re-run submit"

  command -v gh >/dev/null 2>&1 || die "gh CLI not found — needed to open the pull request"

  # No write access is assumed: gh forks on demand. The fork is PUBLIC too, which the
  # consumer is told rather than left to discover.
  echo "engine-proposal: pushing $br and opening a pull request (forking if you lack write access)."
  echo "  Note: if a fork is created it is public, like the upstream repository."
  # PUSH FIRST. `gh pr create --head <br>` expects the head ref to already exist on the
  # remote; it does not push for you when the target repo is pinned with --repo, so the
  # PR failed with "Head sha can't be blank / No commits between main and <br>". Found on
  # the verb's first real use — nothing had ever exercised the publish half before.
  #
  # This is the irreversible step: everything up to here is local and discardable.
  if ! git -C "$eng" push -q --set-upstream origin "$br" 2>&1; then
    die "could not push $br to origin — you may lack write access. Fork the repo and push there, then open the pull request by hand; nothing was published."
  fi
  echo "engine-proposal: pushed $br"

  # Read the body from the BRANCH, not the working tree. submit restores the checkout to
  # where it found it (the pinned commit, in a submodule), so the queue file is not on disk
  # at HEAD — only on the ref being pushed.
  local body; body="$(mktemp)"
  git -C "$eng" show "$br:proposals/$SLUG.md" > "$body" 2>/dev/null \
    || die "branch $br IS pushed, but proposals/$SLUG.md is not on it — open the pull request by hand."
  if ! gh pr create --repo "$(git -C "$eng" remote get-url origin | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')" \
        --head "$br" --title "proposal: $SLUG" --body-file "$body" 2>&1; then
    rm -f "$body"
    die "branch $br IS pushed, but opening the pull request failed — open it by hand from that branch rather than re-running push."
  fi
  rm -f "$body"
  printf '%s\n%s\n' "$br" "$eng" > "$(submit_marker_dir)/$SLUG.submitted"
  rm -f "$marker"
  echo "engine-proposal: submitted. status will now report it as submitted-pending until merged."
}

# --- queue (ENGINE-DEV side) ---------------------------------------------------
# The consumer verbs all need --vault. This one does not: it runs in the engine repo and
# answers "what is waiting for me?" — the work-list half of the queue design, without
# which the directory is only a storage format and draining it means `ls` plus grep.
do_queue() {
  local repo="${REPO_ARG:-}"
  if [[ -z "$repo" ]]; then
    repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  local q="$repo/proposals"
  [[ -d "$q" ]] || die "no proposals/ queue at $q (pass --repo for a different engine checkout)"

  local fm_get; fm_get() {
    awk -v key="$2" '
      NR==1 && $0=="---" { f=1; next }
      f && $0=="---" { exit }
      f { if (index($0, key ":") == 1) { sub(/^[^:]*:[ \t]*/,""); gsub(/^"|"$/,""); print; exit } }
    ' "$1" 2>/dev/null
  }

  local n_open=0 n_other=0 out_open="" out_other=""
  local f slug outcome received reason
  for f in "$q"/*.md; do
    [[ -e "$f" ]] || continue
    slug="$(basename "$f" .md)"
    outcome="$(fm_get "$f" outcome)"
    received="$(fm_get "$f" received)"
    reason="$(fm_get "$f" reason)"
    if [[ "$outcome" == "open" ]]; then
      out_open+="$(printf '  %-52s received %s\n' "$slug" "${received:-?}")"$'\n'
      n_open=$((n_open+1))
    else
      out_other+="$(printf '  %-52s %-20s %s\n' "$slug" "${outcome:-<none>}" "${reason:0:44}")"$'\n'
      n_other=$((n_other+1))
    fi
  done

  # AWAITING MERGE — the interval between `push` and merge, where a proposal is visible
  # to the consumer (which reports it SUBMITTED) and invisible here, because arrival is
  # defined as the merged file. A proposal pushed from a FORK can only be merged by this
  # end, so it can sit indefinitely with both ends behaving correctly and nobody holding it.
  #
  # It degrades loudly on purpose. A remote section that is quietly empty when it could not
  # look is the very failure being fixed, one level up: "no open proposals" and "I could not
  # check" must never render the same.
  local n_pr=0 out_pr="" pr_note=""
  if [[ "${QUEUE_NO_REMOTE:-0}" == "1" ]]; then
    pr_note="skipped (QUEUE_NO_REMOTE=1)"
  elif ! command -v gh >/dev/null 2>&1; then
    pr_note="could not check — the gh CLI is not installed"
  else
    local pr_json
    if ! pr_json="$(cd "$repo" && gh pr list --state open --limit 50 \
                      --json number,title,headRefName,files 2>/dev/null)"; then
      pr_note="could not check — gh could not reach the remote (offline, or not authenticated)"
    else
      local line
      # Only pull requests that ADD a proposals/<slug>.md, and only slugs not already
      # merged: once the file lands, the file-derived entry above is the single record.
      while IFS=$'\t' read -r num slug title; do
        [[ -n "${slug:-}" ]] || continue
        [[ -e "$q/$slug.md" ]] && continue
        out_pr+="$(printf '  %-52s #%s  %s\n' "$slug" "$num" "${title:0:38}")"$'\n'
        n_pr=$((n_pr+1))
      done < <(printf '%s' "$pr_json" | python3 -c '
import json,sys
try: prs = json.load(sys.stdin)
except Exception: prs = []
for pr in prs:
    for f in pr.get("files") or []:
        path = f.get("path","")
        if path.startswith("proposals/") and path.endswith(".md"):
            print("\t".join([str(pr["number"]), path[len("proposals/"):-3], pr.get("title","")]))
            break
' 2>/dev/null)
    fi
  fi

  printf 'engine-proposal: queue at %s\n\n' "${q#$PWD/}"
  if [[ "$n_pr" -gt 0 ]]; then
    # Deliberately FIRST and named differently: these need a MERGE, not a design review.
    printf 'AWAITING MERGE — pushed, pull request still open (%d):\n%s\n' "$n_pr" "$out_pr"
  fi
  if [[ -n "$pr_note" ]]; then
    printf 'AWAITING MERGE — %s.\n  Open proposal pull requests are NOT included below; this list may be incomplete.\n\n' "$pr_note"
  fi
  if [[ "$n_open" -gt 0 ]]; then
    printf 'OPEN — awaiting intake (%d):\n%s\n' "$n_open" "$out_open"
  elif [[ "$n_pr" -eq 0 && -z "$pr_note" ]]; then
    printf 'OPEN — awaiting intake: none, and no open proposal pull requests. The queue is drained.\n\n'
  elif [[ "$n_pr" -gt 0 ]]; then
    # Drained of REVIEW work, but not of work: the pull requests above still need merging.
    printf 'OPEN — awaiting intake: none. The queue is drained of merged proposals — but see AWAITING MERGE above.\n\n'
  else
    # Could not check the remote. Still say "drained" about what was actually inspected,
    # and keep the caveat attached, so this never reads as an unqualified all-clear.
    printf 'OPEN — awaiting intake: none. The merged queue is drained; open pull requests were NOT checked (above).\n\n'
  fi
  if [[ "${QUEUE_ALL:-0}" == "1" && "$n_other" -gt 0 ]]; then
    printf 'RESOLVED (%d):\n%s\n' "$n_other" "$out_other"
  elif [[ "$n_other" -gt 0 ]]; then
    printf '(%d resolved; --all to list them)\n\n' "$n_other"
  fi
  # The drain instruction lives with the list, so it cannot drift away from it.
  if [[ "$n_open" -gt 0 ]]; then
    cat <<'EOF'
To process one (see the skill's intake section):
  1. Reproduce/verify its premises before choosing a shape.
  2. Record the decision by editing proposals/<slug>.md frontmatter —
     outcome: accepted | partially-accepted | rejected | alias  (+ reason: for a decline)
  3. Regenerate the ledger:  bin/gen-proposals-ledger.sh
     NEVER hand-edit PROPOSALS.md; it is derived, and lint-proposals.sh will catch it.
EOF
  fi
}

case "$CMD" in
  scan)   do_scan ;;
  stash)  do_stash ;;
  submit) do_submit ;;
  push)   do_push ;;
  queue)  do_queue ;;
  status) do_status ;;
  *) die "usage: engine-proposal.sh {scan|submit|push|status} --vault DIR | queue [--repo DIR] [--all]   (stash: retired, still accepted) [...]  (got '${CMD:-}')" ;;
esac
