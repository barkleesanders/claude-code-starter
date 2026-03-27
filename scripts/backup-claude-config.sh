#!/bin/bash
# Backup Claude Code configuration to boilerplate repo
# Run automatically on SessionStart or manually with /backup-config
#
# When run as SessionStart hook: quiet mode (one-line output with commit link)
# When run manually (/backup-config): verbose mode (full details)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$REPO_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REMOTE_URL="https://github.com/YOUR_USERNAME/claude-code-starter"

# Detect if running as hook (non-interactive) vs manual
QUIET=false
if [ -z "$PS1" ] && [ ! -t 0 ]; then
    QUIET=true
fi

# Source directories
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

log() {
    if [ "$QUIET" = false ]; then
        echo "$@"
    fi
}

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

log "=== Claude Code Config Backup ==="
log "Timestamp: $TIMESTAMP"
log ""

# Function to copy if exists
copy_if_exists() {
    local src="$1"
    local dest="$2"
    local name="$3"

    if [ -e "$src" ]; then
        mkdir -p "$(dirname "$dest")"
        cp -r "$src" "$dest"
        log "✓ $name"
    fi
}

# Backup main config files
log "--- Core Config ---"
copy_if_exists "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/$TIMESTAMP/CLAUDE.md" "CLAUDE.md"
copy_if_exists "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/$TIMESTAMP/settings.json" "settings.json"

# Backup agents (only .md files, not symlinks)
log ""
log "--- Agents ---"
mkdir -p "$BACKUP_DIR/$TIMESTAMP/agents"
if [ -d "$CLAUDE_DIR/agents" ]; then
    for f in "$CLAUDE_DIR/agents"/*.md; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
            cp "$f" "$BACKUP_DIR/$TIMESTAMP/agents/"
            log "✓ $(basename "$f")"
        fi
    done
fi

# Backup skills (only SKILL.md files from non-symlink directories)
log ""
log "--- Skills ---"
mkdir -p "$BACKUP_DIR/$TIMESTAMP/skills"
if [ -d "$CLAUDE_DIR/skills" ]; then
    for d in "$CLAUDE_DIR/skills"/*/; do
        if [ -d "$d" ] && [ ! -L "${d%/}" ]; then
            skill_name=$(basename "$d")
            skill_file="$d/SKILL.md"
            skill_file_lower="$d/skill.md"

            if [ -f "$skill_file" ]; then
                mkdir -p "$BACKUP_DIR/$TIMESTAMP/skills/$skill_name"
                cp "$skill_file" "$BACKUP_DIR/$TIMESTAMP/skills/$skill_name/"
                log "✓ $skill_name"
            elif [ -f "$skill_file_lower" ]; then
                mkdir -p "$BACKUP_DIR/$TIMESTAMP/skills/$skill_name"
                cp "$skill_file_lower" "$BACKUP_DIR/$TIMESTAMP/skills/$skill_name/"
                log "✓ $skill_name"
            fi
        fi
    done
fi

# Backup Codex config
log ""
log "--- Codex Config ---"
copy_if_exists "$CODEX_DIR/config.toml" "$BACKUP_DIR/$TIMESTAMP/codex/config.toml" "codex/config.toml"

# Backup zshrc relevant sections
if [ -f "$HOME/.zshrc" ]; then
    grep -E "^export (ANTHROPIC|OPENAI|CLAUDE)" "$HOME/.zshrc" > "$BACKUP_DIR/$TIMESTAMP/zshrc-exports.sh" 2>/dev/null || true
    grep -E "^alias claude" "$HOME/.zshrc" >> "$BACKUP_DIR/$TIMESTAMP/zshrc-exports.sh" 2>/dev/null || true
fi

# Update the main repo config files (for git tracking)
log ""
log "--- Updating Repo ---"
cp "$BACKUP_DIR/$TIMESTAMP/CLAUDE.md" "$REPO_DIR/CLAUDE.md" 2>/dev/null || true
cp "$BACKUP_DIR/$TIMESTAMP/settings.json" "$REPO_DIR/settings.json" 2>/dev/null || true

if [ -d "$BACKUP_DIR/$TIMESTAMP/agents" ]; then
    mkdir -p "$REPO_DIR/agents"
    cp "$BACKUP_DIR/$TIMESTAMP/agents"/*.md "$REPO_DIR/agents/" 2>/dev/null || true
fi

if [ -d "$BACKUP_DIR/$TIMESTAMP/skills" ]; then
    for skill_dir in "$BACKUP_DIR/$TIMESTAMP/skills"/*/; do
        if [ -d "$skill_dir" ]; then
            skill_name=$(basename "$skill_dir")
            mkdir -p "$REPO_DIR/skills/$skill_name"
            cp -r "$skill_dir"/* "$REPO_DIR/skills/$skill_name/" 2>/dev/null
        fi
    done
fi

# Create manifest
cat > "$BACKUP_DIR/$TIMESTAMP/manifest.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "user": "$USER"
}
EOF

# Keep only last 5 backups
cd "$BACKUP_DIR"
ls -dt */ 2>/dev/null | tail -n +6 | xargs rm -rf 2>/dev/null || true

# Auto-commit & push
cd "$REPO_DIR"
LAST_HASH=$(git rev-parse --short HEAD)
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "# Config backup: up to date → ${REMOTE_URL}/commit/${LAST_HASH}"
else
    git add -A
    FILE_COUNT=$(git diff --cached --numstat | wc -l | tr -d ' ')
    git commit -m "Auto-backup config $(date +%Y-%m-%d)" --no-verify -q 2>/dev/null
    LAST_HASH=$(git rev-parse --short HEAD)

    if git push -q 2>/dev/null; then
        echo "# Config backup: ${FILE_COUNT} files synced → ${REMOTE_URL}/commit/${LAST_HASH}"
    else
        echo "# Config backup: committed locally → ${REMOTE_URL}/commit/${LAST_HASH} (push failed, will retry)"
    fi
fi
