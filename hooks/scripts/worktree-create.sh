#!/usr/bin/env bash
# worktree-create.sh — Creates a jj workspace for Claude Code's worktree mechanism.
# Called as a WorktreeCreate hook. Reads hook input JSON ({"name": ..., "cwd": ...}) from stdin.
# Prints the absolute path of the new workspace on stdout; everything else goes to stderr.
# This hook replaces Claude Code's built-in worktree creation everywhere the plugin is
# installed, so outside jj repos it falls back to a plain git worktree.

set -euo pipefail

INPUT=$(cat)
field() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1') or '')" <<<"$INPUT"; }
NAME=$(field name)
CWD=$(field cwd)
CWD="${CWD:-$PWD}"

if [ -z "$NAME" ]; then
  echo "WorktreeCreate: no 'name' in hook input" >&2
  exit 1
fi

# cd rather than -R: -R only accepts the workspace root, and Claude may be in a subdirectory
if ROOT=$(cd "$CWD" && jj workspace root 2>/dev/null); then
  DIR="$ROOT/.claude/worktrees/$NAME"
  mkdir -p "$(dirname "$DIR")"
  # Default parents: the new @ is a sibling of the current @ (on @-), not its child.
  # Basing it on @ would rebase the workspace (making it stale) on every edit in the main one.
  jj -R "$ROOT" workspace add "$DIR" --name "${NAME//\//-}" >&2
elif ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  # Not a jj repo: mirror Claude Code's default (worktree-<name> branch under .claude/worktrees)
  DIR="$ROOT/.claude/worktrees/$NAME"
  mkdir -p "$(dirname "$DIR")"
  git -C "$ROOT" worktree add -b "worktree-${NAME//\//-}" "$DIR" HEAD >&2
else
  echo "WorktreeCreate: $CWD is neither a jj nor a git repository" >&2
  exit 1
fi

echo "$DIR"
