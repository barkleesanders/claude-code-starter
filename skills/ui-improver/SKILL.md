---
name: ui-improver
user-invocable: true
description: Complete UI improvement workflow combining design intelligence, micro-polish, and code simplification. Use when building, reviewing, or improving any UI — new pages, components, style decisions, accessibility reviews, animation polish, code cleanup after writing frontend code. Triggers on any frontend work: "make this look better", "polish the UI", "review this component", "improve the interface", "simplify this code", building dashboards, landing pages, forms, modals, buttons, or any visual element.
---

# UI Improver

A complete UI improvement workflow that runs three phases in order:

1. **Design Decisions** — structural design choices: accessibility, layout, typography systems, color, navigation, forms, animation principles
2. **Micro-Polish** — details that compound into a great experience: border radius, shadows, typography rendering, animations, image outlines, hit areas
3. **Code Simplification** — clean up the implementation after writing: clarity, consistency, no unnecessary complexity

Run all three phases on any UI work. Skip phases that clearly don't apply (e.g., skip Phase 1 for a one-line change).

---

## Phase 1: Design Decisions

Follow this priority order — fix CRITICAL issues before MEDIUM ones.

### 1. Accessibility (CRITICAL)

- Minimum 4.5:1 contrast ratio for normal text, 3:1 for large text
- Visible focus rings on all interactive elements (2–4px)
- Descriptive `alt` text on meaningful images; empty `alt=""` on decorative ones
- `aria-label` on icon-only buttons
- Tab order matches visual order; full keyboard support
- Use `<label for>` on all form inputs — never placeholder-only labels
- `role="alert"` or `aria-live="polite"` for dynamic error messages
- `prefers-reduced-motion` — reduce or disable animations when requested
- Don't convey information by color alone; add icon or text
- Skip links ("Skip to main content") for keyboard users
- Sequential heading hierarchy (h1→h6, no level skip)

### 2. Touch & Interaction (CRITICAL)

- Min tap target: 44×44pt (Apple) / 48×48dp (Material); extend with pseudo-element if visual is smaller
- 8px minimum gap between touch targets
- Use `touch-action: manipulation` to remove 300ms tap delay on web
- Disable buttons during async operations; show spinner
- Visual feedback within 100ms of tap
- Don't rely on hover-only interactions; always provide tap/click equivalent
- Keep primary touch targets away from notch, Dynamic Island, gesture bar, screen edges

### 3. Performance (HIGH)

- Use WebP/AVIF images with `srcset`/`sizes`
- Declare `width`/`height` or `aspect-ratio` on images to prevent CLS
- `font-display: swap` to avoid invisible text (FOIT)
- Lazy load below-fold images (`loading="lazy"`)
- Use skeleton/shimmer instead of spinners for loads > 1s
- Virtualize lists with 50+ items
- Only animate `transform`/`opacity`/`filter` — never `width`, `height`, `top`, `left`
- Debounce/throttle scroll, resize, input events

### 4. Style & Consistency (HIGH)

- Match style to product type — don't mix flat and skeuomorphic randomly
- One icon set/visual language across the product (consistent stroke width, corner radius)
- No emoji icons — use SVG (Heroicons, Lucide, etc.)
- Each screen has one primary CTA; secondary actions are visually subordinate
- Use semantic color tokens (`primary`, `error`, `surface`) — not raw hex in components
- Consistent elevation/shadow scale for cards, sheets, modals
- Design light and dark variants together

### 5. Layout & Responsive (HIGH)

- Mobile-first; `<meta name="viewport" content="width=device-width, initial-scale=1">`
- No horizontal scroll on mobile
- Body text minimum 16px on mobile (avoids iOS auto-zoom)
- Line length: 35–60 chars on mobile, 60–75 on desktop
- Use `min-h-dvh` instead of `100vh` on mobile
- 4pt/8dp spacing system
- Consistent `max-w` on desktop (`max-w-6xl` / `max-w-7xl`)
- Fixed navbars/bottom bars must reserve padding for underlying content

### 6. Typography & Color (MEDIUM)

- Line height 1.5–1.75 for body text
- Font weight hierarchy: Bold headings (600–700), Regular body (400), Medium labels (500)
- Avoid text below 12px
- `tabular-nums` on all dynamically updating numbers (prices, counters, timers)
- `text-wrap: balance` on headings; `text-wrap: pretty` on paragraphs/captions
- `-webkit-font-smoothing: antialiased` on macOS root layout

### 7. Animation (MEDIUM)

- Duration: 150–300ms micro-interactions; ≤400ms complex transitions
- Ease-out for entering; ease-in for exiting
- Always interruptible — use CSS transitions for interactive state changes, keyframes for one-shot sequences
- Exit animations shorter than enter (~60–70% duration)
- Stagger list/grid entrance by 30–50ms per item (not all-at-once)
- Spring physics preferred over linear for natural feel
- Every animation must express meaning — not just decoration

### 8. Forms & Feedback (MEDIUM)

- Visible label per input (not placeholder-only)
- Error message below the related field; include cause + how to fix
- Loading → success/error state on submit
- Mark required fields
- Validate on blur, not on every keystroke
- Semantic input types (`email`, `tel`, `number`) for correct mobile keyboard
- Confirm before destructive actions
- Auto-dismiss toasts in 3–5s; use `aria-live="polite"` so screen readers catch them

### 9. Navigation (HIGH)

- Bottom nav: max 5 items with icon + label; top-level only
- Back navigation must be predictable; preserve scroll and state
- Current location highlighted in navigation
- Modals must have a clear close affordance; don't use modals for primary navigation flows
- Support system gesture navigation (iOS swipe-back, Android predictive back)
- After page transition, move focus to main content region

### 10. Charts & Data (when applicable)

- Match chart type to data (trend → line, comparison → bar, proportion → pie/donut ≤5 categories)
- Always show a legend; provide tooltips on hover/tap with exact values
- Accessible color palettes — don't rely on red/green alone
- Provide a table or `aria-label` summary for screen readers
- Show skeleton/shimmer while chart data loads
- Respect `prefers-reduced-motion` for chart entrance animations

---

## Phase 2: Micro-Polish

These details compound into a "just feels right" experience.

### Concentric Border Radius

`outerRadius = innerRadius + padding`

```css
/* Good */
.card { border-radius: 20px; padding: 8px; }
.card-inner { border-radius: 12px; }  /* 20 - 8 = 12 ✓ */

/* Bad — same radius on both */
.card { border-radius: 12px; padding: 8px; }
.card-inner { border-radius: 12px; }
```

Tailwind: `rounded-2xl p-2` outer → `rounded-lg` inner.

### Optical Alignment

- **Buttons with icon**: `icon-side-padding = text-side-padding - 2px`
- **Play triangles**: shift SVG 2px right (`margin-left: 2px`)
- **Asymmetric icons** (stars, arrows): fix directly in the SVG viewBox

### Shadows Over Borders

Replace depth/elevation borders with layered `box-shadow`:

```css
/* Light mode */
--shadow-border:
  0px 0px 0px 1px rgba(0,0,0,0.06),
  0px 1px 2px -1px rgba(0,0,0,0.06),
  0px 2px 4px 0px rgba(0,0,0,0.04);

/* Dark mode */
--shadow-border: 0 0 0 1px rgba(255,255,255,0.08);
```

Don't apply to dividers or layout separators — those stay as borders.

### Image Outlines

```css
/* Light mode — MUST be pure black, not slate/zinc/etc. */
img { outline: 1px solid rgba(0,0,0,0.1); outline-offset: -1px; }

/* Dark mode — MUST be pure white */
img { outline: 1px solid rgba(255,255,255,0.1); outline-offset: -1px; }
```

Tailwind: `outline outline-1 -outline-offset-1 outline-black/10 dark:outline-white/10`

Never use a tinted neutral — it reads as dirt on the image edge.

### Font Smoothing

```css
html { -webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale; }
```

Tailwind: `<html className="antialiased">` on root layout. macOS only; safe to apply globally.

### Tabular Numbers

```css
.counter, .price, .timer { font-variant-numeric: tabular-nums; }
```

Apply to: counters, prices, timers, scoreboards, table columns. Not needed on static display numbers.

### Text Wrap

```css
h1, h2, h3 { text-wrap: balance; }   /* Tailwind: text-balance */
p, li, figcaption { text-wrap: pretty; }  /* Tailwind: text-pretty */
/* Leave long text (10+ lines) default */
```

### Interruptible Animations

- CSS `transition` for interactive state changes (hover, toggle, open/close) — interruptible by design
- CSS `@keyframes` only for one-shot sequences (page enter, loading)

### Staggered Enter / Subtle Exit

- Split content into semantic chunks (title, description, buttons) and stagger with ~100ms delay
- Combine `opacity`, `translateY(12px)`, `blur(4px)` for enter
- Exit: `translateY(-12px)`, shorter duration (~150ms vs ~300ms enter)
- `AnimatePresence initial={false}` to skip enter animations on first render (for default-state elements)

### Contextual Icon Animations

When icons swap on state change:
- `scale: 0.25 → 1`, `opacity: 0 → 1`, `filter: blur(4px) → blur(0px)` — use exactly these values
- With Framer Motion: `transition: { type: "spring", duration: 0.3, bounce: 0 }` — bounce always `0`
- Without motion library: keep both icons in DOM, cross-fade with CSS, use `cubic-bezier(0.2, 0, 0, 1)`
- Check `package.json` for `motion`/`framer-motion` before choosing approach

### Scale on Press

```css
.button:active { scale: 0.96; }
/* Never below 0.95 — it feels exaggerated */
```

Add a `static` prop pattern to disable when motion is distracting (form submits, etc.).

### Never `transition: all`

```css
/* Bad */
.button { transition: all 150ms ease-out; }

/* Good */
.button { transition-property: scale, background-color; transition-duration: 150ms; }
```

Tailwind `transition` shorthand = `transition: all` — use `transition-[scale,opacity]` bracket syntax instead.

### `will-change` — Sparingly

Only for `transform`, `opacity`, `filter`. Never `will-change: all`. Add only when you notice first-frame stutter. Each layer costs memory.

---

## Phase 3: Code Simplification

After writing UI code, review for clarity and consistency. The goal is readable, explicit code — not the fewest lines.

### Rules

1. **Preserve functionality** — never change what code does, only how
2. **Reduce nesting** — flatten conditionals and component hierarchies where possible
3. **Eliminate redundancy** — remove duplicated logic, consolidate related state
4. **Clear naming** — rename variables and functions so comments become unnecessary
5. **No nested ternaries** — use `if/else` or `switch` for multiple conditions
6. **Explicit over clever** — `if (isLoading) return <Spinner />` beats a dense inline expression
7. **Scope only recent changes** — only touch code modified in this session unless asked

### Common Simplifications in UI Code

| Pattern | Fix |
|---------|-----|
| Nested ternary in JSX | Extract to variable or early return |
| Inline styles that repeat | Extract to CSS class or Tailwind utility |
| `className` string concatenation | Use `cn()` / `clsx()` |
| Handler that only calls another function | Remove wrapper, pass directly |
| Boolean prop `isVisible={true}` | Use shorthand `isVisible` |
| State that mirrors props | Derive from props instead |
| `useEffect` with no dependencies | Move logic outside component |
| Component with 10+ props | Extract sub-components or use composition |

---

## Review Output Format

Present all changes as a **Before/After table**, grouped by principle:

```markdown
#### Concentric border radius
| Before | After |
| --- | --- |
| `rounded-xl` on card + `rounded-xl` on inner | `rounded-2xl` on card, `rounded-lg` on inner |

#### Tabular numbers
| Before | After |
| --- | --- |
| `<span>{count}</span>` | `<span className="tabular-nums">{count}</span>` |
```

Include every change. Omit tables for principles where nothing needed to change.

---

## Quick Checklist

**Phase 1 — Design**
- [ ] Contrast ≥ 4.5:1 on all text
- [ ] All interactive elements keyboard-accessible
- [ ] Touch targets ≥ 44×44px
- [ ] No horizontal scroll on mobile
- [ ] One primary CTA per screen
- [ ] Form errors below the relevant field

**Phase 2 — Polish**
- [ ] Nested rounded elements use concentric border radius
- [ ] Icons optically centered
- [ ] Shadows instead of borders for depth/elevation
- [ ] `text-wrap: balance` on headings, `pretty` on paragraphs
- [ ] `-webkit-font-smoothing: antialiased` on root
- [ ] Tabular numbers on dynamic values
- [ ] Image outlines with pure black/white (no tinted neutrals)
- [ ] Buttons scale to `0.96` on press
- [ ] `AnimatePresence initial={false}` on default-state elements
- [ ] No `transition: all`
- [ ] `will-change` only on transform/opacity/filter

**Phase 3 — Simplify**
- [ ] No nested ternaries in JSX
- [ ] `cn()` for className logic
- [ ] No wrapper handlers that just call through
- [ ] State doesn't mirror props
- [ ] Components have clear, single responsibilities
