#!/usr/bin/env bash
# Search MEMORY.md + bd memories + per-skill reference files for a topic.
# Prints concentrated hits. Run at skill load when you need prior context.
# Usage: memory-search.sh <topic> [more words...]
set -e

[ "$#" -lt 1 ] && { echo "usage: $0 <topic>" >&2; exit 1; }
Q="$*"
MEMORY="$HOME/.claude/projects/-Users-<user>/memory"

echo "=== MEMORY.md index hits ==="
[ -f "$MEMORY/MEMORY.md" ] && grep -i -n "$Q" "$MEMORY/MEMORY.md" | head -10 || echo "(no index)"

echo
echo "=== Memory file bodies (top 3) ==="
if [ -d "$MEMORY" ]; then
  grep -l -i -r "$Q" "$MEMORY" 2>/dev/null | head -3 | while read -r f; do
    echo "--- $(basename "$f") ---"
    grep -i -B1 -A2 "$Q" "$f" | head -15
    echo
  done
fi

echo "=== bd memories ==="
if command -v bd >/dev/null 2>&1; then
  bd memories "$Q" 2>/dev/null | head -10 || echo "(bd memories not supported here)"
fi
