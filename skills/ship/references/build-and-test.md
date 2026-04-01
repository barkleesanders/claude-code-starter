# Build & Test

Covers Phase 1 (build verification, smart test execution, targeted test suites) and Phase 1.1 (frontend-backend API contract verification).

---

## Phase 1: BUILD & TEST (BLOCKING)

### 100% PRODUCTION CODE COVERAGE (MANDATORY)

When fixing issues or running audits, scan ALL production source files — not just changed ones. Track coverage:

```bash
# Count production files (excluding tests)
TOTAL=$(find src/ -name "*.tsx" -o -name "*.ts" | grep -v __tests__ | grep -v ".test." | wc -l | tr -d ' ')

# Run 10 progressive audit passes covering:
# error handling, security, mobile/responsive, a11y, React patterns,
# banned colors, performance, backend security, error boundaries, final sweep

# Report coverage: "Files: Y/$TOTAL (Z%)"
# Do NOT ship until 100% of production files have been scanned
```

- Auto-detect project type by scanning for configuration files
- Execute appropriate build commands for detected stack
- **STOP IMMEDIATELY** if build fails - provide detailed error report

### SMART TEST EXECUTION (CRITICAL — DO NOT RUN FULL SUITE)

**NEVER run `npm test` or `npx vitest run` without targeting.** Vitest fork workers leak ~5GB RAM each when they hang. Running the full suite risks killing the system.

**Step 1: Identify changed files**
```bash
git diff --name-only HEAD
```

**Step 2: Run ONLY affected tests (in order of preference)**
```bash
# 1. PREFERRED: Tests affected by uncommitted changes
timeout 60 npx vitest run --changed 2>&1; EXIT=$?; pkill -f vitest 2>/dev/null; echo "EXIT: $EXIT"
# Exit 0 = pass, Exit 124 = tests passed but vitest hung on exit (OK if green checkmarks shown)

# 2. On feature branch: tests affected since main
timeout 60 npx vitest run --changed HEAD~1 2>&1; pkill -f vitest 2>/dev/null

# 3. If --changed finds zero tests: match by module name
timeout 120 npx vitest run -t "moduleName" 2>&1; pkill -f vitest 2>/dev/null

# 4. LAST RESORT ONLY (changes span 10+ unrelated modules):
timeout 180 npx vitest run 2>&1; pkill -f vitest 2>/dev/null
```

**HARD SAFETY LIMITS:**
- **ALWAYS** wrap every test command with `timeout` (60-180s max)
- **ALWAYS** run `pkill -f vitest 2>/dev/null` after EVERY test invocation
- **Maximum 3 test invocations total** per deployment attempt — if tests fail 3 times, STOP and report. Do NOT keep retrying.
- Exit code 124 from `timeout` is OK if all tests showed green checkmarks before the hang

**Decision logic:**
- Parse test output: total count, passed, failed, skipped
- **If ANY test fails**: BLOCK deployment, display failure report. Do NOT retry automatically.
- **If tests show 100% pass**: Proceed to Phase 1.1
- If skipped tests detected: Issue warning but allow proceed if no failures

### TARGETED TEST SUITES (MANDATORY — replaces GitHub Actions CI)

After the generic `vitest run --changed` pass, run these specific test suites that the CI workflow used to handle. Each is BLOCKING — if any fail, stop deployment.

```bash
# 1. Worker route ordering — catch-all route must be LAST
timeout 60 npx vitest run src/worker/index.test.ts 2>&1; EXIT=$?; pkill -f vitest 2>/dev/null
# BLOCK if exit != 0 — means app.all("*") is before API routes

# 2. DocuSeal integration — signing flow must not regress
timeout 60 npx vitest run tests/docuseal-integration.test.ts 2>&1; EXIT=$?; pkill -f vitest 2>/dev/null
# BLOCK if exit != 0 — DocuSeal integration is fragile, took multiple attempts to stabilize

# 3. ESLint a11y — accessibility + React hooks rules
timeout 60 npx eslint "src/react-app/**/*.{ts,tsx}" 2>&1; EXIT=$?
# BLOCK if exit != 0
# There is NO "pre-existing" exception for ESLint errors.
# ALL errors (jsx-a11y/*, react-hooks/refs, etc.) MUST be fixed before deploying.
# See "Step 2b: ESLint a11y/React Auto-Fix Patterns" in ZERO-TOLERANCE LINT POLICY above.
# If errors exist, FIX THEM using the documented patterns, then re-run.

# 4. Module-scope throw check — React silent startup killer
MATCHES=$(grep -rn "^throw \|^  throw " src/react-app/ --include="*.ts" --include="*.tsx" \
  | grep -v ".test." | grep -v "node_modules" \
  | grep -v "main.tsx.*Root element" | grep -v "utils/api.ts" || true)
if [ -n "$MATCHES" ]; then
  echo "BLOCK: Found throw at module scope in react-app"
  echo "$MATCHES"
fi
```

**Post-deploy production tests** (run in Phase 4.1 after wrangler deploy):
```bash
# 5. Production integration tests — verifies live endpoints
timeout 60 TEST_BASE_URL=https://aivaclaims.com npx vitest run tests/worker-integration.test.ts 2>&1
pkill -f vitest 2>/dev/null
# WARN if fails (don't block — already deployed, but flag for investigation)
```

---

## Phase 1.1: FRONTEND-BACKEND API CONTRACT VERIFICATION

**Purpose**: Detect API endpoints called by frontend that have no corresponding backend route handler.

**Background**: A common bug is deploying frontend code that calls API endpoints that were never implemented in the backend. When this happens, the catch-all SPA handler returns HTML instead of JSON, causing confusing "Expected JSON" errors.

**Execution**:

1. **Extract Frontend API Calls**:
   - Scan frontend code (src/react-app/, src/pages/, src/components/, etc.) for API call patterns:
     - `fetch("/api/..."`
     - `secureFetch("/api/..."`
     - `secureFetchJson("/api/..."`
     - `axios.get/post/put/delete("/api/..."`
   - Parse out unique API paths (normalize dynamic segments like `:id` to `*`)
   - Store as FRONTEND_API_ENDPOINTS list

2. **Extract Backend Route Handlers**:
   - Scan backend code (src/worker/, src/server/, src/api/, etc.) for route registration patterns:
     - `app.get("/api/...")`
     - `app.post("/api/...")`
     - `app.put("/api/...")`
     - `app.delete("/api/...")`
     - `router.get/post/put/delete`
     - `.route("/api/...", routerModule)`
   - Parse out unique API paths (normalize dynamic segments)
   - Store as BACKEND_API_ENDPOINTS list

3. **Compare and Detect Missing Routes**:
   - For each path in FRONTEND_API_ENDPOINTS:
     - Check if a matching path exists in BACKEND_API_ENDPOINTS
     - Account for route parameters (`:id`, `:userId`, etc. = `*`)
   - Build MISSING_ROUTES list

4. **Decision Logic**:
   - **If 0 missing routes**: Display "All frontend API calls have backend handlers" and continue
   - **If missing routes detected**: **BLOCK deployment**

5. **On BLOCK**:
   - Display table of missing routes with frontend file/line, expected backend path, suggested backend file
   - Offer options: implement missing routes, remove frontend calls, `--skip-api-check` override, cancel

**Override**: `--skip-api-check`: Skip this phase (requires explicit confirmation, logged to audit)
