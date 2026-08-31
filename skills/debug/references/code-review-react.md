# Code Review: TypeScript & React 19

### TypeScript & React 19 Review

#### Critical (Block Merge)

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

#### High Priority

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

#### Architecture/Style

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
