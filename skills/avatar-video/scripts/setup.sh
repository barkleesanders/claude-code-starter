#!/usr/bin/env bash
set -euo pipefail

# Avatar Video Pipeline — First-Time Setup
# Creates ~/.avatar-video/.env with FAL_KEY

CONFIG_DIR="$HOME/.avatar-video"
ENV_FILE="$CONFIG_DIR/.env"

echo "=== Avatar Video Pipeline Setup ==="
echo ""

# Create config directory
mkdir -p "$CONFIG_DIR"

# Check if already configured
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    if [[ -n "${FAL_KEY:-}" ]]; then
        echo "Existing FAL_KEY found in $ENV_FILE"
        read -rp "Overwrite? (y/N): " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo "Keeping existing configuration."
            echo ""
            echo "Verifying key..."
            # Test the key
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: Key $FAL_KEY" \
                "https://queue.fal.run/fal-ai/minimax/speech-02-hd" \
                -X POST -d '{"text":"test"}' 2>/dev/null || echo "000")
            if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "422" || "$HTTP_CODE" == "401" ]]; then
                if [[ "$HTTP_CODE" == "401" ]]; then
                    echo "WARNING: FAL_KEY appears invalid (401 Unauthorized)"
                else
                    echo "FAL_KEY is valid!"
                fi
            fi
            exit 0
        fi
    fi
fi

# Prompt for FAL_KEY
echo "Get your FAL_KEY at: https://fal.ai → Dashboard → API Keys"
echo ""
read -rp "Enter your FAL_KEY: " FAL_KEY

if [[ -z "$FAL_KEY" ]]; then
    echo "ERROR: FAL_KEY cannot be empty"
    exit 1
fi

# Write .env
cat > "$ENV_FILE" << EOF
FAL_KEY=$FAL_KEY
EOF
chmod 600 "$ENV_FILE"

echo ""
echo "Saved to $ENV_FILE"

# Verify the key works
echo "Verifying FAL_KEY..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    "https://fal.run/fal-ai/minimax/speech-02-hd" \
    -X POST -d '{"text":"hello"}' 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "FAL_KEY verified successfully!"
elif [[ "$HTTP_CODE" == "401" ]]; then
    echo "WARNING: FAL_KEY returned 401 Unauthorized. Check your key."
elif [[ "$HTTP_CODE" == "000" ]]; then
    echo "WARNING: Could not reach fal.ai. Check your internet connection."
else
    echo "Got HTTP $HTTP_CODE — key may be valid (some endpoints require specific inputs)."
fi

# Check nano-banana
echo ""
if command -v nano-banana &>/dev/null; then
    echo "nano-banana: installed"
else
    echo "WARNING: nano-banana not found. Install via the /nano-banana skill for image generation."
fi

# Check jq
if command -v jq &>/dev/null; then
    echo "jq: installed"
else
    echo "WARNING: jq not found. Install with: brew install jq"
fi

# Initialize costs file
if [[ ! -f "$CONFIG_DIR/costs.json" ]]; then
    echo '[]' > "$CONFIG_DIR/costs.json"
    echo ""
    echo "Initialized cost tracker at $CONFIG_DIR/costs.json"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Usage:"
echo "  # Full pipeline (text → video)"
echo '  ~/.claude/skills/avatar-video/scripts/generate-avatar.sh "Your script here"'
echo ""
echo "  # Individual steps"
echo '  ~/.claude/skills/avatar-video/scripts/minimax-tts.sh "Text to speak" --voice Friendly_Person'
echo '  ~/.claude/skills/avatar-video/scripts/omnihuman-lipsync.sh --image portrait.png --audio speech.mp3'
