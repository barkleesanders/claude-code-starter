# Hono — Client Components / Islands (`hono/jsx/dom`)

Verified against `hono.dev/docs/guides/jsx-dom` 2026-06-04.

Islands = small interactive widgets that run in the browser, mounted into SSR'd placeholders.
Hono's client runtime (`hono/jsx/dom`) is React-compatible in shape but tiny — a counter is
**2.8 KB brotli vs 47.8 KB for React**.

## A client island

```tsx
/** @jsxImportSource hono/jsx/dom */
import { useState } from 'hono/jsx'
import { render } from 'hono/jsx/dom'

function Counter({ start = 0 }: { start?: number }) {
  const [count, setCount] = useState(start)
  return (
    <div>
      <p>Count: {count}</p>
      <button onClick={() => setCount(count + 1)}>+1</button>
    </div>
  )
}

// mount into the SSR placeholder <div id="counter" data-start="3">
const el = document.getElementById('counter')
if (el) render(<Counter start={Number(el.dataset.start ?? 0)} />, el)
```

- **Hooks are live here:** `useState`, `useEffect`, `useRef`, `useReducer`, `useCallback`,
  `useMemo`, `useContext` — imported from `hono/jsx` but only interactive in the DOM runtime.
- `render(node, el)` is the mount call (analogous to React's `createRoot().render`).
- The client build MUST set `jsxImportSource: 'hono/jsx/dom'` (Vite `esbuild.jsxImportSource`
  or a `/** @jsxImportSource hono/jsx/dom */` pragma at the top of every client file).

## The island contract (SSR ↔ client)

1. **Server** renders a placeholder with the initial data in `data-*` (or a JSON `<script>`):
   ```tsx
   <div id="dna-graph" data-matches={JSON.stringify(matches)} />
   ```
   (Escape `</` in embedded JSON to avoid `</script>` breakout if you use a script tag.)
2. **Client entry** finds each placeholder and mounts:
   ```ts
   const el = document.getElementById('dna-graph')
   if (el) render(<DnaGraph matches={JSON.parse(el.dataset.matches!)} />, el)
   ```
3. **Build** emits the client entry as a separate, code-split bundle and the SSR page loads it
   with `<script type="module" src="/assets/island-dna.js" defer>`.

## Mounting framework-agnostic libs (D3, Leaflet) — no React needed

D3 and Leaflet manipulate the DOM directly; you don't need a UI framework for them. Use a
client entry (plain TS or a `hono/jsx/dom` `useEffect`) to initialize them into an SSR'd box:

```ts
// island-map.ts  (client build)
import L from 'leaflet'
const el = document.getElementById('map')!
const data = JSON.parse(el.dataset.journey!)
const map = L.map(el).setView([data.lat, data.lng], data.zoom)
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map)
data.points.forEach((p) => L.marker([p.lat, p.lng]).addTo(map).bindPopup(p.label))
```

```ts
// island-dna.ts (client build) — D3 force graph
import * as d3 from 'd3'
const el = document.getElementById('dna-graph')!
const { nodes, links } = JSON.parse(el.dataset.matches!)
// ...standard d3.forceSimulation into an <svg> appended to el...
```

This is the cleanest React-SPA migration path for `react-leaflet`/`d3` components: drop the
React wrapper, keep the library, mount from a client entry. The server renders an empty sized
container so layout doesn't shift (set explicit width/height to avoid CLS).

## hydration vs fresh render

`render()` does a client-side render into the container. For a heritage site, the simplest
robust pattern is: **SSR the static skeleton, and let the island fully own its interactive
subtree** (the container is empty on the server, the island fills it). True hydration (reusing
SSR'd DOM) is more fragile to mismatches — only pursue it if you need the interactive markup
visible before JS loads.

## Sizing & a11y

- Give every island container an explicit min-height so SSR layout doesn't jump when JS mounts.
- Provide a `<noscript>` fallback (static image/table) for charts/maps where it matters.
- Don't block first paint: load island scripts with `defer`/`type="module"`.

## Don't

- ❌ `import { render } from 'hono/jsx/dom'` in a **server** file — it references `document`.
- ❌ `c.html(<Counter/>)` and expect clicks to work — server JSX is inert in the browser.
- ❌ One giant client bundle for the whole site — code-split per island so each page ships only
  the JS it needs.
