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

VAULT_PATH="" WIKI_NAME="" BOUNDARY="" GIT_EMAIL="" GIT_NAME="" ENGINE_URL="" LINK_SKILLS=1

usage() {
  cat <<'USAGE'
Usage: new-wiki.sh --path DIR --boundary personal|work --email EMAIL [options]

Required:
  --path DIR         where to create the vault (must not exist)
  --boundary B          personal | work  (sets the boundary + frontmatter)
  --email EMAIL      git identity for this vault

Options:
  --name NAME        wiki name (default: basename of --path)
  --git-name NAME    git user.name for this vault
  --engine-url URL   engine submodule source (default: this clone's origin)
  --no-link-skills   skip symlinking ~/.claude/skills/* -> engine skills
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
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 1;;
  esac
done

[ -n "$VAULT_PATH" ] || { echo "error: --path required" >&2; exit 1; }
[ -n "$GIT_EMAIL" ] || { echo "error: --email required" >&2; exit 1; }
[ -e "$VAULT_PATH" ] && { echo "error: $VAULT_PATH already exists" >&2; exit 1; }
case "$BOUNDARY" in personal|work) ;; *) echo "error: --boundary must be 'personal' or 'work'" >&2; exit 1;; esac
[ -n "$WIKI_NAME" ] || WIKI_NAME="$(basename "$VAULT_PATH")"

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

for d in memory notes concepts entities repos projects comparisons queries \
         raw/articles raw/papers raw/transcripts raw/assets; do
  mkdir -p "$VAULT_PATH/$d"
  touch "$VAULT_PATH/$d/.gitkeep"
done

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

cat <<EOF

Done. $WIKI_NAME is a git repo pinning wiki-engine at:
  $(git -C "$VAULT_PATH/engine" rev-parse --short HEAD)

Next steps (not automated — machine/user choices):
  1. Set the vault path for the skills:
       export WIKI_PATH="$VAULT_PATH"      # add to ~/.zshrc or ~/.bashrc
  2. Wire the agent entry point — add to ~/.claude/CLAUDE.md:
       @$VAULT_PATH/CLAUDE.md
  3. Add a remote and push:
       git -C "$VAULT_PATH" remote add origin <url>
       git -C "$VAULT_PATH" push -u origin main
  4. Seed the empty vault from your existing environment (memories, repos, projects):
       run the 'wiki-onboard' skill in a Claude Code session with WIKI_PATH set.
EOF
