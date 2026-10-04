# Code Implementation — Writing Frontend Code Directly

**Load this when**: the user wants Claude to write working frontend code (HTML/CSS/JS, React, Vue, Svelte, Next.js, etc.) directly in their repo. NOT a Stitch generation.

**Assumes**: `aesthetic-core.md` already ran and a direction is locked. Every code decision below must serve that direction.

---

## Code Imperatives

Everything you write must be:

1. **Production-grade** — runs, compiles, no placeholders, no TODOs. If you'd be embarrassed to commit it, don't write it.
2. **Functional** — wired up. Buttons work, forms submit, state persists where it should. No "// connect this later."
3. **Visually striking and memorable** — the direction from Phase 0 has to *show* in the output.
4. **Cohesive** — one clear aesthetic point-of-view. Don't mix brutalist nav with playful cards.
5. **Meticulously refined** — spacing values intentional, font weights deliberate, color choices justified.

---

## Framework Choice

Match transport to direction and constraints.

| Constraint / Direction | Reach for |
|---|---|
| Static marketing page, no JS state | Vanilla HTML + CSS, optional Alpine.js for tiny interactions |
| Component library or design system | Pure HTML/CSS or web components (framework-agnostic) |
| Form-heavy / app shell with state | React (Next.js if SSR matters) or SvelteKit |
| Maximalist motion / GSAP-heavy | React (best Motion-library ecosystem) or vanilla |
| Editorial / typography-heavy | Astro (zero-JS by default) |
| User wrote the framework in their prompt | That one. Don't second-guess. |

If the user is in an existing repo, **match what's already there**. Don't introduce a new framework mid-project.

---

## Full-page HTML files: document order

When writing a single self-contained HTML file (vanilla static page, design-system demo, one-shot prototype), use **`<body>` → `<script>` → `<style>`** order. NOT the traditional `<head><style><script></head><body>`.

```html
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>...</title>

<body>
  <!-- All content here, first. -->
</body>

<script>/* behavior, after body */</script>
<style>/* all CSS, last */</style>
</html>
```

Why: dramatically improves generation quality — body content gets written first, so scripts and styles are scoped to what's actually on the page instead of being scaffolded against an empty body. Browsers reparse trailing `<style>`/`<script>` into the head correctly; CSS matching is order-agnostic. Do not "fix" generated files back to the standard layout.

This applies to single-file HTML deliverables. Framework components (React/Vue/Svelte/Astro) keep their normal structure — the framework owns the document shell.

---

## Typography Implementation

From `aesthetic-core.md`'s direction: pair **display + body** fonts.

- Load with `@font-face` (self-host preferred) or `<link>` from a CDN that *isn't* `fonts.googleapis.com/css?family=Inter`.
- Set `font-display: swap` to prevent FOIT.
- Use `font-feature-settings` to enable ligatures, oldstyle figures, and stylistic alternates that ship with the font but aren't on by default.
- Type scale: pick a ratio (1.25 / 1.333 / 1.5 / 1.618) and generate the scale from a single base size. No arbitrary px.

CSS variable convention:

```css
:root {
  --font-display: 'Fraunces', 'Migra', serif;
  --font-body: 'IBM Plex Sans', 'Geist', sans-serif;
  --type-scale: 1.333;
  --text-base: 1rem;
  --text-lg: calc(var(--text-base) * var(--type-scale));
  --text-xl: calc(var(--text-lg) * var(--type-scale));
  /* ... */
}
```

---

## Color Implementation

CSS variables, always. Tailwind users: define in `@theme` (v4) or `tailwind.config.js` `theme.colors` (v3).

```css
:root {
  /* Direction-driven palette */
  --bg-base: #0a0a0a;          /* dominant 60% */
  --bg-elevated: #1a1a1a;      /* dominant 60% (variant) */
  --fg-default: #f5f0e8;       /* primary 30% */
  --fg-muted: rgba(245, 240, 232, 0.6);
  --accent: #d4a45f;           /* sharp 10% — gold for luxury direction */
}
```

Rules:
- 60-30-10 minimum. 80-15-5 is fine for restraint-heavy directions.
- Don't use `rgb(255, 255, 255)` or `#000000` directly. Pick near-blacks (`#0a0a0a`) and near-whites (`#fafaf7`) — they read warmer and more deliberate.
- Dark-mode toggle? Define a parallel set under `[data-theme="light"]` or `@media (prefers-color-scheme: light)`.

---

## Motion Implementation

From `aesthetic-core.md`: **one orchestrated page load > scattered micro-interactions**, and every animation passes the four-question gate first (frequency → purpose → tool → curve/duration). The full build sequence with ready-to-copy recipes is `Skill(animate)` + its `RECIPES.md`; the strict reviewer is `Skill(review-animations)`.

### Tool ladder — stop at the first rung that fits

| Need | Tool |
|---|---|
| Hover, press, color, a state toggle driven by a class/attribute | **CSS transition** (interruptible — retargets from the current value) |
| Entry on mount with no JS state | **CSS `@starting-style`** (fallback: `useEffect(() => setMounted(true), [])` + `data-mounted`) |
| Predetermined motion that must stay smooth while the page is busy | **CSS animation** — runs off the main thread; rAF-driven JS drops frames during load/paint |
| Programmatic control with CSS performance, no library | **WAAPI** `element.animate([...], { duration, easing, fill: 'forwards' })` |
| Springs, layout animations, exit animations, gesture-driven values | **Motion** (`import { motion, useSpring } from "motion/react"`) |
| Scroll-driven storytelling, long timelines | **GSAP** (vanilla or React) |
| Route-change transitions in Next 15+ / React Router 7 | **View Transitions API** |

If the task is really a *component* (toast, drawer, ⌘K menu, dropdown, OTP input) stop and run `Skill(pick-ui-library)` — hand-rolling those is how you get a `<div>` dropdown with no focus management.

### React specifics
- **Motion shorthands are NOT hardware-accelerated.** `animate={{ x: 100 }}` / `y` / `scale` run on the main thread via rAF and drop frames under load. Use the full string: `animate={{ transform: "translateX(100px)" }}`. (Vercel's dashboard tab animation dropped frames on page load for exactly this reason; CSS fixed it.)
- Spring config, Apple-style: `{ type: "spring", duration: 0.5, bounce: 0.2 }` — easier to reason about than mass/stiffness/damping. Keep bounce 0.1–0.3 and only after a momentum gesture.
- `AnimatePresence initial={false}` so default-state elements don't animate in on first render.
- Decorative mouse-tracking: interpolate through `useSpring`, never bind the value 1:1 to the pointer.
- Write per-frame values to `ref.current.style`, not state — a React re-render per frame is a jank source.

### Vanilla / Vue / Svelte
- **CSS keyframes + `animation-delay`** for the page-load stagger. One `.reveal` class with `--i` / `nth-child` delays (30–80 ms apart, ≤ 500 ms total) gets you 80% of the way.
- **CSS scroll-driven animations** (`animation-timeline: scroll()`) or `IntersectionObserver` (`{ once: true, margin: "-100px" }`) for reveal-on-scroll. Never a `scroll` event listener. No parallax by default.
- `clip-path: inset()` is the sanctioned fourth animatable property — image reveals, hold-to-delete overlays, seamless tab-color transitions (duplicate the list, clip the "active" copy), comparison sliders. Pure CSS, GPU-composited.
- `translate()` percentages are relative to the element's own size: `translateY(100%)` hides a drawer/toast whatever its height. Prefer over px.

### Performance cheatsheet (emilkowalski/skills)

| Problem | Solution |
|---|---|
| Animation stutters | Animate `transform`/`opacity`, not `width`/`top` |
| Long list scrolls slowly | Virtualize — only render what's visible (`Skill(pick-ui-library)` → Virtuoso) |
| Blur causes perf issues | Keep animated `blur()` under 20px (Safari especially) |
| Motion's `x`/`y` drops frames | Animate the full `transform` string instead |
| Random properties animate | Never `transition: all`; list exact properties |
| React re-renders every frame | Write to `ref.current.style`, not state |
| Element shifts 1px as motion starts | `will-change: transform` — only once you see it |
| Drawer with many children janks on drag | Set `transform` on the element, never a CSS variable on the parent (style recalc on every child) |

### Mobile-facing output — ship the `mobile-native` Baseline first
Any page that will be opened on a phone (all of them, plus every Capacitor / PWA surface) gets this floor **before the first component** — none of these reproduce in desktop device emulation, and each is one declaration:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content" />
<meta name="theme-color" media="(prefers-color-scheme: light)" content="<top-of-page color>" />
<meta name="theme-color" media="(prefers-color-scheme: dark)"  content="<top-of-page color>" />
```
```css
html { -webkit-tap-highlight-color: transparent; -webkit-text-size-adjust: 100%; overscroll-behavior: none; }
input, textarea, select { font-size: 16px; }                   /* iOS zooms into anything smaller — never fix it with maximum-scale=1 */
button, a, [role="button"] { touch-action: manipulation; user-select: none; -webkit-user-select: none; }
@media (hover: hover) and (pointer: fine) { /* every :hover rule lives here — touch fakes hover and leaves it stuck */ }
.app { height: 100dvh; }  .hero { min-height: 100svh; }         /* never 100vh for an app shell or bottom-pinned UI */
.bottom-bar { padding-bottom: env(safe-area-inset-bottom, 0px); } /* needs viewport-fit=cover or it's 0 */
```
Full symptom table (`Hover state stuck after tap` → …) and the *Never Ship* list: `Skill(mobile-native)`. Verify on real hardware — connect the phone, dev server on `0.0.0.0`, Safari → Develop / `chrome://inspect`.

### Don't
- Animate `width` / `height` / `top` / `left` / `margin` / `padding`. Use `transform` and `opacity` only (`height` tolerated for accordions where no transform equivalent exists).
- Animate everything. Contrast is the point.
- Use `transition: all`. Name the properties explicitly.
- Use `ease-in` on UI, enter from `scale(0)`, animate a keyboard-initiated action, or exceed 300 ms on a UI element without a stated reason.
- Ship motion without `prefers-reduced-motion` (gentler, not zero) and hover gating.

## Spatial Composition Implementation

The unexpected layouts from `aesthetic-core.md` need real code structure:

- **CSS Grid** is the right tool for asymmetric layouts. Define a named-line grid (`grid-template-columns: [edge-l] 1fr [content-start] 8fr [content-end] 1fr [edge-r]`) and break out of `content-*` deliberately.
- **Subgrid** for nested alignment without re-declaring the parent grid.
- **Container queries** (`@container`) for component-level responsiveness — way better than viewport breakpoints inside reusable components.
- **`aspect-ratio`** for media. `padding-bottom` hacks belong in 2018.

Grid-breaking moves:
- Headline spans `edge-l / edge-r` (full bleed); body stays in `content-*`.
- Image hangs into the right margin: `grid-column: content-end / edge-r`.
- Sticky sidenav while main content scrolls past it.
- Diagonal/rotated section divider with `clip-path` or `transform: skewY()`.

---

## Backgrounds & Visual Details Implementation

Solid colors are the absence of design (see `aesthetic-core.md`). Implementations:

| Effect | How |
|---|---|
| Grain / noise | Inline SVG `<filter>` with `feTurbulence`, scaled to fill, `mix-blend-mode: overlay`, 5-15% opacity |
| Gradient mesh | Layered `radial-gradient`s with `mix-blend-mode: screen` or `multiply` |
| Geometric patterns | SVG pattern in a `<defs>` block, referenced via `fill="url(#pattern)"` |
| Layered transparency | Multiple absolutely-positioned divs with `backdrop-filter: blur(...)` and low-alpha backgrounds |
| Dramatic shadow | Multiple `box-shadow` layers — never just one. Inset + outset + colored glow. |
| Custom cursor | `cursor: url(...) x y, auto;` with a real PNG/SVG, falling back to `crosshair` or `pointer` |
| Grain overlay on page | A fixed-position `<div>` with the SVG noise filter, `pointer-events: none`, `z-index: 9999` |

---

## Accessibility Floor (NEVER ship below this)

The bold-direction code still has to pass these:

- **Contrast**: WCAG 2.2 AA minimum. Use [APCA](https://github.com/Myndex/apca-w3) for type-on-color and design directions where you're deliberately edge-casing the palette.
- **Focus states**: visible, on-brand. Never `outline: none` without a replacement. Custom focus rings should match the accent color.
- **Reduced motion**: wrap all non-essential animations in `@media (prefers-reduced-motion: no-preference)` — animation is opt-in, not opt-out.
- **Semantic HTML**: `<button>` for buttons, `<a>` for links, `<nav>` for nav. Don't div-everything.
- **Keyboard nav**: every interactive element reachable by Tab, dismissible by Esc where applicable.

---

## Component Library Posture

If the user already has shadcn / MUI / Mantine installed: **customize, don't ship defaults.**

- Override the theme tokens to match Phase 0's direction. The shadcn default neutral-with-zinc-accent must go.
- Replace the font stack. Replace the radius scale. Replace the shadow tokens.
- Components are scaffolding — the aesthetic comes from you.

If the user has NO library installed: don't add one for a small page. Hand-write the few components.

---

## Device-Frame Previews — render at REAL device width, then scale-to-fit (MANDATORY)

When showing an app/site inside a phone (or tablet/laptop) mockup frame — a showcase of "every screen," a landing-page device shot, an `<iframe>` preview — **never let the embedded page render at the frame's narrow CSS width.** A mobile layout designed for ~390px, rendered into a ~240px iframe, overflows, wraps weirdly, and looks broken ("not formatted within the frame"). This bit the SUSU mockup (2026-06-17): Dashboard/Activity/Loans overflowed because the iframe was the bezel width.

**The fix — the standard product-shot technique:** render the inner page at a true device resolution and visually shrink it with a CSS transform.

```css
/* Frame inner = the visible window cut into the bezel. Clip with overflow:hidden. */
.phone-inner { width: 244px; height: 560px; overflow: hidden; border-radius: 32px; }
/* The iframe renders at a REAL phone width (390px logical) and a tall virtual height,
   then scales down to fit. scale = innerWidth / 390.  244/390 = 0.626.
   virtual height = visibleHeight / scale  →  560 / 0.626 ≈ 895. */
.phone-screen {
  width: 390px; height: 895px; border: 0;
  transform: scale(0.626); transform-origin: top left;
  pointer-events: none; /* preview only; the wrapping <a> opens it full-size */
}
```

Geometry recipe for any frame size: pick a real device logical width `D` (390 iPhone, 393 Pixel, 430 Pro Max, 768 iPad). `scale = innerW / D`. `iframeHeight = visibleH / scale`. The iframe's layout box stays `D × iframeHeight`; `overflow:hidden` on the parent clips it; the transform shows it at `innerW × visibleH`.

**Two traps that ride along (both hit SUSU):**
1. **Scrollbar inside every frame.** A fixed-height iframe whose content is taller shows a scrollbar. Add `scrolling="no"` to preview iframes (they're non-interactive anyway), and for the real app give the scroll root `scrollbar-width:none` + `::-webkit-scrollbar{display:none}` (mobile apps show no persistent bar; content still scrolls).
2. **`<span>` styled as a block collapses to 0×0.** If you refactor a device frame's notch/bezel from `<div>` to `<span>`, set `display:block` (or absolute) — inline elements ignore `width`/`height`, so the notch silently vanishes.

**Verify in a real browser, not source:** load the page and eval, per frame, `iframe.contentWindow.innerWidth === D` (renders at device width) and `documentElement.scrollWidth <= clientWidth` (no horizontal overflow). Screenshot to confirm the screens sit cleanly inside the bezels.

---

## Deterministic Anti-Pattern Scan (run before declaring done)

After writing the code, run [Impeccable](https://github.com/pbakaus/impeccable)'s CLI scanner. No API key, no LLM round-trip — it's regex + jsdom checking 27 specific patterns (side-stripe borders, gradient text, overused fonts, gray-on-color contrast, pure black/white, nested cards, bounce easing, tiny body text, small touch targets, layout-property animations, etc.). Catches things you'd otherwise notice on a second look.

```bash
# Scan files / dirs (HTML, CSS, JSX, TSX, Vue, Svelte)
npx impeccable detect src/

# Scan a deployed URL (uses Puppeteer)
npx impeccable detect https://your-preview-url

# Faster regex-only mode (skips jsdom)
npx impeccable detect --fast src/

# JSON output for CI
npx impeccable detect --json src/
```

Exit code `0` = clean. Exit code `2` = anti-patterns detected — read the findings and decide whether to rework or whether the violation is deliberate for the direction (e.g. brutalist intentionally uses pure `#000`). Document deliberate violations inline so the next pass doesn't "fix" them.

If `npx` isn't available or scanning fails: don't block, but note it in the handoff so the user can run it manually.

---

## Final Checklist Before Calling Done

- [ ] Phase 0 direction is visible in the output — not just "I tried"
- [ ] Anti-slop banlist clear: no Inter/Roboto/Arial unless deliberate, no purple-on-white, no shadcn defaults
- [ ] Absolute Bans clean (see `aesthetic-core.md` → Absolute Bans): no side-stripe borders, no gradient text, no decorative glassmorphism, no hero-metric template, no identical card grids, no modal-first
- [ ] Color uses OKLCH (not raw hex), neutrals tinted (no pure `#000`/`#fff`)
- [ ] Theme choice (dark vs light) backed by a one-sentence scene, not category reflex
- [ ] AI slop test passes both first-order (theme not guessable from category) and second-order (aesthetic not guessable from category + anti-reference)
- [ ] `npx impeccable detect` run on the output — clean, or deliberate violations annotated
- [ ] Real working code, no TODOs, no placeholders, no commented-out blocks
- [ ] Motion is orchestrated, not scattered; no bounce/elastic; no animating layout properties
- [ ] Contrast passes AA; reduced-motion respected; focus states visible
- [ ] Any device-frame/iframe preview renders the inner page at a REAL device width (e.g. 390px) and scales-to-fit — never at the cramped bezel width; no scrollbar in the frame; verified in-browser (innerWidth === device width, no horizontal overflow)
- [ ] If in an existing repo: framework + conventions + import style match the surrounding code
