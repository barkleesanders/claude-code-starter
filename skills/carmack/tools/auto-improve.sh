#!/usr/bin/env bash
#
# Unified self-improvement runner. Invoked at the start of /carmack.
# Runs all scanners, surfaces any pending reviews to stdout so Claude
# can see them and act. Exit is always 0.
#
# Usage:
#   auto-improve.sh              # run all scanners, print summary
#   auto-improve.sh --clear      # archive consumed logs (after review)
#   auto-improve.sh drift        # run drift validator only
#   auto-improve.sh usage        # run usage report only
#   auto-improve.sh memory <q>   # run memory search
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_CLAUDE="$HOME/.claude"

mode="${1:-all}"
shift || true

case "$mode" in
  --clear)
    for log in tool-errors feedback skill-usage agent-outcomes; do
      f="$HOME_CLAUDE/${log}.jsonl"
      [ -f "$f" ] && mv "$f" "${f}.archived-$(date +%Y%m%d-%H%M%S)" && echo "archived $f"
    done
    rm -f "$HOME_CLAUDE/tool-errors-pending.md" "$HOME_CLAUDE/feedback-pending.md" "$HOME_CLAUDE/skill-drift.md" "$HOME_CLAUDE/skill-usage-report.md"
    exit 0
    ;;
  drift)
    "$SCRIPT_DIR/skill-drift-check.sh" "$@"
    exit 0
    ;;
  usage)
    python3 "$SCRIPT_DIR/skill-usage-report.py" "$@"
    exit 0
    ;;
  memory)
    "$SCRIPT_DIR/memory-search.sh" "$@"
    exit 0
    ;;
esac

# Default: run all scanners, print concise summary
any_pending=0
echo "=== Self-improvement scan ==="

# 1. Tool-error catalog
if [ -x "$SCRIPT_DIR/scan-tool-errors.sh" ]; then
  out=$("$SCRIPT_DIR/scan-tool-errors.sh" 2>&1 || true)
  if echo "$out" | grep -q 'novel pattern'; then
    echo "⚠  tool-errors: $(echo "$out" | tail -1)"
    any_pending=1
  fi
fi

# 2. Behavioral feedback
if python3 "$SCRIPT_DIR/scan-feedback.py" 2>/dev/null; then
  if [ -s "$HOME_CLAUDE/feedback-pending.md" ]; then
    count=$(grep -c '^## ' "$HOME_CLAUDE/feedback-pending.md" 2>/dev/null || echo 0)
    [ "$count" -gt 0 ] && echo "⚠  feedback: $count candidate(s) — review $HOME_CLAUDE/feedback-pending.md" && any_pending=1
  fi
fi

# 3. Skill-usage anomalies (only if log is big enough to be meaningful)
if [ -f "$HOME_CLAUDE/skill-usage.jsonl" ] && [ $(wc -l < "$HOME_CLAUDE/skill-usage.jsonl") -gt 20 ]; then
  python3 "$SCRIPT_DIR/skill-usage-report.py" --quiet 2>/dev/null && \
    [ -s "$HOME_CLAUDE/skill-usage-report.md" ] && \
    echo "ℹ  skill-usage-report.md updated"
fi

# 4. Memory surfacing is interactive — a CWD-aware prompt is more useful
# than running it blindly. Skipped in the batch path.

# 5. Drift check runs weekly via timestamp sentinel — skip if run <7d ago
DRIFT_STAMP="$HOME_CLAUDE/.drift-last-run"
need_drift=1
if [ -f "$DRIFT_STAMP" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$DRIFT_STAMP" 2>/dev/null || stat -c %Y "$DRIFT_STAMP") ))
  [ "$age" -lt 604800 ] && need_drift=0
fi
if [ "$need_drift" = "1" ] && [ -x "$SCRIPT_DIR/skill-drift-check.sh" ]; then
  "$SCRIPT_DIR/skill-drift-check.sh" --quiet 2>/dev/null || true
  date > "$DRIFT_STAMP"
  if [ -s "$HOME_CLAUDE/skill-drift.md" ]; then
    drift_count=$(grep -c '^- ' "$HOME_CLAUDE/skill-drift.md" 2>/dev/null || echo 0)
    [ "$drift_count" -gt 0 ] && echo "⚠  drift: $drift_count issue(s) — review $HOME_CLAUDE/skill-drift.md" && any_pending=1
  fi
fi

[ "$any_pending" = "0" ] && echo "all clear — no novel patterns, feedback, drift, or anomalies"
exit 0
