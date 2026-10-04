#!/usr/bin/env bash
set -euo pipefail

# Infinite Talk Lip-Sync via fal.ai
# Budget lip-sync: cheaper than OmniHuman, supports up to 10 minutes
#
# Usage:
#   infinitetalk-lipsync.sh --image <path> --audio <path> [options]
#
# Options:
#   --image <path>      Portrait image (local file or URL)
#   --audio <path>      Audio file (local file or URL)
#   --resolution <res>  480p or 720p (default: 720p)
#   --output <name>     Output filename without extension
#   --dir <path>        Output directory (default: current)
#   --url-only          Print video URL instead of downloading

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.avatar-video"
ENV_FILE="$CONFIG_DIR/.env"
ENDPOINT="fal-ai/infinitetalk"

# Load FAL_KEY
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
fi

if [[ -z "${FAL_KEY:-}" ]]; then
    echo "ERROR: FAL_KEY not found. Run setup: ~/.claude/skills/avatar-video/scripts/setup.sh" >&2
    exit 1
fi

# Defaults
IMAGE_PATH=""
AUDIO_PATH=""
RESOLUTION="720p"
OUTPUT=""
OUTPUT_DIR="."
URL_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image) IMAGE_PATH="$2"; shift 2 ;;
        --audio) AUDIO_PATH="$2"; shift 2 ;;
        --resolution) RESOLUTION="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --dir) OUTPUT_DIR="$2"; shift 2 ;;
        --url-only) URL_ONLY=true; shift ;;
        --help|-h)
            echo "Usage: infinitetalk-lipsync.sh --image <path> --audio <path> [options]"
            echo ""
            echo "Options:"
            echo "  --image <path>      Portrait image (local file or URL)"
            echo "  --audio <path>      Audio file (local file or URL) — up to 10 minutes"
            echo "  --resolution <res>  480p or 720p (default: 720p)"
            echo "  --output <name>     Output filename without extension"
            echo "  --dir <path>        Output directory"
            echo "  --url-only          Print video URL only"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$IMAGE_PATH" ]]; then
    echo "ERROR: --image is required" >&2
    exit 1
fi

if [[ -z "$AUDIO_PATH" ]]; then
    echo "ERROR: --audio is required" >&2
    exit 1
fi

# Default output name
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="infinitetalk-$(date +%s)"
fi

OUTPUT_PATH="$OUTPUT_DIR/${OUTPUT}.mp4"

# Upload local files to fal.ai storage if needed
upload_to_fal() {
    local filepath="$1"
    local content_type="$2"

    # If already a URL, return as-is
    if [[ "$filepath" == http* ]]; then
        echo "$filepath"
        return
    fi

    if [[ ! -f "$filepath" ]]; then
        echo "ERROR: File not found: $filepath" >&2
        return 1
    fi

    echo "  Uploading $(basename "$filepath")..." >&2

    # Get upload URL from fal.ai
    INITIATE_RESPONSE=$(curl -s -X POST "https://fal.ai/api/storage/upload/initiate" \
        -H "Authorization: Key $FAL_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"file_name\": \"$(basename "$filepath")\", \"content_type\": \"$content_type\"}")

    UPLOAD_URL=$(echo "$INITIATE_RESPONSE" | jq -r '.upload_url // empty')
    FILE_URL=$(echo "$INITIATE_RESPONSE" | jq -r '.file_url // empty')

    if [[ -z "$UPLOAD_URL" || -z "$FILE_URL" ]]; then
        # Fallback: direct upload
        FILE_URL=$(curl -s -X POST "https://fal.ai/api/storage/upload" \
            -H "Authorization: Key $FAL_KEY" \
            -H "Content-Type: $content_type" \
            --data-binary "@$filepath" | jq -r '.url // empty')

        if [[ -z "$FILE_URL" ]]; then
            echo "ERROR: Failed to upload $filepath" >&2
            return 1
        fi
        echo "$FILE_URL"
        return
    fi

    # Upload to presigned URL
    curl -s -X PUT "$UPLOAD_URL" \
        -H "Content-Type: $content_type" \
        --data-binary "@$filepath" >/dev/null

    echo "$FILE_URL"
}

echo "Infinite Talk Lip-Sync"
echo "  Image: $IMAGE_PATH"
echo "  Audio: $AUDIO_PATH"
echo "  Resolution: $RESOLUTION"
echo ""

# Upload files
IMAGE_URL=$(upload_to_fal "$IMAGE_PATH" "image/png")
AUDIO_URL=$(upload_to_fal "$AUDIO_PATH" "audio/mpeg")

echo ""
echo "Submitting to Infinite Talk..."

# Build payload
PAYLOAD=$(jq -n \
    --arg image_url "$IMAGE_URL" \
    --arg audio_url "$AUDIO_URL" \
    --arg resolution "$RESOLUTION" \
    '{image_url: $image_url, audio_url: $audio_url, resolution: $resolution}')

# Submit to queue
QUEUE_RESPONSE=$(curl -s -X POST "https://queue.fal.run/$ENDPOINT" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

REQUEST_ID=$(echo "$QUEUE_RESPONSE" | jq -r '.request_id // empty')

if [[ -z "$REQUEST_ID" ]]; then
    # Try synchronous as fallback for short clips
    RESPONSE=$(curl -s -X POST "https://fal.run/$ENDPOINT" \
        -H "Authorization: Key $FAL_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD")

    VIDEO_URL=$(echo "$RESPONSE" | jq -r '.video.url // empty')

    if [[ -z "$VIDEO_URL" ]]; then
        echo "ERROR: Failed to submit job" >&2
        echo "${QUEUE_RESPONSE}" >&2
        exit 1
    fi

    DURATION=$(echo "$RESPONSE" | jq -r '.duration // 0')
else
    echo "  Request ID: $REQUEST_ID"
    echo "  Polling for result..."

    # Poll queue
    STATUS_URL="https://queue.fal.run/$ENDPOINT/requests/$REQUEST_ID/status"
    RESULT_URL="https://queue.fal.run/$ENDPOINT/requests/$REQUEST_ID"

    MAX_POLLS=300  # 10 minutes at 2s intervals
    POLL_COUNT=0
    while [[ $POLL_COUNT -lt $MAX_POLLS ]]; do
        STATUS=$(curl -s -H "Authorization: Key $FAL_KEY" "$STATUS_URL" 2>/dev/null || echo '{}')
        if ! echo "$STATUS" | jq empty 2>/dev/null; then
            STATUS='{"status":"IN_QUEUE"}'
        fi
        QUEUE_STATUS=$(echo "$STATUS" | jq -r '.status // "IN_QUEUE"')

        if [[ "$QUEUE_STATUS" == "COMPLETED" ]]; then
            echo "  Done!"
            break
        elif [[ "$QUEUE_STATUS" == "FAILED" ]]; then
            echo "ERROR: Infinite Talk generation failed" >&2
            echo "$STATUS" >&2
            exit 1
        fi

        # Progress every 30s
        if [[ $((POLL_COUNT % 15)) -eq 0 && $POLL_COUNT -gt 0 ]]; then
            ELAPSED=$((POLL_COUNT * 2))
            echo "  Still processing... (${ELAPSED}s elapsed, status: $QUEUE_STATUS)"
        fi

        POLL_COUNT=$((POLL_COUNT + 1))
        sleep 2
    done

    if [[ $POLL_COUNT -ge $MAX_POLLS ]]; then
        echo "ERROR: Timed out after 10 minutes. Check request $REQUEST_ID manually." >&2
        exit 1
    fi

    # Get result
    RESPONSE=$(curl -s -H "Authorization: Key $FAL_KEY" "$RESULT_URL")
    VIDEO_URL=$(echo "$RESPONSE" | jq -r '.video.url // empty')
    DURATION=$(echo "$RESPONSE" | jq -r '.duration // 0')

    if [[ -z "$VIDEO_URL" ]]; then
        echo "ERROR: No video URL in response" >&2
        echo "$RESPONSE" >&2
        exit 1
    fi
fi

if [[ "$URL_ONLY" == true ]]; then
    echo "$VIDEO_URL"
else
    # Download video
    mkdir -p "$OUTPUT_DIR"
    curl -s -o "$OUTPUT_PATH" "$VIDEO_URL"
    echo ""
    echo "Video saved: $OUTPUT_PATH"
    echo "  Duration: ${DURATION}s"
    echo "  URL: $VIDEO_URL"
fi

# Log cost — 480p: $0.03/s, 720p: $0.06/s
if [[ "$DURATION" != "0" && "$DURATION" != "null" ]]; then
    if [[ "$RESOLUTION" == "480p" ]]; then
        COST=$(echo "scale=4; $DURATION * 0.03" | bc)
        RATE="0.03"
    else
        COST=$(echo "scale=4; $DURATION * 0.06" | bc)
        RATE="0.06"
    fi
else
    COST="0"
    RATE="0.06"
fi

COSTS_FILE="$CONFIG_DIR/costs.json"
if [[ -f "$COSTS_FILE" ]]; then
    COST_ENTRY=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg step "lipsync" \
        --arg engine "infinitetalk" \
        --arg resolution "$RESOLUTION" \
        --arg duration "$DURATION" \
        --arg cost "$COST" \
        --arg image "$IMAGE_PATH" \
        --arg audio "$AUDIO_PATH" \
        --arg output "$OUTPUT_PATH" \
        --arg video_url "$VIDEO_URL" \
        '{timestamp: $ts, step: $step, engine: $engine, resolution: $resolution, duration_s: $duration, cost: $cost, image: $image, audio: $audio, output: $output, video_url: $video_url}')

    jq ". + [$COST_ENTRY]" "$COSTS_FILE" > "${COSTS_FILE}.tmp" && mv "${COSTS_FILE}.tmp" "$COSTS_FILE"
fi

echo "  Cost: ~\$$COST (${DURATION}s @ \$$RATE/s)"
