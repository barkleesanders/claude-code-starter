#!/bin/bash
# Ensures Chrome remote debugging is active and a target tab has a warm daemon.
# Usage: source this script, then use CDP commands without "Allow" popups.
#
# The "Allow debugging" modal fires once per tab when a daemon first connects.
# This script pre-warms a daemon for the production URL so subsequent
# cdp.mjs commands connect instantly with no popup.

CDP="$HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"
PROD_URL="${1:-https://aiva-m9t.pages.dev/}"

# 1. Check Chrome is running with debugging
if ! test -f "$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"; then
  echo "[CDP] Chrome remote debugging not active. Enable at chrome://inspect/#remote-debugging"
  exit 1
fi

PORT=$(head -1 "$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort")
echo "[CDP] Chrome debugging active on port $PORT"

# 2. Find or open the production tab
TARGET=$(node "$CDP" list 2>/dev/null | grep "$PROD_URL" | awk '{print $1}' | head -1)

if [ -z "$TARGET" ]; then
  echo "[CDP] No tab open for $PROD_URL — opening one"
  open "$PROD_URL"
  sleep 3
  TARGET=$(node "$CDP" list 2>/dev/null | grep "$PROD_URL" | awk '{print $1}' | head -1)
fi

if [ -z "$TARGET" ]; then
  echo "[CDP] Could not find tab for $PROD_URL"
  exit 1
fi

echo "[CDP] Production tab: $TARGET"

# 3. Pre-warm the daemon (this triggers the Allow popup ONCE, then stays warm 20min)
node "$CDP" snap "$TARGET" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "[CDP] Daemon warm — all future commands will work without popup"
else
  echo "[CDP] Daemon failed — click Allow in Chrome, then re-run this script"
  exit 1
fi

# Export for other scripts
export CDP_TARGET="$TARGET"
echo "[CDP] Export: CDP_TARGET=$TARGET"
echo "[CDP] Usage: node \$CDP shot $TARGET"
