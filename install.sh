#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${CLAUDE_CONFIG_HOME:-$HOME/.claude}"

mkdir -p "$TARGET_DIR/skills" "$TARGET_DIR/agents" "$TARGET_DIR/commands"
rsync -a "$SOURCE_DIR/skills/" "$TARGET_DIR/skills/"
rsync -a "$SOURCE_DIR/agents/" "$TARGET_DIR/agents/"
rsync -a "$SOURCE_DIR/commands/" "$TARGET_DIR/commands/"

if [ ! -e "$TARGET_DIR/CLAUDE.md" ]; then
  cp "$SOURCE_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
fi

printf 'Claude Code Starter installed in %s\n' "$TARGET_DIR"
