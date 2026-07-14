#!/usr/bin/env bash
# reflow.sh — normalize Markdown to the engine's soft-wrap convention: one physical
# line per paragraph and per list item (no mid-paragraph hard wraps), so pages render
# as flowing prose in every Obsidian view/mode with no setting to configure.
#
# It joins wrapped prose and list-item lines only. Frontmatter, fenced code, headings,
# blockquotes, tables, horizontal rules, HTML comments, and blank lines are left as-is.
# It never changes words — it only removes the newlines that hard-wrap a block.
#
# Usage:
#   reflow.sh FILE...            rewrite each file in place
#   reflow.sh --check FILE...    exit 1 if any file would change (no write)
#   reflow.sh --stdout FILE      print the reflowed file to stdout
set -euo pipefail

MODE="write"
case "${1:-}" in
  --check)  MODE="check";  shift;;
  --stdout) MODE="stdout"; shift;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac
[ $# -gt 0 ] || { echo "usage: reflow.sh [--check|--stdout] FILE..." >&2; exit 1; }

reflow_one() {
  awk '
    BEGIN { fm=0; code=0; buf=""; have=0 }
    function flush() { if (have) { print buf; buf=""; have=0 } }
    function add(s) { if (have) buf = buf " " s; else { buf=s; have=1 } }
    NR==1 && $0=="---" { fm=1; print; next }
    fm==1 { print; if ($0=="---") fm=2; next }
    /^[ \t]*```/ { flush(); code = !code; print; next }
    code { print; next }
    /^[ \t]*$/ { flush(); print; next }
    /^#{1,6}[ \t]/          { flush(); print; next }
    /^[ \t]*>/              { flush(); print; next }
    /^[ \t]*\|/             { flush(); print; next }
    /^([-*_])( *\1){2,} *$/ { flush(); print; next }
    /^[ \t]*<!--/           { flush(); print; next }
    /^[ \t]*([-*+]|[0-9]+\.)[ \t]/ { flush(); add($0); next }
    /^[ \t]+[^ \t]/ { if (have) { s=$0; sub(/^[ \t]+/,"",s); add(s); next } print; next }
    { add($0); next }
    END { flush() }
  ' "$1"
}

rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "skip (not a file): $f" >&2; continue; }
  case "$MODE" in
    stdout) reflow_one "$f";;
    check)  if ! diff -q "$f" <(reflow_one "$f") >/dev/null; then echo "would reflow: $f"; rc=1; fi;;
    write)  tmp="$(mktemp)"; reflow_one "$f" > "$tmp"; if ! diff -q "$f" "$tmp" >/dev/null; then mv "$tmp" "$f"; echo "reflowed: $f"; else rm -f "$tmp"; fi;;
  esac
done
exit $rc
