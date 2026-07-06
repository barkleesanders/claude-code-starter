# Debugging Discipline

## Diagnostic Checklist (When Debugging Any Production Error)

1. **Is the error message accurate?** Check if a catch-all is masking the real error
2. **Check runtime logs**: `wrangler tail` or Cloudflare dashboard -- what's the actual error?
3. **Reproduce locally**: Can you hit the same endpoint with the same token?
4. **Check external services**: Is Clerk/Stripe/DB actually responding?
5. **Check env vars**: Are all secrets set in the deployment environment?
6. **Check www redirect**: Is the user hitting `www.` and losing cookies?
7. **Check third-party IDs**: Are template/product IDs in wrangler.json still valid?
8. **Check CSP**: Does `frame-src` include domains for embedded widgets (DocuSeal, Stripe, etc.)?
9. **Text overflowing card on mobile?** Check for `flex items-center` without `min-w-0`, `grid-cols-2` without `sm:` breakpoint, icon divs missing `flex-shrink-0`
10. **User preference not persisting across page loads?** Check if `localStorage.setItem` in component has a matching `localStorage.getItem` in App.tsx that runs on every mount
11. **Admin routes returning 403 for the real admin?** Check if custom `requireAdmin()` in route files is synchronous (metadata-only). It must be async with a DB `is_admin=1` fallback -- see Pattern 14
12. **Users logged out after every deploy?** Check for `vite:preloadError` handler in main.tsx, ChunkLoadError detection in ErrorBoundary, and `CDN-Cache-Control: no-store` in securityHeaders -- see Pattern 6
13. **XSS via innerHTML?** Check BOTH raw `.innerHTML =` (in entry points like index.tsx at project root -- runs before React) AND `dangerouslySetInnerHTML` (in React components). Search from `.` not `src/` -- root-level files are blind spots. See Pattern 7
14. **JSON-LD breaking the page?** Check if `JSON.stringify` in `<script>` tags escapes `</` with `\u003c` -- see Pattern 8
15. **Async button fires twice?** Check if `onClick={async ...}` has `disabled={isLoading}` state -- see Pattern 9
16. **Unauthenticated user sees error instead of redirect?** Check if page calling `secureFetch` has frontend auth guard -- see Pattern 10
17. **Admin route returns 500 instead of 403?** Check if `requireAdmin` throws `HTTPException(403)` not `Error` -- see Pattern 11
18. **Grid overflows on mobile?** Check if `grid-cols-N` (N>1) has `sm:` or `md:` responsive breakpoints -- see Pattern 12
19. **Feature works on desktop but blank/broken on iPhone?** Check for `<iframe>` with blob URLs (PDFs won't render on iOS), `vh` units (use `dvh`), or `position: fixed` conflicts with keyboard -- see Pattern 13
20. **Component renders twice or state "lags behind"?** Check for `useEffect` that sets derived state -- compute during render instead. Check for `useEffect` + `useRef` to track previous values -- use `useState` + render comparison instead -- see Pattern 15

---

## Zero-Tolerance Lint & Security Cleanup (MANDATORY)

**Every debugging session MUST leave the codebase cleaner than it found it.** Before handing off or marking a fix complete, run:

```bash
# LINT: Fix ALL errors to zero
npx biome check --fix . 2>&1       # Auto-fix what it can
npx biome check . 2>&1             # Verify 0 errors remain
# If errors remain: fix them manually (missing keys, formatting, config exclusions)
# If dist/ or build output triggers errors: update biome.json files.includes to exclude them
# If CSS @tailwind false positives: disable CSS linter in biome.json
# If safe dangerouslySetInnerHTML: add overrides in biome.json for that file

# SECURITY: Fix ALL vulnerabilities to zero
npm audit fix 2>&1                  # Auto-fix
npm audit 2>&1                      # Verify 0 vulnerabilities
# If vulns remain: npm install <pkg>@latest, or add "overrides" in package.json
# ALL severities matter -- fix LOW too, not just CRITICAL

# BUILD: Verify nothing broke
npm run build 2>&1
```

**The debugging session is NOT complete until:** `biome check . = 0 errors` AND `npm audit = 0 vulnerabilities` AND `build passes`.

---

## Debugging Discipline Rules

### 1. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding.
- Point at logs, errors, failing tests -- then resolve them.
- Zero context switching required from the user.
- Go fix failing CI tests without being told how.

### 2. Find Root Causes, Not Band-Aids
- No temporary fixes. No "it works now" without understanding why.
- If something goes sideways, STOP and re-plan immediately -- don't keep pushing the same approach.
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."

### 3. Systematic Debugging (4-Phase -- Iron Law)

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes. Use ESPECIALLY when under time pressure, when "just one quick fix" seems obvious, or when previous fixes didn't work.

**Phase 1: Root Cause Investigation**
1. Read error messages carefully -- stack traces, line numbers, error codes
2. Reproduce consistently -- exact steps, every time, or gather more data
3. Check recent changes -- git diff, new dependencies, config, environment
4. Multi-component systems -- log data at EACH component boundary (entry/exit), run once, find WHERE it breaks
5. Admin-user data sync -- if "admin changed X but user sees old X", use the decision tree:
   - a) Hook has visibilitychange? b) URL state auto-advances? c) Endpoint cleans dependent fields? d) Optimistic update re-syncs? e) Same data source for indicators?
6. Trace data flow -- where does bad value originate? Trace backward through call chain to source. Fix at source, not symptom

**Phase 2: Pattern Analysis**
1. Find working examples -- similar working code in same codebase
2. Compare against references -- read reference implementation COMPLETELY, don't skim
3. Identify differences -- list every difference, however small
4. Understand dependencies -- components, settings, config, assumptions

**Phase 3: Hypothesis and Testing**
1. Form SINGLE hypothesis -- "I think X is the root cause because Y" -- write it down
2. Test minimally -- smallest possible change, one variable at a time
3. Verify before continuing -- worked -> Phase 4; didn't -> NEW hypothesis (don't stack fixes)

**Phase 4: Implementation**
1. Create failing test case -- simplest reproduction, automated if possible
2. Implement SINGLE fix -- address root cause, ONE change, no "while I'm here" improvements
3. Verify fix -- test passes? No other tests broken? Issue actually resolved?
4. **3-failure rule:** if 3 fixes fail, STOP -- question the architecture, not the fix. Discuss with human before attempting more.

**Red Flags (STOP and return to Phase 1):**
- "Quick fix for now" / "Just try changing X" / "I don't fully understand but this might work"
- "One more fix attempt" (after 2+ failures)
- Each fix reveals new problem in different place -> architectural problem
- Proposing solutions before tracing data flow

### Supporting Techniques

**Root Cause Tracing** -- Bugs manifest deep in the stack. Trace BACKWARD:
1. Observe symptom -> 2. Find immediate cause -> 3. What called this? -> 4. Keep tracing up -> 5. Find original trigger -> 6. Fix at source + add validation at each layer (defense-in-depth)
- Add instrumentation: `console.error('DEBUG:', { directory, cwd, stack: new Error().stack })`
- For test pollution: run tests one-by-one with bisection to find polluter

**Defense-in-Depth** -- After fixing a bug, validate at EVERY layer data passes through:
- Layer 1: Entry point validation (reject invalid input at API boundary)
- Layer 2: Business logic validation (data makes sense for this operation)
- Layer 3: Environment guards (refuse dangerous operations in specific contexts)
- Layer 4: Debug instrumentation (capture context for forensics)
- Single validation = "fixed the bug". Four layers = "made the bug impossible"

**Condition-Based Waiting** -- Replace arbitrary `sleep`/`setTimeout` with condition polling:
```typescript
// Guessing: await sleep(50); const result = getResult();
// Waiting: await waitFor(() => getResult() !== undefined);
```
- Poll every 10ms, always include timeout with clear error message
- Only use arbitrary timeout for known timing behavior (debounce intervals) -- document WHY

### 4. Verify The Fix Actually Works
- Never mark a bug as fixed without proving it.
- After deploy: curl the endpoint, verify the response, check the UI.
- Run the exact reproduction steps that triggered the bug.
- Ask yourself: "Would a staff engineer approve this fix?"

### 5. Self-Improvement Loop
- After ANY correction from the user: write a lesson to memory.
- Write rules that prevent the same mistake.
- If you fixed the wrong thing twice, the third attempt must use a fundamentally different approach.

---

## Pattern 16: Data Stale Between Admin and User Portals

**Symptoms:**
- Admin marks step/claim/document as complete, but user still sees old status
- Progress bar shows correct % but navigation says "Step 1 of 7"
- Data-driven indicators update but navigation/selection doesn't advance
- User must manually F5 to see admin changes
- Works fine if user loads page AFTER admin change, but not if page was already open

**Root Causes (decision tree -- check in order):**
1. **No background refresh** -- User hook fetches on mount only, no `visibilitychange` listener
2. **URL-persisted stale pointer** -- `?step=1` in URL, useEffect only initializes when `null`, never recalculates
3. **Dirty write** -- Admin marks step "completed" but `flag_message="Missing docs"` persists
4. **Optimistic desync** -- Admin UI uses optimistic update but never calls `fetchData()` after success
5. **Split-brain display** -- Progress bar reads from data (correct), step indicator reads from URL state (stale)

**Quick Detection:**
```bash
# Find hooks without background refresh
for f in src/react-app/hooks/*.ts; do
  if grep -q "secureFetch" "$f" && ! grep -q "visibilitychange" "$f"; then
    echo "STALE: $(basename $f) -- no background refresh"
  fi
done

# Find URL-derived state that only initializes once
grep -n "=== null" --include="*.tsx" -r src/react-app/pages/ | grep -i "step\|index\|active"

# Find admin UPDATEs without field cleanup
grep -A3 "UPDATE.*SET.*status" --include="*.ts" -r src/worker/ | grep -v "flag_message\|NULL\|CASE"

# Find optimistic updates without refetch
grep -B2 -A15 "Optimistic" --include="*.tsx" -r src/react-app/pages/Admin | grep -c "fetchClientData"
```

**Fix Pattern:**
```typescript
// 1. Add silentFetch (no spinner) + visibilitychange to every user hook
const silentFetch = useCallback(async () => {
  try {
    const res = await secureFetch("/api/data");
    if (res.ok) setData(await res.json());
  } catch (err) { console.error("Silent refetch failed:", err); }
}, []);

useEffect(() => {
  fetchData(); // initial (shows spinner)
  const handler = () => { if (document.visibilityState === "visible") silentFetch(); };
  document.addEventListener("visibilitychange", handler);
  return () => document.removeEventListener("visibilitychange", handler);
}, [fetchData, silentFetch]);

// 2. Auto-advance URL state when active item is completed
if (data[activeIndex]?.status === "completed") {
  const next = data.findIndex(d => d.status !== "completed");
  if (next !== -1) setActiveIndex(next);
}

// 3. Clear dependent fields in admin write endpoint
UPDATE steps SET status = ?,
  flag_message = CASE WHEN ? = 'completed' THEN NULL ELSE flag_message END
WHERE ...

// 4. Re-sync after optimistic update
await securePut(url, body);
await fetchClientData(); // pull server-computed side effects
```

**Real-world case (2026-03-30):** your app dashboard showed "Step 1 of 7" with 71% progress. `activeStepIndex` was URL-persisted via `?step=1` and the useEffect only initialized when `null`. Admin marked 5 steps complete but user's pointer never advanced. Fixed by: auto-advance logic + silentFetch on all 6 user-facing data hooks.
