#!/usr/bin/env bash
# PostToolUse hook: track which files have been Read/Written in this session.
# Used by pre-edit-check.sh to warn before Edit fails with
# "File has not been read yet. Read it first before writing to it."
#
# Tracks Read, Write, NotebookEdit (all tools that the Edit tool's prerequisite considers satisfied).
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TRACK_DIR="${TMPDIR:-/tmp}/claude-file-reads"
TRACK_FILE="${TRACK_DIR}/${SESSION_ID}.txt"
mkdir -p "$TRACK_DIR"

case "$TOOL_NAME" in
  Read|Write|NotebookEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$TRACK_FILE"
    fi
    ;;
  Edit)
    # After a successful Edit, Claude Code internally marks the file read
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    if [ -n "$FILE_PATH" ]; then
      echo "$FILE_PATH" >> "$TRACK_FILE"
    fi
    ;;
esac

# Rotate old tracking files (keep 7 days)
find "$TRACK_DIR" -name '*.txt' -mtime +7 -delete 2>/dev/null || true

exit 0
