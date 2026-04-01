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

**CSP Lesson (DocuSeal)**: Third-party embeds often load assets from CDNs/cloud storage, not their main domain. Trace actual resource URLs in browser network tab. DocuSeal serves document images from `*.s3.amazonaws.com`, not `docuseal.com`.

**1b. CSP Third-Party Domain Audit (BLOCKING)**:

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
- If no risky changes: Skip directly to Phase 2
