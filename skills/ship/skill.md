---
name: ship
user-invocable: true
description: "Safe production deployment with quality gates, safety audits, and rollback. Deploys to PRODUCTION by default."
---

# /ship - Production Deployment

Execute safe **production deployment** directly with comprehensive quality gates and integrated safety audits. All phases run inline — no subagent.

**Default behavior: Deploys directly to PRODUCTION**

## MANDATORY: FIX ALL ISSUES EVERY RUN (ZERO EXCEPTIONS)

**Every `/ship` invocation MUST execute ALL fix phases in order. NEVER skip a phase for efficiency, even if the code change is small or "just a copy change".**

The following phases are **MANDATORY on every run** — treat them as a checklist:

| Phase | Gate | Must reach |
|-------|------|-----------|
| 0 | Lint (full project — Biome/ESLint) | 0 errors, 0 warnings |
| 0 (Stage 1.5) | `npm audit` / security audit | 0 vulnerabilities |
| 1 | Build (`tsc --noEmit` + build tool) | Exit 0 |
| 1 | Tests (targeted, with timeout) | All pass |
| 1 | Project-specific test suites (if `package.json` has `test:worker`, `test:integration`, etc.) | All pass |
| 1.1 | Frontend-backend API contract | 0 missing routes |
| 1.25 | Security audit + Dependabot alerts | 0 open alerts with available fix |
| 1.26 | Code scanning hygiene | Auto-fix all |
| 1.3 | React scope + env safety | No blockers |
| 1.4 | SEO/sitemap consistency | No conflicts |
| 1.42 | Deploy session invalidation | Handlers exist |
| 1.45 | Third-party config, XSS, auth guards | No blockers |

**If a phase finds issues, FIX THEM INLINE before moving to the next phase.** Do not defer. Do not warn-and-continue for fixable issues. The goal is: every `/ship` run leaves the repo in a strictly better state than it found it.

**Warnings are NOT acceptable.** Lint must return 0 errors AND 0 warnings. Fix warnings by: (1) auto-fixing, (2) manually fixing remaining issues, or (3) suppressing false positives in linter config with justification. "Pre-existing warnings" is not an excuse — fix them all.

**Dependabot is NOT optional.** If `gh api repos/{owner}/{repo}/dependabot/alerts` returns open alerts with available fixes, add overrides to `package.json`, run install, verify build, commit, and push — all within this run.

**Stale lockfile check (MANDATORY).** Before fixing Dependabot alerts, check which lockfile(s) the alerts reference (`manifest_path` in the API response). If alerts reference a lockfile the project doesn't use (e.g., `pnpm-lock.yaml` when project uses `bun.lock`, or `package-lock.json` when project uses `pnpm`), the stale lockfile MUST be deleted from git and added to `.gitignore`. Overrides only fix the active lockfile — stale lockfiles cause false Dependabot alerts that can never close.

```bash
# Detect active package manager
ACTIVE_LOCK=""
[ -f bun.lock ] && ACTIVE_LOCK="bun.lock"
[ -f pnpm-lock.yaml ] && ACTIVE_LOCK="pnpm-lock.yaml"
[ -f package-lock.json ] && ACTIVE_LOCK="package-lock.json"

# Remove any OTHER tracked lockfiles that aren't the active one
for STALE in pnpm-lock.yaml package-lock.json bun.lock yarn.lock; do
  if [ "$STALE" != "$ACTIVE_LOCK" ] && git ls-files --error-unmatch "$STALE" 2>/dev/null; then
    git rm --cached "$STALE"
    echo "$STALE" >> .gitignore
    echo "Removed stale lockfile: $STALE (was causing false Dependabot alerts)"
  fi
done
```

**After fixing Dependabot alerts, VERIFY they actually closed.** Wait 60s after push, then re-check:
```bash
sleep 60
REMAINING=$(gh api "repos/${REPO}/dependabot/alerts" --jq '[.[] | select(.state=="open")] | length')
if [ "$REMAINING" -gt 0 ]; then
  gh api "repos/${REPO}/dependabot/alerts" --jq '.[] | select(.state=="open") | "\(.number): \(.dependency.manifest_path)"'
fi
```

## Usage

```
/ship [optional instructions]
```

## Deployment Targets

| Command | Target |
|---------|--------|
| `/ship` | **PRODUCTION** (default) |
| `/ship --staging` | Staging first, then prompt for production |
| `/ship --staging-only` | Staging only, no production |
| `/ship --audit` | Run safety audit tiers only (no deploy) |
| `/ship --audit tier2` | Run specific audit tier |
| `/ship --audit full` | Run all audit tiers |
| `/ship --watch-ci` | Block until all CI checks complete after push |
| `/ship --no-ci` | Skip Phase 4.6 CI monitoring entirely |
| `/ship --skip-review` | Skip Phase 4.2 multi-agent code review |
| `/ship --skip-perf` | Skip Phase 4.3 web performance audit |
| `/ship --skip-visual` | Skip Phase 4.35 visual regression check |

## Examples

- `/ship` — Deploy to **production** with full verification
- `/ship the auth feature` — Deploy specific feature to **production**
- `/ship --staging` — Deploy to staging first, then promote to prod
- `/ship --allow-lint-errors` — Override lint failures (with audit trail)
- `/ship --audit` — Run safety audit only, no deployment
- `/ship --audit tier2` — Run Tier 2 investigation audit

## Tools Available

### ogrep — Code Search During Gates
```bash
ogrep query "throw.*module scope" --mode fulltext   # Find risky patterns
ogrep query "validateClientEnv" -n 20               # Find all validation calls
```

### qmd — Documentation Search
```bash
qmd query "deployment checklist"    # Search project docs
qmd query "rollback procedure"      # Find rollback docs
```

### bd — Task Tracking
```bash
bd create --title="Deploy: run quality gates" --type=task   # Track deployment tasks
bd close <id>                                                # Mark gate complete
```

## CRITICAL: NO TASK MANAGEMENT TOOLS

**DO NOT use TodoWrite, TaskCreate, or TaskUpdate tools.** Use `bd` (beads) for task tracking instead:

```bash
bd create --title="Deploy: <description>" --type=task  # Create at start
bd update <id> --status=in_progress                     # Claim it
bd close <id> --reason="Deployed to production"         # Close when done
```

Print a short status line when transitioning phases:
```
── Phase 0 ✓ → Phase 1: Build & Test ──
```

Just execute the phases in order. Do the work, don't track the work.

## DEPLOYMENT TARGET (DEFAULT: PRODUCTION)

**Default behavior**: Deploy directly to production. The `/ship` command deploys to production unless explicitly told otherwise.

**Staging-first workflow**: If user specifies "staging first", "to staging", or `--staging`:
1. Deploy to staging/preview environment first
2. Display staging URL and verification steps
3. Wait for explicit "promote to production" confirmation
4. Then run production deployment

**Flags**:
- (default): Deploy to production
- `--staging` or "to staging first": Deploy to staging, then prompt for production
- `--staging-only`: Deploy to staging only, skip production
- `--prod` or `--production`: Explicit production deploy (same as default)
- `--no-babysit`: Skip Phase 6 PR babysitter
- `--babysit`: Force Phase 6 even on default branch (monitor CI after direct push)

## EXECUTION PROTOCOL

### CODE SEARCH

Use standard tools (Grep, Glob, Read) for code discovery. Use `ogrep` if available for AST-aware search, but never block on it — fall back to Grep/Glob immediately if unavailable.

---

## Phase -1: REPOSITORY CONTEXT VERIFICATION (ALWAYS FIRST)

**Purpose**: Verify you're in the correct repository and establish baseline information.
**Execution**: MUST run before any other phase.

1. **Verify Git Repository**:
   - Run: `git rev-parse --is-inside-work-tree 2>/dev/null`
   - If not in git repo: **STOP** - Display error: "Not in a git repository. Navigate to your project directory first."
   - If in git repo: Continue

2. **Identify Repository Context**:
   - Extract repository information:
     - REPO_URL: `git config --get remote.origin.url`
     - REPO_NAME: `basename -s .git "$REPO_URL"` or extract from URL
     - CURRENT_BRANCH: `git rev-parse --abbrev-ref HEAD`
     - WORKING_DIR: `pwd`
     - LAST_COMMIT: `git log -1 --oneline`
     - UPSTREAM: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`

3. **Display Repository Context Banner**:
   ```
   ════════════════════════════════════════════════════════════
   SHIP WORKING CODE - Repository Context
   ════════════════════════════════════════════════════════════

   Repository: $REPO_NAME
   Remote URL: $REPO_URL
   Branch: $CURRENT_BRANCH
   Directory: $WORKING_DIR

   ════════════════════════════════════════════════════════════
   ```

4. **Verify Remote Repository Accessibility**:
   - Run: `git ls-remote --exit-code origin HEAD >/dev/null 2>&1`
   - If successful: "Remote repository accessible"
   - If failed: **STOP** - Display error: "Cannot reach remote repository."

5. **Check Working Directory State**:
   - Run: `git status --porcelain`
   - If output is empty: "Working directory clean"
   - If output exists: Display uncommitted changes and offer options:
     1. Stage all changes and continue (git add -A)
     2. Cancel deployment
   - Execute user's choice accordingly

6. **Protected Branch Detection**:
   - Check if current branch matches protected patterns: `main|master|production|prod|release`
   - If on protected branch: Display warning and require explicit YES/NO confirmation
   - If NO: **STOP** deployment
   - If YES: Log warning and continue

7. **Verify Branch Tracking**:
   - Run: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
   - If no upstream: Offer options to set upstream or continue without
   - If upstream exists: Check ahead/behind status

8. **Display Repository Summary** with all verification results before proceeding to Phase -0

---

## Phase -0: MERGE CONFLICT AUTO-RESOLUTION

**Purpose**: Ensure the working tree is conflict-free, validated, and committed before linting or testing begins.
**Execution**: Always operate from repository root. Skip automatically if no conflicts detected.

1. **Detect Conflicts**:
   - Run: `git status --porcelain | cat` and collect paths with `U` status codes
   - Scan files for merge markers using `rg -l "<<<<<<<"`
   - If no conflicts found: Display "No merge conflicts found" and continue to Phase 0

2. **Resolve Conflicts (Non-interactive)**:
   - Manifest/lock files: Regenerate via package manager instead of manual edits
   - Generated artifacts: Re-run the generator to avoid hand-merging
   - Configuration files: Merge both sides' safe keys, prefer stricter rules
   - Source/text content: Preserve both logical intents where possible
   - Binary files: Default to current branch (ours)
   - Delete all conflict markers before moving on
   - Never prompt the user - choose sensible defaults

3. **Validate Builds & Tests**:
   - Detect ecosystem and run appropriate install/build/test commands
   - If validation fails, iterate on merges or revert until tests pass

4. **Finalize**:
   - Stage everything: `git add -A`
   - Commit locally: `git commit -m "chore: resolve merge conflicts"`
   - Never push or tag in this phase
   - Output concise summary of decisions made
   - Only proceed to Phase 0 when `git status --porcelain` is clean

---

## Phase 0: CODE QUALITY - INTELLIGENT LINT AUTO-FIXING (AI-ENHANCED)

### Stage 0: Git Checkpoint (Safety First)
- Create safety checkpoint: `git stash push -m "pre-lint-checkpoint-$(date +%s)"`
- Store stash reference for potential rollback
- Display: "Created safety checkpoint for rollback"

### Stage 1: Biome Auto-Fix (Standard)
- Detect Biome configuration (biome.json)
- If not configured: Skip to Phase 0.5
- If configured:
  - Run pre-fix scan: `biome check .` to establish baseline
  - Parse output: Extract error count, warning count, fixable issue count
  - Auto-fix all fixable issues: `biome check --fix`
  - Re-verify: Run `biome check .` again
  - Type safety check: `npx tsc --noEmit --skipLibCheck` (if TypeScript)
  - If type errors introduced: Offer rollback
  - Display Stage 1 results

#### ZERO-TOLERANCE LINT POLICY (MANDATORY — FIX ALL ERRORS)

**There is NO "pre-existing noise" exception.** ALL lint errors in the project must reach 0 before shipping. If `biome check .` reports errors in ANY file (src/, dist/, tools/, anywhere), they MUST be fixed or the biome config must be updated to properly exclude non-source paths.

**Step 1: Ensure biome.json excludes build output and non-source files**
```bash
# biome.json MUST have files.includes that scopes to source only:
# "files": { "includes": ["src/**", "*.ts", "*.json"] }
# This prevents dist/, node_modules/, and tool output from being checked

# If CSS files trigger false positives (e.g., @tailwind directives):
# "css": { "linter": { "enabled": false } }

# If specific files have safe patterns (e.g., Layout.tsx with static dangerouslySetInnerHTML):
# Use "overrides" to suppress specific rules for specific files
```

**Step 2: Fix ALL remaining source errors — no exceptions**
```bash
# Run biome on entire project
npx biome check .

# Common fixes that must be applied:
# - Missing key props in .map() → add key={uniqueValue}
# - dangerouslySetInnerHTML with static content → suppress via overrides in biome.json
# - @tailwind directives → disable CSS linter in biome.json
# - Formatting issues → npx biome check --fix .
```

**Decision rule:** `biome check .` MUST return `0 errors` before proceeding. NOT "0 errors in changed files" — 0 errors TOTAL. Pre-existing issues are bugs that must be fixed NOW, not deferred.

### Stage 2: AI-Powered Manual Fix (INTELLIGENT — NO LIMIT)
**Trigger**: If errors remain after Stage 1

1. **Parse ALL Remaining Errors**: Extract structured error data with file path, line number, rule ID, message, severity

2. **Intelligent Fixing Loop** (NO ARTIFICIAL LIMIT — fix ALL errors):
   - For each unfixed error:
     a. Read file with context (line +/- 15 lines)
     b. Analyze the specific lint rule violation
     c. Generate compliant fix that maintains functionality
     d. Apply fix using Edit tool
     e. Verify fix: Run `biome check [file]`
     f. Type safety re-check (if TypeScript)
     g. Rollback if new errors introduced, try alternative fix approach
     h. Display progress: "Fixed N/TOTAL lint errors"
   - **For config-level fixes** (false positives from build output, CSS, or safe patterns):
     a. Update biome.json to exclude paths or suppress rules via overrides
     b. Verify the suppression is justified (safe static content, build artifacts, third-party snippets)

3. **Track Results**: AI_FIXED_COUNT — must equal TOTAL_ERRORS

### Stage 3: Final Verification & Decision
- Run final comprehensive check: `biome check .`
- **REQUIRED: 0 errors, 0 warnings**
- **If 0 errors remain**: Clean up checkpoint, continue to Phase 0.5
- **If errors remain after all fix attempts**:
  - **BLOCK** deployment — do NOT offer `--allow-lint-errors` as first option
  - Display remaining errors with file:line and specific fix instructions
  - Attempt another round of fixes before suggesting override

### Stage 1.5: npm audit / Security Auto-Fix (MANDATORY — ZERO VULNERABILITIES)

**Run IMMEDIATELY after lint fixes, BEFORE proceeding to Phase 0.5.**

```bash
# Step 1: Run audit
npm audit 2>&1

# Step 2: If vulnerabilities found, auto-fix
npm audit fix 2>&1

# Step 3: If audit fix didn't resolve all, update packages directly
# For each remaining vulnerability:
#   npm install <package>@latest
#   OR npm install <package>@<fixed-version>

# Step 4: Verify
npm audit 2>&1  # MUST show "found 0 vulnerabilities"

# Step 5: If STILL not zero, use overrides for transitive deps:
# Add to package.json: "overrides": { "<pkg>": ">=<fix_version>" }
# Then: npm install
```

**Decision rule:** `npm audit` MUST return `found 0 vulnerabilities` before proceeding. If a vulnerability has a fix version available, it MUST be applied. No exceptions for LOW/MEDIUM — fix them ALL.

---

## Phase 0.5: DEPLOYMENT RATE LIMIT CHECK (VERCEL PROTECTION)

- Check if project has Vercel deployment (vercel.json exists)
- If Vercel project detected:
  - Check deployment count from last 4 hours
  - Categorize risk level:
    - < 5 deployments: SAFE
    - 5-10 deployments: CAUTION - Warn, ask confirmation
    - 10-20 deployments: WARNING - Strong warning, ask confirmation
    - 20+ deployments: CRITICAL - **BLOCK** deployment
  - If rate limited: Display bypass URL, estimated wait time, offer --force-override
- If not Vercel project: Skip to Phase 1

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

### PROJECT-SPECIFIC TEST SUITES (AUTO-DETECT)

After the generic `vitest run --changed` pass, auto-detect and run any project-specific test suites from `package.json`. Each is BLOCKING.

```bash
# Auto-detect available test scripts and run them
for SCRIPT in test:worker test:docuseal test:integration; do
  if grep -q "\"$SCRIPT\"" package.json 2>/dev/null; then
    echo "Running $SCRIPT..."
    timeout 60 npx vitest run $(node -e "console.log(JSON.parse(require('fs').readFileSync('package.json','utf8')).scripts['$SCRIPT'].replace('vitest run ',''))" 2>/dev/null) 2>&1
    EXIT=$?; pkill -f vitest 2>/dev/null
    if [ $EXIT -ne 0 ]; then
      echo "BLOCK: $SCRIPT failed (exit $EXIT)"
    fi
  fi
done

# ESLint a11y (if configured)
if grep -q '"lint:a11y"' package.json 2>/dev/null; then
  timeout 60 npx eslint "src/react-app/**/*.{ts,tsx}" 2>&1
fi

# Module-scope throw check (React apps)
if [ -d "src/react-app" ]; then
  MATCHES=$(grep -rn "^throw \|^  throw " src/react-app/ --include="*.ts" --include="*.tsx" \
    | grep -v ".test." | grep -v "node_modules" \
    | grep -v "main.tsx.*Root element" | grep -v "utils/api.ts" || true)
  if [ -n "$MATCHES" ]; then
    echo "BLOCK: Found throw at module scope in react-app"
    echo "$MATCHES"
  fi
fi
```

**Post-deploy production tests** (run in Phase 4.1 after deployment):
```bash
# If project has production integration tests, run them after deploy
if grep -q '"test:integration:prod"' package.json 2>/dev/null; then
  timeout 60 TEST_BASE_URL=$DEPLOY_URL npx vitest run tests/worker-integration.test.ts 2>&1
  pkill -f vitest 2>/dev/null
  # WARN if fails (already deployed, but flag for investigation)
fi
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

---

## Phase 1.25: SECURITY AUDIT (BLOCKING — ZERO VULNERABILITIES REQUIRED)

**Purpose**: Ensure ZERO known security vulnerabilities exist before deployment. Not "zero critical" — ZERO total.

- Auto-detect package manager and run appropriate audit command
- **If ANY vulnerabilities found: AUTO-FIX immediately, do NOT just report them**
- Parse audit output: Extract vulnerabilities by severity (LOW, MODERATE, HIGH, CRITICAL)
- Display vulnerability report table

### Aggressive Auto-Fix Protocol (MANDATORY)

```bash
# Step 1: Run audit
npm audit 2>&1

# Step 2: Auto-fix what npm can handle
npm audit fix 2>&1

# Step 3: For remaining vulnerabilities, update packages directly
# Extract vulnerable packages and their fix versions from audit output
# For each: npm install <package>@latest (or @<specific-fix-version>)

# Step 4: For transitive dependency vulnerabilities that npm audit fix can't reach:
# Add "overrides" to package.json: { "<vulnerable-pkg>": ">=<fix-version>" }
# Then: npm install

# Step 5: Verify ZERO vulnerabilities
npm audit 2>&1  # MUST show "found 0 vulnerabilities"

# Step 6: Verify build still works after updates
npm run build 2>&1
```

**The goal is 0 vulnerabilities, not "acceptable risk".** Every vulnerability with an available fix MUST be patched before shipping. This includes LOW severity — they accumulate and signal neglect to security scanners.

### Dependabot Auto-Fix (MANDATORY — BLOCKING)

**ALWAYS check and fix Dependabot alerts before deploying.** This is not optional. If `git push` output shows "GitHub found N vulnerabilities", this gate MUST resolve them before proceeding.

**Step 1: Check for open alerts**
```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/${REPO}/dependabot/alerts" --jq '.[] | select(.state=="open") | "\(.number): \(.security_advisory.severity) — \(.security_advisory.summary) (\(.dependency.package.name)@\(.security_vulnerability.vulnerable_version_range) → fix: \(.security_vulnerability.first_patched_version.identifier))"'
```

**Step 2: For each open alert, auto-fix**
```bash
# Get fix version for each alert
ALERT_DATA=$(gh api "repos/${REPO}/dependabot/alerts" --jq '.[] | select(.state=="open") | {num: .number, pkg: .dependency.package.name, fix: .security_vulnerability.first_patched_version.identifier, vuln: .security_vulnerability.vulnerable_version_range, manifest: .dependency.manifest_path}')

# Detect package manager
if [ -f pnpm-lock.yaml ]; then PKG_MGR="pnpm"; fi
if [ -f package-lock.json ]; then PKG_MGR="npm"; fi
if [ -f bun.lock ]; then PKG_MGR="bun"; fi

# For each vulnerable package:
# 1. Add override in package.json
#    - npm: "overrides" → {"pkg@vuln_range": ">=fix_version"}
#    - pnpm: "pnpm.overrides" → {"pkg@vuln_range": ">=fix_version"}
# 2. Run install: pnpm install / npm install / bun install
# 3. Verify: grep the lockfile for the fixed version
# 4. Build test: npm run build
# 5. Commit: "fix: patch <pkg> <CVE> (Dependabot #N)"
```

**Step 3: Verify fix took effect**
```bash
# Check lockfile has the patched version
grep "<package_name>" pnpm-lock.yaml | head -5  # or package-lock.json

# Verify alert auto-closed (GitHub scans lockfile on push)
gh api "repos/${REPO}/dependabot/alerts/<N>" --jq '.state'
# Should return "fixed" after push
```

### Decision Logic
- **If 0 open alerts**: Continue
- **If alerts exist with available fix**: **AUTO-FIX** (add override, install, verify, commit)
- **If alert has no fix available**: WARN, document in commit, continue
- **If fix breaks build**: Revert override, WARN, document as known issue
- **NEVER skip or ignore HIGH/CRITICAL alerts with available fixes**

### Override handling
- `--allow-security-low`: Allow LOW severity, block MODERATE+
- `--force-security-override`: Override ALL (requires --reason argument)
- Log all overrides to audit trail

---

## Phase 1.26: CODE SCANNING HYGIENE (AUTO-FIX)

**Purpose**: Detect and auto-fix the three categories of code scanning alerts (OpenSSF Scorecard, DevSkim, dependency advisories) before they accumulate.

### Step 1: Check for GitHub Code Scanning
```bash
# Only run if repo has code scanning enabled
ALERT_COUNT=$(gh api repos/{owner}/{repo}/code-scanning/alerts --jq '[.[] | select(.state=="open")] | length' 2>/dev/null || echo "0")
```

If `ALERT_COUNT > 0` or repo has `.github/workflows/` with scanning workflows, proceed.

### Step 2: Token Permissions (OpenSSF Scorecard)
```bash
# Check all workflow files for overly broad permissions
for f in .github/workflows/*.yml; do
  # Flag: no top-level permissions block
  grep -q "^permissions:" "$f" || echo "WARN: $f missing top-level permissions"
  # Flag: write-all at top level
  grep -q "permissions:.*write-all" "$f" && echo "BLOCK: $f has write-all"
  # Flag: security-events or contents at top level when should be job-level
  grep -B1 "security-events: write" "$f" | grep -q "^permissions:" && echo "WARN: $f has security-events:write at top level"
done
```

**Auto-fix**:
- Add `permissions: contents: read` (or `read-all`) at top level of every workflow
- Move write permissions to job level only where genuinely needed
- `security-events: write` → job level for scan upload jobs
- `contents: write` → job level for release/asset upload jobs only

### Step 3: Dependency Vulnerabilities (RUSTSEC / npm audit)
```bash
# Auto-detect project type and run audit
if [ -f Cargo.toml ]; then cargo audit 2>&1; fi
if [ -f package.json ]; then npm audit --omit=dev 2>&1; fi
if [ -f requirements.txt ]; then pip-audit 2>&1; fi
```

**Auto-fix**:
- If fix available: update the dependency
- If informational (unmaintained): migrate to maintained alternative if <20 code changes; otherwise add ignore with rationale and 1-year expiry
- ALWAYS prefer maintained alternatives over ignoring

### Step 4: TODO/FIXME/HACK Comments (DevSkim)
```bash
# Scan source files for flagged comments
grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.rs" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" --include="*.go" src/ 2>/dev/null
```

**Auto-fix**:
- Already done → DELETE the comment
- Trivial improvement → IMPLEMENT it
- Future work → Convert to `NOTE:` with context
- Known limitation → Convert to `NOTE: Known limitation:`

### Decision Logic
- **If 0 issues found**: Continue to Phase 1.3
- **If only TODOs**: Auto-fix inline, continue
- **If workflow permission issues**: Auto-fix, continue
- **If dependency vuln with fix**: Auto-fix, re-run Phase 1 to verify
- **If dependency vuln without fix**: Display warning, log to audit trail, continue

---

## Phase 1.3: REACT SCOPE & ENV SAFETY CHECKS

**Purpose**: Prevent "X is not defined" production crashes and silent React startup failures.

**1. React Scope Check** — Find child components referencing parent scope:
```bash
# Child components referencing parent scope (potential crash)
grep -rn "const.*= (" --include="*.tsx" src/ | grep -v "export" | head -20
# JSX using variables without optional chaining (null crash)
grep -rn "{[a-z][a-zA-Z]*\.[a-z]" --include="*.tsx" src/ | grep -v "\?." | head -20
# Nested component definitions (anti-pattern)
grep -B2 "return.*<" --include="*.tsx" src/ | grep "const.*= () =>" | head -10
```
- If scope issues found: WARN with file:line locations

### Common Bug Pattern
```tsx
// WILL CRASH IN PRODUCTION
const Parent = ({ data }) => {
  const Card = ({ title }) => (
    <div>
      <h3>{title}</h3>
      {data.items.map(...)}  // BUG: 'data' not passed to Card!
    </div>
  );
  return <Card title="Report" />;
};

// CORRECT
const Card = ({ title, items }) => (
  <div>
    <h3>{title}</h3>
    {items?.map(...)}
  </div>
);
const Parent = ({ data }) => <Card title="Report" items={data?.items} />;
```

**2. Env Validation Check** — Ensure env validation won't kill React before mount:
```bash
# Check validateClientEnv is called WITH fallbacks
grep -A2 "validateClientEnv" src/react-app/App.tsx
# Check for module-level throws (kills React before mount, zero console errors)
grep -n "throw" src/react-app/App.tsx
```
- If `validateClientEnv()` called without fallbacks for vars with hardcoded defaults: **BLOCK**
- If bare `throw` at module scope outside functions: **BLOCK**

---

## Phase 1.35: useEffect ABUSE CHECK

**Purpose**: Prevent unnecessary `useEffect` usage. `useEffect` is ONLY for synchronizing with external systems (browser APIs, third-party widgets, network requests). All other uses are anti-patterns that cause extra render cycles, sync bugs, and stale closures.

**1. Scan for useEffect in changed files:**
```bash
# List all useEffect occurrences in changed files
git diff --name-only HEAD~1 -- '*.tsx' '*.ts' | xargs grep -n "useEffect" 2>/dev/null
```

**2. Flag these anti-patterns (each is a WARN):**

| Anti-Pattern | Detection | Fix |
|-------------|-----------|-----|
| Derived state in useEffect | `useEffect(() => { setX(compute(y)) }, [y])` | Compute during render: `const x = compute(y)` |
| Event logic in useEffect | `useEffect(() => { if (changed) doThing() }, [val])` | Move to event handler |
| Previous value tracking via useRef+useEffect | `useEffect(() => { prevRef.current = val }, [val])` | `[prev, setPrev] = useState(val)` + compare during render |
| Reset state on prop change | `useEffect(() => { setState(null) }, [prop])` | Key the component or compare during render |
| Data fetching in useEffect | `useEffect(() => { fetch(...) }, [])` | TanStack Query / SWR / React 19 `use()` |
| Copying server data to local state | `useEffect(() => setTodos(data), [data])` | Use query result directly as source of truth |

**3. Valid useEffect uses (DO NOT flag):**
- `addEventListener` / `removeEventListener` (external browser API)
- Third-party widget init/destroy (external system)
- `IntersectionObserver` / `ResizeObserver` (external browser API)
- WebSocket connect/disconnect (external network)
- `document.title` update (external browser API)
- `localStorage` read on mount in App.tsx (external storage sync)

**Decision rule:** If any useEffect in changed files does NOT synchronize with an external system, WARN with the file:line and suggested fix. Not a deploy blocker, but must be flagged.

---

## Phase 1.4: SEO & SITEMAP CONSISTENCY CHECKS

**Purpose**: Prevent SEO fallback FOUC and sitemap/indexing conflicts.

**1. FOUC Check** — SEO fallback must be CSS-hidden by default:
```bash
# Must show display: none WITHOUT JS dependency
grep -A3 "\.seo-fallback" index.html | grep "display.*none"
# Anti-pattern: JS-dependent hiding
grep "data-app-loaded\|data-loaded\|data-hydrated" index.html
# Noscript override for no-JS users
grep -A2 "<noscript>" index.html | grep "seo-fallback"
```
- If SEO fallback visibility depends on JS: **BLOCK**

**2. Sitemap Consistency Check** — No noindex/auth pages in sitemap, sources must match:
```bash
# Check for noindex pages listed in sitemap
for url in $(grep -oP '<loc>\K[^<]+' public/sitemap.xml 2>/dev/null); do
  path=$(echo "$url" | sed 's|https://[^/]*||'); [ -z "$path" ] && path="/"
  if grep -A2 "\"$path\"" src/worker/seo/page-metadata.ts 2>/dev/null | grep -q "noindex.*true"; then
    echo "CONFLICT: $path has noindex but is in sitemap"
  fi
done
# Compare worker hardcoded sitemap vs public sitemap
diff <(grep -oP '<loc>\K[^<]+' src/worker/index.ts 2>/dev/null | sort) \
     <(grep -oP '<loc>\K[^<]+' public/sitemap.xml 2>/dev/null | sort)
# Trailing slashes cause redirects (not homepage)
grep -oP '<loc>\K[^<]+' public/sitemap.xml src/worker/index.ts 2>/dev/null | grep -E '[^/]/$'
# Auth pages should NOT be in sitemap
grep -oP '<loc>\K[^<]+' public/sitemap.xml src/worker/index.ts 2>/dev/null | grep -E 'sign-in|sign-up|dashboard|admin'
```
- If noindex page in sitemap: **BLOCK** — remove from sitemap
- If sitemaps out of sync: **BLOCK** — sync them
- If trailing slashes on non-homepage: WARN — causes redirect issues
- If auth pages in sitemap: **BLOCK** — remove them

---

## Phase 1.42: DEPLOY SESSION INVALIDATION CHECK (SPA + Cloudflare)

**Purpose**: Prevent users from being logged out after every deployment. When Wrangler deploys new assets, JS chunk filenames change. If SPA fallback returns HTML for missing `.js` files, React crashes and auth session is lost.

**1. Chunk Load Recovery Check** — Verify client-side recovery exists:
```bash
# Must have vite:preloadError handler in main.tsx
grep "vite:preloadError" src/react-app/main.tsx
# Must have ChunkLoadError detection in ErrorBoundary
grep -E "ChunkLoadError|dynamically imported module" src/react-app/components/ErrorBoundary.tsx
# Must have sessionStorage loop-prevention flag
grep "chunk-reload" src/react-app/main.tsx src/react-app/components/ErrorBoundary.tsx
```
- If no `vite:preloadError` handler: **BLOCK** — users will lose session on every deploy
- If no ErrorBoundary chunk detection: WARN — secondary defense missing

**2. CDN Cache Header Check** — Verify edge cache doesn't serve stale HTML:
```bash
# Must have CDN-Cache-Control: no-store on HTML responses
grep "CDN-Cache-Control" src/worker/middleware/securityHeaders.ts
# Verify live
curl -sI "$DEPLOY_URL" | grep -i "cdn-cache-control"
```
- If no `CDN-Cache-Control: no-store`: **BLOCK** — CF edge will cache stale HTML with old chunk refs

**3. SPA Fallback Awareness**:
- `not_found_handling: "single-page-application"` in wrangler.json means missing `.js` files return HTML 200 (not 404)
- This is required for client-side routing but causes the chunk crash bug
- The client-side recovery (vite:preloadError + ErrorBoundary) is the mitigation — it MUST exist

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

---

## Phase 2: MANUAL OVERRIDE PATH

- Accept override ONLY with explicit --force-override flag plus --reason argument
- Display prominent warning about bypassing quality gates
- Require additional user confirmation with clear [YES/NO] prompt
- Log override event with timestamp, reason, and user identifier
- Prefix commit message with [OVERRIDE] marker for audit trail

---

## Phase 3: GITHUB DEPLOYMENT

- Stage all changes with git add
- Generate descriptive commit message based on what was executed:
  - Include test pass count
  - Include lint fix statistics (auto-fixed, AI-fixed, remaining)
  - Include verification status if Phase 1.5 ran
  - Include override markers if any flags used
- Display git diff summary showing what will be pushed
- Require explicit user confirmation: [CONFIRM PUSH] or [CANCEL]
- Push to current branch using git push origin
- Verify push success using gh CLI commands
- Store COMMIT_SHA and TEST_RESULTS for Phase 3.5

---

## Phase 3.5: README & CHANGELOG AUTO-UPDATE

**Execution**: ONLY if Phase 1 tests passed 100%

### How It Works

1. Check if `README.md` exists and has a `## Latest Changes` section
2. If no such section exists, create one after the first heading
3. Find the last commit hash mentioned in the changelog
4. Collect all commits since that last documented commit
5. Group related commits by date
6. Prepend new entries at the top (newest first)

### Entry Format
```markdown
### <Date> - <commit message summary> (Commit: <short-hash>)
- Bullet point describing each meaningful change
- Tests: X passed, Y failed (if tests were run)
- Commit: <short-hash> ([View on GitHub](https://github.com/<owner>/<repo>/commit/<short-hash>))
```

### Auto-Detection
```bash
REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
LAST_HASH=$(grep -oP 'Commit: \K[a-f0-9]{7}' README.md | head -1)
git log --format="%h %ad %s" --date=short ${LAST_HASH}..HEAD
```

### Rules
- Always run this gate — even for small changes
- Skip docs-only commits (avoid infinite loops)
- Max 20 entries — archive older entries
- Commit and push as separate commit: `docs: update Latest Changes with <commit-hash> deploy`
- **If README update fails: BLOCK Phase 4 deployments**

---

## Phase 4: DOWNSTREAM DEPLOYMENTS

**Deployment Target Logic**:
- **Default (no flags)**: Deploy to PRODUCTION
- **`--staging` or "to staging first"**: Deploy to staging, then prompt for production promotion
- **`--staging-only`**: Deploy to staging only

### VERCEL DEPLOYMENT (if vercel.json exists)

**Production Deployment (DEFAULT)**:
1. Pre-deployment Check: Verify CLI and authentication
2. Execute Deployment: `vercel deploy --prod --yes`
3. Verify Deployment Success: Check exit code, parse output
4. Health Check: Wait 10s, HTTP GET with 3 retries
5. Report Status with URL, deployment ID, response time

**Staging/Preview Deployment (if --staging)**:
1. Execute Preview Deployment: `vercel deploy --yes` (no --prod flag)
2. Health Check: Wait 10s, HTTP GET to preview URL
3. Display staging URL prominently
4. **If "staging first" mode**: Ask user to verify staging, then confirm production promotion
5. **On promotion confirmation**: Run production deployment (`vercel deploy --prod --yes`)

### CLOUDFLARE DEPLOYMENT (if wrangler.toml/json exists)

**Step 0: Detect Deployment Type** — CF Workers vs CF Pages:
```bash
# CF Pages: has pages_build_output_dir in wrangler.toml
grep -q "pages_build_output_dir" wrangler.toml 2>/dev/null && echo "CF_PAGES" || echo "CF_WORKERS"
# Also check for npm run deploy script
grep -q '"deploy"' package.json 2>/dev/null && echo "HAS_DEPLOY_SCRIPT"
```

**Step 1: Auth Verification** — CF has multiple auth methods that conflict:
```bash
# Check for CLOUDFLARE_API_TOKEN in .env files (wrangler loads these via dotenv!)
grep -rn "CLOUDFLARE_API_TOKEN" .env .env.local .env.production 2>/dev/null

# Check wrangler OAuth config
cat ~/.wrangler/config/default.toml 2>/dev/null | grep "scopes"

# Test: does wrangler whoami work?
npx wrangler whoami 2>&1 | head -5
```

**CRITICAL: `.env.local` Token Override Bug**
Wrangler auto-loads `.env.local` via dotenv. If `.env.local` has `CLOUDFLARE_API_TOKEN` with limited permissions, it OVERRIDES the wrangler OAuth token (which may have full permissions including `pages:write`). Symptoms:
- `wrangler pages deploy` fails with "Authentication error [code: 10000]"
- `wrangler whoami` says "authenticating via custom API token"
- But `~/.wrangler/config/default.toml` has `pages:write` in scopes

**Fix**: Remove or comment out `CLOUDFLARE_API_TOKEN` from `.env.local` if the OAuth token has the right permissions. The OAuth token in `~/.wrangler/config/default.toml` is the preferred auth method.

**Step 2: Deploy** (CF Pages):
```bash
# Preferred: use project's deploy script (handles build + deploy)
npm run deploy:full 2>&1  # build + deploy in one command
# OR: just deploy pre-built dist/
npm run deploy 2>&1       # wrangler pages deploy dist
```

If no deploy script exists:
```bash
npm run build && npx wrangler pages deploy dist --project-name=$(grep '^name' wrangler.toml | head -1 | sed 's/.*= *"//;s/"//')
```

**Step 2 (CF Workers — no pages_build_output_dir)**:
```bash
npm run deploy 2>&1  # OR: npx wrangler deploy
```

**Step 3: Verify Deployment Success**:
```bash
# Check exit code from deploy command
# Parse deployment URL from output (e.g., "https://abc123.project.pages.dev")
# Health check production URL
sleep 3
curl -sI "$DEPLOY_URL" | head -5

# CRITICAL: Verify version.json shows current commit (not stale "dev")
curl -s "$DEPLOY_URL/version.json" 2>/dev/null
# Should show: current commit SHA, "production" environment, recent timestamp
# If shows "dev" or old timestamp: version.json is cached or not regenerated during build
```

**Step 4: Version Freshness Check**:
```bash
# Compare deployed version with local git
DEPLOYED_SHA=$(curl -s "$DEPLOY_URL/version.json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('commitSha','unknown')[:7])" 2>/dev/null)
LOCAL_SHA=$(git rev-parse --short HEAD)
if [ "$DEPLOYED_SHA" = "$LOCAL_SHA" ]; then
  echo "✓ Deployed version matches local HEAD"
else
  echo "⚠ Version mismatch: deployed=$DEPLOYED_SHA local=$LOCAL_SHA"
  echo "  CF Pages may still be building, or version.json is cached"
fi
```

**Common CF Pages Deployment Failures**:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Auth error 10000 | `.env.local` has broken `CLOUDFLARE_API_TOKEN` | Remove from `.env.local`, use wrangler OAuth |
| version.json shows "dev" | Committed to git with local values | Add to `.gitignore`, generate at build time |
| Old version after deploy | Service worker caches version.json | Add to SW `NETWORK_ONLY_PATTERNS` |
| CDN serves stale version.json | No cache-control header | Add `Cache-Control: no-store` in `_headers` |
| No auto-deploy on push | No GitHub integration configured | Set up in CF Dashboard or use `npm run deploy` |

**Staging Deployment (if --staging)**:
1. Check for staging environment in wrangler.toml: `[env.staging]`
2. If staging env exists: `wrangler deploy --env staging`
3. If no staging env: `wrangler pages deploy dist --branch preview`
4. **If "staging first" mode**: Ask user to verify, then confirm production promotion

### DOCKER DEPLOYMENT (if Docker credentials configured)
- Push to Docker registry: `docker push`
- Verify push success
- Report registry URL and image tag

### Cloudflare API Access (MCP)

The `cloudflare-api` MCP server provides full access to ~2,500 Cloudflare API endpoints. Use during deployment for operations beyond what `wrangler` CLI covers:
- DNS records, redirects, firewall rules
- Zone settings, SSL, cache config
- KV/D1/R2 operations during deploy verification

| Task | Use |
|------|-----|
| Deploy Worker code | `wrangler deploy` |
| Tail logs | `wrangler tail` |
| DNS, redirects, firewall | **Cloudflare MCP** |
| Zone settings, SSL, cache | **Cloudflare MCP** |

### DEPLOYMENT SUMMARY
Display comprehensive summary table with platform name, environment, status, live URL, response time.

---

## Phase 4.1: POST-DEPLOY VERIFICATION

**Purpose**: Verify production deployment serves correct content after deploy.

### Part 0: Chrome CDP Live Screenshot (if available)

After deploy, take a screenshot of the live production site to visually verify:

```bash
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"
TARGET=$($CDP list 2>/dev/null | grep "$DEPLOY_URL" | awk '{print $1}' | head -1)

if [ -n "$TARGET" ]; then
  # Reload the page to pick up new deploy
  $CDP nav "$TARGET" "$DEPLOY_URL" 2>/dev/null
  sleep 3
  $CDP shot "$TARGET" 2>/dev/null
  echo "Screenshot saved to /tmp/screenshot.png — verify visually"
else
  echo "No Chrome tab open for $DEPLOY_URL — skipping visual check"
fi
```

If a tab is open and CDP daemon is warm, this gives instant visual verification with no popups. If not available, skip to curl checks.

### Part A: HTML Meta Tag Checks (curl)
```bash
# Verify twitter meta tags use name= (Twitter ignores property=)
curl -s "$DEPLOY_URL" | grep -i "twitter:" | head -10
# Verify og:image URL returns image content-type
OG_URL=$(curl -s "$DEPLOY_URL" | grep -oP 'og:image" content="\K[^"]+')
curl -sI "$OG_URL" | grep -E "^(HTTP|content-type)"
# Verify cache-bust param exists on image URLs
curl -s "$DEPLOY_URL" | grep -oP '(og|twitter):image" content="\K[^"]+'
```
- If `property=` on twitter tags: WARN — Twitter ignores them
- If no `?v=` param on image URLs: WARN — social platforms cache old images
- If image URL returns 404: Report error

### Part B: Visual Verification via agent-browser (CDP) — MANDATORY
```bash
# Open OG preview service
agent-browser open "https://www.opengraph.xyz"
sleep 2
agent-browser snapshot -i -c
agent-browser fill "@eN" "https://yourapp.example.com"
agent-browser press Enter
sleep 5
agent-browser screenshot --path /tmp/og-preview-twitter.png
agent-browser scroll down 500
agent-browser screenshot --path /tmp/og-preview-full.png

# Also screenshot direct OG image
agent-browser open "https://yourapp.example.com/images/og-social-card.png?v=20260306"
sleep 2
agent-browser screenshot --path /tmp/og-image-direct.png

# Trigger Twitter re-scrape
agent-browser open "https://x.com/intent/tweet?text=https://yourapp.example.com"
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
curl -s -H "User-Agent: Twitterbot/1.0" -o /tmp/served.png "$(curl -s -H 'User-Agent: Twitterbot/1.0' https://yourapp.example.com/ | grep -oP 'twitter:image" content="\K[^"]+')"
# Compare: if different = cache issue (add ?v=), if same = image file needs updating
```

### Two Cache Layers (Critical)
| Layer | What | Bust With |
|-------|------|-----------|
| **Page metadata** | og:image URL for page | Card Validator or `?v=N` on page URL |
| **Image CDN** | Image bytes at CDN | `?v=YYYYMMDD` on image URL in meta tags |

### Production Integration Tests (post-deploy)
```bash
# If project has production integration tests, run them against live site
if grep -q '"test:integration:prod"' package.json 2>/dev/null; then
  timeout 60 TEST_BASE_URL=$DEPLOY_URL npx vitest run tests/worker-integration.test.ts 2>&1
  pkill -f vitest 2>/dev/null
  # WARN if fails (already deployed) — flag for investigation, do not auto-rollback
fi
```

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

## Phase 4.3: WEB PERFORMANCE AUDIT (POST-DEPLOY)

**Purpose**: Baseline and monitor Core Web Vitals after every production deploy. Catches performance regressions before users notice.

**Trigger**: After successful deployment (Phase 4 complete). Runs automatically.

**Execution**: Use the `/web-perf` skill via Chrome DevTools MCP to measure production performance.

```
1. Open production URL in headless Chrome
2. Run Lighthouse audit (Performance category)
3. Capture Core Web Vitals:
   - FCP (First Contentful Paint) — target: < 1.8s
   - LCP (Largest Contentful Paint) — target: < 2.5s
   - TBT (Total Blocking Time) — target: < 200ms
   - CLS (Cumulative Layout Shift) — target: < 0.1
   - Speed Index — target: < 3.4s
4. Compare against previous baseline (if stored)
5. Flag regressions > 20% from baseline
```

**Display format**:
```
── Phase 4.3: Web Performance ──
┌────────┬──────────┬────────┬────────────┐
│ Metric │ Current  │ Target │ Status     │
├────────┼──────────┼────────┼────────────┤
│ FCP    │ 1.2s     │ < 1.8s │ ✓ PASS     │
│ LCP    │ 2.1s     │ < 2.5s │ ✓ PASS     │
│ TBT    │ 150ms    │ < 200ms│ ✓ PASS     │
│ CLS    │ 0.05     │ < 0.1  │ ✓ PASS     │
│ Score  │ 85       │ > 70   │ ✓ PASS     │
└────────┴──────────┴────────┴────────────┘
```

**Decision logic**:
- Lighthouse score < 50: **WARN** — severe regression, consider rollback
- Lighthouse score 50-70: **WARN** — investigate before next deploy
- Lighthouse score > 70: PASS
- Any metric regression > 50% from previous: **WARN**

**Fallback**: If Chrome DevTools MCP is unavailable, skip with message: "Web perf audit skipped — run `/web-perf` manually to baseline."

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

**Using Chrome CDP (preferred — uses live session)**:
```bash
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"
TARGET=$($CDP list 2>/dev/null | grep "$DEPLOY_URL" | awk '{print $1}' | head -1)

if [ -n "$TARGET" ]; then
  $CDP nav "$TARGET" "$DEPLOY_URL"
  sleep 3

  # Desktop screenshot
  $CDP shot "$TARGET"  # saves to /tmp/screenshot.png
  # Read the screenshot to check for visual issues

  # For mobile: use agent-browser with viewport setting
  agent-browser open "$DEPLOY_URL" --viewport 375x812
  agent-browser screenshot --path /tmp/mobile-screenshot.png
  agent-browser close
fi
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
── Phase 6: PR Babysitter launched in background ──
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

---

## Pre-Ship Verification Checklist (Non-Negotiable)

Before declaring ANY deploy complete, verify ALL of these:

1. **Bundle hash changed** — `curl -s <URL> | grep 'index-'` must show a NEW hash vs. previous deploy
2. **Page loads correctly** — curl the actual page, verify it returns 200 and contains expected content
3. **API endpoints work** — test at least one authenticated endpoint returns data, not "Unauthorized"
4. **New routes reachable** — if you added a route, verify it doesn't 404 or get swallowed by a catch-all
5. **No stale cache** — if `cf-cache-status: HIT`, verify it's serving the new content not old
6. **Clean build** — for Cloudflare Workers: `rm -rf dist && tsc -b && vite build && wrangler deploy` (never just `wrangler deploy`)
7. **Type definitions correct** — for CF Workers, edit `worker-configuration.d.ts` (ambient), not just `src/worker/env.d.ts` (module)

**If ANY check fails: do NOT say "deployed successfully". Fix it first.**

## Safety Audit Tiers

### Tier 1 — Critical (always runs on deploy)
- Silent failure detection — env vars without validation
- Silent React startup failures — env validation throwing before mount
- Security audit — vulnerabilities, exposed secrets
- Test execution verification

### Tier 2 — Investigation (`--audit tier2`)
Uses `systematic-debugging`:
- Blind spot auditor — edge cases missing test coverage
- Test quality gate — tests that pass but don't verify real behavior
- Rate limit protector — public endpoints missing rate limiting

### Tier 3 — Deep Analysis (`--audit tier3`)
Uses `carmack-mode-engineer`:
- Code archaeology — "old/legacy" code that's actually critical
- Critical systems guard — unprotected auth/payment/data-deletion paths
- Build reproduction harnesses for complex issues

### Full (`--audit full`)
Runs all three tiers in sequence.

---

## Cross-Platform CI Verification (Rust/Multi-Platform PRs)

**For PRs to open source Rust projects with multi-platform CI matrices:**

```bash
# 1. Format check (CI rejects ANY formatting diff)
cargo fmt --all -- --check

# 2. Clippy with warnings-as-errors
cargo clippy --all-targets --all-features

# 3. Check for conditional compilation blind spots
grep -n "let mut" src/**/*.rs | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  var=$(echo "$line" | grep -oP 'let mut \K\w+')
  if grep -A20 "let mut $var" "$file" | grep -q '#\[cfg(target_os'; then
    echo "WARNING: $file — $var may need #[allow(unused_mut)]"
  fi
done
```

After push: `gh pr checks <PR_NUMBER> --watch`

---

## OUTPUT REQUIREMENTS

- Always show clear phase headers marking current stage
- Use visual indicators for success, failure, warnings
- Display progress bars for multi-step operations
- Provide actionable error messages when builds or tests fail
- Show deployment summary table with service name, status, and live URL
- Include estimated time for each phase
- Display comprehensive banners at phase transitions

---

## SAFETY CONSTRAINTS

### Critical Rules:
- **FAIL FAST**: Terminate immediately on build errors or test failures
- **GitHub deployment ALWAYS happens before any other platform**
- **Multiple confirmation gates prevent accidental shipping**
- **All override actions are permanently logged**
- **Never silently skip tests or quality checks**
- **Refuse ambiguous commands that might bypass gates**
- **Data verification is mandatory for risky changes unless explicitly overridden**
- **NEVER execute destructive infrastructure commands** — these require human execution
- **NEVER modify or replace .tfstate files**
- **ALWAYS show terraform plan output to user** before any terraform apply

### Phase-Specific Rules:
- Phase -1: NEVER proceed if not in git repo or remote unreachable
- Phase 1: NEVER run `npm test` or full `npx vitest run` — always use `--changed` and `timeout`
- Phase 1: NEVER retry tests more than 3 times — stop and report failures
- Phase 1: ALWAYS run `pkill -f vitest 2>/dev/null` after every test invocation
- Phase -0: NEVER push or tag during merge conflict resolution
- Phase 0: NEVER deploy with lint errors unless explicit override
- Phase 0.5: BLOCK on 20+ deployments unless --force-override
- Phase 1: BLOCK on ANY test failure
- Phase 1.1: BLOCK if frontend calls API endpoints with no backend handler
- Phase 1.25: BLOCK on MODERATE+ vulnerabilities unless override
- Phase 1.26: WARN on TODO/FIXME/HACK comments in changed files (auto-fix to NOTE:)
- Phase 1.26: WARN on workflow files missing top-level permissions (auto-fix to read-only)
- Phase 1.26: BLOCK on `permissions: write-all` at workflow top level (must narrow to job-level)
- Phase 1.3: BLOCK if env validation throws at module scope without fallbacks
- Phase 1.4: BLOCK if noindex pages appear in sitemap or sitemaps are out of sync
- Phase 1.42: BLOCK if no vite:preloadError handler (deploy will log users out)
- Phase 1.42: BLOCK if no CDN-Cache-Control: no-store header on HTML responses
- Phase 4.2: Run multi-agent review when changes span 3+ files or touch security paths
- Phase 4.2: BLOCK if any reviewer finds CRITICAL security/performance issue
- Phase 4.3: WARN if Lighthouse score drops below 50 (severe perf regression)
- Phase 4.35: BLOCK if mobile screenshot shows blank page (broken rendering)
- Phase 4.35: WARN if mobile screenshot shows horizontal scroll (responsive bug)
- Phase 4: WARN if deployed version.json SHA doesn't match local HEAD (stale deploy)
- Phase 4: BLOCK if `CLOUDFLARE_API_TOKEN` in `.env.local` overrides wrangler OAuth (auth conflict)
- Phase 4: Verify `version.json` is in `.gitignore` and not git-tracked (prevents stale commits)
- Phase 4: Verify service worker has `version.json` in NETWORK_ONLY patterns (prevents SW caching)
- Phase 1.45: BLOCK if critical third-party env vars missing from wrangler config
- Phase 1.45: BLOCK if raw `.innerHTML =` without escapeHtml() (XSS risk — especially entry points outside src/)
- Phase 1.45: BLOCK if dangerouslySetInnerHTML without DOMPurify (XSS risk)
- Phase 1.45: BLOCK if JSON.stringify in script tag without `</` escaping (script breakout)
- Phase 1.45: WARN if async onClick without disabled state (double-click risk)
- Phase 1.45: WARN if pages call secureFetch without frontend auth guard (degraded UX)
- Phase 1.45: WARN if admin routes throw Error instead of HTTPException(403)
- Phase 1.5: NEVER skip verification if migrations/backfills detected
- Phase 3.5: NEVER update README if tests didn't pass 100%
- Phase 4: NEVER report success without URL verification
- Phase 4.5: NEVER auto-rollback without user confirmation
- Phase 6: NEVER merge the PR automatically — only humans merge
- Phase 6: NEVER force-push, dismiss reviews, or override branch protection
- Phase 6: NEVER modify files outside the PR's changeset
- Phase 6: Max 5 fix-push cycles, max 30 min runtime — then exit with report
- Phase 1.5: NEVER run terraform destroy or apply -auto-approve
- Phase 1.5: BLOCK if terraform plan shows resources being destroyed

---

## TONE

Be authoritative and safety-focused. Be firm about quality requirements while remaining helpful when errors occur. Emphasize that quality gates protect the user, their data, and their users. When blocking deployment, clearly explain why and provide specific remediation steps.
