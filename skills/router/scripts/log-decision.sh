#!/usr/bin/env bash
# Append one routing decision to the decisions log (the self-improvement corpus).
# Usage: log-decision.sh "<task summary>" "<skill(s) chosen>" "<outcome: worked|partial|wrong|unknown>" ["<note>"]
set -euo pipefail
STATE="$HOME/.claude/state/router"
mkdir -p "$STATE"
LOG="$STATE/decisions.jsonl"
task="${1:-}"; skills="${2:-}"; outcome="${3:-unknown}"; note="${4:-}"
# ISO-ish timestamp (portable; no GNU date needed)
ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
# JSON-escape via python (always present on this Mac)
python3 - "$ts" "$task" "$skills" "$outcome" "$note" >> "$LOG" <<'PY'
import json,sys
ts,task,skills,outcome,note=sys.argv[1:6]
print(json.dumps({"ts":ts,"task":task,"skills":skills,"outcome":outcome,"note":note}))
PY
echo "router: logged decision ($outcome) -> $LOG"
