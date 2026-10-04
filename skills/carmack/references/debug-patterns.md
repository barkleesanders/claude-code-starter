# Debug Patterns & React Checks

## 5-Phase Workflow

1. **Root Cause Investigation** -- Gather evidence, no assumptions
2. **Pattern Analysis** -- Find similar issues, related code
3. **Hypothesis & Testing** -- Form and test theories
4. **Implementation & Verification** -- Fix with approval checkpoint; offer `/codex:review --wait` before presenting fix
5. **Session Persistence** -- Save state for resumability

## Code Search Tools

### ogrep -- Semantic Code Search
Use `ogrep` for AST-aware code search by meaning. Always index before first search in a project.
```bash
ogrep index .                          # Build index (first time)
ogrep query "where is auth handled"    # Semantic search
ogrep query "error handling" --mode fulltext  # Keyword search (no embeddings needed)
ogrep query "database connection" -n 10      # More results
ogrep chunk <ref> --context 5          # Get chunk with surrounding context
```

### qmd -- Knowledge & Documentation Search
Use `qmd` for searching docs, notes, and markdown knowledge bases (fully local, no API keys).
```bash
qmd collection add ~/project/docs --name docs   # Add docs collection
qmd embed                                        # Build embeddings (auto-downloads models)
qmd query "how does authentication work"         # Hybrid search with reranking
qmd search "env validation"                      # BM25 keyword search
qmd vsearch "startup failure"                    # Vector similarity search
```

### bd -- Task Tracking
Use `bd` (beads) for structured task tracking with dependency graphs.
```bash
bd create "Investigate auth timeout" -p 1   # Create priority-1 task
bd list                                      # Show all tasks
bd ready                                     # Show unblocked tasks
bd update <id> --claim                       # Claim a task
bd done <id>                                 # Complete a task
bd dep add <child> <parent>                  # Add dependency
```

## TEST SAFETY RULES (CRITICAL)

Vitest fork workers leak ~5GB memory each when they hang. These rules prevent system resource exhaustion:

1. **ALWAYS use timeout**: `timeout 120 npx vitest run src/specific/test.ts 2>&1`
2. **NEVER run full test suite**: Always target specific test files
3. **Maximum 3 test runs per phase**: Stop and diagnose if tests keep failing/hanging
4. **Clean up after tests**: `pgrep -f vitest | xargs kill 2>/dev/null`
5. **NEVER run `npm test` without timeout** -- vitest workers hang and consume all RAM

### Forbidden Test Patterns
```bash
# WILL LEAK MEMORY -- no timeout, full suite
npm test
npx vitest run
npx vitest run --reporter=verbose

# CORRECT -- timeout + specific file
timeout 120 npx vitest run src/worker/utils/sanitizer.test.ts 2>&1
```

## Debugging Anti-Patterns (Lessons from Real Incidents)

### Anti-Pattern: Chasing Symptoms Instead of Tracing the Pipeline

**Signal**: You're fixing missing things one-by-one and each fix reveals another missing thing.

```
❌ See "Cannot find module 'X'" → install X → "Cannot find module 'Y'" → install Y → repeat 10x
✅ Ask: "WHY are all these modules missing?" → trace the install pipeline → find the broken step
```

**The `file` command is your best friend.** When a tool fails with unexpected parse errors, check if the file it's loading is actually the type it expects:
```bash
file /path/to/suspicious-file.js
# Expected: "Node.js script executable" or "ASCII text"
# Bug: "POSIX shell script" — the file isn't what its extension claims
```

**Real case (2026-04-06):** OpenClaw broke after every npm update. Spent 30 minutes installing missing packages one-by-one. The real cause: `npm-cli.js` was a shell script (not JavaScript). One `file` command would have found it in 2 seconds.

### Anti-Pattern: Trusting Exit Code 0

A command returning exit 0 doesn't mean it worked correctly. Non-fatal error handlers mask failures:

```
❌ `npm install -g pkg` exits 0 → assume pkg is fully installed
✅ `npm install -g pkg` exits 0 → verify postinstall ran → verify expected node_modules exist
```

**Rule**: After installing anything with a postinstall step, verify the OUTCOME not just the exit code. Check if the expected files/modules actually exist.

### Anti-Pattern: Treating External Form 500s as Global Submit Failure

City and vendor form platforms often route by a combined department/category id. A category change can move the request onto a different form handler even when the URL, auth/session, photo, address, and general payload shape look the same.

```
Wrong: SF311 save 500 after AI category rewrite -> change auth/photo upload/retry logic
Right: Probe failing request_type_id and known-good request_type_id through the same first-party save path
```

Debug protocol:
1. Capture the exact category/form id selected after AI/manual changes.
2. Reproduce the failing category with the same photo/address/description/session.
3. Reproduce a known-good category with the same payload shape.
4. If only the non-default category hard-500s, implement a category fallback that preserves the user's intended category in description/telemetry.
5. Add a regression test that mocks failing category 500 -> known-good fallback success.

Real case (2026-05-09): ImproveBayArea SF311 resubmit failed after "Improve with AI" selected alternate SF categories. Verint hard-500ed those form saves, while the proven street-cleaning form worked. The fix was category-specific fallback plus telemetry, not auth or photo rewrites.

### Anti-Pattern: Probing with Curl Defaults Against Browser-Gated Code

curl's default `Accept: */*` is NOT what browsers send. Any middleware that gates on `accept.includes("text/html")` will SKIP your curl probe and you'll mistakenly conclude the middleware is broken.

```
❌ `curl -sI https://site.com/` → middleware skips → "cookie not set, code is broken"
✅ `curl -sI -H "Accept: text/html,application/xhtml+xml,*/*;q=0.8" \
     -A "Mozilla/5.0 ... Chrome/147.0.0.0" https://site.com/`
```

**Rule**: When debugging server-side cookie/header behavior gated on Accept or User-Agent, use a real-browser-shaped request. Default curl is a different traffic class than browser traffic.

### Anti-Pattern: "Cookie missing" without checking for OVERWRITE

In Hono / Express / any framework where middlewares set headers, "Set-Cookie missing" usually means OVERWRITE, not "never set". One Set-Cookie header in the response means another middleware clobbered yours.

```
❌ Set-Cookie missing → my middleware never ran
✅ Check if ANOTHER Set-Cookie is present → if yes, you're being clobbered → use {append: true}
```

Real bug 2026-05-05: `c.header("Set-Cookie", ...)` without `{append: true}` in outer Hono middleware overwrote inner middleware's cookie. ~3h debugging "the cookie isn't being set" when the cookie WAS being set then overwritten in the same response. See `auth-cookies-guide.md` "Server-side cookie not reaching browser".

### Anti-Pattern: Checking Version Instead of Health

```
❌ `<tool> --version` works → tool is healthy
✅ `<tool> --version` works BUT the tool uses plugins → check if plugins actually loaded
```

Version checks only verify the binary runs. They don't verify that extensions, plugins, configs, or runtime dependencies are intact. Always health-check the actual runtime behavior.

### The Toolchain Investigation Rule

When an application's build/install step fails, the bug might be in the TOOLCHAIN, not the application:
1. Check if `npm`/`node`/`pip`/`cargo` themselves are working correctly
2. Check if wrapper scripts have corrupted real entry points
3. Check if helper scripts have side effects on system binaries
4. Use `file`, `which`, and `readlink -f` to verify tool identity

---

## Hot-Path Data-Volume & Cache-Topology Audit

**Run this whenever** you touch an HTTP route handler, a `scheduled()`/cron body, a cache (read or write/warm), or a SQL/D1 query — in debug mode (diagnosing slowness), feature mode (you're adding a route/cron/cache), or review mode. It catches the class of design bug that tsc/biome/tests can't see: a hot path doing whole-table work, a cache nobody warms, a cron warming a cache nobody reads.

**Symptom that triggers it:** "why is this page/route so slow?" — seconds not ms, worse on the first hit. Or: a `?w=24h` / "last N days" view renders empty though the data clearly exists wider.

### Check 1 — Unbounded per-request work (MEASURE, don't guess)
List every query / `fetch` that runs **before the response is sent** on the route. Each must be (a) bounded — `LIMIT`, indexed range scan, fixed-cardinality `GROUP BY` (≤ a few hundred buckets) — or (b) served from a cache, with the live query only on a cold miss. For any `COUNT(*)` / `SUM(CASE...)` / `ORDER BY x LIMIT 1 OFFSET N/2` / whole-partition aggregate over `WHERE <partition_key> = ?` where the partition can be large/growing:
```bash
npx wrangler d1 execute <DB> --remote --json --command "<the exact query with a real param>" \
  | python3 -c "import sys,json; r=json.load(sys.stdin)[0]; print('duration_ms:', r['meta']['duration'], 'rows_read:', r['meta']['rows_read'])"
```
**>~100,000 `rows_read` on a per-request path = bug.** (`MIN`/`MAX` over an indexed `(partition_key, ts)` are O(1); `COUNT(*)`/`SUM(...)` scan every index entry for the partition.) Fix: KV-cache the result (it's a slow-changing aggregate — hourly cron writes it, 2h TTL self-heals, route reads KV and falls to D1 only on cold miss + writes back), or fold it into an existing cached payload, or scope it to the window, or drop it. **Per the fix-all rule, fix it even if it predates your change.**

**The run-before-cache-check trap:** `const x = await slow(); const cached = await readCache(); if (cached) return render(cached, x);` — `slow()` runs even on a cache HIT. Move it after the check, fold it into the cached payload, or cache it separately.

### Check 2 — Cache topology (reader ↔ writer must match)
- For every `readCached*` / `KV.get(key)` / `caches.match(url)` in the route: `grep` the codebase for who **writes** that exact key/URL. Nothing writes it (or only an out-of-band manual script, with no cron) → permanent cache MISS in production → the route always pays the cold path.
- For every `prewarm*` / cache-warming cron step: `grep` for who **reads** the keys it writes. A warmer that warms keys nothing reads — or warms a *different key-shape* than the route reads first (`oak311:open_data:<city>:<win>:<status>` vs `agg:<city>:<win>`) — is dead work AND a latent perf bug.
- The cache-warmer must run **after** the data it depends on lands (warm aggregates after the delta import, not before/in parallel).
- Cron-written keys get a TTL (a broken cron self-heals); manually-seeded keys the cron must not clobber stay TTL-less on a disjoint key space.

### Check 3 — Lagged-source trailing windows
`WHERE ts >= now() - <interval>` against a source that publishes with a lag (Socrata/DataSF `requested_datetime`, batch ETL, anything not real-time) can be **empty by construction** for narrow intervals. Anchor on `MAX(ts)`: `WHERE ts >= (SELECT MAX(ts) FROM t WHERE partition_key=?) - <interval>`; label "latest N of *published* data". For real-time sources `MAX(ts) ≈ now()` so it's a no-op — apply it uniformly.

### Check 4 — TEXT-timestamp index sanity
Range scan on a TEXT `ts` column: the stored format and the comparison literal must sort lexically the same (both ISO-with-`Z`, or both floating-no-`Z`). `'2026-05-04T12:00:00.000'` stored vs `'2026-05-04T12:00:00.123Z'` queried → wrong rows or a forced `SCAN`. `EXPLAIN QUERY PLAN` must show `USING INDEX`.

**Reference incident (2026-05-12, improvebayarea.com):** `/dashboard/<city>` ran `coverageForCity()` = `SELECT MIN,MAX,COUNT(*),SUM(...) FROM reports WHERE city_id=?` unconditionally before every render (for a footer line + a path gate). For SF that `WHERE` matched 8,603,743 rows — measured: **7,970 ms / 8.6M rows_read per request**. The hourly cron warmed `refreshCityReports`'s raw-rows KV but the route read `agg:<city>:<window>` first (nothing warmed it → permanent miss → live 8-statement batch every hit). And `?w=24h` rendered empty because it was `now()`-anchored against DataSF's ~1-2-day-lagged `requested_datetime`. Three separate design bugs, all invisible to lint/types/tests, fixed across three round-trips that this audit would have collapsed to one. Now also enforced as ship Phase 1.55.

---

## Reproduction Harnesses

- Builds repro scripts in `tools/repro/`
- Closed-loop execution: create -> run -> verify -> clean up
- Minimal reproduction cases isolating the exact failure

## Debugger & Instrumentation

- Attaches debuggers autonomously (lldb)
- Instruments code without asking for logs
- Takes complete ownership of investigation
- Creates minimal, surgical fixes with regression tests

## React-Specific Checks

### "X is not defined" -- Scope Audit

**#1 production crash cause.** Inner/child component references a variable from parent scope without receiving it as a prop.

#### Step 1: Check Scope
For each use of the undefined variable, verify it's in scope:
- Is it a prop? Check the component's props interface
- Is it local state? Check useState declarations
- Is it imported? Check import statements
- Is it from context? Check useContext usage

#### Step 2: Verify Child Components
- All child/inner components ONLY use: props, local state, imports, context
- Child should NEVER reference parent's local variables directly
- No inline component definitions that close over parent state

#### Step 3: Detection Commands
```bash
# Find the undefined variable in the file
grep -n "<variable_name>" <file>

# Find all nested components (potential scope issues)
grep -n "const.*= (" <file> | grep -v "export"

# Find nullable access without optional chaining
grep -rn "{[a-z][a-zA-Z]*\.[a-z]" --include="*.tsx" | grep -v "\?."
```

#### Step 4: Common Patterns
- Inner component referencing outer component's variables
- Missing prop drilling (parent has data, child needs it)
- useCallback/useMemo referencing variables not in scope

```tsx
// BUG: Inner component references parent's variable
const Parent = ({ data }) => {
  const Inner = () => <div>{data.field}</div>;  // data not in scope!
  return <Inner />;
};

// FIX: Pass as prop
const Inner = ({ data }) => <div>{data.field}</div>;
const Parent = ({ data }) => <Inner data={data} />;
```

#### Step 5: Fix Verification
1. `npm run build` -- Ensure no TypeScript errors
2. `timeout 120 npx vitest run src/path/to/relevant.test.ts` -- Run ONLY related tests with timeout
3. Re-run detection commands to verify no remaining issues

### Silent React Startup Failure

**#2 production crash cause.** React silently fails to mount -- only SSR/SEO fallback HTML visible, zero console errors.

#### Step 1: Confirm Symptoms
- Page loads but `#root` div is empty or contains only SSR fallback HTML
- No errors in console, no network failures
- React never started at all

#### Step 2: Test Module Import
```javascript
// In Chrome DevTools console:
import('/src/react-app/App.tsx').catch(e => console.error('Module failed:', e))
// If this logs an error, the module is failing during evaluation
```

#### Step 3: Check Env Validation Timing
```bash
# Find module-level code that runs before React mounts
grep -Bn5 "export default function\|export function App" src/react-app/App.tsx | grep "validate\|throw\|assert"

# Check if validateClientEnv() has fallbacks
grep -A2 "validateClientEnv" src/react-app/App.tsx
```

#### Step 4: Verify Env Variables
```bash
# List all VITE_ vars used in codebase
grep -roh "VITE_[A-Z_]*" --include="*.ts" --include="*.tsx" src/ | sort -u

# Check .env files for these vars
cat .env .env.local .env.production 2>/dev/null | grep "VITE_"
```

#### Step 5: Apply Fix
```typescript
// Pass the fallback INTO validation so it knows about it
const FALLBACK = "pk_test_...";
validateClientEnv({ VITE_CLERK_PUBLISHABLE_KEY: FALLBACK });
const KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || FALLBACK;
```

#### Step 6: Verify
```bash
npm run build  # No TypeScript errors
timeout 120 npx vitest run src/path/to/relevant.test.ts  # Targeted test with timeout
# After deploy: document.querySelector('#root').children.length > 0
```

### Catch-All Error Handling Masking Root Cause

**#3 production debugging trap.** A single `try-catch` wrapping multiple operations returns a generic error message, making it impossible to identify which operation actually failed.

#### Symptoms
- Error message says one thing (e.g., "Token verification failed") but the actual failure is something else (e.g., Clerk API down, DB timeout)
- Logs show the generic error but not the specific operation that threw
- Can't reproduce locally because the failing service works fine in dev

#### Step 1: Find Catch-All Blocks
```bash
# Find catch blocks that return generic error messages
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/ | grep -A5 "return.*json.*error"
```

#### Step 2: Identify Distinct Failure Modes
For each catch-all block, list what can throw:
1. **Auth/JWT verification** -> 401 (bad token, expired, wrong key)
2. **External API calls** (Clerk, Stripe, etc.) -> 503 (service unavailable)
3. **Database operations** -> 503 (DB down) or 500 (query error)
4. **Business logic** -> 400/422 (validation failure)

#### Step 3: Split into Granular Try-Catch
```typescript
// CATCH-ALL: All errors look the same
try {
  const token = await verifyToken(jwt);
  const user = await clerkApi.getUser(token.sub);
  const data = await db.query("SELECT ...");
} catch (error) {
  return json({ error: "Authentication failed" }, 401);  // MISLEADING!
}

// GRANULAR: Each failure mode has distinct error + status code
let token;
try {
  token = await verifyToken(jwt);
} catch (e) {
  console.error("JWT verification failed:", e.message);
  return json({ error: "Token verification failed" }, 401);
}

try {
  const user = await clerkApi.getUser(token.sub);
  const data = await db.query("SELECT ...");
} catch (e) {
  console.error("Auth lookup error:", e.message);
  return json({ error: "Service temporarily unavailable" }, 503);
}
```

#### Step 4: Add Diagnostic Logging
Each catch block should log:
- **Which operation** failed (JWT verify, API call, DB query)
- **The actual error message** (`error.message`, not just "Unknown error")
- **Context** (userId, endpoint, request ID if available)

### URL-Persisted State Desync (Stale Step/Tab/View Bug)

**#4 production UX bug.** State derived from URL params (`?step=`, `?tab=`, `?page=`) never recalculates when underlying data changes, causing the UI to show stale information while data-driven indicators (progress bars, counts) update correctly.

#### Symptoms
- Progress bar says 71% but step indicator says "Step 1 of 7"
- Admin marks items complete but end user sees old state
- Data refreshes (counts update) but navigation/selection doesn't advance
- Page reload doesn't fix it (URL param persists)

#### Step 1: Find URL-Persisted State
```bash
# Find state derived from URL search params
grep -n "searchParams.get\|useSearchParams\|URLSearchParams" --include="*.tsx" --include="*.ts" -r src/

# Find useEffect guards that skip recalculation
grep -B2 -A5 "=== null" --include="*.tsx" -r src/ | grep -A5 "activeStep\|activeIndex\|currentStep"
```

#### Step 2: Verify Recalculation Logic
For each URL-derived state variable, check:
1. Is there a useEffect that only initializes when state is `null`?
2. Does the useEffect re-run when data changes but state is already set?
3. If the state points to a "completed" or stale item, does it auto-advance?

```tsx
// BUG: Only initializes once, never recalculates
useEffect(() => {
  if (activeIndex === null) {
    setActiveIndex(findBestIndex());  // Only runs when null
  }
}, [data, activeIndex]);

// FIX: Also recalculates when active item becomes stale
useEffect(() => {
  if (activeIndex === null) {
    setActiveIndex(findBestIndex());
    return;
  }
  // Auto-advance if current item was completed externally
  if (data[activeIndex]?.status === "completed") {
    const hasIncomplete = data.some((d) => d.status !== "completed");
    if (hasIncomplete) setActiveIndex(findBestIndex());
  }
}, [data, activeIndex]);
```

#### Step 3: Check Multi-View Consistency
If the same state is displayed on multiple tabs/views:
```bash
# Find all places the state variable is rendered
grep -n "activeStepIndex\|activeIndex" --include="*.tsx" -r src/ | grep -v "import\|const\|set"
```
- If one view nullifies the state (e.g., `activeTab !== "claim" -> null`), other views using the same variable will show fallback values
- Fix: compute a separate display value for views where the URL state isn't active

#### Step 4: Verify Admin->User Data Flow
When admin updates data that affects user display:
1. **Backend**: Does the update endpoint clear related fields? (e.g., clear `flag_message` when marking step "completed")
2. **Admin UI**: Does optimistic update re-sync with server after success? (call `fetchData()` after PUT)
3. **User UI**: Is there a background refresh mechanism? (visibility-change listener, polling)
4. **Audit**: Is the audit action correct for write operations? (not a "view" action for a "write")

#### Step 5: Detection Commands
```bash
# Find useEffect guards that may block recalculation
grep -B5 "=== null" --include="*.tsx" -r src/ | grep "useEffect\|activeStep\|activeIndex\|currentItem"

# Find optimistic updates without refetch
grep -A10 "Optimistic update" --include="*.tsx" -r src/ | grep -v "fetch\|refetch\|reload"

# Find admin write endpoints using wrong audit action
grep -B5 "ADMIN_VIEW" --include="*.ts" -r src/worker/ | grep -B5 "PUT\|POST\|DELETE\|update\|create\|delete"
```

### Admin-User Portal Sync Audit (MANDATORY for dual-portal apps)

**#5 production UX bug class.** When an app has both admin and end-user portals sharing the same database, data written by admin must be correctly reflected in the user's view. This class of bug is insidious because each portal works fine in isolation -- the bug only appears when admin acts while the user is already viewing.

#### The Three Sync Failure Modes

| Mode | What Breaks | Example | Root Cause |
|------|------------|---------|------------|
| **Stale Navigation** | Data updates but UI pointer doesn't | Progress=71% but shows Step 1 | URL-persisted state not recalculated (see above) |
| **Stale Data** | User's data never refreshes | Admin marks complete, user still sees "pending" | No background refresh, no polling, no visibility handler |
| **Dirty Write** | Admin writes incomplete data | Admin marks step complete but flag_message persists | Backend endpoint doesn't clean up related fields |

#### Step 1: Map All Admin Write -> User Read Paths

For every admin endpoint that modifies data, trace the full path:

```bash
# Find all admin PUT/POST/DELETE endpoints
grep -n "app\.\(put\|post\|delete\).*admin" --include="*.ts" -r src/worker/

# For each endpoint, identify:
# 1. What table/fields does it write?
# 2. What user-facing endpoint reads those fields?
# 3. What user-facing component displays them?
# 4. How does the component refresh its data?
```

**Document as a table:**
```
Admin Endpoint              -> DB Write           -> User Endpoint    -> User Component     -> Refresh Mechanism
PUT /admin/steps/:id        -> steps.status       -> GET /api/steps   -> Dashboard.tsx       -> mount-only (BUG!)
PUT /admin/clients/:id      -> intake.*           -> GET /api/intake  -> IntakeForm.tsx      -> mount-only (BUG!)
POST /admin/messages        -> admin_messages     -> GET /api/messages-> Dashboard.tsx       -> polling 30s (OK)
```

Any row where "Refresh Mechanism" is "mount-only" is a bug. User will never see admin changes without manual reload.

#### Step 2: Verify Background Refresh Exists

Every user-facing hook that reads admin-writable data MUST have at least one of:

```bash
# Check 1: visibilitychange listener (minimum viable sync)
grep -A20 "useEffect" --include="*.ts" -r src/react-app/hooks/ | grep "visibilitychange"

# Check 2: Polling interval
grep -n "setInterval\|useInterval" --include="*.ts" -r src/react-app/hooks/

# Check 3: WebSocket/SSE subscription
grep -n "WebSocket\|EventSource\|onmessage" --include="*.ts" -r src/react-app/

# Check 4: Focus refetch (React Query / SWR pattern)
grep -n "refetchOnWindowFocus\|revalidateOnFocus" --include="*.ts" -r src/react-app/
```

**Rule**: If NONE of the above exist for a hook, the user will NEVER see admin changes without manual F5. Add at minimum a `visibilitychange` silent refetch.

**Critical**: Silent refetch must NOT set `isLoading=true`. If it does, returning to the tab shows a full-screen spinner. Use a separate `silentFetch` function that only updates data state, not loading state.

#### Step 3: Verify Admin Write Endpoints Clean Up Related Fields

When admin advances a status (e.g., step -> completed), all fields that only make sense for the previous status must be cleared:

```bash
# Find admin UPDATE statements
grep -A5 "UPDATE.*SET.*status" --include="*.ts" -r src/worker/ | grep -v "flag_message\|notes\|reason"
# If the UPDATE only sets status but not related fields -> BUG
```

**Common dirty write patterns:**
- Step marked "completed" but `flag_message` ("Missing documents") still shows on user dashboard
- Claim status changed to "approved" but `rejection_reason` still populated
- User deactivated but `session_token` not invalidated

**Rule**: Every admin status-change endpoint must include a CASE clause or explicit NULL set for dependent fields:
```sql
-- CORRECT: Clear flag when completing
UPDATE steps SET status = ?, 
  flag_message = CASE WHEN ? = 'completed' THEN NULL ELSE flag_message END
WHERE ...
```

#### Step 4: Verify Optimistic Updates Re-Sync

Admin UIs often use optimistic updates for responsiveness. But optimistic state can diverge from server truth if it never re-syncs:

```bash
# Find optimistic updates
grep -B5 -A15 "Optimistic update\|optimistic" --include="*.tsx" -r src/react-app/pages/Admin

# For each, verify: after the API call succeeds, is fetchData() called?
# Pattern to look for:
#   try { await securePut(...); await fetchClientData(); }  <- CORRECT
#   try { await securePut(...); haptic.success(); }         <- BUG: no re-sync
```

**Rule**: Every optimistic update MUST call `fetchData()` after successful API response to pull back server-computed side effects (intake.is_complete, cleared flags, computed timestamps).

#### Step 5: Verify Audit Actions Match Operation Type

Admin write operations must log the correct audit action -- not a "view" action:

```bash
# Find write endpoints using view audit actions
grep -B10 "AuditActions\.\(ADMIN_VIEW\|VIEW\)" --include="*.ts" -r src/worker/ | grep -B10 "PUT\|POST\|DELETE"
```

**Rule**: `PUT`/`POST`/`DELETE` handlers must use write-specific audit actions (`ADMIN_UPDATE_*`, `ADMIN_CREATE_*`, `ADMIN_DELETE_*`). Using `ADMIN_VIEW_CLIENT` for a write operation makes audit logs useless for investigating who changed what.

#### Step 6: Verify Multi-View Consistency

If the same data appears on multiple tabs/views, each view must show the correct current state:

```bash
# Find state variables used across multiple tab views
grep -n "activeStepIndex\|activeTab\|currentStep" --include="*.tsx" -r src/react-app/pages/ | \
  grep -v "const\|set\|import" | awk -F: '{print $2}' | sort -u
```

**Common trap**: State derived from URL params (e.g., `activeStepIndex`) is nullified when user is on a different tab. If the overview tab renders "Step X of Y" using the same variable, it shows the fallback value (usually Step 1) instead of the actual next step.

**Rule**: Data-driven display values should be computed from data (useMemo), not from navigation state. Navigation state tells you *where the user is*; data tells you *what to show*.

#### Pre-Ship Checklist for Admin-User Sync

Run this checklist before shipping ANY change that touches admin endpoints or user data display:

- [ ] Every admin write endpoint clears dependent fields on status change
- [ ] Every admin write endpoint uses the correct audit action (not VIEW for writes)
- [ ] Every admin optimistic update calls fetchData after success
- [ ] Every user-facing data hook has visibility-change silent refetch
- [ ] Silent refetch does NOT trigger loading spinner (separate silentFetch function)
- [ ] URL-persisted navigation state auto-advances when data changes
- [ ] Multi-tab/multi-view displays use data-derived values, not navigation state
- [ ] No useEffect that only initializes once but depends on externally-changeable data
