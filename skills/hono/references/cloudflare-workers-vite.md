# Hono on Cloudflare Workers + Vite (dual server/client build)

Verified against `hono.dev` Workers + Vite guides 2026-06-04. Two supported build paths:
the modern **`@cloudflare/vite-plugin`** (what `sanders-king-heritage` already has installed)
and the classic **`@hono/vite-build` + `@hono/vite-dev-server`**. Prefer the one already in the
repo to minimize churn.

## wrangler.jsonc (Worker + static assets)

```jsonc
{
  "name": "your-site",
  "main": "src/index.tsx",            // the Hono server entry (was absent for the pure-SPA setup)
  "compatibility_date": "2025-04-01",
  "assets": {
    "directory": "./dist/client",     // built client JS/CSS + static files
    "binding": "ASSETS"               // lets the Worker fall through to assets
  }
}
```

- For a **pure SSR site**, the Worker renders every route, and `assets` only holds hashed
  JS/CSS + images/favicons. Drop `not_found_handling: single-page-application` (that's an
  SPA-only concept) unless you intentionally keep a client-routed section.
- The Worker should fetch assets it doesn't own:
  `app.get('/assets/*', (c) => c.env.ASSETS.fetch(c.req.raw))` — or let the platform serve
  `assets` automatically and only define dynamic routes in the Worker.

## Server entry (`src/index.tsx`)

```tsx
import { Hono } from 'hono'
import { secureHeaders } from 'hono/secure-headers'
import { Home } from './pages/Home'
import { About } from './pages/About'

type Bindings = { ASSETS: Fetcher }
const app = new Hono<{ Bindings: Bindings }>()

app.use(secureHeaders())
app.get('/', (c) => c.html(<Home />))
app.get('/about', (c) => c.html(<About />))

export default app
```

## Vite: build BOTH a server bundle and client island bundles

The defining feature of a Hono+islands setup is **two builds**: the server worker (SSR) and the
client entries (islands). Two common shapes:

### A. `@cloudflare/vite-plugin` (modern; already in this repo)

```ts
// vite.config.ts
import { defineConfig } from 'vite'
import { cloudflare } from '@cloudflare/vite-plugin'

export default defineConfig({
  plugins: [cloudflare()],          // reads wrangler.jsonc, builds the Worker + assets
  esbuild: { jsxImportSource: 'hono/jsx' },   // server default
  build: {
    rollupOptions: {
      // client island entries — each becomes a code-split, hashed bundle in dist/client/assets
      input: {
        'island-dna': 'src/client/island-dna.tsx',
        'island-map': 'src/client/island-map.ts',
      },
    },
  },
})
```

Client island files set `hono/jsx/dom` per-file with `/** @jsxImportSource hono/jsx/dom */` so
the server default stays `hono/jsx`. (Mixing import sources in one config is why the pragma
exists.)

### B. Classic `@hono/vite-build` + `@hono/vite-dev-server`

```ts
import build from '@hono/vite-build/cloudflare-workers'
import devServer from '@hono/vite-dev-server'
import { defineConfig } from 'vite'

export default defineConfig(({ mode }) => {
  if (mode === 'client') {
    return {
      esbuild: { jsxImportSource: 'hono/jsx/dom' },
      build: { rollupOptions: { input: './src/client.tsx',
        output: { entryFileNames: 'static/client.js' } } },
    }
  }
  return { plugins: [build({ entry: 'src/index.tsx' }), devServer({ entry: 'src/index.tsx' })] }
})
```

Then `vite build --mode client && vite build` (client first, server second). The client output
lands in the assets dir the Worker serves.

## tsconfig

```jsonc
{
  "compilerOptions": {
    "jsx": "react-jsx",
    "jsxImportSource": "hono/jsx",     // server default; client files override via pragma
    "types": ["@cloudflare/workers-types"],
    "moduleResolution": "Bundler",
    "module": "ESNext",
    "target": "ESNext",
    "strict": true
  }
}
```

## Adding hono/jsx SSR to a repo that ALSO has a React client (verified 2026-06-28)

Common when converting public pages of a React SPA to SSR (e.g. AIVA-Frontend: a
`@vitejs/plugin-react` client in `src/react-app` + a Hono Worker in `src/worker`, built by ONE
`vite.config.ts` with both `react()` and `@cloudflare/vite-plugin`). You must give the Worker
`.tsx` files `jsxImportSource: hono/jsx` WITHOUT touching the React transform. Recipe:

1. **Per-file pragma** `/** @jsxImportSource hono/jsx */` as line 1 of every Worker `.tsx`.
   `@vitejs/plugin-react`'s Babel automatic runtime honors the pragma per-file, so the Worker
   JSX compiles to `hono/jsx/jsx-runtime` while React files (no pragma) stay on
   `react/jsx-runtime`. No global config change → no collision.
2. **Worker-scoped tsconfig** (e.g. `tsconfig.worker.json`, `include: ["src/worker"]` only):
   add `"jsx": "react-jsx"` + `"jsxImportSource": "hono/jsx"` so `tsc` parses+types the Worker
   JSX. Because its `include` is just `src/worker`, the React app's `tsconfig.app.json` keeps
   `jsxImportSource: react`.
3. **Route from a `.ts` entry without JSX syntax:** keep `index.ts` as `.ts` and have each page
   export a `renderX()` returning the JSX node — `app.get("/x", (c) => c.html(renderX()))`. The
   extensionless import resolves `.ts`→`.tsx` automatically; no JSX appears in `index.ts`.

**Prove it didn't leak into React** (the collision check): after `vite build`, grep the built
Worker bundle — it must contain hono's `JSXNode` and **zero** `react/jsx-runtime` /
`React.createElement`; the client bundle must still build its React pages. Verify SSR output
with an esbuild probe:
`esbuild probe.mts --bundle --platform=node --format=esm --jsx=automatic --jsx-import-source=hono/jsx --outfile=probe.mjs && node probe.mjs`
asserting the rendered string has the real `<h1>` and no SPA `id="root"` skeleton.

**Emit per-route JSON-LD for SEO parity:** if the SSR route replaces a crawler pre-render
shadow, the SSR page must carry the schema the shadow had. Add an optional `structuredData`
prop to the layout that emits `<script type="application/ld+json">` (JSON.stringify, then
replace every `<` with its `<` escape so the JSON can't break out of the script), and pass the page's
existing PAGE_METADATA structuredData (single source of truth).

## Dev + deploy

- Dev: `vite dev` (the CF/Hono plugin runs the Worker in a Miniflare-like dev server with HMR).
- Build: `vite build` (+ a client pass if using shape B).
- Deploy: `wrangler deploy`. Verify a clean build first: `rm -rf dist && vite build`.
- **Closed-loop verify:** `curl -s https://<site>/about | grep '<h1'` returns real SSR markup
  (not an empty `<div id="root">`); island `<script>` 200s; `wrangler deployments list` shows
  the new version.

## Static assets, favicons, OG

Put favicons, `site.webmanifest`, OG image, robots/sitemap in the assets dir (or `public/`
that Vite copies). Reference them with absolute paths. The SSR `<head>` carries per-route meta.

## Gotchas

- **No `process.env`** — `c.env` only on Workers.
- **`main` must point at the server entry** — a pure-SPA `wrangler.jsonc` often has no `main`;
  add it when converting to SSR.
- **Island import-source bleed** — if clicks don't work, check the client file actually built
  with `hono/jsx/dom` (pragma or `--mode client` esbuild option), not the server default.
- **CSS:** Tailwind via `@tailwindcss/vite` works; the SSR `<head>` links the built CSS hash.
