#!/bin/bash
# email-deliverability-check.sh — /ship Phase 4.07 gate.
#
# Catches the 2026-07-13 diy-fax class: email "works" (send() resolves) but the
# message lands in SPAM because the From domain is misaligned — e.g. an APEX
# sender (fax@aivaclaims.com) delivered into a Google-Workspace mailbox on that
# same strictly-DMARC'd domain. Code review, tests, and even a resolved send()
# cannot see mailbox placement; only reading the destination mailbox can.
#
# Usage:
#   email-deliverability-check.sh <repo> [--domain <sender-domain>]
#       [--accounts a@x.com,b@y.com] [--static-only]
#
# STATIC checks (pre-deploy, always run):
#   S1  Every From-address literal in src/ + wrangler config is examined.
#       BLOCK if any sender uses an APEX domain whose MX points at a hosted
#       mailbox provider (Google/Microsoft) — that mail will be junked by the
#       provider's own strict SPF/DMARC. Senders must use a dedicated,
#       Email-Sending-onboarded subdomain (e.g. notifications.example.com).
#   S2  WARN if a From domain is not onboarded in `wrangler email sending list`
#       (requires wrangler auth; skipped when unavailable).
#
# LIVE checks (post-deploy, when --accounts given; needs gog auth per account):
#   L1  Newest message from --domain in each account (in:anywhere, 1d):
#         BLOCK if labeled SPAM.
#         BLOCK if Authentication-Results lacks dmarc=pass.
#         WARN (not block) if no message found — UNVERIFIED, trigger a real
#         send (e.g. the app's own event) and re-run; absence is not proof.
#
# Exit: 0 = pass · 1 = unverified/warn only · 2 = BLOCK
set -uo pipefail

REPO="" ; DOMAIN="" ; ACCOUNTS="" ; STATIC_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --accounts) ACCOUNTS="$2"; shift 2 ;;
    --static-only) STATIC_ONLY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) [ -z "$REPO" ] && REPO="$1" && shift || { echo "unexpected arg: $1" >&2; exit 1; } ;;
  esac
done
[ -n "$REPO" ] || { echo "usage: $0 <repo> [--domain D] [--accounts a,b] [--static-only]" >&2; exit 1; }
cd "$REPO" || { echo "no such repo: $REPO" >&2; exit 1; }

FAIL=0; WARN=0
ok()   { printf '  \033[32mok\033[0m     %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m   %s\n' "$*"; WARN=1; }
bad()  { printf '  \033[31mBLOCK\033[0m  %s\n' "$*"; FAIL=1; }

echo "Email deliverability gate — $REPO"

# ---- S1: apex-sender-into-hosted-mailbox detection --------------------------
echo "1. Static: sender From-domains"
FROMS=$(grep -rhoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
          src/ wrangler.toml wrangler.json wrangler.jsonc 2>/dev/null \
        | grep -viE 'example\.(com|org)|@types|\.png|\.jpg' | sort -u)
SENDER_DOMAINS=""
if [ -z "$FROMS" ]; then
  ok "no email literals found in src/ or wrangler config"
fi
for addr in $FROMS; do
  dom="${addr#*@}"
  # Heuristic: an address is a SENDER if it appears in a from/NOTIFY_FROM/send
  # context; recipients are fine on any domain. Check context lines.
  ctx=$(grep -rE "(from|FROM|From)[^@]{0,40}$addr" src/ wrangler.toml wrangler.json wrangler.jsonc 2>/dev/null | head -1)
  [ -z "$ctx" ] && continue
  SENDER_DOMAINS="$SENDER_DOMAINS $dom"
  dots=$(echo "$dom" | awk -F. '{print NF-1}')
  if [ "$dots" -le 1 ]; then # apex (example.com) — check MX for hosted mailbox
    mx=$(dig +short MX "$dom" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if echo "$mx" | grep -qE 'google|googlemail|outlook|microsoft|protection\.'; then
      bad "sender $addr uses APEX domain '$dom' whose MX is a hosted mailbox ($(echo "$mx" | head -1 | awk '{print $2}')) — same-domain strict SPF/DMARC will spam-folder it. Use an Email-Sending-onboarded SUBDOMAIN sender."
    else
      warn "sender $addr uses apex domain '$dom' (no hosted-mailbox MX detected, but subdomain senders are still the safe pattern)"
    fi
  else
    ok "sender $addr uses subdomain '$dom'"
  fi
done

# ---- S2: onboarded in CF Email Sending --------------------------------------
# Ask the CF API per-zone, NOT `wrangler email sending list`: that table's
# columns are wrangler-version-dependent (an older pinned wrangler in the repo
# renders the zone id in the name column), which false-negatives a domain that
# IS onboarded. The zone's own subdomains endpoint is the authority.
# (2026-07-13: notifications.improvebayarea.com WARNed as "not onboarded" while
#  the API showed enabled=true, tag 0770c1cd — hence this rewrite.)
echo "2. Static: Cloudflare Email Sending onboarding"
CF_CRED="$HOME/.cloudflared/cf-global-api-key.json"
for dom in $(echo "$SENDER_DOMAINS" | tr ' ' '\n' | sort -u); do
  [ -z "$dom" ] && continue
  state=""
  if [ -f "$CF_CRED" ]; then
    state=$(SENDER_DOM="$dom" python3 - "$CF_CRED" <<'PY' 2>/dev/null
import json, os, sys, urllib.request
cred = json.load(open(sys.argv[1]))
H = {'X-Auth-Email': cred['email'], 'X-Auth-Key': cred['global_api_key']}
dom = os.environ['SENDER_DOM']
def get(p):
    return json.load(urllib.request.urlopen(
        urllib.request.Request('https://api.cloudflare.com/client/v4' + p, headers=H), timeout=20))
try:
    zones = get('/zones?per_page=100')['result']
    # longest matching zone suffix (notifications.a.com -> zone a.com)
    z = max((x for x in zones if dom == x['name'] or dom.endswith('.' + x['name'])),
            key=lambda x: len(x['name']), default=None)
    if not z:
        print('nozone'); sys.exit()
    if dom == z['name']:
        print('enabled' if get(f"/zones/{z['id']}/email/sending/settings")['result'].get('enabled') else 'disabled')
        sys.exit()
    subs = get(f"/zones/{z['id']}/email/sending/subdomains?per_page=100")['result'] or []
    hit = next((s for s in subs if s.get('name') == dom), None)
    print('enabled' if hit and hit.get('enabled') else ('disabled' if hit else 'missing'))
except Exception:
    print('unknown')
PY
)
  fi
  case "$state" in
    enabled)  ok "$dom onboarded in Email Sending (CF API)" ;;
    disabled) bad "$dom exists but Email Sending is DISABLED — send() will fail E_SENDER_NOT_VERIFIED" ;;
    missing|nozone) bad "$dom is NOT onboarded to Email Sending — run: npx wrangler email sending enable $dom" ;;
    *) warn "could not verify $dom onboarding against the CF API (creds/network) — UNVERIFIED, do not assume" ;;
  esac
done

# ---- L1: live mailbox placement + DMARC alignment ---------------------------
if [ "$STATIC_ONLY" -eq 0 ] && [ -n "$ACCOUNTS" ] && [ -n "$DOMAIN" ]; then
  echo "3. Live: mailbox placement + Authentication-Results (domain=$DOMAIN)"
  IFS=',' read -ra ACCTS <<< "$ACCOUNTS"
  for acct in "${ACCTS[@]}"; do
    row=$(gog -a "$acct" gmail search "in:anywhere from:$DOMAIN newer_than:1d" --json --max 1 2>/dev/null \
          | python3 -c "import sys,json;ts=(json.load(sys.stdin).get('threads') or []);print(ts[0]['id'] if ts else '')" 2>/dev/null)
    if [ -z "$row" ]; then
      warn "$acct: no message from $DOMAIN in last 1d — UNVERIFIED (trigger a real send and re-run)"
      continue
    fi
    meta=$(gog -a "$acct" gmail get "$row" --json 2>/dev/null)
    labels=$(echo "$meta" | python3 -c "import sys,json;d=json.load(sys.stdin);m=d.get('message') or d;print(','.join(m.get('labelIds') or []))" 2>/dev/null)
    authres=$(echo "$meta" | python3 -c "
import sys,json
d=json.load(sys.stdin); m=d.get('message') or d
hs=(m.get('payload') or {}).get('headers') or []
print(next((h['value'] for h in hs if h.get('name','').lower()=='authentication-results'),''))" 2>/dev/null)
    if echo "$labels" | grep -q "SPAM"; then
      bad "$acct: newest message from $DOMAIN ($row) is labeled SPAM — deliverability regression"
    else
      ok "$acct: message $row not in spam (labels: ${labels:-none})"
    fi
    if [ -n "$authres" ]; then
      if echo "$authres" | grep -qi "dmarc=pass"; then ok "$acct: dmarc=pass"
      else bad "$acct: Authentication-Results without dmarc=pass → ${authres:0:120}"; fi
    else
      warn "$acct: no Authentication-Results header readable — alignment unverified"
    fi
  done
fi

echo
if [ "$FAIL" -eq 1 ]; then echo "RESULT: BLOCK — fix sender alignment before/after deploy."; exit 2; fi
if [ "$WARN" -eq 1 ]; then echo "RESULT: UNVERIFIED — warnings above; trigger a real send and re-run the live check."; exit 1; fi
echo "RESULT: clean — senders aligned and delivered to inbox."; exit 0
