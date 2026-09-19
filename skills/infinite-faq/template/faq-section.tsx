/** @jsxImportSource hono/jsx */
/**
 * Infinite FAQ — server-rendered section (hono/jsx, SSR only).
 *
 * Renders a two-column FAQ: heading + intro on the left, an accordion on the right whose
 * LAST row is "Ask anything else". Everything here works with JavaScript OFF:
 *   - rows are native <details>/<summary>, so they open without a script;
 *   - the ask row is a real <form method="post" action="/api/faq/ask">, so a no-JS submit
 *     still reaches the route (which answers with a plain-text stream).
 * The client island (faq-island.tsx) progressively enhances the ask row in place.
 *
 * Copy this file into the site's SSR tree unchanged; pass site copy through props.
 */

export type FaqItem = { q: string; a: string };

export type FaqSectionProps = {
  heading: string;
  intro: string;
  items: FaqItem[];
  askPlaceholder?: string;
  /** Route the island POSTs to and the no-JS form submits to. Must match mountInfiniteFaq. */
  action?: string;
  /** Shimmer text shown before the first token. */
  loadingText?: string;
};

const Chevron = () => (
  <svg
    class="faq-chevron"
    width="16"
    height="16"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path d="m6 9 6 6 6-6" />
  </svg>
);

const Arrow = () => (
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

export const FaqSection = (props: FaqSectionProps) => {
  const action = props.action ?? '/api/faq/ask';
  const placeholder = props.askPlaceholder ?? 'Ask anything else';
  const loadingText = props.loadingText ?? 'Reading the docs';

  return (
    <section class="faq" aria-labelledby="faq-heading">
      <div class="faq-lead">
        <h2 id="faq-heading" class="faq-heading">
          {props.heading}
        </h2>
        <p class="faq-intro">{props.intro}</p>
      </div>
      <div class="faq-list">
        {props.items.map((item) => (
          <details class="faq-row">
            <summary class="faq-q">
              <span>{item.q}</span>
              <Chevron />
            </summary>
            <div class="faq-a">
              <p>{item.a}</p>
            </div>
          </details>
        ))}
        {/* The island replaces the contents of this element; the attributes carry its config. */}
        <div
          id="faq-ask"
          class="faq-ask"
          data-action={action}
          data-placeholder={placeholder}
          data-loading={loadingText}
        >
          <form class="faq-ask-form" method="post" action={action}>
            <label for="faq-ask-input" class="faq-sr-only">
              {placeholder}
            </label>
            <input
              id="faq-ask-input"
              class="faq-ask-input"
              name="question"
              type="text"
              placeholder={placeholder}
              maxlength={600}
              autocomplete="off"
              required
            />
            <button type="submit" class="faq-ask-btn" aria-label="Send">
              <Arrow />
            </button>
          </form>
        </div>
      </div>
    </section>
  );
};
