#!/usr/bin/env bash
# UserPromptSubmit hook: scan the user's message for correction/success
# phrases about the last assistant turn, log candidates to feedback-pending.md.
# Never blocks — exit 0 always.
set -e
INPUT=$(cat 2>/dev/null || echo '{}')
printf '%s' "$INPUT" | python3 "$HOME/.claude/skills/hooks/feedback-logger.py" 2>/dev/null || true
exit 0
