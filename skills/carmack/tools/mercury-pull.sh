#!/usr/bin/env bash
# Pull Mercury business account data (Example LLC).
# Token stored at ~/.config/mercury/token — mode 600.
# Usage:
#   mercury-pull.sh accounts          # list accounts + balances
#   mercury-pull.sh txns [limit]      # checking transactions (default 200)
#   mercury-pull.sh savings [limit]   # savings transactions
#   mercury-pull.sh summary           # monthly-burn summary by vendor
set -euo pipefail
source ~/.config/mercury/token
API="https://api.mercury.com/api/v1"
CHECKING_ID="ebe4cf98-2768-11ef-88cc-fb0b11291459"
SAVINGS_ID="ebeafcf6-2768-11ef-88cc-d7398e60f325"
mode="${1:-summary}"
case "$mode" in
  accounts)
    curl -sf --max-time 15 -H "Authorization: Bearer $MERCURY_TOKEN" "$API/accounts" | python3 -m json.tool
    ;;
  txns)
    lim="${2:-200}"
    curl -sf --max-time 20 -H "Authorization: Bearer $MERCURY_TOKEN" \
      "$API/account/$CHECKING_ID/transactions?limit=$lim&offset=0"
    ;;
  savings)
    lim="${2:-200}"
    curl -sf --max-time 20 -H "Authorization: Bearer $MERCURY_TOKEN" \
      "$API/account/$SAVINGS_ID/transactions?limit=$lim&offset=0"
    ;;
  summary)
    curl -sf --max-time 20 -H "Authorization: Bearer $MERCURY_TOKEN" \
      "$API/account/$CHECKING_ID/transactions?limit=200&offset=0" | \
      python3 "$HOME/.claude/skills/carmack/tools/mercury-summary.py"
    ;;
  *) echo "usage: mercury-pull.sh {accounts|txns|savings|summary}"; exit 1 ;;
esac
