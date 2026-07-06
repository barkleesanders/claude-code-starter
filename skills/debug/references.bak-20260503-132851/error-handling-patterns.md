# Error Handling Patterns

## Pattern 1: Catch-All Error Handling Masking Root Cause

**Rank: #3 production debugging trap.**

A single `try-catch` wrapping multiple operations returns a generic error, making it impossible to identify which operation actually failed.

### Symptoms
- Error message says one thing (e.g., "Token verification failed") but actual failure is different (e.g., API down, DB timeout)
- Logs show generic error but not the specific operation that threw
- Can't reproduce locally because the failing external service works in dev

### Quick Detection
```bash
# Find catch blocks returning generic errors in middleware/handlers
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/worker/ | grep -A5 "return.*json.*error"

# Find large try-catch blocks (catch far from try = multiple wrapped operations)
grep -n "} catch" --include="*.ts" -r src/worker/middleware/
```

### Fix Pattern
```typescript
// CATCH-ALL: All errors return same message + status code
try {
  const token = await verifyToken(jwt);        // Auth failure
  const user = await clerkApi.getUser(sub);    // API failure
  const data = await db.query("SELECT ...");   // DB failure
} catch (error) {
  return json({ error: "Authentication failed" }, 401);  // MISLEADING!
}

// SPLIT: Each failure mode gets correct status + message
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

### Status Code Guide
| Failure Mode | Status Code | When |
|-------------|-------------|------|
| JWT/token verification | 401 | Bad token, expired, wrong key |
| External API (Clerk, Stripe) | 503 | Service unavailable |
| Database error | 503 or 500 | Connection failed, query error |
| Business logic validation | 400 or 422 | Bad input |

### Real-World Case: Production App Benefits Finder (2026-02-27)
- **Symptom**: "Unauthorized: Token verification failed" on every benefits search
- **Root cause**: Clerk API call in the same try-catch was failing, but the catch returned 401
- **Fix**: Split into JWT try-catch (401) and service try-catch (503)
- **File**: `src/worker/middleware/clerkAuth.ts`
- **Commit**: `5aeec79`

---

## Pattern 11: CI False Positives from Local Grep

**Rank: Common time-waster in CI debugging.**

Local `grep` for code patterns produces false matches that lead to wrong conclusions about what CI is actually checking.

### Symptoms
- You "fix" what grep tells you is wrong, but CI still fails
- grep matches patterns inside string literals, comments, or unrelated code
- CI uses a project-specific validator with different rules than your grep

### Quick Detection
```bash
# Don't guess -- read the actual CI logs
gh run view <RUN_ID> --log-failed

# Or get all check-runs for latest commit
gh api repos/<owner>/<repo>/commits/<SHA>/check-runs --jq '.check_runs[] | {name, conclusion}'
```

### Real-World Case: topgrade i18n (2026-03-07)
- Grepped for `t!("...")` to find locale strings needing translations
- `format!("...")` matched because `format` ends in `t`, making grep think it was `t!(...)`
- Wasted a round of CI. Should have read the actual CI checker script or used `gh run view --log-failed`

---

## Pattern 14: Admin Route Auth Missing DB Fallback (Metadata-Only Check)

**Rank: Silent 403 for production admin -- every admin route fails with no obvious cause.**

Custom `requireAdmin()` functions in route files that only check Clerk `publicMetadata.role === "admin"` silently block the real production admin, who is set via `is_admin = 1` in the DB (not Clerk metadata).

### Symptoms
- Admin tabs (Referrals, Users, etc.) show "Could not load data" or "Failed to load" for the real admin
- `/api/admin/*` routes return 403 for `admin@example.com`
- No error in logs because the `throw new Error("Admin access required")` is caught and returned as 403
- Works fine in local dev if you set Clerk metadata there but not in production

### Root Cause
Two separate admin authorization mechanisms exist:
1. **`adminMiddleware`** in `src/worker/index.ts` -- checks Clerk metadata OR DB `is_admin=1` (correct)
2. **Custom `requireAdmin()`** in individual route files -- may only check Clerk metadata (wrong)

The production admin (`admin@example.com`) uses `is_admin = 1` in the DB. It does NOT have `publicMetadata.role === "admin"` in Clerk. Any route that uses a metadata-only check returns 403 for this user.

### Quick Detection
```bash
# Find custom requireAdmin functions in route files
grep -rn "requireAdmin\|require_admin" src/worker/routes/ --include="*.ts"

# Check if any are synchronous (sync = no DB fallback = metadata-only)
grep -B2 -A10 "function requireAdmin" src/worker/routes/*.ts

# Check adminMiddleware in index.ts for comparison
grep -A15 "adminMiddleware" src/worker/index.ts
```

### Fix Pattern
```typescript
// WRONG -- metadata-only, silently blocks DB-based admin
function requireAdmin(c: Context) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role !== "admin") {
    throw new Error("Admin access required");
  }
  return user;
}

// CORRECT -- must be async, matches adminMiddleware pattern
async function requireAdmin(c: Context<{ Bindings: Env }>) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role === "admin") return user;
  // DB fallback -- production admin uses is_admin=1, not Clerk metadata
  const dbUser = await c.env.DB.prepare(
    "SELECT is_admin FROM users WHERE id = ?",
  ).bind(user.id).first<{ is_admin: number }>();
  if (dbUser?.is_admin === 1) return user;
  throw new Error("Admin access required");
}

// All call sites must await: requireAdmin(c) -> await requireAdmin(c)
```

### Real-World Case: Production App adminClerk.ts (2026-03-13)
- **Symptom**: Referrals tab, user lookup, referrers list all showed "Could not load data" for `admin@example.com`
- **Root cause**: `requireAdmin()` was synchronous and metadata-only. Production admin has `is_admin=1` but no Clerk metadata role.
- **Fix**: Made `requireAdmin` async with DB `is_admin` fallback; updated all 6 call sites from `requireAdmin(c)` to `await requireAdmin(c)`. Added `Context<{ Bindings: Env }>` type so `c.env.DB` was accessible.
- **Files**: `src/worker/routes/adminClerk.ts`

---

## Admin Route Returns 500 Instead of 403

- **Symptom**: Admin check fails but returns 500 (Internal Server Error) instead of 403 (Forbidden)
- **Quick Detection**: `grep -A5 "function requireAdmin" --include="*.ts" src/worker/ | grep "throw new Error"`
- **Fix**: `throw new HTTPException(403, { message: "Admin access required" })` instead of `throw new Error(...)`
- **Incident (2026-03-15)**: `adminClerk.ts` routes returned 500 for non-admin users
