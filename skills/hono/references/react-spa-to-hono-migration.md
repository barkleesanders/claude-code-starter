# React SPA → Hono SSR Migration Playbook

A page-by-page, keep-the-build-green conversion. Verified Hono APIs (2026-06-04). The north-star
ground truth: **every page and every interactive feature that worked in the SPA still works after
conversion** — SSR is the win, lost functionality is a regression.

## 0. Inventory first (don't rewrite blind)

For the target repo, enumerate:
- **Routes/pages** (React Router `<Route>`s) → each becomes a Hono `app.get` returning `c.html`.
- **Interactive components** (anything with `useState`/effects/event handlers, maps, charts,
  modals) → islands. List them explicitly; these are the only things that need client JS.
- **Pure data modules** (`.ts` exporting arrays/objects) → import unchanged into server pages.
- **Icon usage** (`lucide-react` etc.) → must become server-safe (inline SVG).
- **Styling** (Tailwind/CSS) → keep; SSR `<head>` links the built CSS.
- **Build/deploy** (`wrangler.jsonc`, `vite.config.ts`) → add a `main` server entry + island build.

Map each item to "SSR static", "island", or "delete" BEFORE writing code.

## 1. Decide the architecture

- **SSR-first + islands** (recommended): server renders all markup; only listed interactive
  widgets ship JS. Best Lighthouse/SEO, smallest payload.
- Keep `@cloudflare/vite-plugin` if the repo already has it; add a `main` entry and island
  rollup inputs (see `cloudflare-workers-vite.md`).

## 2. Scaffold the server shell

1. Add `src/index.tsx` (`new Hono()`), a shared `<Layout>` (via `html` helper or `jsxRenderer`),
   and `secureHeaders()`.
2. Point `wrangler.jsonc` `main` at it; keep `assets` for hashed JS/CSS + favicons/OG.
3. Set `tsconfig` server default `jsxImportSource: hono/jsx`.
4. Build + `curl /` to confirm SSR markup before porting any page.

## 3. Convert pages one at a time (green at each step)

For each React page component `PageX.tsx`:
1. Copy the **static/markup** parts into a `hono/jsx` server component. Replace `className`→`class`
   (optional), remove React imports, keep the data-module imports.
2. Replace `react-router` `<Link to>` with `<a href>`.
3. Replace `lucide-react` icons with inline SVG (or a server-safe icon helper).
4. Add the route `app.get('/x', (c) => c.html(<PageX/>))`.
5. **Curl it.** `curl -s localhost:.../x | grep '<h1'` → real content. Move on only when green.

## 4. Convert interactive components to islands

For each interactive component:
- **Pure UI state** (modal open, tabs, toggles): rewrite as a `hono/jsx/dom` island with
  `useState`. Server renders a placeholder `<div id="modal-root">`; client mounts the island.
- **D3 chart / force graph** (`DNAMatchNetwork`, `Karyogram`, `ChromosomePainting`): drop the
  React wrapper, keep `d3`. Server renders a sized `<div data-…>` placeholder; a client entry
  reads `data-*`/JSON and runs the D3 code into it. D3 never needed React.
- **Leaflet map** (`react-leaflet` `MigrationMap`): drop `react-leaflet`, keep `leaflet`. Client
  entry `L.map(el)…` from the placeholder. Set explicit container height (avoid CLS).
- Pass initial data SSR→client via `data-*` attrs or a `<script type="application/json">` block
  (escape `</`).
- Add each island as a rollup `input`; load it on the relevant page via
  `<script type="module" src="/assets/island-x.js" defer>`.

## 5. Strip SPA-only machinery

- Remove `react-router`, `react-dom` (unless an island needs React — prefer `hono/jsx/dom`),
  and the SPA bootstrap (`createRoot(...).render(<App/>)`).
- Remove `not_found_handling: single-page-application` from `wrangler.jsonc` for a fully-SSR site
  (keep only if a sub-section stays client-routed).
- `lucide-react` → removable once icons are inline SVG. `hono` becomes a *real* dependency.

## 6. Per-page SEO (the payoff)

Put `<title>`, `<meta name=description>`, canonical, OG/Twitter, JSON-LD directly in each
route's SSR `<head>`. This is the concrete reason to convert — crawlers and social scrapers now
get real markup on first byte instead of an empty SPA shell.

### Why this matters more than "add SSR" — the crawler-shadow trap (measured, example.com 2026-06-28)

A SPA often already has a **crawler-only SEO shadow**: a worker branch that UA-sniffs
(`isCrawler(ua)`) and serves hand-written `<head>` meta to Googlebot, while humans get the empty
`<div id="root">`. Teams assume this "covers SEO." It does not, and replacing it with real SSR is
strictly better for four separate reasons — verified by converting 6 AIVA public pages from
SPA+shadow → `hono/jsx` SSR and measuring the live result:

| Dimension | SPA + crawler shadow (before) | Hono SSR (after) | Why it's an SEO win |
|---|---|---|---|
| **Body content in static HTML** | shadow `<body>` was a **stub: 1 `<h1>` + 1 `<p>`** (meta only) | **/faq 2,448 words, /services 870, /terms 867** | Google indexed a near-empty page; now it indexes the full text. The shadow gave snippets, not substance. |
| **Who gets real content** | only UAs in the allowlist; everyone else (humans, **AI bots not listed**) got the empty shell | **every UA — 200 + full content** (verified: OAI-SearchBot, GPTBot, PerplexityBot, Googlebot, browser) | AI source-selection (ChatGPT Search, Perplexity) can't execute JS; an unlisted UA saw nothing. Now they cite real bytes. |
| **Source of truth** | **two** (React page *and* the shadow template) → silent drift = an SEO *regression* waiting to happen | **one** (the SSR component) | Drift between shadow and real page is invisible until rankings drop. SSR eliminates the class. |
| **Human first paint / CWV** | content only after JS download+execute | content in first byte | Better LCP; Core Web Vitals is a ranking signal. |

**Honest framing (don't overclaim).** If the shadow already supplied title/description/OG and
Google was rendering JS, this is **not** "unindexed → indexed" and SERP snippets/social cards were
likely already fine. The defensible wins are the four above: full body in static HTML, all-UA
coverage (esp. AI crawlers), single source of truth, faster paint. State it that way.

**The AI-crawler gate is the highest-leverage check** — run `/seo-audit`'s
`scripts/ai-crawl-reachability.sh <domain> /<deep-route>` (or the per-UA `curl` matrix). Two layers:
(1) edge reachability (a CF `ai_bots_protection: block` returns 403 to AI bots regardless of
`robots.txt`), and (2) **prerender parity** — an AI UA can get 200 yet still be served the
route-blind shell (homepage `<title>`/canonical on every route). Real SSR fixes both at once
because there is no UA branch — everyone gets the same per-route HTML.

**Leave interactive/auth pages on the SPA.** Converting a page with a Clerk funnel or a live tool
(`/`, `/benefits-finder` at AIVA) to *static* SSR breaks it; those need the islands pattern, not a
static port — and the highest-traffic landing page staying SPA is the biggest *remaining* SEO lever,
so call it out rather than pretend the migration is complete.

## 7. Verify (closed-loop, per the no-lie gate)

- `rm -rf dist && vite build` exit 0; `tsc --noEmit` exit 0.
- For EACH route: `curl -s https://<site>/<route>?cb=$(date +%s) | grep` proves the page's real
  content is in the HTML (not an empty root div).
- For EACH island: the script 200s and the widget updates in a real browser (drive the real profile via fcdp
  Chrome / chrome-devtools MCP; confirm the map renders, the graph draws, the modal opens).
- Grep the live DOM for `undefined`/`NaN`/`[object Object]` (render-safety).
- Lighthouse before/after — SSR should jump performance + SEO.

## 8. Common conversion bugs

| Symptom | Cause | Fix |
|---|---|---|
| Island clicks dead | client file built with `hono/jsx` (server) | pragma `/** @jsxImportSource hono/jsx/dom */` or `--mode client` |
| Empty page, only shell | route returns layout but not page body / island never mounts | SSR the content; only carve interactivity into islands |
| `document is not defined` at build/SSR | `hono/jsx/dom` or browser API imported into server bundle | keep DOM code in client entries only |
| Map/chart 0-height or CLS jump | placeholder has no dimensions | set explicit width/height on the SSR container |
| Icons missing | `lucide-react` imported into server JSX | inline SVG / server-safe icons |
| `process.env.X` undefined | Workers has no process.env | `c.env.X` (typed `Bindings`) |

## 9. Do-not

- ❌ Big-bang delete the React app then rebuild — convert incrementally, keep the build green.
- ❌ Re-implement D3/Leaflet logic from scratch — reuse it, just change how it's mounted.
- ❌ Ship a page as "converted" without curling its live SSR markup.
