#!/usr/bin/env bash
# block-git.sh — Intercepts git commands in jj repos and suggests jj equivalents.
# Called as a PreToolUse hook for Bash. Reads hook input JSON from stdin
# (command at tool_input.command). Denies via JSON on stdout; exit 0 otherwise allows.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prints "<cwd>\n<git subcommand>" for the first git invocation anywhere in the
# command line (after cd &&, env assignments, git -C <dir>, ...), nothing otherwise.
PARSED=$(python3 -B -c '
import sys; sys.path.insert(0, sys.argv[1]); import hooklib
command, cwd = hooklib.read_input()
for seg in hooklib.segments(command):
    if hooklib.program(seg) == "git":
        print(cwd)
        print(hooklib.subcommand(seg, {"-C", "-c"})[1])
        break
' "$HERE" 2>/dev/null) || exit 0

[ -n "$PARSED" ] || exit 0
cwd=$(sed -n 1p <<<"$PARSED")
git_subcmd=$(sed -n 2p <<<"$PARSED")

# Walk up from the session's cwd (which follows Claude's cd) looking for .jj/
check_dir="${cwd:-$PWD}"
found_jj=false
while [ -n "$check_dir" ] && [ "$check_dir" != "/" ]; do
  if [ -d "$check_dir/.jj" ]; then
    found_jj=true
    break
  fi
  check_dir="$(dirname "$check_dir")"
done

if [ "$found_jj" = false ]; then
  # Not a jj repo — allow git commands
  exit 0
fi

# Map git subcommand to jj equivalent
case "$git_subcmd" in
  status)      jj_equiv="jj status" ;;
  diff)        jj_equiv="jj diff" ;;
  log)         jj_equiv="jj log" ;;
  commit)      jj_equiv="jj commit" ;;
  add)         jj_equiv="(not needed — jj has no staging area, working copy is the commit)" ;;
  branch)      jj_equiv="jj bookmark" ;;
  checkout)    jj_equiv="jj new" ;;
  switch)      jj_equiv="jj new" ;;
  merge)       jj_equiv="jj new <rev1> <rev2> (create merge commit)" ;;
  rebase)      jj_equiv="jj rebase" ;;
  reset)       jj_equiv="jj restore" ;;
  stash)       jj_equiv="(not needed — jj commit and jj new handle this)" ;;
  push)        jj_equiv="jj git push" ;;
  pull)        jj_equiv="jj git fetch" ;;
  fetch)       jj_equiv="jj git fetch" ;;
  clone)       jj_equiv="jj git clone" ;;
  init)        jj_equiv="jj git init" ;;
  show)        jj_equiv="jj show" ;;
  tag)         jj_equiv="jj tag" ;;
  cherry-pick) jj_equiv="jj duplicate <rev> -o @ (or jj new <rev> then jj squash)" ;;
  revert)      jj_equiv="jj revert -r <rev> -o @" ;;
  blame)       jj_equiv="jj file annotate" ;;
  restore)     jj_equiv="jj restore" ;;
  mv)          jj_equiv="jj file track (after moving)" ;;
  rm)          jj_equiv="jj file untrack" ;;
  worktree)    jj_equiv="jj workspace" ;;
  *)           jj_equiv="(check jj --help for equivalent)" ;;
esac

python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import hooklib; hooklib.deny(sys.argv[2])' "$HERE" \
  "BLOCK: This is a jj repository. Use jj instead of git.
  git $git_subcmd → $jj_equiv"
