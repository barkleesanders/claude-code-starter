#!/usr/bin/env bash
# cf-security-insights.sh — triage + safe auto-fix for Cloudflare Security Center "Insights".
#
# Applies the 3 REAL, zero-perf-cost fixes account-wide:
#   1. Block AI bots      (bot_management.ai_bots_protection = "block")
#   2. AI Labyrinth       (bot_management.crawler_protection = "enabled")
#   3. security.txt       (security-center/securitytxt, served at edge)
#
# DELIBERATELY SKIPS the false-positive / judgment-call classes CF flags:
#   - Bot Fight Mode            -> hurts Lighthouse/CWV (JS challenge). User-excluded.
#   - Unproxied CNAME           -> Clerk/SendGrid/Brevo/etc. MUST stay DNS-only; proxying breaks them.
#   - Dangling A/AAAA           -> often a live Google-forwarding/Firebase origin; never auto-delete DNS.
#   - DMARC Record Error        -> usually a valid record already exists (CF over-counts per MX).
#
# Auth: ~/.cloudflared/cf-global-api-key.json  ({email, global_api_key})
# Usage:
#   cf-security-insights.sh            # dry-run: list zones + what WOULD change
#   cf-security-insights.sh --apply    # apply the 3 safe fixes to every zone
#   cf-security-insights.sh --apply --contact mailto:you@example.com
#
# Ref: ~/.claude/skills/shared/site-security-defaults.md (triage map + Compared-to-What rule)
set -euo pipefail

APPLY=0
CONTACT="mailto:you@example.com"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --contact) CONTACT="$2"; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

CRED="$HOME/.cloudflared/cf-global-api-key.json"
[ -f "$CRED" ] || { echo "❌ missing $CRED" >&2; exit 1; }
EMAIL=$(python3 -c "import json,sys;print(json.load(open('$CRED'))['email'])")
KEY=$(python3 -c "import json,sys;print(json.load(open('$CRED'))['global_api_key'])")
# security.txt Expires = +1 year, computed (no hardcoded date)
EXPIRES=$(python3 -c "import datetime;print((datetime.date.today().replace(year=datetime.date.today().year+1)).isoformat()+'T00:00:00.000Z')")

ACCT=$(python3 -c "import json,sys;print(json.load(open('$CRED')).get('account_id',''))")
cf(){ curl -s -H "X-Auth-Email: $EMAIL" -H "X-Auth-Key: $KEY" -H "Content-Type: application/json" "$@"; }

echo "=== Cloudflare Security Insights — safe auto-fix ==="
echo "mode: $([ $APPLY -eq 1 ] && echo APPLY || echo DRY-RUN)   contact: $CONTACT   sec.txt expires: $EXPIRES"
echo

# Target zones = union of /zones list AND every zone_tag CF flagged in a SAFE insight class.
# The insight-driven half is essential: workers.dev/pages.dev zones accept the fixes but
# do NOT appear in the standard /zones listing, so a zones-only loop silently misses them.
ZONES_JSON=$(cf "https://api.cloudflare.com/client/v4/zones?per_page=200")
INSIGHTS_JSON=""
[ -n "$ACCT" ] && INSIGHTS_JSON=$(cf "https://api.cloudflare.com/client/v4/accounts/$ACCT/security-center/insights?per_page=300")
ZLIST=$(ZONES_JSON="$ZONES_JSON" INSIGHTS_JSON="$INSIGHTS_JSON" python3 -c "
import json,os
seen={}
for z in (json.loads(os.environ['ZONES_JSON']).get('result') or []): seen[z['id']]=z['name']
ij=os.environ.get('INSIGHTS_JSON') or ''
if ij:
    SAFE={'no_block_ai_bots','no_challenge_ai_bots','security_txt_not_enabled'}
    for i in (json.loads(ij).get('result') or {}).get('issues',[]):
        if i.get('issue_class') in SAFE and not i.get('dismissed'):
            z=(i.get('payload') or {}).get('zone_tag')
            if z: seen.setdefault(z, i.get('subject',z))
for zid,name in seen.items(): print(zid, name)")

printf "%-34s %-10s %-12s %-9s\n" "ZONE" "AI-bots" "AILabyrinth" "sec.txt"
while IFS=' ' read -r ZID NAME; do
  [ -z "$ZID" ] && continue
  if [ $APPLY -eq 1 ]; then
    bm=$(cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/bot_management" \
         --data '{"ai_bots_protection":"block","crawler_protection":"enabled"}')
    ab=$(echo "$bm" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['result']['ai_bots_protection'] if d.get('success') else 'ERR')" 2>/dev/null || echo ERR)
    al=$(echo "$bm" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['result']['crawler_protection'] if d.get('success') else 'ERR')" 2>/dev/null || echo ERR)
    st=$(cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/security-center/securitytxt" \
         --data "{\"enabled\":true,\"contact\":[\"$CONTACT\"],\"preferred_languages\":\"en\",\"expires\":\"$EXPIRES\"}" \
         | python3 -c "import json,sys;print('OK' if json.load(sys.stdin).get('success') else 'ERR')" 2>/dev/null || echo ERR)
  else
    cur=$(cf "https://api.cloudflare.com/client/v4/zones/$ZID/bot_management")
    ab=$(echo "$cur" | python3 -c "import json,sys;d=json.load(sys.stdin)['result'];print('block' if d.get('ai_bots_protection')=='block' else 'would-set')" 2>/dev/null || echo '?')
    al=$(echo "$cur" | python3 -c "import json,sys;d=json.load(sys.stdin)['result'];print('enabled' if d.get('crawler_protection')=='enabled' else 'would-set')" 2>/dev/null || echo '?')
    st="would-set"
  fi
  printf "%-34s %-10s %-12s %-9s\n" "$NAME" "$ab" "$al" "$st"
done <<< "$ZLIST"

cat <<'EOF'

— SKIPPED (false-positive / judgment-call classes; verify by hand, do NOT auto-apply CF's advice) —
  Bot Fight Mode        : hurts Lighthouse (JS challenge). Enable only on parked/infra domains if user opts in.
  Unproxied CNAME       : Clerk/SendGrid/Brevo/etc. require DNS-only — proxying BREAKS them. Leave grey-cloud.
  Dangling A/AAAA       : curl the host first — Google-forwarding/Firebase origins are live, not dangling.
  DMARC Record Error    : dig _dmarc.<domain> TXT — a valid record usually already exists (CF over-counts per MX).
EOF
if [ $APPLY -eq 1 ]; then
  echo; echo "✅ applied. Closed-loop verify: curl -sI https://<domain>/.well-known/security.txt → 200"
fi
exit 0
