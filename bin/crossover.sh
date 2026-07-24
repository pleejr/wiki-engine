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
# Transport is split by default: export emits ONE BLOCK PER ITEM, because total
# paste volume — not per-item size — is what the copy-paste channel drops (a
# 3-item block reliably lost 1-2 items, including its smallest, while every
# single-item block survived). The batch stays the unit of integrity: every
# block carries the same batch id + bundle hash and a MANIFEST of the batch's
# ordered (sha256, path) pairs, so import can accumulate blocks, name what is
# still outstanding, and take a re-paste of just the one block that failed.
# --bundle restores the old single-block output.
#
# The script only touches the filesystem (write / rm / rewrite references) and
# prints text. It never runs git: the calling session commits removals through
# the vault's normal branch->PR flow, so git history is the soft-delete safety net.
#
# Usage:
#   crossover.sh export  --vault DIR --batch ID [--copy] [--reviewed]
#                        [--bundle] [--block N] PATH [PATH...]
#   crossover.sh import  --vault DIR [--overwrite]        < export-block(s)
#   crossover.sh finalize --vault DIR --batch ID [--yes]  < receipt-block
#
# PATHs are vault-relative (e.g. memory/foo.md). --copy marks the batch as a
# copy (dual-purpose content): finalize will refuse to delete it. --reviewed
# skips the secret-scan for a human-reviewed export (use only after confirming
# the files carry no real secret — the scan flags secret *assignments*, so a
# note that merely discusses "secrets"/"tokens" in prose passes without it).
# --bundle emits the whole batch as one block (the pre-1.24 shape). --block N
# re-emits only block N of the same batch — pass the SAME full PATH list, so
# the batch identity (bundle + manifest) is unchanged — to repair one lossy
# paste without re-sending the rest.

set -uo pipefail

PROTO="CROSSOVER v1"
LEDGER_DIR=".crossover"

die() { printf 'crossover: %s\n' "$*" >&2; exit 1; }

sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
sha256_stdin() { shasum -a 256 2>/dev/null | awk '{print $1}'; }
b64enc() { openssl base64 -in "$1"; }                 # 64-col wrapped lines (copy-paste-safe)
b64dec() { openssl base64 -d -A; }                    # stdin -> stdout (tolerates joined input)

# bundle hash = sha256 of the newline-joined, order-preserved item hashes.
# Empty list -> a sentinel that can never equal a real bundle (bash 3.2 expands
# "${empty[@]}" as nothing under set -u, so guard rather than hash an empty line).
bundle_of() { (( $# )) || { printf 'none\n'; return 0; }; printf '%s\n' "$@" | sha256_stdin; }

# --- argument parsing ---------------------------------------------------------
CMD="${1:-}"; shift || true
VAULT=""; BATCH=""; COPY=0; OVERWRITE=0; ASSUME_YES=0; REVIEWED=0; BUNDLE=0; ONLY_BLOCK=0
PATHS=()
while (( $# )); do
  case "$1" in
    --vault)     VAULT="${2:-}"; shift 2 ;;
    --batch)     BATCH="${2:-}"; shift 2 ;;
    --copy)      COPY=1; shift ;;
    --reviewed)  REVIEWED=1; shift ;;
    --bundle)    BUNDLE=1; shift ;;
    --block)     ONLY_BLOCK="${2:-}"; shift 2 ;;
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

  local mode; mode="$([[ $COPY -eq 1 ]] && echo copy || echo move)"
  local n=${#PATHS[@]} nblocks i
  # one block per item by default; --bundle keeps the whole batch in one block
  if [[ $BUNDLE -eq 1 ]]; then nblocks=1; else nblocks=$n; fi
  # validate the block selector BEFORE touching the ledger — a die past this
  # point would leave the batch's outbound ledger truncated, i.e. destroy the
  # origin's record of what the batch is
  if [[ "$ONLY_BLOCK" != 0 ]]; then
    [[ "$ONLY_BLOCK" =~ ^[0-9]+$ ]] || die "--block takes a block number (1..$nblocks)"
    (( ONLY_BLOCK >= 1 && ONLY_BLOCK <= nblocks )) || die "--block $ONLY_BLOCK out of range (this batch has $nblocks block(s); pass the SAME full path list you exported with)"
  fi

  mkdir -p "$VAULT/$LEDGER_DIR"
  local ledger="$VAULT/$LEDGER_DIR/$BATCH.outbound"
  : > "$ledger"

  # the ledger is the batch's identity at the origin — always the full item list,
  # however transport is split
  for (( i=0; i<n; i++ )); do
    printf '%s\t%s\t%s\n' "${PATHS[$i]}" "${hashes[$i]}" "$mode" >> "$ledger"
  done

  # emit_block <block-no> <first-item-idx> <item-count>
  emit_block() {
    local bno="$1" first="$2" cnt="$3" j b
    printf '##%s EXPORT\n' "$PROTO"
    printf 'batch %s\n' "$BATCH"
    printf 'source %s\n' "$(vault_id)"
    printf 'generated %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'mode %s\n' "$mode"
    printf 'count %d\n' "$n"
    printf 'bundle %s\n' "$bundle"
    printf 'block %d/%d\n' "$bno" "$nblocks"
    # the manifest names the WHOLE batch in every block, so a single block is
    # enough for import to know what else is still outstanding
    printf '##MANIFEST\n'
    for (( j=0; j<n; j++ )); do printf 'item %s %s\n' "${hashes[$j]}" "${PATHS[$j]}"; done
    for (( j=first; j<first+cnt; j++ )); do
      b="$(sed -nE 's/^boundary:[[:space:]]*([a-z]+).*/\1/p' "$VAULT/${PATHS[$j]}" | head -1)"
      printf '##ITEM\n'
      printf 'path %s\n' "${PATHS[$j]}"
      printf 'sha256 %s\n' "${hashes[$j]}"
      printf 'boundary %s\n' "${b:-unknown}"
      # payload as wrapped base64 between ##DATA and the next marker — short lines
      # survive copy-paste where one multi-thousand-char line gets mangled/truncated
      printf '##DATA\n'
      b64enc "$VAULT/${PATHS[$j]}"
    done
    printf '##END\n'
  }

  if [[ $BUNDLE -eq 1 ]]; then
    emit_block 1 0 "$n"
  else
    local emitted=0
    for (( i=0; i<n; i++ )); do
      [[ "$ONLY_BLOCK" != 0 && $((i+1)) -ne $ONLY_BLOCK ]] && continue
      # a blank line between blocks, so each ##EXPORT…##END span is easy to
      # select and copy on its own; a re-emitted single block gets none
      (( emitted )) && printf '\n'
      emit_block $((i+1)) "$i" 1
      emitted=1
    done
  fi

  if [[ "$ONLY_BLOCK" != 0 ]]; then
    printf 'crossover: re-emitted block %s/%d of batch %s (item %s) — paste this block alone.\n' \
      "$ONLY_BLOCK" "$nblocks" "$BATCH" "${PATHS[$((ONLY_BLOCK-1))]}" >&2
  elif [[ $BUNDLE -eq 1 ]]; then
    printf 'crossover: exported %d item(s) as batch %s (mode=%s) in ONE block (--bundle); ledger %s\n' \
      "$n" "$BATCH" "$mode" "$LEDGER_DIR/$BATCH.outbound" >&2
    if (( n > 1 )); then
      printf 'crossover: NOTE — multi-item blocks are the shape that loses items in a lossy paste. Prefer the default one-block-per-item.\n' >&2
    fi
  else
    printf 'crossover: exported %d item(s) as batch %s (mode=%s) in %d block(s), one per item; ledger %s\n' \
      "$n" "$BATCH" "$mode" "$nblocks" "$LEDGER_DIR/$BATCH.outbound" >&2
    printf 'crossover: paste each ##%s EXPORT ... ##END block SEPARATELY into the destination session; import accumulates them.\n' "$PROTO" >&2
  fi
}

# ============================================================ import ==========
# Accumulating import. A batch may arrive as N separate pastes (the default
# split transport), in any order, across separate invocations — so import merges
# every block it sees into the batch's inbound ledger and judges the batch, not
# the paste. The receipt always covers the WHOLE batch (per the manifest), with
# never-received items reported `missing`, so the origin's finalize gate is
# unchanged: only an all-verified receipt whose bundle matches can authorize a
# delete.
do_import() {
  local line key val
  local batch="" src="" bundle="" blocks_seen=0 blk="" blk_count=""
  local cur_path="" cur_sha="" cur_data="" in_data=0 in_manifest=0
  # accumulator (prior ledger, then this stream on top), upserted by path
  local a_paths=() a_shas=() a_status=()
  # what THIS stream carried, in arrival order (also the legacy fallback manifest)
  local t_paths=() t_shas=() t_status=()
  # manifest of the whole batch (ordered)
  local m_paths=() m_shas=()
  # a block's own manifest lines, staged until its `count` confirms it is whole
  local c_paths=() c_shas=()

  record() {   # path sha status — upsert into the accumulator
    local p="$1" s="$2" st="$3" i=0 n=${#a_paths[@]}
    while (( i < n )); do
      if [[ "${a_paths[$i]}" == "$p" ]]; then a_shas[$i]="$s"; a_status[$i]="$st"; return 0; fi
      i=$((i+1))
    done
    a_paths+=("$p"); a_shas+=("$s"); a_status+=("$st")
  }
  status_of() {  # path -> status, empty if never seen
    local p="$1" i=0 n=${#a_paths[@]}
    while (( i < n )); do
      [[ "${a_paths[$i]}" == "$p" ]] && { printf '%s' "${a_status[$i]}"; return 0; }
      i=$((i+1))
    done
  }
  record_stream() {  # path sha status — upsert into this stream's results
    local p="$1" s="$2" st="$3" i=0 n=${#t_paths[@]}
    while (( i < n )); do
      if [[ "${t_paths[$i]}" == "$p" ]]; then t_shas[$i]="$s"; t_status[$i]="$st"; return 0; fi
      i=$((i+1))
    done
    t_paths+=("$p"); t_shas+=("$s"); t_status+=("$st")
  }

  flush_item() {
    [[ -n "$cur_path" ]] || return 0
    local abs="$VAULT/$cur_path" tmp out got status=""
    tmp="$(mktemp)"; out="$(mktemp)"
    printf '%s' "$cur_data" | b64dec > "$tmp" 2>/dev/null || status="decode-failed"
    if [[ -z "$status" ]]; then
      got="$(sha256 "$tmp")"
      if [[ "$got" != "$cur_sha" ]]; then
        status="hash-mismatch"
      else
        # crossover into this vault flips the boundary tag
        sed -E 's/^(boundary:[[:space:]]*)[a-z]+/\1personal/' "$tmp" > "$out"
        if [[ -e "$abs" ]] && cmp -s "$abs" "$out"; then
          status="written"          # already landed byte-identical: a re-paste is idempotent
        elif [[ -e "$abs" && $OVERWRITE -eq 0 ]]; then
          status="exists-skipped"
        else
          mkdir -p "$(dirname "$abs")"
          cat "$out" > "$abs"
          status="written"
        fi
      fi
    fi
    record_stream "$cur_path" "$cur_sha" "$status"
    rm -f "$tmp" "$out"
    cur_path=""; cur_sha=""; cur_data=""
  }

  take_manifest() {  # accept a block's manifest only if it is whole (count matches)
    if [[ "$blk_count" =~ ^[0-9]+$ ]] && (( ${#c_paths[@]} != blk_count )); then
      printf 'crossover: WARNING — block %s manifest is short (%d of %s lines); ignoring it (re-paste this block).\n' \
        "${blk:-?}" "${#c_paths[@]}" "$blk_count" >&2
    elif (( ${#c_paths[@]} )); then
      m_paths=("${c_paths[@]}"); m_shas=("${c_shas[@]}")
    fi
    c_paths=(); c_shas=()
  }

  local t
  while IFS= read -r line; do
    # trim surrounding whitespace before matching: a chat client that indents or
    # pads the pasted block must not hide a marker or a header key (payload lines
    # are whitespace-stripped anyway)
    t="${line#"${line%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    case "$t" in
      "##$PROTO EXPORT") flush_item; in_data=0; in_manifest=0; blocks_seen=$((blocks_seen+1)); blk=""; blk_count="" ;;
      "##MANIFEST") in_manifest=1; in_data=0; c_paths=(); c_shas=() ;;
      "##ITEM") flush_item; [[ $in_manifest -eq 1 ]] && take_manifest; in_manifest=0; in_data=0 ;;
      "##DATA") in_data=1; cur_data="" ;;
      "##END")  flush_item; [[ $in_manifest -eq 1 ]] && take_manifest; in_manifest=0; in_data=0 ;;
      *)
        if [[ $in_data -eq 1 ]]; then
          # accumulate wrapped base64; strip any stray CR/whitespace so a
          # reflowed paste still decodes to the exact bytes
          cur_data+="${line//[[:space:]]/}"
        elif [[ $in_manifest -eq 1 ]]; then
          # inside the manifest only `item <sha> <path>` lines count; anything
          # else is paste damage and is ignored (the count check catches a short
          # manifest, so a mangled one can never masquerade as the batch)
          if [[ "$t" == item\ * ]]; then
            val="${t#item }"
            c_shas+=("${val%% *}"); c_paths+=("${val#* }")
          fi
        else
          key="${t%% *}"; val="${t#* }"
          case "$key" in
            batch)
              [[ -z "$batch" || "$batch" == "$val" ]] || die "blocks in this paste are from different batches ($batch vs $val) — import them separately"
              batch="$val" ;;
            source)   src="$val" ;;
            bundle)
              [[ -z "$bundle" || "$bundle" == "$val" ]] || die "blocks in this paste carry different bundle hashes — they are not one batch"
              bundle="$val" ;;
            block)    blk="$val" ;;
            count)    blk_count="$val" ;;
            path)     cur_path="$val" ;;
            sha256)   cur_sha="$val" ;;
            data)     cur_data="$val" ;;   # legacy single-line payload
            # mode/boundary/generated are informational in the block
          esac
        fi ;;
    esac
  done
  flush_item
  [[ -n "$batch" ]] || die "input is not a $PROTO export block"

  mkdir -p "$VAULT/$LEDGER_DIR"
  local ledger="$VAULT/$LEDGER_DIR/$batch.inbound"
  local mfile="$VAULT/$LEDGER_DIR/$batch.manifest"

  # the batch's manifest survives across pastes: a block whose manifest was
  # mangled still gets judged against the whole batch
  if (( ${#m_paths[@]} )); then
    { printf 'bundle %s\n' "$bundle"; local k
      for (( k=0; k<${#m_paths[@]}; k++ )); do printf 'item %s %s\n' "${m_shas[$k]}" "${m_paths[$k]}"; done
    } > "$mfile"
  elif [[ -f "$mfile" ]]; then
    while IFS= read -r line; do
      case "$line" in
        item\ *) val="${line#item }"; m_shas+=("${val%% *}"); m_paths+=("${val#* }") ;;
        bundle\ *) [[ -n "$bundle" ]] || bundle="${line#bundle }" ;;
      esac
    done < "$mfile"
  else
    # legacy block (pre-manifest): the batch is whatever this paste carried
    if (( ${#t_paths[@]} )); then m_paths=("${t_paths[@]}"); m_shas=("${t_shas[@]}"); fi
  fi

  # prior pastes of this batch seed the accumulator; this stream's results win
  local lp lh ls i
  if [[ -f "$ledger" ]]; then
    while IFS=$'\t' read -r lp lh ls; do
      [[ -n "$lp" ]] && record "$lp" "$lh" "$ls"
    done < "$ledger"
  fi
  for (( i=0; i<${#t_paths[@]}; i++ )); do
    record "${t_paths[$i]}" "${t_shas[$i]}" "${t_status[$i]}"
  done

  # the receipt covers the whole batch, in manifest order
  local verified=() st all_ok=1 outstanding=()
  : > "$ledger"
  for (( i=0; i<${#m_paths[@]}; i++ )); do
    st="$(status_of "${m_paths[$i]}")"; [[ -n "$st" ]] || st="missing"
    printf '%s\t%s\t%s\n' "${m_paths[$i]}" "${m_shas[$i]}" "$st" >> "$ledger"
    if [[ "$st" == "written" ]]; then
      verified+=("${m_shas[$i]}")
    else
      all_ok=0; outstanding+=("${m_paths[$i]} ($st)")
    fi
  done
  local got_bundle="none"
  if (( ${#verified[@]} )); then got_bundle="$(bundle_of "${verified[@]}")"; fi

  printf '##%s RECEIPT\n' "$PROTO"
  printf 'batch %s\n' "$batch"
  printf 'source %s\n' "$src"
  printf 'dest %s\n' "$(vault_id)"
  printf 'bundle %s\n' "$got_bundle"
  for (( i=0; i<${#m_paths[@]}; i++ )); do
    st="$(status_of "${m_paths[$i]}")"; [[ -n "$st" ]] || st="missing"
    printf '##ITEM path %s status %s sha256 %s\n' "${m_paths[$i]}" "$st" "${m_shas[$i]}"
  done
  local ok=0
  [[ "$got_bundle" == "$bundle" && $all_ok -eq 1 ]] && ok=1
  if (( ok )); then printf 'status all-verified\n'; else printf 'status incomplete\n'; fi
  printf '##END\n'

  printf 'crossover: batch %s — %d block(s) in this paste; %d/%d item(s) verified into %s.\n' \
    "$batch" "$blocks_seen" "${#verified[@]}" "${#m_paths[@]}" "$(vault_id)" >&2
  if (( ok )); then
    printf 'crossover: all-verified — give the receipt block above to the origin session to finalize.\n' >&2
  else
    printf 'crossover: INCOMPLETE — do not finalize. Outstanding:\n' >&2
    printf '  - %s\n' "${outstanding[@]:-（none — bundle mismatch）}" >&2
    printf 'crossover: re-paste only the block(s) for those item(s); this ledger keeps what already verified (%s).\n' \
      "$LEDGER_DIR/$batch.inbound" >&2
  fi
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
  (( ${#exp_hashes[@]} )) || die "outbound ledger for batch $BATCH is empty — re-run export for this batch before finalizing"
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
