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
  1. Copy `~/.claude/skills/ship/references/biome.template.json` (Codex: `~/.codex/skills/ship/references/biome.template.json`) to `biome.json`. NEVER run biome init — that walks fat trees such as public/data.
  2. Keep the template scope. Merge extra excludes if the repo has fat trees
     (`!!**/public/data`, `!!**/.prices_build_stash`, `!!**/*.jsonl`, `!!**/.beads`).
     Do not switch back to a whole-tree `files.includes` of `"**"`.
     Tailwind / worker CSS: `"css": { "linter": { "enabled": false } }`
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

### Stage 1.7: Embedded JS/CSS String Safety Check (MANDATORY)

**Biome operates on file-level syntax and does NOT understand strings-within-strings.** When a project uses inline HTML templates (Cloudflare Workers, server-rendered HTML, template literals containing `<script>` blocks), Biome auto-fix can silently break embedded JavaScript.

**The #1 pattern:** `noUselessEscapeInString` removes backslash escapes that are *syntactically necessary* inside embedded JS strings. Example: Biome converts `Didn\'t` → `Didn't` inside a single-quoted JS string embedded in a TypeScript template literal — this unescaped apostrophe terminates the JS string and kills the entire client-side script.

**Biome is only ONE cause. The bug class is: code inside a string is invisible to every
compiler you run.** A hand edit, a search-and-replace, a sed, or an agent rewriting a
comment breaks it exactly as easily — and `tsc --noEmit`, `vite build`, `wrangler deploy
--dry-run` and a **full green test suite** all pass on a bundle whose client script cannot
parse, because none of them ever parse that string. The failure appears only in a user's
browser, as a dead page.

**Reference incident (2026-08-05, improvebayarea).** A `python3 -c` replace intended for a
COMMENT also rewrote real code inside the template literal:
`setGeoFromSource(..., 'photo_exif', { force: true })` → `..., force:true)`. `tsc` exit 0,
`vite build` exit 0, `wrangler deploy --dry-run` exit 0, **56 tests passed**. It was caught
by eye while reading a diff. Nothing mechanical would have stopped that deploy.

**So run a PARSE gate, not a pattern grep.** `new Function(code)` parses without executing —
no DOM, no globals, no side effects — and it is cause-agnostic: it catches Biome damage, a
bad sed, a stray backtick in a comment (a backtick or `${` inside a template literal
terminates it), and anything else. Trigger it after **ANY** edit to a file that emits code
inside a string, not just after a Biome fix.

```bash
# Cause-agnostic: does every inline <script> in the RENDERED output actually parse?
node -e '
const fs=require("fs");
// LAST argv element, not argv[1]: as `node -e" argv[1] is the file, but if you save
// this snippet to guard.js then argv[1] is the SCRIPT PATH and it silently parses
// its own source (0 blocks -> exit 2). Verified by doing exactly that, 2026-08-05.
const html=fs.readFileSync(process.argv[process.argv.length-1],"utf8");
const blocks=[...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)]
  .map(m=>m[1]).filter(s=>s.trim());
if(!blocks.length){console.error("GUARD VACUOUS: 0 inline <script> found — regex drifted");process.exit(2);}
let bad=0;
blocks.forEach((c,i)=>{try{new Function(c)}catch(e){bad++;console.error(`block #${i}: ${e.message}`)}});
console.log(`${blocks.length} inline <script> block(s), ${bad} parse failure(s)`);
process.exit(bad?1:0);
' /tmp/rendered.html
```

Feed it the **rendered** HTML — `curl` the live page post-deploy, or call the render
function in a test pre-deploy. As a permanent repo gate, make it a unit test over the
render function (improvebayarea `src/geo_freeze.test.ts`, "inline browser bundle stays
syntactically valid"), so it runs on every `vitest` rather than only when someone
remembers. **Prove the guard can fail** — re-inject the exact corruption and confirm it
reports `SyntaxError`; a guard that has never failed is a guard you have not tested. Note
the `0 blocks → exit 2` branch: if the regex ever drifts, the gate must scream rather than
silently pass on nothing.

**Same class, other hosts:** SQL built into a string, CSS in a `<style>` template, a shell
script emitted by a generator, an email HTML template. If your toolchain does not parse it,
add a parse gate for it.

**Fix patterns:**
- Change single-quoted strings containing apostrophes to double-quoted: `'Didn't'` → `"Didn't"`
- Add biome.json override to disable `noUselessEscapeInString` for files with inline HTML templates
- After fix, always verify: `curl -s <URL> | grep -o 'KEY_JS_FUNCTION_NAME'` to confirm JS executes

**Prevention — biome.json override for inline HTML files:**
```json
{
  "overrides": [{
    "include": ["src/index.ts"],
    "linter": {
      "rules": {
        "suspicious": {
          "noUselessEscapeInString": "off"
        }
      }
    }
  }]
}
```

**Why (2026-04-11):** Biome auto-fix removed `\'` escape from `Didn\'t` in a single-quoted JS string inside an HTML template literal in a Cloudflare Worker. The unescaped apostrophe terminated the string, causing a JS syntax error that killed the entire page — no map, no data, no judges loaded. The TypeScript compiler (`tsc`) did not catch this because the JS is inside a template string, not parsed as JS by TypeScript.

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

## Stage 1.6: Hardcoded auth/key fallback scan (MANDATORY)

**Why**: Vite (and similar build tools) inline `import.meta.env.*` at build time. CI builds run without `.env` (gitignored), so any hardcoded fallback in source becomes the SHIPPED value — even if `.env` is correct locally and dashboard secrets are correct in production. If the fallback is a *dev*-instance value (`pk_test_*`, `sk_test_*`, `*.accounts.dev`, etc.), production silently runs against the dev auth provider with all its rate limits and broken email deliverability.

**Real incident (2026-04-30):** `App.tsx` had `const CLERK_KEY_FALLBACK = "pk_test_..."` used as `import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || CLERK_KEY_FALLBACK`. Production bundle shipped `pk_test_*` for months despite `.env` being updated and Cloudflare secrets being correct. Email verification emails never delivered because dev Clerk instance has hard send-rate caps. Fix: replace fallback with the prod value (or with a hard error so CI fails loudly).

```bash
# Scan source for production-toxic auth fallbacks. Fail the gate if any hit.
PATTERNS='pk_test_|sk_test_|prime-rhino-99|\.clerk\.accounts\.dev|pk_(test|live)_[A-Za-z0-9_-]{20,}|sk_(test|live)_[A-Za-z0-9_-]{20,}'

# Allowlist: env files (intentional), test files, type-prefix detection constants in vendored SDKs (e.g. "pk_test_" as a string constant).
HITS=$(grep -rEn "$PATTERNS" src/ 2>/dev/null \
  | grep -vE '\.test\.|__tests__|/node_modules/|\.d\.ts:' \
  | grep -vE '"(pk|sk)_(test|live)_"\s*[,;)]' )  # bare prefix constants are SDK-internal

if [ -n "$HITS" ]; then
  echo "BLOCK: hardcoded auth-key patterns in source — these will ship even when env is correct:"
  echo "$HITS"
  exit 1
fi

# Same for the BUILT bundle — catch cases where the source is clean but a dependency baked it in.
if [ -d dist ]; then
  BUNDLE_HITS=$(grep -rE "pk_test_|sk_test_|prime-rhino-99|\.clerk\.accounts\.dev" dist/ 2>/dev/null \
    | grep -v '\.map:' )
  if [ -n "$BUNDLE_HITS" ]; then
    echo "BLOCK: built bundle contains dev-instance auth references:"
    echo "$BUNDLE_HITS"
    exit 1
  fi
fi
```

**Generalize to other auth providers:**

| Provider | Dev fingerprint | Prod fingerprint |
|---|---|---|
| Clerk | `pk_test_*`, `*.clerk.accounts.dev`, `*.clerk.dev`, instance slug like `prime-rhino-99` | `pk_live_*`, `clerk.<your-domain>` |
| Supabase | project ref ending in `-dev` or local URLs `localhost:54321` | live project ref + `<ref>.supabase.co` |
| Auth0 | `<tenant>-dev.<region>.auth0.com` | `<tenant>.<region>.auth0.com` or custom domain |
| Firebase | demo-* projectId, `localhost:9099` (auth emulator) | real projectId, `<project>.firebaseapp.com` |
| Stripe | `pk_test_*`, `sk_test_*` | `pk_live_*`, `sk_live_*` |

**Fix pattern:**
```ts
// ❌ Silently ships dev value to prod when .env is gitignored from CI
const FALLBACK = "pk_test_...";
const KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || FALLBACK;

// ✅ Hard-fail at build/runtime if env is missing — surfaces the bug immediately
const KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY;
if (!KEY) throw new Error("VITE_CLERK_PUBLISHABLE_KEY is required at build time");

// ✅ Or fallback to PROD value (publishable keys are public-by-design)
const FALLBACK = "pk_live_..."; // prod custom domain
```

---

## Stage 1.8: TypeScript Anti-Slop Scan (WARN — surface generic guards & laundered casts)

**Why**: Generic `isRecord`/`isObject` guards, `as unknown as T` launder-casts, and `(x as any).field` reach-casts let code compile and run on data of unknown shape without ever stating the shape — pushing type errors to a production `TypeError`. It's the runtime-guard sibling of the hardcoded-fallback and No-Suppression problems, and the upstream cause of the undefined/null-render bug class. Full rule + Zod refactor patterns: `~/.claude/skills/shared/anti-slop-typescript.md`.

```bash
# Scan source (TS/TSX). Advisory by default — lists hits + refactor hints, never blocks on a count.
~/.claude/skills/code/tools/detect-ts-slop.sh src/ 2>&1 || true

# Or scope to this release's diff:
# ~/.claude/skills/code/tools/detect-ts-slop.sh --diff origin/main
```

**Decision rule (WARN, not BLOCK):** This stage does NOT hard-fail the ship — anti-slop has legitimate exceptions (a *targeted* predicate that genuinely fits, a justified narrow cast). It surfaces every hit with file:line so they get refactored to a named type / discriminated union / Zod schema before merge. Per the Fix-All-Issues rule, treat the list as work, not noise. To enforce a hard ceiling on egregious slop, run with `--threshold N` (exits 1 when total > N) — opt-in, since false positives on a hard block would wrongly stop a clean release.

**Required alternatives (priority):** named `interface`/`type` → discriminated union on a literal field → **Zod/Valibot schema at the trust boundary** with `type X = z.infer<typeof Schema>` → library-inferred types (`z.infer`, Prisma/Drizzle `$inferSelect`, tRPC, Hono `InferResponseType`) → targeted predicate (last resort, justified inline). Typed code should compile (`tsc --noEmit`) with zero casts added to make it pass.
