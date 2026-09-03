#!/usr/bin/env bash
# lint-docs.sh — keep the usage docs honest so new users adopt with the lowest friction.
# Nine cheap, deterministic checks (no LLM, never `claude`):
#   1. every skill (skills/*/) is mentioned in USAGE.md  — nothing user-facing goes undocumented
#   2. every engine-shipped file USAGE/SCHEMA/README reference actually exists — no stale
#      pointers to deleted tools, whether written bare (`foo.sh`) or as a path (`adopt.d/foo.sh`)
#   3. no shipped skill or tool STAMPS a specific boundary value — the engine is
#      boundary-agnostic (SCHEMA.md), so it must ask the vault, never name one
#   4. a worktree-taking skill must name CANONICAL where it touches git-ignored state (v1.51.0)
#   5. every vault WALK goes through the shared exclusion, never its own prune list (v1.54.3)
#   6. every documented hook SNIPPET states a `timeout` — a hook the host cancels is silent,
#      and the snippet is what people copy into a real settings.json
#   7. a defect-report template's Expected-versus-fix rule is sited on BOTH surfaces, not
#      only in the half the reporter never reads (v1.68.0)
#   8. every skill's `description:` fits the host router's cut — error above 1500
#      characters, warning above 1400 — because the clauses past the cut are the
#      `Distinct from` / `NOT for` exclusions, and a clause the router cannot see is
#      not a rule (v1.74.0)
#   9. every `skills/<s>/references/*.md` is linked from that skill's SKILL.md — a
#      reference file nothing links to is never loaded, so content moved there to
#      slim a body has silently left the skill (v1.75.0)
#      — see the section comments below; the count above and this list have both been wrong
#      before, so keep all three in step: this header, the numbered sections, and the
#      success line at the bottom that names each check to the reader.
# Run in CI (engine-ci) and before cutting a release. Exit 1 on any gap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# VAULT_SCAN_SKIP_DIRS lives here; check 5 asserts the Python indexer agrees with it.
. "$SCRIPT_DIR/wiki-root-lib.sh" || { echo "lint-docs: missing wiki-root-lib.sh" >&2; exit 1; }
USAGE="$ROOT/USAGE.md"
[ -f "$USAGE" ] || { echo "lint-docs: no USAGE.md at $USAGE" >&2; exit 1; }

fail=0

# 1. every skill documented in USAGE.md
for d in "$ROOT"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  # MATCH THE DOCUMENTED FORM, not the bare word. This was an unanchored `grep -q "$name"`,
  # so a skill whose name is an ordinary word passed on any incidental mention: `drain`
  # matched "drainable" in an unrelated table row, and the gate reported full coverage for
  # a skill nobody had documented. Every skill is listed as a backticked name, so require
  # that — a substring match on a common word is the same class of false pass the engine
  # keeps finding elsewhere.
  if ! grep -qF -- "\`$name\`" "$USAGE"; then
    echo "lint-docs: skill '$name' is not documented in USAGE.md (add it to the Skills section)" >&2
    echo "lint-docs:   looked for the backticked name; an incidental mention of the bare" >&2
    echo "lint-docs:   word does not count as documentation." >&2
    fail=1
  fi
done

# 2. every engine-shipped file the docs reference exists (catch stale doc pointers)
#
# TWO SHAPES, THREE FILES — because this check read one file and matched one shape, and a
# reference escaped it by being more precise rather than less. `USAGE.md` credited the
# banner to `adopt.d/40-session-banner-hook.sh`, a step deleted at v1.13.0, and it survived
# 58 releases with this gate green every time: `/` and `.` are outside the bare-name class
# and the backtick is anchored, so a path-shaped reference produced no match at all — and
# neither does `bin/reflow.sh`, a file this rule exists to check, merely written with its
# directory. `SCHEMA.md` documents the same `bin/` surface in more depth and was never read.
#
# A gate that reports "no stale command references" identically whether it checked a
# reference or never saw it is the fail-open shape worth spending a few lines on.
#
# Bounded to the engine's OWN top-level directories on purpose. Docs legitimately name
# paths that do not exist in this repo — consumer-side (`~/.claude/spawn-session`),
# templated (`$WIKI/.wiki-gates.conf`), globbed — and a check that fails closed on correct
# prose gets weakened rather than fixed. Tokens carrying $, ~ or * are skipped for the same
# reason. The allow-list is a closed set: a NEW top-level directory falls outside it
# silently, which is this same gap one level up — so extend it when one is added.
doc_refs() {   # $1 = doc path; prints `owner|path` pairs to check, one per line
  local doc="$1" base
  base="$(basename "$doc")"
  # bare `<name>.sh` -> resolved under bin/, as this rule has always done
  grep -oE '`[a-z0-9_-]+\.sh`' "$doc" | tr -d '`' | sort -u | while read -r c; do
    printf '%s|bin/%s\n' "$base" "$c"
  done
  # `<engine-dir>/<path>` -> resolved from the repo root
  grep -oE '`(bin|skills|scaffold|adopt\.d|\.github)/[A-Za-z0-9._/-]+`' "$doc" | tr -d '`' | sort -u | while read -r r; do
    case "$r" in *'$'*|*'~'*|*'*'*) continue;; esac
    printf '%s|%s\n' "$base" "$r"
  done
}
for doc in "$USAGE" "$ROOT/SCHEMA.md" "$ROOT/README.md"; do
  [ -f "$doc" ] || continue
  while IFS='|' read -r where ref; do
    [ -n "$ref" ] || continue
    [ -e "$ROOT/$ref" ] || { echo "lint-docs: $where references $ref, which does not exist" >&2; fail=1; }
  done < <(doc_refs "$doc")
done

# 3. no engine-shipped skill or tool names a specific boundary VALUE ---------------
# SCHEMA.md: each consuming wiki declares its own boundary and the engine is
# boundary-agnostic. Two skills contradicted that by naming one — including inside a
# copy-me frontmatter template — and bin/crossover.sh rewrote every imported page to a
# hardcoded literal. The consequence was silent: a mis-stamped page passes the
# boundary-present gate, is committed and indexed, and is then dropped from semantic
# recall by rag-build's cross-boundary skip, with no message anywhere.
#
# DELIBERATELY NARROW: it matches the STAMPING form only — a `boundary:` key immediately
# followed by a bare token. Prose that enumerates the choice ("boundary (`personal` |
# `work`)"), the scaffolder's own --boundary enum, and the {{BOUNDARY}} placeholder are
# all legitimate and must keep passing. `boundary: generic` is excluded too: that is the
# engine-proposal handoff block's own domain marker, not a vault's boundary, and it has
# its own gate in engine-proposal.sh's scan. A broader rule would either flag every one of
# those or be loosened until it could no longer fail — which is the same defect class
# facing the other way. The limit is stated here rather than left to be discovered.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "lint-docs: $hit" >&2
  echo "lint-docs:   the engine must ask the vault for its boundary (bin/vault-boundary.sh)," >&2
  echo "lint-docs:   never name a value — a mis-stamped page vanishes from recall silently." >&2
  fail=1
done < <(cd "$ROOT" && grep -rnE '(^|[^a-zA-Z-])boundary:[[:space:]]*`?[a-z][a-z0-9-]*' \
           skills/ bin/ scaffold/ 2>/dev/null \
         | grep -vE '\{\{BOUNDARY\}\}|boundary:[[:space:]]*<' \
         | grep -vE 'boundary:[[:space:]]*generic' \
         | grep -vE '^bin/(vault-boundary|lint-docs|lint)\.sh:' || true)

# 4. a worktree-taking skill must name CANONICAL where it touches git-ignored state ------
# A worktree checks out TRACKED files only. So a step aimed at git-ignored per-machine
# state from inside `$WORK` finds an empty directory, correctly reports nothing to do, and
# exits clean — fail-open, and invisible: the state is git-ignored, so its growth never
# appears in `git status`, a diff, or any gate. checkpoint's `raw/sessions` prune ran that
# way for five weeks after the buffer was untracked, pruning nothing, while the section
# one below it (`.rag/`) named canonical explicitly and stayed correct.
#
# "Missing" is exactly what the wrong tree looks like, so no presence test can catch this;
# the only mechanical signal is whether the step NAMES the tree it means. Scoped to skills
# that actually take a worktree — elsewhere there is no second tree to be wrong about.
ignored_tokens="$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/scaffold/gitignore.tmpl" 2>/dev/null \
  | sed 's#/\*\.md$#/#' \
  | grep -vE '^(\.worktrees/?|\.DS_Store)$' || true)"
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  grep -q 'vault-worktree\.sh ensure' "$f" || continue
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      case "$hit" in *'$WIKI_PATH'*) continue ;; esac
      echo "lint-docs: skills/$(basename "$(dirname "$f")")/SKILL.md:${hit%%:*} names '$tok' without naming canonical \$WIKI_PATH" >&2
      echo "lint-docs:   that path is git-ignored, so it exists ONLY in canonical — a step" >&2
      echo "lint-docs:   pointed at \$WORK finds it empty and reports success having done nothing." >&2
      fail=1
    done < <(grep -nF -- "$tok" "$f" || true)
  done <<< "$ignored_tokens"
done

# 5. every vault walk uses the shared exclusion ------------------------------------------
# THE DEFECT THIS CLOSES was four private copies of one prune list: `.git`, `engine`,
# `.obsidian`, `.rag` — and, in one of five, `.worktrees`. The four that omitted it walked
# every page of every live session worktree as vault content, so the verified-status report
# double-counted repo pages, the umbrella lint ran its per-page gates against another
# branch's checkout, a memory `[[link]]` resolved because some OTHER branch had the target,
# and the migration sweep would have rewritten files in a checkout its session did not
# author. None of it reproduces in a quiet vault, which is why it survived.
#
# Adding the missing name to four lists would leave the fifth tool — the one nobody has
# written yet — to copy whichever list it happens to see. So the list moved into
# wiki-root-lib.sh and this gate keeps it the only one: a walk rooted at a vault must call
# vault_pages / vault_grep_excludes, not hand-roll a prune.
while IFS= read -r hit; do
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  case "$f" in */wiki-root-lib.sh) continue;; esac        # the definition itself
  echo "lint-docs: ${f#$ROOT/}:$ln walks a vault with its own prune list" >&2
  echo "lint-docs:   use vault_pages (or vault_grep_excludes for a recursive grep) from" >&2
  echo "lint-docs:   wiki-root-lib.sh — a private copy is how .worktrees went unexcluded in" >&2
  echo "lint-docs:   four of five walks, silently, for as long as no session was open." >&2
  fail=1
done < <(grep -rn -- '-name \.obsidian' "$ROOT/bin" 2>/dev/null || true)

while IFS= read -r hit; do
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  echo "lint-docs: ${f#$ROOT/}:$ln greps a vault recursively without the shared excludes" >&2
  echo "lint-docs:   add \$(vault_grep_excludes) — a bare grep -r descends into .worktrees," >&2
  echo "lint-docs:   and a sweep that WRITES would edit another session's checkout." >&2
  fail=1
done < <(grep -rn -- 'grep -r[a-z]* --include=.\*\.md.\+"\$\(VAULT\|WIKI\)"' "$ROOT/bin" 2>/dev/null \
         | grep -v 'vault_grep_excludes' || true)

# The Python indexer skips the CLASS rather than a list — every name in
# VAULT_SCAN_SKIP_DIRS is either `engine` or a dot-directory, and python's own walk plus an
# explicit dot-prefix test covers the second group without enumerating it. That is stronger
# than list-equality (it cannot miss the next dot-directory), so assert the RULE: the walk
# must skip `engine` and anything dot-prefixed. Asserting the old list here would fail a
# correct implementation, which is its own kind of broken gate.
py_walk="$(grep -n 'SKIP_NAMES' "$ROOT/bin/rag-build.sh" 2>/dev/null || true)"
[ -n "$py_walk" ] \
  || { echo "lint-docs: rag-build.sh has no SKIP_NAMES — the indexer's skip rule is gone" >&2; fail=1; }
printf '%s' "$py_walk" | grep -q 'startswith(".")' \
  || { echo "lint-docs: rag-build.sh does not skip dot-directories by class" >&2; \
       echo "lint-docs:   an enumerated list is how .worktrees/ went unskipped — a full" >&2; \
       echo "lint-docs:   checkout of every page, indexed a second time under paths that" >&2; \
       echo "lint-docs:   vanish when the worktree is retired." >&2; fail=1; }
case " $VAULT_SCAN_SKIP_DIRS " in
  *" engine "*) ;;
  *) echo "lint-docs: VAULT_SCAN_SKIP_DIRS no longer names 'engine'; the two walks have diverged" >&2; fail=1;;
esac

# 6. every documented hook snippet states a timeout -------------------------------------
# A hook that names no `timeout` inherits the HOST's window, which the engine does not
# choose and does not learn about: a SessionEnd hook was observed cancelled at about one
# second, and `rag-capture.sh` at a workspace root takes seconds. The failure is fail-open
# and silent — the hook stays wired, the script never reaches its own output, and the empty
# buffer reads as a quiet month. Copy-paste is how a snippet becomes a machine's real
# wiring, so the snippet is the artifact that has to be right.
#
# Scoped to the LIVE docs only: CHANGELOG.md is history and must never be rewritten to suit
# a later rule, and proposals/ quote a reporter's observed settings verbatim, which is
# evidence rather than a recommendation.
timeout_hits="$(
  for f in "$ROOT"/*.md "$ROOT"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    # Leading `(` on purpose: a case pattern's bare `)` is unbalanced to bash's parser
    # INSIDE a `$( )`, which makes everything after it read as unquoted — the fence
    # backticks below then look like a command substitution nobody closed.
    case "$(basename "$f")" in (CHANGELOG.md) continue;; esac
    # A fence must START the line. USAGE.md quotes a fence mid-sentence inside a table
    # cell, and counting that one flips the open/closed state for the whole rest of the
    # file — which is how the first version of this gate read the real hook snippet as
    # prose and passed a doc that had no timeout at all.
    awk -v file="${f#$ROOT/}" '
      /^[[:space:]]*```/ {
        if (inblk && blk ~ /"type"[[:space:]]*:[[:space:]]*"command"/ && blk !~ /"timeout"/) print file ":" start
        inblk = !inblk; blk = ""; if (inblk) start = NR + 1; next }
      inblk { blk = blk $0 "\n" }
    ' "$f"
  done
)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "lint-docs: $hit documents a hook command with no \"timeout\"" >&2
  echo "lint-docs:   the host cancels a hook that outruns its own default window, and a" >&2
  echo "lint-docs:   cancelled hook is silent — an empty capture buffer looks like a quiet" >&2
  echo "lint-docs:   month. State the budget in the snippet people copy." >&2
  fail=1
done <<< "$timeout_hits"

# 7. a defect-report template's Expected-versus-fix rule is sited on BOTH surfaces --------
# A skill that drives a handoff has two audiences in one file, and a rule written once lands
# in whichever half its author was thinking about. The rule that catches the most common way
# an `Expected:` goes wrong — the suggested fix beside it cannot produce it — sat only in the
# INTAKE section, which is addressed to the maintainer receiving the report. The reporter
# never reads it, so the check was applied only after submission, by the reader who pays a
# round trip to discover it. The gap is asymmetric rather than absent, which is exactly why
# reading the skill end-to-end does not reveal it: every clause a reporter needs exists
# somewhere, and this one is in the half they are not the audience for.
#
# ASSERTS THE PROPERTY, NOT THE WORDING. Two things must hold, and neither pins a sentence:
# the template's own `Expected:` field must point at the fix, and the rule must appear in at
# least TWO sections — single-siting is the whole defect, so a rewrite that keeps both sites
# passes and a rewrite that drops either one goes red. Keyed off any SKILL.md that ships a
# defect-report template, not off one skill by name, so the next such template inherits it.
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rel="skills/$(basename "$(dirname "$f")")/SKILL.md"

  # The template is a fenced block that asks for BOTH an Expected and a suggested fix.
  # A skill shipping no such block has nothing to be asymmetric about, and is skipped.
  tmpl="$(awk '
    /^[[:space:]]*```/ {
      if (inb && blk ~ /(^|\n)Expected:/ && blk ~ /Suggested fix/) printf "%s", blk
      inb = !inb; blk = ""; next }
    inb { blk = blk $0 "\n" }
  ' "$f")"
  [ -n "$tmpl" ] || continue

  # (a) the template's own Expected FIELD — the line plus its indented continuation, up to
  # the next field at column 0 — must relate itself to the fix. The field is what a reporter
  # fills in; a bare placeholder there is the version that shipped the defect.
  exp_field="$(printf '%s' "$tmpl" | awk '/^Expected:/ { inx = 1; print; next } inx && /^[^ \t]/ { exit } inx { print }')"
  if ! printf '%s' "$exp_field" | grep -qi 'fix'; then
    echo "lint-docs: $rel's defect-report template asks for 'Expected:' without relating it to the suggested fix" >&2
    echo "lint-docs:   the two are separate fields, so nothing makes the reporter compare them —" >&2
    echo "lint-docs:   and an Expected the fix cannot produce is the most common way one goes wrong." >&2
    fail=1
  fi

  # (b) the rule must be sited in at least two sections. Prose only: a fence is a template
  # or a quoted example, not a surface that instructs anyone.
  sites="$(awk '
    /^[[:space:]]*```/ { inb = !inb; next }
    inb { next }
    /^## / { sec = $0; next }
    /Expected/ && /fix/ { if (!(sec in seen)) { seen[sec] = 1; n++ } }
    END { print n + 0 }
  ' "$f")"
  if [ "$sites" -lt 2 ]; then
    echo "lint-docs: $rel sites the Expected-versus-fix rule in $sites section(s); both ends of the handoff need it" >&2
    echo "lint-docs:   the intake half is addressed to the maintainer, so a reporter never reads it." >&2
    echo "lint-docs:   Sited there alone, the check runs only after submission — one round trip late." >&2
    fail=1
  fi
done

# 8. every skill description fits the host router's cut -----------------------------------
# The host presents each skill's `description:` to its routing step truncated at roughly
# 1536 characters. The description is the routing surface, and its shape is what/when,
# `Triggers:`, then `Distinct from` and `NOT for` — so the clauses that fall past the cut
# are exactly the exclusions, and the skill keeps routing on its positive triggers while
# the rules that hand a case to a sibling silently stop applying. Measured at v1.73.4:
# three descriptions at 2446 / 1982 / 1845 characters, every `NOT for` past the cut, and
# nothing here read the length — the generator read `description:` only to render it.
#
# Two tiers, both against the VALUE (the `description: ` prefix stripped — measuring the
# raw line shifts every number by exactly 13 and the two sets look like a disagreement):
# error above DESC_MAX (1500, a margin under the cut), warning above DESC_WARN (1400) so a
# description creeping toward the cut is named before it crosses. A description over the
# budget is not shortened here — which clauses survive is the skill author's call.
DESC_MAX=1500
DESC_WARN=1400
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rel="skills/$(basename "$(dirname "$f")")/SKILL.md"
  len="$(awk '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && /^description:/ { sub(/^description:[ \t]*/, ""); print length($0); exit }
  ' "$f")"
  [ -n "$len" ] || { echo "lint-docs: $rel has no description: — the router has nothing to match" >&2; fail=1; continue; }
  if [ "$len" -gt "$DESC_MAX" ]; then
    echo "lint-docs: $rel description is $len characters; the router cuts at ~1536, so anything past $DESC_MAX is unseen at routing time" >&2
    echo "lint-docs:   the clauses that fall off are 'Distinct from' / 'NOT for' — move rationale to the body, keep the exclusions" >&2
    fail=1
  elif [ "$len" -gt "$DESC_WARN" ]; then
    echo "lint-docs: warning: $rel description is $len characters (budget $DESC_MAX; the router cuts at ~1536)" >&2
  fi
done

# 9. every references/ file is linked from its skill body -----------------------------------
# A skill body is loaded whole on every invocation; a `references/` file is loaded only when
# the body links to it. Moving history and worked examples out of a body to keep it under
# budget is therefore only a move if the body still points at the file — otherwise the
# content has silently left the skill, and nothing reports it. The link is matched as the
# path `references/<name>` in prose or a markdown link; a mention inside a code fence is a
# quoted example and does not count.
for d in "$ROOT"/skills/*/references; do
  [ -d "$d" ] || continue
  skill="$(basename "$(dirname "$d")")"
  body="$ROOT/skills/$skill/SKILL.md"
  for r in "$d"/*.md; do
    [ -f "$r" ] || continue
    name="$(basename "$r")"
    if ! awk '/^[[:space:]]*```/ { inb = !inb; next } !inb' "$body" | grep -qF "references/$name"; then
      echo "lint-docs: skills/$skill/references/$name is linked from nowhere in skills/$skill/SKILL.md" >&2
      echo "lint-docs:   a reference file the body never points at is never loaded — the content has left the skill" >&2
      fail=1
    fi
  done
done

if [ "$fail" -eq 0 ]; then
  echo "lint-docs: all skills documented; no stale doc references in USAGE/SCHEMA/README, bare or path-shaped; no hardcoded boundary values; worktree skills name canonical for ignored state; every vault walk uses the shared exclusion; every documented hook states a timeout; every defect-report template relates Expected to the fix on both surfaces; every skill description fits the router's cut; every references/ file is linked from its skill"
fi
exit "$fail"
