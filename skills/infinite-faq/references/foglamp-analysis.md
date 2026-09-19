# "Infinite FAQ" — ground-truth analysis of the reference (2026-09-18)

Source: https://x.com/heyimgustavo/status/2100728786694136224 ("infinite faq", 8.3s video, Gustavo / Foglamp).
Live site: https://www.foglamp.dev (Next.js + Turbopack, Vercel). Backend: https://api.foglamp.dev (Google Frontend).

## What the video shows (frames: video-frame-*.png)
1. Two-column section. Left: `Questions` h2 + "The short ones are here. For anything else, ask Foggy below."
2. Right: 5 accordion rows (question + chevron, hairline dividers). The 6th row is
   `Ask anything else →` — visually a sibling of the accordion rows, NOT a chat widget.
3. Clicking it focuses an `<input>`; typing shows the caret; the arrow becomes a filled submit button.
4. Enter → button turns into a Stop (■) button; a shimmer "Reading the docs" appears under the row.
5. Tokens stream in below the row as markdown (bold, links). Answer stays inline; the accordion stays put.

## The real client (references/foglamp-AskFoggy.pretty.js, de-minified from chunk 0i~uphgcb3vp5.js)
- Component `AskFoggy`: Vercel AI SDK v5 `useChat({ transport: new DefaultChatTransport({ api: `${NEXT_PUBLIC_SERVER_URL}/foggy/public` }) })`
- `isLoading = status === 'submitted' || status === 'streaming'`
- Answer text = `messages.findLast(role==='assistant').parts.filter(type==='text').map(t=>t.text).join('')`
- `showShimmer = isLoading && !answerText` → `<TextShimmerLoader text="Reading the docs" />`
- `<input id="ask-foggy" placeholder="Ask anything else" maxLength={600} autoComplete="off">`, sr-only label
- Button: loading ? Stop (calls `stop()`) : Submit (disabled when empty; ghost→secondary variant when text present)
- Markdown via `Streamdown` (streaming-safe markdown renderer), tables disabled
- Error: tries `JSON.parse(error.message).error`, else "Foggy hit a snag. Please try again in a moment."
- Answer container: `min-h-60 pt-5 pb-6 text-[15px] leading-relaxed` with `[&_a]:underline` etc.

## The wire (references/foglamp-stream-capture.sse, captured live 2026-09-18 17:43 UTC)
POST https://api.foglamp.dev/foggy/public  (CORS: origin-locked to https://www.foglamp.dev)
Body: {"id":..,"messages":[{"id":..,"role":"user","parts":[{"type":"text","text":"can i do evals?"}]}],"trigger":"submit-message"}
Response: 200 text/event-stream, `x-vercel-ai-ui-message-stream: v1`, `x-accel-buffering: no`
  data: {"type":"start"} / start-step / text-start / N × text-delta{delta} / text-end / finish-step / finish{finishReason} / [DONE]
- NO tool-call parts on the wire ⇒ grounding is done server-side BEFORE the first token (docs in the
  system prompt or a retrieval step). "Reading the docs" is just the pre-first-token shimmer.
- Whole answer ≈ 6 deltas; first token in ~1s.

## Remake target for the user's sites
- Every site is Hono on Cloudflare Workers; AIVA / improvebayarea / improvecortland already call
  Workers AI via the `AI` binding (`@cf/meta/llama-3.3-70b-instruct-fp8-fast`, `@cf/openai/gpt-oss-120b`).
- So: `hono/jsx` SSR accordion (works with JS off) + `hono/jsx/dom` island for the ask row +
  `POST /api/faq/ask` that streams Workers AI (`stream:true`) grounded on a per-site corpus.
