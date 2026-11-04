#!/usr/bin/env bash
# guard-jj-message.sh — Blocks jj commands that would open an interactive editor.
# Covers commit/describe/split/squash without -m, --editor, and -i/--interactive.
# Called as a PreToolUse hook for Bash. Reads hook input JSON from stdin
# (command at tool_input.command). Denies via JSON on stdout; exit 0 otherwise allows.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -B -c '
import sys; sys.path.insert(0, sys.argv[1]); import hooklib

GLOBAL_OPTS = {"-R", "--repository", "--at-op", "--at-operation", "--color", "--config", "--config-file"}
ALIASES = {"ci": "commit", "desc": "describe"}
# split options that take a value, so their values are not mistaken for paths
SPLIT_VALUE_OPTS = {"-r", "--revision", "-o", "--onto", "-d", "--destination",
                    "-A", "--insert-after", "-B", "--insert-before", "-m", "--message", "--tool"}

def has(rest, short, long):
    return any(t == short or t == long or t.startswith(long + "=")
               or (short and t.startswith(short) and not t.startswith("--")) for t in rest)

def problem(sub, rest):
    if has(rest, "", "--editor"):
        return "--editor forces the interactive message editor. Drop it and pass -m."
    if (sub != "describe" and has(rest, "-i", "--interactive")) or has(rest, "", "--tool"):
        return "-i/--interactive and --tool open an interactive diff editor. Pass file paths instead."
    if sub == "split":
        i, positional = 0, False
        while i < len(rest):
            if rest[i] in SPLIT_VALUE_OPTS:
                i += 2
                continue
            if not rest[i].startswith("-"):
                positional = True
            i += 1
        if not positional:
            return "with no file paths opens an interactive diff editor. Pass the paths for the first commit: jj split -m \"msg\" <paths...>"
    if has(rest, "-m", "--message"):
        return None
    if sub == "describe" and has(rest, "", "--stdin"):
        return None
    if sub == "squash" and has(rest, "-u", "--use-destination-message"):
        return None
    hint = "  Or use -u (--use-destination-message) to reuse the destination message." if sub == "squash" else ""
    return "without -m opens an interactive editor.\n  Always provide: jj %s -m \"your message\" ...%s" % (sub, "\n" + hint if hint else "")

command, _ = hooklib.read_input()
for seg in hooklib.segments(command):
    if hooklib.program(seg) != "jj":
        continue
    idx, sub = hooklib.subcommand(seg, GLOBAL_OPTS)
    sub = ALIASES.get(sub, sub)
    if sub not in ("commit", "describe", "split", "squash"):
        continue
    reason = problem(sub, seg[idx + 1:])
    if reason:
        hooklib.deny("BLOCK: jj %s %s" % (sub, reason))
        break
' "$HERE" 2>/dev/null || exit 0
