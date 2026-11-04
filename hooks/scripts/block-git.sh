#!/usr/bin/env bash
# block-git.sh — Intercepts git commands in jj repos and suggests jj equivalents.
# Called as a PreToolUse hook for Bash. Reads hook input JSON from stdin
# (command at tool_input.command). Denies via JSON on stdout; exit 0 otherwise allows.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prints the git subcommand of the first git invocation anywhere in the command line
# (after cd &&, env assignments, wrappers, $(...), bash -c, ...) that runs inside a jj repo,
# nothing otherwise. The directory follows earlier cd/pushd segments and git -C <dir>.
git_subcmd=$(python3 -B -c '
import os, sys; sys.path.insert(0, sys.argv[1]); import hooklib
command, cwd = hooklib.read_input()
for seg, d in hooklib.commands(command, cwd or os.getcwd()):
    if hooklib.program(seg) != "git":
        continue
    idx, sub = hooklib.subcommand(seg, {"-C", "-c", "--git-dir", "--work-tree"})
    for i, tok in enumerate(seg[1:idx], 1):
        if tok == "-C" and i + 1 < len(seg):
            d = hooklib.resolve_dir(d, [seg[i + 1]])
    if hooklib.jj_root(d):
        print(sub or "(none)")
        break
' "$HERE" 2>/dev/null) || exit 0

# Not in a jj repo (or no git at all) — allow
[ -n "$git_subcmd" ] || exit 0

# Map git subcommand to jj equivalent
case "$git_subcmd" in
  status)      jj_equiv="jj status" ;;
  diff)        jj_equiv="jj diff" ;;
  log)         jj_equiv="jj log" ;;
  commit)      jj_equiv="jj commit -m \"msg\" [paths...]" ;;
  add)         jj_equiv="(not needed — jj has no staging area, working copy is the commit)" ;;
  branch)      jj_equiv="jj bookmark" ;;
  checkout)    jj_equiv="jj new <rev> (start work on top of it) or jj edit <rev> (amend it); files: jj restore --from <rev> <paths>" ;;
  switch)      jj_equiv="jj new <rev>" ;;
  merge)       jj_equiv="jj new <rev1> <rev2> (create merge commit)" ;;
  rebase)      jj_equiv="jj rebase -b @ -o <dest>" ;;
  reset)       jj_equiv="jj restore (discard edits), jj abandon (drop a commit), jj squash (fold into parent), or jj undo" ;;
  stash)       jj_equiv="(not needed — leave the changes in @ and run jj new <rev> to work elsewhere)" ;;
  push)        jj_equiv="jj git push -b <bookmark> (or /jj-push)" ;;
  pull)        jj_equiv="jj git fetch, then jj rebase -b @ -o 'trunk()' (or /jj-sync)" ;;
  fetch)       jj_equiv="jj git fetch" ;;
  clone)       jj_equiv="jj git clone" ;;
  init)        jj_equiv="jj git init" ;;
  remote)      jj_equiv="jj git remote list|add|remove|rename|set-url" ;;
  rev-parse)   jj_equiv="jj root (repo root), jj log -r <rev> --no-graph -T commit_id (resolve a rev)" ;;
  ls-files)    jj_equiv="jj file list" ;;
  show)        jj_equiv="jj show" ;;
  tag)         jj_equiv="jj tag list|set|delete" ;;
  cherry-pick) jj_equiv="jj duplicate <rev> -o @ (or jj new <rev> then jj squash)" ;;
  revert)      jj_equiv="jj revert -r <rev> -o @" ;;
  blame)       jj_equiv="jj file annotate" ;;
  restore)     jj_equiv="jj restore" ;;
  clean)       jj_equiv="(delete the files directly — jj snapshots the removal) or jj restore <paths>" ;;
  apply|am)    jj_equiv="(apply the patch with patch -p1, jj snapshots the result)" ;;
  mv)          jj_equiv="mv <old> <new> (plain mv — jj detects the change automatically)" ;;
  rm)          jj_equiv="rm <file> (plain rm — jj snapshots the deletion); to stop tracking but keep the file, ignore it and run jj file untrack" ;;
  worktree)    jj_equiv="jj workspace" ;;
  *)           jj_equiv="(check jj --help for equivalent)" ;;
esac

python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import hooklib; hooklib.deny(sys.argv[2])' "$HERE" \
  "BLOCK: This is a jj repository. Use jj instead of git.
  git $git_subcmd → $jj_equiv"
