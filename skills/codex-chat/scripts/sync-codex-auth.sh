#!/usr/bin/env bash
# sync-codex-auth.sh — Sync cli-proxy-api Codex tokens into Codex CLI auth.json
# Usage: sync-codex-auth.sh [TOKEN_FILE]
# Default token file: ~/.cli-proxy-api/codex-you@example.com.json

set -euo pipefail

TOKEN_FILE="${1:-$HOME/.cli-proxy-api/codex-you@example.com.json}"
AUTH_FILE="$HOME/.codex/auth.json"

if [ ! -f "$TOKEN_FILE" ]; then
  echo "[sync-codex-auth] Token file not found: $TOKEN_FILE"
  exit 1
fi

if [ ! -f "$AUTH_FILE" ]; then
  echo "[sync-codex-auth] Codex auth.json not found: $AUTH_FILE"
  exit 1
fi

# Extract tokens from cli-proxy-api format
ACCESS_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d['access_token'])")
REFRESH_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d['refresh_token'])")
ID_TOKEN=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d['id_token'])")
ACCOUNT_ID=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d['account_id'])")
LAST_REFRESH=$(python3 -c "import json; d=json.load(open('$TOKEN_FILE')); print(d['last_refresh'])")

# Convert last_refresh from "2026-03-18T19:27:27-07:00" to ISO8601 UTC
LAST_REFRESH_UTC=$(python3 -c "
from datetime import datetime, timezone
import sys
ts = '$LAST_REFRESH'
try:
    dt = datetime.fromisoformat(ts)
    print(dt.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000000Z'))
except:
    print(ts)
")

# Build new auth.json preserving Codex's expected format
python3 -c "
import json

auth = {
    'auth_mode': 'chatgpt',
    'OPENAI_API_KEY': None,
    'tokens': {
        'id_token': '''$ID_TOKEN''',
        'access_token': '''$ACCESS_TOKEN''',
        'refresh_token': '''$REFRESH_TOKEN''',
        'account_id': '$ACCOUNT_ID'
    },
    'last_refresh': '$LAST_REFRESH_UTC'
}

with open('$AUTH_FILE', 'w') as f:
    json.dump(auth, f, indent=2)
    f.write('\n')

print('[sync-codex-auth] Updated $AUTH_FILE')
print(f'  account_id: $ACCOUNT_ID')
print(f'  last_refresh: $LAST_REFRESH_UTC')
print(f'  access_token: ...{\"$ACCESS_TOKEN\"[-20:]}')
print(f'  refresh_token: {\"$REFRESH_TOKEN\"[:30]}...')
"
