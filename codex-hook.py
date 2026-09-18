#!/usr/bin/env python3
"""Record Codex Bash hook events for RedTrace without affecting execution."""

import datetime
import fcntl
import json
import os
import sys


def execution_origin(event: dict) -> str:
    explicit = str(event.get("execution_location") or event.get("environment") or "").lower()
    if "remote" in explicit or "cloud" in explicit:
        return "remote"
    cwd = str(event.get("cwd") or "")
    remote_roots = ("/workspace", "/workspaces", "/app", "/mnt/data", "/root/")
    return "remote" if cwd.startswith(remote_roots) else "local"


MAX_FIELD = 65536
def printable_output(value) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value[:MAX_FIELD]
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))[:MAX_FIELD]


def first_value(mapping: dict, *keys):
    for key in keys:
        value = mapping.get(key)
        if value not in (None, ""):
            return value
    return None


def command_from_input(tool_input: dict) -> str:
    value = first_value(tool_input, "command", "cmd", "script", "shell_command")
    if isinstance(value, list):
        return " ".join(str(item) for item in value)
    if value is not None:
        return str(value)
    return ""


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except Exception:
        return 0

    event_name = str(event.get("hook_event_name") or event.get("hookEventName") or "")
    tool_input = event.get("tool_input") if isinstance(event.get("tool_input"), dict) else {}
    command = command_from_input(tool_input)
    tool_name = str(event.get("tool_name") or event.get("toolName") or "")
    record = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "phase": "start" if event_name == "PreToolUse" else "finish",
        "origin": execution_origin(event),
        "session_id": event.get("session_id"),
        "turn_id": event.get("turn_id"),
        "tool_use_id": event.get("tool_use_id"),
        "cwd": event.get("cwd"),
        "tool_name": tool_name,
        "command": command,
        "output": printable_output(first_value(event, "tool_response", "tool_output", "tool_result")),
        "target": first_value(tool_input, "path", "file", "file_path", "filename", "target", "query", "pattern", "search_query") or "",
        "tool_input": printable_output(tool_input),
        "exit_code": first_value(event, "exit_code", "exitCode"),
        "error": printable_output(event.get("error")),
    }

    folder = os.path.expanduser("~/.redtrace")
    os.makedirs(folder, mode=0o700, exist_ok=True)
    path = os.environ.get("REDTRACE_EVENT_LOG") or os.path.join(folder, "codex-events.jsonl")
    try:
        with open(path, "a", encoding="utf-8") as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            handle.flush()
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        os.chmod(path, 0o600)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
