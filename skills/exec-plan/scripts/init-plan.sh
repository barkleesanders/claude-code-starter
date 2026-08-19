#!/usr/bin/env bash
# init-plan.sh — Create exec-plan directory structure with template files
# Usage: bash ~/.claude/skills/exec-plan/scripts/init-plan.sh "plan name"
set -euo pipefail

PLAN_NAME="${1:?Usage: init-plan.sh <plan-name>}"
# Sanitize to kebab-case
PLAN_SLUG=$(echo "$PLAN_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
PLAN_DIR="$HOME/tools/exec-plans/${PLAN_SLUG}"

if [ -d "$PLAN_DIR" ]; then
  echo "Plan already exists: $PLAN_DIR"
  echo "Use '/exec-plan resume ${PLAN_SLUG}' to continue."
  exit 0
fi

mkdir -p "$PLAN_DIR"

# plan.md
cat > "$PLAN_DIR/plan.md" << EOF
# Execution Plan: ${PLAN_NAME}

## Purpose
{What is being built and why. A stranger should understand the goal.}

## Context
- **Repository:** {repo path}
- **Branch:** exec-plan/${PLAN_SLUG}
- **Key files:** {entry points}
- **Dependencies:** {external deps}
- **Constraints:** {limits}

## Progress
- [ ] **M1: {Milestone 1}** -- {description}
  - Acceptance: {testable criteria}

## Surprises
{Updated during execution with timestamps}

## Decision Log
See decisions.md for full log.

## Retrospective
{Filled at close}

## Self-Contained Recovery Instructions
- Navigate: \`cd {repo-path}\`
- Branch: \`git checkout exec-plan/${PLAN_SLUG}\`
- Install: \`{install command}\`
- Test: \`{test command}\`
- Current milestone: M1
- Sprint contract: See ~/tools/exec-plans/${PLAN_SLUG}/sprint-log.md
- Evidence: See ~/tools/exec-plans/${PLAN_SLUG}/evidence.md
EOF

# sprint-log.md
cat > "$PLAN_DIR/sprint-log.md" << 'EOF'
# Sprint Log

Sprint contracts and evaluator verdicts for this execution plan.
Each sprint section is appended chronologically.

---
EOF

# evidence.md
cat > "$PLAN_DIR/evidence.md" << 'EOF'
# Evidence Log

Test results, command outputs, and measurements collected during execution.
Each entry is appended chronologically with timestamps.

---
EOF

# decisions.md
cat > "$PLAN_DIR/decisions.md" << 'EOF'
# Decision Log

Architecture and design decisions with rationale.
Each decision is numbered sequentially.

---
EOF

# handoff.md
cat > "$PLAN_DIR/handoff.md" << 'EOF'
# Handoff Document

This file is updated before context compaction or session end.
It contains everything a new session needs to resume work.

Status: No handoff written yet. This is a fresh plan.
EOF

echo "Created exec-plan at: $PLAN_DIR"
echo "Files: plan.md, sprint-log.md, evidence.md, decisions.md, handoff.md"
