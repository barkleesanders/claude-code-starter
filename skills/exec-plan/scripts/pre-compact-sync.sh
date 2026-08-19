#!/usr/bin/env bash
# pre-compact-sync.sh — PreCompact hook for exec-plan
# Checks for active exec-plans and reminds agent to write handoff.md
set -euo pipefail
trap 'exit 0' ERR

PLANS_DIR="$HOME/tools/exec-plans"

# Fast exit: no exec-plans directory
[ -d "$PLANS_DIR" ] || exit 0

# Find plans with IN_PROGRESS sprints
ACTIVE_PLANS=""
for plan_dir in "$PLANS_DIR"/*/; do
  [ -d "$plan_dir" ] || continue
  plan_name=$(basename "$plan_dir")
  sprint_log="${plan_dir}sprint-log.md"

  if [ -f "$sprint_log" ] && grep -q "Status: IN_PROGRESS" "$sprint_log" 2>/dev/null; then
    ACTIVE_PLANS="${ACTIVE_PLANS}${plan_name} "
  fi
done

# Fast exit: no active plans
[ -n "$ACTIVE_PLANS" ] || exit 0

# Trim trailing space
ACTIVE_PLANS=$(echo "$ACTIVE_PLANS" | xargs)

# Emit reminder as additionalContext
jq -n --arg ctx "[exec-plan] CONTEXT COMPACTION IMMINENT. Active plans: ${ACTIVE_PLANS}. You MUST update handoff.md for each active plan with: current milestone state, what was accomplished, what is in progress, blockers, key context, next action. Write to ~/tools/exec-plans/{plan-name}/handoff.md NOW before context is lost." \
  '{"additionalContext": $ctx}'
