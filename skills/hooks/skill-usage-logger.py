#!/usr/bin/env python3
"""Log Skill and Agent tool invocations with outcome for usage telemetry."""
import json
import os
import sys
import time
from pathlib import Path

def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0

    tool = d.get("tool_name", "")
    if tool not in ("Skill", "Agent"):
        return 0

    tool_input = d.get("tool_input", {}) or {}
    resp = d.get("tool_response", {}) or {}
    is_error = bool(resp.get("is_error", False))

    entry = {
        "ts": int(time.time()),
        "tool": tool,
        "outcome": "error" if is_error else "ok",
    }

    if tool == "Skill":
        entry["skill"] = tool_input.get("skill", "?")
        entry["args_len"] = len(str(tool_input.get("args", "")))
    else:
        entry["subagent"] = tool_input.get("subagent_type", "general-purpose")
        entry["description"] = str(tool_input.get("description", ""))[:80]

    log = Path(os.path.expanduser("~/.claude/skill-usage.jsonl"))
    log.parent.mkdir(parents=True, exist_ok=True)
    try:
        if log.exists() and log.stat().st_size > 2_000_000:
            keep = log.read_text(errors="ignore").splitlines()[-1000:]
            log.write_text("\n".join(keep) + "\n")
    except Exception:
        pass
    with log.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
