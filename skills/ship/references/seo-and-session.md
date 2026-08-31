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

## Phase 1.4a: OG / SOCIAL PREVIEW METADATA (PUBLIC SITES)

**Purpose**: Every shipped public site should look intentional when pasted into email, Slack, iMessage, LinkedIn, X, Discord, or procurement notes. A live site without OG/Twitter metadata or a preview image looks unfinished even if the app works.

**Trigger**: Run for every public website, landing page, app, dashboard, or Cloudflare Worker returning HTML. Skip only for private APIs with no HTML surface.

**Required fields**:
- `<title>` and `<meta name="description">`
- `<link rel="canonical">`
- `og:site_name`, `og:title`, `og:description`, `og:type`, `og:url`
- `og:image`, `og:image:alt`, `og:image:width`, `og:image:height`
- `twitter:card`, `twitter:title`, `twitter:description`, `twitter:image`, `twitter:image:alt`

**Image requirements**:
- Create the image if it does not exist.
- Prefer 1200x630 PNG/JPEG/WebP. SVG is acceptable for Worker demos when the image URL returns `image/svg+xml` and the tags declare the type.
- Use an absolute HTTPS URL in metadata, not a relative path.
- Add a cache-busting version (`?v=<date-or-sha>`) because social crawlers cache aggressively.
- The image must show the real product/project identity, not a blank logo-only placeholder.

```bash
HTML=$(curl -s "$DEPLOY_URL/?og_check=$(date +%s)")
printf "%s" "$HTML" | rg -i '<title>|name="description"|rel="canonical"|property="og:|name="twitter:'
OG_URL=$(printf "%s" "$HTML" | grep -oP 'property="og:image" content="\K[^"]+' | head -1)
[ -n "$OG_URL" ] || { echo "BLOCK: og:image missing"; exit 1; }
curl -sI "$OG_URL" | rg -i '^(HTTP|content-type)'
```

- If metadata is missing: **BLOCK** — add it before deployment.
- If the image URL is relative, 404s, or does not return `image/*`: **BLOCK**.
- If `twitter:*` uses `property=` instead of `name=`: WARN and fix before reporting success.

**improvebayarea.com — city-count surfaces (EVERY ship of this repo):**
The OG JPEG is a static `public/og.jpg` rebuilt by `scripts/build-og.sh`. HTML tags interpolate `cityNames().length`; the pixels do not. After adding a city, if the script is not re-run, Slack/iMessage still show the old count (2026-08-23: tags said 25, JPEG still said 21).

BLOCK unless:
```bash
cd <improvebayarea-repo>
timeout 120 ./node_modules/.bin/vitest run src/ui_cities.test.ts src/cities.test.ts
```
That suite (a) asserts every city name appears in homepage HTML, (b) OCRs `public/og.jpg` and requires `One tap. N cities.` to equal `CITIES.length`, (c) requires `og.jpg?v=${OG_IMAGE_VERSION}` on homepage + trust pages.

If OCR reports a different N: run `bash scripts/build-og.sh`, bump `OG_IMAGE_VERSION` in `src/brand.ts` to today (`YYYY-MM-DD`), commit all of `public/og.{jpg,png,webp}`. Do not ship a cache-buster bump without new pixels, or crawlers keep the old 21.

Post-deploy: cache-busted `curl` of live `og:title` AND OCR of live `/og.jpg?v=…` must both show the same N.

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

**3. Hono Set-Cookie append check** — Prevent outer middleware from clobbering inner cookies:
```bash
# Every c.header("Set-Cookie", ...) must use {append: true}
MISSING=$(grep -rn 'c\.header("Set-Cookie"' src/worker/ 2>/dev/null | grep -v "append: true" || true)
if [ -n "$MISSING" ]; then
  echo "BLOCK: Set-Cookie calls missing {append: true}:"
  echo "$MISSING"
fi
```
- If any `c.header("Set-Cookie", ...)` lacks `{append: true}`: **BLOCK** — outer middleware will silently overwrite inner cookies (real bug 2026-05-05: aiva_visit clobbered by aiva_cf for ~3h)
- After deploy: `curl -sI -H "Accept: text/html" -A "Mozilla/5.0 Chrome/147" "$DEPLOY_URL/?cb=$(openssl rand -hex 4)" | grep -i set-cookie` — verify ALL expected cookies present (not just one)

**3. SPA Fallback Awareness**:
- `not_found_handling: "single-page-application"` in wrangler.json means missing `.js` files return HTML 200 (not 404)
- This is required for client-side routing but causes the chunk crash bug
- The client-side recovery (vite:preloadError + ErrorBoundary) is the mitigation — it MUST exist
