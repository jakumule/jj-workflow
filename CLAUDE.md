# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`jj-workflow` is a Claude Code **plugin** (not application code). It teaches Claude to use [jujutsu (jj)](https://martinvonz.github.io/jj/) instead of git. There is no build, no test suite, and no package manager — components are loaded directly by Claude Code from the manifest.

This repo is itself managed with jj. Use `jj` commands, never `git`. The `block-git.sh` hook will reject `git` commands when run inside Claude Code here.

## Architecture

Four component types. Claude Code discovers `hooks/hooks.json` and `skills/` from their default locations; `.claude-plugin/plugin.json` holds only metadata:

1. **Hooks** (`hooks/hooks.json` + `hooks/scripts/*.sh`) — the enforcement layer.
   - Hook input arrives on stdin as `{"tool_name": "Bash", "tool_input": {"command": ...}, "cwd": ...}`. The command is at `tool_input.command`, **not** top level; `cwd` follows Claude's `cd`s. `hooks/scripts/hooklib.py` parses it, splits compound commands (`&&`, `;`, `|`, subshells, env-assignment prefixes), and emits the deny decision.
   - Blocking is done with exit 0 plus `{"hookSpecificOutput": {"permissionDecision": "deny", "permissionDecisionReason": ...}}` on stdout. (With exit 2, Claude only sees stderr. Plain stdout is dropped.)
   - `block-git.sh`: `PreToolUse` on `Bash`. Finds `git` anywhere in the command, walks up from the input's `cwd` looking for `.jj/`, and if found denies with the jj equivalent. Allows otherwise. **This is what makes the plugin work** — every other component assumes git is unavailable.
   - `guard-jj-message.sh`: `PreToolUse` on `Bash`. Denies `jj commit|describe|squash` without `-m`/`--message` (`-u` for squash, `--stdin` for describe), `jj split` without paths, and `--editor`/`-i`/`--tool`, so Claude never gets stuck in an interactive editor.
   - `worktree-create.sh` / `worktree-remove.sh`: `WorktreeCreate` / `WorktreeRemove` hooks bridging Claude Code's worktree mechanism to `jj workspace add` / `jj workspace forget`. The worktree name arrives in the stdin JSON (`name`; remove gets `worktree_path`), not an env var. These hooks replace built-in worktree creation for *every* repo when the plugin is installed, so outside jj repos they fall back to `git worktree add`/`remove`. Workspaces live under `.claude/worktrees/<name>`; create must print only the absolute path on stdout, and remove refuses to delete anything outside `.claude/worktrees/`. jj workspaces share one commit graph, so no merge is needed when work completes.

2. **Slash commands** (`skills/<name>/SKILL.md`, migrated from the older `commands/` format) — `/jj-commit` (selective file grouping + commit, runs optional `.claude/jj-pre-commit.sh` from the host project), `/jj-sync` (fetch + rebase onto trunk), `/jj-push` (set/advance a bookmark and push), `/jj-resolve` (guided conflict resolution), `/jj-absorb` (`jj absorb` working-copy edits into their originating commits), and `/develop` (enter a jj workspace via the `EnterWorktree` mechanism). All have `disable-model-invocation: true` — Claude only runs them when the user types the slash command. `allowed-tools` pre-approves the `jj` calls they make.

3. **Skill** (`skills/jj-concepts/SKILL.md` + `references/`) — background knowledge auto-loaded when jj work is happening. Documents the jj mental model (working copy is a commit, change IDs vs commit IDs, conflicts as data, immutable set).

4. **Script** (`scripts/cleanup-workspace.sh`) — user-invoked workspace teardown helper.

### Key design facts to preserve when editing

- Hook scripts parse stdin JSON with python3 (stdlib only, via `hooklib.py` or `python3 -c`). Keep this — it avoids a `jq` dependency.
- `block-git.sh` detects "is this a jj repo?" by walking up for `.jj/`, **not** by calling `jj`. This makes it cheap and safe when jj isn't installed in the host project.
- Hook commands in `hooks.json` reference scripts via a quoted `"${CLAUDE_PLUGIN_ROOT}"`. Don't hardcode paths.
- Bump `version` in `plugin.json` on every release; installed copies are pinned to it and won't pick up changes otherwise.
- The git→jj mapping table lives in `block-git.sh`. When adding a mapping, also consider whether the `jj-concepts` skill needs the same entry.

## Common tasks

- **Install locally for testing**: `/plugin marketplace add kalupa/jj-workflow` then `/plugin install jj-workflow@jj-workflow` from Claude Code.
- **Test a hook script manually**: `echo '{"tool_input":{"command":"cd x && git status"},"cwd":"'$PWD'"}' | bash hooks/scripts/block-git.sh` — prints a deny JSON inside a jj repo, nothing outside one.
- **Validate the manifest/hooks**: `claude plugin validate .`
- **Inspect plugin wiring**: `cat .claude-plugin/plugin.json hooks/hooks.json`.

There is no test suite. Validate changes by exercising the hook/command in a real Claude Code session.
