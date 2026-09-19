/**
 * Server-side barrel. Deliberately does NOT export faq-island.tsx: that file imports
 * hono/jsx/dom and must only ever be bundled for the browser (npm run build:island).
 */

export type { FaqCorpusDoc, FaqModel, FaqRateLimiter, InfiniteFaqOptions } from './faq-route.ts';
export { askFaqHandler, MAX_QUESTION_CHARS, mountInfiniteFaq } from './faq-route.ts';
export type { FaqItem, FaqSectionProps } from './faq-section.tsx';
export { FaqSection } from './faq-section.tsx';
