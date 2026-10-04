#!/usr/bin/env python3
"""Aggregate ~/.claude/skill-usage.jsonl into a report at
~/.claude/skill-usage-report.md. Flags: unused skills, high-failure skills,
frequent agent types. Run from auto-improve.sh."""
import json
import os
import sys
import collections
from pathlib import Path


def main() -> int:
    quiet = "--quiet" in sys.argv
    log = Path(os.path.expanduser("~/.claude/skill-usage.jsonl"))
    out = Path(os.path.expanduser("~/.claude/skill-usage-report.md"))

    if not log.exists():
        if not quiet:
            print("no usage log yet")
        return 0

    skill_counts = collections.Counter()
    skill_errors = collections.Counter()
    agent_counts = collections.Counter()
    agent_errors = collections.Counter()
    total = 0

    for line in log.read_text(errors="ignore").splitlines():
        try:
            d = json.loads(line)
        except Exception:
            continue
        total += 1
        if d.get("tool") == "Skill":
            s = d.get("skill", "?")
            skill_counts[s] += 1
            if d.get("outcome") == "error":
                skill_errors[s] += 1
        elif d.get("tool") == "Agent":
            a = d.get("subagent", "?")
            agent_counts[a] += 1
            if d.get("outcome") == "error":
                agent_errors[a] += 1

    if total < 5:
        if not quiet:
            print(f"only {total} entries so far — report deferred")
        return 0

    lines = [
        "# Skill & agent usage report",
        "",
        f"{total} invocations logged.",
        "",
        "## Skills — top 20 by frequency",
        "",
        "| skill | invocations | errors | error rate |",
        "|-------|------------:|-------:|-----------:|",
    ]
    for skill, n in skill_counts.most_common(20):
        e = skill_errors.get(skill, 0)
        rate = f"{100*e/n:.0f}%" if n else "-"
        lines.append(f"| {skill} | {n} | {e} | {rate} |")

    lines += ["", "## Agents — top 10 by frequency", ""]
    lines.append("| subagent | invocations | errors |")
    lines.append("|----------|------------:|-------:|")
    for a, n in agent_counts.most_common(10):
        lines.append(f"| {a} | {n} | {agent_errors.get(a, 0)} |")

    # Flags
    flags = []
    for skill, n in skill_counts.items():
        if n >= 3 and skill_errors.get(skill, 0) / n > 0.3:
            flags.append(f"- ⚠ **{skill}**: {100*skill_errors[skill]/n:.0f}% error rate — check triggers/docs")
    if flags:
        lines += ["", "## Flags", ""] + flags

    out.write_text("\n".join(lines) + "\n")
    if not quiet:
        print(f"wrote report to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
