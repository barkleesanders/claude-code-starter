# Hono — Server-Side JSX / SSR

Verified against `hono.dev` (jsx, jsx-renderer, html guides) 2026-06-04.

## Server JSX renders to an HTML string

```tsx
/** @jsxImportSource hono/jsx */
import { Hono } from 'hono'

const app = new Hono()

const Page = (props: { name: string }) => (
  <html lang="en">
    <head><title>Hello</title></head>
    <body><h1>Hello {props.name}</h1></body>
  </html>
)

app.get('/:name', (c) => c.html(<Page name={c.req.param('name')} />))
```

- Default `jsxImportSource` for the **server** is `hono/jsx`. Set it in `tsconfig.json`
  (`"jsx": "react-jsx", "jsxImportSource": "hono/jsx"`) or per-file with the pragma comment.

> **GOTCHA (verified 2026-06-28, AIVA-Frontend): never write the literal `@jsxImportSource`
> token inside a prose/JSDoc comment in a `.tsx` file.** TypeScript's pragma scanner reads
> `@jsxImportSource` from ANY leading comment, not just a dedicated pragma line. A doc comment
> describing the pragma (e.g. with the token wrapped in backticks for markdown) gets parsed as
> a *real* pragma and captures the trailing char into the value → it tries to resolve
> `` hono/jsx`/jsx-runtime`` → TS2875 "module not found" → TS silently falls back to the global
> (React) JSX namespace, producing a flood of misleading `class`→`className` /
> `for`→`htmlFor` / `charset`→`charSet` errors. Fix: keep ONE clean pragma as line 1
> (`/** @jsxImportSource hono/jsx */`) and never repeat the `@jsx…` token in prose (write "jsx
> import-source pragma" without the `@`). Diagnose with
> `tsc --traceResolution | grep jsx-runtime` — a stray char in the resolved module name means a
> comment is poisoning the pragma.
- `FC<P>` in hono/jsx does **not** auto-add `children` to `P` (unlike React's FC). If a layout
  component takes children, declare `children?: Child` (import `Child` from `hono/jsx`) on the
  props interface explicitly, or you get "Property 'children' does not exist".
- `c.html(jsx)` serializes the tree to HTML and sends it with `Content-Type: text/html`.
- There is **no client runtime** for server JSX — `onClick` etc. do nothing in the browser.
  Interactivity comes from islands (`client-islands.md`).

## Layout via the `html` helper (template literals)

`hono/html` gives you a tagged-template `html` that auto-escapes interpolations and lets you
build a document shell that wraps JSX children:

```tsx
import { html } from 'hono/html'

interface SiteData { title: string; children?: any }

const Layout = (props: SiteData) =>
  html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${props.title}</title>
        <link rel="stylesheet" href="/assets/styles.css" />
      </head>
      <body>
        ${props.children}
      </body>
    </html>`

const Home = () => (
  <Layout title="Heritage">
    <main><h1>Sanders–King Heritage</h1></main>
  </Layout>
)

app.get('/', (c) => c.html(<Home />))
```

Use `html` for the `<!doctype>` shell (JSX can't emit a raw doctype cleanly) and JSX for the
body. `raw()` from `hono/html` injects pre-trusted HTML without escaping (only for content you
control — never user input).

## `jsxRenderer` middleware (shared layout without repeating it)

```tsx
import { jsxRenderer } from 'hono/jsx-renderer'

app.use(
  '*',
  jsxRenderer(({ children }) => (
    <html lang="en">
      <head><title>Heritage</title><link rel="stylesheet" href="/assets/styles.css" /></head>
      <body>{children}</body>
    </html>
  ))
)

app.get('/', (c) => c.render(<h1>Home</h1>))        // wrapped in the layout above
app.get('/about', (c) => c.render(<AboutPage />))
```

`c.render(node)` wraps `node` in the registered layout and returns the HTML response. Set
per-route head data with `c.setRenderer(...)` or by passing props through context.

## Components, props, fragments, loops

```tsx
import type { FC } from 'hono/jsx'

const Card: FC<{ title: string }> = ({ title, children }) => (
  <section class="card"><h2>{title}</h2>{children}</section>
)

const List = ({ items }: { items: string[] }) => (
  <ul>{items.map((x) => <li>{x}</li>)}</ul>
)
```

- Use `class=` (Hono accepts `class`; `className` also works). `for=` works on labels.
- Conditionals: `{cond ? <A/> : <B/>}` / `{cond && <A/>}`.
- Fragments: `<>{...}</>` or `import { Fragment } from 'hono/jsx'`.
- `dangerouslySetInnerHTML={{ __html }}` exists; prefer `raw()` for trusted HTML and never
  pass unescaped user input.

## Streaming + async components (advanced)

`hono/jsx` supports `Suspense` + `renderToReadableStream` for streamed SSR, and async
components. For a static heritage/marketing site you usually don't need streaming — plain
`c.html` is simplest and fastest. Reach for streaming only when a page must await slow data
and you want to flush the shell first.

## SEO / meta (why SSR here matters)

Because the markup is real on first byte, put `<title>`, `<meta name="description">`,
canonical, and OG/Twitter tags directly in the SSR `<head>` per route. This is the main win
over a React SPA where crawlers/og-scrapers got an empty shell. Generate a 1200×630 OG image
and reference an absolute URL.
