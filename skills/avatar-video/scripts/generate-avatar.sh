#!/usr/bin/env bash
set -euo pipefail

# Avatar Video Pipeline — Full Orchestrator
# Chains: text → image (nano-banana) → voice (MiniMax Speech) → video (OmniHuman/Infinite Talk)
#
# Usage:
#   generate-avatar.sh "Your script text" [options]
#
# Options:
#   --quality <level>     premium (OmniHuman) or budget (Infinite Talk). Default: premium
#   --engine <name>       omnihuman or infinitetalk (overrides --quality)
#   --voice <id>          MiniMax voice ID. Default: Friendly_Person
#   --voice-speed <float> Speech speed 0.5-2.0. Default: 1.0
#   --image <path>        Skip image gen, use existing portrait
#   --audio <path>        Skip voice gen, use existing audio
#   --image-prompt <str>  Custom prompt for portrait generation
#   --output <name>       Output basename. Default: avatar-{timestamp}
#   --dir <path>          Output directory. Default: current
#   --costs               Show cost summary and exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.avatar-video"
ENV_FILE="$CONFIG_DIR/.env"

# Load FAL_KEY
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

# Defaults
QUALITY="premium"
ENGINE=""
VOICE_ID="Friendly_Person"
VOICE_SPEED="1.0"
IMAGE_PATH=""
AUDIO_PATH=""
IMAGE_PROMPT=""
OUTPUT=""
OUTPUT_DIR="."
SHOW_COSTS=false
TEXT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quality) QUALITY="$2"; shift 2 ;;
        --engine) ENGINE="$2"; shift 2 ;;
        --voice) VOICE_ID="$2"; shift 2 ;;
        --voice-speed) VOICE_SPEED="$2"; shift 2 ;;
        --image) IMAGE_PATH="$2"; shift 2 ;;
        --audio) AUDIO_PATH="$2"; shift 2 ;;
        --image-prompt) IMAGE_PROMPT="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --dir) OUTPUT_DIR="$2"; shift 2 ;;
        --costs) SHOW_COSTS=true; shift ;;
        --help|-h)
            echo "Usage: generate-avatar.sh \"Your script text\" [options]"
            echo ""
            echo "Options:"
            echo "  --quality <level>     premium (OmniHuman) or budget (Infinite Talk)"
            echo "  --engine <name>       omnihuman or infinitetalk (overrides --quality)"
            echo "  --voice <id>          MiniMax voice: Friendly_Person, Wise_Woman, Deep_Voice_Man, etc."
            echo "  --voice-speed <float> Speech speed 0.5-2.0 (default: 1.0)"
            echo "  --image <path>        Skip image gen, use existing portrait"
            echo "  --audio <path>        Skip voice gen, use existing audio"
            echo "  --image-prompt <str>  Custom prompt for portrait generation"
            echo "  --output <name>       Output basename (default: avatar-{timestamp})"
            echo "  --dir <path>          Output directory (default: current)"
            echo "  --costs               Show cost summary and exit"
            echo ""
            echo "Examples:"
            echo '  generate-avatar.sh "Hello, I am your assistant" --quality premium'
            echo '  generate-avatar.sh "Welcome" --engine infinitetalk --voice Deep_Voice_Man'
            echo '  generate-avatar.sh "Hi there" --image portrait.png --voice Calm_Woman'
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

# Show costs
if [[ "$SHOW_COSTS" == true ]]; then
    COSTS_FILE="$CONFIG_DIR/costs.json"
    if [[ ! -f "$COSTS_FILE" ]] || [[ "$(cat "$COSTS_FILE")" == "[]" ]]; then
        echo "No costs recorded yet."
        exit 0
    fi

    echo "=== Avatar Video Cost Summary ==="
    echo ""

    # Total by step
    echo "By step:"
    jq -r 'group_by(.step) | .[] | "  \(.[0].step): $\(map(.cost | tonumber) | add | . * 10000 | round / 10000) (\(length) generations)"' "$COSTS_FILE"
    echo ""

    # Total by engine
    echo "By engine:"
    jq -r 'map(select(.engine)) | group_by(.engine) | .[] | "  \(.[0].engine): $\(map(.cost | tonumber) | add | . * 10000 | round / 10000) (\(length) generations)"' "$COSTS_FILE" 2>/dev/null || true
    echo ""

    # Grand total
    TOTAL=$(jq '[.[].cost | tonumber] | add | . * 10000 | round / 10000' "$COSTS_FILE")
    COUNT=$(jq 'length' "$COSTS_FILE")
    echo "Total: \$$TOTAL across $COUNT operations"
    echo ""

    # Last 5
    echo "Recent:"
    jq -r '.[-5:] | reverse | .[] | "  \(.timestamp) | \(.step) | \(.engine // .model // "-") | $\(.cost)"' "$COSTS_FILE"

    exit 0
fi

if [[ -z "$TEXT" && -z "$AUDIO_PATH" ]]; then
    echo "ERROR: Provide script text or --audio <path>" >&2
    echo "Usage: generate-avatar.sh \"Your script\" [options]" >&2
    exit 1
fi

# Resolve engine from quality
if [[ -z "$ENGINE" ]]; then
    case "$QUALITY" in
        premium) ENGINE="omnihuman" ;;
        budget) ENGINE="infinitetalk" ;;
        *) echo "ERROR: --quality must be 'premium' or 'budget'" >&2; exit 1 ;;
    esac
fi

# Default output name
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="avatar-$(date +%s)"
fi

mkdir -p "$OUTPUT_DIR"

# Initialize costs file if needed
if [[ ! -f "$CONFIG_DIR/costs.json" ]]; then
    mkdir -p "$CONFIG_DIR"
    echo '[]' > "$CONFIG_DIR/costs.json"
fi

echo "=========================================="
echo "  Avatar Video Pipeline"
echo "=========================================="
echo "  Engine: $ENGINE"
echo "  Voice: $VOICE_ID (speed: $VOICE_SPEED)"
if [[ -n "$TEXT" ]]; then
    echo "  Script: ${TEXT:0:60}$([ ${#TEXT} -gt 60 ] && echo '...')"
fi
if [[ -n "$IMAGE_PATH" ]]; then
    echo "  Image: $IMAGE_PATH (provided)"
fi
if [[ -n "$AUDIO_PATH" ]]; then
    echo "  Audio: $AUDIO_PATH (provided)"
fi
echo "  Output: $OUTPUT_DIR/$OUTPUT.mp4"
echo "=========================================="
echo ""

PIPELINE_START=$(date +%s)

# ─── Step 1: Image Generation ───────────────────────────────────────────────

if [[ -z "$IMAGE_PATH" ]]; then
    echo "Step 1/3: Generating portrait image..."

    if ! command -v nano-banana &>/dev/null; then
        echo "ERROR: nano-banana not found. Install via /nano-banana skill." >&2
        exit 1
    fi

    if [[ -z "$IMAGE_PROMPT" ]]; then
        IMAGE_PROMPT="professional headshot portrait photo, neutral background, studio lighting, looking directly at camera, shoulders visible, high quality"
    fi

    IMAGE_PATH="$OUTPUT_DIR/${OUTPUT}-portrait.png"

    nano-banana "$IMAGE_PROMPT" -s 1K -o "${OUTPUT}-portrait" -d "$OUTPUT_DIR"

    # nano-banana outputs as .png — find the actual file
    if [[ ! -f "$IMAGE_PATH" ]]; then
        # Try common nano-banana output patterns
        FOUND=$(find "$OUTPUT_DIR" -name "${OUTPUT}-portrait*" -type f 2>/dev/null | head -1)
        if [[ -n "$FOUND" ]]; then
            IMAGE_PATH="$FOUND"
        else
            echo "ERROR: nano-banana did not produce expected output" >&2
            exit 1
        fi
    fi

    echo "  Portrait: $IMAGE_PATH"
    echo ""
else
    echo "Step 1/3: Using provided image: $IMAGE_PATH"
    echo ""
fi

# ─── Step 2: Voice Generation ───────────────────────────────────────────────

if [[ -z "$AUDIO_PATH" ]]; then
    echo "Step 2/3: Generating voice audio..."

    if [[ -z "${FAL_KEY:-}" ]]; then
        echo "ERROR: FAL_KEY not found. Run setup: ~/.claude/skills/avatar-video/scripts/setup.sh" >&2
        exit 1
    fi

    AUDIO_PATH="$OUTPUT_DIR/${OUTPUT}-speech.mp3"

    "$SCRIPT_DIR/minimax-tts.sh" "$TEXT" \
        --voice "$VOICE_ID" \
        --speed "$VOICE_SPEED" \
        --output "${OUTPUT}-speech" \
        --dir "$OUTPUT_DIR"

    if [[ ! -f "$AUDIO_PATH" ]]; then
        echo "ERROR: TTS did not produce expected output" >&2
        exit 1
    fi

    echo ""
else
    echo "Step 2/3: Using provided audio: $AUDIO_PATH"
    echo ""
fi

# ─── Step 3: Lip-Sync Video ────────────────────────────────────────────────

echo "Step 3/3: Generating lip-synced video ($ENGINE)..."

case "$ENGINE" in
    omnihuman)
        "$SCRIPT_DIR/omnihuman-lipsync.sh" \
            --image "$IMAGE_PATH" \
            --audio "$AUDIO_PATH" \
            --output "$OUTPUT" \
            --dir "$OUTPUT_DIR"
        ;;
    infinitetalk)
        "$SCRIPT_DIR/infinitetalk-lipsync.sh" \
            --image "$IMAGE_PATH" \
            --audio "$AUDIO_PATH" \
            --output "$OUTPUT" \
            --dir "$OUTPUT_DIR"
        ;;
    *)
        echo "ERROR: Unknown engine: $ENGINE (use omnihuman or infinitetalk)" >&2
        exit 1
        ;;
esac

PIPELINE_END=$(date +%s)
PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))

echo ""
echo "=========================================="
echo "  Pipeline Complete!"
echo "=========================================="
echo "  Video: $OUTPUT_DIR/${OUTPUT}.mp4"
echo "  Portrait: $IMAGE_PATH"
echo "  Audio: ${AUDIO_PATH}"
echo "  Duration: ${PIPELINE_DURATION}s"
echo ""
echo "  View costs: $0 --costs"
echo "=========================================="
