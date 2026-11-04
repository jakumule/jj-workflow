#!/usr/bin/env bash
# worktree-create.sh — Creates a jj workspace for Claude Code's worktree mechanism.
# Called as a WorktreeCreate hook. Reads hook input JSON ({"name": ..., "cwd": ...}) from stdin.
# Prints the absolute path of the new workspace on stdout; everything else goes to stderr.

set -euo pipefail

INPUT=$(cat)
field() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1') or '')" <<<"$INPUT"; }
NAME=$(field name)
CWD=$(field cwd)

if [ -z "$NAME" ]; then
  echo "WorktreeCreate: no 'name' in hook input" >&2
  exit 1
fi

ROOT=$(jj -R "${CWD:-$PWD}" workspace root)
DIR="$ROOT/.claude/worktrees/$NAME"
mkdir -p "$(dirname "$DIR")"

# --revision @ gives the workspace a fresh empty change on top of the current @
jj -R "$ROOT" workspace add "$DIR" --name "${NAME//\//-}" --revision @ >&2
echo "$DIR"
