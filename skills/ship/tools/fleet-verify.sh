#!/usr/bin/env bash
# fleet-verify.sh — post-deploy verification battery for a Cloudflare Worker site.
# Promoted from a session scratchpad (2026-07-06) so /ship Phase 4.1 can run the
# same multi-signal check on every deploy instead of re-deriving it each time.
#
# Per URL it reports: HTTP status · Cache-Control · cf-cache-status · HSTS ·
# CSP · rendered-DOM literals (undefined/NaN/[object Object]/Invalid Date) ·
# STATIC h1 count · og:image · security.txt status.
#
# Usage:
#   fleet-verify.sh <name> <url>            # one site
#   fleet-verify.sh --list <file>           # file of "name url" lines
# Exit: 0 always (report tool); grep the output for FAIL markers in the caller.
#
# CAVEATS baked in (each a real 2026-07-06 bug):
#  - Param join: appends ?x= or &x= correctly so a bare URL never becomes /&x=…
#    (tool-error-recovery #29). Cache-buster is opt-in via $FV_BUST=1.
#  - The h1 count is STATIC (curl+grep) and INCLUDES inert <template> content —
#    it can over-count vs the live a11y DOM (xbox-nxe: static 5, runtime 1).
#    Treat >1 as "confirm with a live-DOM querySelectorAll", NOT an automatic fail.
set -uo pipefail

probe() {
  local name="$1" url="$2"
  # safe cache-buster join (opt-in)
  local q="$url"
  if [ "${FV_BUST:-0}" = "1" ]; then
    case "$url" in *\?*) q="$url&_fv=$RANDOM";; *) q="$url?_fv=$RANDOM";; esac
  fi
  local body; body=$(mktemp)
  local H; H=$(curl -s -D - -o "$body" --max-time 25 "$q" 2>/dev/null)
  local code cc ccs hsts csp ct
  code=$(printf '%s' "$H" | grep -oE "HTTP/[0-9.]+ [0-9]{3}" | tail -1 | grep -oE "[0-9]{3}$")
  cc=$(printf '%s' "$H"  | grep -i "^cache-control:"       | head -1 | cut -d' ' -f2- | tr -d '\r')
  ccs=$(printf '%s' "$H" | grep -i "^cf-cache-status:"     | head -1 | cut -d' ' -f2  | tr -d '\r')
  hsts=$(printf '%s' "$H"| grep -ci "^strict-transport-security:")
  csp=$(printf '%s' "$H" | grep -ci "^content-security-policy:")
  ct=$(printf '%s' "$H"  | grep -i "^content-type:" | head -1 | cut -d' ' -f2- | tr -d '\r' | cut -d';' -f1)
  # grep -c prints 0 AND exits 1 on no-match — do NOT chain `|| echo 0` (double count).
  local lit=0 h1=0 og=0
  if [ "$ct" = "text/html" ]; then
    lit=$(grep -coE ">undefined<|>NaN<|\[object Object\]|>Invalid Date<" "$body" 2>/dev/null); lit=${lit:-0}
    h1=$(grep -c "<h1" "$body" 2>/dev/null); h1=${h1:-0}
    og=$(grep -c 'property="og:image"' "$body" 2>/dev/null); og=${og:-0}
  fi
  local base sectxt
  base=$(printf '%s' "$url" | grep -oE "https?://[^/]+")
  sectxt=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$base/.well-known/security.txt")
  rm -f "$body"
  # FAIL markers the caller can grep: non-200, or rendered DOM literals present
  local flag=""
  [ "$code" != "200" ] && flag="$flag FAIL:status"
  [ "${lit:-0}" -gt 0 ] && flag="$flag FAIL:dom-literal"
  printf "%-26s | %s | cc=%-34s | cfs=%-4s | hsts=%s csp=%s | lit=%s h1=%s og=%s | sectxt=%s%s\n" \
    "$name" "${code:-ERR}" "${cc:0:34}" "${ccs:--}" "$hsts" "$csp" "$lit" "$h1" "$og" "$sectxt" "$flag"
}

if [ "${1:-}" = "--list" ]; then
  [ -f "${2:-}" ] || { echo "usage: $0 --list <file-of 'name url' lines>"; exit 1; }
  while read -r n u; do [ -n "$n" ] && [ "${n#\#}" = "$n" ] && probe "$n" "$u"; done < "$2"
elif [ -n "${2:-}" ]; then
  probe "$1" "$2"
else
  echo "usage: $0 <name> <url>   |   $0 --list <file>"; exit 1
fi
