#!/usr/bin/env python3
"""
Claude Code Token Usage Analyzer

Scans ~/.claude/projects/ JSONL session files and generates a markdown report
with token usage breakdowns by project, costliest sessions, and subagent stats.

Usage:
    python3 token-usage.py                    # All time
    SINCE_DAYS=7 python3 token-usage.py       # Last 7 days
    SINCE_DATE=2025-01-15 python3 token-usage.py  # Since specific date

Output: ~/.claude/usage/token_report.md

Based on: https://gist.github.com/kieranklaassen/7b2ebb39cbbb78cc2831497605d76cc6
"""

import json
import os
import sys
from pathlib import Path
from collections import defaultdict
from datetime import datetime, timedelta, timezone

PROJECTS_DIR = Path.home() / ".claude" / "projects"
OUTPUT_DIR = Path.home() / ".claude" / "usage"

SINCE_DAYS = int(os.environ.get("SINCE_DAYS", "0")) or None
SINCE_DATE = os.environ.get("SINCE_DATE")


def extract_text_content(content):
    """Extract text from message content (string or list)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    parts.append(item.get("text", ""))
            elif isinstance(item, str):
                parts.append(item)
        return "\n".join(parts).strip()
    return ""


def is_human_prompt(msg_obj):
    """Check if this is a human-originated prompt (not tool result)."""
    content = msg_obj.get("message", {}).get("content", "")
    if isinstance(content, list):
        types = [i.get("type") for i in content if isinstance(i, dict)]
        if types and all(t == "tool_result" for t in types):
            return False
    return True


def parse_session(jsonl_path, is_subagent=False):
    """Parse a single JSONL session file."""
    usage_total = defaultdict(int)
    prompts = []
    agent_id = None
    session_id = None
    timestamp_start = None
    subagent_sessions = []

    try:
        with open(jsonl_path) as f:
            lines = f.readlines()
    except Exception:
        return None

    for line in lines:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg_type = obj.get("type")
        ts = obj.get("timestamp")

        if ts and not timestamp_start:
            timestamp_start = ts

        if not agent_id:
            agent_id = obj.get("agentId")

        if not session_id:
            session_id = obj.get("sessionId")

        if msg_type == "assistant":
            usage = obj.get("message", {}).get("usage", {})
            usage_total["input_tokens"] += usage.get("input_tokens", 0)
            usage_total["cache_creation_input_tokens"] += usage.get(
                "cache_creation_input_tokens", 0
            )
            usage_total["cache_read_input_tokens"] += usage.get(
                "cache_read_input_tokens", 0
            )
            usage_total["output_tokens"] += usage.get("output_tokens", 0)

        elif msg_type == "user":
            user_type = obj.get("userType", "")
            is_sidechain = obj.get("isSidechain", False)
            content = obj.get("message", {}).get("content", "")
            text = extract_text_content(content)

            if (
                text
                and not is_sidechain
                and is_human_prompt(obj)
                and user_type != "tool"
            ):
                prompts.append(
                    {
                        "text": text,
                        "timestamp": obj.get("timestamp"),
                        "entrypoint": obj.get("entrypoint", ""),
                    }
                )

        # Check for subagent sessions
        session_dir = jsonl_path.parent / jsonl_path.stem
        if session_dir.is_dir():
            subagents_dir = session_dir / "subagents"
            if subagents_dir.is_dir():
                for sub_file in subagents_dir.glob("*.jsonl"):
                    sub_data = parse_session(sub_file, is_subagent=True)
                    if sub_data:
                        sub_data["subagent_file"] = str(sub_file.name)
                        subagent_sessions.append(sub_data)

    total_tokens = (
        usage_total["input_tokens"]
        + usage_total["cache_creation_input_tokens"]
        + usage_total["cache_read_input_tokens"]
        + usage_total["output_tokens"]
    )

    return {
        "file": str(jsonl_path),
        "session_id": session_id or jsonl_path.stem,
        "agent_id": agent_id,
        "is_subagent": is_subagent,
        "timestamp_start": timestamp_start,
        "usage": dict(usage_total),
        "total_tokens": total_tokens,
        "prompts": prompts,
        "subagent_sessions": subagent_sessions,
    }


def get_project_name(project_dir_name):
    """Convert directory name to readable project name.

    Strips the -Users-<username>- prefix that Claude Code adds.
    Uses the actual system username for reliable matching.
    """
    import re

    username = Path.home().name
    prefix = f"-Users-{username}-"
    if project_dir_name.startswith(prefix):
        remainder = project_dir_name[len(prefix):]
        return remainder if remainder else username
    # Also handle the bare -Users-<username> (home dir project)
    if project_dir_name == f"-Users-{username}":
        return "~"
    # Fallback: try generic pattern
    m = re.match(r"^-?Users-[^-]+-(.+)$", project_dir_name)
    if m:
        return m.group(1)
    return project_dir_name


def get_cutoff():
    """Return a UTC-aware datetime cutoff, or None for all time."""
    if SINCE_DATE:
        return datetime.fromisoformat(SINCE_DATE).replace(tzinfo=timezone.utc)
    if SINCE_DAYS:
        return datetime.now(timezone.utc) - timedelta(days=SINCE_DAYS)
    return None


def session_in_range(session, cutoff):
    if not cutoff or not session["timestamp_start"]:
        return True
    try:
        ts = datetime.fromisoformat(
            session["timestamp_start"].replace("Z", "+00:00")
        )
        return ts >= cutoff
    except ValueError:
        return True


def analyze_all():
    """Analyze all projects and sessions."""
    projects = defaultdict(list)
    cutoff = get_cutoff()

    if not PROJECTS_DIR.exists():
        print(f"No projects directory found at {PROJECTS_DIR}")
        sys.exit(1)

    for project_dir in sorted(PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue

        project_name = get_project_name(project_dir.name)

        for jsonl_file in sorted(project_dir.glob("*.jsonl")):
            session = parse_session(jsonl_file)
            if (
                session
                and session["total_tokens"] > 0
                and session_in_range(session, cutoff)
            ):
                projects[project_name].append(session)

    return projects


def format_tokens(n):
    """Format token count with commas."""
    return f"{n:,}"


def summarize_projects(projects):
    """Build per-project summary."""
    summaries = []

    for project_name, sessions in projects.items():
        total = defaultdict(int)
        all_subagent_tokens = 0
        subagent_count = 0

        for session in sessions:
            for k, v in session["usage"].items():
                total[k] += v

            for sub in session["subagent_sessions"]:
                all_subagent_tokens += sub["total_tokens"]
                subagent_count += 1

        grand_total = sum(total.values())

        summaries.append(
            {
                "project": project_name,
                "sessions": len(sessions),
                "usage": dict(total),
                "total_tokens": grand_total,
                "subagent_tokens": all_subagent_tokens,
                "subagent_count": subagent_count,
            }
        )

    summaries.sort(key=lambda x: x["total_tokens"], reverse=True)
    return summaries


def find_costly_sessions(projects, top_n=20):
    """Find the most token-heavy sessions across all projects."""
    all_sessions = []
    for project_name, sessions in projects.items():
        for session in sessions:
            all_sessions.append((project_name, session))
    all_sessions.sort(key=lambda x: x[1]["total_tokens"], reverse=True)
    return all_sessions[:top_n]


def find_costly_subagents(projects, top_n=20):
    """Find the most token-heavy subagent sessions."""
    all_subs = []
    for project_name, sessions in projects.items():
        for session in sessions:
            for sub in session["subagent_sessions"]:
                all_subs.append((project_name, session["session_id"], sub))
    all_subs.sort(key=lambda x: x[2]["total_tokens"], reverse=True)
    return all_subs[:top_n]


def write_report(projects, summaries):
    """Write the analysis report to ~/.claude/usage/token_report.md."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    report_path = OUTPUT_DIR / "token_report.md"
    lines = []

    cutoff = get_cutoff()
    date_range = (
        f"Since {cutoff.strftime('%Y-%m-%d')}" if cutoff else "All time"
    )

    lines.append("# Claude Code Token Usage Report")
    lines.append(
        f"\nGenerated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | Range: {date_range}\n"
    )

    # Grand totals
    grand_input = sum(
        s["usage"].get("input_tokens", 0) for s in summaries
    )
    grand_cache_create = sum(
        s["usage"].get("cache_creation_input_tokens", 0) for s in summaries
    )
    grand_cache_read = sum(
        s["usage"].get("cache_read_input_tokens", 0) for s in summaries
    )
    grand_output = sum(
        s["usage"].get("output_tokens", 0) for s in summaries
    )
    grand_total = sum(s["total_tokens"] for s in summaries)
    total_sessions = sum(s["sessions"] for s in summaries)
    total_subagent_tokens = sum(s["subagent_tokens"] for s in summaries)
    total_subagent_count = sum(s["subagent_count"] for s in summaries)

    lines.append("## Grand Totals\n")
    lines.append(f"- **Projects**: {len(summaries)}")
    lines.append(f"- **Sessions**: {total_sessions:,}")
    lines.append(f"- **Total tokens**: {format_tokens(grand_total)}")
    lines.append(f"  - Input: {format_tokens(grand_input)}")
    lines.append(f"  - Cache creation: {format_tokens(grand_cache_create)}")
    lines.append(f"  - Cache read: {format_tokens(grand_cache_read)}")
    lines.append(f"  - Output: {format_tokens(grand_output)}")
    lines.append(
        f"- **Subagent sessions**: {total_subagent_count:,} ({format_tokens(total_subagent_tokens)} tokens)"
    )
    lines.append("")

    # Per-project breakdown
    lines.append("## By Project\n")
    lines.append(
        "| Project | Sessions | Total | Input | Cache Create | Cache Read | Output | Subagents |"
    )
    lines.append(
        "|---------|----------|-------|-------|--------------|------------|--------|-----------|"
    )

    for s in summaries:
        u = s["usage"]
        lines.append(
            f"| {s['project']} | {s['sessions']} "
            f"| {format_tokens(s['total_tokens'])} "
            f"| {format_tokens(u.get('input_tokens', 0))} "
            f"| {format_tokens(u.get('cache_creation_input_tokens', 0))} "
            f"| {format_tokens(u.get('cache_read_input_tokens', 0))} "
            f"| {format_tokens(u.get('output_tokens', 0))} "
            f"| {s['subagent_count']} ({format_tokens(s['subagent_tokens'])}) |"
        )

    lines.append("")

    # Most costly sessions
    lines.append("## Most Costly Sessions (Top 25)\n")
    costly = find_costly_sessions(projects, top_n=25)

    for i, (proj, session) in enumerate(costly, 1):
        lines.append(
            f"### {i}. {proj} — {format_tokens(session['total_tokens'])} tokens"
        )
        lines.append(f"- **Session**: `{session['session_id']}`")

        if session["timestamp_start"]:
            lines.append(
                f"- **Started**: {session['timestamp_start'][:19].replace('T', ' ')}"
            )

        u = session["usage"]
        lines.append(
            f"- **Tokens**: input={format_tokens(u.get('input_tokens', 0))}, "
            f"cache_create={format_tokens(u.get('cache_creation_input_tokens', 0))}, "
            f"cache_read={format_tokens(u.get('cache_read_input_tokens', 0))}, "
            f"output={format_tokens(u.get('output_tokens', 0))}"
        )
        lines.append(
            f"- **Subagents in session**: {len(session['subagent_sessions'])}"
        )

        if session["prompts"]:
            first = session["prompts"][0]["text"][:400].replace("\n", " ")
            lines.append(f"- **First prompt**: {first}")

        lines.append("")

    # Most costly subagents
    lines.append("## Most Costly Subagents (Top 20)\n")
    costly_subs = find_costly_subagents(projects, top_n=20)

    lines.append(
        "| # | Project | Parent Session | Subagent File | Total Tokens | Input | Output |"
    )
    lines.append(
        "|---|---------|----------------|---------------|--------------|-------|--------|"
    )

    for i, (proj, session_id, sub) in enumerate(costly_subs, 1):
        u = sub["usage"]
        total_input = (
            u.get("input_tokens", 0)
            + u.get("cache_creation_input_tokens", 0)
            + u.get("cache_read_input_tokens", 0)
        )
        lines.append(
            f"| {i} | {proj} | `{session_id[:8]}...` "
            f"| `{sub.get('subagent_file', '?')}` "
            f"| {format_tokens(sub['total_tokens'])} "
            f"| {format_tokens(total_input)} "
            f"| {format_tokens(u.get('output_tokens', 0))} |"
        )

    lines.append("")

    with open(report_path, "w") as f:
        f.write("\n".join(lines))

    print(f"Report: {report_path}")
    return report_path


def print_summary(summaries, projects):
    """Print a quick summary to stdout."""
    grand_total = sum(s["total_tokens"] for s in summaries)
    total_sessions = sum(s["sessions"] for s in summaries)

    print(
        f"\nTotal: {format_tokens(grand_total)} tokens across "
        f"{total_sessions} sessions in {len(summaries)} projects\n"
    )
    print(
        f"{'Project':<50} {'Sessions':>8} {'Total Tokens':>14} {'Subagents':>10}"
    )
    print("-" * 86)

    for s in summaries[:30]:
        print(
            f"{s['project']:<50} {s['sessions']:>8,} "
            f"{format_tokens(s['total_tokens']):>14} {s['subagent_count']:>10,}"
        )

    print("\nTop 10 costliest sessions:")
    for proj, session in find_costly_sessions(projects, top_n=10):
        ts = (
            session["timestamp_start"][:10]
            if session["timestamp_start"]
            else "?"
        )
        first_prompt = ""
        if session["prompts"]:
            first_prompt = (
                session["prompts"][0]["text"][:80].replace("\n", " ")
            )
        print(
            f"  [{ts}] {proj}: {format_tokens(session['total_tokens'])} — {first_prompt}"
        )


def main():
    print("Scanning Claude Code sessions...")
    projects = analyze_all()
    print(f"Found {len(projects)} projects")

    summaries = summarize_projects(projects)
    print_summary(summaries, projects)

    write_report(projects, summaries)
    print(f"\nFull report: {OUTPUT_DIR / 'token_report.md'}")


if __name__ == "__main__":
    main()
