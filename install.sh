#!/bin/bash
# Claude Code Starter Installer

set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Claude Code Starter..."

# Check for beads (bd) — task tracking is mandatory per CLAUDE.md
if ! command -v bd >/dev/null 2>&1; then
    echo ""
    echo "WARNING: 'bd' (beads) not found."
    echo "This config uses beads for ALL task tracking (replaces TodoWrite/TaskCreate)."
    echo ""
    echo "Install with:"
    echo "  brew install steveyegge/tap/beads       # macOS"
    echo "  cargo install --git https://github.com/steveyegge/beads  # cross-platform"
    echo ""
    echo "See https://github.com/steveyegge/beads for details."
    echo ""
    read -p "Continue without bd? [y/N] " cont
    if [[ ! "$cont" =~ ^[Yy]$ ]]; then
        echo "Aborting. Install bd and re-run this script."
        exit 1
    fi
else
    echo "Found bd $(bd --version 2>/dev/null | head -1)"
fi

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
echo "Files installed:"
echo "  - 35 agents (systematic-debugging, carmack-mode-engineer, ship-working-code, ...)"
echo "  - 51 skills (/debug, /carmack, /ship, /safety-audit, /token-usage, ...)"
echo "  - 26 commands (incl. workflows/)"
echo "  - CLAUDE.md quick reference"
echo ""

# CLI tools — install everything the agents/skills reference (skip with --no-tools)
if [ -x "$SCRIPT_DIR/install-tools.sh" ] && [ "${1:-}" != "--no-tools" ]; then
    echo "─────────────────────────────────────────────────────────────"
    echo "Now installing CLI tools required by agents and skills..."
    echo "(brew, node, gh, ripgrep, ogrep, agent-browser, wrangler, vercel, rclone, ffmpeg)"
    echo "Skip with: ./install.sh --no-tools"
    echo "─────────────────────────────────────────────────────────────"
    "$SCRIPT_DIR/install-tools.sh"
    echo ""
fi

# Auto-initialize beads in the current working directory if it's a git repo
if command -v bd >/dev/null 2>&1 && [ -d "$PWD/.git" ] && [ ! -d "$PWD/.beads" ]; then
    echo "Initializing beads in current repo ($PWD)..."
    (cd "$PWD" && git config beads.role maintainer 2>/dev/null; bd init --quiet --skip-hooks 2>/dev/null) || true
    echo "  -> .beads/ created. Run 'bd ready' to find work, 'bd create' to add tasks."
    echo ""
fi

echo "Usage:"
echo "  /debug [issue]     - 5-phase bug investigation"
echo "  /carmack [issue]   - Build features, fix bugs, deep debugging"
echo "  /ship              - Safe production deployment"
echo "  /safety-audit      - Production safety checks"
echo ""
echo "Task tracking (MANDATORY per CLAUDE.md):"
echo "  bd create --title=\"...\" --type=task --priority=2   # Create before coding"
echo "  bd ready                                              # Show unblocked work"
echo "  bd close <id>                                         # Close when done"
echo ""
echo "Note: You may need to restart Claude Code for changes to take effect."
