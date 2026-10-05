# Verification — 2026-09-18 (example Worker, live Workers AI via `wrangler dev --remote`)

Machine: laptop, node v26.8.2, wrangler 4.134.0, hono 4.13.8, zod 4.6.x, biome 2.5.14,
oxlint 1.80.0, esbuild 0.25. Account: you@example.com's (Workers AI billed there).
Every command below was run; outputs are pasted, not paraphrased. Captured streams live in
this directory (`example-stream-*.sse`, `workers-ai-raw-*.sse`).

## 0. Premise check against live upstream docs

| Claim | Source (fetched 2026-09-18) | Result |
|---|---|---|
| `env.AI.run(model, {messages, stream:true})` returns a stream you pass straight to `new Response(stream, {headers:{"content-type":"text/event-stream"}})` | https://developers.cloudflare.com/workers-ai/models/llama-3.3-70b-instruct-fp8-fast/ and https://developers.cloudflare.com/workers-ai/models/gpt-oss-120b/ (Usage tab, TypeScript) | confirmed; `max_tokens` default **256** on both |
| Per-chunk JSON shape | not documented on either page → **measured** (§5) | llama: `response` + `choices[0].delta.content`; gpt-oss: `delta.reasoning` then `delta.content` |
| `hono/jsx/dom` exports `render`; hooks `useState/useEffect/useRef` from `hono/jsx` | https://hono.dev/docs/guides/jsx-dom | confirmed (list of React-compatible hooks) |
| `hono/streaming` exports `stream`, `streamText`, `streamSSE`; `streamSSE(c, cb, onError)`, `stream.writeSSE({data,event,id})`, `stream.onAbort`, `stream.aborted` | https://hono.dev/docs/helpers/streaming | confirmed; note "streaming may not work well on Wrangler — add `Content-Encoding: Identity`" (not needed here, measured) |
| Client disconnect reaches the Worker as `request.signal` | https://developers.cloudflare.com/workers/runtime-apis/request/ → compat flag `enable_request_signal` (https://developers.cloudflare.com/workers/configuration/compatibility-flags/, no default-on date) | opt-in flag required; added to the example |

The former `/workers-ai/features/streaming/` page returns a real **404**; the sitemap
(`sitemap-0.xml`, 1.2 MB) has no streaming page — the streaming docs now live on model pages.
Context7 was unavailable (`Invalid API key`), so WebFetch/curl of the docs' own markdown was used.

## 1. Static gates (all armed with positive controls)

```
$ cd ~/.claude/skills/infinite-faq/example && npm install --no-audit --no-fund   # ok
$ npx tsc --noEmit ; echo rc=$?                                                  # rc=0
$ echo 'const x: number = "no";' > src/__tsc_control.ts; npx tsc --noEmit | grep -c 'error TS'   # 1  (armed)
$ biome check --config-path=$HOME/.config/biome template example/src example/public/site.css example/package.json example/tsconfig.json
Checked 12 files in 5ms. No fixes applied.      rc=0   (7 format/organizeImports findings were fixed with --write first; 0 lint/ findings)
$ biome check … bad.ts | grep -c 'lint/'          # 4  (armed: any, ==, unused let)
$ bash ~/.claude/skills/code/tools/detect-ts-slop.sh template example/src
── anti-slop TypeScript scan (2 target(s)) ──
✅ no TypeScript slop patterns found.
$ oxlint -c ~/.config/oxlint/oxlintrc.json src/index.tsx src/faq/index.ts src/faq/faq-route.ts src/faq/faq-island.tsx src/faq/faq-section.tsx ; echo rc=$?
rc=0 diagnostics=0
```
oxlint trap: `oxlint … template example/src` and `oxlint … src` both print
`No files found to lint` (rc=1, 0 diagnostics = UNMEASURED) because the tree sits under the
hidden `~/.claude` directory. Explicit file paths work; the control file with 16 branches +
`debugger` produced 2 diagnostics.

Island bundle: `public/faq-island.js` 32,943 B minified, 13,266 B gzip. The two `innerHTML`
strings in the bundle are hono/jsx/dom's own `dangerouslySetInnerHTML` support, not template code.

## 2. SSR page

```
$ npx wrangler dev --remote --port 8787        # "Ready on http://localhost:8787"
$ curl -s -D ssr-headers.txt localhost:8787/ -o ssr.html
Content-Type: text/html; charset=UTF-8
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
$ grep -o '<details' ssr.html | wc -l          # 5
$ grep -c 'Ask anything else' ssr.html         # 1
$ grep -o '<div id="faq-ask"[^>]*>' ssr.html
<div id="faq-ask" class="faq-ask" data-action="/api/faq/ask" data-placeholder="Ask anything else" data-loading="Reading the docs">
$ grep -c 'method="post" action="/api/faq/ask"' ssr.html   # 1
$ curl -s -o /dev/null -w '%{http_code} %{content_type}\n' localhost:8787/faq.css        # 200 text/css
$ curl -s -o /dev/null -w '%{http_code} %{content_type}\n' localhost:8787/faq-island.js  # 200 text/javascript
```

## 3. Streaming POST (llama-3.3-70b default) — `example-stream-llama.sse`

```
$ time curl -sN -D - -X POST localhost:8787/api/faq/ask -H 'content-type: application/json' -d '{"question":"can i do evals?"}' -o stream-llama.sse
HTTP/1.1 200 OK
Transfer-Encoding: chunked
Content-Type: text/event-stream
Cache-Control: no-cache
CF-Ray: a3d23c98abdecd36-SJC
Content-Security-Policy: default-src 'self'; script-src 'self'; …
real 1.381s
$ grep -c text-delta stream-llama.sse   # 21     grep -c '"finish"' → 1     grep -c DONE → 1
data: {"type":"text-delta","delta":"Yes"}
data: {"type":"text-delta","delta":", you can"}
…
data: {"type":"finish"}
data: [DONE]
```
Worker log: `{"event":"faq.ask.finish","model":"@cf/meta/llama-3.3-70b-instruct-fp8-fast","ms":1051,"deltas":21,"chars":202,"tokens":51}`.

`x-accel-buffering: no` — three outcomes: set by our code (present in local `wrangler dev`:
`x-accel-buffering: no` in the response), **stripped by Cloudflare's edge** in `--remote`
(absent, `CF-Ray` present). Kept in the route for non-Cloudflare proxies; harmless on CF.

## 4. Negative controls

```
$ B=localhost:8787/api/faq/ask
empty      {"question":""}      → {"error":"Ask a question of 1 to 600 characters."} [400]
whitespace {"question":"   "}   → same [400]
700 chars                       → same [400]
600 chars (boundary)            → [200] text/event-stream
not JSON   'nope'               → {"error":"Body must be JSON {question} or a form field \"question\"."} [400]
wrong key  {"q":"hi"}           → 400
```

Grounding (corpus is a fictional "Lantern" SDK; neither question is answerable from it):
```
Q: How many alpacas does the CEO own?
A: The reference material does not cover this question, please contact https://example.test/contact for more information.
Q: what is the phone number for support?
A: The reference material does not cover the question, please contact https://example.test/contact.
```
No phone number, price, or name was invented in either.

No-JS form fallback:
```
$ curl -s -D - -X POST $B --data-urlencode 'question=can i self-host it?'
HTTP/1.1 200 OK
Content-Type: text/plain;charset=UTF-8
Yes, you can self-host Lantern. The collector is a single Docker image and needs only Postgres. https://example.test/#faq
```

## 5. Raw model chunk shapes (temporary passthrough route, removed after capture)

`workers-ai-raw-llama-3.3.sse` — first frame carries `choices[0].delta.content:""` AND
`response:""`; every content frame carries BOTH `choices[0].delta.content` and `response` with
the same text; last frame `{"response":"","usage":{…,"completion_tokens":8}}` then `[DONE]`.
Served model id reports `@cf/meta/llama-3.3-70b-instruct-sd`.

`workers-ai-raw-gpt-oss-120b.sse` — 117 frames for "Say hello in five words": 105 frames of
`choices[0].delta.{reasoning,reasoning_content}`, then 7 `delta.content` frames, an empty
`choices:[]` frame, the usage frame (`completion_tokens:123`), `[DONE]`. No `response` field on
content frames.

The route's `pieceOf()` = `response || choices[0].delta.content` handles both; reasoning is
never forwarded (checked: `grep -c -i 'user asks\|reasoning' example-stream-gpt-oss.sse` → 0).

## 6. gpt-oss-120b end to end (temporary second mount at `/api/faq/ask-gpt`, removed)

```
real 4.907s   deltas=61 finish=1 reasoning_leaked=0
Yes—you can run evals with Lantern. They let you score recorded outputs using a plain‑language rubric, automatically running on new events and showing a pass rate over time. The Free plan includes 5 evals, and the Pro plan offers unlimited evals. https://example.test/docs/evals
log: {"event":"faq.ask.finish","model":"@cf/openai/gpt-oss-120b","ms":4047,"deltas":61,"chars":278,"tokens":180}
```
llama 1.4 s vs gpt-oss 4.9 s for the same question; llama stays the default.

## 7. Abort mid-stream

Trap found first: `kill -INT` on a backgrounded curl in non-interactive zsh does nothing (the
job ignores SIGINT), so the "abort" completed normally (59 deltas, `finish` logged). Use
`SIGTERM`.

Without `enable_request_signal` (remote and local): client exit 143 after 16 deltas, worker
still answers `/` with 200, but **no** `faq.ask.abort` and no `finish` — the callback was
parked, invisible.

With `compatibility_flags = ["enable_request_signal"]` and the abort log moved INSIDE the
signal listener (the doc says the invocation ends right after it):
```
local workerd:  client exit=143 deltas=20 finish=0 ; worker alive: 200
                {"event":"faq.ask.abort","model":"@cf/meta/llama-3.3-70b-instruct-fp8-fast","ms":1644,"deltas":22,"chars":201,"tokens":3}
--remote, curl SIGTERM:  start logged, no abort line (wrangler's local proxy holds the upstream connection)
--remote, real Chrome Stop button:  {"event":"faq.ask.abort",…,"ms":1447,"deltas":7,"chars":63}   ← propagated
```
So: the runtime signal works; only the curl-through-wrangler-proxy path masks it.

## 8. Browser (real Chrome via `~/tools/fcdp/fcdp`)

```
$ fcdp open http://localhost:8787/
$ fcdp js "…"  → {"details":5,"form":true,"islandMounted":true,"summary":"What is Lantern?"}
$ fcdp fill '#faq-ask-input' 'can i do evals?'   → {"filled":true,"value":"can i do evals?"}; sendEnabled:true
$ fcdp js "document.querySelector('#faq-ask form').requestSubmit()"
+250 ms → {"stopButton":true,"shimmer":"Reading the docs"}
+5 s    → {"answer":"Yes, you can do evals. Evals score recorded outputs with a rubric you write in plain language. The Free plan includes 5 evals, while the Pro plan offers unlimited evals. https://example.test/docs/evals","links":["https://example.test/docs/evals"],"sendBack":true}
Stop:   click Stop at 1.5 s → {"answerChars":52,"error":false,"sendBack":true}; unchanged 3 s later (52)
Screenshot: references/example-rendered.png
$ fcdp console --secs 6
# console: 2 event(s) in 6s
LOG     Matching rules found: Array(9)            ← a browser extension's cookie-banner detector
WARNING Failed to detect known cookie bannes.     ← same extension; not the page
→ 0 CSP violations.
Positive control: inject <script>window.__csp_leak=1</script> → console shows 1 "Refused … Content Security Policy" line, window.__csp_leak === undefined.
```
One UI fix from the screenshot: the input drew a focus rectangle; the reference shows only the
caret. `faq.css` now sets `.faq-ask-input:focus-visible { outline: none }` (button keeps its ring).

## 9. Gaps / not verified

- Not deployed anywhere (by design). Production edge behaviour of `enable_request_signal` is
  documented, and measured on local workerd + through the remote dev proxy from a real browser,
  but not on a deployed Worker.
- Rate limiting: the Cloudflare Rate Limiting binding path is typed and wired but the example
  declares no `[[ratelimits]]`, so only the per-isolate bucket ran (not exercised to 429).
- Light theme was not screenshotted (tokens only).
