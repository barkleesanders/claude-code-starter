# Security Audit & Code Scanning

Covers Phase 1.25 (security audit with Dependabot auto-fix) and Phase 1.26 (code scanning hygiene).

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
