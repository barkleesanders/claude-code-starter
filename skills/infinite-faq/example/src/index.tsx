/** @jsxImportSource hono/jsx */
/**
 * Infinite FAQ — minimal example Worker (verification target for the skill).
 *
 * `/`          SSR page: 5 accordion questions + the "Ask anything else" row.
 * `/api/faq/ask` POST — streams a grounded Workers AI answer (see src/faq/faq-route.ts).
 * `/faq.css`, `/faq-island.js` — served from ./public by the assets binding.
 *
 * CSP is deliberately strict (`script-src 'self'`, `connect-src 'self'`) to prove the island
 * needs no inline script and the stream is same-origin.
 */

import { Hono } from 'hono';
import { secureHeaders } from 'hono/secure-headers';
import type { FaqCorpusDoc, FaqItem } from './faq';
import { FaqSection, mountInfiniteFaq } from './faq';

type Bindings = { AI: Ai; ASSETS: Fetcher };

const app = new Hono<{ Bindings: Bindings }>();

app.use(
  secureHeaders({
    contentSecurityPolicy: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'"],
      connectSrc: ["'self'"],
      imgSrc: ["'self'", 'data:'],
      objectSrc: ["'none'"],
      baseUri: ["'self'"],
      formAction: ["'self'"],
      frameAncestors: ["'none'"],
    },
  }),
);

const SITE_URL = 'https://example.test';

/** The visible FAQ. These five rows are also the first part of the grounding corpus. */
const ITEMS: FaqItem[] = [
  {
    q: 'What is Lantern?',
    a: 'Lantern is a small observability SDK for LLM apps: it records prompts, responses, tool calls and latency so you can see what your agent actually did.',
  },
  {
    q: 'Which SDK versions are supported?',
    a: 'Lantern supports the Vercel AI SDK v4 and v5, the OpenAI Node SDK v4+, and any provider through the plain HTTP recorder.',
  },
  {
    q: 'Can I self-host it?',
    a: 'Yes. The collector is a single Docker image and needs only Postgres. The hosted plan exists for teams that would rather not run it.',
  },
  {
    q: 'Where are my prompts and responses stored?',
    a: 'In your own Postgres when self-hosting. On the hosted plan, in the region you pick at signup (US or EU), encrypted at rest, deleted 30 days after you close the account.',
  },
  {
    q: 'What does the SDK add to my request latency?',
    a: 'Nothing on the request path. Events are batched in memory and flushed in the background; a flush that fails is retried and never blocks your call.',
  },
];

/**
 * Corpus option 2 from the skill: the FAQ items themselves plus a few doc pages inlined at
 * build time. Real sites generate this file from their help pages (see integration-guide.md).
 */
const CORPUS: FaqCorpusDoc[] = [
  ...ITEMS.map((i) => ({ title: i.q, url: `${SITE_URL}/#faq`, text: i.a })),
  {
    title: 'Pricing',
    url: `${SITE_URL}/pricing`,
    text: 'Free plan: 10,000 events per month, 7-day retention, 5 evals. Pro plan: $29 per month, 1,000,000 events, 90-day retention, unlimited evals, email support. Self-hosting is free under the Apache 2.0 license.',
  },
  {
    title: 'Evals',
    url: `${SITE_URL}/docs/evals`,
    text: 'Evals score recorded outputs with a rubric you write in plain language. Each eval runs on new events automatically and shows a pass rate over time. The Free plan includes 5 evals; Pro is unlimited.',
  },
];

mountInfiniteFaq(app, {
  siteName: 'Lantern',
  fallbackUrl: `${SITE_URL}/contact`,
  corpus: CORPUS,
});

const Page = () => (
  <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Lantern — Questions</title>
      <link rel="stylesheet" href="/faq.css" />
      <link rel="stylesheet" href="/site.css" />
    </head>
    <body>
      <main class="wrap">
        <FaqSection
          heading="Questions"
          intro="The short ones are here. For anything else, ask below."
          items={ITEMS}
          askPlaceholder="Ask anything else"
        />
      </main>
      <script type="module" src="/faq-island.js"></script>
    </body>
  </html>
);

app.get('/', (c) => c.html(<Page />));

export default app;

