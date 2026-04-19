#!/usr/bin/env python3
"""Read a PostToolUse hook payload on stdin, append a compact error row
to ~/.claude/tool-errors.jsonl when the tool failed. Silent on non-errors."""
import json
import sys
import hashlib
import os
import time
from pathlib import Path

def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0

    resp = d.get("tool_response", {})
    if not isinstance(resp, dict) or not resp.get("is_error"):
        return 0

    content = resp.get("content", "")
    if isinstance(content, list):
        parts = []
        for x in content:
            if isinstance(x, dict):
                parts.append(str(x.get("text", x)))
            else:
                parts.append(str(x))
        content = " ".join(parts)
    text = str(content)[:800]

    first_line = text.split("\n", 1)[0][:120]
    sig = hashlib.sha256(first_line.encode("utf-8", "replace")).hexdigest()[:16]

    entry = {
        "ts": int(time.time()),
        "tool": d.get("tool_name", "?"),
        "sig": sig,
        "first_line": first_line,
        "excerpt": text[:400],
    }

    log = Path(os.path.expanduser("~/.claude/tool-errors.jsonl"))
    log.parent.mkdir(parents=True, exist_ok=True)

    try:
        if log.exists() and log.stat().st_size > 2_000_000:
            keep = log.read_text(errors="ignore").splitlines()[-500:]
            log.write_text("\n".join(keep) + "\n")
    except Exception:
        pass

    with log.open("a") as f:
        f.write(json.dumps(entry) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
