#!/usr/bin/env bash
# new-wiki.sh — scaffold a new LLM-Wiki that consumes this wiki-engine.
#
# Run from a standalone clone of wiki-engine, e.g.:
#   ./bin/new-wiki.sh --path ~/Documents/repos/work-wiki --name work-wiki \
#                     --boundary work --email you@company.com --git-name "Your Name"
#
# Creates the vault repo, pins wiki-engine as the engine/ submodule, renders the
# scaffold templates, seeds node folders, and (by default) symlinks the skills
# into ~/.claude/skills. It does NOT touch your shell rc, ~/.claude/CLAUDE.md, or
# create any remote — those are printed as next steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VAULT_PATH="" WIKI_NAME="" BOUNDARY="" GIT_EMAIL="" GIT_NAME="" ENGINE_URL="" LINK_SKILLS=1 RAG=1
WIRE_SHELL=0 SHELL_RC="" WIRE_CLAUDE_MD=0 REMOTE_URL="" CREATE_REMOTE="" VISIBILITY="private" PUSH=0

usage() {
  cat <<'USAGE'
Usage: new-wiki.sh --path DIR --boundary personal|work --email EMAIL [options]

Required (prompted for if omitted and running interactively):
  --path DIR         where to create the vault (must not exist)
  --boundary B          personal | work  (sets the boundary + frontmatter)
  --email EMAIL      git identity for this vault

Options:
  --name NAME        wiki name (default: basename of --path)
  --git-name NAME    git user.name for this vault
  --engine-url URL   engine submodule source (default: this clone's origin)
  --no-link-skills   skip symlinking ~/.claude/skills/* -> engine skills
  --no-rag           skip provisioning the self-contained semantic-recall runtime

Machine wiring (opt-in; safe on a dedicated single-vault machine — idempotent):
  --wire-shell [RC]  append `export WIKI_PATH=<path>` to RC (default: ~/.zshrc);
                     skipped with a warning if WIKI_PATH is already exported there
  --wire-claude-md   append `@<path>/CLAUDE.md` to ~/.claude/CLAUDE.md (always-on router)
  --remote URL       add `origin` = URL, then push main
  --create-remote SLUG   create the remote via `gh` (OWNER/NAME) and push
  --visibility V     private | public | internal for --create-remote (default: private)
  -h, --help         show this
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --path) VAULT_PATH="$2"; shift 2;;
    --name) WIKI_NAME="$2"; shift 2;;
    --boundary) BOUNDARY="$2"; shift 2;;
    --email) GIT_EMAIL="$2"; shift 2;;
    --git-name) GIT_NAME="$2"; shift 2;;
    --engine-url) ENGINE_URL="$2"; shift 2;;
    --no-link-skills) LINK_SKILLS=0; shift;;
    --no-rag) RAG=0; shift;;
    --wire-shell) WIRE_SHELL=1
      case "${2:-}" in ""|--*) SHELL_RC="$HOME/.zshrc"; shift;; *) SHELL_RC="$2"; shift 2;; esac;;
    --wire-claude-md) WIRE_CLAUDE_MD=1; shift;;
    --remote) REMOTE_URL="$2"; PUSH=1; shift 2;;
    --create-remote) CREATE_REMOTE="$2"; PUSH=1; shift 2;;
    --visibility) VISIBILITY="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 1;;
  esac
done

# Interactive fill-in for the required args when running on a terminal.
if [ -t 0 ]; then
  while [ -z "$VAULT_PATH" ]; do read -r -p "Vault path (must not exist): " VAULT_PATH || true; done
  while [ -z "$BOUNDARY" ]; do read -r -p "Boundary (personal|work): " BOUNDARY || true; done
  while [ -z "$GIT_EMAIL" ]; do read -r -p "Git email for this vault: " GIT_EMAIL || true; done
  [ -n "$GIT_NAME" ] || read -r -p "Git name (optional): " GIT_NAME || true
fi

[ -n "$VAULT_PATH" ] || { echo "error: --path required" >&2; exit 1; }
[ -n "$GIT_EMAIL" ] || { echo "error: --email required" >&2; exit 1; }
[ -e "$VAULT_PATH" ] && { echo "error: $VAULT_PATH already exists" >&2; exit 1; }
case "$BOUNDARY" in personal|work) ;; *) echo "error: --boundary must be 'personal' or 'work'" >&2; exit 1;; esac
case "$VISIBILITY" in private|public|internal) ;; *) echo "error: --visibility must be private|public|internal" >&2; exit 1;; esac
[ -n "$WIKI_NAME" ] || WIKI_NAME="$(basename "$VAULT_PATH")"
# Expand a leading ~ that survives when --path is quoted.
case "$VAULT_PATH" in "~/"*) VAULT_PATH="$HOME/${VAULT_PATH#\~/}";; esac

if [ -z "$ENGINE_URL" ]; then
  ENGINE_URL="$(git -C "$ENGINE_ROOT" remote get-url origin 2>/dev/null || echo "$ENGINE_ROOT")"
fi

if [ "$BOUNDARY" = "personal" ]; then OTHER="work"; else OTHER="personal"; fi
BOUNDARY_CAP="$(printf '%s' "$BOUNDARY" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
DATE="$(date +%Y-%m-%d)"

echo "Scaffolding '$WIKI_NAME' (boundary: $BOUNDARY) at $VAULT_PATH"
echo "  engine: $ENGINE_URL"

mkdir -p "$VAULT_PATH"
git -C "$VAULT_PATH" init -q -b main
git -C "$VAULT_PATH" config user.email "$GIT_EMAIL"
[ -n "$GIT_NAME" ] && git -C "$VAULT_PATH" config user.name "$GIT_NAME"

git -C "$VAULT_PATH" submodule add -q "$ENGINE_URL" engine

while IFS= read -r d; do
  case "$d" in ''|'#'*) continue;; esac
  mkdir -p "$VAULT_PATH/$d"
  touch "$VAULT_PATH/$d/.gitkeep"
done < "$ENGINE_ROOT/scaffold/node-dirs.txt"

render() {
  sed -e "s|{{WIKI_NAME}}|$WIKI_NAME|g" \
      -e "s|{{BOUNDARY}}|$BOUNDARY|g" \
      -e "s|{{BOUNDARY_CAP}}|$BOUNDARY_CAP|g" \
      -e "s|{{OTHER}}|$OTHER|g" \
      -e "s|{{GIT_EMAIL}}|$GIT_EMAIL|g" \
      -e "s|{{DATE}}|$DATE|g" \
      "$1"
}
render "$ENGINE_ROOT/scaffold/CLAUDE.md.tmpl"  > "$VAULT_PATH/CLAUDE.md"
render "$ENGINE_ROOT/scaffold/index.md.tmpl"   > "$VAULT_PATH/index.md"
render "$ENGINE_ROOT/scaffold/log.md.tmpl"     > "$VAULT_PATH/log.md"
render "$ENGINE_ROOT/scaffold/README.md.tmpl"  > "$VAULT_PATH/README.md"
render "$ENGINE_ROOT/scaffold/gitignore.tmpl"  > "$VAULT_PATH/.gitignore"

# Seed the skills catalog from the engine's actual skills so a fresh vault matches
# whatever skill set this engine pins (the template block is just a placeholder).
"$ENGINE_ROOT/bin/gen-skills-index.sh" --wiki "$VAULT_PATH" >/dev/null

if [ "$LINK_SKILLS" -eq 1 ]; then
  mkdir -p "$HOME/.claude/skills"
  for s in "$ENGINE_ROOT"/skills/*/; do
    name="$(basename "$s")"
    ln -sfn "$ENGINE_ROOT/skills/$name" "$HOME/.claude/skills/$name"
  done
  echo "  linked ~/.claude/skills/* -> $ENGINE_ROOT/skills/ (all engine skills)"
fi

git -C "$VAULT_PATH" add -A
git -C "$VAULT_PATH" commit -q -m "Scaffold $WIKI_NAME from wiki-engine (boundary: $BOUNDARY)"

# --- optional git remote --------------------------------------------------------
REMOTE_DONE=""
if [ -n "$CREATE_REMOTE" ]; then
  if command -v gh >/dev/null 2>&1; then
    gh repo create "$CREATE_REMOTE" "--$VISIBILITY" --source "$VAULT_PATH" --remote origin --push
    REMOTE_DONE="created $CREATE_REMOTE ($VISIBILITY) and pushed"
  else
    echo "  ! --create-remote needs the 'gh' CLI (not found) — skipped." >&2
  fi
elif [ -n "$REMOTE_URL" ]; then
  git -C "$VAULT_PATH" remote add origin "$REMOTE_URL"
  git -C "$VAULT_PATH" push -u -q origin main && REMOTE_DONE="pushed to $REMOTE_URL"
fi

# --- optional machine wiring (idempotent; single-vault machines only) ------------
WIRE_DONE=()
if [ "$WIRE_SHELL" -eq 1 ]; then
  LINE="export WIKI_PATH=\"$VAULT_PATH\""
  if [ -f "$SHELL_RC" ] && grep -q '^[[:space:]]*export WIKI_PATH=' "$SHELL_RC"; then
    echo "  ! $SHELL_RC already exports WIKI_PATH — left as-is (edit by hand if it should point here)." >&2
  else
    printf '\n# wiki-engine vault\n%s\n' "$LINE" >> "$SHELL_RC"
    WIRE_DONE+=("WIKI_PATH -> $SHELL_RC (open a new shell)")
  fi
fi
if [ "$WIRE_CLAUDE_MD" -eq 1 ]; then
  CMD="$HOME/.claude/CLAUDE.md"; IMPORT="@$VAULT_PATH/CLAUDE.md"
  mkdir -p "$HOME/.claude"
  if [ -f "$CMD" ] && grep -qF "$IMPORT" "$CMD"; then
    echo "  ! $CMD already imports this vault — left as-is." >&2
  else
    printf '\n%s\n' "$IMPORT" >> "$CMD"
    WIRE_DONE+=("always-on import -> $CMD")
  fi
fi

# Self-contained semantic recall: provision the vault's .rag/venv CPU embedder and
# build the initial index. Git-ignored (.rag/), non-fatal (a locked-down/offline
# laptop still gets a working vault; run engine/bin/rag-setup.sh later).
RAG_READY=0
if [ "$RAG" -eq 1 ]; then
  echo "Provisioning semantic recall (self-contained CPU embedder)…"
  if "$ENGINE_ROOT/bin/rag-setup.sh" --wiki "$VAULT_PATH"; then
    "$ENGINE_ROOT/bin/rag-build.sh" --wiki "$VAULT_PATH" || true
    RAG_READY=1
  else
    echo "  ! rag-setup failed (offline or pip restricted) — skipped." >&2
    echo "    Provision later with: $VAULT_PATH/engine/bin/rag-setup.sh" >&2
  fi
fi

cat <<EOF

Done. $WIKI_NAME is a git repo pinning wiki-engine at:
  $(git -C "$VAULT_PATH/engine" rev-parse --short HEAD)
EOF

[ -n "$REMOTE_DONE" ] && echo "  remote: $REMOTE_DONE"
if [ "${#WIRE_DONE[@]}" -gt 0 ]; then
  echo "  wired:"
  for w in "${WIRE_DONE[@]}"; do echo "    - $w"; done
fi

echo
echo "Next steps (not automated — machine/user choices):"
n=1
if [ "$WIRE_SHELL" -ne 1 ]; then
  echo "  $n. Set the vault path for the skills:"
  echo "       export WIKI_PATH=\"$VAULT_PATH\"      # add to ~/.zshrc or ~/.bashrc"; n=$((n+1))
fi
if [ "$WIRE_CLAUDE_MD" -ne 1 ]; then
  echo "  $n. Wire the agent entry point — add to ~/.claude/CLAUDE.md:"
  echo "       @$VAULT_PATH/CLAUDE.md"; n=$((n+1))
fi
if [ -z "$REMOTE_DONE" ]; then
  echo "  $n. Add a remote and push:"
  echo "       git -C \"$VAULT_PATH\" remote add origin <url>"
  echo "       git -C \"$VAULT_PATH\" push -u origin main"; n=$((n+1))
fi
echo "  $n. Seed the empty vault from your existing environment (memories, repos, projects):"
echo "       run the 'wiki-onboard' skill in a Claude Code session with WIKI_PATH set,"
echo "       or just run the 'wiki-adopt' skill which drives this whole flow end to end."

if [ "$RAG_READY" -eq 1 ]; then
  echo "  Semantic recall is ready (self-contained .rag/venv); wiki-context auto-recalls."
  echo "  It re-indexes on checkpoint; rebuild manually with engine/bin/rag-build.sh."
fi
