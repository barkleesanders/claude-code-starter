#!/usr/bin/env bash
# Worker surface-exposure probe for /ship (added 2026-07-06).
# Asks the CF API what wrangler WON'T tell you: whether this worker's
# workers.dev subdomain and .cloudflare.app preview hostname are live.
#
# Why: CF Security Insights flags `<name>.cloudflare.app` preview hostnames
# (half-provisioned, 522, zone security can't apply) for missing
# TLS/HSTS/Always-HTTPS/security.txt — 7 workers were flagged within hours of
# the 2026-07-06 deploys. Worse, a custom-domain worker with workers.dev
# enabled serves a FULL UNPROTECTED DUPLICATE of prod (AIVA's twin did).
# `wrangler deploy` does NOT disengage an already-enabled subdomain even when
# the config says workers_dev:false (observed on wrangler 4.104) — only the
# API POST does. This probe closes that gap at ship time, before the alert
# email ever fires.
#
# Usage: worker-surface-check.sh <repo-dir> [--apply]
#   --apply  POST the fix (previews off; workers.dev off for custom-domain workers)
# Exit: 0 clean/fixed/skip, 1 findings present (and --apply not given or failed).
set -uo pipefail
DIR="${1:-$PWD}"; APPLY="${2:-}"
cd "$DIR" 2>/dev/null || { echo "usage: $0 <repo-dir> [--apply]"; exit 1; }

# NOTE (2026-07-27): this reads the SOURCE config. Repos using @cloudflare/vite-plugin
# actually DEPLOY from dist/<uuid>/wrangler.json via the .wrangler/deploy/config.json
# redirect ("Using redirected Wrangler configuration" on every deploy). Verified for AIVA:
# the two agree on name/preview_urls/workers_dev/cache, so this check is NOT currently
# mis-reading anything -- only `main` differs. It becomes wrong if the plugin ever drops or
# rewrites a field this script inspects. To read the deployed config instead:
#   RD=.wrangler/deploy/config.json
#   [ -f "$RD" ] && CFG=$(cd "$(dirname "$RD")" && realpath "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["configPath"])' config.json)")
# See ~/.claude/skills/shared/cf-integration-harness.md
CFG=$(ls wrangler.jsonc wrangler.json wrangler.toml 2>/dev/null | head -1)
[ -z "$CFG" ] && { echo "worker-surface-check: no wrangler config — skip"; exit 0; }

read -r NAME HASROUTES < <(node -e '
  const fs=require("fs");let t=fs.readFileSync(process.argv[1],"utf8");
  let name="",hasRoutes="n";
  if(process.argv[1].endsWith(".toml")){
    const m=t.match(/^\s*name\s*=\s*"([^"]+)"/m); name=m?m[1]:"";
    if(/^\s*(routes?\s*=|\[\[?routes\]?\]|\[env\.[^\]]*\.routes\])/m.test(t)||/custom_domain\s*=\s*true/.test(t))hasRoutes="y";
  } else {
    // strict JSON first; string-aware comment strip as jsonc fallback
    const parse=(s)=>JSON.parse(s);
    let o=null; try{o=parse(t);}catch(e){
      let out="",inStr=false,inLC=false,inBC=false;
      for(let i=0;i<t.length;i++){const c=t[i],n=t[i+1];
        if(inLC){if(c==="\n"){inLC=false;out+=c;}continue;}
        if(inBC){if(c==="*"&&n==="/"){inBC=false;i++;}continue;}
        if(inStr){out+=c;if(c==="\\"){out+=n??"";i++;}else if(c==="\""){inStr=false;}continue;}
        if(c==="\""){inStr=true;out+=c;continue;}
        if(c==="/"&&n==="/"){inLC=true;continue;}
        if(c==="/"&&n==="*"){inBC=true;i++;continue;}
        out+=c;}
      out=out.replace(/,\s*([}\]])/g,"$1");
      try{o=parse(out);}catch(e2){}
    }
    if(o){name=o.name||"";if((o.routes&&o.routes.length)||o.route)hasRoutes="y";}
  }
  console.log(name+" "+hasRoutes);' "$CFG" 2>/dev/null)

[ -z "$NAME" ] && { echo "worker-surface-check: could not parse worker name from $CFG — skip"; exit 0; }

CREDS="$HOME/.cloudflared/cf-global-api-key.json"
[ ! -f "$CREDS" ] && { echo "worker-surface-check: no CF creds ($CREDS) — cannot probe; run manually from a machine with creds"; exit 0; }
KEY=$(node -e "console.log(require(process.env.HOME+'/.cloudflared/cf-global-api-key.json').global_api_key)")
ACCT=$(node -e "console.log(require(process.env.HOME+'/.cloudflared/cf-global-api-key.json').account_id)")
EMAIL=$(node -e "console.log(require(process.env.HOME+'/.cloudflared/cf-global-api-key.json').email)")

resp=$(curl -s --max-time 20 "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts/$NAME/subdomain" \
  -H "X-Auth-Email: $EMAIL" -H "X-Auth-Key: $KEY")
ok=$(echo "$resp" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const j=JSON.parse(d);console.log(j.success?(j.result.enabled+" "+j.result.previews_enabled):"err")}catch(e){console.log("err")}})')
[ "$ok" = "err" ] && { echo "worker-surface-check: API probe failed for '$NAME' (worker may not exist yet) — skip"; exit 0; }
ENABLED=$(echo "$ok" | cut -d' ' -f1); PREVIEWS=$(echo "$ok" | cut -d' ' -f2)

echo "worker-surface-check: $NAME — live: workers.dev=$ENABLED previews=$PREVIEWS | config routes=$HASROUTES"
RC=0; WANT_ENABLED="$ENABLED"; WANT_PREVIEWS="$PREVIEWS"

if [ "$PREVIEWS" = "true" ]; then
  echo "  ⚠️  FINDING: previews_enabled=true → <$NAME>.cloudflare.app preview hostname exists (522s,"
  echo "     un-securable) and WILL trip CF Security Insights (TLS/HSTS/Always-HTTPS/security.txt)."
  WANT_PREVIEWS=false; RC=1
fi
if [ "$HASROUTES" = "y" ] && [ "$ENABLED" = "true" ]; then
  echo "  ⚠️  FINDING: custom-domain worker with workers.dev ENABLED → <$NAME>.<acct>.workers.dev serves"
  echo "     an unprotected duplicate of prod (bypasses zone security, splits SEO). Disable it."
  WANT_ENABLED=false; RC=1
fi

if [ "$RC" = 1 ] && [ "$APPLY" = "--apply" ]; then
  fix=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts/$NAME/subdomain" \
    -H "X-Auth-Email: $EMAIL" -H "X-Auth-Key: $KEY" -H "Content-Type: application/json" \
    --data "{\"enabled\":$WANT_ENABLED,\"previews_enabled\":$WANT_PREVIEWS}")
  echo "$fix" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);console.log(j.success?"  ✅ APPLIED: enabled="+j.result.enabled+" previews="+j.result.previews_enabled:"  ❌ apply failed: "+JSON.stringify(j.errors).slice(0,120))})'
  echo "$fix" | grep -q '"success": *true' && RC=0
  echo "  ↳ also set workers_dev/preview_urls in $CFG for declarative parity (wrangler alone won't disengage)."
fi

[ "$RC" = 0 ] && echo "worker-surface-check: OK" || echo "worker-surface-check: FINDINGS (re-run with --apply to fix via API)"
exit $RC
