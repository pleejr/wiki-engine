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
#   scan  --vault DIR [--file F]    block on stdin (or F) -> findings; exit 1 if any leak
#   stash --vault DIR --slug ID     block on stdin -> $VAULT/.engine-proposal/ID.outbox (git-ignored)
#
# `scan` derives the consumer's OWN identifiers from the vault (git remote slug,
# directory name, git user name/email) and flags any literal appearance in the
# block, plus universal private-shaped patterns (home paths, emails, a non-generic
# `boundary:` tag, secret assignments). A clean block exits 0. The scan is a
# backstop for the skill's genericization, not a replacement — it can only catch
# identifiers it can derive, so the skill still owns the actual scrub.
#
# Usage:
#   engine-proposal.sh scan  --vault DIR [--file draft.md]   < block
#   engine-proposal.sh stash --vault DIR --slug my-idea       < block

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

case "$CMD" in
  scan)  do_scan ;;
  stash) do_stash ;;
  *) die "usage: engine-proposal.sh {scan|stash} --vault DIR [...]  (got '${CMD:-}')" ;;
esac
