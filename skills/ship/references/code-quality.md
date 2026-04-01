# Code Quality - Lint & Audit

Covers Phase 0 (Biome lint auto-fixing, zero-tolerance policy, AI-powered fixing, npm audit).

---

## Phase 0: CODE QUALITY - INTELLIGENT LINT AUTO-FIXING (AI-ENHANCED)

### Stage 0: Git Checkpoint (Safety First)
- Create safety checkpoint: `git stash push -m "pre-lint-checkpoint-$(date +%s)"`
- Store stash reference for potential rollback
- Display: "Created safety checkpoint for rollback"

### Stage 1: Biome Auto-Fix (Standard)
- Detect Biome configuration (biome.json)
- **If not configured: AUTO-SETUP Biome before proceeding** (MANDATORY):
  1. Run `npx @biomejs/biome init` to create biome.json
  2. Configure for the project's tech stack:
     - For React/TSX: ensure JSX support enabled
     - Add `"files": { "ignore": ["dist/", "node_modules/", "*.min.js"] }` to exclude build output
     - If Tailwind CSS: add `"css": { "linter": { "enabled": false } }` to avoid @tailwind false positives
  3. Run `npx @biomejs/biome check --fix .` to auto-fix all fixable issues
  4. Manually fix any remaining errors
  5. Run `npx tsc --noEmit --skipLibCheck` to verify no type regressions
  6. Stage and commit: `git add biome.json && git commit -m "chore: add Biome linter configuration"`
  7. Continue with normal Biome lint flow below
- If configured:
  - Run pre-fix scan: `biome check .` to establish baseline
  - Parse output: Extract error count, warning count, fixable issue count
  - Auto-fix all fixable issues: `biome check --fix`
  - Re-verify: Run `biome check .` again
  - Type safety check: `npx tsc --noEmit --skipLibCheck` (if TypeScript)
  - If type errors introduced: Offer rollback
  - Display Stage 1 results

#### ZERO-TOLERANCE LINT POLICY (MANDATORY — FIX ALL ERRORS)

**There is NO "pre-existing noise" exception.** ALL lint errors from ALL linters in the project must reach 0 before shipping. This applies to BOTH:
- **Biome**: `biome check .` — 0 errors
- **ESLint a11y/React**: `npx eslint "src/react-app/**/*.{ts,tsx}"` — 0 errors

If EITHER tool reports errors, they MUST be fixed. "Pre-existing" errors are NOT an excuse to skip — they are bugs that must be fixed NOW.

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

**Step 2: Fix ALL remaining source errors from BOTH linters — no exceptions**
```bash
# Run biome on entire project
npx biome check .

# Run ESLint a11y on React source
npx eslint "src/react-app/**/*.{ts,tsx}" 2>&1 | grep "error"

# Common biome fixes:
# - Missing key props in .map() → add key={uniqueValue}
# - dangerouslySetInnerHTML with static content → suppress via overrides in biome.json
# - @tailwind directives → disable CSS linter in biome.json
# - Formatting issues → npx biome check --fix .
```

**Step 2b: ESLint a11y/React Auto-Fix Patterns**
```bash
# Common ESLint error patterns and their fixes:

# react-hooks/refs — "Cannot access refs during render"
# Root cause: useInView/useRef hook returns object with .ref and state, accessed as hero.ref/hero.isInView
# Fix: Destructure at call site: const { ref: heroRef, isInView: heroInView } = useInView()
# Then use heroRef and heroInView separately in JSX

# react-hooks/refs — "Cannot update ref during render"
# Root cause: someRef.current = value during render body
# Fix: Move into useEffect(() => { someRef.current = value; }, [value])

# jsx-a11y/no-noninteractive-element-interactions — onLoad on <img>
# onLoad is a media lifecycle event, not a user interaction
# Fix: eslint-disable-next-line jsx-a11y/no-noninteractive-element-interactions

# jsx-a11y/no-noninteractive-tabindex — tabIndex on iframe
# iframes need tabIndex for keyboard navigation
# Fix: Wrap with eslint-disable/enable block with justification comment
```

**Decision rule:** BOTH `biome check .` AND `npx eslint "src/react-app/**/*.{ts,tsx}"` MUST return `0 errors` before proceeding. NOT "0 errors in changed files" — 0 errors TOTAL. Pre-existing issues are bugs that must be fixed NOW, not deferred.

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
