# AIVA-Specific Guidelines

> These guidelines apply when working in AIVA Claims projects (aivaclaims.com).

## DESIGN COLOR PROHIBITION — PERMANENT BAN (NEVER VIOLATE)

> **This is a hard constraint, not a suggestion. Violating this causes production UI regressions that require emergency hotfixes. Enforce it on every UI change.**

### BANNED COLORS — NEVER USE IN ANY UI

The following Tailwind classes and hex ranges are permanently banned from all design work. They all render as purple or purple-adjacent on the dark navy backgrounds used in aivaclaims.com and similar apps:

| Category | Banned Tailwind Classes |
|----------|------------------------|
| Purple | `purple-*` (all shades) |
| Violet | `violet-*` (all shades) |
| Fuchsia | `fuchsia-*` (all shades) |
| Pink | `pink-*` (all shades) |
| Rose | `rose-*` (all shades) |
| Indigo (purple range) | `indigo-*` (all shades) |

**Banned hex ranges**: #800080–#FF00FF (purple), #FF1493–#FFB6C1 (pink), #EE82EE–#DA70D6 (violet/orchid), #4B0082–#8B008B (dark purple/indigo)

### WHY THIS MATTERS

- **Pink and rose Tailwind classes look purple on dark navy** — `pink-400/30` on a `bg-navy-900` background reads as a purple border. This is NOT obvious from the class name.
- **Indigo spans two perceptual regions** — lower indigo shades (100–400) read as blue, but upper shades (500–900) and `indigo-*` in general are effectively purple.
- A sweep that only looks for `purple` misses the entire `pink-*`, `rose-*`, and `indigo-*` class families. ALWAYS search all six families together.
- This caused a production purple border bug on aivaclaims.com (2026-03) that required multiple hotfix deployments to fully eradicate.

### REQUIRED COLOR SCAN — RUN AFTER EVERY UI CHANGE

```bash
# MANDATORY: Run this after any UI implementation or edit
grep -rn "purple\|violet\|fuchsia\|pink\|rose\|indigo" --include="*.tsx" --include="*.ts" --include="*.css" src/

# Any match = MUST FIX before shipping
# Exception: non-color uses of these words (e.g., "indigo" in a comment, "rose" in a variable name unrelated to color)
```

If ANY color match is found, replace it with an approved VA Design System color (see below).

### APPROVED CANONICAL PALETTE — aivaclaims.com

Use ONLY these colors for aivaclaims.com UI. They match VA.gov's design system, building veteran trust through design familiarity.

| Purpose | Color Name | Hex | Tailwind Arbitrary |
|---------|-----------|-----|-------------------|
| Primary Blue | VA Primary | `#005ea2` | `text-[#005ea2]` |
| Dark Blue | VA Primary Dark | `#1a4480` | `bg-[#1a4480]` |
| Darkest Blue / Navy | VA Primary Darker | `#162e51` | `bg-[#162e51]` |
| Light Blue | VA Blue Light | `#73b3e7` | `text-[#73b3e7]` |
| Cyan / Info | VA Info | `#00bde3` | `border-[#00bde3]` |
| Success / Green | VA Success | `#00a91c` | `text-[#00a91c]` |
| Warning / Gold | VA Gold | `#ffbe2e` | `text-[#ffbe2e]` |
| Error / Red | VA Secondary | `#d83933` | `text-[#d83933]` |
| Error Light | VA Secondary Light | `#f2938c` | `text-[#f2938c]` |

**Gradients**: Use navy `#162e51` → blue `#1a4480` → `#005ea2` progressions. Never gradient into purple range.

### REPLACEMENT CHEATSHEET

| Banned Class | Replacement |
|-------------|-------------|
| `purple-*` | `[#005ea2]` (blue) or `[#162e51]` (navy) |
| `violet-*` | `[#005ea2]` (blue) or `[#73b3e7]` (light blue) |
| `fuchsia-*` | `[#005ea2]` (blue) |
| `pink-*` | `[#73b3e7]` (light blue) or `[#00bde3]` (cyan info) |
| `rose-*` / `rose-400` (error) | `[#d83933]` (VA red) or `[#f2938c]` (VA red light) |
| `indigo-*` | `[#005ea2]` (primary) or `[#1a4480]` (dark blue) |

### ENFORCEMENT CHECKLIST — UI IMPLEMENTATION TASKS

Before marking any UI task complete:

```
[ ] 1. Ran grep scan: grep -rn "purple|violet|fuchsia|pink|rose|indigo" src/
[ ] 2. Zero matches remaining (or all matches are non-color uses)
[ ] 3. All new colors are from the approved VA palette above
[ ] 4. No hex values in the banned ranges (#800080–#FF00FF, #EE82EE–#DA70D6)
[ ] 5. Gradients stay within navy → blue progression, never into purple
```

---

## OG Image & Favicon Generation Standards (MANDATORY)

When generating OG images, favicons, or social sharing assets, follow these specs on the FIRST attempt. Do NOT generate and fix later.

### OG Image Requirements

| Spec | Requirement | Why |
|------|-------------|-----|
| **Dimensions** | Exactly **1200x630px** | Universal standard for Facebook, Twitter, LinkedIn, WhatsApp, iMessage, Slack |
| **File size** | **< 300KB** (target), **< 600KB** (max) | WhatsApp rejects > 600KB; large images = slow unfurls |
| **Format** | **JPEG** (photos/illustrations), **PNG** only if transparency needed | JPEG is 5-10x smaller than PNG for photo-like images |
| **Aspect ratio** | **1.91:1** (1200/630) — use `16:9` in nano-banana then resize | Closest standard ratio; exact resize with magick after |
| **CTA text** | MUST include a call-to-action in the image | "Explore...", "Discover...", "Try...", "Join..." |
| **Safe zone** | Keep text/logos within center 1000x500px | Edges get cropped on some platforms |

### OG Meta Tag Requirements

| Tag | Optimal Length | Example |
|-----|---------------|---------|
| `og:title` | **50-60 chars** | "Sanders-King Family Heritage — Explore 7 Generations of History" (58) |
| `og:description` | **110-160 chars** | Full sentence with keywords, ending with a period. (155) |
| `og:image:width` | `1200` | Always set explicitly |
| `og:image:height` | `630` | Always set explicitly |
| `og:image:type` | `image/jpeg` or `image/png` | Match actual format |

### Required Meta Tags (Complete Set)

```html
<!-- OG -->
<meta property="og:title" content="[50-60 chars with CTA verb]" />
<meta property="og:description" content="[110-160 chars, keyword-rich]" />
<meta property="og:type" content="website" />
<meta property="og:url" content="https://example.com/" />
<meta property="og:image" content="https://example.com/og-image.jpg" />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:image:type" content="image/jpeg" />
<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="[same as og:title]" />
<meta name="twitter:description" content="[same as og:description]" />
<meta name="twitter:image" content="[same as og:image]" />
```

### nano-banana → Production OG Workflow

```bash
# Step 1: Generate at 2K 16:9 (closest to 1.91:1)
nano-banana "your prompt — MUST include CTA text like 'Explore...' or 'Discover...'" -s 2K -a 16:9 -o og-image -d /tmp

# Step 2: Resize to exact 1200x630 and convert to optimized JPEG
magick /tmp/og-image.png -resize 1200x630! -quality 80 -strip public/og-image.jpg

# Step 3: Verify size < 300KB and dimensions = 1200x630
ls -la public/og-image.jpg  # Should be < 300KB
magick identify public/og-image.jpg  # Should show 1200x630

# Step 4: If still > 600KB, reduce quality
magick /tmp/og-image.png -resize 1200x630! -quality 60 -strip public/og-image.jpg
```

### Favicon Generation Workflow

```bash
# Step 1: Generate square icon at 1K
nano-banana "icon prompt — simple, recognizable at 16px, flat design, no text" -s 1K -a 1:1 -o favicon-src -d /tmp

# Step 2: Create all required sizes
magick /tmp/favicon-src.png -resize 180x180 public/apple-touch-icon.png
magick /tmp/favicon-src.png -resize 192x192 public/favicon-192.png
magick /tmp/favicon-src.png -resize 512x512 public/favicon-512.png
magick /tmp/favicon-src.png -resize 32x32 /tmp/f32.png
magick /tmp/favicon-src.png -resize 16x16 /tmp/f16.png
magick /tmp/f16.png /tmp/f32.png public/favicon.ico

# Step 3: Create web manifest
cat > public/site.webmanifest << 'EOF'
{
  "name": "Site Name",
  "short_name": "Short",
  "icons": [
    { "src": "/favicon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/favicon-512.png", "sizes": "512x512", "type": "image/png" }
  ],
  "theme_color": "#hex",
  "background_color": "#hex",
  "display": "standalone"
}
EOF
```

### Required HTML Favicon Links

```html
<link rel="icon" href="/favicon.ico" sizes="32x32" />
<link rel="icon" href="/favicon-192.png" type="image/png" sizes="192x192" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="manifest" href="/site.webmanifest" />
<meta name="theme-color" content="#hex" />
```

### Pre-Deploy Checklist

```bash
# MANDATORY: Run after generating OG image + favicon
[ ] OG image is JPEG (not PNG unless transparency needed)
[ ] OG image dimensions = 1200x630: magick identify public/og-image.jpg
[ ] OG image size < 300KB: ls -la public/og-image.jpg
[ ] OG image has CTA text visible in the image
[ ] og:title is 50-60 characters (not < 40)
[ ] og:description is 110-160 characters (not < 100)
[ ] og:image:width = 1200, og:image:height = 630, og:image:type set
[ ] twitter:card = summary_large_image
[ ] twitter:image matches og:image URL
[ ] favicon.ico exists (multi-size 16+32)
[ ] apple-touch-icon.png = 180x180
[ ] site.webmanifest references 192 + 512 icons
[ ] theme-color meta tag matches site brand
```

---

## Social Card / OG Image Debugging Playbook

When debugging "Twitter/social card shows old image":

### Investigation Order
1. **Download Twitter's cached image** (`pbs.twimg.com/card_img/...`) and compare visually with local file
2. **Check TWO cache layers**: page metadata cache (7-day TTL) AND image CDN cache (indefinite)
3. **Verify all 4 source files** have consistent image URLs: `index.html`, `page-metadata.ts`, `render-html.ts`, `SEO.tsx`
4. **Test as Twitterbot**: `curl -s -H "User-Agent: Twitterbot/1.0" https://site.com/ | grep twitter:image`
5. **Compare MD5**: download served image vs local file to confirm server isn't serving stale version

### Nuclear Fix (Busts Both Cache Layers)
```bash
# Add ?v=YYYYMMDD to image URL in ALL 4 source files
# This creates a new image URL Twitter has NEVER fetched
grep -rn "og-card\|og-social\|og-image" index.html src/worker/seo/ src/react-app/components/SEO.tsx
# Update all matches to include ?v=20260306
# Deploy, then share https://yoursite.com/?v=3 on Twitter (fresh page URL too)
```

### Key Insight
File rename alone doesn't work — it busts image CDN but NOT page metadata cache. The `?v=` param on the image URL busts BOTH because Twitter treats `image.png?v=1` and `image.png?v=2` as completely different resources.

---

## Cloudflare Workers Admin Auth Pattern (AIVA / Hono)

**CRITICAL: Never write a custom `requireAdmin()` that only checks Clerk metadata.** The production admin at `help@aivaclaims.com` uses `is_admin = 1` in the DB — NOT Clerk `publicMetadata.role`. A metadata-only check silently returns 403 for the real admin on every route it guards.

### The Rule

Any new route file that needs admin protection MUST use one of:
1. **`adminMiddleware`** from `src/worker/index.ts` — pass as Hono middleware
2. **An async `requireAdmin(c)`** that mirrors `adminMiddleware` exactly:

```typescript
// ✅ CORRECT — async with DB fallback
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

// ❌ WRONG — sync, metadata-only, blocks DB-based admin
function requireAdmin(c: Context) {
  const user = requireClerkAuth(c);
  if (user.publicMetadata?.role !== "admin") throw new Error("Admin access required");
  return user;
}
```

### Quick Detection
```bash
# Find metadata-only requireAdmin (sync = no DB fallback)
grep -B2 -A8 "function requireAdmin" src/worker/routes/*.ts | grep -A5 "publicMetadata"

# All call sites must await
grep -rn "requireAdmin(c)" src/worker/routes/ --include="*.ts" | grep -v "await "
```

**Incident (2026-03-13)**: `adminClerk.ts` shipped with synchronous metadata-only check. Every `/api/admin/clerk/*` route returned 403, making the Referrals tab, user lookup, and referrers list fail silently for the real admin.
