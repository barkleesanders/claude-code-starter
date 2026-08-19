---
name: hono
description: >-
  Build, structure, and ship web apps/sites with the Hono framework — the
  the user default for new sites and for converting React SPAs to SSR. Use when
  the user wants to create a Hono app, convert/remake a site in Hono, add SSR +
  islands on Cloudflare Workers, set up Hono routing/middleware/JSX, choose
  between hono/jsx (server) and hono/jsx/dom (client), wire the Vite build, or
  asks "is this Hono", "make it Hono", "Hono SSR", "Hono on Workers", "@hono/jsx",
  "islands", "hono framework". Loads current, verified Hono API patterns so you
  leverage the framework fully instead of guessing from memory.
---

# Hono Framework — Full-Leverage Skill

Hono is a small, ultrafast web framework built on **Web Standards** (Request/Response,
`fetch`). It runs on Cloudflare Workers, Deno, Bun, Node, and the edge. For the user's
stack it is the **default for new sites** and the **target for React-SPA → SSR conversions**
(global rule: "Default to Hono SSR for new sites", 2026-05-15).

> **Ground-truth note:** every API in this skill was verified against `hono.dev` docs via
> Context7 (`/websites/hono_dev`) on 2026-06-04. Before asserting a Hono API that is NOT in
> these references, re-verify against `hono.dev` — do not invent middleware names, import
> paths, or hook names from memory. Hono's API surface is small; if you can't find it in the
> references or live docs, it probably doesn't exist under that name.

## When to use this skill

- Creating a new website or web app on Cloudflare Workers (or any edge runtime)
- Converting/remaking an existing React/Vue/SPA site into Hono SSR + islands
- Adding server-rendered HTML, routing, middleware, or an API to an existing Hono worker
- Deciding `hono/jsx` (server SSR) vs `hono/jsx/dom` (client hydration/islands)
- Wiring the Vite build for a Hono Worker with interactive client islands
- Any "make it Hono / is this Hono / Hono SSR / Hono on Workers" request

## The 90-second mental model

1. **One `app = new Hono()`.** Routes are `app.get/post/...('/path', handler)`. The handler
   gets a single **Context** `c` and returns a `Response` (via `c.text`, `c.json`, `c.html`,
   `c.redirect`, or a raw `Response`).
2. **Server JSX is just a function that returns HTML.** `import { ... } from 'hono/jsx'`,
   write components, `return c.html(<Page/>)`. No virtual DOM on the server — it renders to a
   string. This is your SSR.
3. **Interactivity = islands.** A small client bundle built with `hono/jsx/dom` mounts into a
   placeholder via `render(<Widget/>, el)`. `useState`/`useEffect` from `hono/jsx` work there.
   A counter island is **2.8 KB brotli vs 47.8 KB for React** — that's the whole point.
4. **`c.env` is your bindings**, typed via `new Hono<{ Bindings }>()`. No `process.env` on
   Workers.
5. **Static assets** are served by the platform (`assets` in `wrangler.jsonc`), not by route
   handlers. The Worker handles dynamic routes; the SPA/asset fallback handles the rest.

## Core decision: server vs client JSX (do not mix import sources)

| | Server (SSR) | Client (island) |
|---|---|---|
| Import | `hono/jsx` | `hono/jsx/dom` |
| Renders to | HTML string (`c.html`) | live DOM (`render(node, el)`) |
| `jsxImportSource` | `hono/jsx` (default) | `hono/jsx/dom` (set per client build) |
| Hooks | for structure only | `useState`, `useEffect`, `useRef`, etc. are live |
| Ship size | 0 KB to the browser | tiny (counter ≈ 2.8 KB brotli) |

The classic mistake is rendering an interactive component with `hono/jsx` and expecting clicks
to work — server JSX has no event loop in the browser. Interactive = build it into the **client
entry** with `hono/jsx/dom` and mount it.

## Workflow for any Hono task

1. **Identify the runtime + build.** Cloudflare Workers? Then `wrangler.jsonc` `main` =
   server entry, `assets` for static, and a Vite config that emits BOTH a server bundle and a
   client island bundle. See `references/cloudflare-workers-vite.md`.
2. **Lay out routes + SSR pages** with `hono/jsx`. Shared `<Layout>` via the `html` helper or
   the `jsxRenderer` middleware. See `references/ssr-jsx.md`.
3. **Carve out islands** — only the genuinely interactive pieces (maps, charts, modals,
   toggles). Each island = a client entry that `render()`s into an SSR'd `<div id="...">`.
   See `references/client-islands.md`.
4. **Add middleware** (logger, CORS, cache, secureHeaders, etc.) with `app.use()`. See
   `references/core-routing-middleware.md`.
5. **Verify**: `c.html` returns 200 with real markup (curl it), island bundle loads and
   hydrates (check the DOM updates), no `hono/jsx` import in client code and no
   `hono/jsx/dom` in server code.

## Converting a React SPA → Hono (the big one)

Read `references/react-spa-to-hono-migration.md`. The short version:

- **Pages → SSR JSX.** Each React Router route becomes a Hono route returning `c.html(<Page/>)`.
  Static content (text, layout, data-driven markup) renders on the server — instant, SEO-friendly,
  great Lighthouse.
- **Interactive components → islands.** `react-leaflet` map, `d3` force graph, modals, anything
  with `useState`/event handlers → a `hono/jsx/dom` island OR keep the underlying lib
  (Leaflet/D3 are framework-agnostic) and mount it from a client entry. D3 and Leaflet don't
  need React at all.
- **Icons:** `lucide-react` is React-specific. On the server use inline SVG (or `lucide`'s
  framework-agnostic SVG strings); don't import `lucide-react` into `hono/jsx`.
- **Router:** delete `react-router`; routing is server-side in Hono. Client nav can be plain
  `<a href>` (full SSR navigation) or a tiny island if you want SPA-like transitions.
- **Data modules** (plain `.ts` exports) port over unchanged — import them into server pages.
- **Don't big-bang it blindly.** Keep the build green at every step; convert page-by-page and
  curl each route. A working SSR page with a missing island beats a broken全-rewrite.

## Hard rules

- **Never mix `hono/jsx` and `hono/jsx/dom` in the same module.** Pick by where the code runs.
- **No `process.env` on Workers** — use `c.env` (typed `Bindings`) or `env(c)` from `hono/adapter`.
- **Don't hand-serve static files from route handlers** when the platform has an `assets` binding.
- **Verify against live docs before using an unfamiliar Hono API** — the framework is small and
  memory-invented middleware/hooks are the #1 failure mode.
- **Client islands must be code-split** so SSR pages ship 0 JS except the island that page needs.

## Reference files

| File | Use when |
|---|---|
| `references/core-routing-middleware.md` | Routing, Context (`c`), middleware, bindings, error handling |
| `references/ssr-jsx.md` | Server JSX, `c.html`, `html` helper, `jsxRenderer`, layouts, streaming |
| `references/client-islands.md` | `hono/jsx/dom`, `render()`, hooks, hydration, mounting D3/Leaflet |
| `references/cloudflare-workers-vite.md` | `wrangler.jsonc`, dual client/server Vite build, assets, deploy |
| `references/react-spa-to-hono-migration.md` | Step-by-step React-SPA → Hono conversion playbook |

All import paths and patterns in these files were verified against `hono.dev` on 2026-06-04.
