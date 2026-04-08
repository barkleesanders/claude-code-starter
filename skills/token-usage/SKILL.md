---
name: token-usage
description: "Analyze Claude Code token usage across all projects and sessions"
---

# /token-usage - Token Usage Analyzer

Analyze your Claude Code token usage by scanning JSONL session files in `~/.claude/projects/`.

## Usage

```
/token-usage              # All time usage
/token-usage 7            # Last 7 days
/token-usage 2025-01-15   # Since specific date
```

## What It Does

Scans all Claude Code session files and generates a markdown report with:
- **Grand totals** — total tokens across all projects and sessions
- **Per-project breakdown** — input, cache, output tokens by project
- **Costliest sessions** — top 25 sessions by token count with first prompt
- **Subagent analysis** — which subagents consumed the most tokens

## Instructions

When this skill is invoked:

1. Determine the time range from the user's argument:
   - No argument: all time
   - A number (e.g., `7`): last N days
   - A date (e.g., `2025-01-15`): since that date

2. Run the analyzer script:

```bash
# All time
python3 ~/.claude/skills/token-usage/token-usage.py

# Last N days
SINCE_DAYS=7 python3 ~/.claude/skills/token-usage/token-usage.py

# Since date
SINCE_DATE=2025-01-15 python3 ~/.claude/skills/token-usage/token-usage.py
```

3. Read and present the report from `~/.claude/usage/token_report.md`

4. Highlight key insights:
   - Which project uses the most tokens
   - Whether subagent usage is proportional
   - Any sessions that look unusually expensive
   - Cache hit ratio (cache_read vs cache_creation)

## Output Location

Reports are written to `~/.claude/usage/token_report.md`. This directory is gitignored — your usage data stays local and is never committed.

## Privacy

This tool only reads your local session files. No data is sent anywhere. Reports stay in `~/.claude/usage/` on your machine.
