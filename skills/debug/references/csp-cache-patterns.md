# CSP & Cache Patterns

## Pattern 4: Cloudflare WWW Redirect Auth Break

Cookies set on `your-app.com` aren't sent to `www.your-app.com`. Edge cache serves HTML before Worker redirect runs.

### Quick Detection
```bash
curl -sI "https://www.your-app.com" | grep -E "^(HTTP|location)"
# Should return 301 to non-www
```

Full guide: CLAUDE.md "Cloudflare WWW Redirect Fix" section

---

## Pattern 5: Twitter/Social Card Showing Old OG Image

**Rank: #4 production debugging trap.**

Social platforms (Twitter/X, Facebook, LinkedIn) cache OG card images on TWO levels: page metadata cache AND image CDN cache. Changing the image file or meta tags alone won't update the card.

### Symptoms
- Twitter card preview shows old/outdated image (e.g., old dollar amounts, old design)
- Image file is correct on your server but social platforms show cached version
- Card Validator or third-party tools show correct tags but Twitter app shows old card
- `pbs.twimg.com/card_img/` URL still serves the old image

### Two Cache Layers
| Layer | What It Caches | TTL | How to Bust |
|-------|---------------|-----|-------------|
| **Page metadata** | og:image URL, title, description for a given page URL | ~7 days | Card Validator, tweet the URL, or use `?v=N` query param on page URL |
| **Image CDN** | Actual image bytes at the og:image URL | Indefinite | Add `?v=YYYYMMDD` cache-bust param to the image URL in meta tags |

### Quick Detection
```bash
# 1. Check what your server actually serves to Twitterbot
curl -s -H "User-Agent: Twitterbot/1.0" "https://yoursite.com/" | grep "og:image\|twitter:image"

# 2. Download what the server serves vs what Twitter cached
curl -s -o /tmp/served.png "$(curl -s -H 'User-Agent: Twitterbot/1.0' https://yoursite.com/ | grep -oP 'twitter:image" content="\K[^"]+')"
# Compare visually with Read tool

# 3. Download Twitter's cached card image (from pbs.twimg.com URL)
curl -s -o /tmp/twitter-cached.jpg "https://pbs.twimg.com/card_img/XXXXX/XXXXX?format=jpg&name=medium"
# Compare visually -- if different from served image, it's a cache issue

# 4. Check all 4 files for consistency
grep -rn "og-card\|og-social\|og-image\|og_image" index.html src/worker/seo/ src/react-app/components/SEO.tsx
```

### Fix Pattern (Nuclear -- Busts Both Cache Layers)
1. **Add `?v=YYYYMMDD` to image URL in ALL source files:**
   - `index.html` (static meta tags)
   - Worker SSR (`page-metadata.ts`, `render-html.ts`)
   - React SEO component (`SEO.tsx`)
2. **Deploy**
3. **Verify**: `curl -s -H "User-Agent: Twitterbot/1.0" https://yoursite.com/ | grep "twitter:image"`
4. **Share with fresh page URL**: `https://yoursite.com/?v=3` bypasses page metadata cache
5. **Use Card Validator** to update bare URL: `cards-dev.x.com/validator`

### Why File Rename Alone Doesn't Work
Renaming `og-social-card.png` -> `og-card-2026.png` busts the image CDN cache but NOT the page metadata cache. Twitter still serves its cached card for `yoursite.com` until re-crawled. The `?v=` param on the image URL busts BOTH layers because Twitter treats it as a new image URL it has never fetched.

### Real-World Case: Production App OG Card (2026-03-06)
- **Symptom**: Twitter showed $1.38M card, server had $1.42M card
- **Investigation**: File rename + meta tag fixes deployed, but Twitter's `pbs.twimg.com` CDN still served old image
- **Root cause**: Two cache layers -- page metadata AND image CDN both stale
- **Fix**: Added `?v=20260306` to image URL in all 4 source files, deployed, shared with `?v=3` page URL
- **Files**: `index.html`, `src/worker/seo/page-metadata.ts`, `src/worker/seo/render-html.ts`, `src/react-app/components/SEO.tsx`

---

## Pattern 9: Third-Party Embed CSP Blocking (Multi-Layer)

**Rank: #4 production crash cause (silent blank page).**

Third-party embeds (DocuSeal, Stripe, etc.) need CSP permissions across **ALL SIX** directives, not just `frame-src`. Web component embeds (like `@docuseal/react`) render in the parent page context, so every resource they load is governed by your CSP. Missing even one directive causes partial rendering -- form fields appear but document background is invisible.

### Symptoms
- Embedded form shows only interactive fields (inputs, signature boxes) but no document text/background
- Page loads but embedded widget is blank white
- Works in development (no CSP) but broken in production
- Browser console shows CSP violation warnings (if you check)

### Three-Layer Bug Pattern
1. **Stale resource ID** -- config references a deleted/old template/product
2. **CSP blocks the embed script/iframe** -- widget doesn't load at all
3. **CSP blocks resource CDN** -- widget loads but images/fonts/styles from third-party CDN are blocked, causing partial rendering

### CSP Directives Checklist for ANY Third-Party Embed
When adding a new third-party embed, you MUST check ALL SIX directives:

| Directive | What It Controls | Example Domain |
|-----------|-----------------|----------------|
| `script-src` | JS scripts loaded by the embed | `cdn.docuseal.com` |
| `connect-src` | API/fetch calls the embed makes | `docuseal.com/embed/forms` |
| `frame-src` | Iframes (if embed uses them) | `docuseal.com` |
| `img-src` | Document page images, logos | `*.s3.amazonaws.com` (presigned S3 URLs!) |
| `style-src` | CSS styles for the form | `docuseal.com` |
| `font-src` | Custom fonts | `docuseal.com` |

### Quick Detection
```bash
# 1. Check CSP for ALL relevant directives (not just frame-src!)
curl -sI "https://yoursite.com/" | grep -i "content-security-policy" | tr ';' '\n'

# 2. Check the embed's actual resource domains
# Download the embed script and find all URLs it references
curl -s "https://cdn.docuseal.com/js/form.js" | grep -oE 'https?://[a-zA-Z0-9._/-]+' | sort -u

# 3. Check where the embed serves images from (CRITICAL -- often a CDN, not the main domain)
# DocuSeal: images come from docuseal.s3.amazonaws.com (AWS S3 presigned URLs)
# Stripe: images come from *.stripe.com
# Clerk: images come from img.clerk.com

# 4. Validate resource ID exists via API
curl -s "https://api.docuseal.com/templates/$ID" -H "X-Auth-Token: $KEY"
```

### Fix Pattern
1. Update any stale IDs in `wrangler.json` (or secrets)
2. Add the third-party domain to ALL SIX CSP directives in `securityHeaders.ts`
3. Check where the embed serves **images** from -- it's often a CDN subdomain, NOT the main domain
4. Redeploy and verify the full form renders (not just form fields)

### Real-World Case: Production App DocuSeal (2026-03-08)
Three separate deploys needed because CSP was fixed incrementally instead of comprehensively:
- **Deploy 1**: Added `docuseal.com` to `frame-src`, `connect-src`, `script-src` -- form fields appeared but document was blank
- **Deploy 2**: Added `docuseal.com` to `img-src`, `style-src`, `font-src` -- still blank document
- **Deploy 3**: Added `*.s3.amazonaws.com` to `img-src` -- document finally rendered
- **Root cause**: DocuSeal serves document page images from **presigned AWS S3 URLs** (`docuseal.s3.amazonaws.com`), not from `docuseal.com`
- **Lesson**: Always trace the actual resource URLs an embed loads (check network tab or the embed's JS source), don't assume they come from the main domain

### Real-World Case: Production App Clerk Social Login Icons (2026-03-31)
Social provider icons (Google, Apple) on `/sign-up` and `/sign-in` were completely broken -- empty boxes with no images, NO console errors (CSP violations don't always surface in console).
- **Root cause**: `img-src` CSP was missing `https://img.clerk.com`. Clerk serves provider logos from that CDN, not from `*.clerk.com`
- **Fix**: Added `https://img.clerk.com` to `img-src` in `securityHeaders.ts`
- **Lesson**: When icons/images from a third-party are broken, ALWAYS check CSP `img-src` FIRST -- before assuming CSS color issues. CSP blocks are silent (no console errors by default)

### Required CSP Domains for Common Third Parties
```bash
# Quick audit: verify all third-party CDN domains are in CSP
CSP_FILE="src/worker/middleware/securityHeaders.ts"
grep -q "img.clerk.com" "$CSP_FILE"          || echo "MISSING: img-src -> https://img.clerk.com (social login icons)"
grep -q "clerk-telemetry" "$CSP_FILE"         || echo "MISSING: connect-src -> https://*.clerk-telemetry.com"
grep -q "s3.amazonaws.com" "$CSP_FILE"        || echo "MISSING: img-src -> https://*.s3.amazonaws.com (DocuSeal images)"
grep -q "cdn.brevo.com" "$CSP_FILE"           || echo "MISSING: script-src -> https://cdn.brevo.com (Brevo widget)"
grep -q "www.facebook.com" "$CSP_FILE"        || echo "MISSING: img-src -> https://www.facebook.com (Meta Pixel)"
grep -q "googletagmanager.com" "$CSP_FILE"    || echo "MISSING: script-src -> https://www.googletagmanager.com (GA4)"
```

---

## Deploy Logs Users Out (SPA Chunk Invalidation)

**#5 production crash cause.** Every Cloudflare Workers deployment logs out all active users.

### Root Cause
`wrangler deploy` changes JS chunk hashes. SPA fallback (`not_found_handling: "single-page-application"`) returns HTML for missing `.js` files instead of 404. React crashes on HTML-as-JS, user reloads, Clerk session lost.

### Quick Detection
```bash
# Verify all three defenses exist:
grep "vite:preloadError" src/react-app/main.tsx                          # Client recovery
grep -E "ChunkLoadError|dynamically imported" src/react-app/components/ErrorBoundary.tsx  # ErrorBoundary
grep "CDN-Cache-Control" src/worker/middleware/securityHeaders.ts         # Edge cache prevention
```
- If ANY of the three is missing: **BUG** -- users will be logged out on every deploy

### Fix
1. **main.tsx**: Add `vite:preloadError` listener that auto-reloads once (sessionStorage flag prevents loops)
2. **ErrorBoundary**: Detect `ChunkLoadError` / `dynamically imported module` and auto-reload once
3. **securityHeaders**: Add `CDN-Cache-Control: no-store` header to prevent CF edge caching stale HTML

### Real-World Case: Production App (2026-03-15)
- **Symptom**: User had to re-login after every `wrangler deploy`
- **Root cause**: CF edge cached HTML with old chunk refs. Old chunks 404'd as HTML (SPA fallback). React crashed.
- **Fix**: Three-layer defense (client preload recovery + ErrorBoundary chunk detection + CDN cache header)
- **Files**: `src/react-app/main.tsx`, `src/react-app/components/ErrorBoundary.tsx`, `src/worker/middleware/securityHeaders.ts`

---

## CF Pages Stale Version / Failed Deploy

**#6 production trap.** Version display shows `"dev"`, old timestamp, or wrong commit after pushing code.

### Root Cause (5 interacting issues)
1. `version.json` committed to git with local `"dev"` values
2. Service worker caches version.json (cache-first strategy)
3. No `Cache-Control: no-store` header for `/version.json`
4. `.env.local` has `CLOUDFLARE_API_TOKEN` that overrides wrangler OAuth token
5. No CF Pages GitHub auto-deploy integration

### Quick Detection
```bash
# What does production actually serve?
curl -s "https://YOUR_SITE.pages.dev/version.json"
# If "dev" or old SHA -> stale deploy

# Is version.json git-tracked? (should NOT be)
git ls-files public/version.json
# If output -> BUG: remove from git, add to .gitignore

# Is .env.local overriding wrangler auth?
grep "CLOUDFLARE_API_TOKEN" .env.local 2>/dev/null
# If found -> remove it, use wrangler OAuth from ~/.wrangler/config

# Does service worker cache version.json?
grep "version.json\|NETWORK_ONLY" public/sw.js
# If not in NETWORK_ONLY -> BUG: SW serves stale version

# Does _headers bypass cache?
grep "version.json" public/_headers
# If missing -> BUG: CDN may cache it
```

### Fix Checklist
- [ ] `public/version.json` in `.gitignore` + `git rm --cached`
- [ ] `generate-version.js` has git fallback: `execSync('git rev-parse HEAD')`
- [ ] `vite.config.ts` `__BUILD_VERSION__` has same git fallback
- [ ] `public/_headers` has `Cache-Control: no-store` for `/version.json`
- [ ] `public/sw.js` has `/version\.json/` in `NETWORK_ONLY_PATTERNS`
- [ ] `.env.local` does NOT have `CLOUDFLARE_API_TOKEN` (use wrangler OAuth)
- [ ] `npm run deploy` works: `wrangler pages deploy dist`

### The `.env.local` Token Override Trap
Wrangler auto-loads `.env.local` via dotenv. A broken `CLOUDFLARE_API_TOKEN` there overrides the wrangler OAuth token (which may have `pages:write`). `env -u` doesn't help -- wrangler reads the file directly. Only fix: remove the token from `.env.local`.

- **Incident (2026-03-17)**: 6 pushes to main, none deployed. Five interacting causes required five fixes across `.gitignore`, `generate-version.js`, `vite.config.ts`, `_headers`, `sw.js`, and `.env.local`.
