#!/usr/bin/env bash
# ralph-prd-status.sh — Ralph PRD finish-line predicate for loop-runner.
#
# Exit 0 iff prd.json has at least one userStory AND every userStory has
# passes:true. Otherwise exit 1. Used as the loop-runner `--stop "target=…"`
# command so a Ralph build's loop ends exactly when all stories are green.
# Prints "N/M stories passing" for the ledger/log.
#
# Usage: ralph-prd-status.sh [path-to-prd.json]   (default: ./prd.json)
PRD="${1:-prd.json}"
[ -f "$PRD" ] || { echo "no $PRD here"; exit 2; }
python3 - "$PRD" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"unreadable prd.json: {e}"); sys.exit(2)
stories = d.get("userStories", []) or []
done = [s for s in stories if s.get("passes") is True]
red  = [s.get("id", "?") for s in stories if s.get("passes") is not True]
print(f"{len(done)}/{len(stories)} stories passing" + (f" (red: {', '.join(red)})" if red else ""))
sys.exit(0 if stories and len(done) == len(stories) else 1)
PY
