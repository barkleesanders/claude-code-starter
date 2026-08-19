# Infrastructure, Admin & Verification

Covers Phase 1.45 (third-party config, XSS, auth guards, infra protection), Phase 1.46 (admin-user sync verification), and Phase 1.5 (deployment verification for risky changes).

---

## Phase 1.45: THIRD-PARTY CONFIG, ERROR HANDLING & INFRA PROTECTION

**1. Third-Party Integration Config Check**:
```bash
# Verify env vars referenced in worker code exist in wrangler config
grep -rn "env\.\(DOCUSEAL\|CLERK\|STRIPE\|RESEND\)" src/worker/ --include="*.ts" 2>/dev/null | \
  grep -oP 'env\.\K[A-Z_]+' | sort -u | while read VAR; do
    if ! grep -q "\"$VAR\"" wrangler.json 2>/dev/null; then
      echo "WARNING: $VAR used in worker code but not in wrangler.json"
    fi
  done

# Verify all required env vars are set (vars + secrets combined)
npx wrangler secret list 2>/dev/null | grep -oP '"name":\s*"\K[^"]+' > /tmp/secrets.txt
grep -oP '"[A-Z_]+":\s*"[^"]+"' wrangler.json | grep -oP '"[A-Z_]+' | tr -d '"' >> /tmp/secrets.txt
for REQUIRED in DOCUSEAL_API_KEY DOCUSEAL_TEMPLATE_ID CLERK_SECRET_KEY; do
  if ! grep -q "$REQUIRED" /tmp/secrets.txt; then
    echo "CRITICAL: $REQUIRED missing from both wrangler.json and secrets!"
  fi
done
```
- If critical env vars missing from both wrangler.json and secrets: **BLOCK**

**1a. Worker Secret Binding Gate (BLOCKING)**:

Cloudflare Worker `vars` are plaintext config. Any binding name that looks sensitive must be a secret binding, not a literal in `wrangler.json`/`wrangler.toml`.

```bash
# List sensitive plaintext vars in Wrangler config. Every hit needs review.
rg -n '"[A-Z0-9_]*(KEY|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*"\s*:' wrangler.json wrangler.toml 2>/dev/null

# Confirm Cloudflare stores the binding as secret_text.
npx wrangler secret list
```

- If a sensitive binding appears as a plaintext `vars` value: **BLOCK**
- If `wrangler secret put <NAME>` fails because the binding name is already in use: remove the plaintext var from config, deploy without `--keep-vars`, immediately run `wrangler secret put <NAME>`, then re-run `wrangler secret list`
- Do not use `--keep-vars` when the purpose is removing plaintext Worker vars; it preserves the old plaintext binding
- The safe end state is `wrangler secret list` showing the binding as `secret_text` and no sensitive literal left in Wrangler config

**1b. Production Auth Instance Binding Gate (BLOCKING)**:

Run this for Cloudflare Worker apps that use Clerk/Auth0/Supabase/Firebase or any auth provider with dev/prod instances.

**AIVA override (current architecture, August 2026):** AIVA uses first-party Better Auth at `/api/auth/*`; Clerk is retired. Do not require a Clerk custom domain or `pk_live_*`. For AIVA, block on **any** Clerk host/key/SDK/JWKS fingerprint in source, dry-run, live HTML, or CSP, then require `GET /api/auth/ok` → 200 and a wrong-password `POST /api/auth/sign-in/email` → 401. If auth/session/passkey/TOTP/password/recovery/sign-out code changed, also run `~/.claude/skills/shared/account-security-lifecycle.md`.

```bash
# Source/config scan for development auth fingerprints
rg -n 'pk_test_|sk_test_|\.accounts\.dev|CLERK_PUBLISHABLE_KEY|CLERK_JWT_ISSUER|CLERK_JWKS_URL' \
  wrangler.toml wrangler.json src --glob '!*.test.*' 2>/dev/null || true

# Effective Worker upload scan. This must be clean before production deploy.
if [ -f wrangler.toml ] || [ -f wrangler.json ]; then
  npx wrangler deploy --env="" --dry-run --outdir /tmp/ship-worker-dryrun 2>&1 | tee /tmp/ship-worker-dryrun.log
  rg 'CLERK_PUBLISHABLE_KEY.*pk_test|CLERK_JWT_ISSUER.*accounts\.dev|CLERK_JWKS_URL.*accounts\.dev|pk_test_|sk_test_' \
    /tmp/ship-worker-dryrun.log && echo "BLOCK: production Worker dry-run contains development auth fingerprint"
fi
```

- If static scan or dry-run shows `pk_test_*`, `sk_test_*`, `.accounts.dev`, or a dev issuer/JWKS in production mode: **BLOCK**
- If using Clerk production custom domains, verify Clerk Platform domain status is complete before switching to `pk_live_*`:

```bash
clerk apps list --json
clerk api --platform "/platform/applications/<app_id>/domains/<domain>/status"
curl -sI -m 8 "https://clerk.<root>/v1/environment" | head -1
```

- If Clerk domain DNS/SSL/mail status is incomplete, or `/v1/environment` cannot return 200 for the production domain: **BLOCK**
- After deploy, fetch live HTML with a cache-buster and verify it contains prod auth fingerprints only:

```bash
curl -s "https://${PROD_DOMAIN}/?ship_cb=$(date +%s)" | rg 'pk_live_|pk_test_|accounts\.dev'
```

**1c. External Municipal Form Fallback Gate (BLOCKING when touched)**:

Trigger this when changes touch files containing `sf311`, `verint`, `seeclickfix`, `request_type_id`, `category`, `resubmit`, `rewrite-text`, `analyze`, or `submit`.

```bash
CHANGED=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only)
if echo "$CHANGED" | rg -i 'sf311|verint|seeclickfix|request_type_id|categor|resubmit|rewrite-text|analyze|submit'; then
  echo "Municipal submit/category code changed: require targeted fallback regression"
  rg -n 'sf311_category_fallback|category_fallback|request_type_id|Verint|SF311 save 500' src tests
fi
```

Required verification:
- A targeted test covers non-default city form/category returning 500.
- The same test proves fallback to a known-good form/category succeeds.
- The fallback preserves the user-selected category in description and/or telemetry.
- Live/post-deploy verification checks the official city tracker when a live ticket is filed.

If municipal submit/category code changed and no fallback regression exists: **BLOCK**.

**1c-bis. Third-Party Response Signal-Extraction Fixture Gate (BLOCKING when touched)**:

Trigger when changes touch ANY parser that classifies a third-party HTTP response as success / failure / pending / partial — i.e., a function whose return type narrows on the response body. Common offenders: ASP.NET WebForms replays (DBI, SF Permit Center), Verint dform `/api/save` interpreters, OAuth-callback decoders, webhook verifiers, scraper detectors.

```bash
CHANGED=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only)
TRIPS=0
for f in $CHANGED; do
  case "$f" in *.ts|*.tsx|*.mjs|*.js)
    # File looks like a third-party-response parser if it contains BOTH a return-shape with ok/error AND substring-matching on a fetched response.
    if rg -q 'ok:\s*(true|false)' "$f" 2>/dev/null && rg -q 'await.*\.(text|json)\s*\(\)|response\.text|html\.includes|html\.match' "$f" 2>/dev/null; then
      base=$(basename "$f" | sed 's/\.[a-z]*$//')
      # Look for adjacent fixtures. Common shapes:
      #   src/__fixtures__/<integration>/...-success.{html,json}
      #   tests/fixtures/<integration>/...
      #   __fixtures__/<base>/
      if ! ls src/__fixtures__/ tests/fixtures/ __fixtures__/ 2>/dev/null | grep -q .; then
        echo "BLOCK: $f looks like a third-party-response parser but no __fixtures__/ directory exists"
        TRIPS=$((TRIPS+1))
        continue
      fi
      # Require BOTH success and failure fixtures named for this integration.
      if ! find src/__fixtures__ tests/fixtures __fixtures__ -type f 2>/dev/null | rg -q -i 'success|recorded|ok\.' ; then
        echo "BLOCK: $f changed but no captured *-success.* fixture found anywhere under __fixtures__/"
        TRIPS=$((TRIPS+1))
      fi
      if ! find src/__fixtures__ tests/fixtures __fixtures__ -type f 2>/dev/null | rg -q -i 'failure|reject|validation|error\.' ; then
        echo "BLOCK: $f changed but no captured *-failure.* fixture found anywhere under __fixtures__/"
        TRIPS=$((TRIPS+1))
      fi
      # Verify the test imports / readFileSync's at least one fixture, not just hand-written HTML.
      test_f="${f%.ts}.test.ts"
      if [ -f "$test_f" ] && ! rg -q 'readFileSync.*__fixtures__|import.*__fixtures__|loadFixture' "$test_f"; then
        echo "BLOCK: $test_f exists but doesn't load any __fixtures__/ — synthetic-only tests can't catch heuristic drift"
        TRIPS=$((TRIPS+1))
      fi
    fi
  ;; esac
done
[ "$TRIPS" -gt 0 ] && echo "BLOCK: $TRIPS signal-extraction fixture violations — see ~/.claude/skills/shared/third-party-signal-fixtures.md"
```

Required to clear this gate:
- For every modified file that parses a third-party response into `{ok, ...}`, there is at least one captured **real success** response and one captured **real failure** response in `__fixtures__/`.
- A live-traffic probe under `tools/repro/<integration>-probe.{sh,mjs,py}` is checked in so the next agent can re-capture when the upstream drifts.
- The test file `readFileSync`s the fixture or `import`s it — synthetic hand-written HTML alone is rejected.
- The detector's distinguishing feature (anchored DOM id, JSON field, status code combination) is present in exactly one of the two fixtures, verified by `grep`.

Reference incident (2026-05-27): every IBA-submitted SF DBI complaint was reported as `validation` error for ~10 days while the city actually recorded every one of them. `src/sfdbi.ts` `looksLikeEchoedForm = html.includes("Sub_Button0") && html.includes("CheckBox1")` matched the real success page too — DBI's "Thank you" response is the SAME `AddressData2.aspx` page with only `<span id="InfoReq1_lblError">` text changed. The pre-existing test used a 100-byte synthetic success fixture (`<html><body><h1>Thank you</h1>...`) that didn't contain `Sub_Button0`, so the bug never tripped in CI. See Pattern #23 (`error-handling-patterns.md`) and `~/.claude/skills/shared/third-party-signal-fixtures.md` for the generalized rule.

**1c-ter. Experience Cloud / Aura 311 catalog + submit envelope (BLOCKING when touched) — Phase 1.45g:**

Trigger when the diff touches Salesforce/Aura 311 catalog JSON, `fetchCaseTypeDetails` parse, `submitCase` / `addressDetails` / `sObjCase`, `captureFailure`, or the KV catalog cache key (`la311:catalog:`). Full class: Pattern #36.

```bash
CHANGED=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only)
if echo "$CHANGED" | rg -i 'myla311|auraGuest|fetchCaseTypeDetails|submitCase|addressDetails|sObjCase|captureFailure|la311:catalog|classifyCaseType|submitGate'; then
  echo "Aura 311 catalog/envelope changed: require Pattern 36 structural tests"
  rg -n 'toastPayload|objCaseConfigWrapper|captureFailure|caseConfigId|Permit_Number__c|unwrapLocator' src tests
fi
```

BLOCK until:
- A toast/`validateAddress` fixture unwraps to locator keys (`address`/`location`), **not** `toastPayload`. Prove with `gron fixture.json | rg 'toastPayload|response.address'` (toast-only = fail) or a `hurl --test` jsonpath assert.
- Every id-bearing type has `caseConfigId`+`sCaseType` **or** explicit `captureFailure`. 0 dummy `modelFlags`.
- Refuse strings name official field API names, not class stubs.
- Catalog schema change bumped the KV cache key.
- Post-deploy: cache-busted `GET /api/categories` matches those counts. `hurl --test` is a valid structural-test form.

`/carmack` must not have been the deployer — this gate runs only under `/ship`.

**CSP Lesson (DocuSeal)**: Third-party embeds often load assets from CDNs/cloud storage, not their main domain. Trace actual resource URLs in browser network tab. DocuSeal serves document images from `*.s3.amazonaws.com`, not `docuseal.com`.

**1c. CSP Third-Party Domain Audit (BLOCKING)**:

Third-party services (Clerk, Brevo, DocuSeal, etc.) load images, scripts, and fonts from CDN domains that differ from their API domains. If these CDN domains aren't in the CSP, assets silently fail to load — resulting in broken icons, missing images, or invisible UI elements with no console errors.

```bash
# Cross-reference: for each third-party used, verify ALL their asset domains are in CSP
CSP_FILE="src/worker/middleware/securityHeaders.ts"

# Clerk: needs img.clerk.com for social provider icons (Google, Apple logos)
grep -q "img.clerk.com" "$CSP_FILE" || echo "BLOCK: img-src missing https://img.clerk.com (social login icons will be broken)"
grep -q "clerk-telemetry" "$CSP_FILE" || echo "WARN: connect-src missing https://*.clerk-telemetry.com (Clerk telemetry blocked)"

# Brevo: needs cdn.brevo.com for widget assets
grep -q "cdn.brevo.com" "$CSP_FILE" || echo "BLOCK: script-src missing https://cdn.brevo.com"

# DocuSeal: needs *.s3.amazonaws.com for document images
grep -q "s3.amazonaws.com" "$CSP_FILE" || echo "BLOCK: img-src missing https://*.s3.amazonaws.com (DocuSeal document images)"

# Facebook: needs both www.facebook.com (img pixel) and connect.facebook.net (script)
grep -q "www.facebook.com" "$CSP_FILE" || echo "BLOCK: img-src missing https://www.facebook.com (Meta Pixel)"
grep -q "connect.facebook.net" "$CSP_FILE" || echo "BLOCK: script-src missing https://connect.facebook.net"

# Google: needs googletagmanager.com for GA4
grep -q "googletagmanager.com" "$CSP_FILE" || echo "BLOCK: script-src missing https://www.googletagmanager.com"
```
- If ANY third-party asset domain is missing from CSP: **BLOCK** — assets silently fail with no console errors
- **Rule**: When adding a new third-party service, always check which CDN domains it loads assets from (img, script, style, font, connect) and add ALL of them to the CSP

**2. Admin Auth Parity Check (Cloudflare Workers / Hono)**:
```bash
# Find custom requireAdmin functions in route files
grep -rn "function requireAdmin" src/worker/routes/ --include="*.ts"

# Check if any are synchronous (sync = metadata-only = blocks DB-based admin)
# A synchronous requireAdmin has no "await" inside its body
grep -A10 "function requireAdmin" src/worker/routes/*.ts 2>/dev/null | grep -v "async" | grep "publicMetadata"

# Verify all call sites await
grep -rn "requireAdmin(c)" src/worker/routes/ --include="*.ts" | grep -v "await "
```
- If `requireAdmin` is synchronous (no `async`, no `await c.env.DB`): **BLOCK** — production admin uses DB `is_admin=1`, not Clerk metadata
- If any call site is missing `await`: **BLOCK** — returns a Promise<user> instead of user, auth check never runs

**3. Catch-All Error Handling Check**:
```bash
# Find catch blocks returning generic errors (masks real failure source)
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/worker/ | grep -A5 "return.*json.*error"
# Find large try-catch blocks
grep -n "} catch" --include="*.ts" -r src/worker/middleware/ src/worker/index.ts
```
- If single catch wraps both auth AND service calls: WARN — should be split

**4. XSS via innerHTML / dangerouslySetInnerHTML Check**:
```bash
# IMPORTANT: Search ALL .tsx/.ts files, not just src/ — entry points like index.tsx
# sit at project root and are a common blind spot for XSS

# Find raw innerHTML assignments (non-React, often in entry points/overlays)
grep -rn "\.innerHTML\s*=" --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist
# For each hit: verify data is escaped via escapeHtml() or equivalent

# Find all dangerouslySetInnerHTML usage (React components)
grep -rn "dangerouslySetInnerHTML" --include="*.tsx" . | grep -v node_modules | grep -v dist
# For each hit, verify sanitization exists (DOMPurify, not regex)
grep -B20 "dangerouslySetInnerHTML" --include="*.tsx" . | grep -v node_modules | grep "DOMPurify"
```
- If raw `innerHTML` assignment without `escapeHtml()`: **BLOCK** — XSS risk (especially in error overlays, loading screens, and entry points that run before React mounts)
- If `dangerouslySetInnerHTML` without DOMPurify in same file: **BLOCK** — XSS risk
- Regex-based sanitizers are NOT sufficient — require DOMPurify as defense-in-depth

**5. JSON-LD Script Tag Breakout Check**:
```bash
# Find JSON inside <script> tags via dangerouslySetInnerHTML
grep -B5 "dangerouslySetInnerHTML" --include="*.tsx" . | grep -v node_modules | grep -E "script|json-ld|structured"
# Verify JSON.stringify output is escaped
grep -A2 "JSON.stringify" --include="*.tsx" . | grep -v node_modules | grep "replace.*<\|\\\\u003c"
```
- If `JSON.stringify` in `<script>` without `</` escaping: **BLOCK** — script breakout risk

**6. Frontend Auth Guard Check**:
```bash
# Find routes in App.tsx without auth guards
grep -A3 "element=" --include="*.tsx" src/react-app/App.tsx | grep -v "ProtectedRoute\|AdminRoute\|SignIn\|SignUp\|Welcome\|NotFound\|FAQ\|Privacy\|Terms\|service\|open-browser\|useEffect.*isAuthenticated"
# Protected pages must have auth redirect
grep -rn "secureFetch\|secureFetchJson" --include="*.tsx" src/react-app/pages/ | grep -oP '[^/]+\.tsx' | sort -u | while read page; do
  if ! grep -q "isAuthenticated\|ProtectedRoute\|requireAuth" "src/react-app/pages/$page" 2>/dev/null; then
    echo "WARNING: $page calls secure API but has no frontend auth guard"
  fi
done
```
- If page calls `secureFetch` but has no auth guard or redirect: WARN — degraded UX for unauthenticated users

**7. Double-Click Protection Check (Async Buttons)**:
```bash
# Find async onClick without disabled state
grep -rn "onClick.*async\|onClick.*void" --include="*.tsx" src/react-app/ | grep -v "disabled="
```
- If async onClick without `disabled` state on same element: WARN — double-click causes duplicate requests

**8. Admin Route Error Code Check**:
```bash
# Admin route handlers should throw HTTPException(403), not Error
grep -rn "throw new Error.*admin\|throw new Error.*Admin" --include="*.ts" src/worker/
# requireAdmin should use HTTPException
grep -A5 "function requireAdmin" --include="*.ts" src/worker/ | grep "throw"
```
- If admin check throws plain `Error` instead of `HTTPException(403)`: WARN — returns 500 instead of 403

**3. Infrastructure Destruction Prevention**:

**AI agents MUST NEVER autonomously execute destructive infrastructure commands.**

BLOCKED commands (NEVER execute without explicit human confirmation):
```bash
# Terraform
terraform destroy                    # BLOCKED
terraform apply -auto-approve        # BLOCKED
terraform state rm                   # BLOCKED

# AWS CLI
aws rds delete-db-instance           # BLOCKED
aws ec2 terminate-instances          # BLOCKED
aws s3 rb / aws s3 rm --recursive    # BLOCKED
aws cloudformation delete-stack      # BLOCKED

# GCP
gcloud sql instances delete          # BLOCKED
gcloud compute instances delete      # BLOCKED
gcloud container clusters delete     # BLOCKED

# Generic
DROP TABLE / DROP DATABASE           # BLOCKED without confirmation
```

Required protocol:
1. ALWAYS run `terraform plan` first — show output to user
2. NEVER run `terraform apply` without user reviewing the plan
3. If plan shows >0 resources to destroy, STOP and ask
4. NEVER modify or replace .tfstate files
5. NEVER run `terraform destroy` — ask the user to run it themselves

---

## Phase 1.46: ADMIN-USER SYNC VERIFICATION (BLOCKING)

**Purpose**: Detect admin-to-user data sync gaps that cause the "admin marks something but user doesn't see it" class of bugs. Runs automatically when changes touch admin endpoints, user-facing hooks, or shared data models.

**Trigger**: Auto-detect if staged changes touch any of:
- `src/worker/` files with "admin" in path or containing admin route handlers
- `src/react-app/hooks/` (data fetching hooks)
- `src/react-app/pages/Dashboard` or `src/react-app/pages/Admin`
- Database migration files

If none of the above are touched, skip to Phase 1.5.

### Check 1: Admin Write Endpoints Must Clean Up Related Fields
```bash
# Find admin UPDATE statements that set status but don't handle dependent fields
grep -A3 "UPDATE.*SET.*status" --include="*.ts" -r src/worker/ | grep -v "flag_message\|notes\|reason\|NULL"
```
- If admin status-change UPDATE doesn't handle dependent fields: **WARN** — stale data may show on user side

### Check 2: User Data Hooks Must Have Background Refresh
```bash
# List all custom hooks that call secureFetch/fetch for user data
HOOKS=$(grep -l "secureFetch\|fetch(" --include="*.ts" src/react-app/hooks/ 2>/dev/null)
for hook in $HOOKS; do
  HOOKNAME=$(basename "$hook")
  HAS_VISIBILITY=$(grep -c "visibilitychange" "$hook" 2>/dev/null || echo 0)
  HAS_POLLING=$(grep -c "setInterval\|useInterval" "$hook" 2>/dev/null || echo 0)
  if [ "$HAS_VISIBILITY" = "0" ] && [ "$HAS_POLLING" = "0" ]; then
    echo "WARN: $HOOKNAME has no background refresh (no visibilitychange or polling)"
  fi
done
```
- If any user data hook lacks background refresh: **WARN** — admin changes invisible until manual reload

### Check 3: Silent Refetch Must Not Trigger Loading Spinner
```bash
# Find visibility/polling refetch that calls the main fetch (which sets isLoading=true)
for hook in $(grep -l "visibilitychange" --include="*.ts" src/react-app/hooks/ 2>/dev/null); do
  HOOKNAME=$(basename "$hook")
  # Check if visibility handler calls the spinner-triggering fetch vs a silent version
  VISIBILITY_CALLS=$(grep -A5 "visibilitychange" "$hook" | grep -o "[a-zA-Z]*[Ff]etch[a-zA-Z]*" | head -1)
  if echo "$VISIBILITY_CALLS" | grep -qv "silent\|Silent\|quiet\|background"; then
    # Check if that function sets isLoading
    if grep -A10 "const $VISIBILITY_CALLS" "$hook" | grep -q "setIsLoading(true)\|setLoading(true)"; then
      echo "BLOCK: $HOOKNAME visibility refetch triggers loading spinner (will flash on tab switch)"
    fi
  fi
done
```
- If visibility refetch triggers spinner: **BLOCK** — full-screen flash every time user switches tabs

### Check 4: Optimistic Updates Must Re-Sync
```bash
# Find optimistic updates in admin pages
grep -B2 -A20 "Optimistic update\|optimistic" --include="*.tsx" -r src/react-app/pages/Admin 2>/dev/null | \
  grep -c "fetchClientData\|refetch\|fetchData" || echo "0"
```
- If optimistic update block has no fetchData call after success: **WARN** — server-computed side effects lost

### Check 5: URL-Persisted State Must Auto-Advance
```bash
# Find useEffect guards that skip recalculation when state is already set
grep -B2 -A8 "=== null" --include="*.tsx" -r src/react-app/pages/ | \
  grep -B5 "activeStep\|activeIndex\|currentStep\|activeTab" | \
  grep "useEffect\|return;"
```
- If useEffect only initializes when state is null but data can change externally: **WARN** — stale navigation

### Check 6: Admin Write Audit Actions Match Operation
```bash
# Find write endpoints using view/read audit actions
grep -B15 "AuditActions" --include="*.ts" -r src/worker/ | \
  grep -B15 "ADMIN_VIEW\|VIEW_CLIENT\|VIEW_CASE" | \
  grep "put\|post\|delete\|PUT\|POST\|DELETE\|update\|create" 2>/dev/null
```
- If write endpoint uses a "VIEW" audit action: **WARN** — audit trail is misleading

### Decision Logic
- **If any BLOCK found**: Fix inline before continuing
- **If only WARNs**: Display all warnings, continue (not a deploy blocker but should be fixed)
- **If clean**: Display "Admin-user sync: all checks passed" and continue

---

## Phase 1.5: DEPLOYMENT VERIFICATION (CONDITIONAL)

**Auto-detect risky changes** by scanning staged changes for:
- Database migrations
- Backfill scripts
- Destructive keywords (migration, backfill, drop table, delete from)

**If risky changes detected**, generate comprehensive Go/No-Go checklist:

1. **Define Data Invariants** - Specific conditions that must remain true
2. **Pre-Deploy Audit Queries (SQL - Read-Only)** - Baseline counts and checks
3. **Migration/Backfill Steps** - Step-by-step with estimated runtime and rollback
4. **Post-Deploy Verification Queries** - Run within 5 minutes
5. **Rollback Plan** - Can we roll back? Steps? Data restoration?
6. **24-Hour Monitoring Plan** - Time-based actions and alert conditions

- Require explicit [CONFIRM CHECKLIST] to proceed
- Store checklist for Phase 5 monitoring reminders
- If no risky changes: Skip directly to Phase 1.55

---

## Phase 1.55: HOT-PATH DATA-VOLUME & CACHE-TOPOLOGY GATE (BLOCKING when route handlers, crons, or caches changed)

**Fires when the changeset touches:** any HTTP route handler, a `scheduled()` / cron body, a cache read (`KV.get`, `caches.match`, `readCached*`), a cache write/warm (`KV.put`, `caches.put`, `prewarm*`, `writeCached*`), or any SQL/D1 query. Skip only if the change is purely internal CLI / docs / tests with no route/cron/cache/query in the diff.

**Why this gate exists (2026-05-12 incident):** `improvebayarea.com/dashboard/<city>` ran `coverageForCity()` — `SELECT MIN,MAX,COUNT(*),SUM(...) FROM reports WHERE city_id=?` — UNCONDITIONALLY before every render, just for a footer line + a path-decision gate. For San Francisco that `WHERE` matched **8,603,743 rows**; measured live: **7,970 ms / 8.6M rows_read per request**. Separately, the hourly "transparency cache" cron warmed `refreshCityReports`'s raw-rows KV keys — but the route reads `agg:<city>:<window>` first, which nothing warmed → every request paid a live ~8-statement D1 batch. Two distinct design bugs, both invisible to tsc/biome/tests. The fix took three round trips that this gate would have collapsed to zero.

### Check A — Unbounded per-request work
For every query/`fetch` that runs **before the response is sent** on a changed (or changed-cache-feeding) route:
1. Is it bounded? — has a `LIMIT`, an indexed range scan, or a fixed-cardinality `GROUP BY` (≤ a few hundred buckets). OR is it served from a cache (KV/edge) with the live query only on a cold miss?
2. If it's a `COUNT(*)` / `SUM(CASE...)` / `ORDER BY x LIMIT 1 OFFSET N/2` / any whole-partition aggregate over a `WHERE <partition_key> = ?` that can match a large/growing set — **measure it**:
   ```bash
   npx wrangler d1 execute <DB> --remote --json --command "<the exact query with a real param>" \
     | python3 -c "import sys,json; r=json.load(sys.stdin)[0]; print('duration_ms:', r['meta']['duration'], 'rows_read:', r['meta']['rows_read'])"
   ```
   **BLOCK if `rows_read` > ~100,000 on a per-request path.** Fix: cache the result (it's a slow-changing aggregate), or drop it, or scope it to the window.
3. **Run-before-cache-check trap:** if the route does `const x = await expensiveThing(); ... const cached = await readCache(); if (cached) return render(cached, x);` — `expensiveThing()` runs even on a cache HIT. Either fold its output into the cached payload, or move it after the cache check, or cache it separately.

### Check B — Cache topology (reader ↔ writer must match)
1. For every `readCached*` / `KV.get(key)` / `caches.match(url)` introduced or in the changed route — `grep` the codebase for who **writes** that exact key/URL. If nothing writes it (or only an out-of-band manual script does, with no cron), it's a permanent cache MISS in production → the route always pays the cold path. **BLOCK.**
2. For every `prewarm*` / cache-warming cron step — `grep` for who **reads** the keys it writes. A warmer that warms keys nothing reads (or warms a *different* key shape than the route reads — `oak311:open_data:...` vs `agg:...`) is dead work and a latent perf bug. **BLOCK.**
3. Cache-warmer must run **after** the data it depends on lands (e.g. `prewarmAggregates` after `fetchDelta`, not before/in-parallel).
4. Cron-written cache keys get a TTL (self-heals a broken cron); manually-seeded keys that the cron must not clobber stay TTL-less and on a disjoint key space.

### Check C — Lagged-source trailing windows
If a changed query filters `WHERE ts >= now() - <interval>` against a source that publishes with a lag (DataSF/Socrata, batch ETL, anything not real-time), the trailing-N window can be **empty by construction**. Anchor on `MAX(ts)` instead (`WHERE ts >= (SELECT MAX(ts) ... ) - <interval>`) and label it honestly ("latest N of *published* data"). Verify against the live source's `MAX(ts)`.

### Check D — TEXT timestamp index sanity
If a query does a range scan on a TEXT `created_at`/`ts` column, confirm the stored format and the comparison literal sort lexically the same (e.g. both ISO-with-`Z`, or both floating-no-`Z`). A mismatch (`'2026-05-04T12:00:00.000'` stored vs `'2026-05-04T12:00:00.123Z'` queried) either returns wrong rows or defeats the index. `EXPLAIN QUERY PLAN` should show `USING INDEX`, not `SCAN`.

**Output:** if any check BLOCKs, fix inline before Phase 2 (it's a perf/correctness bug, not a nit). If all pass, one line: `-- Phase 1.55 OK: N route(s)/cron(s)/cache(s) audited, max rows_read=<n>, cache topology consistent --`.

---

## Phase 1.56: D1 SCHEMA-DRIFT / MIGRATION-APPLIED-TO-PROD GATE (BLOCKING when a D1 write column set or a migration file changed)

**Fires when** the diff touches any D1 `INSERT INTO`/`UPDATE … SET`/`SELECT` column set, adds/edits a `migrations/*.sql` file, or references a new column/table. Skip only for diffs with no D1 write or migration change.

**Why (2026-07-05 reference incident):** AIVA `POST /api/intake` 500'd for *every* user. The worker code + Zod schema referenced `mos`, `migrations/25_add_mos_to_intake.sql` existed in the repo, but the column was **never applied to the remote D1** (the team applied later migrations ad-hoc via direct `execute`; the `d1_migrations` tracker only recorded 1–9). The write threw `D1_ERROR: no such column: mos`, surfaced only as Hono's generic "Internal Server Error" with no server log. **A migration FILE existing — and the LOCAL D1 having the column — are NOT proof the column is in prod. Only the remote `PRAGMA table_info` is.**

**Run the automated gate (it does both checks):**
```bash
~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo-dir> [<d1-name-or-id>]
# exit 0 = clean · 1 = drift (BLOCK) · 2 = setup error
```

- **Check A — tracker clean:** `wrangler d1 migrations list --remote` must say "No migrations to apply". Unapplied entries = drift (genuinely un-run, or a stale tracker that will re-run on the next `apply`).
- **Check B — columns exist in prod:** every column in a changed `INSERT INTO t (…)` / `UPDATE t SET …` must appear in that table's remote `PRAGMA table_info`. A code-column-not-in-prod is exactly the outage above → the script exits 1 naming the table + column.

**BLOCK and fix BEFORE the code deploys:**
1. Apply ONLY the genuinely-missing DDL to remote, additively: `ALTER TABLE t ADD COLUMN c …` / `CREATE TABLE IF NOT EXISTS …`. Confirm with `PRAGMA table_info(t)` on `--remote`.
2. Reconcile the tracker so a future `apply` skips it: `INSERT OR IGNORE INTO d1_migrations (name) VALUES ('<file>.sql');`.
3. **NEVER run `wrangler d1 migrations apply` to catch up a drifted DB.** Migrations authored as non-idempotent data transforms corrupt data on re-run (AIVA `16_add_records_request_step.sql` does `UPDATE steps SET order_index = order_index + 1 WHERE order_index >= 3` — a double-run double-shifts every user's step order); bare `CREATE`/`ALTER` (no `IF NOT EXISTS`) error on existing objects. Diff object-by-object vs remote and apply only what's missing.
4. Confirm the changed write handler wraps its `.run()` in try/catch that logs `sanitizeError(err)` and returns clean JSON (ties to Phase 1.57) — so the next drift is diagnosable, not a silent generic 500.

Full pattern (detect + fix + instrument): `~/.claude/skills/shared/d1-schema-drift.md`.

**Output:** BLOCK if the script exits non-zero; fix prod schema + reconcile inline, re-run until it exits 0. On pass: `-- Phase 1.56 OK: D1 schema in sync — N write-target table(s) verified vs remote PRAGMA, migrations tracker clean --`.
