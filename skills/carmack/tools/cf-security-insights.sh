#!/usr/bin/env bash
# cf-security-insights.sh — triage + safe auto-fix for Cloudflare Security Center "Insights".
#
# Applies the REAL, zero-perf-cost fixes account-wide:
#   1. security.txt       (security-center/securitytxt, served at edge)
#   2. Worker preview hostnames OFF (subdomain.previews_enabled=false, EVERY worker) —
#      (2)+ detail below.
#
# NO LONGER auto-applied (user directive 2026-07-07): Block-AI-bots
# (ai_bots_protection) and AI Labyrinth (crawler_protection). AI bots must reach the
# sites for AI/LLM SEO in the user's "new AI work"; both settings hurt that. They are
# now REPORT-ONLY here and are NEVER written. For the zone/DNS security layer (DNSSEC,
# Free WAF Managed Ruleset, Leaked-Credential detection, CAA) run the companion
# ~/.claude/skills/carmack/tools/cf-account-harden.py (DRY_RUN=1 to preview).
#
#   (2) Worker preview hostnames OFF (subdomain.previews_enabled=false, EVERY worker) —
#      `<name>.cloudflare.app` previews are half-provisioned (522, no zone security)
#      and are what CF flags as "Domains missing TLS Encryption" / "without Always
#      Use HTTPS" / "without HSTS" / "Security.txt not configured". Per-repo /ship
#      Phase 4.09 closes only the deployed worker; THIS sweep closes all of them
#      (2026-07-07: 17 workers alerted, 13 more were one scan-wave away).
#      Custom-domain workers with workers.dev ON are REPORTED (not auto-fixed —
#      needs repo context; run worker-surface-check.sh <repo> --apply).
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
# 2026-08-15 user directive: public contact is the org address, never gmail.
CONTACT="mailto:security@example.org"
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
  # AI-bot blocking + AI Labyrinth (crawler_protection) are NO LONGER auto-applied.
  # User directive 2026-07-07: AI bots must be able to reach the sites for AI/LLM SEO
  # ("new AI work"); Block-AI-bots and AI Labyrinth both hurt that. Left as-is per zone;
  # ab/al columns are now REPORT-ONLY (never written).
  ab="report"; al="report"
  if [ $APPLY -eq 1 ]; then
    st=$(cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZID/security-center/securitytxt" \
         --data "{\"enabled\":true,\"contact\":[\"$CONTACT\"],\"preferred_languages\":\"en\",\"expires\":\"$EXPIRES\"}" \
         | python3 -c "import json,sys;print('OK' if json.load(sys.stdin).get('success') else 'ERR')" 2>/dev/null || echo ERR)
  else
    st="would-set"
  fi
  printf "%-34s %-10s %-12s %-9s\n" "$NAME" "$ab" "$al" "$st"
done <<< "$ZLIST"

# --- 4. Worker preview-hostname sweep (account-wide) -------------------------
# The `.cloudflare.app` preview class: every worker with previews_enabled=true
# grows a half-provisioned public hostname CF's scanner flags for missing
# TLS / Always-HTTPS / HSTS / security.txt. wrangler deploy can silently
# re-enable it, so this must re-run on every sweep.
echo
echo "— Worker preview hostnames (account-wide) —"
if [ -z "$ACCT" ]; then
  echo "  (no account_id in creds — skipped)"
else
  SCRIPTS=$(cf "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts?per_page=100" \
    | python3 -c "import json,sys;[print(s['id']) for s in json.load(sys.stdin).get('result') or []]")
  CUSTOM_DOMAIN_SVCS=$(cf "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/domains" \
    | python3 -c "import json,sys;print('\n'.join(sorted({d['service'] for d in json.load(sys.stdin).get('result') or []})))")
  NFIX=0; NWARN=0; NTOTAL=0
  while IFS= read -r W; do
    [ -z "$W" ] && continue
    NTOTAL=$((NTOTAL+1))
    SUB=$(cf "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts/$W/subdomain")
    EN=$(echo "$SUB" | python3 -c "import json,sys;d=json.load(sys.stdin);print(str(d.get('result',{}).get('enabled','?')).lower() if d.get('success') else '?')" 2>/dev/null || echo '?')
    PV=$(echo "$SUB" | python3 -c "import json,sys;d=json.load(sys.stdin);print(str(d.get('result',{}).get('previews_enabled','?')).lower() if d.get('success') else '?')" 2>/dev/null || echo '?')
    if [ "$PV" = "true" ]; then
      if [ $APPLY -eq 1 ]; then
        RES=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts/$W/subdomain" \
          --data "{\"enabled\":$EN,\"previews_enabled\":false}" \
          | python3 -c "import json,sys;print('fixed' if json.load(sys.stdin).get('success') else 'ERR')" 2>/dev/null || echo ERR)
        printf "  %-40s previews=true -> %s\n" "$W" "$RES"
      else
        printf "  %-40s previews=true (would-disable)\n" "$W"
      fi
      NFIX=$((NFIX+1))
    fi
    if [ "$EN" = "true" ] && echo "$CUSTOM_DOMAIN_SVCS" | grep -qx "$W"; then
      printf "  ⚠️  %-38s custom-domain worker with workers.dev ENABLED — unprotected prod duplicate.\n" "$W"
      printf "      NOT auto-fixed (needs repo context): run worker-surface-check.sh <repo> --apply\n"
      NWARN=$((NWARN+1))
    fi
  done <<< "$SCRIPTS"
  echo "  workers probed: $NTOTAL; previews $([ $APPLY -eq 1 ] && echo disabled || echo to-disable): $NFIX; workers.dev-on-custom-domain warnings: $NWARN"
fi

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
