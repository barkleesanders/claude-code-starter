#!/usr/bin/env bash
# sourcemap-exposure-check.sh — client source maps must never reach the public.
#
# Usage: sourcemap-exposure-check.sh [repo-root] [--live <origin>] [--dist <dir>]
#   repo-root  defaults to $PWD
#   --live     also probe the deployed site: fetch a page, find its first
#              /assets/*.js, assert the bundle has no sourceMappingURL and that
#              <bundle>.map answers 404 (not 200, not 403).
#   --live-path <p>  extra page(s) to harvest bundles from (default: / /dashboard /app)
#   --dist     built client dir to scan (default: auto — dist/client, dist, build, .output/public)
#
# Three outcomes per check, never two: OK / FAIL / UNMEASURED (the site is not
# built, no bundle found, curl blocked). UNMEASURED is never a pass — the caller
# decides; this script exits 2 for it so a gate cannot mistake it for clean.
#
# Why (measured 2026-09-20, AIVA-Frontend security audit item #11): vite.config.ts
# `sourcemap: true` => every /assets/*.js carried `//# sourceMappingURL=` and
# Cloudflare served the .map (1.55 MB, full sourcesContent of the SPA) to anyone.
# Fix shape: vite `sourcemap: "hidden"` (maps still emitted for wrangler's
# upload_source_maps) + `*.map` in public/.assetsignore (@cloudflare/vite-plugin
# merges it into dist/client/.assetsignore; wrangler applies gitignore rules —
# `WRANGLER_LOG=debug wrangler deploy --dry-run` shows "Ignoring asset:" per map).
#
# Exit: 0 all measured checks OK · 1 any FAIL · 2 no FAIL but something UNMEASURED
set -u
ROOT="$PWD"; LIVE=""; DIST=""; LIVE_PATHS="/dashboard /app"
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE="$2"; shift 2;;
    --dist) DIST="$2"; shift 2;;
    --live-path) LIVE_PATHS="$LIVE_PATHS $2"; shift 2;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    *) ROOT="$1"; shift;;
  esac
done
cd "$ROOT" 2>/dev/null || { echo "UNMEASURED  cannot cd to $ROOT"; exit 2; }
FAIL=0; UNM=0
ok()   { echo "OK          $*"; }
fail() { echo "FAIL        $*"; FAIL=1; }
unm()  { echo "UNMEASURED  $*"; UNM=1; }

# --- 1. Source config: does the bundler emit browser-visible maps?
CFG_HITS=""; CFG_FOUND=0
for f in vite.config.ts vite.config.mts vite.config.js vite.config.mjs next.config.js next.config.mjs next.config.ts esbuild.config.* webpack.config.* astro.config.* nuxt.config.*; do
  [ -f "$f" ] || continue
  CFG_FOUND=1
  # `sourcemap: true` / `sourcemap: 'inline'` / productionBrowserSourceMaps: true are the leak shapes.
  if grep -nE "(sourcemap|sourceMap)\s*:\s*(true|['\"]inline['\"])|productionBrowserSourceMaps\s*:\s*true" "$f" | grep -vE '^\s*[0-9]+:\s*//' >/dev/null; then
    CFG_HITS="$CFG_HITS $f"
    fail "$f emits browser-visible client source maps: $(grep -nE "(sourcemap|sourceMap)\s*:\s*(true|['\"]inline['\"])|productionBrowserSourceMaps\s*:\s*true" "$f" | head -1)"
  else
    ok "$f: no browser-visible sourcemap setting (hidden/false/unset)"
  fi
done
[ "$CFG_FOUND" = 0 ] && unm "no bundler config found in $ROOT"

# --- 2. Cloudflare static assets: are *.map excluded from the asset manifest?
#     (`ls a b c` exits non-zero if ANY is missing — loop instead; this exact bug
#     made deployed-unmerged-check print "unknown" for auto-deploy on 2026-09-20.)
CF=0; for w in wrangler.json wrangler.jsonc wrangler.toml; do [ -f "$w" ] && CF=1; done
if [ "$CF" = 1 ]; then
  if [ -f public/.assetsignore ] && grep -qE '^\s*\*\.map\s*$' public/.assetsignore; then
    ok "public/.assetsignore excludes *.map"
  elif [ -f .assetsignore ] && grep -qE '^\s*\*\.map\s*$' .assetsignore; then
    ok ".assetsignore excludes *.map"
  else
    # only a FAIL if maps are actually emitted into the served dir (checked in 3)
    echo "NOTE        no *.map line in public/.assetsignore (fine only if no .map lands in the served asset dir)"
  fi
fi

# --- 3. Built artifact: any served bundle pointing at a map? any .map in the served dir?
if [ -z "$DIST" ]; then
  for d in dist/client dist build .output/public out; do
    [ -d "$d" ] && { DIST="$d"; break; }
  done
fi
if [ -n "$DIST" ] && [ -d "$DIST" ]; then
  BUNDLES=$(find "$DIST" -type f \( -name '*.js' -o -name '*.css' \) 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BUNDLES" = "0" ]; then
    unm "$DIST has no js/css bundles (not built?)"
  else
    LEAK=$(grep -rlE 'sourceMappingURL=' --include='*.js' --include='*.css' "$DIST" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$LEAK" = "0" ]; then ok "$DIST: 0 of $BUNDLES bundles carry sourceMappingURL="; else fail "$DIST: $LEAK of $BUNDLES bundles carry sourceMappingURL= (first: $(grep -rlE 'sourceMappingURL=' --include='*.js' --include='*.css' "$DIST" | head -1))"; fi
    MAPS=$(find "$DIST" -type f -name '*.map' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$MAPS" != "0" ]; then
      if [ -f "$DIST/.assetsignore" ] && grep -qE '^\s*\*\.map\s*$' "$DIST/.assetsignore"; then
        ok "$DIST: $MAPS .map files present but $DIST/.assetsignore excludes *.map"
      elif [ "$CF" = 1 ]; then
        fail "$DIST: $MAPS .map files would be uploaded as static assets (no *.map in $DIST/.assetsignore)"
      else
        echo "NOTE        $DIST: $MAPS .map files emitted; confirm your host does not serve them"
      fi
    fi
  fi
else
  unm "no built client dir found (dist/client, dist, build, .output/public, out) — run the build first"
fi

# --- 4. Live origin (post-deploy): every script bundle the served pages reference + its .map
#     Probes "/" and each --live-path (default: /dashboard, /app — SPA entry points that
#     reference /assets/index-*.js; an SSR home page may only reference island scripts).
probe_page() {
  local page="$1" html js seen=""
  html=$(curl -sL --max-time 20 -A 'sourcemap-exposure-check' "$LIVE$page" 2>/dev/null)
  for js in $(printf '%s' "$html" | grep -oE '(src|href)="[^"]+\.js"' | sed -E 's/^(src|href)="//; s/"$//' | sed -E "s#^$LIVE##" | grep -E '^/' | sort -u | head -6); do
    case " $PROBED " in *" $js "*) continue;; esac
    PROBED="$PROBED $js"
    local tmp code mcode
    tmp=$(mktemp); code=$(curl -sL --max-time 20 -A 'sourcemap-exposure-check' -o "$tmp" -w '%{http_code}' "$LIVE$js" 2>/dev/null)
    if [ "$code" != "200" ]; then unm "$LIVE$js -> HTTP $code (cannot read bundle)"; else
      if grep -q 'sourceMappingURL=' "$tmp"; then fail "$LIVE$js carries sourceMappingURL="; else ok "$LIVE$js: no sourceMappingURL="; fi
    fi
    rm -f "$tmp"
    mcode=$(curl -sL --max-time 20 -A 'sourcemap-exposure-check' -o /dev/null -w '%{http_code}' "$LIVE$js.map" 2>/dev/null)
    case "$mcode" in
      404|410) ok "$LIVE$js.map -> $mcode";;
      200) fail "$LIVE$js.map -> 200 (client source map is publicly served)";;
      000) unm "$LIVE$js.map -> no response (network/WAF)";;
      *) unm "$LIVE$js.map -> $mcode (blocked-or-unmeasured, not a 404)";;
    esac
  done
}
if [ -n "$LIVE" ]; then
  LIVE="${LIVE%/}"; PROBED=""
  for page in / $LIVE_PATHS; do probe_page "$page"; done
  [ -z "$PROBED" ] && unm "$LIVE: no script bundle reference found on / $LIVE_PATHS (WAF? SSR without scripts?)"
fi

if [ "$FAIL" = 1 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$UNM" = 1 ]; then echo "RESULT: UNMEASURED (no failures, but not every check could run)"; exit 2; fi
echo "RESULT: OK"; exit 0
