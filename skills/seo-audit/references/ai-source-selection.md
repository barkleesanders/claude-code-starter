# AI Source Selection Audit — Will ChatGPT/LLMs Pick This Page?

Distinct from classic SEO (can Google *rank* it?) and from GEO/AEO copywriting (is the
*answer* well-phrased?). This audit answers a narrower, mechanical question: **when an LLM
assistant searches the web, can it FETCH your page, and once fetched, will it CITE you?**

Framework synthesized from Suganthan Mohanadasan's teardown of ChatGPT's live search
internals — "How ChatGPT Picks Its Sources"
(https://suganthan.com/blog/how-chatgpt-picks-sources/) — plus a real audit of
example.com (2026-06-25) that the methodology below is derived from.

> Use this section for any client that cares about appearing in ChatGPT / Perplexity /
> Claude / Bing Copilot / Google AI answers. Cross-reference the **ai-seo** skill for the
> content/answer-phrasing side; this file is the *retrieval & citation plumbing* side.

---

## How an LLM assistant actually sources an answer (the mechanics)

ChatGPT's search runs through four retrieval back-ends (`result_source`): a licensed-publisher
pipeline (**Labrador** — Reuters/WSJ/Wikipedia/arXiv, ~1KB snippets), two commercial scrapers
(**Bright Data** for shopping/finance/commercial, **Oxylabs** for regional/local/open web), and
a baseline **SERP** pipeline for news. You don't choose your pipeline — your page's category and
the user's *wording* do.

Three outcomes, in order, and they are NOT the same thing:

1. **Fetched** — the page is pulled into the model's context (invisible to the user).
2. **Cited** — the page is attached as a numbered source/footnote.
3. **Mentioned** — your brand name appears in the prose but is NOT the cited source.

The gap between these is where pages lose. Example from the source: YouTube was *fetched* more
than Reddit, but Reddit was *cited* far more — because YouTube metadata had no transcript text
to extract, while Reddit's text was fully present. **Extractable plain text beats rich-but-opaque
media every time.** And note: a query may never trigger a search at all — wording classified as a
`text` turn answers from training data only, with zero retrieval.

---

## The seven signals that decide fetch-and-cite (audit these)

### 1. CAN the bot even reach you? (the silent killer)
The entire framework assumes the crawler gets a 200. If your edge/WAF/CDN returns 403/429 to
AI bot user-agents, you are invisible no matter how good the content is — and `robots.txt`
saying `Allow: /` does NOT help, because a WAF block happens at a *lower layer than robots.txt*.
This is the most common and most invisible failure. **Always test this first** (see methodology).

The bots that matter, by job:
- `OAI-SearchBot` — builds ChatGPT Search's **index** (the persistent one). Most important.
- `ChatGPT-User` — live, on-demand fetch when a user's prompt triggers browsing.
- `GPTBot` — OpenAI's training crawler (future model knowledge + Common Crawl-style reach).
- `PerplexityBot`, `Perplexity-User` — Perplexity index + live fetch.
- `ClaudeBot`, `Claude-User`, `anthropic-ai` — Anthropic index/fetch/training.
- `Google-Extended` — gates your content for Gemini/Vertex (separate from Googlebot ranking).

A site can be perfectly Google-indexed and totally ChatGPT-invisible. Test each UA separately.

### 2. Are the FACTS in plain server-rendered HTML text?
The model extracts facts (prices, dates, specs, numbers, claims) from the *fetched bytes*. Most
AI scrapers execute little or no JavaScript. So:
- Facts rendered client-side by React/Vue/Svelte after hydration are **not seen**.
- The model literally scans for currency symbols (`$`, `€`) and structured numbers in the text.
- A JS-only pricing table doesn't just rank badly — the model falls back to a third party
  (G2, a review site) for your numbers, and cites *them*, not you.
- Facts inside a PDF, an image, a `<canvas>`, or behind a JS toggle/accordion → invisible.

The model's own stated reasoning: prefer the official page for facts → if the official page is
JS-gated/unparseable → fall back to and cite a third party. So a JS wall actively *hands your
citation to a competitor.*

### 3. Per-route parity between what bots see and what users see
SPA shells frequently serve the *same* `index.html` (same `<title>`, same `<meta description>`,
same canonical pointing at the homepage) for every route, then fix it client-side via
React Helmet / next/head. A non-JS bot then sees N pages that all look like the homepage. Test
that each route's *static* HTML carries that route's own title, description, self-referencing
canonical, and body facts.

### 4. Canonical correctness for non-JS fetchers
If `/services/x` ships a static canonical of `https://site.com/` (homepage) and only corrects it
in JS, non-JS crawlers read "this is a duplicate of the homepage" → the page is collapsed away.
Every indexable route's *static* canonical must be self-referencing.

### 5. Domain-level dedup → one strong page per claim
Results are deduped by domain: 20 thin pages on one claim collapse to 1 in the model's view. A
single authoritative page per factual claim beats a pile of weak/near-duplicate pages. This is
the anti-pattern for naive programmatic-SEO fanout — mass thin pages don't multiply citations.

### 6. You cannot cite yourself → earn third-party text coverage
For *claims about your brand* (you're the best/cheapest/fastest), the model cites third parties,
not your own marketing page. The highest-citation sources in the sample were **Reddit** and
text-based review/comparison hubs (because they're text, topical, and not the subject). To be
*mentioned* as a recommendation you need: Reddit threads, review-site listings, comparison/
"alternatives" pages, and PR. Your own page earns citations for *your own verifiable specs/facts*
(pricing, hours, what you do) — not for self-praise.

### 7. Local/commercial caps
Local intent returns at most ~2 results (`local_results_limit: 2`) — top-2 or invisible.
Commercial/shopping routes through Bright Data; weather/finance likewise. Match the page type to
how that category is actually retrieved.

---

## Detection methodology (run these — don't guess)

`curl` is the right tool here: it does NOT execute JS, so it sees roughly what a non-JS AI
scraper sees. (Caveat: live-fetch agents like ChatGPT-User render more than the index crawlers;
still, the index crawlers are the ones that build persistent visibility, so optimize for no-JS.)

**A. Bot reachability matrix — the first thing to run, every time:**
```bash
for ua in "OAI-SearchBot/1.0" "ChatGPT-User/1.0" "GPTBot/1.0" "ClaudeBot/1.0" \
          "PerplexityBot/1.0" "Googlebot/2.1" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"; do
  code=$(curl -sL -o /tmp/ua.html -w "%{http_code}" -A "$ua" https://TARGET/)
  printf "%-42s http=%s bytes=%s\n" "$ua" "$code" "$(wc -c </tmp/ua.html|tr -d ' ')"
done
# Any AI bot returning 403/429 while a browser UA gets 200 = WAF/edge block. CRITICAL finding.
# A short custom body ("Your request was blocked.") + `server: cloudflare`/`cf-ray` in -D
# headers = a Cloudflare bot-block (Security→Bots "Block AI Scrapers", Super Bot Fight Mode,
# or a WAF rule) firing BEFORE the app. robots.txt is irrelevant to this layer.
```

**B. Facts-survive-without-JS check (per money page):**
```bash
curl -sL https://TARGET/services/x -o /tmp/p.html
grep -oiE '<title>[^<]*</title>|<link rel="canonical"[^>]*>' /tmp/p.html   # per-route? self-canonical?
grep -ciE '\$[0-9]|[0-9]+ (days|hours|%)|price|free' /tmp/p.html           # are the numbers in the bytes?
grep -c 'application/ld+json' /tmp/p.html                                   # schema in static HTML?
sed -e 's/<[^>]*>//g' /tmp/p.html | tr -s ' \n' ' \n' | grep -v '^\s*$' | head -40  # visible text
```

**C. Render-parity check (does a bot get the SAME shell on every route?):**
Fetch `/` and three deep routes; if byte counts and `<title>`/canonical are identical across all
of them, the static shell is route-blind and facts are JS-only. (If a *prerender* path exists for
known bots, fetch as `Googlebot` and compare to the browser fetch — different bytes = a prerender
is in play, and the fix may be "route AI bots through the existing prerender" rather than new SSR.)

**D. `site:` survivability:** confirm `site:TARGET/specific-page` is indexed; if money pages are
missing, suspect canonical-to-homepage or thin/dup collapse.

---

## Scoring checklist (report each as Pass / Fail / N-A with evidence)

| # | Check | Evidence to capture |
|---|-------|---------------------|
| 1 | OAI-SearchBot, ChatGPT-User, GPTBot, ClaudeBot, PerplexityBot all get **200** | reachability matrix output |
| 2 | Bot allowlist includes **OAI-SearchBot** specifically (often forgotten) | code/WAF allowlist |
| 3 | Each money page's facts/numbers present in **static** (no-JS) HTML | curl + grep |
| 4 | Each route ships its **own** title/description in static HTML | curl per route |
| 5 | Each indexable route's static canonical is **self-referencing** (not homepage) | grep canonical |
| 6 | JSON-LD schema present in **static** bytes (not JS-injected) | grep ld+json |
| 7 | One authoritative page per claim (no thin programmatic fanout) | sitemap + dedup review |
| 8 | Third-party citation surface exists (Reddit, reviews, comparisons, PR) | external search |
| 9 | `robots.txt` allows the AI bots **and** the edge/WAF agrees (no 403) | A + robots fetch |
| 10 | Local-intent pages aimed at top-2 (if local matters) | SERP/maps check |

---

## Fix patterns (in leverage order)

1. **Unblock AI bots at the edge first.** A WAF 403 nullifies everything else. Cheapest, highest
   ROI. Then re-run the reachability matrix to confirm 200s.
2. **If a prerender path already serves Googlebot, extend its UA allowlist to the AI bots**
   (especially `OAI-SearchBot`) rather than building new SSR. Verify the prerendered HTML carries
   per-route title, self-canonical, facts-in-text, and schema.
3. **Move any JS-gated facts into server-rendered HTML** (SSR/SSG/prerender). Numbers, pricing,
   specs, dates — not just nav chrome.
4. **Fix static canonicals** to self-reference per route.
5. **Consolidate thin pages**; one strong page per claim.
6. **Build the third-party surface** (you can't cite yourself): seed Reddit answers, get on
   review/comparison hubs, earn PR. This is the only lever for "recommend me" queries.

## Common false-positives / calibration notes

- "We have great SEO content" — verify it's in the *static* bytes, not post-hydration DOM.
- "robots.txt allows GPTBot" — necessary but NOT sufficient; the WAF can still 403.
- "Googlebot indexes us fine" — Googlebot renders JS; AI index crawlers largely don't. Different
  problem. Google-green ≠ ChatGPT-visible.
- A *live-fetch* agent (ChatGPT-User) may render more JS than the *index* crawler (OAI-SearchBot).
  Optimize for the no-JS index crawler; the live agent is a bonus, not the baseline.
- You cannot fully optimize for personalization — ChatGPT injects the user's own history/files as
  private sources. Aim for the deterministic, un-personalized path.
