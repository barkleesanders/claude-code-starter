#!/usr/bin/env bash
# security-txt-check.sh — /ship Phase 4.05g
#
# Every public HTML site must:
#   1. Serve /.well-known/security.txt (RFC 9116) with
#      Contact: mailto:security@<apex-of-THIS-site>
#   2. Redirect /security.txt → /.well-known/security.txt (301/302)
#   3. Forward security@<apex> to you@example.com via Cloudflare
#      Email Routing (destination already verified on this account 2026-04-24)
#
# The mailbox domain is derived from the site being shipped, never a hardcoded
# inbox on another zone. www.example.com → security@example.com.
#
# Usage:
#   security-txt-check.sh <repo> [--url https://apex] [--apply]
# Exit: 0 ok | 1 BLOCK | 2 UNMEASURED
set -u

FORWARD_TO="${SECURITY_TXT_FORWARD_TO:-you@example.com}"
APPLY=0
URL=""
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --url) URL="${2:-}"; shift 2 ;;
    --*) echo "security-txt-check: unknown flag $1" >&2; exit 2 ;;
    *) REPO="$1"; shift ;;
  esac
done

[ -n "$REPO" ] || { echo "usage: $0 <repo> [--url https://apex] [--apply]" >&2; exit 2; }
[ -d "$REPO" ] || { echo "security-txt-check: not a directory: $REPO" >&2; exit 2; }

# Skip non-HTML workers (no custom_domain / no HTML routes).
APEX=""
if [ -f "$REPO/wrangler.toml" ] || [ -f "$REPO/wrangler.jsonc" ] || [ -f "$REPO/wrangler.json" ]; then
  APEX=$(python3 - "$REPO" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
text = ""
for name in ("wrangler.toml", "wrangler.jsonc", "wrangler.json"):
    p = root / name
    if p.exists():
        text = p.read_text()
        break
hosts = []
for m in re.finditer(r'pattern\s*=\s*"([^"]+)"', text):
    hosts.append(m.group(1).split("/")[0])
for m in re.finditer(r'"pattern"\s*:\s*"([^"]+)"', text):
    hosts.append(m.group(1).split("/")[0])
hosts = [h[4:] if h.startswith("www.") else h for h in hosts if h and "." in h
         and not h.endswith(".workers.dev") and not h.endswith(".pages.dev")]
print(hosts[0] if hosts else "")
PY
)
fi

# A site hosted on a SUBDOMAIN (league.example.com) must advertise the mailbox of the
# REGISTERED ZONE (security@example.com) — a subdomain is not a zone and can never carry
# Email Routing. Resolve the apex by walking suffixes against the CF zones list; fall
# back to the two-label suffix when no creds are available. (Added 2026-09-10 after the
# check demanded security@league.example.com, an address that cannot exist.)
if [ -n "$APEX" ] && [ "$(printf '%s' "$APEX" | tr -cd . | wc -c)" -gt 1 ]; then
  ZONE_APEX=$(python3 - "$APEX" <<'PYZ'
import json, os, sys, urllib.request
host = sys.argv[1]; labels = host.split(".")
cands = [".".join(labels[i:]) for i in range(len(labels) - 1)]
creds = os.path.expanduser("~/.cloudflared/cf-global-api-key.json")
try:
    c = json.load(open(creds)); hdr = {"X-Auth-Email": c["email"], "X-Auth-Key": c["global_api_key"]}
    for z in cands:
        req = urllib.request.Request(f"https://api.cloudflare.com/client/v4/zones?name={z}", headers=hdr)
        if json.load(urllib.request.urlopen(req, timeout=10)).get("result"):
            print(z); sys.exit(0)
except Exception:
    pass
print(cands[-1])
PYZ
)
  [ -n "$ZONE_APEX" ] && APEX="$ZONE_APEX"
fi

if [ -z "$APEX" ]; then
  echo "security-txt-check: no custom-domain HTML host in wrangler config — skip"
  exit 0
fi
[ -z "$URL" ] && URL="https://$APEX"
MAILBOX="security@$APEX"

FAIL=0
UNMEASURED=0
echo "security-txt-check: $APEX  mailbox=$MAILBOX  url=$URL"

# --- live HTTP ---
WELL=$(mktemp)
ALIAS_HDR=$(mktemp)
curl -sS -D - -o "$WELL" --max-time 20 "$URL/.well-known/security.txt" > "${WELL}.hdr" 2>/tmp/sectxt-well.err || true
WELL_CODE=$(grep -oE "HTTP/[0-9.]+ [0-9]{3}" "${WELL}.hdr" | tail -1 | grep -oE "[0-9]{3}$" || true)
if [ -z "$WELL_CODE" ]; then
  echo "  UNMEASURED /.well-known/security.txt (curl failed: $(tr '\n' ' ' </tmp/sectxt-well.err))"
  UNMEASURED=1
elif [ "$WELL_CODE" != "200" ]; then
  echo "  BLOCK /.well-known/security.txt HTTP $WELL_CODE (want 200)"
  FAIL=1
else
  if grep -q "^Contact: mailto:$MAILBOX" "$WELL"; then
    echo "  ok   Contact: mailto:$MAILBOX"
  else
    echo "  BLOCK Contact mailbox is not $MAILBOX"
    echo "        body: $(tr '\n' '|' < "$WELL" | head -c 240)"
    FAIL=1
  fi
fi

curl -sS -D "$ALIAS_HDR" -o /dev/null --max-time 20 "$URL/security.txt" >/dev/null 2>/tmp/sectxt-alias.err || true
ALIAS_CODE=$(grep -oE "HTTP/[0-9.]+ [0-9]{3}" "$ALIAS_HDR" | head -1 | grep -oE "[0-9]{3}$" || true)
ALIAS_LOC=$(grep -i "^location:" "$ALIAS_HDR" | head -1 | tr -d '\r' | awk '{print $2}')
if [ -z "$ALIAS_CODE" ]; then
  echo "  UNMEASURED /security.txt (curl failed)"
  UNMEASURED=1
elif [ "$ALIAS_CODE" = "301" ] || [ "$ALIAS_CODE" = "302" ] || [ "$ALIAS_CODE" = "308" ]; then
  case "$ALIAS_LOC" in
    */.well-known/security.txt*) echo "  ok   /security.txt $ALIAS_CODE → $ALIAS_LOC" ;;
    *) echo "  BLOCK /security.txt $ALIAS_CODE Location=$ALIAS_LOC (want /.well-known/security.txt)"
       FAIL=1 ;;
  esac
elif [ "$ALIAS_CODE" = "200" ]; then
  echo "  BLOCK /security.txt is 200 — must 301 to /.well-known/security.txt (RFC 9116 alias)"
  FAIL=1
else
  echo "  BLOCK /security.txt HTTP $ALIAS_CODE (want 301 to /.well-known/security.txt)"
  FAIL=1
fi
rm -f "$WELL" "${WELL}.hdr" "$ALIAS_HDR"

# --- Workspace-hosted MX short-circuit (2026-09-09) ---
# A domain whose MX already points at Google Workspace (example.com) must NOT
# get Cloudflare Email Routing enabled: that rewrites MX away from aspmx.l.google.com
# and breaks the operational mailbox. Delivery for $MAILBOX is then a Workspace
# alias/group on that tenant (measured 2026-09-09: security@example.com is an
# alternate email on help@example.com), which the CF API cannot see. Treat a
# Google MX as "receive path exists" and skip the Email Routing block entirely.
MX_LIST="$(dig +short MX "$APEX" @1.1.1.1 2>/dev/null | tr 'A-Z' 'a-z')"
if printf '%s\n' "$MX_LIST" | grep -qE '(aspmx\.l\.google\.com|googlemail\.com|google\.com)\.?$'; then
  echo "  ok   MX for $APEX is Google Workspace ($(printf '%s' "$MX_LIST" | head -1 | awk '{print $2}')) — Email Routing must stay OFF; $MAILBOX is a Workspace alias"
  WORKSPACE_MX=1
else
  WORKSPACE_MX=0
fi

# --- Email Routing ---
CFG="$HOME/.cloudflared/cf-global-api-key.json"
if [ "$WORKSPACE_MX" = "1" ]; then
  :
elif [ ! -f "$CFG" ]; then
  echo "  UNMEASURED Email Routing (no $CFG)"
  UNMEASURED=1
else
  eval "$(python3 - "$CFG" "$APEX" "$MAILBOX" "$FORWARD_TO" "$APPLY" <<'PY'
import json, os, sys, urllib.request, urllib.error
cfg_path, apex, mailbox, forward_to, apply = sys.argv[1:6]
cfg = json.load(open(cfg_path))
email = cfg.get("email") or os.environ.get("CLOUDFLARE_EMAIL") or "you@example.com"
key = cfg["global_api_key"]
acct = cfg.get("account_id") or "<CLOUDFLARE_ACCOUNT_ID>"

def cf(method, url, data=None):
    req = urllib.request.Request(url, data=data, method=method, headers={
        "X-Auth-Email": email, "X-Auth-Key": key, "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return {"success": False, "errors": [{"message": body}]}

zones = cf("GET", f"https://api.cloudflare.com/client/v4/zones?name={apex}")
zid = ((zones.get("result") or [{}])[0] or {}).get("id")
if not zid:
    print("echo '  UNMEASURED Email Routing (no CF zone for this apex)'")
    print("UNMEASURED=1")
    sys.exit(0)
settings = cf("GET", f"https://api.cloudflare.com/client/v4/zones/{zid}/email/routing")
st = settings.get("result") or {}
enabled = bool(st.get("enabled"))
status = st.get("status")
print(f"echo '  routing enabled={enabled} status={status}'")
if not enabled or status not in ("ready",):
    if apply == "1":
        en = cf("POST", f"https://api.cloudflare.com/client/v4/zones/{zid}/email/routing/dns", b"{}")
        if en.get("success"):
            print("echo '  ok   enabled Email Routing DNS (MX+SPF)'")
            enabled = True
        else:
            print(f"echo \"  BLOCK enable Email Routing failed: {en.get('errors')}\"")
            print("FAIL=1")
    else:
        print("echo '  BLOCK Email Routing is not enabled — re-run with --apply'")
        print("FAIL=1")

rules = cf("GET", f"https://api.cloudflare.com/client/v4/zones/{zid}/email/routing/rules")
hit = False
for rule in rules.get("result") or []:
    if not rule.get("enabled"):
        continue
    tos = [m.get("value") for m in (rule.get("matchers") or []) if m.get("field") == "to"]
    dests = []
    for a in rule.get("actions") or []:
        if a.get("type") == "forward":
            dests.extend(a.get("value") or [])
    if mailbox.lower() in [t.lower() for t in tos if t] and forward_to.lower() in [d.lower() for d in dests]:
        hit = True
        print(f"echo '  ok   rule {mailbox} → {forward_to}'")
        break
if not hit:
    if apply == "1":
        body = json.dumps({
            "name": "security@ -> gmail",
            "enabled": True,
            "matchers": [{"type": "literal", "field": "to", "value": mailbox}],
            "actions": [{"type": "forward", "value": [forward_to]}],
        }).encode()
        created = cf("POST", f"https://api.cloudflare.com/client/v4/zones/{zid}/email/routing/rules", body)
        if created.get("success"):
            print(f"echo '  ok   created rule {mailbox} → {forward_to}'")
        else:
            print(f"echo \"  BLOCK create rule failed: {created.get('errors')}\"")
            print("FAIL=1")
    else:
        print(f"echo '  BLOCK no enabled rule {mailbox} → {forward_to} — re-run with --apply'")
        print("FAIL=1")
PY
)"
fi

echo "security-txt-check: fail=$FAIL unmeasured=$UNMEASURED"
if [ "$UNMEASURED" -ne 0 ] && [ "$FAIL" -eq 0 ]; then
  exit 2
fi
exit "$FAIL"
