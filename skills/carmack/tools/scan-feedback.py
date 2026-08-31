#!/usr/bin/env python3
"""Group ~/.claude/feedback-pending.jsonl into human-readable pending reviews.

Reads the JSONL written by feedback-logger.py, dedups by
(kind, assistant_snippet_prefix), writes ~/.claude/feedback-pending.md
listing the top candidates. Prints a summary line to stdout.
"""
import json
import os
import collections
from pathlib import Path


def main() -> int:
    log = Path(os.path.expanduser("~/.claude/feedback-pending.jsonl"))
    out = Path(os.path.expanduser("~/.claude/feedback-pending.md"))

    if not log.exists():
        try:
            out.unlink()
        except FileNotFoundError:
            pass
        return 0

    try:
        lines = log.read_text(errors="ignore").splitlines()
    except Exception:
        return 0

    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except Exception:
            continue

    # Group by (kind, first ~60 chars of assistant snippet)
    groups = collections.defaultdict(list)
    for e in entries:
        key = (e.get("kind", "?"), (e.get("assistant_snippet", "") or "")[:80])
        groups[key].append(e)

    items = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    if not items:
        try:
            out.unlink()
        except FileNotFoundError:
            pass
        return 0

    md = [
        "# Pending behavioral-feedback review",
        "",
        f"{len(items)} candidate(s) from `{log}`.",
        "",
        "When /carmack loads, review each entry and either:",
        "- Save as a new memory (feedback type) via `bd remember \"...\"` or a memory file",
        "- Skip if it was a one-off, out-of-scope, or already captured",
        "",
        "After review, run `auto-improve.sh --clear` to archive the log.",
        "",
        "---",
        "",
    ]
    for i, ((kind, snip), rows) in enumerate(items[:30], 1):
        md.append(f"## {i}. [{kind} · {len(rows)}x] trigger: `{rows[0]['matched']}`")
        md.append("")
        md.append(f"**User said**: {rows[0]['prompt'][:200]}")
        md.append("")
        if rows[0].get("assistant_snippet"):
            md.append(f"**After this assistant action**: {rows[0]['assistant_snippet'][:200]}")
            md.append("")

    out.write_text("\n".join(md))
    print(f"wrote {len(items)} feedback candidate(s) to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
