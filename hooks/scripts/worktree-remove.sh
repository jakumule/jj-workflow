#!/usr/bin/env bash
# worktree-remove.sh — Forgets a jj workspace created by worktree-create.sh and deletes it.
# Called as a WorktreeRemove hook. Reads hook input JSON ({"worktree_path": ...}) from stdin.

set -uo pipefail

INPUT=$(cat)
field() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1') or '')" <<<"$INPUT"; }
DIR=$(field worktree_path)
[ -n "$DIR" ] || DIR=$(field path)
NAME=$(field name)
CWD=$(field cwd)

if [ -z "$DIR" ]; then
  if [ -z "$NAME" ]; then
    echo "WorktreeRemove: no path or name in hook input" >&2
    exit 1
  fi
  DIR="$(jj -R "${CWD:-$PWD}" workspace root)/.claude/worktrees/$NAME"
fi

# Only ever delete directories created by worktree-create.sh
case "$DIR" in
  */.claude/worktrees/?*) ;;
  *) echo "WorktreeRemove: refusing to remove '$DIR'" >&2; exit 1 ;;
esac

if [ -d "$DIR/.jj" ]; then
  jj -R "$DIR" workspace forget >/dev/null 2>&1 || true
elif [ -e "$DIR/.git" ]; then
  # git fallback from worktree-create.sh; keeps the worktree-<name> branch
  git -C "$DIR" worktree remove --force "$DIR" >/dev/null 2>&1 || true
fi
rm -rf "$DIR"
