---
name: carmack
user-invocable: true
description: "Universal engineering agent: build features, fix bugs, deep debugging. Covers planning (PRDs, brainstorming), code review (TypeScript/React 19, Rust, security, performance), feature implementation (ralph mode), git safety, browser automation, task tracking, Codex second-opinion, and web research. The one skill for all engineering work."
---

# /carmack - Engineering Agent

Universal engineering agent for building, debugging, fixing, reviewing, and shipping. Combines carmack-mode deep debugging with systematic 5-phase investigation, plus all development workflow tools.

## Usage

```
/carmack [issue or feature description]
```

## Examples

- `/carmack intermittent 500 errors on /api/auth`
- `/carmack add email notification feature`
- `/carmack memory leak in background worker`
- `/carmack test started failing after merge`
- `/carmack race condition causing data corruption`
- `/carmack build broke after dependency update`

## Carmack Philosophy

1. Evidence over assumptions
2. Minimal reproduction cases
3. Debugger over print statements
4. Surgical fixes, not rewrites
5. Closed-loop verification
6. Know what NOT to build — use existing tools over custom implementations
7. Ship, measure, iterate — perfection is the enemy of validation

---

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

## Build Decision Framework

Before building ANYTHING, run this checklist. The best engineers aren't the ones who know the most — they're the ones who know what NOT to build.

### Step 1: Should You Build This?

Ask: **Does a production-grade solution already exist?**

| Domain | DON'T Build | USE Instead |
|--------|------------|-------------|
| Auth | Custom login/sessions/OAuth | Clerk, Supabase Auth, Auth.js |
| Payments | Custom payment processing | Stripe (45 min to integrate) |
| UI Components | Raw CSS, custom primitives | Tailwind + shadcn/ui + Radix |
| Forms + Validation | Custom validators | Zod + React Hook Form |
| State Management | Redux, deep Context trees | Zustand (client), Server Components (server) |
| APIs (MVP stage) | Custom REST from scratch | tRPC, Server Actions |
| Database | Raw SQL, self-hosted DB | Prisma + managed Postgres (Supabase/Neon) |
| File Uploads | Custom storage/CDN | UploadThing, Cloudinary |
| Search | Custom full-text search | Algolia, Typesense, Meilisearch |
| Realtime | Custom WebSocket infra | Supabase Realtime, Pusher, PartyKit |
| Deployment | Manual SSH/deploy scripts | Vercel one-click, Railway, Render |
| Error Monitoring | Manual log checking | Sentry (set up day 1, free tier) |
| Analytics | Custom tracking | PostHog, Plausible (set up before launch) |

### Step 2: Red Flag Detection

Before implementing a feature, check for these time sinks:

```bash
# STOP if you're about to:
# - Spend >2 hours on auth for an unvalidated MVP
# - Write raw CSS when Tailwind covers it
# - Build a custom API layer before you have 10 users
# - Deploy manually instead of push-to-deploy
# - Skip error monitoring ("I'll add it later")
# - Build custom file upload handling
# - Roll your own search engine
# - Hardcode API keys anywhere (use .env + .gitignore)
```

### Step 3: Time Budget Rule

If a feature takes >1 day and a service solves it in <1 hour, use the service. Your energy is worth more than your custom implementation. Migrate later IF real usage data justifies it.

## UX Pre-Investigation Quick Checks

Before diving into deep Carmack-mode investigation of a UI issue, run these 5-minute scans first. These catch the most common bugs without needing a full reproduction harness.

### Quick Scan Commands

```bash
# 1. Find alert() calls — always replace with inline error state
grep -rn "alert(" --include="*.tsx" src/react-app/

# 2. Find async onClick without disabled prop — double-click = duplicate requests
grep -rn "onClick.*async\|onClick.*void" --include="*.tsx" src/ | grep -v "disabled="

# 3. Find catch blocks with only console.error (silent to user)
grep -rn "console.error" --include="*.tsx" src/react-app/pages/

# 4. Find flex rows with text content missing min-w-0 (text overflow on mobile)
grep -rn "flex items-center gap" --include="*.tsx" src/ | grep -v "min-w-0"

# 5. Find 2-column grids without sm: responsive breakpoint (overflow at 375px)
grep -rn "grid-cols-2" --include="*.tsx" src/ | grep -v "sm:grid-cols"

# 6. Find user preference writes without App.tsx restoration
grep -rn "localStorage.setItem" --include="*.tsx" src/react-app/ | grep -v "App.tsx"
```

### UX Pre-Check Triage Table

| Finding | Severity | Immediate Fix |
|---------|----------|---------------|
| `alert(message)` in catch/validation | P1 — Always replace | `useState<string\|null>(null)` + inline display |
| Async `onClick` without `disabled` | P2 — Double-click risk | `isLoading` state + `disabled={isLoading}` |
| `catch` with only `console.error` | P2 — Silent failure | Add `setError(err.message)` |
| `flex items-center gap-X` no `min-w-0` | P2 — Mobile overflow | `min-w-0 flex-1` + `flex-shrink-0` on icons |
| `grid-cols-2` without `sm:grid-cols` | P2 — 375px overflow | `grid-cols-1 sm:grid-cols-2` |
| `localStorage.setItem` in component only | P2 — Pref resets on reload | Add `useEffect([], [])` reader in `App.tsx` |
| `<iframe>` with blob URL for PDFs | P1 — Blank on iOS | Detect iOS, show Open/Download buttons instead |
| `max-h-[90vh]` on modals | P2 — iOS address bar | Use `max-h-[90dvh]` (dynamic viewport height) |
| `opacity-0 group-hover:opacity-100` only | P2 — Invisible on touch | Add always-visible alternative button |

### iOS Safari Compatibility Quick Scan

```bash
# 7. Find PDF iframes with blob URLs (blank on iOS)
grep -rn "iframe.*blob\|iframe.*pdf" --include="*.tsx" src/

# 8. Find vh units in modals (should be dvh for iOS)
grep -rn "max-h-\[.*vh\]" --include="*.tsx" src/ | grep -v "dvh"

# 9. Find hover-only UI with no touch fallback
grep -rn "opacity-0 group-hover:opacity-100" --include="*.tsx" src/
```

### Flex Text Overflow: Full Diagnosis Flow

When users report "text escaping boxes on mobile":

```bash
# Step 1: Find all flex rows with text children
grep -rn "flex items-center" --include="*.tsx" src/ | head -30

# Step 2: For each hit, check if text wrapper has min-w-0
# Open the file, look for:
# <div className="flex items-center gap-X">
#   <div className="w-N h-N">icon</div>  ← needs flex-shrink-0
#   <div>text</div>                       ← needs min-w-0

# Step 3: Check grids that hold these flex rows
grep -rn "grid grid-cols" --include="*.tsx" src/ | grep -v "sm:\|md:"

# Step 4: Test at 375px viewport width
# Chrome DevTools → Toggle device toolbar → iPhone SE (375px)
# Any card where text bleeds past the right edge = this bug
```

**Root cause in one sentence**: Grid cells constrain width via `minmax(0, 1fr)`, but flex children inside them have `min-width: auto` and claim their natural text width, overflowing the cell.

**Complete fix recipe** (apply all 4 together):
```jsx
// Outer flex container
<div className="flex items-center gap-3 min-w-0 flex-1">
  {/* Fixed-size icon */}
  <div className="w-10 h-10 rounded-xl flex-shrink-0">
    <Icon />
  </div>
  {/* Text wrapper */}
  <div className="min-w-0">
    <h4 className="text-sm font-semibold break-words">Long title text</h4>
    <p className="text-xs text-white/60 truncate">Supporting text</p>
  </div>
</div>
```

### Hono / Cloudflare Workers HTML — Text Overflow Prevention

When writing HTML pages served from Hono Workers (JSX templates, `c.html()`, or React SSR), apply these rules to prevent text escaping bounding boxes. This applies to **any** server-rendered HTML — not just React SPAs.

#### Global CSS Rules (MANDATORY for every Hono HTML page)

Every HTML page served by a Hono Worker MUST include these defensive CSS rules, either inline or in a stylesheet:

```css
/* Prevent text overflow globally */
* { min-width: 0; }
p, li, span, h1, h2, h3, h4, h5, h6, td, th, label, a {
  overflow-wrap: break-word;
  word-wrap: break-word;
}
table { display: block; overflow-x: auto; max-width: 100%; }
main { overflow-x: hidden; }
```

**Why**: Without `min-width: 0`, flex children claim their natural text width and overflow containers. Without `overflow-wrap: break-word`, long words (URLs, email addresses, UUIDs) escape fixed-width boxes. Without `overflow-x: auto` on tables, wide tables push the entire page sideways on mobile.

#### Quick Scan Commands (Hono/HTML projects)

```bash
# 1. Find flex containers without min-w-0 on text children (Tailwind)
grep -rn "flex.*items-.*gap" --include="*.tsx" --include="*.ts" --include="*.html" src/ | grep -v "min-w-0"

# 2. Find rigid min-width that forces overflow on mobile
grep -rn "min-w-\[" --include="*.tsx" --include="*.ts" src/ | grep -v "min-w-0\|min-w-\[0"

# 3. Find grids without responsive breakpoints
grep -rn "grid-cols-[2-9]" --include="*.tsx" --include="*.ts" src/ | grep -v "sm:\|md:\|lg:"

# 4. Find fixed-width columns that break on small screens
grep -rn "w-[0-9]\{2,\}\b\|w-\[.*px\]" --include="*.tsx" --include="*.ts" src/ | grep "shrink-0\|flex-none"

# 5. Find tables without overflow wrapper
grep -rn "<table" --include="*.tsx" --include="*.ts" --include="*.html" src/ | grep -v "overflow"

# 6. Check if global overflow prevention exists in CSS
grep -rn "overflow-wrap\|word-wrap\|break-word\|min-width.*0" --include="*.css" src/
```

#### Hono HTML Overflow Triage Table

| Pattern | Problem | Fix |
|---------|---------|-----|
| `min-w-[120px]` on flex child | Forces horizontal overflow on 375px screens | Use `shrink-0` instead, or remove min-width |
| `w-28 shrink-0` on date/label column | Wide rigid column steals space from content | `sm:w-28` (stack on mobile) or `flex-col sm:flex-row` |
| `flex gap-X` with text child, no `min-w-0` | Text claims natural width, overflows container | Add `min-w-0` on text wrapper div |
| `<table>` without overflow wrapper | Wide tables push page horizontally | Wrap in `div.overflow-x-auto` or CSS `table { display: block; overflow-x: auto; }` |
| Long strings (URLs, emails) in fixed cards | Text bleeds past card border | `overflow-wrap: break-word` on the container |
| SVG `<text>` without truncation | Names/labels overflow SVG viewBox | Truncate to max chars: `text.slice(0, 24) + "…"` |
| `grid-cols-2` without `sm:` prefix | Two columns at 375px = text overflow | `grid-cols-1 sm:grid-cols-2` |
| Icon + text flex row | Icon shrinks, text overflows | `shrink-0` on icon, `min-w-0` on text container |

#### Hono JSX Template Pattern (overflow-safe)

```tsx
// ✅ Overflow-safe Hono JSX layout
app.get("/", (c) => {
  return c.html(
    <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <style>{`
          * { min-width: 0; box-sizing: border-box; }
          body { overflow-x: hidden; }
          p, h1, h2, h3, span, td, th, a {
            overflow-wrap: break-word;
            word-wrap: break-word;
          }
          table { display: block; overflow-x: auto; max-width: 100%; }
        `}</style>
      </head>
      <body>
        {/* Flex layout — always min-w-0 on text children */}
        <div style="display: flex; gap: 1rem; align-items: flex-start;">
          <div style="flex-shrink: 0; width: 40px;">Icon</div>
          <div style="min-width: 0; flex: 1;">
            <h3>Title that might be very long</h3>
            <p>Description text wraps properly</p>
          </div>
        </div>
      </body>
    </html>
  );
});
```

#### When to Apply This

- **Every time** you create a new Hono route that returns HTML
- **Every time** you add Tailwind flex/grid layouts to a Worker-served page
- **Every code review** of Hono/Workers HTML templates
- **After deployment** — screenshot at 375px viewport width and verify no horizontal scroll

---

### Anti-Patterns That Kill Velocity

1. **Building auth from scratch** — #1 time killer. 2 weeks on something users never see
2. **Over-engineering state** — Zustand + Server Components handles 95% of MVPs
3. **Manual deployments** — One mistake away from breaking prod. Automate day 1
4. **Skipping monitoring** — You'll find bugs when users tweet, not when they happen
5. **Pushing straight to main** — Use feature branches + preview deployments, even solo
6. **Chasing perfect before shipping** — Shipped and imperfect beats polished and unlaunched
7. **No onboarding/empty states** — Confused users don't convert, they leave
8. **Relying on memory for decisions** — Document WHY you chose this library/pattern/tradeoff
9. **Postponing refactoring forever** — After every 2-3 features, clean up the mess

### MVP Shipping Checklist

Before calling a feature "done":

```
[ ] Error monitoring configured (Sentry/equivalent)
[ ] Analytics tracking core flows (PostHog/Plausible)
[ ] Secrets in .env files, never committed
[ ] Preview deployments working (auto per PR)
[ ] Empty states guide new users
[ ] README documents setup + key decisions
[ ] Lighthouse score >70
[ ] Push-to-deploy configured (no manual deploys)
```

---

## Planning & Discovery

### Brainstorming

Use before implementing features when requirements are unclear or multiple approaches exist.

**Skip brainstorming when**: Requirements are explicit, user knows exactly what they want, or it's a straightforward bug fix.

**Use brainstorming when**: Vague terms ("make it better"), multiple valid interpretations, trade-offs need exploring.

#### Phase 0: Assess Requirement Clarity

**Signals requirements are clear**: Specific acceptance criteria given, exact behavior described, scope constrained.

**Signals brainstorming needed**: Vague terms used, multiple interpretations exist, trade-offs undiscussed.

#### Phase 1: Understand the Idea

Ask questions **one at a time**. Prefer multiple choice when natural options exist.

**Question techniques:**
- Prefer: "Should notifications be: (a) email only, (b) in-app only, or (c) both?"
- Avoid: "How should users be notified?"
- Start broad → narrow (purpose → users → constraints)
- Validate assumptions explicitly: "I'm assuming users are logged in. Correct?"
- Ask about success criteria early

**Key topics to explore:**

| Topic | Example Questions |
|-------|-------------------|
| Purpose | What problem does this solve? Motivation? |
| Users | Who uses this? What's their context? |
| Constraints | Technical limitations? Timeline? Dependencies? |
| Success | How measure success? What's the happy path? |
| Edge Cases | What shouldn't happen? Error states? |
| Existing Patterns | Similar features in codebase to follow? |

**Exit**: Continue until idea is clear OR user says "proceed" or "let's move on"

#### Phase 2: Explore Approaches

Propose 2-3 concrete approaches:

```markdown
### Approach A: [Name]

[2-3 sentence description]

**Pros:**
- [Benefit 1]

**Cons:**
- [Drawback 1]

**Best when:** [Circumstances where this approach shines]
```

Guidelines: Lead with recommendation, be honest about trade-offs, consider YAGNI, reference codebase patterns.

#### Phase 3: Capture the Design

```markdown
---
date: YYYY-MM-DD
topic: <kebab-case-topic>
---

# <Topic Title>

## What We're Building
[1-2 paragraphs max]

## Why This Approach
[Why chosen over alternatives]

## Key Decisions
- [Decision 1]: [Rationale]

## Open Questions
- [Unresolved for planning phase]

## Next Steps
→ `/workflows:plan` for implementation details
```

**Output:** `docs/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

#### YAGNI Principles

- Don't design for hypothetical future requirements
- Choose the simplest approach that solves the stated problem
- Prefer boring, proven patterns over clever solutions
- Ask "Do we really need this?" when complexity emerges
- Defer decisions that don't need to be made now

#### Anti-Patterns to Avoid

| Anti-Pattern | Better Approach |
|--------------|-----------------|
| Asking 5 questions at once | Ask one at a time |
| Jumping to implementation details | Stay focused on WHAT, not HOW |
| Proposing overly complex solutions | Start simple, add complexity only if needed |
| Ignoring existing codebase patterns | Research what exists first |
| Making assumptions without validating | State assumptions explicitly and confirm |
| Creating lengthy design documents | Keep it concise — details go in the plan |

---

### PRD Generation

Create Product Requirements Documents when planning a feature, starting a new project, or asked to spec out requirements.

**Important:** Do NOT start implementing. Just create the PRD.

#### Step 1: Ask Clarifying Questions

Ask only critical questions where prompt is ambiguous. Use lettered options for quick answers:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

Users can respond "1A, 2C, 3B" for fast iteration. Focus on: Problem/Goal, Core Functionality, Scope/Boundaries, Success Criteria.

#### Step 2: PRD Structure

```markdown
# PRD: [Feature Name]

## Introduction
Brief description and problem it solves.

## Goals
Specific, measurable objectives (bullet list).

## User Stories

### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion (not "works correctly")
- [ ] Another verifiable criterion
- [ ] Typecheck/lint passes
- [ ] **[UI stories only]** Verify in browser using agent-browser

## Functional Requirements
- FR-1: The system must allow users to...
- FR-2: When a user clicks X, the system must...

## Non-Goals (Out of Scope)
What this feature will NOT include.

## Design Considerations (Optional)
UI/UX requirements, mockup links, existing components to reuse.

## Technical Considerations (Optional)
Known constraints, dependencies, performance requirements.

## Success Metrics
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

## Open Questions
Remaining questions or areas needing clarification.
```

**Good acceptance criteria**: "Button shows confirmation dialog before deleting"
**Bad acceptance criteria**: "Works correctly"

**Output:** Save to `tasks/prd-[feature-name].md` (kebab-case).

---

## Code Review

### TypeScript & React 19 Review

#### 🚫 Critical (Block Merge)

| Issue | Why It's Critical |
|-------|-------------------|
| `useEffect` for derived state | Extra render cycle, sync bugs — compute during render instead |
| `useEffect` to react to events | Sync bugs, stale closures — move logic to event handler |
| `useEffect` + `useRef` to track prev value | Extra render cycle — use `[prev, setPrev] = useState()` + render comparison |
| `useEffect` to reset state on prop change | Sync bugs — key the component or compare during render |
| `useEffect` for data fetching | Race conditions, no cache — use TanStack Query / SWR |
| Missing cleanup in `useEffect` | Memory leaks |
| Direct state mutation (`.push()`, `.splice()`) | Silent update failures |
| Conditional hook calls | Breaks Rules of Hooks |
| `key={index}` in dynamic lists | State corruption on reorder |
| `any` type without justification | Type safety bypass |
| `useFormStatus` in same component as `<form>` | Always returns false (React 19 bug) |
| Promise created inside render with `use()` | Infinite loop |
| `alert()` for errors/validation | Blocks JS thread, can't style, breaks UX |
| `dangerouslySetInnerHTML` without DOMPurify | XSS risk — regex sanitizers are bypassable |
| Raw `.innerHTML =` without escapeHtml() | XSS risk — entry points (index.tsx) run before React's auto-escaping |
| `JSON.stringify` in `<script>` with partial escaping (only `<`) | Script breakout — must escape ALL 5 chars: `< > & U+2028 U+2029` per OWASP |
| Template `${var}` in HTML attribute without escapeHtml() | Attribute breakout — `"` in value breaks `href=""` / `content=""` attributes |
| `href={dynamicUrl}` without URL scheme validation | javascript: URI injection — blocks JS execution via `<a href="javascript:...">` |
| Incomplete escapeHtml() (missing `& > ' \``) | Partial escaping leaves attack surface — must cover all 6 chars |
| Data hook without `visibilitychange` refresh | Admin changes invisible to users — every hook reading admin-writable data needs `silentFetch` + visibility listener |
| URL-persisted state (`?step=`, `?tab=`) without auto-advance | State never recalculates when underlying data changes externally — stale navigation |
| Optimistic update without server re-sync | `fetchData()` must be called after successful PUT to pull server-computed side effects |
| Admin write endpoint without dependent field cleanup | Setting `status=completed` but leaving `flag_message="Missing docs"` — dirty write |

#### ⚠️ High Priority

| Issue | Impact | Fix |
|-------|--------|-----|
| Incomplete dependency arrays | Stale closures | Fix deps |
| Props typed as `any` | Runtime errors | Explicit types |
| Unjustified `useMemo`/`useCallback` | Unnecessary complexity | Remove |
| Missing Error Boundaries | Poor error UX | Add boundaries |
| Controlled input initialized with `undefined` | React warning | Use empty string |
| Async `onClick` without `disabled` state | Double-click = duplicate requests | `isLoading` state + `disabled={isLoading}` + spinner |
| `console.error()` in catch without error display | User sees no feedback | Add error state inline near action |
| `flex items-center` with text child, no `min-w-0` | Mobile text overflow | `min-w-0` on flex + text wrapper |
| `localStorage` write without App.tsx reader | Preference resets on reload | `useEffect([], [])` in App.tsx |

#### 📝 Architecture/Style

| Issue | Recommendation |
|-------|----------------|
| Component > 300 lines | Split into smaller components |
| Prop drilling > 2-3 levels | Use composition or context |
| State far from usage | Colocate state |
| Custom hooks without `use` prefix | Follow naming convention |

#### Quick Detection Patterns

**useEffect BAN — NEVER call useEffect directly. Use useMountEffect() for the rare external sync case.**

This is a hard rule, not a guideline. Direct `useEffect` is banned because it seeds race conditions, infinite loops, and stale closures — especially when agents write code. The hook forces implicit synchronization logic when React already provides better declarative primitives.

**The sanctioned escape hatch — `useMountEffect()`:**
```typescript
// This is the ONLY way to run an effect. It wraps useEffect(..., []) with
// explicit intent: "I am syncing with an external system on mount/unmount."
export function useMountEffect(effect: () => void | (() => void)) {
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(effect, []);
}
```

**Valid uses of useMountEffect:**
- DOM integration (focus, scroll position)
- Third-party widget init/destroy lifecycles
- Browser API subscriptions (addEventListener, IntersectionObserver, ResizeObserver)
- WebSocket connect/disconnect
- localStorage read on mount in App.tsx root

**For "reset when ID changes" — use key, not effects:**
```typescript
// ❌ WRONG: useEffect to re-init when ID changes
function VideoPlayer({ videoId }) {
  useEffect(() => { loadVideo(videoId); }, [videoId]);
}

// ✅ CORRECT: key forces clean remount — parent owns the lifecycle boundary
function VideoPlayerWrapper({ videoId }) {
  return <VideoPlayer key={videoId} videoId={videoId} />;
}
function VideoPlayer({ videoId }) {
  useMountEffect(() => { loadVideo(videoId); });
}
```

**Conditional mounting — parent guards preconditions, child mounts clean:**
```typescript
// ❌ WRONG: Guard inside effect
function VideoPlayer({ isLoading }) {
  useEffect(() => { if (!isLoading) playVideo(); }, [isLoading]);
}

// ✅ CORRECT: Mount only when preconditions are met
function VideoPlayerWrapper({ isLoading }) {
  if (isLoading) return <LoadingScreen />;
  return <VideoPlayer />;
}
function VideoPlayer() {
  useMountEffect(() => playVideo());
}
```

**Detection scan (run on every review):**
```bash
# Find ALL direct useEffect usage — each one is a violation unless wrapped in useMountEffect
grep -rn "useEffect" --include="*.tsx" --include="*.ts" src/react-app/ | grep -v node_modules | grep -v "useMountEffect" | grep -v "// eslint-disable"
```

**Anti-Pattern 1: Derived state in useEffect (compute during render instead)**
```typescript
// ❌ WRONG: Extra render cycle, sync bugs
const [fullName, setFullName] = useState('');
useEffect(() => {
  setFullName(firstName + ' ' + lastName);
}, [firstName, lastName]);

// ✅ CORRECT: Compute during render — zero useEffect needed
const fullName = firstName + ' ' + lastName;
```

**Anti-Pattern 2: Event logic in useEffect (move to event handler)**
```typescript
// ❌ WRONG: Reacting to state change that happened in an event
useEffect(() => {
  if (product.isInCart) showNotification('Added!');
}, [product]);

// ✅ CORRECT: Logic in event handler where the change originated
function handleAddToCart() {
  addToCart(product);
  showNotification('Added!');
}
```

**Anti-Pattern 3: Tracking previous values with useEffect (use useState instead)**
```typescript
// ❌ WRONG: useEffect + useRef to track previous value
const prevCount = useRef(count);
useEffect(() => {
  if (prevCount.current !== count) {
    // react to change
  }
  prevCount.current = count;
}, [count]);

// ✅ CORRECT: Compare prev vs current during render
const [prevCount, setPrevCount] = useState(count);
if (prevCount !== count) {
  setPrevCount(count);
  // react to change — this runs during render, no extra cycle
}
```

**Anti-Pattern 4: Resetting state when props change**
```typescript
// ❌ WRONG: useEffect to reset state on prop change
useEffect(() => {
  setSelection(null);
}, [items]);

// ✅ CORRECT: Key the component to force remount
<ItemList items={items} key={itemsId} />

// ✅ ALSO CORRECT: Compare during render
const [prevItems, setPrevItems] = useState(items);
if (prevItems !== items) {
  setPrevItems(items);
  setSelection(null);
}
```

**Anti-Pattern 5: Fetching data in useEffect (use a data library)**
```typescript
// ❌ WRONG: Manual fetch in useEffect (no caching, no loading state, no error handling, race conditions)
useEffect(() => {
  fetch('/api/data').then(r => r.json()).then(setData);
}, []);

// ✅ CORRECT: Use TanStack Query, SWR, or React 19 use() with Suspense
const { data } = useQuery({ queryKey: ['data'], queryFn: fetchData });
```

**ONLY valid uses (via useMountEffect, NEVER raw useEffect):**
| Use Case | Why It's Valid |
|----------|---------------|
| `addEventListener` / `removeEventListener` | External browser API |
| Third-party widget init/destroy | External system lifecycle |
| `IntersectionObserver` / `ResizeObserver` | External browser API |
| WebSocket connect/disconnect | External network |
| `document.title` update | External browser API |
| localStorage read on mount (App.tsx root) | External storage sync |

**Why useMountEffect failures are better than useEffect failures:**
`useMountEffect` failures are binary and loud (ran once, or not at all). Direct `useEffect` failures degrade gradually — flaky behavior, performance regressions, loops — before a hard failure. Choose your bug: loud and obvious beats silent and gradual.

**React 19 Hook Mistakes**

```typescript
// ❌ WRONG: useFormStatus in form component (always returns false)
function Form() {
  const { pending } = useFormStatus();
  return <form action={submit}><button disabled={pending}>Send</button></form>;
}

// ✅ CORRECT: useFormStatus in child component
function SubmitButton() {
  const { pending } = useFormStatus();
  return <button type="submit" disabled={pending}>Send</button>;
}
```

```typescript
// ❌ WRONG: Promise created in render (infinite loop)
function Component() {
  const data = use(fetch('/api/data')); // New promise every render!
}

// ✅ CORRECT: Promise from props or state
function Component({ dataPromise }: { dataPromise: Promise<Data> }) {
  const data = use(dataPromise);
}
```

**State Mutation Detection**

```typescript
// ❌ WRONG: Mutations (no re-render)
items.push(newItem);
setItems(items);

// ✅ CORRECT: Immutable updates
setItems([...items, newItem]);
setArr(arr.map((x, idx) => idx === i ? newValue : x));
```

**TypeScript Red Flags**

```typescript
// ❌ Red flags to catch
const data: any = response;           // Unsafe any
const App: React.FC<Props> = () => {}; // Discouraged pattern

// ✅ Preferred patterns
const data: ResponseType = response;
const App = ({ prop }: Props) => {};  // Explicit props
```

#### State Management Quick Guide

| Data Type | Solution |
|-----------|----------|
| Server/async data | TanStack Query (never copy to local state) |
| Simple global UI state | Zustand (~1KB, no Provider) |
| Fine-grained derived state | Jotai (~2.4KB) |
| Component-local state | useState/useReducer |
| Form state | React 19 useActionState |

```typescript
// ❌ NEVER copy server data to local state
const { data } = useQuery({ queryKey: ['todos'], queryFn: fetchTodos });
const [todos, setTodos] = useState([]);
useEffect(() => setTodos(data), [data]);

// ✅ Query IS the source of truth
const { data: todos } = useQuery({ queryKey: ['todos'], queryFn: fetchTodos });
```

#### TypeScript Config Recommendations

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true,
    "exactOptionalPropertyTypes": true
  }
}
```

`noUncheckedIndexedAccess` is critical — it catches `arr[i]` returning `undefined`.

#### Immediate Red Flags

| Pattern | Problem | Fix |
|---------|---------|-----|
| `eslint-disable react-hooks/exhaustive-deps` | Hides stale closure bugs | Refactor logic |
| Component defined inside component | Remounts every render | Move outside |
| `useState(undefined)` for inputs | Uncontrolled warning | Use empty string |
| Barrel files (`index.ts`) in app code | Bundle bloat, circular deps | Direct imports |
| Child component using parent's variable | ReferenceError in production | Pass as prop |
| Missing `?.` on nullable values in JSX | Runtime crash | Add optional chaining |
| `alert(message)` in catch block | Jarring UX, not styleable | Inline `setError(message)` |
| Async handler, no `disabled` on trigger | Double-click → duplicate requests | `disabled={isLoading}` + spinner |

#### ESLint a11y & React Hooks Detection (MANDATORY ON EVERY REVIEW)

**Run this scan on every code review — 0 errors required:**
```bash
timeout 60 npx eslint "src/react-app/**/*.{ts,tsx}" 2>&1 | grep "error"
# MUST return 0 errors. "Pre-existing" errors are NOT acceptable — fix them.
```

**Common ESLint error patterns and fixes:**

| ESLint Rule | Pattern | Fix |
|-------------|---------|-----|
| `react-hooks/refs` — "Cannot access refs during render" | `const x = useInView(); ... x.ref ... x.isInView` | Destructure: `const { ref: xRef, isInView: xInView } = useInView()` |
| `react-hooks/refs` — "Cannot update ref during render" | `someRef.current = value` in render body | Move to `useEffect(() => { someRef.current = value; }, [value])` |
| `jsx-a11y/no-noninteractive-element-interactions` | `onLoad` on `<img>` | `eslint-disable-next-line` with justification (onLoad is lifecycle, not interaction) |
| `jsx-a11y/no-noninteractive-tabindex` | `tabIndex={0}` on `<iframe>` | `eslint-disable/enable` block with justification |
| `jsx-a11y/prefer-tag-over-role` | `role="dialog"` on `<div>` | Use `<dialog>` element instead (warning, not error) |

---

### UX Error Handling Patterns

#### alert() Anti-Pattern (Critical — Block Merge)

```typescript
// ❌ NEVER: alert() is jarring and unacceptable in modern React apps
const save = async () => {
  if (!isValid) {
    alert("Please fill in all required fields");  // WRONG
    return;
  }
  try {
    await submit();
  } catch (err) {
    alert(err.message);  // WRONG
  }
};

// ✅ CORRECT: Inline error state, shown adjacent to the action
const [error, setError] = useState<string | null>(null);

const save = async () => {
  if (!isValid) {
    setError("Please fill in all required fields");
    return;
  }
  setError(null);  // clear previous error on new attempt
  try {
    await submit();
    setError(null);  // clear on success
  } catch (err) {
    setError(err instanceof Error ? err.message : "Failed. Please try again.");
  }
};

// Standard error display (place immediately after the form/button that caused it):
{error && (
  <div className="rounded-xl border border-red-400/30 bg-red-500/10 px-4 py-2 text-sm text-red-100 flex items-center gap-2">
    <AlertCircle className="w-4 h-4 flex-shrink-0" />
    {error}
  </div>
)}
```

**Error state rules:**
- Clear on next successful operation: `setError(null)` in `try` success path
- Clear on user starting to edit: `onChange={() => setError(null)}` on inputs
- Position adjacent to triggering action (below button, not top of page)
- Name after the action: `saveError`, `paymentError`, `stepNavError` (not just `error`)

#### Missing Loading State on Async Buttons

```typescript
// ❌ User double-clicks → duplicate API calls, race conditions
<button onClick={async () => await submitForm()}>Submit</button>

// ✅ CORRECT: Disable while in-flight, show spinner
const [isSubmitting, setIsSubmitting] = useState(false);

const handleSubmit = async () => {
  setIsSubmitting(true);
  try {
    await submitForm();
  } finally {
    setIsSubmitting(false);  // always reset, even on error
  }
};

<button
  type="button"
  onClick={() => void handleSubmit()}
  disabled={isSubmitting}
  className="... disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
>
  {isSubmitting && <Loader2 className="w-4 h-4 animate-spin" />}
  {isSubmitting ? "Saving..." : "Submit"}
</button>
```

**Loading state naming**: `isSaving` / `isSubmitting` / `isCompletingStep` — match the action verb.

#### Polling Error Without Retry Button

When a polling/auto-refresh fails, always provide a Retry button:

```typescript
{caseUpdatesError ? (
  <div className="flex flex-col sm:flex-row items-center justify-between gap-3 p-4 rounded-2xl border border-red-400/30 bg-red-500/10 text-red-100 text-sm">
    <span>{caseUpdatesError}</span>
    <button
      type="button"
      onClick={() => void fetchCaseUpdates()}
      className="px-4 py-2 rounded-xl bg-red-500/20 border border-red-400/40 text-sm font-semibold whitespace-nowrap"
    >
      Retry
    </button>
  </div>
) : null}
```

#### Quick Detection

```bash
# Find alert() calls
grep -rn "alert(" --include="*.tsx" src/react-app/

# Find async onClick without disabled prop on same element
grep -rn "onClick.*async\|onClick.*void" --include="*.tsx" src/ | grep -v "disabled="

# Find catch blocks with only console.error (no setError/setState visible)
grep -B2 -A8 "} catch" --include="*.tsx" -r src/react-app/pages/ | grep -B10 "console.error" | grep -v "set[A-Z]"

# Find error states with no clear-on-success call
grep -rn "setError(" --include="*.tsx" src/ | grep -v "null"
```

---

### WCAG 2.2 AA Accessibility Implementation (Biome-Compatible)

When implementing accessibility features, Biome's strict a11y linter catches patterns that are technically valid ARIA but use non-semantic elements. Follow these rules to avoid lint failures:

#### Rule 1: Use Semantic Elements Instead of ARIA Roles

```tsx
// ❌ BIOME ERROR: useSemanticElements — role="complementary" on <div>
<div role="complementary" aria-label="Chat Assistant">...</div>

// ✅ CORRECT: Use <aside> (semantic equivalent of role="complementary")
<aside aria-label="Chat Assistant">...</aside>
```

| ARIA Role | Semantic Element |
|-----------|-----------------|
| `role="complementary"` | `<aside>` |
| `role="navigation"` | `<nav>` |
| `role="banner"` | `<header>` |
| `role="contentinfo"` | `<footer>` |
| `role="main"` | `<main>` |
| `role="article"` | `<article>` |
| `role="region"` | `<section aria-label="...">` |

#### Rule 2: Never Put `aria-hidden="true"` on `<kbd>` Elements

Biome treats `<kbd>` as potentially focusable. Wrap in a `<span>` instead:

```tsx
// ❌ BIOME ERROR: noAriaHiddenOnFocusable
<kbd className="..." aria-hidden="true">ESC</kbd>

// ✅ CORRECT: Wrap in span
<span aria-hidden="true">
  <kbd className="...">ESC</kbd>
</span>
```

#### Rule 3: `aria-label` Requires a Role on Generic `<div>`

Biome enforces `useAriaPropsSupportedByRole` — generic `<div>` doesn't support `aria-label`:

```tsx
// ❌ BIOME ERROR: aria-label not supported by this element
<div className="..." aria-label="Press Escape to close">
  <kbd>ESC</kbd> Close
</div>

// ✅ CORRECT: Add role="note" to support aria-label
<div className="..." role="note" aria-label="Press Escape to close">
  <span aria-hidden="true">
    <kbd>ESC</kbd> Close
  </span>
</div>
```

#### Rule 4: CSS `!important` Needs Per-Declaration Biome Ignore

For `prefers-reduced-motion` (WCAG 2.3.1), `!important` is required to override Tailwind utilities. Biome's `noImportantStyles` rule needs per-declaration suppression — block-level comments don't work:

```css
/* ❌ BIOME ERROR: Block-level ignore doesn't suppress per-declaration errors */
/* biome-ignore lint/complexity/noImportantStyles: a11y */
@media (prefers-reduced-motion: reduce) {
  * { animation-duration: 0.01ms !important; }
}

/* ✅ CORRECT: Suppress each declaration individually */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    /* biome-ignore lint/complexity/noImportantStyles: WCAG a11y override */
    animation-duration: 0.01ms !important;
    /* biome-ignore lint/complexity/noImportantStyles: WCAG a11y override */
    animation-iteration-count: 1 !important;
    /* biome-ignore lint/complexity/noImportantStyles: WCAG a11y override */
    transition-duration: 0.01ms !important;
    /* biome-ignore lint/complexity/noImportantStyles: WCAG a11y override */
    scroll-behavior: auto !important;
  }
}
```

#### Rule 5: When Wrapping Existing Content in a New Element, ALWAYS Verify Closing Tags

When adding `<nav>`, `<aside>`, `<footer>`, or other wrapper elements around existing JSX, always verify the closing tag exists and is in the right place. Search for the matching close:

```bash
# After adding <nav aria-label="...">, verify </nav> exists
grep -n "</nav>" src/react-app/components/AppLayout.tsx
```

#### Rule 6: ARIA Tabs Pattern Checklist

When implementing ARIA tabs, all of these must be present:

```tsx
// Container
<div role="tablist" aria-label="Section name">
  // Each tab
  <button
    role="tab"
    id="tab-{id}"
    aria-selected={isActive}
    aria-controls="tabpanel-{id}"
    tabIndex={isActive ? 0 : -1}  // Roving tabindex
  >

// Each panel
<div
  role="tabpanel"
  id="tabpanel-{id}"
  aria-labelledby="tab-{id}"
>

// Keyboard handler on tablist
onKeyDown: Left/Right arrow to cycle tabs
```

#### Rule 7: Focus Trap Pattern for Modals

Every modal (`role="dialog"`) needs:
1. `aria-modal="true"` + `aria-labelledby` pointing to the title's `id`
2. `tabIndex={-1}` on the container + auto-focus on mount
3. Focus trap: Tab/Shift+Tab cycle within focusable elements
4. Save previous focus in `useRef`, restore on unmount
5. Escape key closes the modal

#### Post-Implementation Lint Check (MANDATORY)

```bash
# After ANY a11y implementation, run Biome on changed files
npx biome check src/react-app/components/ChangedFile.tsx

# Common a11y lint errors to watch for:
# - useSemanticElements: Use <aside>/<nav>/<footer> instead of div+role
# - noAriaHiddenOnFocusable: Wrap <kbd> in <span aria-hidden>
# - useAriaPropsSupportedByRole: Add role="note" for aria-label on <div>
# - noImportantStyles: Per-declaration biome-ignore for reduced-motion CSS
```

---

### Variable Scope Errors (CRITICAL - Causes Production Crashes)

**#1 production crash cause.** Inner/child component references a variable from parent scope without receiving it as a prop.

```typescript
// ❌ CRITICAL BUG: Inner component references outer scope variable
const ParentComponent = ({ precedentInfo }) => {
  const DraftCard = ({ title }) => {
    return (
      <div>
        <h3>{title}</h3>
        {/* BUG: precedentInfo doesn't exist in DraftCard's scope! */}
        {precedentInfo.data && <span>{precedentInfo.data}</span>}
      </div>
    );
  };
  return <DraftCard title="Report" />;
};

// ✅ FIX: Pass required data as props
const DraftCard = ({ title, data }) => {
  return (
    <div>
      <h3>{title}</h3>
      {data && <span>{data}</span>}
    </div>
  );
};

const ParentComponent = ({ precedentInfo }) => {
  return <DraftCard title="Report" data={precedentInfo.data} />;
};
```

**Quick detection:**
```bash
# Find nested component definitions that might have scope issues
grep -n "const.*: React.FC\|const.*= ((" components/*.tsx | grep -v "export"

# Find all inner function components
grep -B5 "return.*<" components/*.tsx | grep "const.*=.*=>"

# Find JSX using variables without optional chaining (potential null access)
grep -rn "{[a-zA-Z]*\.[a-zA-Z]" --include="*.tsx" components/ | grep -v "\?."
```

**Review checklist for scope bugs:**
1. Identify all nested/inner components — any `const X = () =>` inside another component
2. List variables used in inner component — every `{variable}` or `variable.property` in JSX
3. Verify each is a prop, local state, import, or context value
4. If from parent scope — it's a BUG. Pass as prop instead.

---

### General Code Review

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
First Carmack pass on AIVA-Frontend found only 1 XSS issue (JSON.stringify without `<` escaping in render-html.ts). Second comprehensive audit found 7 more: unescaped URL interpolation in HTML attributes (HIGH), incomplete JSON-LD escaping missing 4 of 5 required chars (HIGH), benefit.link href without javascript: URI blocking (MEDIUM), overly permissive structuredData type (LOW), missing backtick in escapeHtml (LOW). Total: 8 vulnerabilities, only 1 caught on first pass (12.5% detection rate). This checklist ensures 100% detection on the first pass.

#### 2. Performance Review
Check for:
- N+1 queries
- Missing database indexes
- Unnecessary re-renders (React)
- Memory leaks
- Blocking operations in async code
- Missing caching opportunities
- Large bundle sizes

```javascript
// BAD: N+1 query
users.forEach(async user => {
  const posts = await getPosts(user.id);
});

// GOOD: Batch query
const userIds = users.map(u => u.id);
const posts = await getPostsForUsers(userIds);
```

#### 3. Code Quality Review
Check for:
- Code duplication (DRY violations)
- Functions doing too much (SRP violations)
- Deep nesting / complex conditionals
- Magic numbers/strings
- Poor naming
- Missing error handling
- Incomplete type coverage
- `alert()` calls (should be inline error state)
- Async event handlers missing loading/disabled state
- `catch` blocks with only `console.error` (silent to user)
- `flex items-center` with text child missing `min-w-0` (mobile text overflow)
- `grid-cols-N` without responsive breakpoint on mobile (375px overflow)
- Hono HTML missing global `overflow-wrap: break-word` + `* { min-width: 0 }` in CSS
- `<table>` in Hono/Worker HTML without `overflow-x: auto` wrapper
- Rigid `min-w-[Npx]` on flex children instead of `shrink-0` (mobile overflow trap)
- Fixed-width columns (`w-28`, `w-20`) without `sm:` responsive breakpoint
- `localStorage.setItem` in component without matching App.tsx restore

```javascript
// BAD: Swallowing errors
try {
  await riskyOperation();
} catch (e) {}

// GOOD: Handle or propagate
try {
  await riskyOperation();
} catch (e) {
  logger.error('Operation failed', { error: e });
  throw new AppError('Operation failed', { cause: e });
}
```

#### 4. Testing Review
Check for:
- Missing test coverage for new code
- Tests that don't test behavior
- Flaky test patterns
- Missing edge cases
- Mocked external dependencies

#### 5. Rust-Specific Review
Check for:
- `#[serde(deny_unknown_fields)]` on config structs (breaks backwards compat when keys are removed)
- Variables mutated only inside `#[cfg(target_os)]` blocks (need `#[allow(unused_mut)]`)
- Functions called only from `#[cfg]` blocks (need matching `#[cfg]` or `#[allow(dead_code)]`)
- Missing i18n translations (new strings need ALL locales, not just English)
- `cargo fmt` violations (chained `||`/`&&` line wrapping)
- Collapsible `if` nesting (`if a { if b { ... } }` → `if a && b { ... }`)
- Missing enum variants in exhaustive match/dispatch/default functions
- `cargo audit` advisories (RUSTSEC-*) — update affected crates or document exceptions
- TODO/FIXME/HACK comments — resolve or convert to NOTE/issue references (code scanners flag these)

#### 6. Config & Schema Backwards Compatibility
Check for:
- Removed config keys that will break existing users (add ignored stubs instead of deleting)
- Changed field types that aren't backwards compatible (e.g., `bool` → `Vec<String>`)
- Missing default values for new required fields
- Strict deserialization (`deny_unknown_fields`, `additionalProperties: false`) on user-facing configs

#### Code Review Output Format

```markdown
## Code Review Summary

### 🔴 Critical (Must Fix)
- **[File:Line]** [Issue description]
  - **Why:** [Explanation]
  - **Fix:** [Suggested fix]

### 🟡 Suggestions (Should Consider)
- **[File:Line]** [Issue description]
  - **Why:** [Explanation]
  - **Fix:** [Suggested fix]

### 🟢 Nits (Optional)
- **[File:Line]** [Minor suggestion]

### ✅ What's Good
- [Positive feedback on good patterns]
```

#### Full Review Checklist

- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] Error handling complete
- [ ] Types/interfaces defined
- [ ] Tests added for new code
- [ ] No obvious performance issues
- [ ] Code is readable and documented
- [ ] Breaking changes documented
- [ ] Config changes are backwards compatible (no removed keys without stubs)
- [ ] Cross-platform: `#[cfg]` blocks don't create unused variable warnings
- [ ] i18n: New user-facing strings have all required translations
- [ ] React: No `alert()` calls — use inline `useState` error display
- [ ] React: Async buttons have `disabled={isLoading}` + loading indicator
- [ ] React: `catch` blocks surface errors to user (not just `console.error`)
- [ ] React: Flex rows with text have `min-w-0` (test at 375px mobile)
- [ ] React: User preferences saved to `localStorage` also restored in App.tsx on mount
- [ ] Child components ONLY use: props, local state, imports, context (no parent scope)
- [ ] All nullable values have optional chaining (`?.`)
- [ ] XSS: `dangerouslySetInnerHTML` guarded by DOMPurify (not regex sanitizer)
- [ ] XSS: Raw `.innerHTML =` guarded by escapeHtml() — search ALL files (`.` not `src/`), entry points are blind spots
- [ ] XSS: `JSON.stringify` in `<script>` escapes ALL 5 chars (`< > & U+2028 U+2029`), not just `<`
- [ ] XSS: Template `${var}` in server HTML attributes wrapped in escapeHtml() (href, content, src)
- [ ] XSS: `href={dynamicUrl}` has isSafeUrl() guard blocking `javascript:` and `data:` URIs
- [ ] XSS: escapeHtml() covers all 6 chars: `& < > " ' \`` (backtick = IE attribute delimiter)
- [ ] XSS: No `eval()`, `new Function()`, or `setTimeout/setInterval` with string args
- [ ] XSS: `postMessage` listeners validate `event.origin`; senders don't use `*` target
- [ ] Pages calling `secureFetch` have frontend auth guard or redirect
- [ ] Admin route errors use `HTTPException(403)` not plain `Error`
- [ ] `grid-cols-N` (N>1) has responsive breakpoints (`sm:`, `md:`)
- [ ] No `<iframe>` with blob URLs for PDFs (breaks on iOS Safari — use Open/Download fallback)
- [ ] Modal heights use `dvh` not `vh` (iOS address bar changes viewport height)
- [ ] Hover-only UI (`opacity-0 group-hover:opacity-100`) has always-visible alternative for touch
- [ ] No `TODO`/`FIXME`/`HACK` comments in changed files (convert to `NOTE:` or resolve)
- [ ] GitHub Actions workflows have top-level `permissions: read-all` (no `write-all`)
- [ ] Workflow write permissions are at job level only, not top level
- [ ] No open RUSTSEC/npm audit advisories with available fixes (run `cargo audit` / `npm audit`)
- [ ] Hono HTML: Global `overflow-wrap: break-word` + `* { min-width: 0 }` in CSS
- [ ] Hono HTML: `<table>` elements have `overflow-x: auto` (via CSS or wrapper div)
- [ ] Hono HTML: Flex layouts use `shrink-0` on icons and `min-w-0` on text wrappers
- [ ] Hono HTML: No rigid `min-w-[Npx]` on flex children (use `shrink-0` instead)
- [ ] Hono HTML: Fixed-width columns (`w-28`, `w-20`) use `sm:` breakpoint or stack on mobile

---

### Responsive Design Rules (MANDATORY)

Every UI component must work on BOTH mobile (375px) and desktop (1440px). The approach differs by audience:

**User-facing pages** (Welcome, Dashboard, FAQ, Privacy, Terms, Benefits Finder):
- Design for mobile AND desktop simultaneously — both must look polished
- Use responsive breakpoints: `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`
- Padding: `p-4 sm:p-6 md:p-8` (progressive)
- Text: readable at 375px without horizontal scroll
- Touch targets: minimum 44x44px on interactive elements
- Test at 375px viewport before marking any UI task complete

**Admin pages** (AdminCases, AdminCaseDetail, AdminReferrals, AdminFaxStatus):
- Desktop is the primary experience — optimize for efficiency
- BUT must be functional on mobile — never hide data, use card views instead
- Tables: add `md:hidden` mobile card view + `hidden md:block` desktop table
- Cards use Apple-like labeled fields: `text-[11px] text-navy-300 uppercase tracking-wider`
- Side-by-side layouts: `flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3`
- Tab bars: `overflow-x-auto` + `whitespace-nowrap` + compact mobile padding

**Quick responsive scan (run after ANY UI change):**
```bash
# Tables hiding data on mobile (need card view alternative)
grep -rn 'hidden md:table-cell\|hidden lg:table-cell' --include="*.tsx" src/
# Grids without responsive breakpoint
grep -rn 'grid-cols-[2-9]' --include="*.tsx" src/ | grep -v 'sm:grid-cols\|md:grid-cols\|grid-cols-1'
# Side-by-side without mobile stacking
grep -rn 'flex.*items-center.*justify-between' --include="*.tsx" src/ | grep -v 'flex-col\|sm:flex-row'
# Wide padding without mobile variant
grep -rn 'px-6\|px-8' --include="*.tsx" src/ | grep -v 'sm:px-\|md:px-'
```

---

### Frontend Design Principles

When creating new UI components or pages, commit to a **bold aesthetic direction** before coding:

- **Purpose**: What problem does this interface solve? Who uses it?
- **Tone**: Pick an extreme: brutally minimal, maximalist, retro-futuristic, organic/natural, luxury/refined, playful, editorial, brutalist, art deco, soft/pastel, industrial. Commit to one, execute precisely.
- **Differentiation**: What makes this UNFORGETTABLE? What will someone remember?

**Typography**: Choose beautiful, unique fonts. Avoid Arial, Inter, Roboto. Pair a distinctive display font with a refined body font.

**Color**: Commit to cohesive aesthetic. CSS variables for consistency. Dominant colors + sharp accents outperform timid balanced palettes.

**Motion**: CSS-only for HTML. Motion library for React. One well-orchestrated page load with staggered reveals beats scattered micro-interactions.

**Spatial Composition**: Unexpected layouts. Asymmetry. Overlap. Grid-breaking elements.

**Backgrounds**: Gradient meshes, noise textures, geometric patterns, layered transparencies, dramatic shadows — create atmosphere.

NEVER use generic AI aesthetics: overused fonts (Inter, Space Grotesk), cliché purple gradients on white, predictable layouts.

Component reference: Browse https://component.gallery/ (60 components, 95 design systems, 2,676 examples).

---

## Feature Implementation

### Ralph Mode: Autonomous Feature Build

Ralph is an autonomous loop that implements features by breaking them into small user stories and completing them one at a time.

**When to use**: When asked to "use ralph", "ralph this", or to implement a feature end-to-end.

#### Step 1: Understand the Feature

Ask clarifying questions if needed:
- What problem does this solve?
- What are the key user actions?
- What's out of scope?
- How do we know it's done?

#### Step 2: Create prd.json

Generate in the project root:

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

#### Step 3: Execute the Loop

For each iteration:
1. Read `prd.json` and `progress.txt` (check Codebase Patterns section first)
2. Check you're on the correct branch from PRD `branchName`. If not, check it out or create from main.
3. Pick the **highest priority** user story where `passes: false`
4. Implement that single user story
5. Run quality checks (typecheck, lint, test)
6. If checks pass, commit: `feat: [Story ID] - [Story Title]`
7. Update `prd.json`: set `passes: true` for completed story
8. Append progress to `progress.txt`
9. Continue to the next story

#### Story Size Rules

Each story MUST be completable in ONE iteration. If you can't describe it in 2-3 sentences, it's too big.

**Right-sized:**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

**Too big (split these):**
- "Build the entire dashboard" → schema, queries, UI components, filters
- "Add authentication" → schema, middleware, login UI, session handling

#### Story Order: Dependencies First

1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views

#### Progress Report Format

APPEND to progress.txt (never replace):

```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

If you discover a reusable pattern, add it to `## Codebase Patterns` at the TOP of progress.txt.

#### Engineering Discipline (Non-Negotiable)

**1. Verification Before Done**
- Never mark a task complete without proving it works
- After deploy: curl the page, verify bundle hash changed, test the endpoint
- Ask yourself: "Would a staff engineer approve this?"
- Diff behavior between main and your changes when relevant
- Run tests, check logs, demonstrate correctness

**2. Self-Improvement Loop**
- After ANY correction from the user: write a lesson to memory
- Write rules for yourself that prevent the same mistake
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Review lessons at session start for the relevant project

**2b. Systematic Debugging (Iron Law from obra/superpowers)**
- **NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST** — if you haven't completed Phase 1, you cannot propose fixes
- Phase 1: Root Cause Investigation (reproduce, trace data flow, gather evidence)
- Phase 2: Pattern Analysis (find working examples, compare, identify differences)
- Phase 3: Hypothesis Testing (single hypothesis, test minimally, verify)
- Phase 4: Implementation (failing test first, single fix, verify)
- **Red flags — STOP and return to Phase 1:** "Quick fix for now", "Just try changing X", "I don't fully understand but this might work", "One more fix attempt" (after 2+ failures)
- 3-failure limit: if 3 fixes fail, force architectural reassessment — the approach is wrong
- **"Data appears stale" shortcut:** If the bug is "admin changed X but user still sees old X", skip generic debugging and go straight to the admin-user sync decision tree:
  1. Does the user hook have `visibilitychange` refresh? → If no, that's the bug
  2. Does the admin endpoint clean up dependent fields? → If no, dirty write
  3. Does the admin UI re-sync after optimistic update? → If no, split-brain
  4. Is the user's navigation state URL-persisted and not recalculating? → If yes, stale pointer
  5. Are data indicators (progress %) and navigation indicators (Step X) using different sources? → If yes, split-brain
- Reference: `/debug` skill for full methodology, patterns, and techniques

**3. Autonomous Bug Fixing**
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

**4. Dual-Portal Sync Checklist (MANDATORY when feature touches admin + user views)**

When building ANY feature where admin writes data that users read, complete this before marking the story done:

- [ ] Every user-facing data hook has `silentFetch` + `visibilitychange` listener (no spinner on tab switch)
- [ ] Admin write endpoint clears dependent fields on status change (e.g., `flag_message = NULL` when completing)
- [ ] Admin optimistic update calls `fetchData()` after successful API response
- [ ] URL-persisted navigation state (`?step=`, `?tab=`) auto-advances when data changes
- [ ] Multi-view displays use data-derived values (`useMemo`), not navigation state
- [ ] Admin write endpoint uses correct audit action (not `VIEW` for a `PUT`)
- [ ] Data-driven indicators (progress bar, counts) and navigation indicators (Step X of Y) use the same source of truth

If ANY checkbox is unchecked, the story is not done.

**5. Demand Elegance (Balanced)**
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

**5. Subagent Strategy**
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- One task per subagent for focused execution
- For complex problems, throw more compute at it via subagents

**6. Context Optimization (from muratcankoylan/agent-skills-for-context-engineering)**
- Use file-search skill (`rg` + `ast-grep`) for targeted code searches — count results first, then narrow
- KV-cache: keep static prompt sections stable (no timestamps, no whitespace changes)
- Observation masking: replace verbose tool outputs with compact references when context is >70% utilized
- Context partitioning: split work across sub-agents when task exceeds 60% of window
- Reference: `~/.claude/skills/context-optimization/` and `~/.claude/skills/file-search/`

#### Quality Requirements

- ALL commits must pass quality checks (typecheck, lint, test)
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns

**Language-specific quality gates:**
- **TypeScript/React**: `npm run build && timeout 120 npx vitest run --changed`
- **Rust**: `cargo fmt --all -- --check && cargo clippy --all-targets && cargo check`
- **Python**: `ruff check . && mypy . && pytest`

#### Browser Testing (Required for Frontend Stories)

For any story that changes UI:
1. **If page is open in Chrome**: use chrome-cdp (`node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs snap <tabPrefix>`) — live session, real data
2. **If testing fresh**: use `agent-browser` (see Browser Automation section)
3. Verify UI changes work as expected
4. Take a screenshot: `node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs shot <tabPrefix>`

**Visual Regression Check (MANDATORY for UI changes):**
After deploying any UI change, verify at both viewports:
```bash
# Desktop verification
agent-browser open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-desktop.png --full
agent-browser close

# Mobile verification (375px iPhone SE)
agent-browser --viewport 375x812 open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-mobile.png --full
agent-browser close
```
Check for: blank areas, horizontal overflow, overlapping elements, broken images. If mobile shows horizontal scroll or blank content — the change is not done.

---

### Creating & Editing Skills

Use this guidance when working with SKILL.md files, authoring new skills, or improving existing ones.

#### Core Principles

**1. Skills Are Prompts** — All prompting best practices apply. Be clear, be direct. Assume Claude is smart — only add context Claude doesn't have.

**2. Standard Markdown Format** — YAML frontmatter + markdown body. No XML tags.

```markdown
---
name: my-skill-name
description: What it does and when to use it
---

# My Skill Name

## Quick Start
Immediate actionable guidance...

## Instructions
Step-by-step procedures...

## Examples
Concrete usage examples...
```

**3. Progressive Disclosure** — Keep SKILL.md under 500 lines. Split detailed content into reference files. Load only what's needed.

```
my-skill/
├── SKILL.md              # Entry point (required)
├── reference.md          # Detailed docs (loaded when needed)
├── examples.md           # Usage examples
└── scripts/              # Utility scripts (executed, not loaded)
```

**4. Effective Descriptions** — Include both what the skill does AND when to use it. Write in third person.

```yaml
# Good:
description: Extracts text and tables from PDF files, fills forms, merges documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.

# Bad:
description: Helps with documents
```

#### Required Frontmatter

| Field | Required | Max Length | Description |
|-------|----------|------------|-------------|
| `name` | Yes | 64 chars | Lowercase letters, numbers, hyphens only |
| `description` | Yes | 1024 chars | What it does AND when to use it |
| `allowed-tools` | No | - | Tools Claude can use without asking |
| `model` | No | - | Specific model to use |

#### Naming Conventions

Use **gerund form** (verb + -ing):
- `processing-pdfs`
- `reviewing-code`
- `generating-commit-messages`

Avoid: `helper`, `utils`, `tools`, `anthropic-*`, `claude-*`

#### Creating a New Skill

**Step 1:** Choose type — Simple (single SKILL.md under 500 lines) or Progressive (SKILL.md + reference files).

**Step 2:** Create SKILL.md:

```markdown
---
name: your-skill-name
description: [What it does]. Use when [trigger conditions].
---

# Your Skill Name

## Quick Start

[Immediate actionable example]

## Instructions

[Core guidance]

## Examples

**Example 1:**
Input: [description]
Output:
```
[result]
```

## Guidelines

- [Constraint 1]
- [Constraint 2]
```

**Step 3:** Add reference files if needed (keep one level deep from SKILL.md).

**Step 4:** Test with real usage. Observe where Claude struggles. Refine. Test with Haiku, Sonnet, and Opus.

#### Audit Checklist

- [ ] Valid YAML frontmatter (name + description)
- [ ] Description includes trigger keywords
- [ ] Uses standard markdown headings (not XML tags)
- [ ] SKILL.md under 500 lines
- [ ] References one level deep
- [ ] Examples are concrete, not abstract
- [ ] Consistent terminology
- [ ] No time-sensitive information
- [ ] Scripts handle errors explicitly

#### Anti-Patterns to Avoid

- **XML tags in body** — Use markdown headings instead
- **Vague descriptions** — Be specific with trigger keywords
- **Deep nesting** — Keep references one level from SKILL.md
- **Too many options** — Provide a default with escape hatch
- **Windows paths** — Always use forward slashes
- **Punting to Claude** — Scripts should handle errors
- **Time-sensitive info** — Use "old patterns" section instead

For extended reference docs, see `~/.claude/skills/create-agent-skills/references/`.

---

## Git & Version Control

### Pre-Flight Checks (MANDATORY before every git command)

**ALWAYS run `git status` before these commands:**

| Command | Why Check First |
|---------|-----------------|
| `git commit` | Verify what's staged, check for untracked files |
| `git push` | Ensure commits exist, check branch tracking |
| `git pull` | Check for uncommitted changes that could conflict |
| `git merge` | Verify clean working tree, correct branch |
| `git rebase` | Check for uncommitted changes, verify branch |
| `git checkout` | Check for uncommitted changes that would be lost |
| `git switch` | Same as checkout |
| `git stash` | Verify there are changes to stash |
| `git reset` | Understand what will be affected |
| `git cherry-pick` | Verify clean working tree |

#### Command-Specific Checks

**Before `git commit`:**
```bash
git status
# Verify: correct files staged (green), no unintended files staged, untracked files
```

**Before `git push`:**
```bash
git status
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "No upstream set"
# Verify: commits exist to push, branch has upstream tracking
```

**Before `git pull`:**
```bash
git status
# Verify: working tree is clean OR changes are stashed/committed
```

**Before `git checkout/switch`:**
```bash
git status
# Verify: no uncommitted changes OR changes are safe to carry over
```

**Before `git merge`:**
```bash
git status
git branch --show-current
# Verify: clean working tree, on correct target branch, source branch exists
```

**Before `git rebase`:**
```bash
git status
git log --oneline -5
# Verify: clean working tree, understand commits, not rebasing public history
```

#### Safe Command Patterns

```bash
# Always check status first
git status && git add <files>
git status && git commit -m "message"
git status && git push
git status && git stash
git status && git checkout <branch>
```

#### Recovery Commands

```bash
git reflog                    # See recent actions
git checkout <commit-hash>    # Recover lost commits
git merge --abort             # Abort failed merge
git rebase --abort            # Abort failed rebase
git restore --staged <file>   # Unstage files
```

#### Common Git Errors & Solutions

| Error | Cause | Prevention |
|-------|-------|------------|
| "nothing to commit" | No staged changes | `git status` first, then `git add` |
| "Everything up-to-date" | No new commits | `git log origin/branch..HEAD` first |
| "Please commit or stash" | Uncommitted changes | `git status`, then stash/commit |
| "diverged" | Local/remote out of sync | Check `git status` + `git log` |
| "no upstream branch" | Branch not tracking remote | `git push -u origin branch` |

---

### Security Scanning

**CRITICAL WARNING:** Removing secrets from git history does NOT make them safe! GitHub is scraped by bots within seconds. Archive services may have snapshots. Forks retain original history.

**ALWAYS rotate leaked credentials immediately.** Cleaning history is NOT enough.

#### Modes

- `/git-safety scan` — Detect sensitive files in current state and history
- `/git-safety clean` — Remove sensitive files using git-filter-repo or BFG
- `/git-safety prevent` — Configure .gitignore and pre-commit hooks
- `/git-safety full` — All three in sequence

#### Sensitive File Patterns

```
.env, .env.*, credentials.json, service-account*.json
*.pem, *.key, id_rsa*, secrets.*, .npmrc, *.secret
```

#### Quick Commands

**Scan for sensitive files in history:**
```bash
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -iE 'env|secret|credential|key'
```

**Remove .env from all history:**
```bash
git filter-repo --path .env --invert-paths --force
git push origin --force --all
```

**Add to .gitignore:**
```bash
echo -e "\n.env\n.env.*\n*.pem\n*.key\ncredentials.json" >> .gitignore
```

#### Emergency Response (If Credentials Leaked)

1. **IMMEDIATELY rotate the credential**
2. Check access logs
3. Run `git filter-repo --path .env --invert-paths --force`
4. Force push cleaned history
5. Notify team to re-clone
6. Update .gitignore
7. Set up pre-commit hooks

---

### Worktree Management

Use worktrees for isolated parallel development — reviewing PRs, working on multiple features simultaneously, or isolating risky changes.

**NEVER call `git worktree add` directly.** Always use the worktree-manager script:

```bash
# ✅ CORRECT - Always use the script
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-name

# ❌ WRONG - Never do this directly
git worktree add .worktrees/feature-name -b feature-name main
```

The script handles critical setup: copies `.env` files, ensures `.worktrees` is in `.gitignore`, creates consistent structure.

#### Commands

```bash
# Create a new worktree (copies .env files automatically)
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# List all worktrees with status
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh list

# Switch to a worktree
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Copy .env files to an existing worktree
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-login

# Clean up completed worktrees
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

#### When to Use

- **Code Review**: If NOT already on the PR branch → offer worktree for isolated review
- **Feature Work**: When working on multiple features simultaneously
- **Risky Changes**: When you want to experiment without affecting main branch

#### Parallel Feature Development

```bash
# Start first feature (copies .env files)
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# Start second feature
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-notifications

# List what you have
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh list

# Switch between them
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Clean up when done
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

#### Directory Structure

```
.worktrees/
├── feature-login/          # Worktree 1
├── feature-notifications/  # Worktree 2
└── ...

.gitignore (updated to include .worktrees)
```

#### Troubleshooting

- **"Worktree already exists"**: Script asks to switch to it instead
- **"Cannot remove: current worktree"**: `cd $(git rev-parse --show-toplevel)` first
- **Missing .env files**: `copy-env feature-name` to copy them manually

---

## Browser Automation

### Choosing the Right Tool

| Situation | Tool |
|-----------|------|
| **Debugging a live page** (logged in, real data, current state) | **chrome-cdp** ← prefer this |
| **Testing a fresh URL** (headless, no session needed) | agent-browser |
| **Performance tracing** (Core Web Vitals, traces) | chrome-devtools-mcp |

**chrome-cdp connects to your actual running Chrome session** — tabs already open, cookies intact, no re-login. Use it first when debugging or inspecting real pages.

### chrome-cdp (Live Chrome Session — Preferred for Debugging)

```bash
CDP="node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs"

$CDP list                           # List all open tabs (shows targetId prefixes)
$CDP snap   <targetPrefix>          # Accessibility tree (best for page structure)
$CDP eval   <targetPrefix> "expr"   # Run JS in page context
$CDP shot   <targetPrefix>          # Screenshot → /tmp/screenshot.png
$CDP html   <targetPrefix> ".sel"   # HTML of element matching selector
$CDP click  <targetPrefix> ".sel"   # Click element by CSS selector
$CDP type   <targetPrefix> "text"   # Type at focused element
$CDP nav    <targetPrefix> <url>    # Navigate and wait for load
$CDP net    <targetPrefix>          # Network resource timing
$CDP stop                           # Stop all daemons
```

**Prerequisite:** Chrome must have remote debugging enabled at `chrome://inspect/#remote-debugging`. Once enabled, the daemon per tab persists 20min — "Allow debugging" modal fires once per tab.

---

### agent-browser (Headless — for Fresh Sessions / E2E Tests)

Uses Vercel's `agent-browser` CLI — headless browser automation designed for AI agents with ref-based element selection.

### Setup Check

```bash
# Check installation
command -v agent-browser >/dev/null 2>&1 && echo "Installed" || echo "NOT INSTALLED"

# Install if needed
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

### Core Workflow

1. **Navigate** to URL
2. **Snapshot** to get interactive elements with refs
3. **Interact** using refs (@e1, @e2, etc.)
4. **Re-snapshot** after navigation or DOM changes

```bash
# Step 1: Open URL
agent-browser open https://example.com

# Step 2: Get interactive elements with refs
agent-browser snapshot -i --json

# Step 3: Interact using refs
agent-browser click @e1
agent-browser fill @e2 "search query"

# Step 4: Re-snapshot after changes
agent-browser snapshot -i
```

### Key Commands

**Navigation:**
```bash
agent-browser open <url>       # Navigate to URL
agent-browser back             # Go back
agent-browser forward          # Go forward
agent-browser reload           # Reload page
agent-browser close            # Close browser
```

**Snapshots (Essential for AI):**
```bash
agent-browser snapshot              # Full accessibility tree
agent-browser snapshot -i           # Interactive elements only (recommended)
agent-browser snapshot -i --json    # JSON output for parsing
agent-browser snapshot -c           # Compact (remove empty elements)
agent-browser snapshot -d 3         # Limit depth
```

**Interactions:**
```bash
agent-browser click @e1                    # Click element
agent-browser dblclick @e1                 # Double-click
agent-browser fill @e1 "text"              # Clear and fill input
agent-browser type @e1 "text"              # Type without clearing
agent-browser press Enter                  # Press key
agent-browser hover @e1                    # Hover element
agent-browser check @e1                    # Check checkbox
agent-browser uncheck @e1                  # Uncheck checkbox
agent-browser select @e1 "option"          # Select dropdown option
agent-browser scroll down 500              # Scroll
agent-browser scrollintoview @e1           # Scroll element into view
```

**Get Information:**
```bash
agent-browser get text @e1          # Get element text
agent-browser get html @e1          # Get element HTML
agent-browser get value @e1         # Get input value
agent-browser get attr href @e1     # Get attribute
agent-browser get title             # Get page title
agent-browser get url               # Get current URL
agent-browser get count "button"    # Count matching elements
```

**Screenshots & PDFs:**
```bash
agent-browser screenshot                      # Viewport screenshot
agent-browser screenshot --full               # Full page
agent-browser screenshot output.png           # Save to file
agent-browser pdf output.pdf                  # Save as PDF
```

**Wait:**
```bash
agent-browser wait @e1              # Wait for element
agent-browser wait 2000             # Wait milliseconds
agent-browser wait "text"           # Wait for text to appear
```

### Semantic Locators (Alternative to Refs)

```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign up" click
agent-browser find label "Email" fill "user@example.com"
agent-browser find placeholder "Search..." fill "query"
```

### Sessions (Parallel Browsers)

```bash
agent-browser --session browser1 open https://site1.com
agent-browser --session browser2 open https://site2.com
agent-browser session list
```

### Debug Mode

```bash
# Run with visible browser window
agent-browser --headed open https://example.com
agent-browser --headed snapshot -i
```

### Example: Login Flow

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Sign in" [ref=e3]
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait 2000
agent-browser snapshot -i  # Verify logged in
```

### JSON Output

```bash
agent-browser snapshot -i --json
# Returns: { "success": true, "data": { "refs": { "e1": {"name": "Submit", "role": "button"} } } }
```

---

## Task Tracking (PRD → prd.json)

The `tasks` workflow converts PRD markdown documents into machine-executable `prd.json` format for the ralph execution loop.

### The Job

1. Read the PRD markdown file
2. Extract tasks (from Tasks section or User Stories)
3. **Explode each task into granular, machine-verifiable sub-tasks**
4. Order by dependencies (schema → backend → UI → tests)
5. Output to `prd.json`

**Autonomous mode:** Do not ask questions. Generate prd.json immediately.

### Critical: Agent-Testable Tasks

Every task must be **autonomously verifiable** by an AI agent without human intervention.

**❌ BAD - Vague/subjective:**
- "Works correctly"
- "Review the configuration"
- "Document the findings"
- "Verify it looks good"

**✅ GOOD - Machine-verifiable:**
- "Run `npm run typecheck` - exits with code 0"
- "Navigate to /signup - page loads without console errors"
- "Click submit button - form submits and redirects to /dashboard"
- "File `src/auth/config.ts` contains `redirectUrl: '/onboarding'`"
- "API response status is 200 and body contains `{ success: true }`"

### Acceptance Criteria Patterns

| Type | Pattern | Example |
|------|---------|---------|
| Command | "Run `[cmd]` - exits with code 0" | "Run `timeout 120 npx vitest run src/path/test.ts` - exits with code 0" |
| File check | "File `[path]` contains `[string]`" | "File `middleware.ts` contains `clerkMiddleware`" |
| Browser nav | "agent-browser: open `[url]` - [expected result]" | "agent-browser: open /login - SignIn component renders" |
| Browser action | "agent-browser: click `[element]` - [expected result]" | "agent-browser: click 'Submit' - redirects to /dashboard" |
| Console check | "agent-browser: console shows no errors" | |
| API check | "GET/POST `[url]` returns `[status]` with `[body]`" | "POST /api/signup returns 200" |
| Screenshot | "agent-browser: screenshot shows `[element]` visible" | |

### prd.json Output Format

```json
{
  "project": "Project Name",
  "branchName": "compound/[feature-name]",
  "description": "[One-line description from PRD]",
  "tasks": [
    {
      "id": "T-001",
      "title": "[Specific action verb] [specific target]",
      "description": "[1-2 sentences: what to do and why]",
      "acceptanceCriteria": [
        "Specific machine-verifiable criterion with expected outcome",
        "Another criterion with pass/fail condition",
        "Run `npm run typecheck` - exits with code 0"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Task Granularity Rules

**Target: 8-15 tasks per PRD.** If you have fewer than 6, split further.

**One concern per task:**

| Concern | Separate Task |
|---------|---------------|
| Navigate to page | T-001 |
| Check for errors | T-002 |
| Test input validation | T-003 |
| Test form submission | T-004 |
| Verify redirect | T-005 |
| Test mobile viewport | T-006 |
| Implement fix | T-007 |
| Verify fix on desktop | T-008 |
| Verify fix on mobile | T-009 |

**Never combine "find the problem" with "fix the problem"** in one task.

### Priority Ordering

1. **Investigation tasks** — priority 1-3 (understand before changing)
2. **Schema/database changes** — priority 4-5
3. **Backend logic changes** — priority 6-7
4. **UI component changes** — priority 8-9
5. **Verification tasks** — priority 10+

Lower priority number = executed first.

### Process

1. Read the PRD file
2. Extract high-level tasks (T-001, US-001, FR-1, etc.)
3. Explode each into granular tasks with boolean pass/fail criteria
4. Order by dependencies
5. Generate prd.json — **do NOT wait for user confirmation, save immediately**

### prd.json Checklist

- [ ] **8-15 tasks** generated (not 3-5)
- [ ] Each task does **ONE thing**
- [ ] Investigation separated from implementation
- [ ] Every criterion is **boolean pass/fail**
- [ ] No vague words: "review", "identify", "document", "verify it works"
- [ ] Commands specify expected exit code
- [ ] Browser actions specify expected result
- [ ] All tasks have `passes: false`
- [ ] Priority order reflects dependencies

### bd — Beads Task Tracking

For ongoing project-level task tracking (not feature execution loops), use `bd`:

```bash
bd create "Investigate auth timeout" -p 1   # Create priority-1 task
bd list                                      # Show all tasks
bd ready                                     # Show unblocked tasks
bd update <id> --status=in_progress          # Claim a task
bd close <id>                                # Complete a task
bd close <id1> <id2> ...                     # Close multiple at once
bd dep add <child> <parent>                  # Add dependency
bd show <id>                                 # Detailed view with deps
bd stats                                     # Project statistics
```

---

## Second Opinion (Codex)

Use Codex CLI for complex debugging, code analysis, and getting a second perspective on difficult problems.

### When to Use Codex

- Debugging subtle bugs (bitstream alignment, off-by-one errors)
- Analyzing complex algorithms against specifications
- Getting a detailed code review with specific bug identification
- Understanding obscure file formats or protocols
- When you've tried multiple approaches and are stuck

### The File-Based Pattern

**Step 1: Create a question file**

```
Write to /tmp/question.txt:
- Clear problem statement
- The specific error or symptom
- The relevant code (full functions, not snippets)
- What you've already tried
- Specific questions you want answered

Example structure:
I have a [component] that fails with [specific error].

Here is the full function:
```c
[paste complete code]
```

Key observations:
1. [What works]
2. [What fails]

Can you identify:
1. [Specific question 1]
2. [Specific question 2]

Please write a detailed analysis to /tmp/reply.txt
```

**Step 2: Invoke Codex**

```bash
cat /tmp/question.txt | codex exec -o /tmp/reply.txt --full-auto
```

Flags: `exec` (non-interactive), `-o /tmp/reply.txt` (output file), `--full-auto` (run autonomously).

**Step 3: Read the reply**

```bash
# Use the Read tool on /tmp/reply.txt
```

Evaluate suggestions critically — Codex may identify real bugs but can occasionally misinterpret specifications.

### Quick Pattern (Short Questions)

```bash
echo "Explain the JPEG progressive AC refinement algorithm" | codex exec --full-auto
```

### Tips

1. **Provide complete code**: Don't truncate functions. Codex needs full context.
2. **Be specific**: "Why does Huffman decoding fail after 1477 blocks in AC refinement?" not "Why does this fail?"
3. **Include the spec**: If debugging against a standard (JPEG, PNG), mention relevant spec sections.
4. **Verify suggestions**: Always verify against authoritative sources.
5. **Iterate**: If first response doesn't solve it, create a new question.txt with additional context.

### Models Available via VibeProxy

```bash
# Default — uses gpt-5.1-codex via VibeProxy on port 8317
cat /tmp/question.txt | codex exec -o /tmp/reply.txt --full-auto

# Higher reasoning effort
cat /tmp/question.txt | codex exec -m gpt-5.1-codex-max -o /tmp/reply.txt --full-auto
```

Available models: `gpt-5.1-codex` (default), `gpt-5.1-codex-low`, `gpt-5.1-codex-medium`, `gpt-5.1-codex-high`, `gpt-5.1-codex-max`, `gpt-5.1-codex-max-high`, `gpt-5.1-codex-max-xhigh`.

Codex config: `~/.codex/config.toml` — base URL: `http://127.0.0.1:8317/v1`

### Common Issues

- **"stdin is not a terminal"**: Use `codex exec` not bare `codex`
- **No output**: Check that `-o` flag has a valid path
- **Timeout**: For very complex questions, `--full-auto` flag avoids interactive prompts that would block

---

## Research & Prompts (last30days)

Research any topic from the last 30 days on Reddit, X, and the web. Surfaces what people are actually discussing, recommending, and debating right now.

**Use cases:**
- **Prompting**: "photorealistic people in Nano Banana Pro" → learn techniques, get copy-paste prompts
- **Recommendations**: "best Claude Code skills", "top AI tools" → list of specific things people mention
- **News**: "what's happening with OpenAI" → current events and updates
- **General**: any topic → understand what the community is saying

### Critical: Parse User Intent

Before doing anything, parse for:
1. **TOPIC**: What they want to learn about
2. **TARGET TOOL** (if specified): Where they'll use the prompts
3. **QUERY TYPE**: PROMPTING / RECOMMENDATIONS / NEWS / GENERAL

Common patterns:
- `[topic] for [tool]` → "web mockups for Nano Banana Pro" → TOOL IS SPECIFIED
- `best [topic]` or `top [topic]` → QUERY_TYPE = RECOMMENDATIONS
- Just `[topic]` → TOOL NOT SPECIFIED, run research first, ask AFTER

**Do NOT ask about target tool before research.**

### Setup

**Browser Mode** (no API keys required — uses agent-browser):
```bash
npm i -g @anthropic/agent-browser  # Install if needed
# Skill auto-detects agent-browser and uses browser mode
```

**API Mode** (optional, for better engagement metrics):
```bash
mkdir -p ~/.config/last30days
cat > ~/.config/last30days/.env << 'ENVEOF'
OPENAI_API_KEY=    # For Reddit research
XAI_API_KEY=       # For X/Twitter research
ENVEOF
```

**Do NOT stop if no keys configured.** Fall back to WebSearch.

### Research Execution

**Step 1: Run the research script**
```bash
python3 ~/.claude/skills/last30days/scripts/last30days.py "$ARGUMENTS" --emit=compact 2>&1
```

The script auto-detects available API keys and signals mode:
- **"Mode: both"** or **"Mode: reddit-only"** or **"Mode: x-only"**: API mode
- **"Mode: browser"**: Browser automation mode
- **"Mode: web-only"**: No API keys or browser, use WebSearch only

**Step 2: Do WebSearch (for all modes)**

Choose search queries by QUERY_TYPE:

- **RECOMMENDATIONS**: `best {TOPIC} recommendations`, `{TOPIC} list examples`, `most popular {TOPIC}`
- **NEWS**: `{TOPIC} news 2026`, `{TOPIC} announcement update`
- **PROMPTING**: `{TOPIC} prompts examples 2026`, `{TOPIC} techniques tips`
- **GENERAL**: `{TOPIC} 2026`, `{TOPIC} discussion`

For ALL types: **USE USER'S EXACT TERMINOLOGY** — don't substitute tech names based on your knowledge. Exclude reddit.com, x.com (covered by script).

**Depth options**: `--quick` (8-12 sources), default (20-30), `--deep` (50-70 Reddit, 40-60 X)

### Judge Agent: Synthesize All Sources

After all searches complete:
1. Weight Reddit/X sources HIGHER (engagement signals: upvotes, likes)
2. Weight WebSearch sources LOWER (no engagement data)
3. Identify patterns that appear across ALL three sources (strongest signals)
4. Note contradictions between sources
5. Extract top 3-5 actionable insights

**CRITICAL: Ground synthesis in ACTUAL research content, not pre-existing knowledge.**

### For RECOMMENDATIONS Query Type

Extract SPECIFIC NAMES, not generic patterns:
- Count how many times each product/tool/skill is mentioned
- Note which sources recommend each
- List by popularity/mention count

```
🏆 Most mentioned:
1. [Specific name] - mentioned {n}x (r/sub, @handle, blog.com)
2. [Specific name] - mentioned {n}x (sources)
3. [Specific name] - mentioned {n}x (sources)
```

### For PROMPTING/NEWS/GENERAL

```
What I learned:
[2-4 sentences synthesizing key insights FROM THE ACTUAL RESEARCH OUTPUT]

KEY PATTERNS I'll use:
1. [Pattern from research]
2. [Pattern from research]
```

### Stats Display

For full/partial mode:
```
✅ All agents reported back!
├─ 🟠 Reddit: {n} threads │ {sum} upvotes │ {sum} comments
├─ 🔵 X: {n} posts │ {sum} likes │ {sum} reposts
├─ 🌐 Web: {n} pages │ {domains}
└─ Top voices: r/{sub1}, r/{sub2} │ @{handle1}, @{handle2}
```

### Wait for User's Vision

After showing stats, stop and wait for user to say what they want to create. Then write ONE perfect prompt.

**CRITICAL: Match the FORMAT the research recommends.** If research says JSON prompts → write JSON. If natural language → use prose.

```
Here's your prompt for {TARGET_TOOL}:

---

[The actual prompt IN THE FORMAT THE RESEARCH RECOMMENDS]

---

This uses [brief 1-line explanation of research insight applied].
```

After delivering, offer: "Want another prompt? Just tell me what you're creating next."

**Context Memory:** After research is complete, you are now an EXPERT on this topic. Do NOT run new WebSearches for follow-up questions — answer from what you learned.

---

## 5-Phase Workflow

1. **Root Cause Investigation** — Gather evidence, no assumptions
2. **Pattern Analysis** — Find similar issues, related code
3. **Hypothesis & Testing** — Form and test theories
4. **Implementation & Verification** — Fix with approval checkpoint
5. **Session Persistence** — Save state for resumability

## Code Search Tools

### ogrep — Semantic Code Search
Use `ogrep` for AST-aware code search by meaning. Always index before first search in a project.
```bash
ogrep index .                          # Build index (first time)
ogrep query "where is auth handled"    # Semantic search
ogrep query "error handling" --mode fulltext  # Keyword search (no embeddings needed)
ogrep query "database connection" -n 10      # More results
ogrep chunk <ref> --context 5          # Get chunk with surrounding context
```

### qmd — Knowledge & Documentation Search
Use `qmd` for searching docs, notes, and markdown knowledge bases (fully local, no API keys).
```bash
qmd collection add ~/project/docs --name docs   # Add docs collection
qmd embed                                        # Build embeddings (auto-downloads models)
qmd query "how does authentication work"         # Hybrid search with reranking
qmd search "env validation"                      # BM25 keyword search
qmd vsearch "startup failure"                    # Vector similarity search
```

### bd — Task Tracking
Use `bd` (beads) for structured task tracking with dependency graphs.
```bash
bd create "Investigate auth timeout" -p 1   # Create priority-1 task
bd list                                      # Show all tasks
bd ready                                     # Show unblocked tasks
bd update <id> --claim                       # Claim a task
bd done <id>                                 # Complete a task
bd dep add <child> <parent>                  # Add dependency
```

## TEST SAFETY RULES (CRITICAL)

Vitest fork workers leak ~5GB memory each when they hang. These rules prevent system resource exhaustion:

1. **ALWAYS use timeout**: `timeout 120 npx vitest run src/specific/test.ts 2>&1`
2. **NEVER run full test suite**: Always target specific test files
3. **Maximum 3 test runs per phase**: Stop and diagnose if tests keep failing/hanging
4. **Clean up after tests**: `pgrep -f vitest | xargs kill 2>/dev/null`
5. **NEVER run `npm test` without timeout** — vitest workers hang and consume all RAM

### Forbidden Test Patterns
```bash
# ❌ WILL LEAK MEMORY — no timeout, full suite
npm test
npx vitest run
npx vitest run --reporter=verbose

# ✅ CORRECT — timeout + specific file
timeout 120 npx vitest run src/worker/utils/sanitizer.test.ts 2>&1
```

## INFRASTRUCTURE SAFETY RULES (CRITICAL — PREVENTS PRODUCTION DESTRUCTION)

An AI agent once ran `terraform destroy` and wiped an entire production environment — database, VPC, ECS, load balancers, all backups. These rules are non-negotiable:

### NEVER Execute Autonomously
- `terraform destroy` — NEVER run this. Tell the user to run it themselves.
- `terraform apply -auto-approve` — NEVER skip human plan review.
- `terraform apply` — ONLY after showing `terraform plan` output to user and getting approval.
- Any cloud CLI command that deletes/terminates resources (aws rds delete-*, aws ec2 terminate-*, gcloud * delete)
- Any command that modifies or replaces .tfstate files
- `DROP TABLE`, `DROP DATABASE`, or equivalent destructive SQL

### ALWAYS Do First
- Run `terraform plan` and show output before any `apply`
- Run `terraform state list` to verify state matches reality
- Use read-only cloud CLI commands (describe, list, get) before any write operations
- Verify you're operating on the correct resources by checking names/IDs

### State File Rules
- NEVER copy, move, rename, extract, or overwrite .tfstate files
- NEVER unpack archives that might contain .tfstate files
- If state seems wrong (showing 0 resources when infra exists), STOP and alert the user
- Treat state file corruption as a critical incident — do NOT attempt to fix by running commands

### Blast Radius Check
Before ANY infrastructure operation, answer:
1. What resources will be affected? (list them)
2. Is this reversible? (if no, require human execution)
3. Could this affect resources outside my intended scope? (if unsure, STOP)

## Cloudflare API Access (MCP)

The `cloudflare-api` MCP server provides full access to ~2,500 Cloudflare API endpoints via two tools:
- **`search`** — Write JS to query the OpenAPI spec and find endpoints
- **`execute`** — Write JS to call any Cloudflare API endpoint

Use these when investigating Cloudflare-hosted services:

```
# Investigation examples:
- Query Worker runtime logs for error patterns
- Check DNS resolution and routing issues
- Inspect KV/D1/R2 data during debugging
- Verify Worker bindings and environment variables
- Check firewall rules blocking requests
- Inspect zone analytics for traffic anomalies
- Review cache behavior and purge cache
- Check SSL certificate status
- Investigate edge-level redirect rules
```

### When to Use in Debugging
- **500 errors on Workers**: Check runtime logs, bindings, environment vars via MCP
- **Auth failures**: Verify redirect rules, DNS records, cookie domains via MCP
- **Performance issues**: Check cache hit rates, zone analytics via MCP
- **Data issues**: Query D1/KV directly to verify state via MCP
- **Deployment drift**: Compare Worker routes/bindings to expected config via MCP

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

---

## CI Debugging via GitHub API

When local searches produce false positives or can't identify CI failures, go directly to the CI logs:

```bash
# Get the actual failure from CI logs (not guessing from local grep)
gh run view <RUN_ID> --log-failed

# List all check runs for a commit/PR
gh api repos/<owner>/<repo>/check-runs --jq '.check_runs[] | {name, status, conclusion}'

# Monitor PR checks live
gh pr checks <PR_NUMBER> --watch

# Get specific job log
gh run view <RUN_ID> --job <JOB_ID> --log-failed
```

### When to Use This Instead of Local Debugging
- **i18n checkers**: CI may grep differently than you (e.g., `format!("...")` matches `t!("...")` pattern)
- **Cross-platform failures**: Linux/Windows CI catches things macOS doesn't
- **Custom CI scripts**: Project-specific validators with non-obvious rules
- **Dependency resolution**: CI may pin different versions than your local environment

### Real-World Case (topgrade 2026-03-07)
CI's i18n checker flagged strings as English-only. Local grep for `t!("...")` produced false positives because `format!("...")` ends in `t!`. Had to read actual CI logs via `gh run view --log-failed` to find the real missing translations.

## Fork Mass-Integration Strategy

When forking a stale OSS project to integrate pending community work:

### Workflow
1. **Audit**: `gh pr list --state open`, `gh issue list --state open` — categorize into implementable vs can't-fix
2. **Merge PRs**: Start with bot/dependency PRs (clean), then simple features, then complex refactors
3. **Implement Issues**: Batch by theme (new features, bug fixes, platform improvements)
4. **CI Loop**: Push → check CI → fix failures → push again. Budget 3-5 CI rounds.
5. **Local Test**: Install and run the tool with YOUR existing config. Backwards compat bugs hide here.

### Key Patterns
- **Hot files**: Some files (config, schema, routes) are touched by every PR. Merge these last.
- **Revert fast**: If a PR breaks the build (e.g., dependency major version bump), `git revert HEAD -m 1` immediately
- **Config compat**: Users have deprecated keys in config files. `deny_unknown_fields` + removed keys = crash at startup. Add ignored stubs instead.
- **i18n completeness**: Strict checkers require ALL locales for every new string — not just English

## Reproduction Harnesses

- Builds repro scripts in `tools/repro/`
- Closed-loop execution: create → run → verify → clean up
- Minimal reproduction cases isolating the exact failure

## Debugger & Instrumentation

- Attaches debuggers autonomously (lldb)
- Instruments code without asking for logs
- Takes complete ownership of investigation
- Creates minimal, surgical fixes with regression tests

## React-Specific Checks

### "X is not defined" — Scope Audit

**#1 production crash cause.** Inner/child component references a variable from parent scope without receiving it as a prop.

#### Step 1: Check Scope
For each use of the undefined variable, verify it's in scope:
- Is it a prop? Check the component's props interface
- Is it local state? Check useState declarations
- Is it imported? Check import statements
- Is it from context? Check useContext usage

#### Step 2: Verify Child Components
- All child/inner components ONLY use: props, local state, imports, context
- Child should NEVER reference parent's local variables directly
- No inline component definitions that close over parent state

#### Step 3: Detection Commands
```bash
# Find the undefined variable in the file
grep -n "<variable_name>" <file>

# Find all nested components (potential scope issues)
grep -n "const.*= (" <file> | grep -v "export"

# Find nullable access without optional chaining
grep -rn "{[a-z][a-zA-Z]*\.[a-z]" --include="*.tsx" | grep -v "\?."
```

#### Step 4: Common Patterns
- Inner component referencing outer component's variables
- Missing prop drilling (parent has data, child needs it)
- useCallback/useMemo referencing variables not in scope

```tsx
// ❌ BUG: Inner component references parent's variable
const Parent = ({ data }) => {
  const Inner = () => <div>{data.field}</div>;  // data not in scope!
  return <Inner />;
};

// ✅ FIX: Pass as prop
const Inner = ({ data }) => <div>{data.field}</div>;
const Parent = ({ data }) => <Inner data={data} />;
```

#### Step 5: Fix Verification
1. `npm run build` — Ensure no TypeScript errors
2. `timeout 120 npx vitest run src/path/to/relevant.test.ts` — Run ONLY related tests with timeout
3. Re-run detection commands to verify no remaining issues

### Silent React Startup Failure

**#2 production crash cause.** React silently fails to mount — only SSR/SEO fallback HTML visible, zero console errors.

#### Step 1: Confirm Symptoms
- Page loads but `#root` div is empty or contains only SSR fallback HTML
- No errors in console, no network failures
- React never started at all

#### Step 2: Test Module Import
```javascript
// In Chrome DevTools console:
import('/src/react-app/App.tsx').catch(e => console.error('Module failed:', e))
// If this logs an error, the module is failing during evaluation
```

#### Step 3: Check Env Validation Timing
```bash
# Find module-level code that runs before React mounts
grep -Bn5 "export default function\|export function App" src/react-app/App.tsx | grep "validate\|throw\|assert"

# Check if validateClientEnv() has fallbacks
grep -A2 "validateClientEnv" src/react-app/App.tsx
```

#### Step 4: Verify Env Variables
```bash
# List all VITE_ vars used in codebase
grep -roh "VITE_[A-Z_]*" --include="*.ts" --include="*.tsx" src/ | sort -u

# Check .env files for these vars
cat .env .env.local .env.production 2>/dev/null | grep "VITE_"
```

#### Step 5: Apply Fix
```typescript
// Pass the fallback INTO validation so it knows about it
const FALLBACK = "pk_test_...";
validateClientEnv({ VITE_CLERK_PUBLISHABLE_KEY: FALLBACK });
const KEY = import.meta.env.VITE_CLERK_PUBLISHABLE_KEY || FALLBACK;
```

#### Step 6: Verify
```bash
npm run build  # No TypeScript errors
timeout 120 npx vitest run src/path/to/relevant.test.ts  # Targeted test with timeout
# After deploy: document.querySelector('#root').children.length > 0
```

### Catch-All Error Handling Masking Root Cause

**#3 production debugging trap.** A single `try-catch` wrapping multiple operations returns a generic error message, making it impossible to identify which operation actually failed.

#### Symptoms
- Error message says one thing (e.g., "Token verification failed") but the actual failure is something else (e.g., Clerk API down, DB timeout)
- Logs show the generic error but not the specific operation that threw
- Can't reproduce locally because the failing service works fine in dev

#### Step 1: Find Catch-All Blocks
```bash
# Find catch blocks that return generic error messages
grep -B2 -A5 "catch.*error" --include="*.ts" -r src/ | grep -A5 "return.*json.*error"
```

#### Step 2: Identify Distinct Failure Modes
For each catch-all block, list what can throw:
1. **Auth/JWT verification** → 401 (bad token, expired, wrong key)
2. **External API calls** (Clerk, Stripe, etc.) → 503 (service unavailable)
3. **Database operations** → 503 (DB down) or 500 (query error)
4. **Business logic** → 400/422 (validation failure)

#### Step 3: Split into Granular Try-Catch
```typescript
// ❌ CATCH-ALL: All errors look the same
try {
  const token = await verifyToken(jwt);
  const user = await clerkApi.getUser(token.sub);
  const data = await db.query("SELECT ...");
} catch (error) {
  return json({ error: "Authentication failed" }, 401);  // MISLEADING!
}

// ✅ GRANULAR: Each failure mode has distinct error + status code
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

#### Step 4: Add Diagnostic Logging
Each catch block should log:
- **Which operation** failed (JWT verify, API call, DB query)
- **The actual error message** (`error.message`, not just "Unknown error")
- **Context** (userId, endpoint, request ID if available)

### URL-Persisted State Desync (Stale Step/Tab/View Bug)

**#4 production UX bug.** State derived from URL params (`?step=`, `?tab=`, `?page=`) never recalculates when underlying data changes, causing the UI to show stale information while data-driven indicators (progress bars, counts) update correctly.

#### Symptoms
- Progress bar says 71% but step indicator says "Step 1 of 7"
- Admin marks items complete but end user sees old state
- Data refreshes (counts update) but navigation/selection doesn't advance
- Page reload doesn't fix it (URL param persists)

#### Step 1: Find URL-Persisted State
```bash
# Find state derived from URL search params
grep -n "searchParams.get\|useSearchParams\|URLSearchParams" --include="*.tsx" --include="*.ts" -r src/

# Find useEffect guards that skip recalculation
grep -B2 -A5 "=== null" --include="*.tsx" -r src/ | grep -A5 "activeStep\|activeIndex\|currentStep"
```

#### Step 2: Verify Recalculation Logic
For each URL-derived state variable, check:
1. Is there a useEffect that only initializes when state is `null`?
2. Does the useEffect re-run when data changes but state is already set?
3. If the state points to a "completed" or stale item, does it auto-advance?

```tsx
// ❌ BUG: Only initializes once, never recalculates
useEffect(() => {
  if (activeIndex === null) {
    setActiveIndex(findBestIndex());  // Only runs when null
  }
}, [data, activeIndex]);

// ✅ FIX: Also recalculates when active item becomes stale
useEffect(() => {
  if (activeIndex === null) {
    setActiveIndex(findBestIndex());
    return;
  }
  // Auto-advance if current item was completed externally
  if (data[activeIndex]?.status === "completed") {
    const hasIncomplete = data.some((d) => d.status !== "completed");
    if (hasIncomplete) setActiveIndex(findBestIndex());
  }
}, [data, activeIndex]);
```

#### Step 3: Check Multi-View Consistency
If the same state is displayed on multiple tabs/views:
```bash
# Find all places the state variable is rendered
grep -n "activeStepIndex\|activeIndex" --include="*.tsx" -r src/ | grep -v "import\|const\|set"
```
- If one view nullifies the state (e.g., `activeTab !== "claim" → null`), other views using the same variable will show fallback values
- Fix: compute a separate display value for views where the URL state isn't active

#### Step 4: Verify Admin→User Data Flow
When admin updates data that affects user display:
1. **Backend**: Does the update endpoint clear related fields? (e.g., clear `flag_message` when marking step "completed")
2. **Admin UI**: Does optimistic update re-sync with server after success? (call `fetchData()` after PUT)
3. **User UI**: Is there a background refresh mechanism? (visibility-change listener, polling)
4. **Audit**: Is the audit action correct for write operations? (not a "view" action for a "write")

#### Step 5: Detection Commands
```bash
# Find useEffect guards that may block recalculation
grep -B5 "=== null" --include="*.tsx" -r src/ | grep "useEffect\|activeStep\|activeIndex\|currentItem"

# Find optimistic updates without refetch
grep -A10 "Optimistic update" --include="*.tsx" -r src/ | grep -v "fetch\|refetch\|reload"

# Find admin write endpoints using wrong audit action
grep -B5 "ADMIN_VIEW" --include="*.ts" -r src/worker/ | grep -B5 "PUT\|POST\|DELETE\|update\|create\|delete"
```

### Admin-User Portal Sync Audit (MANDATORY for dual-portal apps)

**#5 production UX bug class.** When an app has both admin and end-user portals sharing the same database, data written by admin must be correctly reflected in the user's view. This class of bug is insidious because each portal works fine in isolation — the bug only appears when admin acts while the user is already viewing.

#### The Three Sync Failure Modes

| Mode | What Breaks | Example | Root Cause |
|------|------------|---------|------------|
| **Stale Navigation** | Data updates but UI pointer doesn't | Progress=71% but shows Step 1 | URL-persisted state not recalculated (see above) |
| **Stale Data** | User's data never refreshes | Admin marks complete, user still sees "pending" | No background refresh, no polling, no visibility handler |
| **Dirty Write** | Admin writes incomplete data | Admin marks step complete but flag_message persists | Backend endpoint doesn't clean up related fields |

#### Step 1: Map All Admin Write → User Read Paths

For every admin endpoint that modifies data, trace the full path:

```bash
# Find all admin PUT/POST/DELETE endpoints
grep -n "app\.\(put\|post\|delete\).*admin" --include="*.ts" -r src/worker/

# For each endpoint, identify:
# 1. What table/fields does it write?
# 2. What user-facing endpoint reads those fields?
# 3. What user-facing component displays them?
# 4. How does the component refresh its data?
```

**Document as a table:**
```
Admin Endpoint              → DB Write           → User Endpoint    → User Component     → Refresh Mechanism
PUT /admin/steps/:id        → steps.status       → GET /api/steps   → Dashboard.tsx       → mount-only (BUG!)
PUT /admin/clients/:id      → intake.*           → GET /api/intake  → IntakeForm.tsx      → mount-only (BUG!)
POST /admin/messages        → admin_messages     → GET /api/messages→ Dashboard.tsx       → polling 30s (OK)
```

Any row where "Refresh Mechanism" is "mount-only" is a bug. User will never see admin changes without manual reload.

#### Step 2: Verify Background Refresh Exists

Every user-facing hook that reads admin-writable data MUST have at least one of:

```bash
# Check 1: visibilitychange listener (minimum viable sync)
grep -A20 "useEffect" --include="*.ts" -r src/react-app/hooks/ | grep "visibilitychange"

# Check 2: Polling interval
grep -n "setInterval\|useInterval" --include="*.ts" -r src/react-app/hooks/

# Check 3: WebSocket/SSE subscription
grep -n "WebSocket\|EventSource\|onmessage" --include="*.ts" -r src/react-app/

# Check 4: Focus refetch (React Query / SWR pattern)
grep -n "refetchOnWindowFocus\|revalidateOnFocus" --include="*.ts" -r src/react-app/
```

**Rule**: If NONE of the above exist for a hook, the user will NEVER see admin changes without manual F5. Add at minimum a `visibilitychange` silent refetch.

**Critical**: Silent refetch must NOT set `isLoading=true`. If it does, returning to the tab shows a full-screen spinner. Use a separate `silentFetch` function that only updates data state, not loading state.

#### Step 3: Verify Admin Write Endpoints Clean Up Related Fields

When admin advances a status (e.g., step → completed), all fields that only make sense for the previous status must be cleared:

```bash
# Find admin UPDATE statements
grep -A5 "UPDATE.*SET.*status" --include="*.ts" -r src/worker/ | grep -v "flag_message\|notes\|reason"
# If the UPDATE only sets status but not related fields → BUG
```

**Common dirty write patterns:**
- Step marked "completed" but `flag_message` ("Missing documents") still shows on user dashboard
- Claim status changed to "approved" but `rejection_reason` still populated
- User deactivated but `session_token` not invalidated

**Rule**: Every admin status-change endpoint must include a CASE clause or explicit NULL set for dependent fields:
```sql
-- ✅ CORRECT: Clear flag when completing
UPDATE steps SET status = ?, 
  flag_message = CASE WHEN ? = 'completed' THEN NULL ELSE flag_message END
WHERE ...
```

#### Step 4: Verify Optimistic Updates Re-Sync

Admin UIs often use optimistic updates for responsiveness. But optimistic state can diverge from server truth if it never re-syncs:

```bash
# Find optimistic updates
grep -B5 -A15 "Optimistic update\|optimistic" --include="*.tsx" -r src/react-app/pages/Admin

# For each, verify: after the API call succeeds, is fetchData() called?
# Pattern to look for:
#   try { await securePut(...); await fetchClientData(); }  ← CORRECT
#   try { await securePut(...); haptic.success(); }         ← BUG: no re-sync
```

**Rule**: Every optimistic update MUST call `fetchData()` after successful API response to pull back server-computed side effects (intake.is_complete, cleared flags, computed timestamps).

#### Step 5: Verify Audit Actions Match Operation Type

Admin write operations must log the correct audit action — not a "view" action:

```bash
# Find write endpoints using view audit actions
grep -B10 "AuditActions\.\(ADMIN_VIEW\|VIEW\)" --include="*.ts" -r src/worker/ | grep -B10 "PUT\|POST\|DELETE"
```

**Rule**: `PUT`/`POST`/`DELETE` handlers must use write-specific audit actions (`ADMIN_UPDATE_*`, `ADMIN_CREATE_*`, `ADMIN_DELETE_*`). Using `ADMIN_VIEW_CLIENT` for a write operation makes audit logs useless for investigating who changed what.

#### Step 6: Verify Multi-View Consistency

If the same data appears on multiple tabs/views, each view must show the correct current state:

```bash
# Find state variables used across multiple tab views
grep -n "activeStepIndex\|activeTab\|currentStep" --include="*.tsx" -r src/react-app/pages/ | \
  grep -v "const\|set\|import" | awk -F: '{print $2}' | sort -u
```

**Common trap**: State derived from URL params (e.g., `activeStepIndex`) is nullified when user is on a different tab. If the overview tab renders "Step X of Y" using the same variable, it shows the fallback value (usually Step 1) instead of the actual next step.

**Rule**: Data-driven display values should be computed from data (useMemo), not from navigation state. Navigation state tells you *where the user is*; data tells you *what to show*.

#### Pre-Ship Checklist for Admin-User Sync

Run this checklist before shipping ANY change that touches admin endpoints or user data display:

- [ ] Every admin write endpoint clears dependent fields on status change
- [ ] Every admin write endpoint uses the correct audit action (not VIEW for writes)
- [ ] Every admin optimistic update calls fetchData after success
- [ ] Every user-facing data hook has visibility-change silent refetch
- [ ] Silent refetch does NOT trigger loading spinner (separate silentFetch function)
- [ ] URL-persisted navigation state auto-advances when data changes
- [ ] Multi-tab/multi-view displays use data-derived values, not navigation state
- [ ] No useEffect that only initializes once but depends on externally-changeable data

## Deploy Session Invalidation (SPA + Cloudflare Workers)

**#5 production crash cause.** Users are logged out after every deployment because old JS chunks return HTML instead of 404.

### Root Cause
1. `wrangler deploy` uploads new assets with new content hashes
2. User's cached `index.html` references old chunk filenames
3. `not_found_handling: "single-page-application"` returns HTML (200) for missing `.js` files
4. React's `import()` gets HTML instead of JS → syntax error → crash → session lost

### Required Defenses (ALL THREE must exist)

**1. Client: `vite:preloadError` handler in main.tsx**
```typescript
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault();
  if (!sessionStorage.getItem('chunk-reload')) {
    sessionStorage.setItem('chunk-reload', '1');
    window.location.reload();
  }
});
// After React mounts successfully:
sessionStorage.removeItem('chunk-reload');
```

**2. Client: ErrorBoundary chunk detection**
```typescript
isChunkLoadError(error) {
  return /dynamically imported module|Loading chunk|ChunkLoadError/.test(
    error?.message || error?.name || ''
  );
}
// In componentDidCatch: auto-reload once using same sessionStorage flag
```

**3. Server: `CDN-Cache-Control: no-store` on HTML responses**
```typescript
// In securityHeaders middleware
c.header("CDN-Cache-Control", "no-store");
```

### Quick Detection
```bash
# All three must exist:
grep "vite:preloadError" src/react-app/main.tsx
grep -E "ChunkLoadError|dynamically imported module" src/react-app/components/ErrorBoundary.tsx
grep "CDN-Cache-Control" src/worker/middleware/securityHeaders.ts
```

### Incident (2026-03-15)
Every `wrangler deploy` logged out all active users. CF edge cached stale HTML (`cf-cache-status: HIT` despite `Cache-Control: no-store`), old HTML referenced old chunks, SPA fallback served HTML for missing `.js` → React crash → Clerk session lost.

---

## CF Pages Stale Deployment / version.json Debugging

**#6 production debugging trap.** Production shows old version, stale timestamp, or `"version": "dev"` after pushing code.

### Root Causes (check in order)

| # | Symptom | Root Cause | Fix |
|---|---------|-----------|-----|
| 1 | `version.json` shows `"dev"` | File committed to git with local build values | Add `public/version.json` to `.gitignore`, `git rm --cached` |
| 2 | `version.json` shows old SHA | Service worker caches it | Add to SW `NETWORK_ONLY_PATTERNS` |
| 3 | CDN serves stale `version.json` | No cache-control header | Add `Cache-Control: no-store` in `_headers` file |
| 4 | Deploy command fails auth | `.env.local` has `CLOUDFLARE_API_TOKEN` that overrides wrangler OAuth | Remove token from `.env.local` |
| 5 | Push doesn't trigger deploy | No CF Pages GitHub integration | Use `npm run deploy` or set up in CF Dashboard |
| 6 | `generate-version.js` outputs `"dev"` | No CF env vars AND no git fallback | Add `execSync('git rev-parse HEAD')` fallback |

### Quick Diagnosis
```bash
# What does production serve?
curl -s "https://YOUR_SITE.pages.dev/version.json"

# What does local build produce?
npm run build && cat public/version.json

# Is version.json git-tracked? (should NOT be)
git ls-files public/version.json

# Does wrangler auth work?
npx wrangler whoami 2>&1 | head -5

# Is .env.local overriding wrangler OAuth?
grep "CLOUDFLARE_API_TOKEN" .env.local 2>/dev/null

# Does the service worker cache version.json?
grep "version.json\|NETWORK_ONLY" public/sw.js
```

### The `.env.local` Token Override Bug (Critical)

Wrangler loads `.env.local` via dotenv internally. If `.env.local` has `CLOUDFLARE_API_TOKEN` with limited permissions, it **overrides** the wrangler OAuth token from `~/.wrangler/config/default.toml` — even if the OAuth token has full permissions including `pages:write`.

**Detection**: `wrangler pages deploy` fails with "Authentication error [code: 10000]" but `~/.wrangler/config/default.toml` shows `pages:write` in scopes.

**Fix**: Remove or comment out `CLOUDFLARE_API_TOKEN` from `.env.local`. The wrangler OAuth token is the correct auth method.

**Important**: `env -u CLOUDFLARE_API_TOKEN` does NOT work because wrangler loads the token from the file, not from the shell environment.

### version.json Architecture (Correct Setup)

```
public/version.json     → in .gitignore (never committed)
scripts/generate-version.js → runs during prebuild
  → reads: CF_PAGES_COMMIT_SHA || git rev-parse HEAD
  → writes: public/version.json with real commit SHA
public/_headers         → Cache-Control: no-store for /version.json
public/sw.js            → version.json in NETWORK_ONLY_PATTERNS
vite.config.ts          → __BUILD_VERSION__ uses same git fallback
```

### Incident (2026-03-17)
Version display showed `"dev"` / `"development"` / 2 hours stale despite 6 pushes to main. Five interacting causes: (1) version.json committed to git with local values, (2) vite.config.ts fell back to `'dev'` without CF env vars, (3) no cache-control header for version.json, (4) service worker cached version.json, (5) no CF Pages GitHub integration (only Vercel webhook existed). Fixed by removing version.json from git, adding git fallback to generate-version.js and vite.config.ts, adding cache bypass headers, and removing broken API token from .env.local.

---

## Cross-Platform CI Safety (Rust Projects)

When submitting PRs to Rust projects with multi-platform CI (Linux, Windows, macOS, FreeBSD, NetBSD, Android):

### Pre-Submit Checklist
1. **`cargo fmt --all -- --check`** — CI is strict about formatting, especially line wrapping in chained `||`/`&&` expressions
2. **`cargo clippy --all-targets`** — Check for unused variables/mutability that only exist due to `#[cfg(target_os)]` blocks
3. **`#[allow(unused_mut)]`** — Add above any `let mut` that's only reassigned inside a platform-specific cfg block
4. **`#[allow(dead_code)]`** — Add above functions only called from cfg blocks

### Common Trap: Conditional Compilation
```rust
// ❌ Passes clippy on macOS, FAILS on Linux/Windows/FreeBSD/NetBSD/Android
let mut value = get_default()?;
#[cfg(target_os = "macos")]
if let Some(override_val) = macos_specific() { value = override_val; }

// ✅ Works on ALL platforms
#[allow(unused_mut)]
let mut value = get_default()?;
#[cfg(target_os = "macos")]
if let Some(override_val) = macos_specific() { value = override_val; }
```

## Launchd/Cron PATH Debugging

When debugging tools that work interactively but fail in automated environments:

### Root Cause
launchd and cron don't load shell profiles (`~/.zshrc`, `~/.bash_profile`). They inherit a minimal PATH: `/usr/bin:/bin:/usr/sbin:/sbin`.

### Investigation Steps
1. **Check what PATH the automated job sees**: Add `echo "PATH=$PATH" >> /tmp/debug-path.txt` to the script
2. **Find all tools the script needs**: `grep -oP '\b(brew|npm|claude|gem|ruby|cargo|rustup)\b' script.sh`
3. **Check if each tool is at a standard Homebrew path**: `which -a <tool>` — if it's only at `/opt/homebrew/bin/` or a keg-only path, it won't be found
4. **Test with stripped PATH**: `env -i PATH="/usr/bin:/bin" bash -c 'which <tool>'`

### Fix Template
```bash
#!/bin/bash
# Always set full PATH in launchd/cron scripts
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

## Code Scanning Auto-Fix (Pre-Push)

**MANDATORY before pushing to any repo with GitHub code scanning enabled.** Check for and auto-fix the three categories of code scanning alerts that OpenSSF Scorecard, DevSkim, and similar scanners flag.

### Detection
```bash
# Check if repo has code scanning enabled
gh api repos/{owner}/{repo}/code-scanning/alerts --jq 'length' 2>/dev/null
```

### Category 1: GitHub Actions Token Permissions (OpenSSF Scorecard)

**Problem**: Workflows with overly broad `permissions` (e.g., `write-all` or no top-level `permissions` defined).

**Auto-fix**:
```bash
# Find all workflow files
ls .github/workflows/*.yml

# For each workflow, ensure:
# 1. Top-level permissions block exists with read-only defaults
# 2. Job-level permissions are narrowed to minimum required

# Pattern: Add/change top-level permissions
# permissions:
#   contents: read
#
# Then only add write permissions at JOB level where needed:
#   jobs:
#     release:
#       permissions:
#         contents: write    # Only for release asset uploads
```

**Rules**:
- Top-level `permissions` MUST default to read-only (`contents: read` or `read-all`)
- Job-level `permissions` ONLY where write access is genuinely needed
- Security scan jobs need `security-events: write` at job level, NOT top level
- Release jobs need `contents: write` at job level for asset uploads
- Never use `write-all` at top level

### Category 2: RUSTSEC / Dependency Vulnerabilities

**Auto-fix**:
```bash
# For Rust projects
cargo audit 2>&1

# For Node projects
npm audit --omit=dev 2>&1

# For Python projects
pip-audit 2>&1
```

**Rules**:
- If the advisory is a real vulnerability with a fix available: update the crate/package
- If the advisory is informational (unmaintained crate): evaluate migration cost
  - If migration is trivial (<20 code changes): migrate to maintained alternative
  - If migration is expensive (100+ code changes): add to ignore config with rationale and 1-year expiry
- ALWAYS prefer updating to a maintained alternative over ignoring

### Category 3: TODO/FIXME/HACK Comments (DevSkim)

Code scanners flag `TODO`, `FIXME`, `HACK`, and similar comments as "suspicious" — incomplete functionality indicators.

**Auto-fix**:
```bash
# Find all flagged comments
grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.rs" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" src/

# For each match:
# 1. If the TODO describes work already done → DELETE the comment
# 2. If the TODO describes a trivial improvement → IMPLEMENT it
# 3. If the TODO describes future work → Convert to "NOTE:" with context
# 4. If the TODO is a known limitation → Convert to "NOTE: Known limitation:"
```

**Conversion patterns**:
```rust
// ❌ Flagged by scanner
// TODO: handle error case
// FIXME: this is a workaround
// HACK: temporary fix

// ✅ Not flagged
// NOTE: Error case handled by caller via Result propagation
// NOTE: Workaround for upstream issue #123 — revisit when fixed
// NOTE: Simplified approach — full implementation tracked in issue #456
```

### Pre-Push Scan (Run After All Changes)
```bash
# Scan for remaining TODO/FIXME/HACK in changed files
git diff --name-only HEAD~1 | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null

# Verify workflow permissions are restrictive
grep -l "permissions:" .github/workflows/*.yml | while read f; do
  echo "=== $f ==="
  grep -A2 "^permissions:" "$f"
done

# Run dependency audit
cargo audit 2>/dev/null || npm audit --omit=dev 2>/dev/null || true
```

### Dependabot Alert Auto-Fix (MANDATORY before push)

**ALWAYS check and fix open Dependabot alerts before pushing.** Never leave HIGH/CRITICAL alerts unfixed when a patched version exists.

```bash
# 1. Check for open alerts
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/${REPO}/dependabot/alerts" \
  --jq '.[] | select(.state=="open") | "\(.number): \(.security_advisory.severity) — \(.dependency.package.name)@\(.security_vulnerability.vulnerable_version_range) → \(.security_vulnerability.first_patched_version.identifier)"'

# 2. For each alert with a fix: add override + reinstall
# npm: package.json → "overrides": {"pkg@vuln_range": ">=fix_ver"}
# pnpm: package.json → "pnpm.overrides": {"pkg@vuln_range": ">=fix_ver"}
# Then: pnpm install (or npm install)

# 3. Verify fix in lockfile
grep "<package>" pnpm-lock.yaml  # should show patched version

# 4. Commit: "fix: patch <pkg> <CVE> (Dependabot #N)"
```

**Rules:**
- AUTO-FIX any alert where `first_patched_version` exists
- If fix breaks the build, revert and document as known issue
- Never skip HIGH/CRITICAL with available fixes
- Dev-only deps with no prod impact: fix anyway (keeps alert count at zero)

---

## GitHub Actions CI Gate (Post-Push Verification)

**MANDATORY after every `git push` to a repo with GitHub Actions workflows.** After pushing code (feature, fix, or PR), detect if the repo has CI workflows and wait for all checks to pass. If checks fail, investigate the failure logs, fix the issue, and re-push — up to 3 retry cycles.

### Detection
```bash
# Check for workflow files or recent runs
ls .github/workflows/ 2>/dev/null
gh run list --limit 3 2>/dev/null
```

If either returns results, CI verification is active.

### Post-Push Monitoring
```bash
# Wait for checks to register
sleep 5

# If there's a PR, watch PR checks
PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)
if [ -n "$PR_NUM" ]; then
  gh pr checks "$PR_NUM" --watch --fail-fast
else
  # Watch workflow runs for this commit
  for RUN_ID in $(gh run list --commit "$(git rev-parse HEAD)" --json databaseId --jq '.[].databaseId'); do
    gh run watch "$RUN_ID"
  done
fi
```

### On Failure: Fix-and-Retry Loop (Max 3 Attempts)
```bash
# 1. Get failure logs
FAILED_RUNS=$(gh run list --commit "$(git rev-parse HEAD)" --json databaseId,conclusion,name \
  --jq '.[] | select(.conclusion=="failure") | .databaseId')
for RUN_ID in $FAILED_RUNS; do
  gh run view "$RUN_ID" --log-failed 2>&1 | tail -50
done

# 2. Investigate and fix the issue (use 5-phase workflow for complex failures)
# 3. Commit fix and push
# 4. Watch new checks — repeat until green or 3 attempts exhausted
```

### Common CI Failure Fixes
| Pattern | Fix |
|---------|-----|
| `cargo fmt` diff | `cargo fmt --all` locally |
| Lint/style errors | Run linter with `--fix` flag |
| Test failures | Fix test or source code |
| Type errors | Fix TypeScript/type issues |
| Missing i18n | Add translations for all locales |
| `unused_mut` / `dead_code` | Add `#[allow(...)]` for cfg-gated code |
| Code scanning TODO alerts | Convert `TODO`/`FIXME`/`HACK` to `NOTE:` or resolve them |
| Token-Permissions alerts | Add top-level `permissions: read-all`, narrow job-level writes |
| RUSTSEC vulnerability | `cargo audit`, update crate or add exception with rationale |

### Integration
- This gate runs after EVERY `git push` during a `/carmack` session
- Applies to feature implementation, bug fixes, and PR submissions
- Do NOT consider the task complete until all CI checks are green
- After 3 failed attempts, stop and report the persistent failure to the user

## Session Files

Investigations are saved to `tools/debug-sessions/{issue-name}/`:
- `{issue-name}-state.md` — Current phase, what's proven/disproven
- `{issue-name}-evidence.md` — Collected evidence and logs
- `{issue-name}-hypothesis.md` — Tested hypotheses and results

Resume: "Resume the {issue-name} investigation"

## Instructions

When this skill is invoked:

**STEP 0 — Notify the user BEFORE launching the agent (MANDATORY):**
Before invoking the Task tool, print a brief status message so the user knows what to expect:
- For bugs/debugging: "Investigating [issue]. This uses a 5-phase deep debugging workflow and may take several minutes depending on complexity. You'll see the results when it finishes."
- For feature requests: "Building [feature]. Running build decision framework first, then implementing. You'll see the results when it finishes."

This prevents the user from thinking the process is stuck during long-running investigations.

**PHASE 0a — LIVE SITE CHECK (for web projects with a production URL):**

Before investigating bugs or verifying fixes on deployed sites, warm up Chrome CDP so you can take screenshots and inspect the live page without the "Allow debugging" popup blocking you:

```bash
# Warm up CDP daemon for production tab (one-time popup, then instant access)
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"

# Find the production tab (adjust URL for the project)
TARGET=$($CDP list 2>/dev/null | grep "aiva-m9t.pages.dev\|aivaclaims.com" | awk '{print $1}' | head -1)

# If found, pre-warm the daemon (avoids "Allow" popup on subsequent commands)
if [ -n "$TARGET" ]; then
  $CDP snap "$TARGET" > /dev/null 2>&1 && echo "[CDP] Daemon warm for $TARGET"
fi
```

Then use `$CDP shot $TARGET` to screenshot, `$CDP snap $TARGET` for accessibility tree, `$CDP eval $TARGET "..."` to run JS — all without popups.

**PHASE 0 — 100% PRODUCTION CODE COVERAGE (MANDATORY):**

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

**PHASE 0b — ZERO-TOLERANCE LINT & SECURITY AUTO-FIX (MANDATORY BEFORE COMPLETION):**

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

**PHASE 0a — FULL CODEBASE AUDIT (MANDATORY FOR ALL CHANGES):**

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

1. **For feature requests**: Run the Build Decision Framework FIRST — check if the user is about to build something that already exists as a service/library. Flag time sinks before writing code.
2. **For bugs/debugging**: Use the 5-Phase Workflow with repro harnesses and debugger attachment.
3. Use the Task tool with `subagent_type: carmack-mode-engineer`
4. Pass the issue or feature description from the user
5. The agent will build repro harnesses and attach debuggers as needed
6. Approval checkpoint before implementing fixes
7. **After every git push**: Run GitHub Actions CI Gate — detect if repo has workflows, watch all checks with `gh pr checks --watch` or `gh run watch`, and if any fail: read logs with `gh run view --log-failed`, fix the issue, commit, push, and repeat (max 3 retries). Do NOT consider the task complete until all CI checks are green.

```
Launch carmack-mode-engineer agent now with the user's issue description.
IMPORTANT: After EVERY git push, check if the repo has GitHub Actions workflows (ls .github/workflows/ or gh run list --limit 3). If yes, watch all checks until they complete. If any check fails, read the failure logs with `gh run view <RUN_ID> --log-failed`, fix the issue, commit, push, and repeat — up to 3 retry cycles. Do NOT consider the task complete until all CI checks are green.
```
