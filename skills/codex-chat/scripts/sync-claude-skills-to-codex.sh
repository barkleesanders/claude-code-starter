#!/usr/bin/env bash
# sync-claude-skills-to-codex.sh — Keep ~/.codex/skills/ aligned with ~/.claude/skills/
#
# What it does:
#   1. Removes dangling symlinks in ~/.codex/skills/ (skills you deleted in Claude).
#   2. Adds a symlink in ~/.codex/skills/ for every Claude skill that doesn't have one yet.
#   3. Leaves Codex-only directories (real dirs, not symlinks) alone.
#
# Why it exists:
#   Dangling symlinks here used to be harmless, but Codex 0.128+ logs broken-skill
#   warnings on every launch. Worse, a malformed [[hooks]] block in config.toml
#   prevented launch entirely (fixed separately). This script keeps the skill set
#   in sync so the next time you delete a Claude skill, Codex doesn't trip on it.
#
# Usage:
#   bash ~/.claude/skills/codex-chat/scripts/sync-claude-skills-to-codex.sh        # sync
#   bash ~/.claude/skills/codex-chat/scripts/sync-claude-skills-to-codex.sh --dry  # preview only

set -euo pipefail

CLAUDE_SKILLS="$HOME/.claude/skills"
CODEX_SKILLS="$HOME/.codex/skills"
DRY_RUN=0

[[ "${1:-}" == "--dry" || "${1:-}" == "-n" ]] && DRY_RUN=1

mkdir -p "$CODEX_SKILLS"

removed=0
added=0
skipped=0

# 1. Remove dangling symlinks
while IFS= read -r link; do
  if [ -L "$link" ] && [ ! -e "$link" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] remove dangling: $link -> $(readlink "$link")"
    else
      rm "$link"
      echo "removed dangling: $(basename "$link")"
    fi
    removed=$((removed + 1))
  fi
done < <(find "$CODEX_SKILLS" -maxdepth 1 -type l)

# 2. Add missing symlinks for Claude skills not yet in Codex
for skill_dir in "$CLAUDE_SKILLS"/*/; do
  name=$(basename "$skill_dir")
  target="$CODEX_SKILLS/$name"

  if [ -e "$target" ] || [ -L "$target" ]; then
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] add: $name -> $skill_dir"
  else
    ln -s "$skill_dir" "$target"
    echo "added: $name"
  fi
  added=$((added + 1))
done

echo
echo "Summary: removed=$removed added=$added already-present=$skipped"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — no changes made)"
