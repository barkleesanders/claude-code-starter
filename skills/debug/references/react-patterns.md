# React Patterns

## Pattern 2: React "X is not defined" (Scope Bug)

**Rank: #1 production crash cause.**

Inner/child component references a variable from parent scope without receiving it as a prop.

### Quick Detection
```bash
grep -n "const.*= (" components/*.tsx | grep -v "export"
grep -rn "{[a-z][a-zA-Z]*\." --include="*.tsx" | grep -v "\?."
```

### Fix
- Pass the variable as a prop, or move the component outside the parent
- Add `?.` optional chaining for all nullable access

Full guide: `/carmack` React-Specific Checks section

---

## Pattern 3: Silent React Startup Failure

**Rank: #2 production crash cause.**

Module-level code throws before React mounts. No console errors, only SSR fallback visible.

### Quick Detection
```javascript
// Chrome DevTools console:
import('/src/react-app/App.tsx').catch(e => console.error('Module failed:', e))
```

```bash
grep -Bn5 "export default function\|export function App" src/react-app/App.tsx | grep "validate\|throw\|assert"
```

### Fix
Pass fallbacks to `validateClientEnv()` for vars with hardcoded defaults.

Full guide: `/carmack` Silent React Startup Failure section

---

## Pattern 15: Unnecessary useEffect Causing Render Bugs

**Rank: #1 React anti-pattern -- causes extra render cycles, stale closures, and sync bugs.**

`useEffect` should ONLY be used to synchronize with external systems (browser APIs, third-party widgets, network requests). Every other use is wrong.

### Symptoms
- Component renders twice on state change (extra render cycle from `useEffect` -> `setState`)
- Stale data displayed briefly before correcting itself (effect runs after paint)
- Infinite re-render loops (`useEffect` sets state that triggers itself)
- State "lags behind" by one render

### Quick Detection
```bash
# Find all useEffect -- each one needs justification
grep -rn "useEffect" --include="*.tsx" --include="*.ts" src/react-app/ | grep -v node_modules

# Derived state anti-pattern: useEffect that calls setState with computed value
grep -A3 "useEffect.*=>" --include="*.tsx" src/react-app/ | grep "set[A-Z]"

# Copying server data to local state
grep -B2 -A2 "useEffect.*data" --include="*.tsx" src/react-app/ | grep "set[A-Z].*data"
```

### Fix Patterns

| Instead of | Do this |
|-----------|---------|
| `useEffect(() => setX(compute(y)), [y])` | `const x = compute(y)` (compute during render) |
| `useEffect(() => { if (changed) doThing() }, [val])` | Move to the event handler that caused the change |
| `useEffect + useRef` to track previous value | `[prev, setPrev] = useState(val)` + compare during render |
| `useEffect(() => setState(null), [prop])` | Key the component: `<Comp key={prop} />` |
| `useEffect(() => fetch(...), [])` | TanStack Query / SWR / React 19 `use()` |

### Valid useEffect uses (don't flag these)
- `addEventListener` / `removeEventListener`
- Third-party widget init/destroy
- `IntersectionObserver` / `ResizeObserver`
- WebSocket connect/disconnect
- `document.title` update
- `localStorage` read on mount (App.tsx root only)

Full guide: `/carmack` useEffect Abuse section

---

## Pattern 13: User Preference Lost on Page Reload (localStorage Write Without App.tsx Read)

**Rank: #5 invisible UX regression -- preference appears to save but resets on refresh.**

When a user preference (font size, theme, language) is written to `localStorage` only inside the preference control component, the preference is applied while that component is mounted, but on the next page load the HTML element reverts to its default before React mounts and the component renders.

### Symptoms
- Text size slider "saves" but resets on every page refresh
- Theme/color/language preference reverts after navigation away and back
- Works in the same session but lost when opening a new tab
- The preference control shows the correct saved value (reads localStorage correctly), but the DOM hasn't been updated yet

### Root Cause
The fix has **two required parts**:
1. **Writer**: Component writes pref to localStorage AND applies it to the DOM immediately (`useEffect`)
2. **Reader**: App root (`App.tsx`) reads the pref from localStorage on EVERY mount and applies it to the DOM -- BEFORE routes render

If only the Writer exists, the DOM uses CSS defaults until the component renders (causing a visible flash and wrong default).

### Fix Pattern

```tsx
// TextSizeControl.tsx -- WRITER (applies + saves)
useEffect(() => {
  localStorage.setItem("dashboardFontSize", fontSize.toString());
  document.documentElement.style.fontSize = `${fontSize}px`; // applies immediately
}, [fontSize]);

// App.tsx -- READER (restores on every page load, before routes render)
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

### Scaling Mechanism: fontSize vs CSS Custom Properties

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

### Quick Detection
```bash
# Find localStorage.setItem without corresponding App.tsx restoration
grep -rn "localStorage.setItem" --include="*.tsx" src/react-app/ | grep -v "App.tsx"
# Then verify each key is also read in App.tsx:
grep -n "localStorage.getItem" src/react-app/App.tsx

# Find components that write to document.documentElement but don't have App.tsx counterpart
grep -rn "document.documentElement.style" --include="*.tsx" src/react-app/ | grep -v "App.tsx"
```

### Real-World Case: AIVA Text Size (2026-03-13)
- **Symptom**: A+/A-/A text size selection saved but reset on every page refresh
- **Root cause**: `TextSizeControl.tsx` wrote to localStorage, but no App.tsx reader -- DOM reverted to `html { font-size: 16px }` on every new load
- **Fix**: Added `useEffect([], [])` to `App.tsx` that reads `dashboardFontSize` and applies to `document.documentElement.style.fontSize` on mount
- **Files**: `src/react-app/App.tsx`, `src/react-app/components/TextSizeControl.tsx`
- **Commit**: `e77b296` (persistence fix) + `f322432` (site-wide scaling via html font-size)

---

## Async Button Double-Click

- **Symptom**: Duplicate API calls, double submissions, race conditions
- **Quick Detection**: `grep -rn "onClick.*async" --include="*.tsx" src/ | grep -v "disabled="`
- **Fix**: Add `isLoading` state, `disabled={isLoading}`, spinner, try/finally reset
- **Incident (2026-03-15)**: Dashboard "Complete Step" buttons had no disabled state during async

---

## Missing Frontend Auth Guard

- **Symptom**: Unauthenticated user sees loading spinner then error instead of redirect to sign-in
- **Quick Detection**: Find pages using `secureFetch` without `isAuthenticated` check or `ProtectedRoute` wrapper
- **Fix**: Add `useEffect` with `isAuthenticated` check that navigates to `/` or wrap route in auth guard
- **Incident (2026-03-15)**: `/referral` route had no auth guard -- showed cryptic error
