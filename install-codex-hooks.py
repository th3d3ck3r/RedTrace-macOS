#!/usr/bin/env python3
"""Merge or remove RedTrace hooks while preserving other Codex hooks."""

import json
import os
import subprocess
import sys
import tempfile


MARKERS = ("redtrace/codex-hook.py", "commandglass/codex-hook.py")
HOOK_COMMAND = 'python3 "$HOME/.redtrace/codex-hook.py"'


def load(path: str) -> dict:
    if not os.path.exists(path):
        return {"hooks": {}}
    with open(path, "r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("hooks.json must contain a JSON object")
    value.setdefault("hooks", {})
    return value


def is_redtrace_group(group) -> bool:
    if not isinstance(group, dict):
        return False
    for hook in group.get("hooks", []):
        if any(marker in str(hook.get("command", "")) for marker in MARKERS):
            return True
    return False


def group() -> dict:
    return {
        "matcher": ".*",
        "hooks": [{
            "type": "command",
            "command": HOOK_COMMAND,
            "timeout": 3,
            "statusMessage": "Streaming command to RedTrace",
        }],
    }


def save(path: str, value: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="hooks.", suffix=".json", dir=os.path.dirname(path))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def verify(path: str) -> None:
    data = load(path)
    hooks = data.get("hooks", {})
    for event_name in ("PreToolUse", "PostToolUse"):
        if not any(is_redtrace_group(item) for item in hooks.get(event_name, [])):
            raise RuntimeError(f"RedTrace {event_name} hook was not saved")

    hook_script = os.path.expanduser("~/.redtrace/codex-hook.py")
    if not os.path.isfile(hook_script) or not os.access(hook_script, os.X_OK):
        raise RuntimeError("RedTrace hook script is missing or not executable")

    descriptor, test_path = tempfile.mkstemp(prefix="redtrace-hook-test.", suffix=".jsonl")
    os.close(descriptor)
    try:
        payload = {
            "hook_event_name": "PreToolUse",
            "tool_name": "exec_command",
            "tool_input": {"cmd": "printf redtrace-hook-self-test"},
            "cwd": os.path.expanduser("~"),
        }
        environment = os.environ.copy()
        environment["REDTRACE_EVENT_LOG"] = test_path
        subprocess.run(
            [sys.executable, hook_script],
            input=json.dumps(payload),
            text=True,
            env=environment,
            check=True,
            timeout=3,
        )
        with open(test_path, "r", encoding="utf-8") as handle:
            record = json.loads(handle.readline())
        if record.get("command") != "printf redtrace-hook-self-test":
            raise RuntimeError("RedTrace hook self-test did not capture the command")
    finally:
        if os.path.exists(test_path):
            os.unlink(test_path)


def main() -> int:
    operation = sys.argv[1] if len(sys.argv) > 1 else "install"
    path = os.path.expanduser("~/.codex/hooks.json")
    data = load(path)
    hooks = data.setdefault("hooks", {})
    for event_name in ("PreToolUse", "PostToolUse"):
        groups = [item for item in hooks.get(event_name, []) if not is_redtrace_group(item)]
        if operation == "install":
            groups.append(group())
        if groups:
            hooks[event_name] = groups
        else:
            hooks.pop(event_name, None)
    save(path, data)
    if operation == "install":
        verify(path)
        print("RedTrace Codex hooks installed and verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
