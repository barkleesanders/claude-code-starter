# Hono — Routing, Context, Middleware, Bindings

Verified against `hono.dev` (Context7 `/websites/hono_dev`) 2026-06-04.

## The app + routing

```ts
import { Hono } from 'hono'

const app = new Hono()

app.get('/', (c) => c.text('Hono!'))
app.get('/posts/:id', (c) => c.json({ id: c.req.param('id') }))
app.post('/posts', async (c) => {
  const body = await c.req.json()
  return c.json(body, 201)
})

export default app // Workers/Bun/Deno pick this up as the fetch handler
```

- Methods: `app.get/post/put/delete/patch/options`, `app.all(...)`, `app.on(method, path, h)`.
- Path params: `/:id`, optional `/:id?`, wildcard `/*`, regex `/:id{[0-9]+}`.
- Chainable: `app.get(...).post(...)` — chaining preserves type inference (matters for RPC).
- Group/mount: `app.route('/api', apiApp)` mounts a sub-app under a prefix.
- 404 / error: `app.notFound((c) => c.text('nope', 404))`,
  `app.onError((err, c) => c.text('boom', 500))`.

### Routers (perf)
Hono auto-selects a router. `RegExpRouter` is fastest (single regex), `SmartRouter` supports
every pattern, `LinearRouter` has the quickest cold start (good for Workers),
`PatternRouter` is the smallest. You rarely set this manually; `import { Hono } from 'hono'`
uses SmartRouter. For Workers cold-start sensitivity you can
`import { Hono } from 'hono/tiny'` (LinearRouter).

## The Context object `c`

Everything flows through `c`:

- **Request:** `c.req.param('id')`, `c.req.query('q')`, `c.req.header('x')`,
  `await c.req.json()/.text()/.formData()/.arrayBuffer()`, `c.req.valid('json')` (with a
  validator), `c.req.path`, `c.req.method`, `c.req.url`.
- **Response helpers:** `c.text(str, status?, headers?)`, `c.json(obj, status?)`,
  `c.html(stringOrJSX)`, `c.redirect(url, status?)`, `c.notFound()`, `c.body(data, ...)`.
- **Headers/status:** `c.header('Cache-Control', '...')`, `c.status(201)`.
- **Per-request state:** `c.set('user', u)` / `c.get('user')` (type via `Variables` generic).
- **Bindings/env:** `c.env.MY_KV` (type via `Bindings` generic).
- **Raw:** `c.req.raw` (the underlying `Request`), `c.executionCtx` (Workers `waitUntil`).

## Middleware

Middleware is `async (c, next) => { ...; await next(); ... }`. Register with `app.use`:

```ts
import { logger } from 'hono/logger'
import { cors } from 'hono/cors'
import { secureHeaders } from 'hono/secure-headers'
import { etag } from 'hono/etag'

app.use(logger())
app.use('/api/*', cors())
app.use(secureHeaders())
app.use('/static/*', etag())
```

> ⚠️ **`secureHeaders()` defaults to `Referrer-Policy: no-referrer`** (see
> `node_modules/hono/dist/middleware/secure-headers/secure-headers.js`:
> `referrerPolicy: ["Referrer-Policy", "no-referrer"]`, on by default). That
> silently breaks **every third-party embed that verifies its host via the
> `Referer` header** — YouTube renders `Error 153: Video player configuration
> error`, and Vimeo / Spotify / SoundCloud / Brightcove behave similarly. The
> video is fine and `frame-src` is fine; the embed just never gets configured.
>
> Fix it **per iframe**, not by weakening the global header (that would leak
> referrers on every outbound link to solve one embed):
>
> ```jsx
> <iframe src="https://www.youtube.com/embed/<ID>"
>         referrerpolicy="strict-origin-when-cross-origin" allowfullscreen />
> ```
>
> Verify on the **rendered** HTML (`curl … | grep '<iframe'`), not the source —
> then in a real browser. Full pattern + probes:
> `~/.claude/skills/debug/references/csp-cache-patterns.md` #27.

Order matters: middleware runs top-down to `next()`, then unwinds bottom-up. Put `logger`,
`secureHeaders`, `cors` early.

### Built-in middleware you'll actually use
`logger`, `cors`, `secureHeaders`, `etag`, `cache` (`hono/cache`), `compress`,
`basicAuth`/`bearerAuth`/`jwt`, `bodyLimit`, `timing`, `requestId`, `trimTrailingSlash`,
`jsxRenderer` (`hono/jsx-renderer`), `serveStatic` (runtime-specific adapter).

> If you "remember" a middleware name not in this list, verify it on `hono.dev/docs/middleware`
> before using it. Don't invent `app.use(authGuard())`-style names.

## Bindings & env (Cloudflare Workers)

```ts
type Bindings = {
  DB: D1Database
  KV: KVNamespace
  ASSETS: Fetcher
  SECRET_TOKEN: string
}
type Variables = { user: { id: string } }

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>()

app.get('/me', (c) => {
  const token = c.env.SECRET_TOKEN     // typed string
  const user = c.get('user')           // typed via Variables
  return c.json({ user })
})
```

Runtime-agnostic env: `import { env } from 'hono/adapter'; const { NAME } = env<{NAME:string}>(c)`.

## Validation (optional but idiomatic)

```ts
import { validator } from 'hono/validator'
// or the typed adapters: @hono/zod-validator, @hono/valibot-validator
app.post('/x', validator('json', (value, c) => {
  if (!value.name) return c.text('name required', 400)
  return value
}), (c) => c.json(c.req.valid('json')))
```

## Module-worker export shapes (Workers)

```ts
export default app                              // simplest
// or, to add scheduled/queue handlers:
export default {
  fetch: app.fetch,
  scheduled: async (event, env, ctx) => { /* cron */ },
}
```
