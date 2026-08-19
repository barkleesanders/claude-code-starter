# React Safety Checks

Covers Phase 1.3 (React scope and env safety) and Phase 1.35 (useEffect abuse check).

---

## Phase 1.3: REACT SCOPE & ENV SAFETY CHECKS

**Purpose**: Prevent "X is not defined" production crashes and silent React startup failures.

**1. React Scope Check** — Find child components referencing parent scope:
```bash
# Child components referencing parent scope (potential crash)
grep -rn "const.*= (" --include="*.tsx" src/ | grep -v "export" | head -20
# JSX using variables without optional chaining (null crash)
grep -rn "{[a-z][a-zA-Z]*\.[a-z]" --include="*.tsx" src/ | grep -v "\?." | head -20
# Nested component definitions (anti-pattern)
grep -B2 "return.*<" --include="*.tsx" src/ | grep "const.*= () =>" | head -10
```
- If scope issues found: WARN with file:line locations

### Common Bug Pattern
```tsx
// WILL CRASH IN PRODUCTION
const Parent = ({ data }) => {
  const Card = ({ title }) => (
    <div>
      <h3>{title}</h3>
      {data.items.map(...)}  // BUG: 'data' not passed to Card!
    </div>
  );
  return <Card title="Report" />;
};

// CORRECT
const Card = ({ title, items }) => (
  <div>
    <h3>{title}</h3>
    {items?.map(...)}
  </div>
);
const Parent = ({ data }) => <Card title="Report" items={data?.items} />;
```

**2. Env Validation Check** — Ensure env validation won't kill React before mount:
```bash
# Check validateClientEnv is called WITH fallbacks
grep -A2 "validateClientEnv" src/react-app/App.tsx
# Check for module-level throws (kills React before mount, zero console errors)
grep -n "throw" src/react-app/App.tsx
```
- If `validateClientEnv()` called without fallbacks for vars with hardcoded defaults: **BLOCK**
- If bare `throw` at module scope outside functions: **BLOCK**

---

## Phase 1.35: useEffect ABUSE CHECK

**Purpose**: Prevent unnecessary `useEffect` usage. `useEffect` is ONLY for synchronizing with external systems (browser APIs, third-party widgets, network requests). All other uses are anti-patterns that cause extra render cycles, sync bugs, and stale closures.

**1. Scan for useEffect in changed files:**
```bash
# List all useEffect occurrences in changed files
git diff --name-only HEAD~1 -- '*.tsx' '*.ts' | xargs grep -n "useEffect" 2>/dev/null
```

**2. Flag these anti-patterns (each is a WARN):**

| Anti-Pattern | Detection | Fix |
|-------------|-----------|-----|
| Derived state in useEffect | `useEffect(() => { setX(compute(y)) }, [y])` | Compute during render: `const x = compute(y)` |
| Event logic in useEffect | `useEffect(() => { if (changed) doThing() }, [val])` | Move to event handler |
| Previous value tracking via useRef+useEffect | `useEffect(() => { prevRef.current = val }, [val])` | `[prev, setPrev] = useState(val)` + compare during render |
| Reset state on prop change | `useEffect(() => { setState(null) }, [prop])` | Key the component or compare during render |
| Data fetching in useEffect | `useEffect(() => { fetch(...) }, [])` | TanStack Query / SWR / React 19 `use()` |
| Copying server data to local state | `useEffect(() => setTodos(data), [data])` | Use query result directly as source of truth |

**3. Valid useEffect uses (DO NOT flag):**
- `addEventListener` / `removeEventListener` (external browser API)
- Third-party widget init/destroy (external system)
- `IntersectionObserver` / `ResizeObserver` (external browser API)
- WebSocket connect/disconnect (external network)
- `document.title` update (external browser API)
- `localStorage` read on mount in App.tsx (external storage sync)

**Decision rule:** If any useEffect in changed files does NOT synchronize with an external system, WARN with the file:line and suggested fix. Not a deploy blocker, but must be flagged.
