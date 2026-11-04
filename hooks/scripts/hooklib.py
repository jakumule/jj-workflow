"""Shared helpers for the PreToolUse hook scripts.

Parses the hook input JSON (command at tool_input.command), splits a Bash
command line into simple commands, and emits a PreToolUse deny decision.
Stdlib only, so the hooks need nothing beyond python3.
"""

import json
import os
import re
import shlex
import sys

SEPARATORS = set("();&|\n")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Commands that run their arguments as another command: sudo git ..., xargs git ...
WRAPPERS = {"env", "command", "exec", "time", "nohup", "sudo", "xargs", "nice", "timeout"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
# $(...) and `...` bodies, matched on the raw string so quoting doesn't hide them
SUBSTITUTION = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
# <<EOF ... EOF bodies are data, not commands
HEREDOC_BODY = re.compile(r"(<<-?\s*(['\"]?)(\w+)\2[^\n]*\n).*?^\s*\3[ \t]*$", re.S | re.M)


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


def _strip_prefix(tokens):
    """Drop env assignments and wrapper commands (with their options) in front of the program."""
    i = 0
    while i < len(tokens):
        if ASSIGNMENT.match(tokens[i]):
            i += 1
        elif program(tokens[i:]) in WRAPPERS:
            wrapper = program(tokens[i:])
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 1
            if wrapper == "timeout" and i < len(tokens):
                i += 1  # the duration
        else:
            break
    return tokens[i:]


def segments(command):
    """Yield each simple command as a token list, minus env assignments and wrappers.

    Also yields the commands nested in $(...), backticks, `bash -c "..."` and
    `find -exec ...`, before the command that contains them.
    """
    command = HEREDOC_BODY.sub(r"\1", command)
    for m in SUBSTITUTION.finditer(command):
        yield from segments(m.group(1) or m.group(2) or "")
    current = []
    for tok in _tokens(command) + [";"]:
        if tok and set(tok) <= SEPARATORS:
            current = _strip_prefix(current)
            if current:
                yield from _nested(current)
                yield current
            current = []
        else:
            current.append(tok)


def _nested(tokens):
    prog = program(tokens)
    if prog in SHELLS and "-c" in tokens[1:-1]:
        yield from segments(tokens[tokens.index("-c", 1) + 1])
    elif prog == "find":
        for i, tok in enumerate(tokens):
            if tok in ("-exec", "-execdir", "-ok", "-okdir"):
                inner = [t for t in tokens[i + 1:] if t not in ("{}", "+", ";")]
                if inner:
                    yield inner


def commands(command, cwd):
    """Yield (tokens, dir) for each simple command, where dir follows any earlier cd/pushd."""
    for seg in segments(command):
        if program(seg) in ("cd", "pushd"):
            cwd = resolve_dir(cwd, [a for a in seg[1:] if not a.startswith("-")][:1] or ["~"])
        yield seg, cwd


def resolve_dir(cwd, args):
    """Apply a cd target to cwd. Targets that can't be resolved statically keep cwd."""
    target = os.path.expanduser(os.path.expandvars(args[0]))
    if "$" in target or (not cwd and not os.path.isabs(target)):
        return cwd
    return os.path.normpath(os.path.join(cwd, target))


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


def jj_root(path):
    """Closest directory at or above path containing .jj/, or None. Never calls jj."""
    path = os.path.abspath(path or os.getcwd())
    while True:
        if os.path.isdir(os.path.join(path, ".jj")):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def deny(reason):
    """Print a PreToolUse deny decision; the reason is shown to Claude."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
