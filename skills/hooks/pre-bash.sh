#!/usr/bin/env bash
# pre-bash.sh - Combined git-preflight + git-safety PreToolUse hook
# Intercepts Bash tool calls containing git operations:
# - Safety (Phase 1): blocks commits/adds that include sensitive files
# - Preflight (Phase 2): injects git status context before state-changing commands
# Exit 0 on any error — hooks must never block the user due to bugs.
set -euo pipefail
trap 'exit 0' ERR

# Guard: jq required for JSON I/O
command -v jq >/dev/null 2>&1 || exit 0

# Read tool input from stdin
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0

# Fast exit: not a git command (~0ms for non-git commands)
[[ "$COMMAND" == *"git "* ]] || exit 0

# Must be inside a git repo
timeout 2 git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ============================================================
# PHASE 1: Git Safety — scan for sensitive files (can BLOCK)
# ============================================================

SENSITIVE_PATTERNS=(
  '\.env$' '\.env\.' '\.pem$' '\.key$' '_key\.json$'
  'credentials\.json$' '\.p12$' '\.pfx$' '\.jks$'
  'id_rsa' 'id_ed25519' '\.secret$' 'token\.json$'
  'sa-key\.json$' '\.keystore$' '\.htpasswd$'
)

# Build single regex from patterns
SENSITIVE_REGEX=$(IFS='|'; echo "${SENSITIVE_PATTERNS[*]}")

if [[ "$COMMAND" =~ git\ add\ (\.|--all|-A) ]] || [[ "$COMMAND" =~ git\ commit ]]; then
  # Collect files that would be affected
  STAGED=$(timeout 3 git diff --cached --name-only 2>/dev/null || true)

  if [[ "$COMMAND" =~ git\ add ]]; then
    UNTRACKED=$(timeout 3 git ls-files --others --exclude-standard 2>/dev/null || true)
    ALL_FILES="${STAGED}"$'\n'"${UNTRACKED}"
  else
    ALL_FILES="$STAGED"
  fi

  # Scan for sensitive files
  FOUND_SENSITIVE=$(echo "$ALL_FILES" | grep -iE "$SENSITIVE_REGEX" 2>/dev/null | sed '/^$/d' | head -10 || true)

  if [[ -n "$FOUND_SENSITIVE" ]]; then
    jq -n --arg reason "BLOCKED: Sensitive files detected in staging area. Remove before committing:
${FOUND_SENSITIVE}

Use 'git reset HEAD <file>' to unstage, or add to .gitignore." \
      '{"decision": "block", "reason": $reason}'
    exit 0
  fi
fi

# ============================================================
# PHASE 2: Git Preflight — inject repo state as context
# ============================================================

STATE_CHANGING="commit|push|pull|merge|rebase|checkout|switch|stash|reset|cherry-pick"

if echo "$COMMAND" | grep -qE "git[[:space:]]+($STATE_CHANGING)"; then
  BRANCH=$(timeout 2 git branch --show-current 2>/dev/null || echo "(detached)")
  STATUS=$(timeout 3 git status --short 2>/dev/null | head -20 || echo "(git status failed)")
  LINE_COUNT=$(echo "$STATUS" | wc -l | tr -d ' ')

  CONTEXT="[git-preflight] Branch: ${BRANCH}"

  if [[ -n "$STATUS" && "$STATUS" != "(git status failed)" ]]; then
    CONTEXT="${CONTEXT}
${STATUS}"
    if [[ "$LINE_COUNT" -ge 20 ]]; then
      CONTEXT="${CONTEXT}
... (${LINE_COUNT}+ files, showing first 20)"
    fi
  else
    CONTEXT="${CONTEXT}
(clean working tree)"
  fi

  # Add ahead/behind info for push/pull
  if echo "$COMMAND" | grep -qE "git[[:space:]]+(push|pull)"; then
    AHEAD_BEHIND=$(timeout 2 git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || true)
    if [[ -n "$AHEAD_BEHIND" ]]; then
      AHEAD=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
      BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')
      CONTEXT="${CONTEXT}
Ahead: ${AHEAD}, Behind: ${BEHIND}"
    fi
  fi

  jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
  exit 0
fi

# No action needed for this command
exit 0
