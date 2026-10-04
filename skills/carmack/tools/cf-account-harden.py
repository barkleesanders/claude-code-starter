#!/usr/bin/env python3
"""Apply free Cloudflare account-security fixes idempotently across all zones.
Companion to cf-security-insights.sh (which does AI-bots/security.txt/worker-previews);
this covers the zone/DNS security layer: DNSSEC, Free WAF Managed Ruleset, Leaked-
Credential detection, CAA. Verified live 2026-07-07 (applied clean across 18 zones).

DRY_RUN=1 (default) prints what WOULD change. DRY_RUN=0 applies.
Deliberately SKIPS AI Labyrinth (user 2026-07-07: hurts AI/SEO) and Bot Fight Mode.

SAFE AUTO-APPLY set (idempotent, no mail/cert-break risk): dnssec, waf, leaked, caa.
  - CAA uses the union of CF Universal-SSL partner CAs (letsencrypt/pki.goog/ssl.com/
    sectigo/digicert) so cert RENEWAL never breaks; CF auto-adds its own partner CAA
    on top. Verified: after adding, Google-Trust-Services cert still served 200.
MAIL fixes are GATED behind INCLUDE_MAIL=1 (they touch DNS TXT / DMARC policy and are
account-specific — a domain that actually sends mail must NOT get p=reject blind):
  - parked : add SPF -all + empty DKIM + p=reject DMARC to no-mail domains (edit PARKED)
  - dmarc  : bump a p=none domain to p=quarantine (NEVER reject unattended; edit target)
Without INCLUDE_MAIL=1 those two are skipped. Run the /deepsearch CF audit first to know
which domains send mail before enabling them.
"""
import json, os, sys, urllib.request, urllib.error

CRED = json.load(open(os.path.expanduser('~/.cloudflared/cf-global-api-key.json')))
EMAIL, KEY, ACCT = CRED['email'], CRED['global_api_key'], CRED['account_id']
DRY = os.environ.get('DRY_RUN', '1') != '0'
ONLY = os.environ.get('ONLY', '')          # optional: restrict to one fix (dnssec|waf|leaked|parked|dmarc|caa)
ZONE_FILTER = os.environ.get('ZONE', '')   # optional: restrict to one zone name
INCLUDE_MAIL = os.environ.get('INCLUDE_MAIL', '0') == '1'  # gate the mail-touching fixes (parked, dmarc)

FREE_WAF_RULESET = "77454fe2d30c4220b5701f6fdfb893ba"  # Cloudflare Managed Free Ruleset (verified 2026-07-07)
PARKED = ["parked-example.com","example.com","hospitalledger.com",
          "treasureislandsfpoweroutages.com","operationepicfuryveterans.com"]
# CAA: CF Universal SSL CAs + reporting. Over-permissive on CA choice = never breaks renewal, still blocks rogue CAs.
CAA_ISSUERS = ["letsencrypt.org","pki.goog","ssl.com","sectigo.com","digicert.com"]
IODEF = "mailto:you@example.com"

def cf(path, method='GET', body=None):
    req = urllib.request.Request(f"https://api.cloudflare.com/client/v4{path}", method=method,
        headers={'X-Auth-Email': EMAIL, 'X-Auth-Key': KEY, 'Content-Type': 'application/json'},
        data=json.dumps(body).encode() if body is not None else None)
    try: return json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        try: b = json.loads(e.read()); b['_code'] = e.code; return b
        except Exception: return {'success': False, '_code': e.code}
    except Exception as e: return {'success': False, '_err': str(e)}

zones = cf("/zones?per_page=100")['result']
zmap = {z['name']: z['id'] for z in zones}
if ZONE_FILTER: zmap = {k: v for k, v in zmap.items() if k == ZONE_FILTER}
log = []
def act(zone, fix, detail, do):
    tag = "WOULD" if DRY else "DID"
    if DRY:
        print(f"  [{tag}] {zone:34s} {fix:9s} {detail}")
        log.append((zone, fix, 'dry', detail)); return
    r = do()
    ok = r.get('success')
    print(f"  [{'OK' if ok else 'ERR'}] {zone:34s} {fix:9s} {detail}" + ("" if ok else f"  !! {r.get('_code')} {[e.get('message') for e in r.get('errors') or []]}"))
    log.append((zone, fix, 'ok' if ok else 'err', detail))

def want(fix):
    if fix in ('parked', 'dmarc') and not INCLUDE_MAIL:
        return False   # mail-touching fixes are opt-in (INCLUDE_MAIL=1)
    return not ONLY or ONLY == fix

# --- 1. DNSSEC (enable where disabled) ---
if want('dnssec'):
    print("=== DNSSEC ===")
    for name, zid in zmap.items():
        st = (cf(f"/zones/{zid}/dnssec").get('result') or {}).get('status')
        # 'active' = live; 'pending' = enabled, DS auto-publishing at the registry (CF-registrar) — both mean done.
        if st in ('active', 'pending'): continue
        act(name, 'dnssec', f"enable (was {st})", lambda zid=zid: cf(f"/zones/{zid}/dnssec", 'PATCH', {"status":"active"}))

# --- 2. Free WAF Managed Ruleset (deploy entrypoint if absent) ---
if want('waf'):
    print("=== WAF Free Managed Ruleset ===")
    for name, zid in zmap.items():
        ep = cf(f"/zones/{zid}/rulesets/phases/http_request_firewall_managed/entrypoint")
        deployed = ep.get('success') and any(
            (r.get('action_parameters') or {}).get('id') == FREE_WAF_RULESET for r in (ep.get('result') or {}).get('rules') or [])
        if deployed: continue
        body = {"rules":[{"action":"execute","action_parameters":{"id":FREE_WAF_RULESET},
                          "expression":"true","description":"Cloudflare Free Managed Ruleset"}]}
        act(name, 'waf', "deploy free managed ruleset",
            lambda zid=zid, body=body: cf(f"/zones/{zid}/rulesets/phases/http_request_firewall_managed/entrypoint", 'PUT', body))

# --- 3. Leaked-credential detection ---
if want('leaked'):
    print("=== Leaked-credential detection ===")
    for name, zid in zmap.items():
        cur = cf(f"/zones/{zid}/leaked-credential-checks")
        if cur.get('success') and (cur.get('result') or {}).get('enabled'): continue
        act(name, 'leaked', "enable", lambda zid=zid: cf(f"/zones/{zid}/leaked-credential-checks", 'POST', {"enabled": True}))

# --- 4. Parked-domain no-mail lockdown (SPF -all, empty DKIM wildcard, strict DMARC) ---
if want('parked'):
    print("=== Parked-domain no-mail lockdown ===")
    recs = [
        ('TXT', '@',            'v=spf1 -all'),
        ('TXT', '*._domainkey', 'v=DKIM1; p='),
        ('TXT', '_dmarc',       'v=DMARC1; p=reject; sp=reject; adkim=s; aspf=s;'),
    ]
    for name in PARKED:
        zid = zmap.get(name)
        if not zid: continue
        existing = cf(f"/zones/{zid}/dns_records?type=TXT&per_page=100").get('result') or []
        def has(recname, needle):
            full = name if recname == '@' else f"{recname}.{name}"
            return any(e['name'].rstrip('.') == full and needle in e['content'] for e in existing)
        for rtype, rn, content in recs:
            key = 'v=spf1' if 'spf1' in content else ('v=DMARC1' if 'DMARC1' in content else 'v=DKIM1')
            if has(rn, key): continue
            dnsname = name if rn == '@' else f"{rn}.{name}"
            body = {"type":"TXT","name":dnsname,"content":content,"ttl":3600}
            act(name, 'parked', f"add TXT {rn} = {content[:32]}",
                lambda zid=zid, body=body: cf(f"/zones/{zid}/dns_records", 'POST', body))

# --- 5. example DMARC p=none -> p=quarantine (NEVER reject unattended; senders verified aligned) ---
if want('dmarc'):
    print("=== example.com DMARC p=none -> p=quarantine ===")
    zid = zmap.get('example.com')
    if zid:
        recs = cf(f"/zones/{zid}/dns_records?type=TXT&per_page=100").get('result') or []
        dmarc = next((e for e in recs if e['name'].startswith('_dmarc.example.com')), None)
        if dmarc and 'p=none' in dmarc['content']:
            newc = dmarc['content'].replace('p=none', 'p=quarantine')
            body = {"type":"TXT","name":dmarc['name'],"content":newc,"ttl":dmarc.get('ttl',1)}
            act('example.com', 'dmarc', f"p=none -> p=quarantine (keep rua)",
                lambda zid=zid, rid=dmarc['id'], body=body: cf(f"/zones/{zid}/dns_records/{rid}", 'PUT', body))
        elif dmarc:
            print(f"  [skip] example.com already {dmarc['content'][:40]}")

# --- 6. CAA records (add where absent) ---
if want('caa'):
    print("=== CAA records ===")
    for name, zid in zmap.items():
        existing = cf(f"/zones/{zid}/dns_records?type=CAA&per_page=50").get('result') or []
        if existing: continue  # already has CAA — leave it
        for ca in CAA_ISSUERS:
            for tag in ('issue','issuewild'):
                body = {"type":"CAA","name":name,"data":{"flags":0,"tag":tag,"value":ca},"ttl":3600}
                act(name, 'caa', f"{tag} {ca}",
                    lambda zid=zid, body=body: cf(f"/zones/{zid}/dns_records", 'POST', body))
        body = {"type":"CAA","name":name,"data":{"flags":0,"tag":"iodef","value":IODEF},"ttl":3600}
        act(name, 'caa', f"iodef {IODEF}",
            lambda zid=zid, body=body: cf(f"/zones/{zid}/dns_records", 'POST', body))

print(f"\n{'DRY-RUN' if DRY else 'APPLIED'}: {len(log)} actions")
import os, tempfile
_logdir = os.path.expanduser('~/.claude/logs')
os.makedirs(_logdir, exist_ok=True)
json.dump(log, open(os.path.join(_logdir, 'cf-harden-log.json'), 'w'), indent=1)
