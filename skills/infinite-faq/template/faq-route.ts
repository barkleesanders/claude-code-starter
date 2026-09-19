/**
 * Infinite FAQ — POST /api/faq/ask (Hono on Cloudflare Workers, Workers AI `AI` binding).
 *
 * Grounding happens HERE, before the first token: the site's corpus goes into the system
 * prompt and the model is told to answer only from it, to cite the site's own URLs, and to
 * say when it does not know. Nothing about the site is left to the model's memory.
 *
 * Wire out (what faq-island.tsx reads), independent of which model produced it:
 *   data: {"type":"text-delta","delta":"..."}   × N
 *   data: {"type":"finish"}
 *   data: [DONE]
 * On a mid-stream failure:  data: {"type":"error","message":"..."}
 *
 * Model chunk shapes are normalised in `pieceOf()`. Both were measured live (see
 * references/verification-2026-09-18.md): llama-3.3 emits {"response":"…"}; gpt-oss-120b
 * emits OpenAI-style {"choices":[{"delta":{"content":"…"}}]} and a `reasoning` field that
 * is deliberately never forwarded — a model's scratchpad is not an answer.
 *
 * Docs (fetched 2026-09-18):
 *   https://developers.cloudflare.com/workers-ai/models/llama-3.3-70b-instruct-fp8-fast/
 *   https://developers.cloudflare.com/workers-ai/models/gpt-oss-120b/
 *   https://hono.dev/docs/helpers/streaming
 */

import type { Context, Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { z } from 'zod';

export type FaqCorpusDoc = { title: string; url: string; text: string };

export type FaqModel = '@cf/meta/llama-3.3-70b-instruct-fp8-fast' | '@cf/openai/gpt-oss-120b';

type ChatMessage = { role: 'system' | 'user'; content: string };

type FaqStreamRequest = {
  messages: ChatMessage[];
  stream: true;
  max_tokens: number;
  temperature: number;
};

/**
 * The slice of the Workers AI binding this route drives. The real `Ai` binding is assignable
 * to it (same approach as improvecortland/src/chat.ts), so sites pass `c.env.AI` as is.
 */
export type FaqAi = { run(model: FaqModel, input: FaqStreamRequest): Promise<unknown> };

/** Cloudflare Rate Limiting binding (`[[ratelimits]]` in wrangler config). */
export type FaqRateLimiter = { limit(opts: { key: string }): Promise<{ success: boolean }> };

export type FaqEnv = { Bindings: { AI: FaqAi } };

export type InfiniteFaqOptions = {
  /** Human name of the site, used in the prompt ("answer questions about <siteName>"). */
  siteName: string;
  /** Where to send people when the corpus has no answer (the site's own contact/help URL). */
  fallbackUrl: string;
  /** The grounding text. Static array, or a loader (KV / D1 / build-time module). */
  corpus: FaqCorpusDoc[] | (() => Promise<FaqCorpusDoc[]>);
  /** Default: llama-3.3-70b — measured faster to first token and non-reasoning. */
  model?: FaqModel;
  /** Output budget. Default 800 for llama, 2048 for gpt-oss (its reasoning eats the budget). */
  maxTokens?: number;
  /** Route path. Default '/api/faq/ask'. Must match the SSR section's `action`. */
  path?: string;
  /** Optional Cloudflare Rate Limiting binding. Without it, a per-isolate bucket is used. */
  rateLimiter?: FaqRateLimiter;
  /** Corpus chars placed in the prompt before truncation. See MAX_CORPUS_CHARS. */
  maxCorpusChars?: number;
};

/**
 * ceiling: the reference client caps the input at 600 (references/foglamp-AskFoggy.pretty.js);
 *   the island enforces the same maxLength, so this only refuses hand-crafted requests.
 * corpus: real civic questions run well under 100 chars (improvecortland/src/chat.ts, 2026-08-31).
 */
export const MAX_QUESTION_CHARS = 600;

/**
 * Upper bound on the request body, checked BEFORE any parser sees it.
 * ceiling: Workers accept bodies up to 100 MB on the Free plan (developers.cloudflare.com/
 *   workers/platform/limits/, read 2026-09-18); c.req.json()/formData() would materialise all
 *   of it before zod ever saw the 600-char cap — ~2x the body in V8 against the 128 MB
 *   isolate cap, taking every other visitor's stream on that isolate down with it.
 * corpus: the largest legitimate body is {"question": 600 chars} plus a short context —
 *   under 3 KB even at 4 bytes per char. 8 KB refuses nothing real.
 */
export const MAX_BODY_BYTES = 8192;

/**
 * The request body, read chunk by chunk and abandoned the moment it passes MAX_BODY_BYTES —
 * Content-Length is a hint (checked first, cheaply) but a chunked body carries none, so the
 * reader is the actual bound. Returns null when too large.
 */
async function readBoundedBody(c: Context): Promise<Uint8Array<ArrayBuffer> | null> {
  const declared = Number(c.req.header('content-length') ?? 0);

  if (declared > MAX_BODY_BYTES) return null;
  const body = c.req.raw.body;

  if (!body) return new Uint8Array(0);
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;

  try {
    for (;;) {
      const { done, value } = await reader.read();

      if (done) break;
      size += value.byteLength;

      if (size > MAX_BODY_BYTES) return null;
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => undefined);
  }

  // A fresh ArrayBuffer (not ArrayBufferLike) so the bytes type-check as a BodyInit.
  const bytes = new Uint8Array(new ArrayBuffer(size));
  let at = 0;

  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.byteLength;
  }

  return bytes;
}

/** The bounded bytes as form fields — the platform parser only ever sees at most 8 KB. */
function boundedFormData(bytes: Uint8Array<ArrayBuffer>, ct: string): Promise<FormData> {
  return new Response(bytes, { headers: { 'content-type': ct } }).formData();
}

/**
 * ceiling: both supported models have a 128,000-token context window (model pages above);
 *   24,000 chars is roughly 6,000 tokens, leaving the window mostly free and keeping time to
 *   first token low — prompt length is the main lever on TTFT for a grounded answer.
 * corpus: a 5-question FAQ plus a help page is ~3,000 chars; a whole help section ~15,000.
 *   Truncation is logged (faq.corpus.truncated) so a too-small budget is visible, not silent.
 */
const MAX_CORPUS_CHARS = 24_000;

/**
 * Per-isolate fallback bucket when no Rate Limiting binding is wired. Best effort only:
 * a Worker isolate is per-colo and short-lived, so this bounds a single burst, not a
 * distributed one. Wire `rateLimiter` for a real limit (see integration-guide.md).
 */
// ceiling: 16bedlimit's production Rate Limiting binding uses simple {limit: 20, period: 60}
//   (measured adequate 2026-08-26); this per-isolate bucket is stricter because it cannot
//   see other isolates. corpus: a human asks at most ~1 question per 30 s; 10/min refuses none.
const LOCAL_BUCKET_LIMIT = 10;
const LOCAL_BUCKET_WINDOW_MS = 60_000;

const DEFAULT_MODEL: FaqModel = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';

/**
 * gpt-oss-120b is a REASONING model: it spends a `reasoning` channel before any `content`,
 * and at the Workers AI default (256) the answer comes back empty with no error
 * (improvecortland/src/chat.ts, measured 2026-08-31). 2048 leaves room for both.
 */
const DEFAULT_MAX_TOKENS: Record<FaqModel, number> = {
  '@cf/meta/llama-3.3-70b-instruct-fp8-fast': 800,
  '@cf/openai/gpt-oss-120b': 2048,
};

const AskBody = z.object({ question: z.string().trim().min(1).max(MAX_QUESTION_CHARS) });

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

function renderCorpus(docs: FaqCorpusDoc[], budget: number): { text: string; truncated: boolean } {
  const parts: string[] = [];
  let used = 0;
  let truncated = false;
  for (const d of docs) {
    const block = `### ${d.title}\nURL: ${d.url}\n${d.text.trim()}`;
    if (used + block.length > budget) {
      truncated = true;
      break;
    }
    parts.push(block);
    used += block.length + 2;
  }
  return { text: parts.join('\n\n'), truncated };
}

function systemPrompt(siteName: string, fallbackUrl: string, corpus: string): string {
  return `You answer visitors' questions about ${siteName} using ONLY the reference material below.

Rules:
- Every fact must come from the reference material. Do not use outside knowledge and do not guess.
- When the material answers the question, answer briefly (2-5 short sentences, or a short list) and include the URL of the page it came from as a bare link.
- When the material does not cover the question, say so plainly in one sentence and point the visitor to ${fallbackUrl}. Never invent a URL, price, date, phone number or name.
- Write plain prose with light markdown only: **bold**, lists, links. No headings, no tables, no code blocks.

Reference material:

${corpus}`;
}

// ---------------------------------------------------------------------------
// Model stream → text pieces
// ---------------------------------------------------------------------------

/**
 * Text carried by one SSE chunk, whatever the model's shape. `||` not `??`: llama's stream
 * sends response:"" alongside real content on early frames (16bedlimit, measured 2026-08-26).
 */
const ChunkSchema = z.object({
  // Workers AI serialises this field as a JSON NUMBER when the chunk's text is all digits
  // ({"choices":[{"delta":{"content":"7 \n"}}],"response":7}, measured 2026-09-18 on
  // llama-3.3-70b-instruct-fp8-fast). z.string() rejected the frame and the digits vanished
  // from years, prices and ids. The string copy lives in choices[0].delta.content.
  response: z.union([z.string(), z.number()]).optional(),
  choices: z
    .array(z.object({ delta: z.object({ content: z.string().nullable().optional() }).optional() }))
    .optional(),
  usage: z
    .object({ completion_tokens: z.number().optional(), total_tokens: z.number().optional() })
    .optional(),
});

type Chunk = z.infer<typeof ChunkSchema>;

function pieceOf(chunk: Chunk): string {
  // The OpenAI-style copy first: it is always a string and keeps the chunk's whitespace,
  // which the numeric `response` form has already lost.
  const content = chunk.choices?.[0]?.delta?.content;

  if (content) return content;
  const r = chunk.response;

  return r === undefined || r === '' ? '' : String(r);
}

type StreamStats = { deltas: number; chars: number; tokens: number | null; rejected: number };

/**
 * Reads the model's SSE body and yields text pieces. Parses `data:` lines only; the
 * `[DONE]` sentinel ends the stream. Cancels the upstream reader when the consumer stops
 * or when `signal` (the client's disconnect) fires, so a pending read() resolves at once.
 */
async function* textPieces(
  body: ReadableStream<Uint8Array>,
  stats: StreamStats,
  signal: AbortSignal,
) {
  const reader = body.getReader();
  const dec = new TextDecoder();
  let buf = '';
  const cancel = () => void reader.cancel().catch(() => undefined);
  signal.addEventListener('abort', cancel, { once: true });
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (!payload) continue;
        if (payload === '[DONE]') return;
        let raw: unknown;
        try {
          raw = JSON.parse(payload);
        } catch {
          continue; // partial or non-JSON frame
        }
        const parsed = ChunkSchema.safeParse(raw);
        if (!parsed.success) {
          // A frame the schema refuses is a model-shape change, not noise: count it.
          stats.rejected += 1;
          continue;
        }
        if (parsed.data.usage?.completion_tokens !== undefined) {
          stats.tokens = parsed.data.usage.completion_tokens;
        }
        const piece = pieceOf(parsed.data);
        if (!piece) continue;
        stats.deltas += 1;
        stats.chars += piece.length;
        yield piece;
      }
    }
  } finally {
    signal.removeEventListener('abort', cancel);
    await reader.cancel().catch(() => undefined);
  }
}

// ---------------------------------------------------------------------------
// Rate limiting
// ---------------------------------------------------------------------------

const localBuckets = new Map<string, { count: number; resetAt: number }>();

function localBucketAllows(key: string, now: number): boolean {
  const b = localBuckets.get(key);
  if (!b || b.resetAt <= now) {
    localBuckets.set(key, { count: 1, resetAt: now + LOCAL_BUCKET_WINDOW_MS });
    return true;
  }
  b.count += 1;
  return b.count <= LOCAL_BUCKET_LIMIT;
}

async function allowed(limiter: FaqRateLimiter | undefined, ip: string): Promise<boolean> {
  if (!limiter) return localBucketAllows(ip, Date.now());
  try {
    return (await limiter.limit({ key: `faq:${ip}` })).success;
  } catch (err) {
    // A limiter outage degrades cost control, not the FAQ. Visible, not silent.
    log('faq.ratelimit.unavailable', { error: err instanceof Error ? err.message : String(err) });
    return true;
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

function log(event: string, fields: Record<string, string | number | boolean | null>) {
  console.log(JSON.stringify({ event, ...fields }));
}

async function readQuestion(c: Context): Promise<{ question: string; form: boolean } | Response> {
  const ct = c.req.header('content-type') ?? '';
  const form =
    ct.includes('application/x-www-form-urlencoded') || ct.includes('multipart/form-data');
  const bytes = await readBoundedBody(c);
  if (bytes === null) {
    return c.json({ error: `Ask a question of 1 to ${MAX_QUESTION_CHARS} characters.` }, 413);
  }
  let raw: unknown;
  try {
    raw = form
      ? { question: (await boundedFormData(bytes, ct)).get('question') }
      : JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return c.json({ error: 'Body must be JSON {question} or a form field "question".' }, 400);
  }
  const parsed = AskBody.safeParse(raw);
  if (!parsed.success) {
    return c.json({ error: `Ask a question of 1 to ${MAX_QUESTION_CHARS} characters.` }, 400);
  }
  return { question: parsed.data.question, form };
}

/** Build the raw handler. Use `mountInfiniteFaq` unless the site wires routes itself. */
export function askFaqHandler(opts: InfiniteFaqOptions) {
  const model = opts.model ?? DEFAULT_MODEL;
  const maxTokens = opts.maxTokens ?? DEFAULT_MAX_TOKENS[model];
  const corpusBudget = opts.maxCorpusChars ?? MAX_CORPUS_CHARS;

  return async (c: Context<FaqEnv>): Promise<Response> => {
    const ip = c.req.header('cf-connecting-ip') ?? 'unknown';
    if (!(await allowed(opts.rateLimiter, ip))) {
      log('faq.ask.ratelimited', { limiter: Boolean(opts.rateLimiter) });
      return c.json({ error: 'Too many questions. Wait a minute and try again.' }, 429, {
        'retry-after': '60',
      });
    }

    const read = await readQuestion(c);
    if (read instanceof Response) return read;
    const { question, form } = read;

    const docs = typeof opts.corpus === 'function' ? await opts.corpus() : opts.corpus;
    const { text: corpus, truncated } = renderCorpus(docs, corpusBudget);
    if (truncated) log('faq.corpus.truncated', { docs: docs.length, budget: corpusBudget });

    const started = Date.now();
    // Length only — the question itself never reaches the logs by default.
    log('faq.ask.start', { qLen: question.length, model, form });

    let body: unknown;
    try {
      body = await c.env.AI.run(model, {
        messages: [
          { role: 'system', content: systemPrompt(opts.siteName, opts.fallbackUrl, corpus) },
          { role: 'user', content: question },
        ],
        stream: true,
        max_tokens: maxTokens,
        temperature: 0.2,
      });
    } catch (err) {
      log('faq.ask.error', {
        model,
        stage: 'run',
        error: err instanceof Error ? err.message : String(err),
      });
      return c.json({ error: 'The assistant is unavailable right now.' }, 503);
    }
    if (!(body instanceof ReadableStream)) {
      log('faq.ask.error', { model, stage: 'run', error: `expected a stream, got ${typeof body}` });
      return c.json({ error: 'The assistant is unavailable right now.' }, 503);
    }

    const stats: StreamStats = { deltas: 0, chars: 0, tokens: null, rejected: 0 };
    const finish = (outcome: 'finish' | 'abort' | 'error') =>
      log(`faq.ask.${outcome}`, { model, ms: Date.now() - started, ...stats });

    // No-JS fallback: the SSR form posts here; answer as plain text once complete.
    if (form) {
      let text = '';
      try {
        for await (const piece of textPieces(body, stats, c.req.raw.signal)) text += piece;
      } catch (err) {
        log('faq.ask.error', {
          model,
          stage: 'stream',
          error: err instanceof Error ? err.message : String(err),
        });
        return c.text('The assistant is unavailable right now.', 503);
      }
      finish('finish');
      return c.text(text.trim() || 'No answer was produced. Please try again.');
    }

    // Client disconnects reach the Worker only under the `enable_request_signal`
    // compatibility flag (https://developers.cloudflare.com/workers/runtime-apis/request/,
    // read 2026-09-18) — without it `signal` never fires and a stopped stream runs to the
    // model's end. Hono's own `stream.onAbort` is kept as the second source (it fires when the
    // runtime cancels the response body). The write is raced against the signal so a
    // disconnected client can never park this isolate on stream backpressure.
    const signal = c.req.raw.signal;
    let aborted = false;
    // Logged INSIDE the listener: once the client is gone the runtime ends this invocation,
    // so code after the loop below is not guaranteed to run.
    const onAbort = () => {
      if (aborted) return;
      aborted = true;
      finish('abort');
    };
    const clientGone = new Promise<void>((resolve) => {
      if (signal.aborted) resolve();
      else signal.addEventListener('abort', () => resolve(), { once: true });
    });
    signal.addEventListener('abort', onAbort, { once: true });
    c.header('cache-control', 'no-cache');
    c.header('x-accel-buffering', 'no'); // stripped by Cloudflare's edge; kept for other proxies
    return streamSSE(
      c,
      async (stream) => {
        stream.onAbort(onAbort);
        for await (const piece of textPieces(body, stats, signal)) {
          if (aborted) break;
          await Promise.race([
            stream.writeSSE({ data: JSON.stringify({ type: 'text-delta', delta: piece }) }),
            clientGone,
          ]);
        }
        if (aborted) return;
        await stream.writeSSE({ data: JSON.stringify({ type: 'finish' }) });
        await stream.writeSSE({ data: '[DONE]' });
        finish('finish');
      },
      async (err, stream) => {
        finish('error');
        log('faq.ask.error', { model, stage: 'stream', error: err.message });
        await stream.writeSSE({
          data: JSON.stringify({
            type: 'error',
            message: 'Hit a snag. Please try again in a moment.',
          }),
        });
      },
    );
  };
}

/** Register POST {path} on the app. Returns the app for chaining. */
export function mountInfiniteFaq<E extends FaqEnv>(
  app: Hono<E>,
  opts: InfiniteFaqOptions,
): Hono<E> {
  app.post(opts.path ?? '/api/faq/ask', askFaqHandler(opts));
  return app;
}
