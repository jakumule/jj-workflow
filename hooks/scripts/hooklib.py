"""Shared helpers for the PreToolUse hook scripts.

Parses the hook input JSON (command at tool_input.command), splits a Bash
command line into simple commands, and emits a PreToolUse deny decision.
Stdlib only, so the hooks need nothing beyond python3.
"""

import json
import re
import shlex
import sys

SEPARATORS = set("();&|\n")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WRAPPERS = {"env", "command", "exec", "time", "nohup"}


def read_input():
    """Return (command, cwd) from the hook input on stdin."""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        return "", ""
    tool_input = data.get("tool_input") or {}
    return tool_input.get("command") or "", data.get("cwd") or ""


def _tokens(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"  # keep newlines as separators
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:
        # Unbalanced quotes (e.g. heredoc bodies): fall back to a naive split.
        return re.findall(r"[;&|()\n]+|[^\s;&|()]+", command)


def segments(command):
    """Yield each simple command as a token list, minus env assignments and wrappers."""
    current = []
    for tok in _tokens(command) + [";"]:
        if tok and set(tok) <= SEPARATORS:
            while current and (ASSIGNMENT.match(current[0]) or current[0] in WRAPPERS):
                current.pop(0)
            if current:
                yield current
            current = []
        else:
            current.append(tok)


def program(tokens):
    """Basename of the executable, so /usr/bin/git is treated like git."""
    return tokens[0].rsplit("/", 1)[-1]


def subcommand(tokens, opts_with_value):
    """Return (index, name) of the first non-option argument after the program."""
    i = 1
    while i < len(tokens):
        tok = tokens[i]
        if tok in opts_with_value:
            i += 2
            continue
        if tok.startswith("-"):
            i += 1
            continue
        return i, tok
    return len(tokens), ""


def deny(reason):
    """Print a PreToolUse deny decision; the reason is shown to Claude."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
