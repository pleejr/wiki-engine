#!/usr/bin/env bash
# new-wiki.sh — scaffold a new LLM-Wiki that consumes this wiki-engine.
#
# Run from a standalone clone of wiki-engine, e.g.:
#   ./bin/new-wiki.sh --path ~/Documents/repos/work-wiki --name work-wiki \
#                     --boundary work --email you@company.com --git-name "Your Name"
#
# Creates the vault repo, records this engine's release in .engine-version, renders the
# scaffold templates, seeds node folders, and hands machine wiring to wire-machine.sh. The
# engine itself reaches sessions as the wiki-engine Claude Code plugin. It does NOT touch
# settings.json, your shell rc, ~/.claude/CLAUDE.md, or create any remote unless asked —
# those are printed as next steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VAULT_PATH="" WIKI_NAME="" BOUNDARY="" GIT_EMAIL="" GIT_NAME="" RAG=1
WIRE_ENV=0 WIRE_SHELL=0 SHELL_RC="" WIRE_CLAUDE_MD=0 WIRE_STATUSLINE=0 REMOTE_URL="" CREATE_REMOTE="" VISIBILITY="private"

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
  --no-rag           skip provisioning the self-contained semantic-recall runtime

Machine wiring (opt-in; safe on a dedicated single-vault machine — idempotent):
  --wire-env         set "env": {"WIKI_PATH": <path>} in settings.json (recommended)
  --wire-shell [RC]  append `export WIKI_PATH=<path>` to RC (default: ~/.zshrc);
                     skipped with a warning if WIKI_PATH is already exported there
  --wire-claude-md   append `@<path>/CLAUDE.md` to ~/.claude/CLAUDE.md (always-on router)
  --wire-statusline  set the engine status line, unless a foreign one is set
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
    --no-rag) RAG=0; shift;;
    --wire-shell) WIRE_SHELL=1
      case "${2:-}" in ""|--*) SHELL_RC="$HOME/.zshrc"; shift;; *) SHELL_RC="$2"; shift 2;; esac;;
    --wire-env) WIRE_ENV=1; shift;;
    --wire-claude-md) WIRE_CLAUDE_MD=1; shift;;
    --wire-statusline) WIRE_STATUSLINE=1; shift;;
    --remote) REMOTE_URL="$2"; shift 2;;
    --create-remote) CREATE_REMOTE="$2"; shift 2;;
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
# shellcheck disable=SC2088  # a LITERAL leading ~/ is what this expands by hand
case "$VAULT_PATH" in "~/"*) VAULT_PATH="$HOME/${VAULT_PATH#\~/}";; esac

. "$SCRIPT_DIR/plugin-lib.sh"
ENGINE_VERSION="$(engine_release "$ENGINE_ROOT")"
# Vault CI checks out what .engine-version names, so it must be a release tag. From a
# checkout past a tag (v2.0.0-3-gabc1234, a development run) record that base tag and say so.
case "$ENGINE_VERSION" in
  v[0-9]*.[0-9]*.[0-9]*-[0-9]*-g*)
    echo "note: this engine is $ENGINE_VERSION, past a release; recording ${ENGINE_VERSION%-*-g*}" >&2
    ENGINE_VERSION="${ENGINE_VERSION%-*-g*}" ;;
esac
# A checkout with no tags in reach (a shallow CI clone) describes itself as a bare sha; the
# manifest still names the release it belongs to.
case "$ENGINE_VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) mv="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$ENGINE_ROOT/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
     [ -n "$mv" ] || { echo "error: cannot tell which release this engine is ($ENGINE_VERSION) — scaffold from a tagged checkout or the plugin" >&2; exit 1; }
     echo "note: this engine is $ENGINE_VERSION with no tag in reach; recording its manifest release v$mv" >&2
     ENGINE_VERSION="v$mv" ;;
esac

if [ "$BOUNDARY" = "personal" ]; then OTHER="work"; else OTHER="personal"; fi
BOUNDARY_CAP="$(printf '%s' "$BOUNDARY" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
DATE="$(date +%Y-%m-%d)"

echo "Scaffolding '$WIKI_NAME' (boundary: $BOUNDARY) at $VAULT_PATH"
echo "  engine: $ENGINE_VERSION"

mkdir -p "$VAULT_PATH"
git -C "$VAULT_PATH" init -q -b main
git -C "$VAULT_PATH" config user.email "$GIT_EMAIL"
[ -n "$GIT_NAME" ] && git -C "$VAULT_PATH" config user.name "$GIT_NAME"

printf '%s\n' "$ENGINE_VERSION" > "$VAULT_PATH/.engine-version"

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
# CI checks out the release .engine-version names into engine/ and lints the vault with it.
mkdir -p "$VAULT_PATH/.github/workflows"
cp "$ENGINE_ROOT/scaffold/vault-gate.yml" "$VAULT_PATH/.github/workflows/gate.yml"

# Seed the skills catalog from the engine's actual skills so a fresh vault matches
# whatever skill set this engine release ships (the template block is just a placeholder).
"$ENGINE_ROOT/bin/gen-skills-index.sh" --wiki "$VAULT_PATH" >/dev/null

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

# --- machine wiring (delegated to the idempotent converge verb) ------------------
# wire-machine.sh is the single source of wiring truth — WIKI_PATH, the always-on
# CLAUDE.md import, the status line, the .rag recall runtime, and vault adoption.
# It is re-run-safe, so `wiki-adopt` reuses it to bring a second machine up from a clone.
WIRE_ARGS=(--wiki "$VAULT_PATH")
[ "$RAG" -eq 1 ] || WIRE_ARGS+=(--no-rag)
if [ "$WIRE_SHELL" -eq 1 ]; then WIRE_ARGS+=(--wire-shell "$SHELL_RC"); fi
if [ "$WIRE_ENV" -eq 1 ]; then WIRE_ARGS+=(--wire-env); fi
if [ "$WIRE_CLAUDE_MD" -eq 1 ]; then WIRE_ARGS+=(--wire-claude-md); fi
if [ "$WIRE_STATUSLINE" -eq 1 ]; then WIRE_ARGS+=(--wire-statusline); fi
"$ENGINE_ROOT/bin/wire-machine.sh" "${WIRE_ARGS[@]}"

cat <<EOF

Done. $WIKI_NAME is a git repo recording wiki-engine $ENGINE_VERSION in .engine-version.
EOF

[ -n "$REMOTE_DONE" ] && echo "  remote: $REMOTE_DONE"
echo "  (machine wiring reported above by wire-machine)"

echo
echo "Next steps:"
n=1
if [ -z "$REMOTE_DONE" ]; then
  echo "  $n. Add a remote and push:"
  echo "       git -C \"$VAULT_PATH\" remote add origin <url>"
  echo "       git -C \"$VAULT_PATH\" push -u origin main"; n=$((n+1))
fi
echo "  $n. Seed the vault from your existing environment (memories, repos, projects):"
echo "       run the 'wiki-onboard' skill in a Claude Code session with WIKI_PATH set."
