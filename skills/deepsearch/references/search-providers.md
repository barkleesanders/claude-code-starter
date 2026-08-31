# Search providers — when to force which one

**Primary stack** runs through the `websearch` CLI (`~/.local/bin/websearch`), which by default tries providers in order and **fails over on quota** (HTTP 402/429/432) or a transient error. Exa is also reachable through the richer **Exa MCP** tools. Confirm stacked config with `websearch keys`.

## The stack (default priority: **searxng** → **linkup** → **parallel** → **youcom** → tavily → brave → jina → exa → tinyfish → **marginalia**)

⚠️ **`websearch keys` reports CONFIGURED, not WORKING.** A key can be set and still be
quota-dead. Metered tiers exhaust silently mid-month. Before trusting a "no results"
conclusion, probe health per provider (Negative-Result Rule):

```bash
for p in searxng linkup parallel youcom tavily brave jina exa tinyfish marginalia; do
  printf "%-11s " "$p"; websearch "probe" -p "$p" -n 1 --json >/dev/null 2>&1 && echo ok || echo DEAD
done
```

**Verified 2026-08-27: 8 of 10 LIVE.** searxng / linkup / parallel / youcom / brave /
exa / tinyfish / marginalia answered. Down: tavily `432` (monthly cap — resets the 1st),
jina `402` (`InsufficientBalanceError`, needs a new key).

⚠️ **A dummy-key probe does NOT validate a contract.** Probing linkup/parallel/youcom with a
fake key returned 401/403, which looked like "endpoint correct, key missing" — and was wrong
for two of the three. You.com's legacy host 403s a *real* key too (the host was wrong), and
Parallel 401s before body validation runs, hiding a malformed body that later 422'd. A dummy
probe proves only "something is listening and rejects anonymous callers". Say **endpoint
reachable**, never **contract correct**, until a real key returns 200.

### SearXNG (self-hosted) — `websearch -p searxng` *(default first hop)*
- **Best for:** the default sweep. **Keyless and unmetered** — it absorbs volume so the
  metered free tiers below stay in reserve for when they matter.
- Meta-search: one query fans out to Google, Brave and DuckDuckGo and returns merged,
  de-duplicated results. Each hit carries an `engines` array naming which upstreams found
  it — a free **independent-corroboration signal** for Phase 4 verification.
- **Local instance:** container `searxng-local`, config `~/tools/searxng-local/settings.yml`.
  `~/tools/searxng-local/searxng-up.sh` starts it, health-checks the JSON API, and rewrites
  `SEARXNG_URL` in `~/.config/websearch/keys.json` to the container's **current** IP.
  Run it if searxng starts failing — apple/container has no restart policy and hands out a
  **fresh 192.168.64.x address on every start** (observed live: `.2` → `.3`), so a stale URL
  is the expected failure. A LaunchAgent (`com.barklee.searxng-local`) runs it at login and hourly.
- **Public instances will not work:** `format=json` must be in `search.formats` in
  `settings.yml`, and public instances disable it. The docs say that returns `403`; in
  practice `searx.be` answers **`200` with HTML**, so the adapter treats an HTML body as the
  same misconfiguration and says so.
- Not a separate index — if a claim needs a source independent of Google/Brave/DDG, reach
  for exa, tinyfish or marginalia instead.

### Linkup — `websearch -p linkup` *(adapter live; needs a key)*
- **Largest recurring free tier found:** ~$20/month of credit, refilled monthly, at
  $0.005/search on `depth:"standard"` ⇒ **~4,000 searches/month**
  ([pricing](https://www.linkup.so/pricing) + [docs pricing](https://docs.linkup.so/pages/documentation/platform/pricing), retrieved 2026-08-27).
- **Sign up with a professional email** (`help@example.com`) — the monthly top-up is
  conditioned on it. Then `~/tools/websearch/add-key.sh linkup`.
- Contract from the vendor's own OpenAPI (`https://api.linkup.so/v1/openapi.json`):
  `POST /v1/search`, `Authorization: Bearer`, required `q` + `depth` + `outputType`.
  The adapter pins `depth:"standard"` — **never `"deep"`, which is 10x the price** ($0.05).
- `outputType:"searchResults"` → `[{name, url, content}]`.

### Parallel — `websearch -p parallel` *(adapter live; needs a key)*
- **~5,000 requests/month free** ($5 monthly credit at $1/1,000 in `fast`/`turbo` mode)
  ([pricing](https://parallel.ai/pricing) + [docs pricing](https://docs.parallel.ai/getting-started/pricing), retrieved 2026-08-27).
- `POST /v1/search`, header `x-api-key`, body `{objective, search_queries, mode}`.
  The adapter pins `mode:"fast"` — same $1/1k as turbo but higher quality; `basic`/`advanced`
  are 5x. Response `{results:[{url, title, publish_date, excerpts[]}]}` — **`excerpts` is an
  ARRAY**, joined by the adapter.
- Key at https://platform.parallel.ai/settings?tab=api-keys — a **Default API Key already
  exists at signup**; click "View Default API Key" rather than creating one. Then
  `~/tools/websearch/add-key.sh parallel`.
- ⚠️ **Body accepts ONLY `objective` / `search_queries` / `mode`.** Sending `max_results`
  returns **422 `extra_forbidden`** — trim the count client-side. A **422 means the key is
  fine and the body is wrong**; do not misread it as an auth failure.
- ⚠️ **Credit reality differs from the pricing page:** onboarding awards **$20 (20,000
  searches) that EXPIRES IN 60 DAYS**, and the settings page states *"Add a payment method to
  become eligible for free monthly credits"* — so the recurring monthly credit **requires a
  card on file**, which is not set up.

### You.com — `websearch -p youcom` *(adapter live; needs a key)*
- **The only DAILY recurring free tier here: 100 queries/day, no credit card**, plus
  **$100 of starting credit** ([pricing](https://you.com/pricing), retrieved 2026-08-27).
  That is ~3,000/month that refills every day rather than monthly — it cannot be
  exhausted for the rest of a month by one heavy research session, which the
  monthly-capped providers can.
- `GET https://api.ydc-index.io/v1/search?query=…&count=…`, header **`X-API-Key`**.
  Env var is **`YDC_API_KEY`** (You.com's own canonical name, not `YOUCOM_*`).
- **Response nests under `results.web[]`**, not a flat `results` array; each hit has
  `snippets[]` (an array) with `description` as the fallback. The adapter handles both.
- Key at https://you.com/platform, then `~/tools/websearch/add-key.sh youcom`.
- ⚠️ **Host is `api.you.com`, NOT `api.ydc-index.io`.** The docs still reference the latter;
  it is the legacy host and rejects current `ydc-sk-…` keys with 403 (same key: 403 there,
  200 on `api.you.com`).

### Tavily — `websearch -p tavily`
- **Best for:** general LLM-oriented search with clean, relevant snippets — reach for it when
  searxng's raw meta-search results are noisy and you want LLM-tuned ranking.
- **Free tier: 1,000 credits/month, resetting on the 1st** ([pricing](https://www.tavily.com/pricing), retrieved 2026-08-27).
  A `432` means that cap is spent, **not** that the key is bad — it comes back on the 1st.
- No longer the first hop (searxng now absorbs volume ahead of it).

### Brave — `websearch -p brave`
- **Best for:** an **independent index** (not Google/Bing-derived), fresh news, privacy-sensitive topics, and as the *second* source in adversarial verification (Phase 4) so you're not citing two mirrors of the same index.
- Reach for it when a topic is contested or Tavily's results look like one echo chamber.

### Jina — `websearch -p jina`
- **Best for:** **reader-grade page extraction** — clean full text of a specific page. Use as a page-reader fallback when `crawling_exa`/`WebFetch` choke on a stubborn page.
- Also a search provider, but its standout value is the reader.

### Exa — `websearch -p exa` OR the Exa MCP (richer)
- **Best for:** **semantic / neural** search (describe the ideal page, not keywords), plus filters the keyword tools can't express.
- Prefer the **MCP** over the CLI when you need:
  - `mcp__exa__web_search_advanced_exa` — `startPublishedDate`/`endPublishedDate` (recency), `includeDomains`/`excludeDomains`, `includeText`/`excludeText`, `category` (`news`/`research paper`/`company`/`github`/`pdf`/`financial report`/`people`), `numResults`, `subpages`.
  - `mcp__exa__crawling_exa` — read full page content as markdown; batch many URLs in one call (Phase 3 depth).
  - `mcp__exa__get_code_context_exa` — API/library/code questions.
  - `mcp__exa__company_research_exa` / `people_search_exa` — entity lookups.
  - Exa's retired Research/agentic pair is **410 Gone** — do not call it. Fan a large topic across parallel subagents + the search/crawl tools above.

### TinyFish — `websearch -p tinyfish` *(last in default failover)*
- **Best for:** an **independent web index** for news/recency, contested topics that need a non-Tavily/non-Brave index, geo/language-biased results (`TINYFISH_LOCATION` / `TINYFISH_LANGUAGE`, default `US`/`en`).
- **Position:** last hop in auto-failover so the free/stacked keys answer first; force with `-p tinyfish` when you want TinyFish specifically.
- **Auth (auto-loaded):** env `TINYFISH_API_KEY`, or `~/.config/websearch/keys.json`, or `~/.tinyfish/config.json` `{ "api_key": "…" }` from `tinyfish auth set` / `tinyfish auth login`. Confirm: `websearch keys` → `✓ tinyfish`. **Never hardcode `sk-tinyfish-*` in skills, reports, or git.**
- **Via websearch (preferred for deepsearch):**
  ```bash
  websearch "latest FIFA World Cup news" -p tinyfish -n 8 --json
  websearch "…" --order tinyfish,brave --json   # TinyFish first for this call only
  ```
- **Native CLI extras** (domain include/exclude, fetch — not all wired into `websearch` yet):
  ```bash
  tinyfish search query "…" --include-domains "reuters.com,apnews.com"
  tinyfish fetch content get "https://example.com/article"
  ```
- **Do not** use `tinyfish agent` / browser automation as a deepsearch default — stay on search → fetch → verify; escalate to `/chrome` only on the global browser ladder.
- Record `provider: tinyfish` in the Sources table when `websearch` reports that provider.

### Marginalia — `websearch -p marginalia` *(keyless, last in failover)*
- **Best for:** the **small / non-commercial web** — independent blogs, personal sites,
  academic and hobbyist pages that Google-derived indexes bury under SEO content.
- **No key required at all** (`https://api.marginalia.nu/public/search/<q>`). It is genuinely
  independent (own crawler), which makes it a real second source in Phase 4 — not a mirror.
- **Do not use it as a general first hop.** Coverage of mainstream/news/commercial pages is
  deliberately thin; it is a complement, not a replacement.
- Results are **CC-BY-NC-SA** — attribute if quoted.

## Picking providers by task

| Task | Use |
|---|---|
| Add / replace a provider key (stores + live-verifies) | `~/tools/websearch/add-key.sh <provider>` |
| Broad first sweep of a sub-question | `websearch "<q>" -n 8 --json` (stacked → searxng first, unmetered) |
| Preserve metered quota on a long research run | `websearch "<q>" -p searxng -n 10 --json` |
| Indie / small-web / non-SEO sources | `websearch "<q>" -p marginalia --json` |
| Independent 2nd source for verification | `websearch "<q>" -p brave --json` + `-p exa` |
| Independent 3rd index / news / force TinyFish | `websearch "<q>" -p tinyfish -n 8 --json` |
| Recency window / date filter | Exa MCP `web_search_advanced_exa` with `startPublishedDate` |
| Restrict to / exclude domains | Exa MCP (richer) **or** `tinyfish search query` `--include-domains` / `--exclude-domains` |
| Read the full text of a page | `mcp__exa__crawling_exa` (batch) → `WebFetch` → `websearch -p jina` → `tinyfish fetch content get` |
| Code / API / SDK question | `mcp__exa__get_code_context_exa` (or the `/context7` MCP) |
| Company / person entity | Exa MCP `company_research_exa` / `people_search_exa` |
| Huge topic, want a server-side agent pass | Parallel subagents + Exa MCP search/crawl (`web_search_advanced_exa` / `crawling_exa`). The retired Research/agentic pair is 410 — do not call it. |

## Cost traps (money, not quota)

- **Linkup `depth`**: the adapter pins `"standard"` ($0.005). **`"deep"` is $0.05 — 10x.**
  Never switch to deep casually; ~4,000 searches becomes ~400.
- **Parallel `mode`**: adapter pins `"fast"`. `fast` and `turbo` bill $1/1k; **`basic` and
  `advanced` are $5/1k — 5x.**
- **Parallel's "spend limit" does NOT limit spend.** Verbatim from its own dialog:
  *"Organization admins receive an email when monthly spend for this app reaches the amount
  you set. **API requests are not blocked.**"* It is an alert. The control that actually
  bounds spend is **`Auto-reload: Off`** on `settings?tab=billing` — with it off the account
  is prepaid-only and the card cannot be auto-charged. Verify that toggle before trusting any
  spend claim.
- **Expiries**: Parallel's $20 signup bonus expires ~2026-10-26. Linkup's monthly refill is
  unproven on a Gmail signup. Both are dated assumptions — re-check, don't inherit.

## Failure handling
- `websearch` exit **3** = all stacked providers exhausted (including TinyFish if keyed) → fall back to the built-in `WebSearch` tool; note the degradation.
- exit **4** = no stacked keys found → check `websearch keys` / `~/.config/websearch/keys.json` / `tinyfish auth status`.
- A single provider erroring is normal — the CLI fails over. Only worry when it exits 3/4.
- Quotas reset over time (monthly free tiers); a 429 today may clear tomorrow.
- TinyFish auth missing: `tinyfish auth login --source cli` or `echo "$TINYFISH_API_KEY" | tinyfish auth set` (user must supply the key — never invent one).

## Adding a provider — what counts as proof

A new adapter is **not** verified until a **real key returns HTTP 200 with parsed results**.

⚠️ **A dummy-key probe proves almost nothing.** Probing with a fake key and getting
401/403 instead of 404 feels like "endpoint and auth shape confirmed" — it is not, and it
was wrong for two of three adapters added on 2026-08-27:
- **You.com**: the legacy host `api.ydc-index.io` returns 403 for a *dummy* key **and** for a
  *real* one. The 403 could not distinguish "right host, bad key" from "wrong host". The
  working host is `api.you.com/v1/search`.
- **Parallel**: a dummy key is rejected at auth *before* body validation runs, so a malformed
  body stayed invisible until a real key surfaced **422 `extra_forbidden`** on `max_results`.

So: say **"endpoint reachable"** after a dummy probe; say **"contract verified"** only after a
real 200. And read status codes precisely — **422 means the key is fine and the body is
wrong**; the error body usually names the offending field.

Checklist for a new provider: adapter in `PROVIDERS` → `KEY_ENV` entry → `SIGNUP` line →
position in `DEFAULT_ORDER` by recurring free allowance → `add-key.sh` case → real-key 200 →
update this file and the SKILL table.

## Output shape (for parsing in a harness)
`websearch … --json` →
```json
{ "query": "...", "provider": "tavily", "count": 5,
  "attempts": [ ... ],
  "results": [ { "title": "...", "url": "https://...", "snippet": "..." } ] }
```
`provider` tells you which key actually answered (record it in the Sources table). `attempts` lists providers tried+skipped on failover.

When TinyFish answers through `websearch`, the payload is the same shape with `"provider": "tinyfish"` and each result `"source": "tinyfish"`.
