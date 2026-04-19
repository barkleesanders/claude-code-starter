#!/usr/bin/env bash
#
# Stop hook: keep the agent working until the plan and user requests are 100% done.
#
# LOGIC:
#   1. First stop attempt with real incomplete signals → block (ask agent to finish)
#   2. Second stop attempt (stop_hook_active=true) → always allow (agent reviewed and confirmed)
#   3. First stop attempt with NO signals → allow (nothing to check)
#   4. Max counter reached → always allow (safety valve)
#
# Incomplete signals:
#   - TaskCreate/TaskUpdate tool calls in transcript with pending/in_progress status
#   - Recent tool errors (is_error=true)
#   - Beads issues with status=in_progress updated within the last BEADS_WINDOW_MIN
#     minutes (default 120) — i.e., issues claimed in this working session.
#
# Env:
#   TASKMASTER_MAX       Max continuations (default: 3, 0 = infinite)
#   BEADS_WINDOW_MIN     Lookback window for in_progress beads issues (default: 120)
#   TASKMASTER_NO_BEADS  If set to "1", skip beads check entirely
#
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# --- If the hook already fired and the agent still wants to stop, let it. ---
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
  COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
  rm -f "$COUNTER_FILE"
  exit 0
fi

# --- loop guard ---
COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
MAX=${TASKMASTER_MAX:-3}

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
fi

if [ "$MAX" -gt 0 ] && [ "$COUNT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

# --- transcript analysis ---
HAS_INCOMPLETE_SIGNALS=false

if [ -f "$TRANSCRIPT" ]; then
  TAIL=$(tail -30 "$TRANSCRIPT" 2>/dev/null || true)
  if echo "$TAIL" | grep -q '"tool_name".*[Tt]ask' 2>/dev/null && \
     echo "$TAIL" | grep -q '"status".*"in_progress"\|"status".*"pending"' 2>/dev/null; then
    HAS_INCOMPLETE_SIGNALS=true
  fi
  if echo "$TAIL" | grep -q '"is_error".*true' 2>/dev/null; then
    HAS_INCOMPLETE_SIGNALS=true
  fi
fi

# --- beads analysis (in_progress issues touched in this session) ---
BEADS_BLOCK=""
BEADS_INFO=""
WINDOW_MIN=${BEADS_WINDOW_MIN:-120}

if [ "${TASKMASTER_NO_BEADS:-0}" != "1" ] && command -v bd >/dev/null 2>&1; then
  # Query each candidate beads DB and merge. Set TASKMASTER_BEADS_DIRS to
  # override (colon-separated). Default covers common layouts on Mac (~)
  # and on the VPS (~/clawd is the main OpenClaw work dir).
  DIRS="${TASKMASTER_BEADS_DIRS:-${HOME}:${HOME}/clawd}"
  BD_JSON="[]"
  OLD_IFS="$IFS"; IFS=":"
  for d in $DIRS; do
    [ -d "$d/.beads" ] || continue
    CHUNK=$(cd "$d" 2>/dev/null && bd list --status=in_progress --json 2>/dev/null || echo "[]")
    BD_JSON=$(jq -s 'add' <(echo "$BD_JSON") <(echo "$CHUNK") 2>/dev/null || echo "$BD_JSON")
  done
  IFS="$OLD_IFS"

  # Use python3 for portable ISO-8601 parsing with timezone offsets.
  # (jq's fromdateiso8601/strptime don't handle "+07:00" offsets consistently
  # across macOS jq 1.8 and Linux jq 1.7.)
  BEADS_RESULT=$(printf '%s' "$BD_JSON" | python3 -c '
import sys, json
from datetime import datetime, timezone, timedelta

window_min = int(sys.argv[1])
cutoff = datetime.now(timezone.utc) - timedelta(minutes=window_min)

try:
    raw = sys.stdin.read()
    items = json.loads(raw) if raw.strip() else []
except Exception:
    items = []

fresh, stale_count = [], 0
for it in items:
    ts = (it.get("updated_at") or "").strip()
    if not ts:
        continue
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        continue
    if dt.astimezone(timezone.utc) >= cutoff:
        fresh.append("  - " + str(it.get("id", "?")) + ": " + str(it.get("title", "")))
    else:
        stale_count += 1

print("FRESH_START")
print("\n".join(fresh))
print("FRESH_END")
print(f"STALE_COUNT={stale_count}")
' "$WINDOW_MIN")
  FRESH=$(echo "$BEADS_RESULT" | sed -n '/FRESH_START/,/FRESH_END/p' | sed '1d;$d')
  STALE_COUNT=$(echo "$BEADS_RESULT" | sed -n 's/^STALE_COUNT=//p')
  STALE_COUNT=${STALE_COUNT:-0}

  if [ -n "$FRESH" ]; then
    HAS_INCOMPLETE_SIGNALS=true
    BEADS_BLOCK=$'\n\nBeads issues still in_progress (touched in last '"$WINDOW_MIN"$' min):\n'"$FRESH"$'\n\nResolve options:\n  bd close <id>                       — mark complete\n  bd update <id> --status=open        — unclaim (put back on ready queue)\n  bd defer <id>                       — park for later (restore with bd undefer)\n  bd update <id> --status=blocked     — mark blocked'
  fi

  if [ "$STALE_COUNT" -gt 0 ]; then
    BEADS_INFO=$'\n\nNote: '"$STALE_COUNT"$' older in_progress beads issue(s) from prior sessions (run `bd list --status=in_progress` to review).'
  fi
fi

# --- decide ---
if [ "$HAS_INCOMPLETE_SIGNALS" = false ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

NEXT=$((COUNT + 1))
echo "$NEXT" > "$COUNTER_FILE"

if [ "$MAX" -gt 0 ]; then
  LABEL="TASKMASTER (${NEXT}/${MAX})"
else
  LABEL="TASKMASTER (${NEXT})"
fi

REASON="${LABEL}: Incomplete tasks or recent errors detected.

Before stopping, quickly check:
1. Any tasks still pending/in_progress? Finish or close them.
2. Any tool errors in the last few actions? Fix them.
3. Did the user's request get fully addressed?
4. BLIND SPOTS: for infra/config work, did you verify with real traffic
   (not just 'gateway started' logs)? Did adjacent systems break
   (binaries, symlinks, channel bundles, related services)? Check
   systemctl status, version string, log errors in last 2 min.
5. Did surfaced issues get fixed, not just reported? (fix-all-issues rule)

If everything is done, confirm completion briefly.${BEADS_BLOCK}${BEADS_INFO}"

jq -n --arg reason "$REASON" '{ decision: "block", reason: $reason }'
