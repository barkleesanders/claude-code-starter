# UX Patterns, Accessibility & Error Handling

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

# 7. CSP blocking third-party assets (broken icons/images with NO console errors)
# When images/icons are broken, ALWAYS check CSP before assuming color/CSS issues
CSP_FILE=$(find src/worker -name "securityHeaders*" -o -name "csp*" 2>/dev/null | head -1)
if [ -n "$CSP_FILE" ]; then
  echo "=== CSP Third-Party Domain Audit ==="
  grep -q "img.clerk.com" "$CSP_FILE" || echo "MISSING: img-src needs https://img.clerk.com (Clerk social icons)"
  grep -q "clerk-telemetry" "$CSP_FILE" || echo "MISSING: connect-src needs https://*.clerk-telemetry.com"
  grep -q "cdn.brevo.com" "$CSP_FILE" || echo "MISSING: script-src needs https://cdn.brevo.com"
  grep -q "s3.amazonaws.com" "$CSP_FILE" || echo "MISSING: img-src needs https://*.s3.amazonaws.com (DocuSeal)"
  grep -q "www.facebook.com" "$CSP_FILE" || echo "MISSING: img-src needs https://www.facebook.com (Meta Pixel)"
fi
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
| Broken/missing third-party icons (no console errors) | P1 — CSP blocking assets | Check `img-src` in CSP for third-party CDN domains (e.g., `img.clerk.com`) |

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

| Anti-Pattern | Better Approach |
|--------------|-----------------|
| Asking 5 questions at once | Ask one at a time |
| Jumping to implementation details | Stay focused on WHAT, not HOW |
| Proposing overly complex solutions | Start simple, add complexity only if needed |
| Ignoring existing codebase patterns | Research what exists first |
| Making assumptions without validating | State assumptions explicitly and confirm |
| Creating lengthy design documents | Keep it concise — details go in the plan |

---

### MVP Shipping Checklist

If a feature takes >1 day and a service solves it in <1 hour, use the service. Your energy is worth more than your custom implementation. Migrate later IF real usage data justifies it.

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
