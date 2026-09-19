---
name: infinite-faq
description: >-
  Add an "infinite FAQ" to any Hono-on-Cloudflare-Workers site: a normal accordion FAQ whose
  last row is "Ask anything else" — focusing it turns it into an input, submitting streams a
  Workers AI answer grounded in the site's own content inline below the row, with a "Reading
  the docs" shimmer before the first token and a Stop button while streaming. Use when the
  user says "infinite faq", "ask anything else", "AI FAQ", "add an FAQ that answers anything",
  "FAQ with a chat row", "foglamp-style FAQ", or wants an accordion FAQ backed by Workers AI.
  Ships a verified 4-file drop-in (SSR section, client island, streaming route, CSS) plus a
  runnable example Worker and per-site integration steps.
---

# Infinite FAQ — accordion FAQ whose last row answers anything

Remake of foglamp.dev's "Ask Foggy" row (analysis + wire capture + video frames in
`references/`) for the user's stack: **Hono SSR (`hono/jsx`) + a `hono/jsx/dom` island + Workers
AI via the `AI` binding**. No API keys, no Vercel AI SDK, works with JavaScript off.

## What it builds

```
┌ Questions ─────────┐  What is X?                              ⌄   <details>/<summary>
│ The short ones are │  ──────────────────────────────────────────
│ here. For anything │  Can I self-host it?                     ⌄
│ else, ask below.   │  ──────────────────────────────────────────
└────────────────────┘  Ask anything else                       →   ← island mounts here
                        ──────────────────────────────────────────
                        Reading the docs        (shimmer, pre-first-token; Stop ■ while streaming)
                        Yes, you can … https://site/docs/evals   (markdown: bold, links, lists)
```

- SSR section renders real `<details>` rows and a real `<form method="post">` ask row, so the
  page is complete for crawlers/curl and still works with JS off (the route answers a form
  POST with `text/plain`).
- The island replaces the ask row's contents: input (`maxLength 600`, sr-only label,
  autocomplete off), Send disabled when empty, `fetch` + `getReader()` over a same-origin SSE
  stream, shimmer until the first delta, Stop = `AbortController.abort()` keeping the partial
  answer, error copy "Hit a snag. Please try again in a moment."
- The route grounds the model BEFORE the first token (corpus in the system prompt), streams
  Workers AI, and normalises both supported models into one wire so the client never sees a
  model's `reasoning` channel.

## The drop-in (`template/`)

| File | Runs | Copy to |
|---|---|---|
| `faq-section.tsx` | server (`hono/jsx`) | the site's SSR components dir |
| `faq-island.tsx` | browser (`hono/jsx/dom`) | the client-entry dir; bundle to `public/faq-island.js` |
| `faq-route.ts` | server (Hono) | next to the site's routes; `mountInfiniteFaq(app, opts)` |
| `faq.css` | browser | `public/faq.css` or appended to the site stylesheet |

**Never import `faq-island.tsx` from server code** — it imports `hono/jsx/dom`. The example's
`src/faq/index.ts` barrel shows the server-safe exports.

Wire between island and route (independent of model):
```
data: {"type":"text-delta","delta":"..."}   × N
data: {"type":"finish"}
data: [DONE]
data: {"type":"error","message":"..."}       (only on a mid-stream failure)
```

## Integration steps (any Hono site)

1. Copy the four files. Build the island once per deploy:
   `esbuild src/faq/faq-island.tsx --bundle --format=esm --minify --target=es2022 --jsx=automatic --jsx-import-source=hono/jsx/dom --outfile=public/faq-island.js`
   (32 KB min / 13 KB gzip, zero deps beyond hono). Serve `public/` via the `[assets]` binding.
2. `wrangler.toml`: `[ai] binding = "AI"` and `compatibility_flags = ["enable_request_signal"]`
   — without the flag a Stop click never reaches the Worker and the model runs to the end
   (docs: https://developers.cloudflare.com/workers/runtime-apis/request/, read 2026-09-18).
3. Mount the route: `mountInfiniteFaq(app, { siteName, fallbackUrl, corpus })`. Optional:
   `model` (`@cf/meta/llama-3.3-70b-instruct-fp8-fast` default, or `@cf/openai/gpt-oss-120b`),
   `maxTokens`, `path`, `rateLimiter`, `maxCorpusChars`.
4. Render `<FaqSection heading intro items askPlaceholder />` in the page, link `/faq.css`,
   add `<script type="module" src="/faq-island.js">`.
5. Verify with the checklist below. Per-site specifics: `references/integration-guide.md`.

## Corpus / grounding — three sourcing options

1. **Static module** (`faq-corpus.ts`, generated at build from the site's help pages) — fastest,
   versioned with the code. Default for marketing/help sites.
2. **The FAQ items themselves** + a few inlined doc pages (what `example/` does) — zero extra
   infra; fine when the site is small.
3. **KV / D1 text** via `corpus: async () => load()` — for crawled corpora (improvecortland's
   `govsite` table) or content edited outside deploys.

Budget: `maxCorpusChars` (default 24,000 ≈ 6k tokens). ⚠️ The Workers AI binding caps
llama-3.3-70b-instruct-fp8-fast at a **24,000-token** context (error 5021 measured live
2026-09-18; the model's native 128k is not what the binding allows) — corpora past ~90k chars
fail with a 503. Overflow
is logged as `faq.corpus.truncated`, never silent. For corpora beyond that, retrieve top-k
docs per question (FTS5 as in improvecortland) and pass those as the corpus.

## CSP

Works under `default-src 'self'; script-src 'self'; connect-src 'self'` — verified by
`fcdp console` with a positive control (an injected inline script was refused). No inline
handlers, no eval, same-origin fetch. Sites already on strict CSP need **nothing added**.

## Rate limiting and abuse

- Wire the Cloudflare Rate Limiting binding (`[[ratelimits]]`, 16bedlimit uses
  `simple: { limit: 20, period: 60 }`) and pass it as `rateLimiter`; 429 + `retry-after: 60`.
- Without it, a per-isolate bucket (10/min per IP) bounds a single burst only — it cannot see
  other isolates. Say so in the site's notes; do not call it a limit.
- Questions are validated with zod (1..600 chars); the question text is never logged. Logs:
  `faq.ask.start/finish/abort/error` with `qLen`, `model`, `ms`, `deltas`, `chars`, `tokens`.

## Model notes (measured 2026-09-18, `references/verification-2026-09-18.md`)

- 🛑 **All-digit chunks arrive with `response` as a JSON NUMBER** —
  `{"choices":[{"delta":{"content":"7 \n"}}],"response":7}` (measured 2026-09-18, 2/2). A
  `z.string()` schema drops the whole frame and years/prices/ids lose digits. The template's
  `ChunkSchema.response` is `z.union([z.string(), z.number()])`, `pieceOf()` prefers
  `choices[0].delta.content`, and refused frames are counted (`stats.rejected`) — keep all three
  in every port, with the "keeps a chunk whose text is all digits" test.

- **llama-3.3-70b-instruct-fp8-fast (default)**: first token ≈ 1 s, whole answer 1.4 s; chunk
  carries the text in both `response` and `choices[0].delta.content`.
- **gpt-oss-120b**: reasoning model — 105 `delta.reasoning` frames before 7 content frames for a
  five-word reply; needs `max_tokens ≥ 2048` or the answer comes back empty with no error
  (improvecortland/src/chat.ts). Grounded answer took 4.9 s. The route never forwards reasoning.
- The route reads `response || delta.content` (`||`, not `??`: llama sends `response:""` beside
  real content on early frames — 16bedlimit).

## Verification checklist (all done for `example/`, repeat per site)

- [ ] `tsc --noEmit` clean **and armed** (a deliberate type error produces 1 diagnostic)
- [ ] `biome check` clean and armed; `detect-ts-slop.sh` 0 findings; oxlint 0 (pass files
      explicitly — it silently skips directory walks under a hidden ancestor like `~/.claude`)
- [ ] `curl -s localhost:8787/ | grep -o '<details' | wc -l` = item count; `Ask anything else`
      and `method="post" action="/api/faq/ask"` present; CSP header present
- [ ] `curl -sN -X POST /api/faq/ask -d '{"question":"…"}'` → `text/event-stream`, N deltas,
      `finish`, `[DONE]`
- [ ] Negatives: `""` → 400, 601+ chars → 400, 600 chars → 200, off-corpus question → "does not
      cover … your fallbackUrl" with no invented facts, form POST → `text/plain`
- [ ] Abort: `SIGTERM` a mid-stream curl (not `SIGINT` — background jobs ignore it) → worker
      still 200, `faq.ask.abort` logged (requires `enable_request_signal`)
- [ ] Browser (`~/tools/fcdp/fcdp`): island mounted, shimmer text + Stop visible after submit,
      answer renders with real `<a>`, Stop keeps partial text, `fcdp console --secs 5` shows
      0 CSP violations AND the inline-script positive control shows 1

## References

- `references/foglamp-analysis.md` — the reference implementation, wire, and UI frames
- `references/verification-2026-09-18.md` — every command and output from the live verification
- `references/example-rendered.png` — the example rendered in real Chrome
- Upstream docs read 2026-09-18: Workers AI model pages (llama-3.3-70b-instruct-fp8-fast,
  gpt-oss-120b), `hono.dev/docs/helpers/streaming`, `hono.dev/docs/guides/jsx-dom`,
  `developers.cloudflare.com/workers/runtime-apis/request/`
