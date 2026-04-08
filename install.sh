#!/bin/bash
# Claude Code Starter Installer

set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Code Starter..."

# Create directories if they don't exist
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$CLAUDE_DIR/skills"
mkdir -p "$CLAUDE_DIR/commands"

# Copy agents
echo "Installing agents..."
cp "$SCRIPT_DIR/agents/"*.md "$CLAUDE_DIR/agents/"

# Copy skills
echo "Installing skills..."
for skill_dir in "$SCRIPT_DIR/skills/"*/; do
    skill_name=$(basename "$skill_dir")
    mkdir -p "$CLAUDE_DIR/skills/$skill_name"
    cp -r "$skill_dir"* "$CLAUDE_DIR/skills/$skill_name/"
done

# Copy commands
echo "Installing commands..."
for cmd_file in "$SCRIPT_DIR/commands/"*.md; do
    if [ -f "$cmd_file" ]; then
        cp "$cmd_file" "$CLAUDE_DIR/commands/"
    fi
done
if [ -d "$SCRIPT_DIR/commands/workflows" ]; then
    cp -r "$SCRIPT_DIR/commands/workflows" "$CLAUDE_DIR/commands/"
fi

# Handle CLAUDE.md
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo ""
    echo "Existing CLAUDE.md found. Options:"
    echo "  1) Replace with starter version"
    echo "  2) Keep existing (skip)"
    echo "  3) Backup existing and replace"
    read -p "Choose [1/2/3]: " choice
    case $choice in
        1)
            cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
            echo "Replaced CLAUDE.md"
            ;;
        2)
            echo "Keeping existing CLAUDE.md"
            ;;
        3)
            mv "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.backup.$(date +%s)"
            cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
            echo "Backed up and replaced CLAUDE.md"
            ;;
        *)
            echo "Keeping existing CLAUDE.md"
            ;;
    esac
else
    cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    echo "Installed CLAUDE.md"
fi

# Handle settings.json
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo ""
    echo "Existing settings.json found."
    echo "Options:"
    echo "  1) Keep existing settings (recommended if already configured)"
    echo "  2) Backup and replace with starter settings"
    echo "  3) View starter settings only"
    read -p "Choose [1/2/3]: " settings_choice
    case $settings_choice in
        1)
            echo "Keeping existing settings.json"
            ;;
        2)
            mv "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.backup.$(date +%s)"
            cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
            echo "Backed up and replaced settings.json"
            ;;
        3)
            echo ""
            echo "Starter settings.json:"
            cat "$SCRIPT_DIR/settings.json"
            echo ""
            ;;
        *)
            echo "Keeping existing settings.json"
            ;;
    esac
else
    echo ""
    echo "No settings.json found. Install starter settings? [y/N]"
    read -p "> " install_settings
    if [[ "$install_settings" =~ ^[Yy]$ ]]; then
        cp "$SCRIPT_DIR/settings.json" "$CLAUDE_DIR/settings.json"
        echo "Installed settings.json"
    fi
fi

echo ""
echo "Installation complete!"
echo ""
echo "Installed:"
echo "  - 35 agents (systematic-debugging, carmack-mode-engineer, ship-working-code, ...)"
echo "  - 45+ skills (/debug, /carmack, /ship, /safety-audit, /token-usage, ...)"
echo "  - 21 commands"
echo "  - CLAUDE.md quick reference"
echo ""
echo "Usage:"
echo "  /debug [issue]     - 5-phase bug investigation"
echo "  /carmack [issue]   - Deep debugging with repro harnesses"
echo "  /ship              - Safe production deployment"
echo "  /safety-audit      - Production safety checks"
echo ""
echo "Note: You may need to restart Claude Code for changes to take effect."
