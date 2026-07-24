#!/usr/bin/env bash
#
# crossover.sh — deterministic transport for the `crossover` skill.
#
# Moves vault items (markdown pages) between two vaults that never share a
# machine, over a copy-paste text channel, with end-to-end integrity so a
# lossy paste can never trigger a wipe of the only good copy.
#
# Three subcommands form a handshake:
#   export   (origin)      selected files  -> a paste block on stdout   [no deletion]
#   import   (destination) a paste block on stdin -> files + a receipt on stdout
#   finalize (origin)      a receipt on stdin -> soft-delete + tombstone sweep, ONLY on hash match
#
# Integrity: each item carries a sha256 of its raw bytes; the batch carries a
# bundle hash (sha256 of the ordered per-item hashes). finalize refuses to
# delete anything unless the returned receipt's bundle hash matches what export
# sent — so "the human said it worked" is never the thing that authorizes a wipe.
#
# The script only touches the filesystem (write / rm / rewrite references) and
# prints text. It never runs git: the calling session commits removals through
# the vault's normal branch->PR flow, so git history is the soft-delete safety net.
#
# Usage:
#   crossover.sh export  --vault DIR --batch ID [--copy] [--reviewed] PATH [PATH...]
#   crossover.sh import  --vault DIR [--overwrite]        < export-block
#   crossover.sh finalize --vault DIR --batch ID [--yes]  < receipt-block
#
# PATHs are vault-relative (e.g. memory/foo.md). --copy marks the batch as a
# copy (dual-purpose content): finalize will refuse to delete it. --reviewed
# skips the secret-scan for a human-reviewed export (use only after confirming
# the files carry no real secret — the scan flags secret *assignments*, so a
# note that merely discusses "secrets"/"tokens" in prose passes without it).

set -uo pipefail

PROTO="CROSSOVER v1"
LEDGER_DIR=".crossover"

die() { printf 'crossover: %s\n' "$*" >&2; exit 1; }

sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
sha256_stdin() { shasum -a 256 2>/dev/null | awk '{print $1}'; }
b64enc() { openssl base64 -in "$1"; }                 # 64-col wrapped lines (copy-paste-safe)
b64dec() { openssl base64 -d -A; }                    # stdin -> stdout (tolerates joined input)

# bundle hash = sha256 of the newline-joined, order-preserved item hashes
bundle_of() { printf '%s\n' "$@" | sha256_stdin; }

# --- argument parsing ---------------------------------------------------------
CMD="${1:-}"; shift || true
VAULT=""; BATCH=""; COPY=0; OVERWRITE=0; ASSUME_YES=0; REVIEWED=0
PATHS=()
while (( $# )); do
  case "$1" in
    --vault)     VAULT="${2:-}"; shift 2 ;;
    --batch)     BATCH="${2:-}"; shift 2 ;;
    --copy)      COPY=1; shift ;;
    --reviewed)  REVIEWED=1; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    --yes)       ASSUME_YES=1; shift ;;
    --) shift; while (( $# )); do PATHS+=("$1"); shift; done ;;
    -*) die "unknown flag: $1" ;;
    *)  PATHS+=("$1"); shift ;;
  esac
done
[[ -n "$VAULT" ]] || die "--vault is required"
[[ -d "$VAULT" ]] || die "vault not found: $VAULT"
VAULT="$(cd "$VAULT" && pwd)"

vault_id() {
  git -C "$VAULT" remote get-url origin 2>/dev/null \
    | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#' || basename "$VAULT"
}

# ============================================================ export ==========
do_export() {
  [[ -n "$BATCH" ]] || die "--batch is required for export"
  (( ${#PATHS[@]} )) || die "no paths given to export"
  local hashes=() rel abs
  # validate + secret-scan before emitting anything. The scan targets secret
  # *assignments* (key : value / key = value) and literal key material, not the
  # bare words — so a workflow note that discusses "secrets"/"tokens" in prose
  # is not a false positive. --reviewed skips it after a human has confirmed.
  for rel in "${PATHS[@]}"; do
    abs="$VAULT/$rel"
    [[ -f "$abs" ]] || die "not a file in vault: $rel"
    if [[ $REVIEWED -eq 0 ]] && grep -nEi \
        -e '(api[_-]?key|client[_-]?secret|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}' \
        -e 'AKIA[0-9A-Z]{16}' \
        -e 'BEGIN [A-Z ]*PRIVATE KEY' \
        "$abs" >/dev/null; then
      die "refusing to export $rel — looks like it carries a secret value (crossover carries no secrets). If it only mentions secrets in prose, re-run with --reviewed."
    fi
  done
  [[ $REVIEWED -eq 1 ]] && printf 'crossover: --reviewed set — secret-scan skipped for this export.\n' >&2
  for rel in "${PATHS[@]}"; do hashes+=("$(sha256 "$VAULT/$rel")"); done
  local bundle; bundle="$(bundle_of "${hashes[@]}")"

  mkdir -p "$VAULT/$LEDGER_DIR"
  local ledger="$VAULT/$LEDGER_DIR/$BATCH.outbound"
  : > "$ledger"

  printf '##%s EXPORT\n' "$PROTO"
  printf 'batch %s\n' "$BATCH"
  printf 'source %s\n' "$(vault_id)"
  printf 'generated %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'mode %s\n' "$([[ $COPY -eq 1 ]] && echo copy || echo move)"
  printf 'count %d\n' "${#PATHS[@]}"
  printf 'bundle %s\n' "$bundle"
  local i=0 b
  for rel in "${PATHS[@]}"; do
    abs="$VAULT/$rel"
    b="$(sed -nE 's/^boundary:[[:space:]]*([a-z]+).*/\1/p' "$abs" | head -1)"
    printf '##ITEM\n'
    printf 'path %s\n' "$rel"
    printf 'sha256 %s\n' "${hashes[$i]}"
    printf 'boundary %s\n' "${b:-unknown}"
    # payload as wrapped base64 between ##DATA and the next marker — short lines
    # survive copy-paste where one multi-thousand-char line gets mangled/truncated
    printf '##DATA\n'
    b64enc "$abs"
    printf '%s\t%s\t%s\n' "$rel" "${hashes[$i]}" "$([[ $COPY -eq 1 ]] && echo copy || echo move)" >> "$ledger"
    i=$((i+1))
  done
  printf '##END\n'
  printf 'crossover: exported %d item(s) as batch %s (mode=%s); ledger %s\n' \
    "${#PATHS[@]}" "$BATCH" "$([[ $COPY -eq 1 ]] && echo copy || echo move)" "$LEDGER_DIR/$BATCH.outbound" >&2
}

# ============================================================ import ==========
do_import() {
  local line key val
  local batch="" src="" bundle=""
  local cur_path="" cur_sha="" cur_data="" in_data=0
  local -a r_paths r_shas r_status
  local seen_hashes=()

  flush_item() {
    [[ -n "$cur_path" ]] || return 0
    local abs="$VAULT/$cur_path" tmp got status
    tmp="$(mktemp)"
    printf '%s' "$cur_data" | b64dec > "$tmp" 2>/dev/null || { status="decode-failed"; }
    if [[ -z "${status:-}" ]]; then
      got="$(sha256 "$tmp")"
      if [[ "$got" != "$cur_sha" ]]; then
        status="hash-mismatch"
      elif [[ -e "$abs" && $OVERWRITE -eq 0 ]]; then
        status="exists-skipped"
      else
        mkdir -p "$(dirname "$abs")"
        # crossover into this vault flips the boundary tag
        sed -E 's/^(boundary:[[:space:]]*)[a-z]+/\1personal/' "$tmp" > "$abs"
        status="written"
      fi
    fi
    seen_hashes+=("$cur_sha")
    r_paths+=("$cur_path"); r_shas+=("$cur_sha"); r_status+=("$status")
    rm -f "$tmp"
    cur_path=""; cur_sha=""; cur_data=""; status=""
  }

  while IFS= read -r line; do
    case "$line" in
      "##$PROTO EXPORT") in_data=0 ;;
      "##ITEM") flush_item; in_data=0 ;;
      "##DATA") in_data=1; cur_data="" ;;
      "##END")  flush_item; break ;;
      *)
        if [[ $in_data -eq 1 ]]; then
          # accumulate wrapped base64; strip any stray CR/whitespace so a
          # reflowed paste still decodes to the exact bytes
          cur_data+="${line//[[:space:]]/}"
        else
          key="${line%% *}"; val="${line#* }"
          case "$key" in
            batch)    batch="$val" ;;
            source)   src="$val" ;;
            bundle)   bundle="$val" ;;
            path)     cur_path="$val" ;;
            sha256)   cur_sha="$val" ;;
            data)     cur_data="$val" ;;   # legacy single-line payload
            # count/mode/boundary are informational in the block
          esac
        fi ;;
    esac
  done
  [[ -n "$batch" ]] || die "input is not a $PROTO export block"

  local got_bundle; got_bundle="$(bundle_of "${seen_hashes[@]}")"
  mkdir -p "$VAULT/$LEDGER_DIR"
  local ledger="$VAULT/$LEDGER_DIR/$batch.inbound"; : > "$ledger"

  printf '##%s RECEIPT\n' "$PROTO"
  printf 'batch %s\n' "$batch"
  printf 'source %s\n' "$src"
  printf 'dest %s\n' "$(vault_id)"
  printf 'bundle %s\n' "$got_bundle"
  local i all_ok=1
  for i in "${!r_paths[@]}"; do
    printf '##ITEM path %s status %s sha256 %s\n' "${r_paths[$i]}" "${r_status[$i]}" "${r_shas[$i]}"
    printf '%s\t%s\t%s\n' "${r_paths[$i]}" "${r_shas[$i]}" "${r_status[$i]}" >> "$ledger"
    [[ "${r_status[$i]}" == "written" ]] || all_ok=0
  done
  if [[ "$got_bundle" == "$bundle" && $all_ok -eq 1 ]]; then
    printf 'status all-verified\n'
  else
    printf 'status incomplete\n'
  fi
  printf '##END\n'
  printf 'crossover: imported batch %s into %s; receipt above%s\n' \
    "$batch" "$(vault_id)" \
    "$([[ "$got_bundle" == "$bundle" && $all_ok -eq 1 ]] && echo '' || echo ' (INCOMPLETE — do not finalize)')" >&2
}

# ============================================================ finalize ========
do_finalize() {
  [[ -n "$BATCH" ]] || die "--batch is required for finalize"
  local out="$VAULT/$LEDGER_DIR/$BATCH.outbound"
  [[ -f "$out" ]] || die "no outbound ledger for batch $BATCH (export was run elsewhere?)"

  # any copy-mode item makes the whole batch non-deletable
  if awk -F'\t' '$3=="copy"{f=1} END{exit !f}' "$out"; then
    die "batch $BATCH is a copy batch — nothing to delete; finalize is only for move batches"
  fi

  local line key val batch="" dest="" r_bundle="" status=""
  local -a rp rs rr
  while IFS= read -r line; do
    case "$line" in
      "##$PROTO RECEIPT") : ;;
      "##END") break ;;
      "##ITEM path "*)
        # ##ITEM path <p> status <s> sha256 <h>
        rp+=("$(sed -E 's/^##ITEM path (.*) status .*/\1/' <<<"$line")")
        rr+=("$(sed -E 's/.* status ([^ ]+) sha256 .*/\1/' <<<"$line")")
        rs+=("$(sed -E 's/.* sha256 (.*)$/\1/' <<<"$line")") ;;
      *)
        key="${line%% *}"; val="${line#* }"
        case "$key" in
          batch)  batch="$val" ;;
          dest)   dest="$val" ;;
          bundle) r_bundle="$val" ;;
          status) status="$val" ;;
        esac ;;
    esac
  done
  [[ -n "$batch" ]] || die "input is not a $PROTO receipt block"
  [[ "$batch" == "$BATCH" ]] || die "receipt batch ($batch) != --batch ($BATCH)"

  # recompute the bundle from the outbound ledger (ordered item hashes) and
  # compare to the receipt
  local -a exp_hashes=(); local eh
  while IFS=$'\t' read -r _ eh _; do exp_hashes+=("$eh"); done < "$out"
  local expected; expected="$(bundle_of "${exp_hashes[@]}")"
  if [[ "$r_bundle" != "$expected" ]]; then
    die "REFUSING TO DELETE: receipt bundle $r_bundle != sent bundle $expected — the transferred copy differs from the original"
  fi
  if [[ "$status" != "all-verified" ]]; then
    die "REFUSING TO DELETE: receipt status is '$status', not 'all-verified'"
  fi
  # every ledger item must be present + written in the receipt
  local rel h ok
  while IFS=$'\t' read -r rel h _; do
    ok=0; local i
    for i in "${!rp[@]}"; do
      [[ "${rp[$i]}" == "$rel" && "${rs[$i]}" == "$h" && "${rr[$i]}" == "written" ]] && ok=1
    done
    [[ $ok -eq 1 ]] || die "REFUSING TO DELETE: $rel not confirmed written in receipt"
  done < "$out"

  if [[ $ASSUME_YES -eq 0 ]]; then
    printf 'crossover: bundle verified. Deleting %d item(s) of batch %s and sweeping references.\n' \
      "$(wc -l <"$out" | tr -d ' ')" "$BATCH" >&2
  fi

  # soft-delete: remove files; the caller commits the removal (history retains them)
  local slug touched=()
  while IFS=$'\t' read -r rel h _; do
    slug="$(basename "$rel" .md)"
    rm -f "$VAULT/$rel"
    # tombstone sweep: [[slug]] -> slug (migrated -> <dest>, <date>), never silent.
    # '#' delimiter so the '/' in <dest> (org/repo) can't break the s-command.
    local today marker; today="$(date -u +%Y-%m-%d)"
    marker="$slug (migrated -> $dest, $today)"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      sed -i.bak -E "s#\[\[$slug\]\]#$marker#g" "$f"
      rm -f "$f.bak"; touched+=("$f")
    done < <(grep -rl --include='*.md' "\[\[$slug\]\]" "$VAULT" 2>/dev/null || true)
  done < "$out"

  # record what happened, mark the ledger finalized
  local rec="$VAULT/$LEDGER_DIR/$BATCH.finalized"
  {
    printf 'finalized %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'dest %s\n' "$dest"
    printf 'deleted:\n'; awk -F'\t' '{print "  "$1}' "$out"
    printf 'tombstoned:\n'; printf '  %s\n' "${touched[@]:-（none）}" | sort -u
  } > "$rec"

  printf 'crossover: deleted %d item(s); tombstoned %d reference file(s). Record: %s\n' \
    "$(wc -l <"$out" | tr -d ' ')" "$(printf '%s\n' "${touched[@]:-}" | grep -c . || true)" \
    "$LEDGER_DIR/$BATCH.finalized" >&2
  printf 'Now commit the removals + tombstones through the vault git flow (soft-delete: history retains the files).\n' >&2
}

case "$CMD" in
  export)   do_export ;;
  import)   do_import ;;
  finalize) do_finalize ;;
  *) die "usage: crossover.sh {export|import|finalize} --vault DIR [...]  (got '${CMD:-}')" ;;
esac
