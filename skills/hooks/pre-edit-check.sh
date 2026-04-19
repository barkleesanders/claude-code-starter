#!/usr/bin/env bash
# PreToolUse hook for Edit: warn when attempting Edit on a file that hasn't
# been Read in this session. Prevents the frustrating "File has not been
# read yet. Read it first before writing to it." error.
#
# Claude Code's Edit tool tracks whether a file was Read in the conversation.
# cat, head, tail, grep, Bash, and even the Write tool (sometimes) do NOT
# count. Only the Read tool counts.
#
# This hook inspects each Edit call and:
#   - Exits 0 silently if the file was tracked as Read/Written this session
#   - Prints a reminder to stderr (shown to Claude) if not tracked
#
# The hook NEVER blocks Edit. It just gives Claude a nudge so the actual
# Edit call can succeed on the first try instead of failing and retrying.
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only act on Edit
[ "$TOOL_NAME" = "Edit" ] || exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
[ -n "$FILE_PATH" ] || exit 0

TRACK_DIR="${TMPDIR:-/tmp}/claude-file-reads"
TRACK_FILE="${TRACK_DIR}/${SESSION_ID}.txt"

# If tracking file doesn't exist, session just started — can't know for sure.
if [ ! -f "$TRACK_FILE" ]; then
  exit 0
fi

# Check if this file was read/written in the session
if grep -Fxq "$FILE_PATH" "$TRACK_FILE" 2>/dev/null; then
  exit 0
fi

# Not tracked — warn on stderr (visible to Claude as hook feedback)
cat >&2 <<EOF
⚠ Edit on "$FILE_PATH" will likely fail: the Edit tool requires that file
  to have been read with the Read tool first in this session. cat/head/tail
  via Bash do NOT count. Only the Read tool counts.

  Fix: call Read on this file before retrying Edit. Example:
    Read(file_path="$FILE_PATH")
    Edit(file_path="$FILE_PATH", old_string="...", new_string="...")
EOF

# Exit 0 — advisory only, don't block
exit 0
