#!/usr/bin/env bash
# Clean up a jj workspace after development work is done. Non-interactive, so Claude can run it.
# Usage: cleanup-workspace.sh <workspace-name>
# Commits made in the workspace stay in the repo; only the workspace and its directory go away.

set -euo pipefail

WORKSPACE_NAME="${1:?Usage: cleanup-workspace.sh <workspace-name>}"

if ! WORKSPACE_DIR=$(jj workspace root --name "$WORKSPACE_NAME" 2>/dev/null); then
  echo "Error: Workspace '$WORKSPACE_NAME' not found" >&2
  echo "" >&2
  echo "Active workspaces:" >&2
  jj workspace list >&2
  exit 1
fi

case "$PWD/" in
  "$WORKSPACE_DIR"/*)
    echo "Error: run this from another workspace, not from inside '$WORKSPACE_NAME'" >&2
    exit 1 ;;
esac

# Snapshot unrecorded edits in the workspace so forgetting it doesn't lose them
if [ -d "$WORKSPACE_DIR/.jj" ]; then
  jj -R "$WORKSPACE_DIR" workspace update-stale >/dev/null 2>&1 || true
  jj -R "$WORKSPACE_DIR" status >/dev/null 2>&1 || true
fi

echo "Cleaning up workspace: $WORKSPACE_NAME"
echo ""
echo "Its working copy and mutable ancestors (these stay in the repo):"
jj log -r "::$WORKSPACE_NAME@ & mutable()" --limit 10
echo ""

jj workspace forget "$WORKSPACE_NAME"

# Only ever delete directories created by worktree-create.sh
case "$WORKSPACE_DIR" in
  */.claude/worktrees/?*) rm -rf "$WORKSPACE_DIR" ;;
  *) echo "Kept directory $WORKSPACE_DIR (not under .claude/worktrees/)" ;;
esac

echo ""
echo "Workspace removed. To continue its work here: jj new <change-id>"
