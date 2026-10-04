#!/usr/bin/env bash
# Workers Cache safety gate for /ship (added 2026-07-06).
# Verifies that a Cloudflare Worker with `cache.enabled=true` is enabled CORRECTLY and SAFELY.
#
# The dangerous class this catches (the AIVA near-miss, 2026-07-06):
#   Workers Cache heuristically caches ANY 200 response with no Cache-Control for 2h
#   (per https://developers.cloudflare.com/workers/cache/configuration/ — "Responses with
#   no Cache-Control header are still cached"). Set-Cookie responses auto-bypass, BUT a
#   cookie/session-authed GET that returns 200 with NO Set-Cookie and NO Cache-Control on
#   THAT response gets cached and served cross-user. => data leak.
#
# Usage: workers-cache-check.sh <repo-dir>   (defaults to CWD)
# Exit: 0 = pass/no-cache-config, 2 = BLOCK (unsafe), 1 = usage error. WARN does not block.
set -uo pipefail
DIR="${1:-$PWD}"; cd "$DIR" 2>/dev/null || { echo "usage: $0 <repo-dir>"; exit 1; }

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
[ -z "$CFG" ] && { echo "workers-cache-check: no wrangler config in $DIR — skip"; exit 0; }

# Is cache.enabled true? (jsonc/json: "cache": { "enabled": true }; toml: [cache]\nenabled = true)
enabled=$(node -e '
  const fs=require("fs");let t=fs.readFileSync(process.argv[1],"utf8");
  if(process.argv[1].endsWith(".toml")){
    const m=t.match(/\[cache\][\s\S]*?enabled\s*=\s*(true|false)/);console.log(m?m[1]:"none");
  } else {
    // Try strict JSON first — a line-comment regex corrupts strings containing
    // "//" (e.g. "https://..." route patterns). Only comment-strip as a
    // jsonc fallback, and only outside string literals.
    const read=(s)=>{const o=JSON.parse(s);return o.cache&&typeof o.cache.enabled==="boolean"?String(o.cache.enabled):"none";};
    try{console.log(read(t));}catch(e1){
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
      try{console.log(read(out));}catch(e2){console.log("parseerror");}
    }
  }' "$CFG" 2>/dev/null)

if [ "$enabled" = "none" ]; then echo "workers-cache-check: no cache.enabled in $CFG — skip"; exit 0; fi
if [ "$enabled" = "parseerror" ]; then echo "❌ workers-cache-check: $CFG failed to parse — fix config"; exit 2; fi
if [ "$enabled" = "false" ]; then echo "workers-cache-check: cache.enabled=false in $CFG — nothing to verify"; exit 0; fi

echo "workers-cache-check: cache.enabled=true in $CFG — running safety gate"
RC=0

# --- 1. wrangler >= 4.69 (else the flag is silently IGNORED at deploy time) ---
wv=$(node -e 'try{console.log(require("./node_modules/wrangler/package.json").version)}catch(e){
  const p=(()=>{try{return require("./package.json")}catch(_){return{}}})();
  console.log((p.devDependencies&&p.devDependencies.wrangler)||(p.dependencies&&p.dependencies.wrangler)||"global")}' 2>/dev/null)
maj=$(echo "$wv" | grep -oE '[0-9]+' | head -1); min=$(echo "$wv" | grep -oE '[0-9]+' | sed -n 2p)
if [ -n "$maj" ] && { [ "$maj" -lt 4 ] || { [ "$maj" -eq 4 ] && [ -n "$min" ] && [ "$min" -lt 69 ]; }; }; then
  echo "  ⚠️  WARN: wrangler '$wv' < 4.69 — cache.enabled is IGNORED until you upgrade (feature inert)."
fi

# --- 2. only enabled / cross_version_cache keys allowed (others => wrangler validation error) ---
badkeys=$(node -e '
  let t=require("fs").readFileSync(process.argv[1],"utf8");
  if(process.argv[1].endsWith(".toml"))process.exit(0);
  const scan=(s)=>{const c=JSON.parse(s).cache||{};for(const k of Object.keys(c))if(!["enabled","cross_version_cache"].includes(k))console.log(k);};
  // Strict JSON first (a line-comment regex corrupts "https://" strings);
  // string-aware comment strip only as jsonc fallback.
  try{scan(t);}catch(e1){
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
    try{scan(out);}catch(e2){}
  }' "$CFG" 2>/dev/null)
[ -n "$badkeys" ] && { echo "  ❌ BLOCK: unsupported cache key(s): $badkeys (only enabled/cross_version_cache allowed)"; RC=2; }

# --- 3. THE LEAK CLASS: COOKIE-read auth surface + no global no-store default ---
# The leak vector is specifically COOKIE/session auth: cookie-authed requests do
# NOT trigger CF's Authorization-header auto-bypass, so an unmarked 200 gets
# heuristically cached 2h and served cross-user. Pure Bearer-header auth
# (request.headers.get("Authorization")) IS auto-bypassed — not a leak signal.
# Signals are code-shaped (cookie READS + cookie-session libs), NOT prose words:
# bare "clerk"/"userId" false-positived on "court clerk" prose (2026-07-06 sweep).
SRC="src"; [ -d "$SRC" ] || SRC="."
authsurface=$(grep -rliE "authenticateRequest|clerkMiddleware|iron-session|lucia|getCookie\(|\.req\.cookie|header\([\"']cookie|headers\.get\([\"']cookie|__session|session[_-]?(token|id)[\"']?\s*[:=)]|createCookie|parseCookies" "$SRC" \
  --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null | grep -viE 'node_modules|/dist/|\.test\.|\.spec\.' | head -1)

# Bearer-only auth note (informational — auto-bypassed by CF)
if [ -z "$authsurface" ] && grep -rqiE "headers\.get\([\"']authorization" "$SRC" --include='*.ts' --include='*.js' 2>/dev/null; then
  echo "  ℹ️  Bearer-header auth detected — CF auto-bypasses Authorization-header requests; not a cookie-leak surface."
fi

if [ -n "$authsurface" ]; then
  # look for a fail-safe: a DEFAULT no-store applied broadly (middleware / app.use /
  # response-helper default). Keywords may sit in a comment up to 4 lines ABOVE the
  # no-store line (grep -B4), not only on the same line.
  failsafe=$(grep -rn -B4 -iE "no-store" "$SRC" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null \
    | grep -viE 'node_modules|/dist/|\.test\.|\.spec\.' \
    | grep -iE "app\.use|use\(|middleware|default|every response|by default|unless.*public|fallthrough|finally" | head -1)
  if [ -z "$failsafe" ]; then
    echo "  ❌ BLOCK: auth/cookie surface present ($authsurface) but NO global 'no-store' default found."
    echo "     Workers Cache heuristically caches any 200 w/ no Cache-Control for 2h → cookie-authed"
    echo "     responses can be served CROSS-USER. Add a middleware that sets 'Cache-Control: private,"
    echo "     no-store' by DEFAULT and have public routes explicitly opt in to 'public, max-age=…',"
    echo "     OR use the per-entrypoint gateway pattern (exports map: default cache.enabled=false)."
    echo "     Reference: improvebayarea src/cache_headers.ts (default-no-store middleware)."
    RC=2
  else
    echo "  ✅ auth surface + global no-store default found ($failsafe) — safe."
  fi
else
  echo "  ✅ no cookie/session auth surface detected — public content; heuristic caching is acceptable."
fi

# --- 3b. REDIRECT-LOOP CLASS: request-scheme sniffing (2026-07-06 AIVA outage) ---
# With cache.enabled, the cache front-layer presents http:// in request.url for
# HTTPS visitors (cf-visitor stays https). Any middleware that sniffs the
# REQUEST url's protocol to force https will 301 every request to itself —
# sitewide infinite redirect loop (example down 21:44Z-22:10Z). Detection:
# a file that builds a URL from the request AND checks protocol === "http".
# Input-URL validators (new URL(userString) + protocol check) are fine.
loopfiles=$(grep -rlE "new URL\((c\.req\.url|request\.url)\)" "$SRC" --include='*.ts' --include='*.tsx' --include='*.js' 2>/dev/null | grep -viE 'node_modules|/dist/|\.test\.')
for lf in $loopfiles; do
  if grep -qE 'protocol === "http:"|protocol==="http:"' "$lf" && ! grep -q "cf-visitor" "$lf"; then
    echo "  ❌ BLOCK: $lf sniffs the REQUEST scheme via url.protocol without consulting cf-visitor."
    echo "     Under Workers Cache the runtime presents http:// for HTTPS visitors → this middleware"
    echo "     will 301 every request to its own URL (sitewide redirect loop — 2026-07-06 AIVA outage)."
    echo "     Fix: derive the client scheme from the cf-visitor header ({\"scheme\":\"https\"}) and use"
    echo "     url.protocol only as a local-dev fallback. Reference: AIVA visitorIsHttps() in"
    echo "     src/worker/middleware/securityHeaders.ts."
    RC=2
  fi
done

# --- 3c. HSTS-DROP CLASS: HSTS (or any behavior) gated on the REQUEST url's https protocol ---
# Same http:// presentation as 3b: `if (url.protocol === "https:")` around HSTS never fires
# under the cache layer → HSTS silently dropped sitewide (found live on AIVA 2026-07-06).
# WARN not BLOCK — degrades security posture, doesn't take the site down.
for lf in $loopfiles; do
  if grep -qE 'protocol === "https:"|protocol==="https:"' "$lf" && ! grep -q "cf-visitor" "$lf"; then
    echo "  ⚠️  WARN: $lf gates behavior on url.protocol === \"https:\" without consulting cf-visitor."
    echo "     Under Workers Cache the runtime presents http:// for HTTPS visitors → this branch"
    echo "     (typically HSTS) silently never fires. Fix: derive the scheme from cf-visitor"
    echo "     (visitorIsHttps() — AIVA src/worker/middleware/securityHeaders.ts)."
  fi
done

# --- 4. re-verify against LIVE docs (the config surface can change) ---
echo "  ↳ RE-VERIFY at ship time (do NOT trust this script's assumptions): WebFetch"
echo "     https://developers.cloudflare.com/workers/cache/configuration/ and confirm: (a) min wrangler,"
echo "     (b) the 'no Cache-Control ⇒ heuristically cached' rule still holds, (c) allowed cache keys."

[ "$RC" = 0 ] && echo "workers-cache-check: PASS" || echo "workers-cache-check: BLOCK (rc=$RC)"
exit $RC
