#!/usr/bin/env bash
#
# Safe JSON config mutator with auto-backup, validation, and rollback.
#
# Usage:
#   json-patch.sh <config-path> '<jq-expression>' [options]
#
# Options:
#   --validate-cmd "<cmd>"   Shell command to run after patch; rollback if non-zero.
#                            Example: --validate-cmd "openclaw doctor 2>&1 | grep -qv 'Unrecognized key'"
#   --restart "<svc>"        systemd service to restart after patch; rollback if not active after 5s.
#   --dry-run                Show what would change without writing.
#   --diff                   Print unified diff of before/after (always shown on failure).
#
# Exit codes:
#   0  success
#   1  invalid arguments / missing deps
#   2  jq patch produced invalid JSON
#   3  validate-cmd failed (rolled back)
#   4  service restart failed (rolled back)
#
# Examples:
#   # Change LCM mode to inline with schema validation and gateway restart
#   json-patch.sh /root/.openclaw/openclaw.json \
#     '.plugins.entries["lossless-claw"].config.proactiveThresholdCompactionMode = "inline"' \
#     --validate-cmd "python3 -m json.tool /root/.openclaw/openclaw.json > /dev/null" \
#     --restart openclaw-gateway

set -euo pipefail

if [ "$#" -lt 2 ]; then
  sed -n '/^# Usage/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

FILE="$1"; shift
EXPR="$1"; shift
VALIDATE_CMD=""
RESTART_SVC=""
DRY_RUN=0
SHOW_DIFF=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-cmd) VALIDATE_CMD="$2"; shift 2 ;;
    --restart)      RESTART_SVC="$2";  shift 2 ;;
    --dry-run)      DRY_RUN=1;         shift   ;;
    --diff)         SHOW_DIFF=1;       shift   ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -f "$FILE" ] || { echo "not a file: $FILE" >&2; exit 1; }

BACKUP="${FILE}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$FILE" "$BACKUP"

TMP=$(mktemp)
if ! jq "$EXPR" "$FILE" > "$TMP" 2>/dev/null; then
  echo "jq expression failed; not modifying $FILE" >&2
  rm -f "$TMP" "$BACKUP"
  exit 2
fi

# Validate JSON
if ! python3 -m json.tool "$TMP" > /dev/null 2>&1; then
  echo "patch produced invalid JSON; not modifying $FILE" >&2
  rm -f "$TMP" "$BACKUP"
  exit 2
fi

if [ "$SHOW_DIFF" = "1" ] || [ "$DRY_RUN" = "1" ]; then
  diff -u "$FILE" "$TMP" || true
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "dry-run: no changes written; backup $BACKUP removed"
  rm -f "$TMP" "$BACKUP"
  exit 0
fi

mv "$TMP" "$FILE"
echo "patched $FILE (backup: $BACKUP)"

rollback() {
  echo "ROLLING BACK to $BACKUP" >&2
  cp "$BACKUP" "$FILE"
}

if [ -n "$VALIDATE_CMD" ]; then
  if ! bash -c "$VALIDATE_CMD"; then
    rollback
    exit 3
  fi
fi

if [ -n "$RESTART_SVC" ]; then
  if ! systemctl restart "$RESTART_SVC"; then
    rollback; systemctl restart "$RESTART_SVC" || true
    exit 4
  fi
  sleep 5
  if ! systemctl is-active --quiet "$RESTART_SVC"; then
    echo "service $RESTART_SVC not active after restart" >&2
    journalctl -u "$RESTART_SVC" --since '30 seconds ago' --no-pager | tail -20 >&2
    rollback; systemctl restart "$RESTART_SVC" || true
    exit 4
  fi
fi

echo "ok"
