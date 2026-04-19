#!/usr/bin/env bash
# post-edit-write.sh - Scope-checker PostToolUse hook
# Fires after Edit/Write on .tsx/.jsx files only.
# Runs quick grep checks for common React scoping bugs:
# 1. Nested component definitions that close over parent scope
# 2. Unsafe property access without optional chaining in JSX
# 3. useEffect with empty deps array (stale closure risk)
# Returns warnings as additionalContext — never blocks.
# Exit 0 on any error — hooks must never break the user's workflow.
set -euo pipefail
trap 'exit 0' ERR

# Guard: jq required for JSON I/O
command -v jq >/dev/null 2>&1 || exit 0

# Read tool input from stdin
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Fast exit: not a React component file (~0ms)
[[ "$FILE_PATH" =~ \.(tsx|jsx)$ ]] || exit 0

# Fast exit: file doesn't exist
[[ -f "$FILE_PATH" ]] || exit 0

WARNINGS=""

# ----------------------------------------------------------
# Check 1: Nested component definitions (parent scope leak)
# Pattern: non-exported `const FooBar = (` inside a file
# ----------------------------------------------------------
NESTED=$(grep -n 'const [A-Z][a-zA-Z]* = (' "$FILE_PATH" 2>/dev/null \
  | grep -v 'export' \
  | grep -v '// hook-ignore' \
  | head -5 || true)

if [[ -n "$NESTED" ]]; then
  WARNINGS="${WARNINGS}
Possible nested component (may close over parent scope):
$(echo "$NESTED" | head -3)"
fi

# ----------------------------------------------------------
# Check 2: Unsafe property access without optional chaining
# Pattern: {foo.bar without {foo?.bar in JSX context
# ----------------------------------------------------------
UNSAFE_ACCESS=$(grep -n '{[a-z][a-zA-Z]*\.[a-z]' "$FILE_PATH" 2>/dev/null \
  | grep -v '\?\.' \
  | grep -v '^\s*//' \
  | grep -v 'import ' \
  | grep -v 'from ' \
  | grep -v 'console\.' \
  | grep -v 'Math\.' \
  | grep -v 'Object\.' \
  | grep -v 'Array\.' \
  | grep -v 'JSON\.' \
  | grep -v 'window\.' \
  | grep -v 'document\.' \
  | grep -v 'process\.' \
  | grep -v '// hook-ignore' \
  | head -5 || true)

if [[ -n "$UNSAFE_ACCESS" ]]; then
  WARNINGS="${WARNINGS}
Possible unsafe property access (missing ?.):
$(echo "$UNSAFE_ACCESS" | head -3)"
fi

# ----------------------------------------------------------
# Check 3: useEffect with empty deps (stale closure risk)
# ----------------------------------------------------------
STALE_EFFECT=$(grep -n 'useEffect(.*\[\s*\]' "$FILE_PATH" 2>/dev/null \
  | grep -v '// hook-ignore' \
  | head -3 || true)

if [[ -z "$STALE_EFFECT" ]]; then
  # Also check multiline pattern: useEffect(\n...\n, [])
  STALE_EFFECT=$(grep -n -A5 'useEffect(' "$FILE_PATH" 2>/dev/null \
    | grep '\[\s*\]' \
    | head -3 || true)
fi

if [[ -n "$STALE_EFFECT" ]]; then
  WARNINGS="${WARNINGS}
useEffect with empty deps [] (verify no stale closures):
$(echo "$STALE_EFFECT" | head -3)"
fi

# ----------------------------------------------------------
# Return warnings if any found
# ----------------------------------------------------------
if [[ -n "$WARNINGS" ]]; then
  BASENAME=$(basename "$FILE_PATH")
  CONTEXT="[scope-checker] ${BASENAME}${WARNINGS}"
  jq -n --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
fi

exit 0
