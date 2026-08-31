#!/usr/bin/env bash
# ai-crawl-reachability.sh — MANDATORY gate for any AI-visibility SEO audit.
#
# Catches the two-layer failure that made example.com invisible to ChatGPT (2026-06-25):
#   LAYER 1 (edge): a WAF/CDN returns 403/429 to AI bots before the app runs.
#                   robots.txt "Allow: /" does NOT override this — it's a lower layer.
#   LAYER 2 (app):  the bot gets 200 but the route-blind SPA shell (homepage <title> +
#                   homepage canonical on every route) because the bot's UA is NOT in the
#                   app's prerender/SSR crawler allowlist. OAI-SearchBot (ChatGPT Search's
#                   INDEX crawler) is the one most often forgotten.
#
# A 200 is NECESSARY but NOT SUFFICIENT. This script also runs a PARITY check: it compares
# what an AI index crawler receives against what Googlebot receives on a deep route. If the
# AI crawler gets a different (shell) <title>/canonical than Googlebot's prerender, the app
# allowlist is missing that bot.
#
# Usage:  ai-crawl-reachability.sh <domain-or-url> [deep-route-path]
#   e.g.  ai-crawl-reachability.sh example.com /services/disability-claims
# Exit:   0 = pass, 1 = CRITICAL (edge block or shell-parity miss), 2 = usage error.

set -uo pipefail
TARGET="${1:-}"; ROUTE="${2:-}"
[ -z "$TARGET" ] && { echo "usage: $0 <domain-or-url> [deep-route-path]"; exit 2; }
case "$TARGET" in http*://*) BASE="${TARGET%/}";; *) BASE="https://${TARGET%/}";; esac

AI_BOTS=("OAI-SearchBot/1.0" "ChatGPT-User/1.0" "GPTBot/1.0" "ClaudeBot/1.0" "PerplexityBot/1.0")
BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
GOOGLE="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
fail=0; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

probe(){ # ua url -> "http bytes title|canonical"
  local ua="$1" url="$2" f="$tmp/p.$RANDOM.html"
  local code; code=$(curl -sL --max-time 20 -o "$f" -w "%{http_code}" -A "$ua" "$url?cb=$RANDOM")
  local bytes title canon
  bytes=$(wc -c <"$f" | tr -d ' ')
  title=$(grep -oiE '<title>[^<]*</title>' "$f" | head -1 | sed -E 's/<[^>]*>//g')
  canon=$(grep -oiE '<link[^>]*rel="canonical"[^>]*>' "$f" | head -1 | grep -oiE 'href="[^"]*"' | head -1)
  echo "$code|$bytes|$title|$canon"
}

echo "=== LAYER 1: AI bot reachability — $BASE/ ==="
br=$(probe "$BROWSER" "$BASE/"); br_code="${br%%|*}"
printf "%-42s http=%s\n" "browser (baseline)" "$br_code"
for ua in "${AI_BOTS[@]}"; do
  r=$(probe "$ua" "$BASE/"); code="${r%%|*}"; rest="${r#*|}"; bytes="${rest%%|*}"
  flag="ok"; [ "$code" != "200" ] && { flag="❌ EDGE-BLOCK (CRITICAL)"; fail=1; }
  printf "%-42s http=%s bytes=%-7s %s\n" "$ua" "$code" "$bytes" "$flag"
done

if [ -n "$ROUTE" ]; then
  echo; echo "=== LAYER 2: prerender parity on $ROUTE (AI crawler vs Googlebot) ==="
  g=$(probe "$GOOGLE" "$BASE$ROUTE");  g_title="$(echo "$g" | cut -d'|' -f3)"; g_canon="$(echo "$g" | cut -d'|' -f4)"
  o=$(probe "OAI-SearchBot/1.0" "$BASE$ROUTE"); o_code="$(echo "$o" | cut -d'|' -f1)"
  o_title="$(echo "$o" | cut -d'|' -f3)"; o_canon="$(echo "$o" | cut -d'|' -f4)"
  echo "Googlebot   title: $g_title"
  echo "            canon: $g_canon"
  echo "OAI-Search  title: $o_title"
  echo "            canon: $o_canon"
  if [ "$o_code" = "200" ] && { [ "$o_title" != "$g_title" ] || [ "$o_canon" != "$g_canon" ]; }; then
    echo "❌ PARITY MISS (CRITICAL): OAI-SearchBot gets a different title/canonical than Googlebot's"
    echo "   prerender — it's likely served the route-blind SPA shell. Add its UA to the app's"
    echo "   crawler/prerender allowlist (e.g. crawler-detect CRAWLER_PATTERNS)."
    fail=1
  else
    echo "✅ parity ok (OAI-SearchBot gets the same per-route HTML as Googlebot)"
  fi
fi

echo
if [ "$fail" = 0 ]; then echo "✅ PASS — AI crawlers can fetch AND get per-route prerendered HTML."
else echo "❌ FAIL — fix the CRITICAL item(s) above before any other SEO work. Cloudflare: check"
     echo "   zones/<id>/bot_management → ai_bots_protection (must be 'disabled' to allow AI bots)."; fi
exit $fail
