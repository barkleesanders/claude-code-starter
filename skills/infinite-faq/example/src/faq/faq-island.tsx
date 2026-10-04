/** @jsxImportSource hono/jsx/dom */
/**
 * Infinite FAQ — client island (hono/jsx/dom, browser only).
 *
 * Mounts on the SSR'd #faq-ask row and replaces the no-JS form with the live one:
 *   type → submit streams the answer inline below the row; a shimmer shows before the first
 *   token; Stop aborts the fetch and keeps whatever streamed so far.
 *
 * Wire: POST {action} with JSON {question}; response is text/event-stream where every line is
 *   data: {"type":"text-delta","delta":"..."} | {"type":"error","message":"..."} | {"type":"finish"}
 *   data: [DONE]
 * (the route in faq-route.ts normalises the model's own chunk shape into this).
 *
 * Safety: the answer is rendered by building DOM nodes from a tiny markdown subset —
 * paragraphs, **bold**, `code`, lists, [links](https://...) and bare https URLs. Text is never
 * assigned through innerHTML, and link hrefs are scheme-allowlisted (http, https, mailto).
 * Works under CSP `script-src 'self'`: no inline handlers, no eval.
 */

import type { Child } from 'hono/jsx';
import { useEffect, useRef, useState } from 'hono/jsx';
import { render } from 'hono/jsx/dom';

/**
 * ceiling: the reference client (references/foglamp-AskFoggy.pretty.js, `maxLength: 600`) —
 *   the wire has no lower platform cap; the server enforces the same bound in faq-route.ts.
 * corpus: real civic questions run well under 100 chars (improvecortland/src/chat.ts, measured
 *   2026-08-31); 600 refuses none of them and still fences off pasted documents.
 */
const MAX_QUESTION_CHARS = 600;

const FALLBACK_ERROR = 'Hit a snag. Please try again in a moment.';

type Status = 'idle' | 'loading' | 'streaming' | 'done' | 'error';

type StreamEvent =
  | { type: 'text-delta'; delta: string }
  | { type: 'error'; message: string }
  | { type: 'finish' };

function parseEvent(payload: string): StreamEvent | null {
  let raw: unknown;
  try {
    raw = JSON.parse(payload);
  } catch {
    return null;
  }
  if (typeof raw !== 'object' || raw === null || !('type' in raw)) return null;
  const ev = raw as { type: unknown; delta?: unknown; message?: unknown };
  if (ev.type === 'text-delta' && typeof ev.delta === 'string') {
    return { type: 'text-delta', delta: ev.delta };
  }
  if (ev.type === 'error') {
    return { type: 'error', message: typeof ev.message === 'string' ? ev.message : '' };
  }
  if (ev.type === 'finish') return { type: 'finish' };
  return null;
}

/** Error copy from a non-2xx JSON body ({error: "..."}), else the generic fallback. */
async function errorCopy(res: Response): Promise<string> {
  try {
    const body: unknown = await res.json();
    if (typeof body === 'object' && body !== null && 'error' in body) {
      const e = (body as { error: unknown }).error;
      if (typeof e === 'string' && e) return e;
    }
  } catch {
    // not JSON — fall through
  }
  return FALLBACK_ERROR;
}

// ---------------------------------------------------------------------------
// Minimal markdown → JSX (text nodes only; never HTML strings)
// ---------------------------------------------------------------------------

const SAFE_HREF = /^(https?:\/\/|mailto:)/i;

/** [label](url), **bold**, `code`, bare http(s) URLs. */
const INLINE_RE =
  /\[([^\]]+)\]\((https?:\/\/[^\s)]+|mailto:[^\s)]+)\)|\*\*([^*]+)\*\*|`([^`]+)`|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;

function renderInline(text: string) {
  const out: Child[] = [];
  let last = 0;
  for (const m of text.matchAll(INLINE_RE)) {
    const idx = m.index ?? 0;
    if (idx > last) out.push(text.slice(last, idx));
    const [whole, label, href, bold, code, bare] = m;
    if (label !== undefined && href !== undefined) {
      out.push(
        SAFE_HREF.test(href) ? (
          <a href={href} rel="noopener noreferrer">
            {label}
          </a>
        ) : (
          label
        ),
      );
    } else if (bold !== undefined) {
      out.push(<strong>{bold}</strong>);
    } else if (code !== undefined) {
      out.push(<code>{code}</code>);
    } else if (bare !== undefined) {
      out.push(
        <a href={bare} rel="noopener noreferrer">
          {bare}
        </a>,
      );
    } else {
      out.push(whole);
    }
    last = idx + whole.length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

type Block = { kind: 'p'; text: string } | { kind: 'ul' | 'ol'; items: string[] };

const UL_RE = /^\s*[-*•]\s+/;
const OL_RE = /^\s*\d+[.)]\s+/;

function parseBlocks(md: string): Block[] {
  const blocks: Block[] = [];
  let para: string[] = [];
  const flushPara = () => {
    if (para.length) blocks.push({ kind: 'p', text: para.join(' ') });
    para = [];
  };
  for (const line of md.replace(/\r/g, '').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) {
      flushPara();
      continue;
    }
    const listKind = UL_RE.test(line) ? 'ul' : OL_RE.test(line) ? 'ol' : null;
    if (listKind) {
      flushPara();
      const item = line.replace(listKind === 'ul' ? UL_RE : OL_RE, '').trim();
      const prev = blocks[blocks.length - 1];
      if (prev && prev.kind === listKind) prev.items.push(item);
      else blocks.push({ kind: listKind, items: [item] });
      continue;
    }
    // Strip markdown headings — the answer sits under a question, it needs no titles.
    para.push(trimmed.replace(/^#{1,6}\s+/, ''));
  }
  flushPara();
  return blocks;
}

const Markdown = ({ text }: { text: string }) => (
  <>
    {parseBlocks(text).map((b) =>
      b.kind === 'p' ? (
        <p>{renderInline(b.text)}</p>
      ) : b.kind === 'ul' ? (
        <ul>
          {b.items.map((it) => (
            <li>{renderInline(it)}</li>
          ))}
        </ul>
      ) : (
        <ol>
          {b.items.map((it) => (
            <li>{renderInline(it)}</li>
          ))}
        </ol>
      ),
    )}
  </>
);

// ---------------------------------------------------------------------------
// The ask row
// ---------------------------------------------------------------------------

type AskProps = { action: string; placeholder: string; loadingText: string };

const StopIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <rect x="5" y="5" width="14" height="14" rx="2" />
  </svg>
);

const ArrowIcon = () => (
  <svg
    width="16"
    height="16"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="3"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path d="M5 12h14" />
    <path d="m12 5 7 7-7 7" />
  </svg>
);

function AskRow({ action, placeholder, loadingText }: AskProps) {
  const [question, setQuestion] = useState('');
  const [answer, setAnswer] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [error, setError] = useState('');
  const controller = useRef<AbortController | null>(null);

  // Abort an in-flight stream if the island unmounts.
  useEffect(() => () => controller.current?.abort(), []);

  const busy = status === 'loading' || status === 'streaming';
  const showShimmer = status === 'loading';

  const stop = () => controller.current?.abort();

  const readStream = async (body: ReadableStream<Uint8Array>) => {
    const reader = body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    let acc = '';
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (!payload || payload === '[DONE]') continue;
        const ev = parseEvent(payload);
        if (!ev) continue;
        if (ev.type === 'text-delta') {
          acc += ev.delta;
          setAnswer(acc);
          setStatus('streaming');
        } else if (ev.type === 'error') {
          throw new Error(ev.message);
        }
      }
    }
    return acc;
  };

  const submit = async (e: Event) => {
    e.preventDefault();
    const q = question.trim();
    if (!q || busy) return;
    const ac = new AbortController();
    controller.current = ac;
    setAnswer('');
    setError('');
    setStatus('loading');
    try {
      const res = await fetch(action, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'text/event-stream' },
        body: JSON.stringify({ question: q }),
        signal: ac.signal,
      });
      if (!res.ok || !res.body) throw new Error(await errorCopy(res));
      const text = await readStream(res.body);
      if (!text.trim()) throw new Error('');
      setStatus('done');
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') {
        // Stopped by the user: keep the partial answer, no error copy.
        setStatus('done');
      } else {
        setError(err instanceof Error && err.message ? err.message : FALLBACK_ERROR);
        setStatus('error');
      }
    } finally {
      if (controller.current === ac) controller.current = null;
    }
  };

  return (
    <div>
      <form class="faq-ask-form" onSubmit={submit}>
        <label for="faq-ask-input" class="faq-sr-only">
          {placeholder}
        </label>
        <input
          id="faq-ask-input"
          class="faq-ask-input"
          type="text"
          value={question}
          onInput={(e) => setQuestion((e.target as HTMLInputElement).value)}
          placeholder={placeholder}
          maxLength={MAX_QUESTION_CHARS}
          autocomplete="off"
        />
        {busy ? (
          <button type="button" class="faq-ask-btn is-stop" aria-label="Stop" onClick={stop}>
            <StopIcon />
          </button>
        ) : (
          <button
            type="submit"
            class={question.trim() ? 'faq-ask-btn is-ready' : 'faq-ask-btn'}
            aria-label="Send"
            disabled={!question.trim()}
          >
            <ArrowIcon />
          </button>
        )}
      </form>
      {status !== 'idle' && (
        <div class="faq-answer" aria-live="polite">
          {showShimmer && <p class="faq-shimmer">{loadingText}</p>}
          {answer && <Markdown text={answer} />}
          {status === 'error' && <p class="faq-error">{error}</p>}
        </div>
      )}
    </div>
  );
}

export function mountInfiniteFaq(el: HTMLElement) {
  const props: AskProps = {
    action: el.dataset.action || '/api/faq/ask',
    placeholder: el.dataset.placeholder || 'Ask anything else',
    loadingText: el.dataset.loading || 'Reading the docs',
  };
  el.replaceChildren();
  render(<AskRow {...props} />, el);
}

const host = document.getElementById('faq-ask');
if (host) mountInfiniteFaq(host);
