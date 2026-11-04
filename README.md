# jj-workflow

A Claude Code plugin that teaches Claude to use [jujutsu (jj)](https://martinvonz.github.io/jj/) instead of git.

## What it does

- **Intercepts git commands** in jj repos and suggests the jj equivalent
- **Guards against interactive editors** — blocks `jj commit`/`describe`/`squash` without `-m`, and `jj split` without paths
- **`/jj-commit`** — selective file grouping and commit workflow
- **`/jj-sync`** — fetch and rebase in-progress work onto the updated trunk
- **`/jj-push`** — point a bookmark at the right change and push it
- **`/jj-resolve`** — guided resolution of jj conflicts (stored as data in commits)
- **`/jj-absorb`** — auto-distribute working-copy edits into the commits that introduced those lines
- **`/develop`** — enter isolated jj workspaces for development
- **Background knowledge** — jj concepts, revset and fileset syntax, conflict resolution, and a git-to-jj command mapping

## Installation

```shell
/plugin marketplace add kalupa/jj-workflow
/plugin install jj-workflow@jj-workflow
```

Or via CLI:

```bash
claude plugin install jj-workflow@jj-workflow
```

## Structure

```
.claude-plugin/plugin.json          Plugin manifest
hooks/hooks.json                    Hook definitions (git blocking, editor guard, worktree lifecycle)
hooks/scripts/block-git.sh          Git command interceptor
hooks/scripts/guard-jj-message.sh   Blocks jj commands that would open an editor
hooks/scripts/worktree-*.sh         WorktreeCreate/WorktreeRemove → jj workspaces
hooks/scripts/hooklib.py            Shared hook-input parsing (stdlib python3)
skills/jj-commit/                   /jj-commit
skills/jj-sync/                     /jj-sync
skills/jj-push/                     /jj-push
skills/jj-resolve/                  /jj-resolve
skills/jj-absorb/                   /jj-absorb
skills/develop/                     /develop
skills/jj-concepts/                 Background jj knowledge for Claude
scripts/cleanup-workspace.sh        Workspace cleanup helper
```

## Pre-commit validation

The `/jj-commit` command checks for `.claude/jj-pre-commit.sh` in your project root. If it exists and is executable, it runs before committing. Use this for project-specific validation:

```bash
# Example: .claude/jj-pre-commit.sh for an hledger project
#!/usr/bin/env bash
hledger check -s -f main.journal

# Example: for a Rust project
#!/usr/bin/env bash
cargo check
```

## How git blocking works

The PreToolUse hook intercepts `git` anywhere in a Bash command (including after `cd … &&`, env assignments, or `git -C <dir>`) when a `.jj/` directory is found above the session's working directory. It maps the git subcommand to its jj equivalent and blocks with a helpful message:

```
BLOCK: This is a jj repository. Use jj instead of git.
  git status → jj status
```

In non-jj repos, git commands pass through normally.

## Workspace model

`/develop` creates jj workspaces via Claude Code's `EnterWorktree` mechanism. Unlike git worktrees, jj workspaces share the same commit graph — no merging needed. Leave with `ExitWorktree` (or exit the session) and choose to remove the worktree; the WorktreeRemove hook forgets the jj workspace and deletes it. For a workspace that was kept, use `scripts/cleanup-workspace.sh <name>`.

The worktree hooks replace Claude Code's built-in worktree creation wherever the plugin is installed, so in plain git repos they fall back to a normal `git worktree` on a `worktree-<name>` branch.

Requires `python3` (hooks parse their JSON input with it) and `jj`.
