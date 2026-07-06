#!/usr/bin/env bash
set -euo pipefail

# MiniMax Speech TTS via fal.ai
# Converts text to speech using MiniMax Speech-02 HD or Turbo
#
# Usage:
#   minimax-tts.sh "Text to speak" [options]
#
# Options:
#   --voice <id>      Voice ID (default: Friendly_Person)
#   --speed <float>   Speech speed 0.5-2.0 (default: 1.0)
#   --pitch <int>     Pitch adjustment (default: 0)
#   --model <id>      turbo or hd (default: turbo)
#   --lang <lang>     Language boost (default: English)
#   --output <name>   Output filename without extension (default: speech-{timestamp})
#   --dir <path>      Output directory (default: current)
#   --url-only        Print audio URL instead of downloading

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.avatar-video"
ENV_FILE="$CONFIG_DIR/.env"

# Load FAL_KEY
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "${FAL_KEY:-}" ]]; then
    echo "ERROR: FAL_KEY not found. Run setup: ~/.claude/skills/avatar-video/scripts/setup.sh" >&2
    exit 1
fi

# Defaults
VOICE_ID="Friendly_Person"
SPEED=1.0
PITCH=0
MODEL="turbo"
LANG="English"
OUTPUT=""
OUTPUT_DIR="."
URL_ONLY=false
TEXT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --voice) VOICE_ID="$2"; shift 2 ;;
        --speed) SPEED="$2"; shift 2 ;;
        --pitch) PITCH="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --lang) LANG="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --dir) OUTPUT_DIR="$2"; shift 2 ;;
        --url-only) URL_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: minimax-tts.sh \"Text to speak\" [options]"
            echo ""
            echo "Options:"
            echo "  --voice <id>      Voice: Friendly_Person, Wise_Woman, Deep_Voice_Man, Calm_Woman, Casual_Guy, Lively_Girl"
            echo "  --speed <float>   Speed 0.5-2.0 (default: 1.0)"
            echo "  --pitch <int>     Pitch adjustment (default: 0)"
            echo "  --model <id>      turbo or hd (default: turbo)"
            echo "  --lang <lang>     Language boost (default: English)"
            echo "  --output <name>   Output filename without extension"
            echo "  --dir <path>      Output directory"
            echo "  --url-only        Print audio URL only"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$TEXT" ]]; then
                TEXT="$1"
            else
                TEXT="$TEXT $1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$TEXT" ]]; then
    echo "ERROR: No text provided" >&2
    echo "Usage: minimax-tts.sh \"Text to speak\" [options]" >&2
    exit 1
fi

# Resolve model endpoint
if [[ "$MODEL" == "turbo" ]]; then
    ENDPOINT="fal-ai/minimax/speech-02-hd"
elif [[ "$MODEL" == "hd" ]]; then
    ENDPOINT="fal-ai/minimax/speech-02-hd"
else
    ENDPOINT="$MODEL"
fi

# Default output name
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="speech-$(date +%s)"
fi

OUTPUT_PATH="$OUTPUT_DIR/${OUTPUT}.mp3"

echo "Generating speech..."
echo "  Voice: $VOICE_ID"
echo "  Speed: $SPEED"
echo "  Model: $MODEL"
echo "  Text: ${TEXT:0:80}$([ ${#TEXT} -gt 80 ] && echo '...')"

# Build JSON payload
PAYLOAD=$(jq -n \
    --arg text "$TEXT" \
    --arg voice_id "$VOICE_ID" \
    --argjson speed "$SPEED" \
    --argjson pitch "$PITCH" \
    --arg lang "$LANG" \
    '{
        text: $text,
        voice_setting: {
            voice_id: $voice_id,
            speed: $speed,
            vol: 1,
            pitch: $pitch,
            english_normalization: false
        },
        language_boost: $lang,
        output_format: "url"
    }')

# Use synchronous endpoint (TTS is fast, typically <5s)
RESPONSE=$(curl -s --max-time 60 -X POST "https://fal.run/$ENDPOINT" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

AUDIO_URL=$(echo "$RESPONSE" | jq -r '.audio.url // empty')

if [[ -z "$AUDIO_URL" ]]; then
    echo "ERROR: Failed to generate speech" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

DURATION_MS=$(echo "$RESPONSE" | jq -r '.duration_ms // 0')

if [[ "$URL_ONLY" == true ]]; then
    echo "$AUDIO_URL"
else
    # Download audio
    mkdir -p "$OUTPUT_DIR"
    curl -s -o "$OUTPUT_PATH" "$AUDIO_URL"
    echo ""
    echo "Audio saved: $OUTPUT_PATH"
    echo "  Duration: ${DURATION_MS}ms"
    echo "  URL: $AUDIO_URL"
fi

# Log cost
CHAR_COUNT=${#TEXT}
# Turbo: $0.06/1K chars, HD: $0.10/1K chars
if [[ "$MODEL" == "hd" ]]; then
    COST=$(echo "scale=4; $CHAR_COUNT * 0.10 / 1000" | bc)
else
    COST=$(echo "scale=4; $CHAR_COUNT * 0.06 / 1000" | bc)
fi

COSTS_FILE="$CONFIG_DIR/costs.json"
if [[ -f "$COSTS_FILE" ]]; then
    COST_ENTRY=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg step "tts" \
        --arg model "$MODEL" \
        --arg voice "$VOICE_ID" \
        --argjson chars "$CHAR_COUNT" \
        --argjson duration_ms "${DURATION_MS:-0}" \
        --arg cost "$COST" \
        --arg output "$OUTPUT_PATH" \
        '{timestamp: $ts, step: $step, model: $model, voice: $voice, chars: $chars, duration_ms: $duration_ms, cost: $cost, output: $output}')

    jq ". + [$COST_ENTRY]" "$COSTS_FILE" > "${COSTS_FILE}.tmp" && mv "${COSTS_FILE}.tmp" "$COSTS_FILE"
fi

echo "  Cost: ~\$$COST ($CHAR_COUNT chars)"
