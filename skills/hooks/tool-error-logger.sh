#!/usr/bin/env bash
# PostToolUse hook: log tool errors to ~/.claude/tool-errors.jsonl
# so the /carmack skill can periodically classify novel patterns.
#
# Receives JSON on stdin with fields: tool_name, tool_input, tool_response.
# Hook output is ignored — exit 0 always, never block.

set -e
INPUT=$(cat 2>/dev/null || echo '{}')

# Fast path: if JSON doesn't contain is_error:true, skip
case "$INPUT" in
  *'"is_error":true'*|*'"is_error": true'*) ;;
  *) exit 0 ;;
esac

# Pipe the payload into a separate python3 invocation (no heredoc nesting)
printf '%s' "$INPUT" | python3 "$HOME/.claude/skills/hooks/tool-error-logger.py" 2>/dev/null || true
exit 0
