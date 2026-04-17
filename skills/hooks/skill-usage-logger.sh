#!/usr/bin/env bash
# PostToolUse hook (Skill/Agent): log skill/agent invocations with outcome.
set -e
INPUT=$(cat 2>/dev/null || echo '{}')
printf '%s' "$INPUT" | python3 "$HOME/.claude/skills/hooks/skill-usage-logger.py" 2>/dev/null || true
exit 0
