# Pre-Flight Checks (MANDATORY)

## Pre-1: Live Site CDP Warmup (for web projects with a production URL)

Before investigating bugs or verifying fixes on deployed sites, warm up Chrome CDP so you can take screenshots and inspect the live page without the "Allow debugging" popup blocking you:

```bash
# Warm up CDP daemon for production tab (one-time popup, then instant access)
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"

# Find the production tab (adjust URL for the project)
TARGET=$($CDP list 2>/dev/null | grep "your-app.pages.dev\|your-app.com" | awk '{print $1}' | head -1)

# If found, pre-warm the daemon (avoids "Allow" popup on subsequent commands)
if [ -n "$TARGET" ]; then
  $CDP snap "$TARGET" > /dev/null 2>&1 && echo "[CDP] Daemon warm for $TARGET"
fi
```

Then use `$CDP shot $TARGET` to screenshot, `$CDP snap $TARGET` for accessibility tree, `$CDP eval $TARGET "..."` to run JS — all without popups.

## Pre-2: Full Codebase Audit (MANDATORY FOR ALL CHANGES)

Before making ANY change — UI, component, logic, config — you MUST search the entire codebase for every other place the same thing appears. Never assume a change is isolated.

```bash
# IMPORTANT: Always search from project root (.) not just src/
# Entry points (index.tsx, main.tsx), config files, and worker code
# often live outside src/ and are blind spots when scoping to src/ only

# For component changes — find EVERY usage of the component
grep -rn '<ComponentName' --include="*.tsx" . | grep -v node_modules

# For styling changes — find every place the same class/pattern is used
grep -rn 'className.*pattern' --include="*.tsx" . | grep -v node_modules

# For logic/function changes — find every caller
grep -rn 'functionName' --include="*.ts" --include="*.tsx" . | grep -v node_modules

# For config/constant changes — find every reference
grep -rn 'CONSTANT_NAME\|config\.key' --include="*.ts" --include="*.tsx" . | grep -v node_modules

# For security scans — MUST search root for innerHTML, eval, etc.
grep -rn '\.innerHTML\s*=' --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist
```

Apply the change to **ALL** instances found — not just the first one. If you only fix one place and there are 10, you've shipped an incomplete fix. The user will see the bug everywhere except the one place you touched.

**The rule**: If grep finds N instances, your PR must touch all N. Document any intentional exceptions.

## Pre-3: 100% Production Code Coverage Scan (MANDATORY)

When fixing bugs or implementing features, you MUST audit ALL production source files — not just the ones you changed. Zero blind spots means zero surprises in production.

```bash
# Step 1: Count total production files
TOTAL=$(find src/react-app -name "*.tsx" -o -name "*.ts" | grep -v __tests__ | grep -v ".test." | wc -l | tr -d ' ')
echo "Production files to audit: $TOTAL"

# Step 2: After making changes, run progressive scans across ALL files:
# - Pass 1: error handling (console.log, alert, silent catch)
# - Pass 2: security (XSS, secrets, SQL injection)
# - Pass 3: mobile/responsive (vh→dvh, grid breakpoints, hover-only)
# - Pass 4: accessibility (alt text, button types, aria labels)
# - Pass 5: React anti-patterns (useEffect abuse, state mutations)
# - Pass 6: banned colors
# - Pass 7: performance (inline styles, missing keys)
# - Pass 8: worker/backend security (admin auth, CORS, rate limits)
# - Pass 9: error boundaries + loading states
# - Pass 10: final sweep + build verification

# Step 3: Track coverage — report after each pass:
echo "Pass N/10 | Files: Y/$TOTAL (Z%) | Issues: N found, N fixed"

# Step 4: Do NOT consider the task complete until:
# - 100% of production files have been scanned
# - Build passes
# - Biome: 0 errors
# - TypeScript: 0 errors
```

## Pre-4: Zero-Tolerance Lint & Security Auto-Fix (MANDATORY BEFORE COMPLETION)

Before marking ANY task complete, you MUST achieve ZERO lint errors and ZERO security vulnerabilities. This is not optional and applies to ALL errors in the project, not just errors in changed files.

```bash
# LINT: Fix ALL errors to zero — no "pre-existing" exceptions
# This applies to BOTH Biome AND ESLint. Both must reach 0 errors.

# BIOME:
# Step 1: Ensure biome.json properly excludes non-source paths (dist/, node_modules/)
# Step 2: Run biome check --fix . to auto-fix what it can
# Step 3: Manually fix ALL remaining errors (missing keys, formatting, etc.)
# Step 4: Update biome.json overrides for safe patterns (static dangerouslySetInnerHTML, CSS @tailwind)
# Step 5: Verify: npx biome check . → MUST show 0 errors, 0 warnings
npx biome check --fix . 2>&1
npx biome check . 2>&1  # MUST be clean

# ESLINT a11y/React:
# Step 6: Run ESLint on React source
# Step 7: Fix ALL errors using patterns from "ESLint a11y & React Hooks Detection" section
# Step 8: Verify: npx eslint "src/react-app/**/*.{ts,tsx}" → MUST show 0 errors
timeout 60 npx eslint "src/react-app/**/*.{ts,tsx}" 2>&1
# 0 errors required. See "ESLint a11y & React Hooks Detection" table for fix patterns.

# SECURITY: Fix ALL vulnerabilities to zero — no severity exceptions
# Step 1: npm audit → identify all vulnerabilities
# Step 2: npm audit fix → auto-fix what it can
# Step 3: npm install <pkg>@latest for remaining vulns with available fixes
# Step 4: Add "overrides" in package.json for stubborn transitive deps
# Step 5: Verify: npm audit → MUST show "found 0 vulnerabilities"
npm audit fix 2>&1
npm audit 2>&1  # MUST be clean

# Step 6: Verify build still works
npm run build 2>&1
```

**Key rules:**
- "Pre-existing lint noise" is a BUG — fix it, don't skip it
- LOW severity vulnerabilities count — fix them ALL
- If biome reports errors in dist/ or build output, fix biome.json to exclude those paths
- If CSS @tailwind directives trigger lint errors, disable CSS linter in biome.json
- If dangerouslySetInnerHTML is used with safe static content, add an override in biome.json
- The ONLY acceptable final state is: `0 errors, 0 warnings, 0 vulnerabilities`
