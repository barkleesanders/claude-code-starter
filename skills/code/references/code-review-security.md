# Code Review: Security & XSS Audit

#### 1. Security Review
Check for:
- SQL injection vulnerabilities
- XSS (Cross-Site Scripting) — **see full XSS audit below**
- Command injection
- Insecure deserialization
- Hardcoded secrets/credentials
- Improper authentication/authorization
- Insecure direct object references

```javascript
// BAD: SQL injection
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD: Parameterized query
const query = 'SELECT * FROM users WHERE id = $1';
await db.query(query, [userId]);
```

#### 1a. COMPREHENSIVE XSS AUDIT (MANDATORY — 10 VECTORS)

**Run this audit on EVERY security-related task.** The 2026-03-21 incident proved that partial XSS scanning misses critical vectors. A first-pass Carmack audit caught 1 of 8 XSS issues; a second comprehensive pass found the remaining 7. This checklist ensures 100% coverage on the first pass.

**Detection Commands (run ALL 10):**

```bash
# VECTOR 1: dangerouslySetInnerHTML without DOMPurify
grep -rn "dangerouslySetInnerHTML" --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist
# For EACH hit: verify DOMPurify sanitization exists in the SAME file
# Regex sanitizers are NOT sufficient — require DOMPurify

# VECTOR 2: Raw .innerHTML assignment without escapeHtml()
grep -rn "\.innerHTML\s*=" --include="*.tsx" --include="*.ts" --include="*.html" . | grep -v node_modules | grep -v dist
# CRITICAL: Search from project root (.), NOT just src/ — entry points (index.tsx, main.tsx)
# run BEFORE React mounts and are blind spots when scoping to src/ only

# VECTOR 3: JSON.stringify in <script> tags — incomplete escaping
grep -rn "JSON\.stringify" --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist
# For each hit inside a <script> or dangerouslySetInnerHTML context:
# MUST escape ALL 5 chars per OWASP: < > & U+2028 U+2029
# Just escaping < is INCOMPLETE — > prevents --> comment closure,
# & prevents HTML entity injection, U+2028/U+2029 break JS parsing
# Use a dedicated escapeJsonLd() function, not inline .replace(/</g, ...)

# VECTOR 4: Template string interpolation in HTML without escapeHtml()
grep -rn '`.*\${.*}`' --include="*.ts" . | grep -v node_modules | grep -v dist | grep -v "import\|require\|console\|Error\|throw"
# In server-side HTML renderers (Hono, Workers, SSR):
# Every ${variable} inside HTML must go through escapeHtml()
# Especially: href="", content="", src="" attributes
# URL values in attributes can break out via " to inject attributes

# VECTOR 5: href attributes with user/API-controlled URLs (javascript: URI)
grep -rn 'href={' --include="*.tsx" . | grep -v node_modules | grep -v dist
# For each hit: check if the URL source is user-controlled or from API/AI
# If yes: MUST validate URL scheme — block javascript:, data:, vbscript:
# Safe pattern: isSafeUrl() guard that allows only http:, https:, relative paths

# VECTOR 6: Incomplete escapeHtml() function
grep -rn "function escapeHtml\|const escapeHtml" --include="*.ts" --include="*.tsx" . | grep -v node_modules
# For each hit: verify it escapes ALL 6 chars: & < > " ' `
# Missing backtick (`) = IE attribute delimiter attack
# Missing & = double-encoding attacks
# OWASP recommends &#x27; (hex) over &#039; (decimal) for single quotes

# VECTOR 7: Structured data / JSON-LD type safety
grep -rn "structuredData\|json-ld\|application/ld+json" --include="*.ts" --include="*.tsx" . | grep -v node_modules
# Types accepting Record<string, unknown> or object are too permissive
# Tighten to require @context and @type fields minimum
# Prevents arbitrary object injection into script tags

# VECTOR 8: Server-side HTML with unescaped URL construction
grep -rn "https://.*\${" --include="*.ts" . | grep -v node_modules | grep -v dist
# URLs built from variables and interpolated into HTML need escapeHtml()
# Even if the variable comes from a static config — defense in depth

# VECTOR 9: eval(), Function(), setTimeout/setInterval with string args
grep -rn "eval(\|new Function(\|setTimeout(\|setInterval(" --include="*.ts" --include="*.tsx" . | grep -v node_modules | grep -v dist
# setTimeout/setInterval with STRING arg (not function) = eval equivalent

# VECTOR 10: postMessage without origin validation
grep -rn "addEventListener.*message\|postMessage\|onmessage" --include="*.ts" --include="*.tsx" . | grep -v node_modules
# message event handlers MUST validate event.origin
# postMessage to * (wildcard) leaks data to any frame
```

**XSS Vulnerability Severity Matrix:**

| Vector | Severity | Auto-Fix | Detection |
|--------|----------|----------|-----------|
| `dangerouslySetInnerHTML` without DOMPurify | CRITICAL | Add DOMPurify import + sanitize() wrapper | grep dangerouslySetInnerHTML |
| Raw `.innerHTML =` without escape | CRITICAL | Wrap value in escapeHtml() | grep innerHTML |
| JSON in `<script>` with partial escaping (only `<`) | HIGH | Replace with escapeJsonLd() covering all 5 chars | grep JSON.stringify near script |
| URL in HTML attribute without escapeHtml() | HIGH | Wrap in escapeHtml() | grep template literals in .ts HTML renderers |
| href with user-controlled URL (no scheme check) | HIGH | Add isSafeUrl() guard | grep href={ with variable source |
| Incomplete escapeHtml() (missing `& > ' \``) | MEDIUM | Add missing chars to escape map | Read escapeHtml function body |
| Overly permissive structured data type | LOW | Tighten to JsonLdSchema interface | grep structuredData type |
| eval/Function/string setTimeout | CRITICAL | Refactor to avoid eval | grep eval |
| postMessage without origin check | HIGH | Add origin validation | grep postMessage |
| URL construction without escaping | MEDIUM | Apply escapeHtml() | grep URL template literals |

**Required escapeJsonLd() implementation (for JSON inside `<script>` tags):**

```typescript
// OWASP-compliant JSON-LD escaping — escapes ALL dangerous chars, not just <
function escapeJsonLd(json: string): string {
  return json
    .replace(/</g, "\\u003c")   // Prevents </script> breakout
    .replace(/>/g, "\\u003e")   // Prevents --> HTML comment closure
    .replace(/&/g, "\\u0026")   // Prevents HTML entity injection
    .replace(/\u2028/g, "\\u2028") // Line Separator breaks JS parsing
    .replace(/\u2029/g, "\\u2029"); // Paragraph Separator breaks JS parsing
}
```

**Required isSafeUrl() implementation (for href attributes with dynamic URLs):**

```typescript
// Blocks javascript:, data:, vbscript: and other dangerous URI schemes
function isSafeUrl(url: string): boolean {
  const trimmed = url.trim().toLowerCase();
  if (/^[a-z][a-z0-9+.-]*:/i.test(trimmed)) {
    return trimmed.startsWith("https:") || trimmed.startsWith("http:");
  }
  return true; // Allow relative URLs (/path, #anchor)
}
```

**Required escapeHtml() — complete (all 6 chars):**

```typescript
function escapeHtml(text: string): string {
  const map: Record<string, string> = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#x27;",   // Hex form per OWASP recommendation
    "`": "&#x60;",   // Backtick — IE attribute delimiter
  };
  return text.replace(/[&<>"'`]/g, (char) => map[char] || char);
}
```

**Incident that drove this (2026-03-21):**
First Carmack pass on your-app found only 1 XSS issue (JSON.stringify without `<` escaping in render-html.ts). Second comprehensive audit found 7 more: unescaped URL interpolation in HTML attributes (HIGH), incomplete JSON-LD escaping missing 4 of 5 required chars (HIGH), benefit.link href without javascript: URI blocking (MEDIUM), overly permissive structuredData type (LOW), missing backtick in escapeHtml (LOW). Total: 8 vulnerabilities, only 1 caught on first pass (12.5% detection rate). This checklist ensures 100% detection on the first pass.
