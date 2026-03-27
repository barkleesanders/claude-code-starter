---
name: debug
user-invocable: true
description: "Quick debugging patterns and known production failure traps. Reference guide for common issues."
---

# /debug - Debugging Quick Reference

Fast reference for known production failure patterns. For deep debugging, use `/carmack`.

## Usage

```
/debug [pattern name or symptom]
```

## Examples

- `/debug catch-all` — Catch-all error handling masking root cause
- `/debug react undefined` — React "X is not defined" scope bug
- `/debug silent startup` — React silently fails to mount
- `/debug auth failed` — Generic auth error hiding real cause

## Known Production Failure Patterns

### Pattern 1: Catch-All Error Handling Masking Root Cause

**Rank: #3 production debugging trap.**

A single `try-catch` wrapping multiple operations returns a generic error, making it impossible to identify which operation actually failed.

#### Symptoms
- Error message says one thing (e.g., "Token verification failed") but actual failure is different (e.g., API down, DB timeout)
- Logs show generic error but not the specific operation that threw
- Can't reproduce locally because the failing external service works in dev

#### Quick Detection
```bash
# Find catch blocks returning generic errors in middleware/handlers
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/worker/ | grep -A5 "return.*json.*error"

# Find large try-catch blocks (catch far from try = multiple wrapped operations)
grep -n "} catch" --include="*.ts" -r src/worker/middleware/
```

#### Fix Pattern
```typescript
// ❌ CATCH-ALL: All errors return same message + status code
try {
  const token = await verifyToken(jwt);        // Auth failure
  const user = await clerkApi.getUser(sub);    // API failure
  const data = await db.query("SELECT ...");   // DB failure
} catch (error) {
  return json({ error: "Authentication failed" }, 401);  // MISLEADING!
}

// ✅ SPLIT: Each failure mode gets correct status + message
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

#### Status Code Guide
| Failure Mode | Status Code | When |
|-------------|-------------|------|
| JWT/token verification | 401 | Bad token, expired, wrong key |
| External API (Clerk, Stripe) | 503 | Service unavailable |
| Database error | 503 or 500 | Connection failed, query error |
| Business logic validation | 400 or 422 | Bad input |

#### Real-World Case: AIVA Benefits Finder (2026-02-27)
- **Symptom**: "Unauthorized: Token verification failed" on every benefits search
- **Root cause**: Clerk API call in the same try-catch was failing, but the catch returned 401
- **Fix**: Split into JWT try-catch (401) and service try-catch (503)
- **File**: `src/worker/middleware/clerkAuth.ts`
- **Commit**: `5aeec79`

---

### Pattern 2: React "X is not defined" (Scope Bug)

**Rank: #1 production crash cause.**

Inner/child component references a variable from parent scope without receiving it as a prop.

#### Quick Detection
```bash
grep -n "const.*= (" components/*.tsx | grep -v "export"
grep -rn "{[a-z][a-zA-Z]*\." --include="*.tsx" | grep -v "\?."
```

#### Fix
- Pass the variable as a prop, or move the component outside the parent
- Add `?.` optional chaining for all nullable access

Full guide: `/carmack` React-Specific Checks section

---

### Pattern 3: Silent React Startup Failure

**Rank: #2 production crash cause.**

Module-level code throws before React mounts. No console errors, only SSR fallback visible.

#### Quick Detection
```javascript
// Chrome DevTools console:
import('/src/react-app/App.tsx').catch(e => console.error('Module failed:', e))
```

```bash
grep -Bn5 "export default function\|export function App" src/react-app/App.tsx | grep "validate\|throw\|assert"
```

#### Fix
Pass fallbacks to `validateClientEnv()` for vars with hardcoded defaults.

Full guide: `/carmack` Silent React Startup Failure section

---

### Pattern 4: Cloudflare WWW Redirect Auth Break

Cookies set on `yourapp.example.com` aren't sent to `www.yourapp.example.com`. Edge cache serves HTML before Worker redirect runs.

#### Quick Detection
```bash
curl -sI "https://www.yourapp.example.com" | grep -E "^(HTTP|location)"
# Should return 301 to non-www
```

Full guide: CLAUDE.md "Cloudflare WWW Redirect Fix" section

---

### Pattern 5: Twitter/Social Card Showing Old OG Image

**Rank: #4 production debugging trap.**

Social platforms (Twitter/X, Facebook, LinkedIn) cache OG card images on TWO levels: page metadata cache AND image CDN cache. Changing the image file or meta tags alone won't update the card.

#### Symptoms
- Twitter card preview shows old/outdated image (e.g., old dollar amounts, old design)
- Image file is correct on your server but social platforms show cached version
- Card Validator or third-party tools show correct tags but Twitter app shows old card
- `pbs.twimg.com/card_img/` URL still serves the old image

#### Two Cache Layers
| Layer | What It Caches | TTL | How to Bust |
|-------|---------------|-----|-------------|
| **Page metadata** | og:image URL, title, description for a given page URL | ~7 days | Card Validator, tweet the URL, or use `?v=N` query param on page URL |
| **Image CDN** | Actual image bytes at the og:image URL | Indefinite | Add `?v=YYYYMMDD` cache-bust param to the image URL in meta tags |

#### Quick Detection
```bash
# 1. Check what your server actually serves to Twitterbot
curl -s -H "User-Agent: Twitterbot/1.0" "https://yoursite.com/" | grep "og:image\|twitter:image"

# 2. Download what the server serves vs what Twitter cached
curl -s -o /tmp/served.png "$(curl -s -H 'User-Agent: Twitterbot/1.0' https://yoursite.com/ | grep -oP 'twitter:image" content="\K[^"]+')"
# Compare visually with Read tool

# 3. Download Twitter's cached card image (from pbs.twimg.com URL)
curl -s -o /tmp/twitter-cached.jpg "https://pbs.twimg.com/card_img/XXXXX/XXXXX?format=jpg&name=medium"
# Compare visually — if different from served image, it's a cache issue

# 4. Check all 4 files for consistency
grep -rn "og-card\|og-social\|og-image\|og_image" index.html src/worker/seo/ src/react-app/components/SEO.tsx
```

#### Fix Pattern (Nuclear — Busts Both Cache Layers)
1. **Add `?v=YYYYMMDD` to image URL in ALL source files:**
   - `index.html` (static meta tags)
   - Worker SSR (`page-metadata.ts`, `render-html.ts`)
   - React SEO component (`SEO.tsx`)
2. **Deploy**
3. **Verify**: `curl -s -H "User-Agent: Twitterbot/1.0" https://yoursite.com/ | grep "twitter:image"`
4. **Share with fresh page URL**: `https://yoursite.com/?v=3` bypasses page metadata cache
5. **Use Card Validator** to update bare URL: `cards-dev.x.com/validator`

#### Why File Rename Alone Doesn't Work
Renaming `og-social-card.png` → `og-card-2026.png` busts the image CDN cache but NOT the page metadata cache. Twitter still serves its cached card for `yoursite.com` until re-crawled. The `?v=` param on the image URL busts BOTH layers because Twitter treats it as a new image URL it has never fetched.

#### Real-World Case: AIVA OG Card (2026-03-06)
- **Symptom**: Twitter showed $1.38M card, server had $1.42M card
- **Investigation**: File rename + meta tag fixes deployed, but Twitter's `pbs.twimg.com` CDN still served old image
- **Root cause**: Two cache layers — page metadata AND image CDN both stale
- **Fix**: Added `?v=20260306` to image URL in all 4 source files, deployed, shared with `?v=3` page URL
- **Files**: `index.html`, `src/worker/seo/page-metadata.ts`, `src/worker/seo/render-html.ts`, `src/react-app/components/SEO.tsx`

---

### Pattern 6: AI Agent Destroys Production Infrastructure

**Rank: CATASTROPHIC — complete environment destruction.**

AI agent runs destructive infrastructure commands (terraform destroy, cloud CLI delete) and wipes production resources including databases and all backups.

#### Symptoms
- Infrastructure suddenly gone (404s, connection refused on all services)
- AWS/GCP/Azure console shows resources deleted
- Terraform state shows 0 resources (or shows wrong resources)
- Automated backups also deleted (they were managed by the same tool that destroyed the infra)

#### Root Cause Chain
1. Agent runs Terraform without correct state file (e.g., on new machine, from archive)
2. Terraform thinks no infrastructure exists — proposes creating everything from scratch
3. Agent runs `terraform apply` creating duplicate resources
4. During "cleanup", agent replaces state file with one referencing production
5. Agent runs `terraform destroy` — wipes actual production infrastructure
6. Destroy command also deletes managed backups/snapshots

#### Prevention Checklist
- [ ] NEVER let agents run `terraform destroy` — humans run it themselves
- [ ] NEVER let agents run `terraform apply -auto-approve`
- [ ] ALWAYS review `terraform plan` output before any `apply`
- [ ] ALWAYS verify state file: `terraform state list` should show expected resources
- [ ] NEVER let agents modify/replace .tfstate files
- [ ] Store Terraform state remotely (S3 + DynamoDB lock), never locally
- [ ] Enable deletion protection on critical resources (RDS, S3)
- [ ] Maintain backups OUTSIDE of Terraform-managed lifecycle
- [ ] Test backup restoration regularly (don't assume backups work)

#### Recovery Steps
1. Check cloud provider for retained snapshots (may not be visible in console)
2. Contact cloud support immediately — they may have internal copies
3. Upgrade to business support for faster response if needed
4. Rebuild non-data infrastructure with Terraform (VPC, ECS, LB can be recreated)
5. Restore database from recovered snapshot
6. Verify data integrity: `SELECT COUNT(*) FROM critical_tables`

#### Real-World Case: DataTalks.Club (2026-02-27)
- **Symptom**: Entire course platform down — no DB, no VPC, no ECS, no load balancer
- **Root cause**: AI agent ran `terraform destroy` after silently swapping state file
- **Impact**: 1,943,200 rows at risk, 24-hour outage, AWS Business Support upgrade (+10% costs)
- **Recovery**: AWS support found internal snapshot, restored after 24 hours
- **Fix**: Remote state in S3, deletion protection, daily restore tests via Lambda, agents banned from destructive infra commands

Full guide: `/carmack` Infrastructure Safety Rules section

---

### Pattern 7: Rust Cross-Platform Conditional Compilation Lint Failures

**Rank: Common CI blind spot for Rust PRs.**

Code compiles on macOS but fails clippy on Linux/Windows/Android/FreeBSD/NetBSD because `#[cfg(target_os)]` blocks make variables conditionally used.

#### Symptoms
- `cargo clippy` passes locally (macOS) but fails in CI on 5+ platforms
- Error: `variable does not need to be mutable` or `unused variable`
- The variable IS used, but only inside a `#[cfg(target_os = "macos")]` block

#### Quick Detection
```bash
# Find variables that are only mutated inside cfg blocks
grep -B5 "#\[cfg(target_os" src/**/*.rs | grep "let mut"
```

#### Fix Pattern
```rust
// ❌ FAILS on non-macOS: `mut` is unused when cfg block is compiled out
let mut gem = require("gem")?;
#[cfg(target_os = "macos")]
if let Some(keg) = resolve_keg(&gem) { gem = keg; }

// ✅ CORRECT: Allow unused_mut for cross-platform compatibility
#[allow(unused_mut)]
let mut gem = require("gem")?;
#[cfg(target_os = "macos")]
if let Some(keg) = resolve_keg(&gem) { gem = keg; }
```

#### Real-World Case: topgrade PR #1830 (2026-03-07)
- **Symptom**: PR passed `cargo clippy` on macOS, failed on Linux/Windows/FreeBSD/NetBSD/Android
- **Root cause**: `let mut gem` only reassigned inside `#[cfg(target_os = "macos")]` block
- **Fix**: Added `#[allow(unused_mut)]` above both declarations
- **Lesson**: Always run `cargo clippy` with `--target` for all CI platforms, or preemptively add `#[allow(unused_mut)]` for variables modified in cfg blocks

---

### Pattern 8: Homebrew Keg-Only Binaries Not on PATH (launchd/cron)

**Rank: #1 cause of silent tool skipping in automated tasks.**

Homebrew installs some formulae as "keg-only" — binaries aren't symlinked into `/opt/homebrew/bin/`. When running under launchd/cron (no shell profile loaded), these tools are invisible.

#### Symptoms
- Tool works in interactive shell but "command not found" in cron/launchd
- Automated updates silently skip steps (no error, just doesn't run)
- System version of a tool used instead of Homebrew version (e.g., system Ruby 2.6 vs Homebrew Ruby 4.0)

#### Quick Detection
```bash
# Find all keg-only formulae with binaries
brew list --formula | while read f; do
  info=$(brew info --json=v2 --formula "$f" 2>/dev/null)
  if echo "$info" | grep -q '"keg_only":true'; then
    prefix=$(brew --prefix "$f")
    [ -d "$prefix/bin" ] && echo "KEG-ONLY: $f -> $prefix/bin"
  fi
done

# Check if a specific tool resolves to system vs Homebrew
env PATH="/opt/homebrew/bin:/usr/bin:/bin" which gem ruby python3
```

#### Fix Pattern
```bash
# In launchd/cron scripts, explicitly add keg-only paths BEFORE /usr/bin
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
```

#### Common Keg-Only Formulae on macOS
| Formula | Keg Path | System Fallback |
|---------|----------|-----------------|
| ruby | `/opt/homebrew/opt/ruby/bin/` | `/usr/bin/ruby` (2.6, ancient) |
| python@3.x | `/opt/homebrew/opt/python@3.x/bin/` | `/usr/bin/python3` |
| openssl | `/opt/homebrew/opt/openssl/bin/` | System LibreSSL |
| sqlite | `/opt/homebrew/opt/sqlite/bin/` | `/usr/bin/sqlite3` |

#### Real-World Case: topgrade launchd (2026-03-07)
- **Symptom**: `gem: FAILED`, `rubygems: FAILED` every day for weeks
- **Root cause**: `/opt/homebrew/opt/ruby/bin/` not on launchd PATH, fell through to `/usr/bin/gem` (Ruby 2.6)
- **Fix**: Added keg-only path to `topgrade-auto.sh` PATH export
- **Also affected**: 11 other topgrade steps silently skipped (rustup, pipx, npm, pnpm, claude, etc.)

---

### Pattern 9: Third-Party Embed CSP Blocking (Multi-Layer)

**Rank: #4 production crash cause (silent blank page).**

Third-party embeds (DocuSeal, Stripe, etc.) need CSP permissions across **ALL SIX** directives, not just `frame-src`. Web component embeds (like `@docuseal/react`) render in the parent page context, so every resource they load is governed by your CSP. Missing even one directive causes partial rendering — form fields appear but document background is invisible.

#### Symptoms
- Embedded form shows only interactive fields (inputs, signature boxes) but no document text/background
- Page loads but embedded widget is blank white
- Works in development (no CSP) but broken in production
- Browser console shows CSP violation warnings (if you check)

#### Three-Layer Bug Pattern
1. **Stale resource ID** — config references a deleted/old template/product
2. **CSP blocks the embed script/iframe** — widget doesn't load at all
3. **CSP blocks resource CDN** — widget loads but images/fonts/styles from third-party CDN are blocked, causing partial rendering

#### CSP Directives Checklist for ANY Third-Party Embed
When adding a new third-party embed, you MUST check ALL SIX directives:

| Directive | What It Controls | Example Domain |
|-----------|-----------------|----------------|
| `script-src` | JS scripts loaded by the embed | `cdn.docuseal.com` |
| `connect-src` | API/fetch calls the embed makes | `docuseal.com/embed/forms` |
| `frame-src` | Iframes (if embed uses them) | `docuseal.com` |
| `img-src` | Document page images, logos | `*.s3.amazonaws.com` (presigned S3 URLs!) |
| `style-src` | CSS styles for the form | `docuseal.com` |
| `font-src` | Custom fonts | `docuseal.com` |

#### Quick Detection
```bash
# 1. Check CSP for ALL relevant directives (not just frame-src!)
curl -sI "https://yoursite.com/" | grep -i "content-security-policy" | tr ';' '\n'

# 2. Check the embed's actual resource domains
# Download the embed script and find all URLs it references
curl -s "https://cdn.docuseal.com/js/form.js" | grep -oE 'https?://[a-zA-Z0-9._/-]+' | sort -u

# 3. Check where the embed serves images from (CRITICAL — often a CDN, not the main domain)
# DocuSeal: images come from docuseal.s3.amazonaws.com (AWS S3 presigned URLs)
# Stripe: images come from *.stripe.com
# Clerk: images come from img.clerk.com

# 4. Validate resource ID exists via API
curl -s "https://api.docuseal.com/templates/$ID" -H "X-Auth-Token: $KEY"
```

#### Fix Pattern
1. Update any stale IDs in `wrangler.json` (or secrets)
2. Add the third-party domain to ALL SIX CSP directives in `securityHeaders.ts`
3. Check where the embed serves **images** from — it's often a CDN subdomain, NOT the main domain
4. Redeploy and verify the full form renders (not just form fields)

#### Real-World Case: AIVA DocuSeal (2026-03-08)
Three separate deploys needed because CSP was fixed incrementally instead of comprehensively:
- **Deploy 1**: Added `docuseal.com` to `frame-src`, `connect-src`, `script-src` — form fields appeared but document was blank
- **Deploy 2**: Added `docuseal.com` to `img-src`, `style-src`, `font-src` — still blank document
- **Deploy 3**: Added `*.s3.amazonaws.com` to `img-src` — document finally rendered
- **Root cause**: DocuSeal serves document page images from **presigned AWS S3 URLs** (`docuseal.s3.amazonaws.com`), not from `docuseal.com`
- **Lesson**: Always trace the actual resource URLs an embed loads (check network tab or the embed's JS source), don't assume they come from the main domain

---

### Pattern 10: Serde deny_unknown_fields Config Parse Crash

**Rank: #1 Rust config backwards compatibility trap.**

`#[serde(deny_unknown_fields)]` on config structs causes instant crash when users have deprecated keys in their config files. No graceful degradation — program exits with a cryptic serde error.

#### Symptoms
- Program crashes on startup after upgrading to a version that removed config keys
- Error like: `unknown field 'no_retry', expected one of [...]`
- Works for new users but crashes for anyone with an existing config file
- May affect many users silently (they don't report, they just revert)

#### Quick Detection
```bash
# Find deny_unknown_fields in Rust config structs
grep -rn "deny_unknown_fields" --include="*.rs" src/

# Find recently removed config fields (check git log)
git log --all -p -- src/config.rs | grep "^-.*Option<" | head -20
```

#### Fix Pattern
```rust
// ❌ CRASHES if user has old keys in config
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    active_field: Option<bool>,
    // removed: old_field used to be here
}

// ✅ Accepts old keys silently, ignores them
#[derive(Deserialize)]
pub struct Config {
    active_field: Option<bool>,
    /// Deprecated: kept for backwards compatibility, ignored
    #[serde(default)]
    old_field: Option<bool>,
}
```

#### Real-World Case: topgrade (2026-03-07)
- **Symptom**: `topgrade` crashed on startup with serde parse error
- **Root cause**: User's `~/.config/topgrade.toml` had `no_retry = true` (deprecated)
- **Fix**: Removed `deny_unknown_fields` from Misc struct, added deprecated keys as ignored `Option<bool>`
- **Lesson**: When removing config keys from a Rust project, ALWAYS add ignored stubs if the struct uses strict deserialization

---

### Pattern 11: CI False Positives from Local Grep

**Rank: Common time-waster in CI debugging.**

Local `grep` for code patterns produces false matches that lead to wrong conclusions about what CI is actually checking.

#### Symptoms
- You "fix" what grep tells you is wrong, but CI still fails
- grep matches patterns inside string literals, comments, or unrelated code
- CI uses a project-specific validator with different rules than your grep

#### Quick Detection
```bash
# Don't guess — read the actual CI logs
gh run view <RUN_ID> --log-failed

# Or get all check-runs for latest commit
gh api repos/<owner>/<repo>/commits/<SHA>/check-runs --jq '.check_runs[] | {name, conclusion}'
```

#### Real-World Case: topgrade i18n (2026-03-07)
- Grepped for `t!("...")` to find locale strings needing translations
- `format!("...")` matched because `format` ends in `t`, making grep think it was `t!(...)`
- Wasted a round of CI. Should have read the actual CI checker script or used `gh run view --log-failed`

---

### Pattern 12: Text Overflow in Flex+Grid Layouts (min-w-0 Missing)

**Rank: #1 mobile layout bug — text escapes card boundaries at 375px.**

Flex items have `min-width: auto` by default. Inside a CSS grid cell, a flex child containing long text expands to its natural content width, overflowing the cell even though the grid constrains it.

#### Symptoms
- Text overflows card/box right edge on mobile (375px) but looks fine on desktop
- Long words ("Templates", "Referral Program") escape container boundaries
- `ExternalLink` / trailing icon pushed off-screen in `justify-between` flex rows
- Bug invisible until explicitly testing at 375px viewport

#### Root Cause
Grid creates constrained cells (`minmax(0, 1fr)`), but flex children inside those cells have `min-width: auto` — they claim their natural content width regardless of the cell width constraint. `overflow-hidden` on the card clips the overflow visually but doesn't fix the layout — other elements still get pushed.

#### Two Variants

**Variant A — Icon + Text row (most common)**
```jsx
// ❌ Text div claims full content width, overflows grid cell
<div className="flex items-center gap-3">
  <div className="w-10 h-10 rounded-xl">  {/* icon */}</div>
  <div>
    <h4 className="text-sm font-semibold">Long Title Text</h4>
  </div>
</div>

// ✅ min-w-0 on outer flex + inner text wrapper lets them shrink properly
<div className="flex items-center gap-3 min-w-0 flex-1">
  <div className="w-10 h-10 rounded-xl flex-shrink-0">  {/* icon */}</div>
  <div className="min-w-0">
    <h4 className="text-sm font-semibold break-words">Long Title Text</h4>
  </div>
</div>
```

**Variant B — Text + trailing icon (justify-between)**
```jsx
// ❌ Text expands naturally, pushes ExternalLink icon off the right edge
<div className="flex items-center justify-between gap-3">
  <div>
    <h4>Long Title Text That Might Be 80px Wide</h4>
  </div>
  <ExternalLink className="w-4 h-4 flex-shrink-0" />
</div>

// ✅ flex-1 + min-w-0 on text div gives icon guaranteed space
<div className="flex items-center justify-between gap-3">
  <div className="min-w-0 flex-1">
    <h4 className="break-words">Long Title Text That Might Be 80px Wide</h4>
  </div>
  <ExternalLink className="w-4 h-4 flex-shrink-0" />
</div>
```

#### Grid Column Fix (Mobile-First)
```jsx
// ❌ 2-column on mobile = ~131px cells — too narrow for icon+text rows at 375px
<div className="grid grid-cols-2 gap-3">

// ✅ Single column on mobile, 2 from sm breakpoint (640px+)
<div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
```

#### Quick Detection
```bash
# Flex rows with text content missing min-w-0
grep -rn "flex items-center gap" --include="*.tsx" src/ | grep -v "min-w-0"

# 2-column grids without sm: responsive breakpoint
grep -rn "grid-cols-2" --include="*.tsx" src/ | grep -v "sm:grid-cols"

# Fixed-size icon divs in flex rows without flex-shrink-0
grep -rn '"w-10 h-10\|w-8 h-8\|w-6 h-6"' --include="*.tsx" src/ | grep -v "flex-shrink-0"

# justify-between rows without flex-1 on text child
grep -rn "justify-between" --include="*.tsx" src/ | grep -v "flex-1"
```

#### Complete Fix Checklist
- [ ] Flex row outer div: `min-w-0 flex-1`
- [ ] Icon div: `flex-shrink-0`
- [ ] Text wrapper div: `min-w-0`
- [ ] Long text headings: `break-words`
- [ ] Card container: `overflow-hidden` (safety net — clipping only, not a substitute for min-w-0)
- [ ] 2-col grids: test at 375px or change to `grid-cols-1 sm:grid-cols-2`

#### Real-World Case: AIVA Dashboard (2026-03-13)
- **Symptom**: "Templates", "Referral Program" text escaping card boxes on iPhone
- **Root cause**: `grid-cols-2` → 65px cells, but text divs had `min-width: auto` → claimed ~70px
- **Fix**: `min-w-0 flex-1` on flex containers, `flex-shrink-0` on icons, `grid-cols-1 sm:grid-cols-2`
- **Files**: `Dashboard.tsx` (10 Quick Action items, Document Templates grid), `Welcome.tsx`
- **Commit**: `37792a2`

---

### Pattern 13: User Preference Lost on Page Reload (localStorage Write Without App.tsx Read)

**Rank: #5 invisible UX regression — preference appears to save but resets on refresh.**

When a user preference (font size, theme, language) is written to `localStorage` only inside the preference control component, the preference is applied while that component is mounted, but on the next page load the HTML element reverts to its default before React mounts and the component renders.

#### Symptoms
- Text size slider "saves" but resets on every page refresh
- Theme/color/language preference reverts after navigation away and back
- Works in the same session but lost when opening a new tab
- The preference control shows the correct saved value (reads localStorage correctly), but the DOM hasn't been updated yet

#### Root Cause
The fix has **two required parts**:
1. **Writer**: Component writes pref to localStorage AND applies it to the DOM immediately (`useEffect`)
2. **Reader**: App root (`App.tsx`) reads the pref from localStorage on EVERY mount and applies it to the DOM — BEFORE routes render

If only the Writer exists, the DOM uses CSS defaults until the component renders (causing a visible flash and wrong default).

#### Fix Pattern

```tsx
// TextSizeControl.tsx — WRITER (applies + saves)
useEffect(() => {
  localStorage.setItem("dashboardFontSize", fontSize.toString());
  document.documentElement.style.fontSize = `${fontSize}px`; // applies immediately
}, [fontSize]);

// App.tsx — READER (restores on every page load, before routes render)
export default function App() {
  useEffect(() => {
    const saved = localStorage.getItem("dashboardFontSize");
    if (saved) {
      const px = parseInt(saved, 10);
      if (px === 14 || px === 16 || px === 18) {  // validate!
        document.documentElement.style.fontSize = `${px}px`;
      }
    }
  }, []); // empty deps = runs once on mount

  return <Routes />;
}
```

#### Scaling Mechanism: fontSize vs CSS Custom Properties

```css
/* html { font-size } scales ALL rem-based Tailwind utilities */
html { font-size: 14px; }
/* Now: text-sm (0.875rem) = 12.25px, text-base (1rem) = 14px, text-lg = 15.75px */

/* CSS custom property scales ONLY elements explicitly using var() */
:root { --my-font-size: 14px; }
.my-text { font-size: var(--my-font-size); }  /* Only this class scales */
/* text-sm, text-base etc. are UNAFFECTED by custom properties */
```

Use `document.documentElement.style.fontSize` (not just a CSS custom property) when you want **all** rem-based utilities to scale.

#### Quick Detection
```bash
# Find localStorage.setItem without corresponding App.tsx restoration
grep -rn "localStorage.setItem" --include="*.tsx" src/react-app/ | grep -v "App.tsx"
# Then verify each key is also read in App.tsx:
grep -n "localStorage.getItem" src/react-app/App.tsx

# Find components that write to document.documentElement but don't have App.tsx counterpart
grep -rn "document.documentElement.style" --include="*.tsx" src/react-app/ | grep -v "App.tsx"
```

#### Real-World Case: AIVA Text Size (2026-03-13)
- **Symptom**: A+/A-/A text size selection saved but reset on every page refresh
- **Root cause**: `TextSizeControl.tsx` wrote to localStorage, but no App.tsx reader — DOM reverted to `html { font-size: 16px }` on every new load
- **Fix**: Added `useEffect([], [])` to `App.tsx` that reads `dashboardFontSize` and applies to `document.documentElement.style.fontSize` on mount
- **Files**: `src/react-app/App.tsx`, `src/react-app/components/TextSizeControl.tsx`
- **Commit**: `e77b296` (persistence fix) + `f322432` (site-wide scaling via html font-size)

---

### Pattern 14: Admin Route Auth Missing DB Fallback (Metadata-Only Check)

**Rank: Silent 403 for production admin — every admin route fails with no obvious cause.**

Custom `requireAdmin()` functions in route files that only check Clerk `publicMetadata.role === "admin"` silently block the real production admin, who is set via `is_admin = 1` in the DB (not Clerk metadata).

#### Symptoms
- Admin tabs (Referrals, Users, etc.) show "Could not load data" or "Failed to load" for the real admin
- `/api/admin/*` routes return 403 for `admin@yourapp.example.com`
- No error in logs because the `throw new Error("Admin access required")` is caught and returned as 403
- Works fine in local dev if you set Clerk metadata there but not in production

#### Root Cause
Two separate admin authorization mechanisms exist:
1. **`adminMiddleware`** in `src/worker/index.ts` — checks Clerk metadata OR DB `is_admin=1` (correct)
2. **Custom `requireAdmin()`** in individual route files — may only check Clerk metadata (wrong)

The production admin (`admin@yourapp.example.com`) uses `is_admin = 1` in the DB. It does NOT have `publicMetadata.role === "admin"` in Clerk. Any route that uses a metadata-only check returns 403 for this user.

#### Quick Detection
```bash
# Find custom requireAdmin functions in route files
grep -rn "requireAdmin\|require_admin" src/worker/routes/ --include="*.ts"

# Check if any are synchronous (sync = no DB fallback = metadata-only)
grep -B2 -A10 "function requireAdmin" src/worker/routes/*.ts

# Check adminMiddleware in index.ts for comparison
grep -A15 "adminMiddleware" src/worker/index.ts
```

#### Fix Pattern
```typescript
// ❌ WRONG — metadata-only, silently blocks DB-based admin
function requireAdmin(c: Context) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role !== "admin") {
    throw new Error("Admin access required");
  }
  return user;
}

// ✅ CORRECT — must be async, matches adminMiddleware pattern
async function requireAdmin(c: Context<{ Bindings: Env }>) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role === "admin") return user;
  // DB fallback — production admin uses is_admin=1, not Clerk metadata
  const dbUser = await c.env.DB.prepare(
    "SELECT is_admin FROM users WHERE id = ?",
  ).bind(user.id).first<{ is_admin: number }>();
  if (dbUser?.is_admin === 1) return user;
  throw new Error("Admin access required");
}

// All call sites must await: requireAdmin(c) → await requireAdmin(c)
```

#### Real-World Case: AIVA adminClerk.ts (2026-03-13)
- **Symptom**: Referrals tab, user lookup, referrers list all showed "Could not load data" for `admin@yourapp.example.com`
- **Root cause**: `requireAdmin()` was synchronous and metadata-only. Production admin has `is_admin=1` but no Clerk metadata role.
- **Fix**: Made `requireAdmin` async with DB `is_admin` fallback; updated all 6 call sites from `requireAdmin(c)` to `await requireAdmin(c)`. Added `Context<{ Bindings: Env }>` type so `c.env.DB` was accessible.
- **Files**: `src/worker/routes/adminClerk.ts`

---

### Pattern 6: Deploy Logs Users Out (SPA Chunk Invalidation)

**#5 production crash cause.** Every Cloudflare Workers deployment logs out all active users.

#### Root Cause
`wrangler deploy` changes JS chunk hashes. SPA fallback (`not_found_handling: "single-page-application"`) returns HTML for missing `.js` files instead of 404. React crashes on HTML-as-JS, user reloads, Clerk session lost.

#### Quick Detection
```bash
# Verify all three defenses exist:
grep "vite:preloadError" src/react-app/main.tsx                          # Client recovery
grep -E "ChunkLoadError|dynamically imported" src/react-app/components/ErrorBoundary.tsx  # ErrorBoundary
grep "CDN-Cache-Control" src/worker/middleware/securityHeaders.ts         # Edge cache prevention
```
- If ANY of the three is missing: **BUG** — users will be logged out on every deploy

#### Fix
1. **main.tsx**: Add `vite:preloadError` listener that auto-reloads once (sessionStorage flag prevents loops)
2. **ErrorBoundary**: Detect `ChunkLoadError` / `dynamically imported module` and auto-reload once
3. **securityHeaders**: Add `CDN-Cache-Control: no-store` header to prevent CF edge caching stale HTML

#### Real-World Case: AIVA (2026-03-15)
- **Symptom**: User had to re-login after every `wrangler deploy`
- **Root cause**: CF edge cached HTML with old chunk refs. Old chunks 404'd as HTML (SPA fallback). React crashed.
- **Fix**: Three-layer defense (client preload recovery + ErrorBoundary chunk detection + CDN cache header)
- **Files**: `src/react-app/main.tsx`, `src/react-app/components/ErrorBoundary.tsx`, `src/worker/middleware/securityHeaders.ts`

### Pattern 7: XSS via innerHTML / dangerouslySetInnerHTML
- **Symptom**: User-influenced HTML rendered without proper sanitization
- **Quick Detection**:
  - `grep -rn "\.innerHTML\s*=" --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist` — catches raw innerHTML in entry points (index.tsx, main.tsx) that run BEFORE React's auto-escaping
  - `grep -rn "dangerouslySetInnerHTML" --include="*.tsx" . | grep -v node_modules` — catches React innerHTML
- **Fix (raw innerHTML)**: Add `escapeHtml()` that converts `&<>"` to entities before insertion
- **Fix (dangerouslySetInnerHTML)**: Add `import DOMPurify from "dompurify"` and wrap content in `DOMPurify.sanitize(html, config)`
- **CRITICAL BLIND SPOT**: Always search from `.` (project root), not `src/`. Entry points like `index.tsx` sit at the root and are invisible to `src/`-scoped scans. Error overlays, loading screens, and bootstrap code run before React mounts — no auto-escaping protection.
- **Incident (2026-03-15)**: `BenefitsDisplay.tsx` used regex sanitizer with misleading "DOMPurify" comment
- **Incident (2026-03-18)**: `index.tsx` error overlay injected error messages directly into `innerHTML` without escaping — caught only by full-codebase audit, missed by all `src/`-scoped scans

### Pattern 8: JSON-LD Script Tag Breakout
- **Symptom**: Page breaks or XSS when structured data contains `</script>`
- **Quick Detection**: `grep -A2 "JSON.stringify" --include="*.tsx" src/ | grep -v "replace.*u003c"`
- **Fix**: `JSON.stringify(data).replace(/</g, '\\u003c')`
- **Incident (2026-03-15)**: `StructuredData.tsx` had unescaped JSON.stringify in `<script>` tag

### Pattern 9: Async Button Double-Click
- **Symptom**: Duplicate API calls, double submissions, race conditions
- **Quick Detection**: `grep -rn "onClick.*async" --include="*.tsx" src/ | grep -v "disabled="`
- **Fix**: Add `isLoading` state, `disabled={isLoading}`, spinner, try/finally reset
- **Incident (2026-03-15)**: Dashboard "Complete Step" buttons had no disabled state during async

### Pattern 10: Missing Frontend Auth Guard
- **Symptom**: Unauthenticated user sees loading spinner then error instead of redirect to sign-in
- **Quick Detection**: Find pages using `secureFetch` without `isAuthenticated` check or `ProtectedRoute` wrapper
- **Fix**: Add `useEffect` with `isAuthenticated` check that navigates to `/` or wrap route in auth guard
- **Incident (2026-03-15)**: `/referral` route had no auth guard — showed cryptic error

### Pattern 11: Admin Route Returns 500 Instead of 403
- **Symptom**: Admin check fails but returns 500 (Internal Server Error) instead of 403 (Forbidden)
- **Quick Detection**: `grep -A5 "function requireAdmin" --include="*.ts" src/worker/ | grep "throw new Error"`
- **Fix**: `throw new HTTPException(403, { message: "Admin access required" })` instead of `throw new Error(...)`
- **Incident (2026-03-15)**: `adminClerk.ts` routes returned 500 for non-admin users

### Pattern 12: CF Pages Stale Version / Failed Deploy

**#6 production trap.** Version display shows `"dev"`, old timestamp, or wrong commit after pushing code.

#### Root Cause (5 interacting issues)
1. `version.json` committed to git with local `"dev"` values
2. Service worker caches version.json (cache-first strategy)
3. No `Cache-Control: no-store` header for `/version.json`
4. `.env.local` has `CLOUDFLARE_API_TOKEN` that overrides wrangler OAuth token
5. No CF Pages GitHub auto-deploy integration

#### Quick Detection
```bash
# What does production actually serve?
curl -s "https://YOUR_SITE.pages.dev/version.json"
# If "dev" or old SHA → stale deploy

# Is version.json git-tracked? (should NOT be)
git ls-files public/version.json
# If output → BUG: remove from git, add to .gitignore

# Is .env.local overriding wrangler auth?
grep "CLOUDFLARE_API_TOKEN" .env.local 2>/dev/null
# If found → remove it, use wrangler OAuth from ~/.wrangler/config

# Does service worker cache version.json?
grep "version.json\|NETWORK_ONLY" public/sw.js
# If not in NETWORK_ONLY → BUG: SW serves stale version

# Does _headers bypass cache?
grep "version.json" public/_headers
# If missing → BUG: CDN may cache it
```

#### Fix Checklist
- [ ] `public/version.json` in `.gitignore` + `git rm --cached`
- [ ] `generate-version.js` has git fallback: `execSync('git rev-parse HEAD')`
- [ ] `vite.config.ts` `__BUILD_VERSION__` has same git fallback
- [ ] `public/_headers` has `Cache-Control: no-store` for `/version.json`
- [ ] `public/sw.js` has `/version\.json/` in `NETWORK_ONLY_PATTERNS`
- [ ] `.env.local` does NOT have `CLOUDFLARE_API_TOKEN` (use wrangler OAuth)
- [ ] `npm run deploy` works: `wrangler pages deploy dist`

#### The `.env.local` Token Override Trap
Wrangler auto-loads `.env.local` via dotenv. A broken `CLOUDFLARE_API_TOKEN` there overrides the wrangler OAuth token (which may have `pages:write`). `env -u` doesn't help — wrangler reads the file directly. Only fix: remove the token from `.env.local`.

- **Incident (2026-03-17)**: 6 pushes to main, none deployed. Five interacting causes required five fixes across `.gitignore`, `generate-version.js`, `vite.config.ts`, `_headers`, `sw.js`, and `.env.local`.

### Pattern 13: iOS Safari Doesn't Render PDFs/Blobs in Iframes

**Common mobile-only failure.** Feature works on desktop, blank on iPhone.

#### Root Cause
iOS Safari has no built-in PDF viewer for `<iframe>` tags. Blob URLs (`blob:...`) inside iframes render as blank white boxes. This also affects `<object>` and `<embed>` tags with PDF blobs on iOS.

#### Quick Detection
```bash
# Find iframe/object/embed with blob URLs or PDF rendering
grep -rn "iframe.*src.*blob\|iframe.*pdf\|<object.*pdf\|<embed.*pdf" --include="*.tsx" --include="*.ts" src/
# Find blob URL creation for documents
grep -rn "URL.createObjectURL" --include="*.tsx" src/ | grep -v "download"
```

#### Fix Pattern
```typescript
// Detect iOS
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.userAgent.includes("Mac") && navigator.maxTouchPoints > 1);

// iOS: show Open/Download buttons instead of iframe
// Desktop: render iframe with blob URL
{isIOS ? (
  <button onClick={() => window.open(blobUrl, "_blank")}>Open PDF</button>
) : (
  <iframe src={blobUrl} />
)}
```

#### Other iOS Safari Gotchas
- **`vh` units** — Don't use `max-h-[90vh]` for modals. Use `max-h-[90dvh]` (dynamic viewport height) because iOS address bar changes viewport height
- **`position: fixed`** — Can behave unexpectedly when virtual keyboard opens. Use `position: sticky` or `inset-0` with viewport units
- **Blob URL lifetime** — iOS Safari may garbage-collect blob URLs faster than desktop. Don't revoke URLs while they're still in use
- **`<input type="file">`** — iOS opens the photo picker, not file system. Use `accept` attribute to filter

#### Real-World Case: AIVA (2026-03-15)
- **Symptom**: Document preview worked on desktop, blank/unresponsive on iPhone
- **Root cause**: `PDFPreview.tsx` used `<iframe src={blobUrl}>` — iOS Safari can't render PDFs in iframes
- **Fix**: Detect iOS, show "Open PDF" + "Download PDF" buttons instead of iframe. Desktop keeps inline viewer.
- **Files**: `src/react-app/components/previews/PDFPreview.tsx`, `src/react-app/components/DocumentPreviewModal.tsx`

---

### Pattern 12: Fixed Grid Breaks on Mobile
- **Symptom**: Content crammed into narrow columns on mobile screens
- **Quick Detection**: `grep -rn "grid-cols-[2-9]" --include="*.tsx" src/ | grep -v "sm:\|md:\|lg:"`
- **Fix**: `grid-cols-2 md:grid-cols-4` instead of `grid-cols-4`
- **Incident (2026-03-15)**: `AdminReferrals.tsx` had `grid-cols-4` without responsive breakpoints

---

### Pattern 15: Unnecessary useEffect Causing Render Bugs

**Rank: #1 React anti-pattern — causes extra render cycles, stale closures, and sync bugs.**

`useEffect` should ONLY be used to synchronize with external systems (browser APIs, third-party widgets, network requests). Every other use is wrong.

#### Symptoms
- Component renders twice on state change (extra render cycle from `useEffect` → `setState`)
- Stale data displayed briefly before correcting itself (effect runs after paint)
- Infinite re-render loops (`useEffect` sets state that triggers itself)
- State "lags behind" by one render

#### Quick Detection
```bash
# Find all useEffect — each one needs justification
grep -rn "useEffect" --include="*.tsx" --include="*.ts" src/react-app/ | grep -v node_modules

# Derived state anti-pattern: useEffect that calls setState with computed value
grep -A3 "useEffect.*=>" --include="*.tsx" src/react-app/ | grep "set[A-Z]"

# Copying server data to local state
grep -B2 -A2 "useEffect.*data" --include="*.tsx" src/react-app/ | grep "set[A-Z].*data"
```

#### Fix Patterns

| Instead of | Do this |
|-----------|---------|
| `useEffect(() => setX(compute(y)), [y])` | `const x = compute(y)` (compute during render) |
| `useEffect(() => { if (changed) doThing() }, [val])` | Move to the event handler that caused the change |
| `useEffect + useRef` to track previous value | `[prev, setPrev] = useState(val)` + compare during render |
| `useEffect(() => setState(null), [prop])` | Key the component: `<Comp key={prop} />` |
| `useEffect(() => fetch(...), [])` | TanStack Query / SWR / React 19 `use()` |

#### Valid useEffect uses (don't flag these)
- `addEventListener` / `removeEventListener`
- Third-party widget init/destroy
- `IntersectionObserver` / `ResizeObserver`
- WebSocket connect/disconnect
- `document.title` update
- `localStorage` read on mount (App.tsx root only)

Full guide: `/carmack` useEffect Abuse section

---

## Diagnostic Checklist (When Debugging Any Production Error)

1. **Is the error message accurate?** Check if a catch-all is masking the real error
2. **Check runtime logs**: `wrangler tail` or Cloudflare dashboard — what's the actual error?
3. **Reproduce locally**: Can you hit the same endpoint with the same token?
4. **Check external services**: Is Clerk/Stripe/DB actually responding?
5. **Check env vars**: Are all secrets set in the deployment environment?
6. **Check www redirect**: Is the user hitting `www.` and losing cookies?
7. **Check third-party IDs**: Are template/product IDs in wrangler.json still valid?
8. **Check CSP**: Does `frame-src` include domains for embedded widgets (DocuSeal, Stripe, etc.)?
9. **Text overflowing card on mobile?** Check for `flex items-center` without `min-w-0`, `grid-cols-2` without `sm:` breakpoint, icon divs missing `flex-shrink-0`
10. **User preference not persisting across page loads?** Check if `localStorage.setItem` in component has a matching `localStorage.getItem` in App.tsx that runs on every mount
11. **Admin routes returning 403 for the real admin?** Check if custom `requireAdmin()` in route files is synchronous (metadata-only). It must be async with a DB `is_admin=1` fallback — see Pattern 14
12. **Users logged out after every deploy?** Check for `vite:preloadError` handler in main.tsx, ChunkLoadError detection in ErrorBoundary, and `CDN-Cache-Control: no-store` in securityHeaders — see Pattern 6
13. **XSS via innerHTML?** Check BOTH raw `.innerHTML =` (in entry points like index.tsx at project root — runs before React) AND `dangerouslySetInnerHTML` (in React components). Search from `.` not `src/` — root-level files are blind spots. See Pattern 7
14. **JSON-LD breaking the page?** Check if `JSON.stringify` in `<script>` tags escapes `</` with `\u003c` — see Pattern 8
15. **Async button fires twice?** Check if `onClick={async ...}` has `disabled={isLoading}` state — see Pattern 9
16. **Unauthenticated user sees error instead of redirect?** Check if page calling `secureFetch` has frontend auth guard — see Pattern 10
17. **Admin route returns 500 instead of 403?** Check if `requireAdmin` throws `HTTPException(403)` not `Error` — see Pattern 11
18. **Grid overflows on mobile?** Check if `grid-cols-N` (N>1) has `sm:` or `md:` responsive breakpoints — see Pattern 12
19. **Feature works on desktop but blank/broken on iPhone?** Check for `<iframe>` with blob URLs (PDFs won't render on iOS), `vh` units (use `dvh`), or `position: fixed` conflicts with keyboard — see Pattern 13
20. **Component renders twice or state "lags behind"?** Check for `useEffect` that sets derived state — compute during render instead. Check for `useEffect` + `useRef` to track previous values — use `useState` + render comparison instead — see Pattern 15

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
# ALL severities matter — fix LOW too, not just CRITICAL

# BUILD: Verify nothing broke
npm run build 2>&1
```

**The debugging session is NOT complete until:** `biome check . = 0 errors` AND `npm audit = 0 vulnerabilities` AND `build passes`.

## Debugging Discipline

**1. Autonomous Bug Fixing**
- When given a bug report: just fix it. Don't ask for hand-holding.
- Point at logs, errors, failing tests — then resolve them.
- Zero context switching required from the user.
- Go fix failing CI tests without being told how.

**2. Find Root Causes, Not Band-Aids**
- No temporary fixes. No "it works now" without understanding why.
- If something goes sideways, STOP and re-plan immediately — don't keep pushing the same approach.
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."

**3. Systematic Debugging (4-Phase from obra/superpowers — S9.2 rated)**
- Phase 1: Root Cause Investigation — reproduce, trace data flow, check recent changes
- Phase 2: Pattern Analysis — find working examples, compare, identify differences
- Phase 3: Hypothesis Testing — single hypothesis only, test minimally, verify
- Phase 4: Implementation — failing test first, single fix, verify
- **3-failure rule:** if 3 fixes fail, the approach is wrong — force architectural reassessment
- For deep systematic debugging: use `/systematic-debugging` skill (full 4-phase methodology + techniques)

**4. Verify The Fix Actually Works**
- Never mark a bug as fixed without proving it.
- After deploy: curl the endpoint, verify the response, check the UI.
- Run the exact reproduction steps that triggered the bug.
- Ask yourself: "Would a staff engineer approve this fix?"

**4. Self-Improvement Loop**
- After ANY correction from the user: write a lesson to memory.
- Write rules that prevent the same mistake.
- If you fixed the wrong thing twice, the third attempt must use a fundamentally different approach.

## Instructions

When this skill is invoked:

1. If user provides a pattern name, show the relevant pattern section
2. If user describes a symptom, match it to the closest known pattern
3. If the issue needs deep investigation, recommend `/carmack`
4. **NEVER deploy to production automatically.** If a fix is ready, tell the user what was fixed and ask: "Ready to deploy? I can run `/ship` when you give the go-ahead." Do NOT invoke `/ship` without explicit user approval.
