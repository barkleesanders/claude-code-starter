# Ant-Level Verification Protocol

> Equivalent to Anthropic's internal `USER_TYPE=ant` quality gates.
> Injected into /carmack, /debug, and /ship for parity with Anthropic employee tooling.

---

## 1. SECURITY REVIEW GATE (Equivalent: ant-only `/security-review` command)

**Run on EVERY code change, not just security-tagged work.** The ant-internal `/security-review` triggers a comprehensive security analysis. Replicate it:

### OWASP Top 10 Sweep (MANDATORY)

For every file touched, scan for:

| # | Vulnerability | Detection | Severity |
|---|---------------|-----------|----------|
| A01 | Broken Access Control | Missing auth checks on routes, IDOR via sequential IDs, missing `requireAuth()`/`requireAdmin()` | CRITICAL |
| A02 | Cryptographic Failures | Hardcoded secrets, weak hashing (MD5/SHA1 for passwords), missing HTTPS enforcement | CRITICAL |
| A03 | Injection | SQL string concat, `eval()`, `new Function()`, template literals in HTML, `.innerHTML =`, command injection via `child_process` | CRITICAL |
| A04 | Insecure Design | Missing rate limiting on auth endpoints, no account lockout, enumerable user IDs | HIGH |
| A05 | Security Misconfiguration | Verbose error messages in production, debug endpoints exposed, default credentials | HIGH |
| A06 | Vulnerable Components | Known CVEs in dependencies (`npm audit`), outdated packages with security patches | HIGH |
| A07 | Auth Failures | JWT without expiry, session tokens in URLs, missing CSRF protection, auth state in localStorage | CRITICAL |
| A08 | Data Integrity | Unsigned serialized data, missing input validation at API boundaries, prototype pollution | HIGH |
| A09 | Logging Failures | PII in logs, missing audit trail for admin actions, no log rotation | MEDIUM |
| A10 | SSRF | User-supplied URLs fetched server-side without allowlist, DNS rebinding | HIGH |

### Quick Detection Commands

```bash
# Secrets & credentials
grep -rn "password\s*=\s*['\"]" --include="*.ts" --include="*.js" --include="*.env*" . | grep -v node_modules
grep -rn "sk-\|sk_live\|sk_test\|AKIA\|ghp_\|glpat-\|xox[bpsa]-" . | grep -v node_modules | grep -v ".git/"

# Injection vectors
grep -rn "eval(\|new Function(\|child_process\|exec(\|execSync(" --include="*.ts" --include="*.js" . | grep -v node_modules
grep -rn "\.innerHTML\s*=" --include="*.ts" --include="*.tsx" --include="*.html" . | grep -v node_modules

# Auth gaps
grep -rn "app\.\(get\|post\|put\|delete\|patch\)" --include="*.ts" . | grep -v "auth\|middleware\|require" | grep -v node_modules

# SSRF
grep -rn "fetch(\|axios\.\|http\.get\|https\.get" --include="*.ts" --include="*.js" . | grep -v node_modules | grep -v "localhost\|127\.0\.0\.1"
```

### Verdict Protocol

- **0 CRITICAL findings** → proceed
- **Any CRITICAL finding** → BLOCK deployment, fix inline
- **HIGH findings** → fix inline if possible, WARN if requires architectural change
- **MEDIUM/LOW** → note in commit message, create follow-up issue

---

## 2. TRUTHFULNESS & ACCURACY PROTOCOL (Equivalent: ant system prompt behavior)

> "Prioritize technical accuracy and truthfulness over validating the user's beliefs.
> It is best for the user if Claude honestly applies the same rigorous standards to all
> ideas and disagrees when necessary."

### Rules

1. **Never confirm a fix works without evidence.** Run the code, curl the endpoint, check the logs.
2. **Never say "this should work" — say "this works because [evidence]" or "I haven't verified this yet."**
3. **If the user's assumption is wrong, say so directly.** Don't hedge with "that's a valid approach but..." — say "that won't work because [specific reason]."
4. **If you don't know something, say so.** Don't confabulate documentation, API signatures, or library behavior. Check the source.
5. **If a fix might have side effects, enumerate them.** Don't hide complexity to seem helpful.
6. **Disagree with the user when the evidence supports it.** Being agreeable is not being helpful.

### Verification Checklist (Before Declaring "Done")

```
[ ] Every claim is backed by a command output, file read, or test result
[ ] Every changed file has been re-read to confirm the edit took effect
[ ] Every new endpoint has been curled/tested with actual request
[ ] Every bug fix has a reproduction that FAILS before and PASSES after
[ ] Build succeeds (not just "should succeed")
[ ] No silent failures — checked stderr, not just stdout
```

---

## 3. CLOSED-LOOP VERIFICATION (Equivalent: ant-level rigor)

The ant-internal build enforces closed-loop verification on all code changes. Replicate it:

### For Every Code Change

1. **State the hypothesis** — "I believe X is broken because Y"
2. **Gather evidence** — Read the actual code, don't assume from memory
3. **Implement the fix** — Minimal, surgical change
4. **Verify the fix** — Run the specific test, curl the endpoint, check the log
5. **Verify no regression** — Run adjacent tests, check related functionality
6. **Document the evidence** — Include verification output in the response

### Anti-Patterns to Block

- "I've updated the file" without reading it back to confirm
- "The test should pass now" without running it
- "This fixes the issue" without reproducing the original failure
- Guessing at library APIs instead of reading source/docs
- Assuming env vars exist without checking

---

## 4. PROMPT CONTEXT DUMP (Equivalent: ant-only debug prompt dumping)

When debugging unexpected Claude behavior or investigating why a fix didn't work:

```bash
# Dump current working context for debugging
mkdir -p ~/.claude/debug-dumps
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cat > ~/.claude/debug-dumps/context-${TIMESTAMP}.md << 'DUMP'
## Debug Context Dump
- CWD: $(pwd)
- Branch: $(git branch --show-current 2>/dev/null || echo "not a git repo")
- Last commit: $(git log --oneline -1 2>/dev/null || echo "none")
- Changed files: $(git diff --name-only 2>/dev/null || echo "none")
- Node version: $(node --version 2>/dev/null || echo "none")
- Package manager: $(ls package-lock.json bun.lock pnpm-lock.yaml yarn.lock 2>/dev/null | head -1 || echo "unknown")
DUMP
echo "Context dumped to ~/.claude/debug-dumps/context-${TIMESTAMP}.md"
```

---

## 5. ENHANCED CODE REVIEW (Equivalent: ant-internal review standards)

When reviewing code (in any mode), apply these additional checks that go beyond the standard review:

### Concurrency & Race Conditions
- Async operations without proper error boundaries
- State updates after component unmount
- Parallel API calls with shared mutable state
- Missing `AbortController` on fetch in useEffect

### Supply Chain
- New dependencies: check npm weekly downloads, last publish date, maintainer count
- `postinstall` scripts in new packages (potential supply chain attack)
- Pinned vs range versions for security-critical packages

### Information Disclosure
- Stack traces in production error responses
- Internal file paths in error messages
- Database schema details in API responses
- Version numbers in headers (x-powered-by)

### Denial of Service
- Unbounded loops over user input
- Missing pagination on list endpoints
- Large file upload without size limits
- Regex with catastrophic backtracking (`(a+)+$`)

---

## 6. INTEGRATION CHECKLIST

### How /carmack uses this protocol:
- **debug mode**: Run Security Review Gate on all files touched during investigation
- **feature mode**: Run full OWASP sweep + Truthfulness Protocol on implementation
- **review mode**: Apply Enhanced Code Review (Section 5) in addition to existing checklists
- Load this file alongside other reference files in STEP 1

### How /debug uses this protocol:
- Before declaring a root cause: verify with Truthfulness Protocol (Section 2)
- After implementing a fix: run Closed-Loop Verification (Section 3)
- For any security-adjacent bug: run Security Review Gate (Section 1)
- Load this file when the symptom touches auth, data handling, or external input

### How /ship uses this protocol:
- **New Phase 1.27**: Run OWASP Top 10 Sweep on all changed files (after Phase 1.26)
- **New Phase 1.28**: Run Enhanced Code Review checks (Section 5) on new dependencies
- **Pre-deploy verification**: Apply Truthfulness Protocol — never say "deployed successfully" without curl evidence
- Load this file at the start alongside other reference files
