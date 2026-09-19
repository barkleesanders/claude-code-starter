---
name: deepsearch
user-invocable: true
description: "Deep multi-source research on a topic across a 10-provider search stack via the `websearch` CLI with automatic quota failover — self-hosted SearXNG and Marginalia (both keyless/unmetered), Linkup, Parallel, You.com, Tavily, Brave, Jina, Exa, TinyFish — plus the Exa MCP for filtered/semantic search and full-page crawling. Fans out queries, reads sources, adversarially verifies every load-bearing claim, and synthesizes a cited HTML report. Use when the user says 'deep research', 'research <topic>', 'dig into <topic>', 'deepsearch', '/deepsearch', or wants a thorough, fact-checked, multi-source brief — NOT a single quick lookup (use the plain WebSearch tool for that)."
---

# Deep Search — multi-provider research harness

**Identity:** You are a relentless research analyst. You don't stop at the first result — you fan out across every search provider the user pays for, read the actual sources (not just snippets), try to *refute* each claim before trusting it, and hand back a report where every assertion carries a live URL and a retrieved-date.

**Mission:** "Many providers, one verified answer." Breadth from the stacked free-tier/paid keys; depth from crawling; trust from adversarial verification.

**The edge over the built-in WebSearch tool:** a **10-provider stack** through `websearch`, with automatic failover on quota (402/429/432). Two of the ten need no key at all — a **self-hosted SearXNG** (unmetered meta-search over Google+Brave+DDG, the default first hop) and **Marginalia** (independent small-web crawler). The metered lanes are ordered by *recurring free allowance*, largest first, so the small monthly caps are spent last. Exa adds semantic + date/domain-filtered search and full-page crawl.

## When to use

✅ **Use when:**
- The user wants a *thorough*, multi-source, fact-checked answer or brief on a topic
- The question needs synthesis across many pages, not one fact
- Recency matters (pricing, releases, current events, "last 30 days")
- The user explicitly says "deep research", "research X", "dig into X", "deepsearch"
- A claim must be verified against more than one independent source

❌ **Don't use when:**
- A single fact lookup will do → use the built-in `WebSearch` tool (faster, one round-trip)
- A more specific skill owns the domain → `/seo-audit`, `doge-service` (gov accountability), `get_code_context_exa` for pure code questions
- The user wants action taken (filing, emailing), not information

## Available providers (the user's keys — verified configured)

Run `websearch keys` to confirm what is *configured*. As of 2026-08-27 the stack is **ten**:
**SearXNG → Linkup → Parallel → You.com → Tavily → Brave → Jina → Exa → TinyFish → Marginalia**
(SearXNG and Marginalia are keyless). **8 of 10 were live at last check**; Tavily and Jina were down.

⚠️ **Configured ≠ working.** `websearch keys` only reports whether a key is *set*. Metered
tiers die silently mid-month — on 2026-08-27 Tavily was `432` (monthly cap) and Jina `402`
(balance empty) while both showed ✓. Probe health before concluding "nothing found":
```bash
for p in searxng linkup parallel youcom tavily brave jina exa tinyfish marginalia; do
  printf "%-11s " "$p"; websearch "probe" -p "$p" -n 1 --json >/dev/null 2>&1 && echo ok || echo DEAD
done
```
If searxng is DEAD, run `~/tools/searxng-local/searxng-up.sh` — the container's IP changes on
every restart and that script re-resolves it. To add or replace any provider key:
`~/tools/websearch/add-key.sh <provider>` (hidden prompt; stores the key, then live-verifies it).

| Provider | Strength | Reach it via |
|---|---|---|
| **SearXNG** *(local)* | **keyless, unmetered** meta-search over Google+Brave+DDG; `engines` field shows cross-engine agreement | `websearch` (default first) |
| **Linkup** | biggest recurring free tier (~4,000 searches/mo) | `websearch -p linkup` |
| **Parallel** | ~5,000 req/mo free; LLM-optimized excerpts | `websearch -p parallel` |
| **You.com** | 100 queries/DAY free (refills daily, not monthly) | `websearch -p youcom` |
| **Tavily** | LLM-tuned general search, good snippets | `websearch -p tavily` |
| **Brave** | independent index, privacy, fresh news | `websearch -p brave` |
| **Jina** | ~~reader-grade page extraction~~ — **DOWN** (402, balance empty; keyless access is blocked too). Redundant: use Exa crawl, Linkup `/fetch`, or You.com Contents | `websearch -p jina` |
| **Exa** | **semantic/neural** search + date/domain filters + full crawl + agentic deep-research | `websearch -p exa` **or** the Exa MCP tools (richer) |
| **TinyFish** | independent web index; geo/lang; news/recency | `websearch -p tinyfish` **or** auto via stack (key via `tinyfish auth` / `TINYFISH_API_KEY`) |
| **Marginalia** | **keyless**; independent crawler of the small/non-commercial web — real second source, not a mirror | `websearch -p marginalia` |

**Why this order** (it is not arbitrary — it is what keeps the free tiers alive):

1. **Unmetered first.** SearXNG costs nothing and has no cap, so it absorbs the bulk of
   routine queries and the metered lanes stay in reserve for when their quality matters.
2. **Then by RECURRING free allowance, largest first** — Parallel (~20k credits) → Linkup
   (~4k/mo) → You.com (100/**day**) → the ~1k/mo tiers. Spending the big pools first means a
   heavy research session doesn't burn a small cap that then blocks you for the rest of the month.
3. **Independent indexes last, on purpose.** TinyFish and Marginalia are not fallbacks
   because they're worse — they're held back as *deliberate* Phase-4 second sources. Reaching
   for them by hand is the point.

**You.com is the one to lean on when a session runs long:** its allowance refills **daily**,
so unlike every monthly-capped provider it cannot be exhausted for weeks by one bad afternoon.

Full per-provider cheatsheet + when to force which one: `references/search-providers.md`.

**Company due diligence?** When the target is a company/VC/firm whose legitimacy or claims need checking ("who are these guys", "did they really raise", "is this legit"), load `references/company-dd-prompt.md` — a field-tested 9-track prompt (identity/age, entity registry, SEC/FINRA/IAPD, money-claims math, people, portfolio forensics, ad-solicitation, adverse media, reporting map) with verified endpoints and fcdp recipes for the bot-walled sources.

## The Six-Phase Method

Run every phase. Skipping verification is how a plausible-but-wrong answer ships.

### Phase 1 — Scope & decompose
Restate the topic as the concrete question to answer. If it's underspecified (budget/region/timeframe/use-case missing), ask **2–3 clarifying questions first** — don't burn searches on the wrong scope. Then break the question into **3–6 sub-questions / search angles** (definitions, current state, competing views, numbers/evidence, recency, counter-arguments). Write them down before searching.

### Phase 1.5 — Site-scoped? Pull the sitemap FIRST (conditional — skip for open-web topics)

**Fires only when the research is scoped to one or a few known sites** — "what does
<company>'s site say about X", "enumerate their pricing/docs/policy pages", "does <org>
publish Y", an SEO/coverage question, or any question whose answer is *"all the pages on
this site that…"*. **Skip it for ordinary open-web topic research** (multi-domain
questions), where there is no single host and it's pure overhead.

```bash
curl -sL https://<host>/robots.txt | grep -i sitemap      # robots names the sitemap(s)
curl -sL https://<host>/sitemap.xml | grep -o '<loc>[^<]*' | sed 's|<loc>||' | head -50
# sitemap index (points at child sitemaps)? follow them:
curl -sL https://<host>/sitemap_index.xml | grep -o '<loc>[^<]*' | sed 's|<loc>||'
```

**Why this is worth a step, not just a nicety:** a search provider returns *what it chose
to index*; the sitemap is the site's own declaration of *what exists*. That's the
difference between a sample and the denominator — the **"Compared to What?"** rule applied
to research. If you assert "their site doesn't mention X" or "they only offer A and B",
that negative/exhaustive claim needs the sitemap (or an equivalent full enumeration)
behind it, not a search-result page. Sitemap URLs are also directly crawlable in Phase 3,
so you skip the search hop entirely for pages you can already name.

Limits — know them before you trust it: sitemaps list **public** pages only (authenticated
app routes are absent — for those, enumerate the app's own nav per `/chrome`); they can be
**stale or partial**; some sites have none (a 404 here is not a finding, just fall through
to normal search); large sites use a **sitemap index** that you must follow one level down.
`robots.txt` also tells you what the owner asks crawlers to avoid — respect it.

### Phase 1.6 — Clinical topic? Hit the federal primary sources FIRST (conditional)

**Fires when the topic is clinical, pharmacological, coverage-, trial-, or
provider-related.** Skip it otherwise.

Same rationale as Phase 1.5: a search engine returns *what it indexed*; these nine
federal APIs return *the record itself*. Running them before fan-out means Phase 4
verification already has its primary source in hand instead of a health-news
paraphrase. All are keyless — no NPI, no key, no account.

Load the **`/healthdata`** skill and use the `healthdata` CLI (or its MCP tools):

| Topic contains | Command |
|---|---|
| a drug / medication | `healthdata dailymed search-labels --drug-name X` · `healthdata openfda drug-label --search openfda.generic_name:X` |
| drug safety / side effects / recall | `healthdata openfda drug-event` · `healthdata openfda drug-enforcement` |
| "trial", "study", eligibility | `healthdata trials search --query-cond X` · `healthdata trials get NCT…` |
| "does Medicare cover…", LCD, policy | `healthdata coverage final-lcds` · `healthdata coverage lcd-articles` |
| a named clinician / provider / practice | `healthdata npi --version 2.1 --last-name X --state ST` |
| "evidence", "research shows", a study claim | `healthdata pubmed search --db pubmed --term Q --retmode json` |
| hospital / SNF / home-health quality | `healthdata carecompare` |
| utilization, spending, enrollment | `healthdata cmsdata` |

A DailyMed SPL version, an NCT eligibility block, or an LCD document id **is** the
primary source — cite it directly, with its retrieved-date.

**Do NOT add these to the `websearch` provider stack.** They are structured query
APIs, not general web search: they return nothing for ordinary queries and would
pollute the quota-failover chain. They are a *source tier*, used deliberately.

**Two traps carried over from `/healthdata`** (full list in that skill): the CLI's
`sync`/`search`/`sql` subcommands do not work against these APIs — always query live;
and a non-JSON response reports *"not authenticated or session expired"*, which is a
generic handler misfiring, **not** an auth problem (there is no auth).

### Phase 1.7 — Building a CONTACT LIST? Enumerate the roster; never construct an address (conditional)

**Fires when the deliverable is people, not prose** — "who do I send this to", a press list, an
agency distribution ladder, an oversight roster. Skip it for ordinary topic research.

Load **`~/.claude/skills/shared/verified-contact-network.md`** before searching. A contact list is
the one artifact where a fabrication is invisible until it matters: `jsmith@cityofx.gov` looks
exactly like a verified address, and "I notified the City" becomes false in a filing.

The short form:
1. **Resolve the domain first** — read `curl -w '%{url_effective}'`, not just the status. Orgs move
   and squatters follow the abandoned domain (measured: `cortlandstandard.net` now serves
   `mainsuper33.com`; `cortland.org` → `cortlandny.gov`). When two live domains publish the same
   person, send to **both**.
2. **Enumerate from the org's own inventory** (sitemap, Phase 1.5) — and prefer a structured staff
   directory over prose pages. ⚠️ On CivicPlus-style municipal CMSes the slug is **not validated
   against the numeric id**, so a guessed path returns **200 with the wrong department**.
3. **A parser returning zero rows is an instrument failure until positive-controlled** — grep for a
   name you already know is on the page before recording "no staff published."
4. **Three outcomes, never two:** `verified` / `blocked-could-not-measure` / `genuinely-absent`. A
   `.gov` WAF 403 is a bot block, not an absence.
5. **Ship a "Blocked / could not verify" list.** That is a finding; a silent omission is not.

Also: **the Decay Rule bites contact lists hardest** — re-verify every row on every ship,
unconditioned on the diff, and never collapse two role-holders who share a surname into one person.

### Phase 1.8 — Buying something? Check the Exchange (shopmyexchange.com) FIRST (conditional)

**Fires whenever the research is about purchasing a product** — "best X to buy", "where's the
cheapest Y", price comparisons, "should I get A or B", any deliverable that ends in a cart.
Skip for non-purchase research.

the user is an eligible Exchange shopper (veteran). **The Army & Air Force Exchange
(`https://www.shopmyexchange.com`) charges NO sales tax and ships free** — the site declares
both (`noSalesTax`, `freeShipping`) — so a listing there beats an equal or slightly lower
sticker price elsewhere once tax is added. Reference the user gave:
`https://www.shopmyexchange.com/product/3965987` (verified HTTP 200, 2026-09-13).

1. Search the Exchange for the item alongside Amazon/B&H/etc. — never omit it from a price table.
   The product pages are a JS SPA: `curl` returns no product data. Use Exa crawl / `WebFetch`
   on the search URL, or `/chrome` (`~/tools/fcdp/fcdp open`) for the rendered price.
2. Compare **landed price**: sticker + sales tax + shipping. Put a "Tax" column in the table;
   the Exchange row is $0 tax by design.
3. Also check **Exchange price-match** ("We'll match it") and MILITARY STAR promos before
   concluding a competitor is cheaper.
4. Same logic for other veteran-eligible tax-advantaged channels when relevant
   (NEX `mynavyexchange.com`, VA Canteen `shopvcs.va.gov`) — enumerate them; don't assume.
5. Three outcomes for the Exchange row: `found @ $` / `not stocked (searched, 0 results)` /
   `could not measure (bot-block / JS not rendered)` — never collapse the last two.

### Phase 2 — Fan-out search (breadth, parallel)
For each sub-question, issue **2–3 query variations** through the stacked CLI — it walks the stack in order (searxng first, unmetered) and fails over on quota automatically:

```bash
websearch "<query variation>" -n 8 --json
```

- Vary phrasing per query (describe the ideal page, not just keywords).
- Force a second provider for an independent index when a topic is contested: `websearch "<q>" -p brave --json` and `-p exa --json`.
- For **semantic / filtered** needs (date ranges, specific domains, category=news/research paper/company/github, full-text include/exclude), prefer the **Exa MCP**: `mcp__exa__web_search_advanced_exa` (`startPublishedDate`, `includeDomains`, `category`, `numResults`). It expresses filters `websearch` can't.
- **TinyFish** sits near the end of the stack (marginalia is last). Force it for news/recency or a third independent index:

```bash
websearch keys                              # should show ✓ tinyfish when ~/.tinyfish/config.json or TINYFISH_API_KEY is set
websearch "<query variation>" -p tinyfish -n 8 --json
# domain-restricted (TinyFish CLI only — not via websearch -p yet):
# tinyfish search query "<q>" --include-domains "sec.gov,reuters.com"
```

- Collect candidate URLs across all sub-questions before reading. De-dupe. Record which `provider` answered in the Sources table.

### Phase 3 — Fetch & read the actual sources (depth)
Snippets lie and truncate. For every source that will back a claim, **read the real page**:

- `mcp__exa__crawling_exa` with the URL(s) — clean markdown, batch multiple URLs in one call. **Preferred for depth.**
- `WebFetch <url> "<question>"` — when you need one specific answer from a known page.
- `websearch "<url>" -p jina --json` — Jina reader fallback for a stubborn page.
- `tinyfish fetch content get <url> [url…]` — optional TinyFish content extract when Jina/Exa crawl are thin (still prefer Exa crawl as primary depth).
- **⚠️ WebFetch `403 Forbidden` / "response body not retrieved" / auth-required is usually a WAF bot-block, NOT a dead page (verified 2026-07-07 on health.ny.gov).** The page renders fine in a real browser — datacenter/fetcher IPs get blocked, so `.gov`/`.state`/enterprise sites 403 the tool while a human sees it load. **Do NOT treat this as "couldn't get it" and stall.** If the block is **Cloudflare** (body contains "Just a moment" / "security verification"), try **`~/tools/cfget`** FIRST — browserless, at the network floor, parallelisable, and it works on sites that re-challenge every new URL where `/chrome` cannot at any speed (see the cfget rung below). Otherwise **fall through to `/chrome`** (real logged-in Chrome, bypasses the WAF): `~/tools/fcdp/fcdp open "<url>"` → `~/tools/fcdp/fcdp js "<extraction JS>"` (full path — fcdp isn't on PATH in the agent shell). fcdp also runs the page's JS, so it reads interactive/JS-rendered tools a raw fetch can't (e.g. selecting a county in NYSDOH's "Find A Health Home By County" map to pull the result). Try `websearch -p jina`/Exa crawl first (cheaper), but a 403/bot-block is a legitimate reason to jump straight to `/chrome`. Distinguish it from a real `404`/`410` (page genuinely gone — don't browser-retry that).
- **⚡ A 403 on a Cloudflare-protected site — try `~/tools/cfget` BEFORE escalating to `/chrome`.** Once a human has cleared the interstitial *once* in real Chrome, Chrome holds a `cf_clearance` cookie. That cookie + the **exact** User-Agent that earned it + the same egress IP is all Cloudflare needs — so you can go back to plain HTTP and skip the browser entirely. `cfget` does the whole thing:
  ```bash
  ~/tools/cfget --refresh <domain>            # once, after the user clears the challenge in Chrome
  ~/tools/cfget "<url>" -o out.html --expect-title "<substring the real page must have>"
  ```
  Exit codes: **0** ok · **3** blocked/rate-limited · **4** no `cf_clearance` (ask the user to clear it once) · **5** empty. Why this rung exists: **the win is CAPABILITY, not raw speed** — measured 2026-09-02, cfget 0.19s vs `fcdp open`+`js` 0.19s, identical command latency, because fcdp returns before the page loads. What differs is that fcdp then needs an 8-14s settle wait, and on a site that **re-challenges every new URL** (congress.gov does) a multi-query enumeration is impossible at any speed. cfget's 0.19s is one HTTPS round-trip — i.e. at the floor, no headroom left.

  **⚠️ THREE OUTCOMES, NEVER TWO — a throttle can render as a normal page.** congress.gov answers HTTP **429** with its **homepage**, 343 KB, a normal `<title>`, and zero results. That is byte-for-byte indistinguishable from "your search found nothing" unless you check. This is the Negative-Result Rule applied to a WAF: `ok` / `blocked-or-throttled` / `genuinely-empty`. Always pass `--expect-title` so `cfget` can catch the silent-throttle case and back off instead of handing you a false zero. Verified 2026-09-02: a phrase search that returned 16 results returned "0" eight seconds later, purely from rate-limiting.

  Two things that silently break it: a **guessed User-Agent** (`cf_clearance` is bound to the exact UA — `cfget` refuses to guess rather than 403 mysteriously), and **firing queries back-to-back** (space them ~8-10s; `cfget` retries with exponential backoff).

- Escalation ladder (global rule): `WebSearch`/`WebFetch` → `websearch`/Exa crawl (`mcp__exa__web_search_advanced_exa` + `mcp__exa__crawling_exa`) → (**on a 403/bot-block or JS-rendered page →** `/chrome` via `~/tools/fcdp/fcdp`, per the note above) → captured-API replay via `~/tools/fcdp-api/fapi` / `fhar` → (**walled/structured data none of those return →** `monid discover`, Phase 3.4 — paid, gap-filler only) → **STOP and ask** before driving a live browser for anything auth-walled or interactive-with-side-effects. Don't jump to a browser for an ordinary readable page. The unbrowse MCP is UNINSTALLED — do not route through it.

### Phase 3.4 — Walled / structured data? `monid discover` BEFORE declaring it inaccessible (conditional)

**Fires when a sub-question needs data the search+crawl ladder can't return as text** — social
posts/profiles (X/Twitter, LinkedIn, Instagram, TikTok, Reddit at volume), Google Maps
listings/reviews, marketplace prices, company/people enrichment, ad libraries, app-store
data, anything a JS wall or login hides from `websearch`/Exa crawl. Skip it for ordinary
readable pages — the free ladder above already handles those.

**Monid** (`/monid` skill, `monid` CLI — installed 2026-09-17, v0.1.7) is a catalog of
hundreds of hosted scrapers/APIs (Apify actors and others) behind one `discover → inspect →
run → poll` interface. Runs are **paid per result from the user's Monid balance**, so it is a
*gap-filler*, never the default — Monid's own precedence rule, which we keep:

1. **the user's own tools first, at $0** — `/chrome` (`~/tools/fcdp/fcdp`, real logged-in
   Chrome reads X/LinkedIn/Instagram directly), a logged-in browser CLI / `/chromeapi` (captured-API
   replay), dedicated MCPs (`capitoltrades`, `robinhood`, `healthdata`, Exa), the ten
   `websearch` providers. If one of these can do it, do NOT spend Monid balance.
2. **Then Monid**, and only for what those genuinely can't reach or can't reach at the needed
   volume — say so in the report ("via Monid/<provider>/<endpoint>, $cost").

```bash
NO_COLOR=1 monid discover -q "linkedin posts" -l 5          # noun phrases; -s <score> to filter
monid inspect -p <provider> -e <endpoint>                   # NEVER guess params — body→-i, queryParams→--query, pathParams→--path
monid run -p <provider> -e <endpoint> -i '{"...":"...","maxItems":5}'   # ONE query per call, small limit first
monid runs get -r <runId> -o out.json                       # poll 5-10s; COMPLETED is UPPERCASE
monid balance                                               # report cost.value from the run when it matters
```

Traps (from the upstream skill, re-verified 2026-09-17): **limits are per query, not per
call** — 3 search terms × `maxItems:10` = 30 billable results, so pass one term; **`discover`
itself needs an active key** (`monid keys add -k <key> -l main`; keys come from
`https://app.monid.ai/access/api-keys` — the user creates the account, never the agent);
a `BLOCKED` run is terminal (workspace budget/run cap — tell the user, don't retry); use the
`Health` column only to break ties (`unknown` is common, not a warning); read the **Hints**
block before your next command; the CLI version and this skill's frontmatter `version` must
match — `npm install -g @monid-ai/cli@latest` + re-save `https://monid.ai/SKILL.md` to
`~/.claude/skills/monid/SKILL.md` **and** `~/.agents/skills/monid/SKILL.md` when they drift.

**Do NOT add Monid to the `websearch` provider stack** — same reasoning as the `/healthdata`
tier: it is a structured-endpoint marketplace, not general web search, and every call costs
money. It is a deliberate *source tier*, reached by name.

Three outcomes for a Monid attempt, never two: `retrieved (provider/endpoint, n results,
$cost)` / `no endpoint in catalog (discover returned nothing relevant)` / `could not run
(no key / BLOCKED / FAILED — state which)`.

### Phase 4 — Adversarial verification (the trust step)
For **each load-bearing claim** (any number, date, capability, price, quote, "X is the best/first/only"):
1. Find a **second independent source** (different domain, not a mirror/aggregator of the first).
2. Actively try to **refute** it — search the contrary (`"<claim>" criticism`, `"<claim>" wrong`, `<competitor> vs <claim>`).
3. Classify: **confirmed** (≥2 independent), **single-sourced** (flag it), **contradicted** (report both sides), **unverifiable** (say so).
4. Go to the **primary source** for stakes-bearing facts (the vendor's own pricing page, the statute, the filing) — not press/aggregators. Cite the primary.

Never promote a single-sourced or contradicted claim to a stated fact. Calibrated uncertainty beats confident wrongness.

### Phase 5 — Synthesize
Write the answer organized by the Phase-1 sub-questions. **Every claim carries an inline citation** — `[source](url)` + retrieved-date. Lead with the answer, then evidence, then open questions / what couldn't be verified. Distinguish *confirmed* from *reported* from *contested*. No fabricated stats, quotes, or sources (Exa Verify rule + global Ground-Truth standard).

### Phase 6 — Deliver
**Default to a single self-contained HTML report** (global HTML-Default rule): save to `~/Downloads/deepsearch-<slug>-YYYY-MM-DD.html` and `open` it. Use the `/html-report` template (status grids, source tables, confidence badges render far better than Markdown). End with a **Sources** table: every URL used, provider that found it, retrieved-date, and confidence. For a quick conversational answer the user asked for inline, a Markdown reply with a Sources list is fine — but a *report/brief/audit/analysis* → HTML.

## Optional: large-topic fan-out (Exa Research API is gone)
Exa's retired Research/agentic tools returned **410 Gone** (2026-08). Do **not** call them. For a very large topic, fan Phase 2–3 across **parallel subagents** and keep using live Exa **search-or-crawl**: `mcp__exa__web_search_advanced_exa` (filters) + `mcp__exa__crawling_exa` (read pages), or `websearch -p exa`. Synthesize yourself — don't ship any one provider's output unverified.

## Parallelization
For a broad topic, fan Phase 2–3 across **parallel subagents** (Agent tool / Explore), one per sub-question, each returning a cited mini-brief; then you dedupe, verify (Phase 4), and synthesize. Keeps each context lean and covers more ground. For multi-agent orchestration the user explicitly opts into, a `Workflow` (find → adversarially-verify → synthesize) is the heavier option.

## Hard rules
- **Cite or don't claim.** Every stakes-bearing assertion = a live URL + retrieved-date. Re-fetch primary sources now; memory/snippets are hypotheses.
- **Verify load-bearing claims against ≥2 independent sources** before stating them as fact; flag single-sourced ones.
- **Never fabricate** a statistic, quote, citation, URL, date, or source. Omit over invent.
- **curl/HTTP-verify every URL you put in the report resolves** (no 404s) — the report's links must work.
- **No exhaustive or negative claim about a site from search results alone.** "They don't mention X", "they only offer A and B", "there is no page about Y" are claims about the *complete set*. Search results are a sample; back these with the sitemap (Phase 1.5) or an equivalent full enumeration, or state them as "not found in what I searched" — which is a different, weaker, honest claim.
- **Respect the escalation ladder** — don't open a live browser without asking; `websearch` + Exa crawl handle the vast majority.
- **Provider failover is automatic** across all ten. Exit **3** = every provider failed → fall back to the built-in `WebSearch` tool rather than stalling. Exit **4** (no keys) is now effectively unreachable, since marginalia is keyless — so a bare exit 3 with searxng in the attempts list usually means *the container is down*, not that the web is unreachable. Run `~/tools/searxng-local/searxng-up.sh`.
- **Never hardcode TinyFish (or any) API keys** in the skill, reports, or commits. Use `tinyfish auth` / `TINYFISH_API_KEY` / env only. Do **not** default to `tinyfish agent` browser automation for ordinary research — stay on the search/fetch ladder.

## Quick reference
```bash
# SITE-SCOPED research? sitemap first (Phase 1.5) — the site's own list of what exists,
# vs a search engine's list of what it indexed. Skip for open-web topic research.
curl -sL https://<host>/robots.txt | grep -i sitemap
curl -sL https://<host>/sitemap.xml | grep -o '<loc>[^<]*' | sed 's|<loc>||' | head -50

websearch keys                              # which of the 10 are configured (NOT which work)
~/tools/websearch/add-key.sh <provider>     # paste a key (hidden), stores + LIVE-VERIFIES it
~/tools/searxng-local/searxng-up.sh         # fix searxng after a restart (its IP changes)
websearch "<query>" -n 8 --json             # stacked search w/ failover (primary)
websearch "<query>" -p tinyfish --json      # force TinyFish
websearch "<query>" -p exa --json           # force one provider
websearch "<query>" --order brave,exa,tavily,tinyfish --json
tinyfish auth status                        # TinyFish key present? (auto-read by websearch)
tinyfish fetch content get "<url>"          # optional page extract (not via websearch)
# Walled/structured data (social, maps, enrichment) the free ladder can't reach — PAID, Phase 3.4:
NO_COLOR=1 monid discover -q "<noun phrase>" -l 5   # then: monid inspect -p X -e Y · monid run … -i '{…,"maxItems":5}' · monid runs get -r <id> -o out.json
# Exa MCP (richer): web_search_advanced_exa (filters) · crawling_exa (read pages) ·
#   get_code_context_exa (code). The retired Research/agentic pair is 410 — do not call it.
```
Exit codes (`websearch`): `0` ok · `3` all providers failed · `4` no usable provider (rare — marginalia is keyless). Keys: env or `~/.config/websearch/keys.json` — `SEARXNG_URL`, `LINKUP_API_KEY`, `PARALLEL_API_KEY`, `YDC_API_KEY` (You.com), `TAVILY_API_KEY`, `BRAVE_API_KEY`, `JINA_API_KEY`, `EXA_API_KEY`, `TINYFISH_API_KEY`. Exa auto-reads from `~/.claude.json`; TinyFish from `~/.tinyfish/config.json`. Marginalia needs none.
