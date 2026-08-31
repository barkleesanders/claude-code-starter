# Post-Deploy Verification & Monitoring

Covers Phase 4.08 (Workers-Cache post-deploy verification), Phase 4.1 (post-deploy verification), Phase 4.2 (multi-agent code review), Phase 4.3 (web performance audit), Phase 4.35 (visual regression check), Phase 4.5 (rollback), Phase 4.6 (CI gate), Phase 5 (monitoring), and Phase 6 (PR babysitter).

---

## Phase 4.08: WORKERS-CACHE POST-DEPLOY VERIFICATION (BLOCKING — added 2026-07-06)

**Fires when**: the deployed changeset enables or modifies the wrangler `cache` block (`"cache": { "enabled": … }`). Full pattern: `~/.claude/skills/shared/workers-cache-safety.md`.

**Why**: enabling Workers Cache changes the runtime's request presentation — the cache front-layer hands the Worker `http://` in `request.url` for HTTPS visitors (`cf-visitor` stays `{"scheme":"https"}`). On 2026-07-06 this 301-looped example.com sitewide for ~25 min (zone analytics: 301s 0–5/hr → 120 → 439/hr). Triage was slowed by a propagation false-negative: a 3-second post-disable curl said "didn't fix it" and triggered an unnecessary rollback — engage/disengage takes >30s to propagate.

**Protocol**:
1. **Staged enable** — if the diff changes worker code AND newly enables cache: deploy code with `cache.enabled: false` first, verify healthy, then flip the flag in a second deploy. Never combine an untested code change with the first cache-enable.
2. **Monitoring window** — at t+15s, t+45s, t+90s after the enable deploy:
   ```bash
   for p in "/" "/<html-page>" "/<json-api>" "/<public-asset>"; do
     curl -s -o /dev/null -w "$p -> %{http_code}\n" "https://<domain>$p?r=$RANDOM"
   done
   ```
   All expected 200s. A <60s check proves NOTHING in either direction.
3. **Semantic header checks** (per route class):
   ```bash
   curl -sI "https://<domain>/<json-api>" | grep -iE "^(cache-control|cf-cache-status):"   # authed/dynamic → private, no-store
   curl -sI "https://<domain>/<public-asset>" | grep -i cache-control                        # keeps its public, max-age opt-in
   curl -sI "https://<domain>/" | grep -i strict-transport                                   # HSTS present (the http:// presentation silently drops url.protocol-gated HSTS)
   ```
4. **Sitewide-3xx tripwire** — if ANY route 301/302s to its own URL: **immediately** redeploy with `cache.enabled: false`, wait ≥60s, re-verify, then diagnose:
   ```bash
   (timeout 20 npx wrangler tail --format json > /tmp/tail.json &); sleep 8
   curl -s -o /dev/null "https://<domain>/?tailprobe=$(date +%s)"; sleep 9
   grep -oE '"url": "https?://[^"]*tailprobe[^"]*"' /tmp/tail.json
   ```
   `http://` for an HTTPS probe = the scheme-presentation class → fix the middleware with the cf-visitor pattern (`visitorIsHttps()`, reference: AIVA `src/worker/middleware/securityHeaders.ts`), never `url.protocol`.
5. Re-enable only after the fix is deployed and step 2–3 pass clean.

---

## Phase 4.1: POST-DEPLOY VERIFICATION

### 4.1.-1 — VERIFY A GUARD WITHOUT FIRING ITS SIDE EFFECT (added 2026-08-25)

When the thing you shipped is a **guard on a side-effecting endpoint** (rate limit,
auth check, size cap, feature flag), the obvious live test is also a live *abuse* of
your own production system — sending five real bug reports, five real emails, five
real notifications to the operator's phone. That cost is usually why the guard goes
unverified, and an unverified guard is the same as no guard.

**Order the guard before the side effect and the free test falls out of the design.**
If the guard runs before the body is parsed, you can drive it with a body that is
*rejected downstream*, so every probe exercises the guard and none reaches the
side-effecting code:

```bash
# The guard runs first; `[]` then fails the "object body required" check, so
# recordBugReport() / sendTelegram() are never reached. Zero side effects.
for i in $(seq 1 7); do
  curl -sS -o /dev/null -w "%{http_code} " -X POST https://<site>/api/bug-report \
    -H 'Content-Type: application/json' -d '[]'
done   # expect: 400 400 400 400 400 429 429
curl -sS -D - -o /dev/null -X POST ... | grep -i '^retry-after'
```

Verified this way on improvebayarea 2026-08-25: `5×400 → 429`, `retry-after: 32`,
and **zero bug reports created**. If you *cannot* construct a probe that stops short
of the side effect, that itself is the finding — the guard is sitting after the
irreversible step and buys less than it appears to. Move it, then verify.

### 4.1.0 — ARTIFACT-FIRST RULE (BLOCKING, read before any browser check — added 2026-07-10)

**Never conclude "the deploy broke production" from a browser tab.** A cached HTML shell referencing
pre-deploy asset hashes produces a perfect impersonation of a broken deploy: the SPA fallback serves
`index.html` for the vanished `.js`, the browser refuses HTML as a module script, React never mounts, and
you see only the SEO fallback text. A long-lived tab or a service worker makes this near-certain — even
when driven live via fcdp/ccb. **The origin, not the tab, is the source of truth.**

Run this BEFORE any rollback, revert, or redeploy:

```bash
SITE=https://<domain>; CB=$(date +%s)
# 1. Which bundle does the LIVE html reference?
HASH=$(curl -s "$SITE/?cb=$CB" -H 'Cache-Control: no-cache' \
       | grep -o 'assets/index-[A-Za-z0-9_-]*\.js' | sort -u | head -1)
echo "live references: $HASH"
# 2. Does the origin serve it as JS, not HTML?
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" "$SITE/$HASH"
#    200 text/javascript -> healthy.   200 text/html -> the deploy REALLY is broken.
# 3. Does the deployed chunk contain the change you just shipped?
curl -s "$SITE/$HASH" | grep -c '<a string only the new code has>'
```

- `200 text/javascript` + your string present → **prod is healthy; your browser is stale.** Reload with
  `navigate_page {ignoreCache: true}` or a cache-busting query param. Do not roll back.
- `200 text/html` on a `.js` URL → the deploy is genuinely broken. Proceed to Phase 4.5.

Also, before calling any post-deploy curl a failure:
- **Allow >30s for Worker/CDN propagation.** A single immediate failure is not evidence (see Phase 4.08).
- `location.reload(true)` is a **no-op** in modern browsers — the `forceReload` argument was removed.
- `ERR_BLOCKED_BY_CLIENT` in the console is an **ad blocker in the profile**, not your code.

Full pattern: `~/.claude/skills/debug/references/csp-cache-patterns.md` #28. Reference incident
(2026-07-10, AIVA): the debug browser tab (the old seeded-profile clone, since REMOVED 2026-07-14 —
fcdp replaced it) showed the MIME error and an unmounted SPA while the origin served the new bundle
correctly and the deployed chunk contained the fix. Concluding from the tab would have rolled back a
correct deploy.


**Purpose**: Verify production deployment serves correct content after deploy.

**Multi-signal battery (fast first pass):** run `~/.claude/skills/ship/tools/fleet-verify.sh <name> <url>` (or `--list <file>` for a whole fleet) — one line per URL with HTTP status · Cache-Control · cf-cache-status · HSTS · CSP · rendered-DOM literal count · static h1 count · og:image · security.txt status. Grep the output for `FAIL:` markers (non-200 or a rendered `undefined`/`NaN`/`[object Object]`/`Invalid Date`). Two caveats baked into the tool: (1) its cache-buster joins `?`/`&` safely so a bare URL never becomes `/&x=…` (the 2026-07-06 false-404 sweep bug); (2) its h1 count is STATIC and includes inert `<template>` content — a `>1` is a "confirm with a live-DOM `querySelectorAll('h1').length`" flag, not an automatic fail (xbox-nxe: static 5, runtime 1). Then proceed to the content-specific checks below.

### Part 0: fcdp Live Screenshot (if available)

After deploy, take a screenshot of the live production site to visually verify. Use **`fcdp`**
(`~/tools/fcdp/fcdp`) for this — it drives the user's REAL Default-profile Chrome directly, so
public pages AND pages needing the user's real login (authed dashboard, admin) both work with
no re-login needed.

```bash
FCDP=~/tools/fcdp/fcdp
$FCDP open "$DEPLOY_URL" 2>/dev/null   # opens/selects a tab and reloads to pick up the new deploy
sleep 3
$FCDP shot /tmp/screenshot.png 2>/dev/null
echo "Screenshot saved to /tmp/screenshot.png — verify visually"
```

If the fcdp bridge is warm, this gives instant visual verification with no popups. If it's not
available (`bridge socket not found` — `launchctl kickstart -k gui/$(id -u)/com.barklee.fcdp-bridge`),
skip to curl checks.

### Part A: HTML Meta Tag Checks (curl)
```bash
HTML=$(curl -s "$DEPLOY_URL/?meta_check=$(date +%s)")
printf "%s" "$HTML" | rg -i '<title>|name="description"|rel="canonical"'
printf "%s" "$HTML" | rg -i 'property="og:(site_name|title|description|type|url|image|image:alt|image:width|image:height)"'
printf "%s" "$HTML" | rg -i 'name="twitter:(card|title|description|image|image:alt)"'
if printf "%s" "$HTML" | rg -i 'property="twitter:'; then
  echo "WARN: twitter tags use property=; Twitter expects name="
fi
OG_URL=$(printf "%s" "$HTML" | grep -oP 'property="og:image" content="\K[^"]+' | head -1)
[ -n "$OG_URL" ] || { echo "BLOCK: og:image missing"; exit 1; }
curl -sI "$OG_URL" | grep -Ei "^(HTTP|content-type)"
printf "%s" "$HTML" | grep -oP '(og|twitter):image" content="\K[^"]+'
```
- If `property=` on twitter tags: WARN — Twitter ignores them
- If no `?v=` param on image URLs: WARN — social platforms cache old images
- If image URL returns non-200 or non-`image/*`: BLOCK and fix before reporting success
- If there is no OG image yet: create a project-specific 1200x630 share image, add absolute URLs, then redeploy

### Part B: Visual Verification via agent-browser (CDP) — MANDATORY
```bash
# Open OG preview service
agent-browser open "https://www.opengraph.xyz"
sleep 2
agent-browser snapshot -i -c
agent-browser fill "@eN" "https://example.com"
agent-browser press Enter
sleep 5
agent-browser screenshot --path /tmp/og-preview-twitter.png
agent-browser scroll down 500
agent-browser screenshot --path /tmp/og-preview-full.png

# Also screenshot direct OG image
agent-browser open "https://example.com/images/og-social-card.png?v=20260306"
sleep 2
agent-browser screenshot --path /tmp/og-image-direct.png

# Trigger Twitter re-scrape
agent-browser open "https://x.com/intent/tweet?text=https://example.com"
sleep 3
```

**Fallback preview services** (if opengraph.xyz rate-limits):
1. `https://metatags.io/`
2. `https://socialsharepreview.com/`

### Part C: Download & Compare (When Card Shows Wrong Image)
```bash
# Download Twitter's cached card image
curl -s -o /tmp/twitter-cached.jpg "https://pbs.twimg.com/card_img/XXXXX/XXXXX?format=jpg&name=medium"
# Download what our server actually serves
curl -s -H "User-Agent: Twitterbot/1.0" -o /tmp/served.png "$(curl -s -H 'User-Agent: Twitterbot/1.0' https://example.com/ | grep -oP 'twitter:image" content="\K[^"]+')"
# Compare: if different = cache issue (add ?v=), if same = image file needs updating
```

### Two Cache Layers (Critical)
| Layer | What | Bust With |
|-------|------|-----------|
| **Page metadata** | og:image URL for page | Card Validator or `?v=N` on page URL |
| **Image CDN** | Image bytes at CDN | `?v=YYYYMMDD` on image URL in meta tags |

### Production Integration Tests (replaces CI `test-production` job)
```bash
# Run the same integration tests the CI ran against live production
timeout 60 TEST_BASE_URL=https://example.com npx vitest run tests/worker-integration.test.ts 2>&1
pkill -f vitest 2>/dev/null
# If fails: WARN (already deployed) — flag for investigation, do not auto-rollback
```

### Auth Instance Verification (CRITICAL — production must NOT serve dev-instance auth) {#auth-instance-verify}

> **For Clerk projects**: use the `clerk` CLI instead of hand-rolled curl when available — `clerk doctor --json` runs end-to-end checks (auth, link, env, instance reachability), `clerk config pull --instance prod` returns the live config, `clerk env pull` writes correct keys to `.env.local`. Falls back to the curl path below when CLI is unavailable. Prefer `clerk` for any agent/CI workflow.


After every deploy that touches auth, verify the LIVE bundle ships the production auth instance, not the dev shim. This catches:
- Hardcoded fallbacks that bypass env vars (CI builds run without `.env`)
- Stale CF cache serving the previous bundle's HTML
- Service-worker / browser cache locked on the old bundle
- Concurrent "clobber" deploys from another agent or shell that overwrote yours

```bash
# 1. Find the bundle the live HTML is referencing
LIVE=$(curl -s "${DEPLOY_URL}/sign-in?cb=$(date +%s)")
BUNDLE=$(echo "$LIVE" | grep -oE '/assets/index-[A-Za-z0-9_-]+\.js' | head -1)
echo "live bundle: $BUNDLE"

# 2. Compare to your local build — they MUST match. If different, CF served stale.
LOCAL=$(ls dist/client/assets/index-*.js 2>/dev/null | grep -v jszip | sort -k1 -t'/' | head -1 | xargs basename 2>/dev/null)
echo "local build: /assets/$LOCAL"
[ "$BUNDLE" = "/assets/$LOCAL" ] || echo "WARN: live bundle hash differs from local — likely CF cache HIT or clobber deploy"

# 3. Inspect the bundle for dev-instance auth references
LEAKS=$(curl -s "${DEPLOY_URL}${BUNDLE}" | grep -oE 'pk_test_[A-Za-z0-9_-]+|sk_test_[A-Za-z0-9_-]+|prime-rhino-[A-Za-z0-9-]+|[a-z0-9-]+\.clerk\.accounts\.dev' | sort -u)
if [ -n "$LEAKS" ]; then
  echo "BLOCK: bundle ships dev-instance auth refs:"
  echo "$LEAKS"
fi

# 4. Confirm prod auth instance is the one being targeted
EXPECTED=pk_live_   # or sk_live_, etc.
KEYS=$(curl -s "${DEPLOY_URL}${BUNDLE}" | grep -oE 'pk_(test|live)_[A-Za-z0-9_-]{20,}' | sort -u)
echo "keys in bundle: $KEYS"
echo "$KEYS" | grep -q "^${EXPECTED}" || echo "BLOCK: prod-flavored key missing from bundle"

# 5. CF cache HIT after deploy? Purge if so. cf-cache-status: HIT means edge is still
#    serving old HTML even though no-store headers say otherwise — happens when the
#    cached response was set BEFORE no-store was added.
CF_STATUS=$(curl -sI "${DEPLOY_URL}/sign-in" | awk -F': ' '/^cf-cache-status:/ {print tolower($2)}' | tr -d '\r')
if [ "$CF_STATUS" = "hit" ]; then
  echo "WARN: CF served HTML from cache. Purging zone."
  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE}/purge_cache" \
    -H "X-Auth-Email: ${CF_EMAIL}" -H "X-Auth-Key: ${CF_API_KEY}" \
    -H "Content-Type: application/json" -d '{"purge_everything":true}' | jq -r '.success'
  sleep 4  # let purge propagate, then re-run steps 1-3
fi

# 6. Auth-provider frontend env (if applicable) — confirms instance is reachable on the
#    custom domain AND has the expected provider config. For Clerk:
curl -s "https://clerk.${ROOT_DOMAIN}/v1/environment" -o /dev/null -w "frontend-api: %{http_code}\n"
# Status 200 = custom domain DNS + SSL working. 4xx/5xx = DNS/SSL issue.
```

**Decision rule**: any leak found → BLOCK. Bundle hash mismatch + CF HIT → purge and re-verify (max 2 retries). Auth provider frontend not 200 → BLOCK (DNS/SSL not ready, OAuth will fail).

**Generalize the dev-fingerprint patterns** for the auth provider in use:

| Provider | Dev fingerprint to grep | Prod fingerprint expected |
|---|---|---|
| Clerk | `pk_test_*`, `*.clerk.accounts.dev`, instance slug like `prime-rhino-99` | `pk_live_*`, `clerk.<root>` |
| Auth0 | `<tenant>-dev.<region>.auth0.com` | `<tenant>.<region>.auth0.com` or `auth.<root>` |
| Supabase | project ref ending `-dev`, `localhost:54321` | live project ref + `<ref>.supabase.co` |
| Firebase | demo-* projectId, `localhost:9099` | real projectId, `<project>.firebaseapp.com` |

### Pre-deploy: sweep stale on-disk checkouts (MANDATORY when auth keys / env-baked secrets are involved)

A clean deploy from `main` can be silently undone seconds later by another agent or shell that runs `wrangler deploy` from a stale on-disk checkout (git worktree, sibling clone, conductor workspace, evo experiment worktree). The stale checkout has older source where the env fallback is still the dev value, so it ships dev keys to prod.

Run this BEFORE Phase 4 deploy to find any checkout that would re-clobber:

```bash
# 1. Worktrees of the current repo
git worktree list

# 2. Machine-wide hunt for the dev fingerprint (replace pattern per provider)
DEV_FP='pk_test_cHJpbWUtcmhpbm8'   # change for non-Clerk projects
find ~ -maxdepth 6 -name "App.tsx" -path "*react-app*" 2>/dev/null \
  | xargs grep -l "$DEV_FP" 2>/dev/null
# Also sweep already-built dist artifacts (someone may deploy them without rebuilding)
find ~ -maxdepth 8 -path "*/dist/client/assets/index-*.js" 2>/dev/null \
  | xargs grep -l "$DEV_FP" 2>/dev/null
```

If anything matches: either remove the worktree (`git worktree remove --force <path>`), patch the file (`sed -i.bak`), or accept the risk and proceed (NOT recommended — the next background agent run will undo your deploy).

**Real incident (2026-04-30):** A clean prod cutover was clobbered 4+ hours later by a 21:09 deploy from a stale `.evo` worktree at a pre-cutover commit. 28 `.evo/run_*/worktrees/exp_*` worktrees + 2 conductor checkouts + 2 sibling explorations all had `pk_test_*` baked in. Single sweep + `git worktree remove --force` chain + `sed` patches across 4 sibling files closed the loop.

### Deploy clobber detection (concurrent-deploy guard)

Another agent, shell, or CI run can `wrangler deploy` (or equivalent) seconds after yours, overwriting your bundle with a stale build. Pin to the version_id you just deployed and warn if it changes during the verification window:

**⚠️ The snippet that lived here until 2026-08-03 was BROKEN and silently always passed.** Keep the
corrected commands below; do not "restore" the old ones. Both of its operands evaluated to the empty
string, so the comparison was `[ "" = "" ]` — true, every time, on every repo. It never once detected a
clobber while looking exactly like a working gate. The two defects, verified against wrangler 4.113:

| Old line | Why it produced `""` |
|---|---|
| `wrangler deployments list \| awk '/Current Version ID:/'` | **`deployments list` never prints that string.** Only `wrangler deploy` does, on its last line. |
| `... \| grep -A1 'Created:' \| head -2 \| awk '/Version/'` | `deployments list` prints **oldest-first**, so `head` grabs the OLDEST deployment — and the field is `Version(s):`, which that `awk` misses anyway. |

Correct version — capture from the deploy itself, compare against `deployments status`:

```bash
# 1. Capture the version FROM THE DEPLOY OUTPUT. This is the only command that prints it.
DEPLOYED_VERSION=$(wrangler deploy 2>&1 | tee /dev/stderr | awk '/Current Version ID:/ {print $NF; exit}')
[ -n "$DEPLOYED_VERSION" ] || { echo "BLOCK: could not capture a version id — deploy may have failed"; }

# 2. Wait past propagation (>30s; a <60s check is not evidence), then ask what is CURRENTLY live.
sleep 45
LIVE=$(wrangler deployments status 2>&1 \
       | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

# 3. A MISMATCH IS NOT A CLOBBER. It is a prompt to verify by CONTENT (step 4).
if [ "$DEPLOYED_VERSION" != "$LIVE" ]; then
  echo "NOTE: live version is $LIVE, not the $DEPLOYED_VERSION wrangler printed."
  echo "      This is EXPECTED on some repos (see below). Do NOT roll back."
  echo "      Resolve it with the content check in step 4, not by version id."
fi
```

> ⚠️ **A version-id mismatch is NOT evidence of a clobber, and on its own must never
> justify a rollback.** Verified on example 2026-08-03: `wrangler deploy` printed
> `Current Version ID: b0e60e43` (21:23:05Z) and **29 s later** `587279b3` (21:23:34Z)
> became the live version. The step-3 comparison therefore reports a clobber on a
> completely normal, successful deploy. Versions land in pairs/triples with irregular
> gaps (29 s, 35 s, 43 s, 61 s), all stamped `src=wrangler trig=version_upload` by the
> same author — so the CF annotation in the next section **cannot** separate them either.
> This exact false signal is what made `wrangler rollback` feel justified once before,
> and the rollback is what actually broke production.

**4. Verify by CONTENT — this is the check that actually proves your deploy landed.**
Version ids are metadata; the bytes being served are the fact.

```bash
# Pick a string that exists ONLY in this change (test id, event name, data-attribute).
MARKER='composer-sms-transport-warning'

# Resolve the REAL module script. Do NOT grep the first /assets/*.js in the HTML —
# a modulepreload or JSON-LD ref will point at a stale/nonexistent bundle and mislead you.
CB=$(date +%s%N)
HTML=$(curl -s -m 20 "https://$HOST/$ROUTE?cb=$CB")
ENTRY=$(printf '%s' "$HTML" | grep -oE '<script type="module"[^>]*src="[^"]+"' | grep -oE '/assets/[^"]+')

# A .js URL answering 200 text/html means that asset is ABSENT and the SPA
# fallback replied. Content-type is the tell, not the status code.
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' -m 20 "https://$HOST$ENTRY?cb=$CB"

# Then grep the chunk that carries your change (often a code-split chunk, not the entry).
curl -s -m 30 "https://$HOST/assets/<your-chunk>.js?cb=$CB" | grep -c "$MARKER"   # expect >=1
```

Expect the live chunk's **hash to differ** from your local build even when the deploy is
yours: a rebuild that changes one chunk's content hash cascades into every importer,
because the import specifier is part of the importing file's bytes. Diff the two and
confirm the only differences are sibling-chunk filenames — if the application code is
identical, it is your build. On example the live and local admin chunks were both
100,283 B and differed solely in `index-BqvIB0ze.js` vs `index-CybPCm53.js` and
`jszip.min-CjCcE8IK.js` vs `jszip.min-DHek5_FY.js`.

**5. Worker-side code has no client asset to grep — fetch the DEPLOYED SCRIPT.**
The check above only proves the *client bundle* landed. A change to `scheduled()`,
a service, or a route handler ships in the Worker script, which is not reachable
by curling the site. Pull it from the CF API and grep for a marker only your
change has:

```bash
CFG=~/.cloudflared/cf-global-api-key.json
EMAIL=$(python3 -c "import json;print(json.load(open('$CFG'))['email'])")
KEY=$(python3   -c "import json;print(json.load(open('$CFG'))['global_api_key'])")
ACC=$(python3   -c "import json;print(json.load(open('$CFG'))['account_id'])")

curl -s -H "X-Auth-Email: $EMAIL" -H "X-Auth-Key: $KEY" \
  "https://api.cloudflare.com/client/v4/accounts/$ACC/workers/scripts/<script-name>" \
  -o /tmp/deployed_worker.js
wc -c /tmp/deployed_worker.js                      # non-trivial size = real script
grep -c '<marker-from-your-change>' /tmp/deployed_worker.js   # expect >=1
```

Grep **several** markers, not one — a single hit can come from a comment or a
string that predates your change. Note the credential file key is
`global_api_key`, not `api_key`. This is the only way to answer "is my worker
code live" without waiting for it to run.

**6. A NEGATIVE result from an eventually-consistent store is not evidence — poll it.**
Cloudflare KV reads lag. A key your new code writes can read `404` for minutes
*after it was written*, so a single read that comes back empty proves nothing and
will send you diagnosing a fix that already worked.

```bash
# WRONG — one read, then a conclusion
wrangler kv key get <key> --namespace-id <ns> --remote     # 404 -> "it failed"

# RIGHT — poll until it appears or a real deadline passes
until R=$(wrangler kv key get <key> --namespace-id <ns> --remote 2>&1 \
          | grep -oE '<expected-shape>'); [ -n "$R" ]; do sleep 20; done
```

**Also check the write is even reachable before treating absence as failure.** If
the key is written only on a success branch (`if (result.ok) await kv.put(...)`),
its absence during a known-bad upstream state is the CORRECT behavior, not a bug.
Establish that the precondition holds before you read.

Reference incident (2026-08-03, AIVA GV-rotation): `gv_rotated_at` read `404`
twice post-deploy and the agent began reasoning about why rotation "didn't
return ok". It had succeeded at `22:40:59.844Z`; KV simply had not propagated. A
polling monitor produced the truth. Pattern #32's "KV reads lag" line existed and
was still walked into — hence this concrete recipe rather than a warning.

**Then attribute it before reacting.** A version you did not expect is not proof of a rogue actor.
Ask the Cloudflare API who made it — `annotations['workers/triggered_by']` is authoritative:

```bash
# build → Cloudflare Workers Builds (CI).  version_upload → a plain `wrangler deploy` by someone.
curl -s -H "X-Auth-Email: $CFE" -H "X-Auth-Key: $CFK" \
  "https://api.cloudflare.com/client/v4/accounts/$ACCT/workers/scripts/$NAME/versions/$LIVE" \
| python3 -c "import sys,json;r=json.load(sys.stdin)['result'];m=r.get('metadata',{});a=r.get('annotations',{}) or {};print(m.get('source'),m.get('author_email'),a.get('workers/triggered_by'))"
```

**Real incident (2026-04-30):** Three separate `wrangler deploy` runs from concurrent shells/agents on the same machine overwrote each other within 30 seconds. The deploy log said "success" each time, but the live bundle ship-tested against the wrong version twice in a row before being caught.

**Real incident (2026-08-03, AIVA — the one that proved this gate was dead):** several unexplained versions
appeared minutes apart during a ship. Because the guard above silently passed, the drift was invisible; the
agent then saw a blank admin page **in a long-lived browser tab**, concluded production was down, and ran
`wrangler rollback`. *The rollback is what actually broke production* — it pinned the worker to an old
bundle while users held the new shell. The origin had been healthy the whole time (`/assets/index-*.js`
→ `200 text/javascript`). Two lessons, both now mechanical:
- Never conclude "prod is broken" from a browser. Check the ORIGIN (debug Pattern #28, and the
  pre-rollback block at the top of this file). Enforced by the PreToolUse hook
  `~/.claude/skills/hooks/pre-bash-rollback-origin-gate.sh`, which BLOCKS `wrangler rollback` when the
  origin still serves the entry bundle as real JS (override: `CLAUDE_ALLOW_ROLLBACK=1`).
- An unexpected version means **investigate**, never **roll back**. Rollback is for a *proven* bad
  deploy, not for an unexplained one.

### Sitemap Live Check
```bash
# Verify production sitemap has no auth/noindex pages
curl -s "$DEPLOY_URL/sitemap.xml" | grep -E "sign-in|sign-up|dashboard|admin"
```

### WWW Redirect Check (if applicable)
```bash
curl -sI "https://www.$(echo $DEPLOY_URL | sed 's|https://||')" | grep -E "^(HTTP|location)"
```
If www returns 200 instead of 301, auth will break. Use Cloudflare MCP to update redirect ruleset.

### GitHub README Image Cache-Busting (if images changed)
```bash
CHANGED_IMAGES=$(git diff --name-only HEAD~1 | grep -E '\.(png|jpg|jpeg|gif|svg|webp)$' || true)
if [ -n "$CHANGED_IMAGES" ] && [ -f README.md ]; then
  for img in $CHANGED_IMAGES; do
    BASENAME=$(basename "$img")
    if grep -q "$BASENAME" README.md; then
      TODAY=$(date +%Y%m%d)
      sed -i.bak -E "s|(${BASENAME})(\?v=[0-9]+)?\"|\1?v=${TODAY}\"|g" README.md
      rm -f README.md.bak
      echo "Cache-busted $BASENAME in README.md"
    fi
  done
fi
```

---

## Phase 4.2: MULTI-AGENT CODE REVIEW (PRE-MERGE QUALITY GATE)

**Purpose**: Run parallel specialized code reviews before changes reach production. Catches security, performance, architecture, and mobile issues that single-pass reviews miss.

**Trigger**: Automatically when changes span 3+ files or touch security-sensitive paths (`src/worker/routes/`, `src/worker/middleware/`, auth, payment, or admin code). Skip for single-file copy/config changes.

**Execution**: Launch 3 parallel review agents using the Agent tool. Each agent gets the diff (`git diff HEAD~1`) and reviews from a different perspective:

1. **Security Reviewer** — XSS vectors, auth bypass, injection, secrets exposure, OWASP top 10
2. **Performance Reviewer** — N+1 queries, bundle size impact, unnecessary re-renders, memory leaks
3. **Mobile/UX Reviewer** — Responsive breakpoints, touch targets, text overflow at 375px, a11y

```
Launch 3 Agent tools in parallel (single message):
- Agent 1 (subagent_type: code-reviewer): "Review this diff for security issues: [diff]"
- Agent 2 (subagent_type: performance-oracle): "Review this diff for performance: [diff]"
- Agent 3 (subagent_type: general-purpose): "Review this diff for mobile/responsive issues at 375px: [diff]"
```

**Decision logic**:
- If ANY reviewer finds a CRITICAL issue: **BLOCK** deployment, display findings
- If only WARNings: Display findings, continue deployment
- If all clear: Continue silently

**Override**: `--skip-review` to bypass (logged to audit trail)

---

## Phase 4.25: AIVA / Cloudflare Live Artifact Verification

**Trigger**: Run for AIVA and any Cloudflare Worker/static-assets site where auth, CSP, env bindings, or generated assets changed.

**Execution**:
```bash
PROD_URL="https://example.com"

# HTML must be freshly fetched and contain no retired auth-provider fingerprint.
curl -sS "${PROD_URL}/?ship_cb=$(date +%s)" > /tmp/ship-live.html
rg -i 'clerk\.[a-z0-9.-]+|clerk-js|@clerk/|prime-rhino-99|\.clerk\.accounts\.dev|pk_(live|test)|sk_test' /tmp/ship-live.html && echo "BLOCK: retired auth fingerprint in live HTML"

# CSP must not retain stale dev origins.
curl -sSI "${PROD_URL}/?ship_cb=$(date +%s)" > /tmp/ship-live.headers
rg -i 'content-security-policy|cf-ray|cf-cache-status' /tmp/ship-live.headers
rg -i 'clerk\.[a-z0-9.-]+|clerk-js|@clerk/|prime-rhino-99|\.clerk\.accounts\.dev|pk_(live|test)|sk_test' /tmp/ship-live.headers && echo "BLOCK: retired auth fingerprint in live headers"

# First-party Better Auth must be alive and distinguish invalid credentials.
curl -sS -o /dev/null -w '%{http_code}\n' "${PROD_URL}/api/auth/ok"

# Worker secrets must be secrets, not plaintext vars.
npx wrangler secret list

# If available in the repo, run the live production integration suite.
npm run test:integration:prod
```

**Decision logic**:
- BLOCK if AIVA live HTML or CSP contains any Clerk host/key/SDK/JWKS fingerprint; absence of `clerk.example.com` is expected
- BLOCK if `/api/auth/ok` is not 200 or wrong-password sign-in is not 401
- BLOCK if a sensitive Worker binding is still a plaintext var instead of `secret_text`
- BLOCK if production integration fails

---

## Phase 4.3: WEB PERFORMANCE AUDIT (POST-DEPLOY)

**Purpose**: Measure all four Lighthouse categories after every production deploy. Detect regressions AND surface actionable fixes to push toward 100/100.

**Trigger**: After successful deployment (Phase 4 complete). Runs automatically.

**Execution**: Use `lighthouse` CLI directly (more reliable than Chrome DevTools MCP for scoring). Always run **3 times and take the median** — single runs have ±5-point variance.

```bash
URL="https://<deployed-url>/"
for i in 1 2 3; do
  mkdir -p /tmp/lh-$i && cd /tmp/lh-$i
  lighthouse "$URL?v=$(date +%s)$i" \
    --output=json --output-path=./home.json \
    --only-categories=performance,accessibility,best-practices,seo \
    --chrome-flags="--headless --no-sandbox --incognito" --quiet 2>&1 | tail -1
done

# Summarize all 3 runs
for i in 1 2 3; do
  python3 -c "
import json
d = json.load(open('/tmp/lh-$i/home.json'))
c, a = d['categories'], d['audits']
print(f'Run $i: perf={int((c[\"performance\"][\"score\"] or 0)*100):>3}  a11y={int((c[\"accessibility\"][\"score\"] or 0)*100):>3}  bp={int((c[\"best-practices\"][\"score\"] or 0)*100):>3}  seo={int((c[\"seo\"][\"score\"] or 0)*100):>3}  LCP={a[\"largest-contentful-paint\"].get(\"displayValue\",\"?\"):<7}  FCP={a[\"first-contentful-paint\"].get(\"displayValue\",\"?\"):<7}  TBT={a[\"total-blocking-time\"].get(\"displayValue\",\"?\")}')
"
done
```

**Decision logic (strict — targets 100/100):**

| Category | Score | Action |
|----------|------:|--------|
| Performance | < 50 | **BLOCK** — severe regression, rollback candidate |
| Performance | 50-79 | **WARN** — load `carmack:lighthouse-optimization.md`, suggest `/carmack lighthouse 100` |
| Performance | 80-94 | WARN+ — surface top 3 blockers (see below) |
| Performance | 95+ | PASS |
| Accessibility | < 100 | **WARN** — a11y violations are real bugs, not variance. Surface each failing audit's `details.items` |
| Best Practices | < 100 | **WARN** — surface deprecations + CSP violations |
| SEO | < 100 | **WARN** — SEO fails are almost always trivial to fix |

**Regression detection**: If previous baseline exists in `.ship/lighthouse-baseline.json`, WARN on any category drop > 5 points. Always save the NEW median as the new baseline.

**Surface top 3 blockers** (when Perf < 95): extract the highest-weight failing audits and dump their `details.items`:

```python
# /tmp/lh-blockers.py
import json, sys
d = json.load(open(sys.argv[1]))
cats, aud = d['categories'], d['audits']
for cat in ['performance','accessibility','best-practices','seo']:
    if (cats[cat]['score'] or 0) * 100 >= 100: continue
    fails = sorted(
        [r for r in cats[cat]['auditRefs']
         if (a := aud.get(r['id'], {})).get('score') is not None and a['score'] < 1 and r.get('weight', 0) > 0],
        key=lambda r: -r['weight']
    )[:3]
    if not fails: continue
    print(f'\n=== {cat.upper()} — top 3 blockers ===')
    for r in fails:
        a = aud[r['id']]
        items = (a.get('details') or {}).get('items') or []
        print(f'  w={r["weight"]:>2.0f}  {r["id"]}: {a.get("title","")[:60]}')
        for it in items[:2]:
            n = it.get('node', {})
            if n.get('snippet'):
                print(f'      snippet: {str(n["snippet"])[:140]}')
            for k in ['url','wastedMs','wastedBytes','reason']:
                if k in it: print(f'      {k}: {str(it[k])[:140]}')

# Check for the #1 hidden TBT villain
for t in (aud.get('long-tasks',{}).get('details') or {}).get('items', []):
    if 'challenge-platform' in t.get('url','') and t.get('duration', 0) > 500:
        print(f'\n🚨 CF Bot Fight Mode JS challenge: {t["duration"]:.0f}ms blocking')
        print('   Disable via: curl -X PUT https://api.cloudflare.com/client/v4/zones/<zone>/bot_management')
        print('   Fix playbook: ~/.claude/skills/carmack/references/lighthouse-optimization.md #2')
```

**Display format (after median computed)**:
```
-- Phase 4.3: Web Performance (3-run median) --
Category       | Score | Target | Status
---------------|-------|--------|--------
Performance    | 97    | 100    | WARN
Accessibility  | 100   | 100    | PASS
Best Practices | 100   | 100    | PASS
SEO            | 100   | 100    | PASS

Core vitals (median run):
FCP  1.8s  LCP  2.4s  TBT  0ms  CLS  0.00

Top Perf blockers to reach 100:
  w=10  first-contentful-paint: 1.8s (target < 1.8s — right at threshold)
  w=25  largest-contentful-paint: 2.4s (target < 2.5s — marginal)

Next steps: /carmack lighthouse 100  (loads lighthouse-optimization.md playbook)
```

**Fallback**: If `lighthouse` CLI isn't installed (`command -v lighthouse` fails), print install hint (`npm i -g lighthouse`) and skip — don't BLOCK the deploy on missing tooling.

---

## Phase 4.35: VISUAL REGRESSION CHECK (POST-DEPLOY)

**Purpose**: Screenshot the live production site at desktop and mobile viewports to catch visual regressions.

**Trigger**: After successful deployment, runs automatically if `agent-browser` or Chrome CDP is available.

**Execution**: Use `/test-browser` approach — screenshot key pages at multiple viewports.

```
1. Screenshot production at 3 viewports:
   a. Desktop (1440px) — full page
   b. Tablet (768px) — full page
   c. Mobile (375px) — full page

2. Key pages to check (detect from router or sitemap):
   - Homepage / Landing page
   - Dashboard (if auth available)
   - Admin pages (if admin)

3. For each screenshot:
   - Check for horizontal overflow (page wider than viewport)
   - Check for blank/empty content areas
   - Check for overlapping elements
   - Verify no broken images (alt text visible instead of image)
```

**Using fcdp (preferred — uses the live, real-profile session)**:
```bash
FCDP=~/tools/fcdp/fcdp
$FCDP open "$DEPLOY_URL"
sleep 3

# Desktop screenshot
$FCDP shot /tmp/screenshot.png
# Read the screenshot to check for visual issues

# For mobile: use agent-browser with viewport setting
agent-browser open "$DEPLOY_URL" --viewport 375x812
agent-browser screenshot --path /tmp/mobile-screenshot.png
agent-browser close
```

**Using agent-browser (fallback — headless)**:
```bash
# Desktop
agent-browser open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-desktop.png --full
agent-browser close

# Mobile
agent-browser --viewport 375x812 open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-mobile.png --full
agent-browser close
```

**Decision logic**:
- If screenshots show blank page: **BLOCK** — deployment broke rendering
- If mobile screenshot shows horizontal scroll: **WARN** — responsive issue
- If all screenshots look normal: PASS
- If browser tools unavailable: Skip with message, not a blocker

**Override**: `--skip-visual` to bypass

---

## Phase 4.5: DEPLOYMENT FAILURE ROLLBACK (CONDITIONAL)

**Trigger**: If any critical platform deployment fails (Vercel or Cloudflare)

1. Display failure summary with specific error details
2. Offer rollback options:
   1. Revert last commit and force push (recommended)
   2. Deploy previous working commit to platforms
   3. Keep current state and fix manually
   4. Cancel (code stays on GitHub, site broken)
3. Execute chosen rollback option
4. Verify rollback deployment success
5. Log rollback action in deployment history
6. Update README/CHANGELOG with rollback note if executed

---

## Phase 4.6: GITHUB ACTIONS CI GATE (POST-PUSH)

**Purpose**: Watch for CI failures after push. Fix and retry up to 3 times.

**Trigger**: After every `git push` if repo has `.github/workflows/` or `gh run list` returns results.

**Default behavior (non-blocking)**: Local checks (build, lint, type-check, targeted tests) already ran before pushing. CI is monitored for **failures only** — do NOT block waiting for slow full test suites to complete.

**Flags**:
| Flag | Behavior |
|------|----------|
| (default) | Quick fail scan only — non-blocking |
| `--watch-ci` | Block until all CI checks complete (old behavior) |
| `--no-ci` | Skip Phase 4.6 entirely |

```bash
# Wait for CI to register
sleep 30

COMMIT=$(git rev-parse HEAD)

if [ "${WATCH_CI}" = "true" ]; then
  # --watch-ci flag: block until all checks complete (old behavior)
  PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)
  if [ -n "$PR_NUM" ]; then
    gh pr checks "$PR_NUM" --watch --fail-fast
  else
    for RUN_ID in $(gh run list --commit "$COMMIT" --json databaseId --jq '.[].databaseId'); do
      gh run watch "$RUN_ID"
    done
  fi
else
  # Default: quick failure scan (non-blocking)
  # Wait another 60s for fast-failing jobs (syntax errors, missing files, import failures)
  sleep 60
  FAILED=$(gh run list --commit "$COMMIT" --json conclusion,databaseId \
    --jq '.[] | select(.conclusion=="failure") | .databaseId' 2>/dev/null)

  if [ -n "$FAILED" ]; then
    # CI failed — read logs and fix
    for RUN_ID in $FAILED; do
      gh run view "$RUN_ID" --log-failed 2>&1 | tail -50
    done
    # Proceed to fix cycle below
  else
    # No failures detected in quick window — proceed without blocking
    echo "CI running in background (no failures detected in quick scan). Fix will auto-apply if it fails."
    # Exit Phase 4.6 — do not block
  fi
fi
```

**On CI Failure** (max 3 retry cycles):
1. Get failure logs: `gh run view <id> --log-failed | tail -50`
2. Identify and fix the issue
3. Commit fix and push
4. Wait for new checks
5. If still failing after 3 attempts: STOP and report to user

| Failure Pattern | Likely Cause | Quick Fix |
|----------------|-------------|-----------|
| `cargo fmt` diff | Formatting mismatch | `cargo fmt --all` |
| `unused_mut` / `dead_code` | Cross-platform cfg blocks | Add `#[allow(...)]` |
| `npm test` / `vitest` failure | Test regression | Fix test or source code |
| Lint errors | Style violations | Auto-fix with `--fix` flag |
| Type errors (tsc) | TypeScript strict mode | Fix types |
| Missing translations | New strings not localized | Add translations for all locales |

---

## Phase 5: POST-DEPLOY MONITORING (CONDITIONAL)

**Trigger**: Only if Phase 1.5 verification checklist was generated

Display persistent monitoring reminder with time-based checkpoints:
- Within 5 minutes: Run post-deploy verification SQL queries
- At +1 hour: Check error dashboard for anomalies
- At +4 hours: Spot check random records
- At +24 hours: Run final data integrity audit

Provide specific commands/links for each checkpoint.

---

## Phase 6: PR BABYSITTER (FIRE-AND-FORGET)

**Trigger**: Automatically after Phase 3 push completes, when ALL of these are true:
- Current branch is NOT main/master/production/prod
- A PR exists: `gh pr view --json number,url` succeeds
- CI checks are configured (`.github/workflows/` exists or `gh pr checks` returns results)

**Skip when**: Direct push to default branch, `--no-babysit` flag, or no PR exists.

**Execution**: Launch as a **background agent** (`run_in_background: true`) immediately after Phase 3 push. The main `/ship` pipeline continues to Phase 3.5+ without waiting. Display:
```
-- Phase 6: PR Babysitter launched in background --
Monitoring PR #<number> for CI failures, reviews, and merge blockers
Will auto-fix what it can; you'll be notified when done or blocked.
```

### Background Agent Loop

**1. Status Check** (each iteration):
```bash
gh pr view --json number,url,state,mergeable,reviewDecision,statusCheckRollup,reviews
gh pr checks
```

**2. Triage & Act** (priority order):

| Priority | Condition | Action |
|----------|-----------|--------|
| 1 | **PR merged or closed** | Exit loop. Report final status. |
| 2 | **New review comments** | Read feedback. If actionable: fix, commit, push. If ambiguous: reply, flag for human. |
| 3 | **CI failure (PR-related)** | Read failure logs. Identify root cause. Fix, commit, push. |
| 4 | **CI failure (flaky)** | Rerun only failed jobs: `gh run rerun <id> --failed`. Max 2 retries per run. |
| 5 | **Merge conflict** | `git fetch origin main && git merge origin/main`, resolve conflicts, push. |
| 6 | **All green, approved** | Report "PR is merge-ready" and exit. |

**3. Flaky vs Real Failure Detection**:
- **Flaky**: Test passed locally, failure in unrelated file, known flaky pattern (timeout, network, race)
- **Real**: Failure in files changed by this PR, compile/type error, deterministic across retries

**4. Polling Cadence** (adaptive backoff):
- CI pending: every 30 seconds
- CI just failed (fixing): every 15 seconds
- CI green, waiting on review: every 2 minutes
- All green + approved: exit
- Max total runtime: 30 minutes

**5. Exit Conditions**:

| Condition | Output |
|-----------|--------|
| PR merged | "PR #N merged successfully" |
| PR closed | "PR #N was closed without merging" |
| All checks pass + approved | "PR #N is merge-ready — waiting for you to merge" |
| 30 min timeout | "Babysitter timed out. Run `/ship --babysit` to resume." |
| Stuck on required approval | "PR #N needs human review approval — pausing" |
| 3+ failed fix attempts | "Could not auto-fix CI after 3 attempts. Manual intervention needed." |

**6. Safety Rules**:
- NEVER force-push or rewrite history
- NEVER dismiss reviews or override branch protection
- NEVER merge the PR automatically (leave that to the human)
- NEVER modify files unrelated to the PR's changeset
- All commits use descriptive messages
- Max 5 fix-push cycles per session
- ALWAYS `pkill -f vitest 2>/dev/null` after any local test runs

**Override**: `--no-babysit` to skip, `--babysit` to force even on default branch
