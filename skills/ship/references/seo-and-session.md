# SEO & Session Safety

Covers Phase 1.4 (SEO/sitemap consistency) and Phase 1.42 (deploy session invalidation check).

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
