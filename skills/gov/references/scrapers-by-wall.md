# Scrapers & Bypass Tools by Captcha/Auth Wall

Reference inventory for government-accountability work that hits common bot-protection or paywalls. Each entry was tested against the Rose Lake Capital / Ivanhoe Atlantic investigation (May 2026); update if new tools appear or pricing changes.

## 1. OpenCorporates (HAProxy CAPTCHA Challenge)

Block: HAProxy "We need to verify you are human before you can continue" image-CAPTCHA on every web search and entity page. The `api.opencorporates.com/v0.4/` endpoint returns `{"error":{"message":"Invalid Api Token"}}` without a paid token.

| Tool | What it does | Verdict |
|---|---|---|
| **[Nephylem/OpenCorporates-Scraper](https://github.com/Nephylem/OpenCorporates-Scraper)** | Selenium-driven, 10 logged-in accounts in parallel, signs in to bypass CAPTCHA, CSV output | Needs 10 OC accounts; 2022-vintage, 5 stars; works |
| **[skickar/OpenCorporatesCLI](https://github.com/skickar/OpenCorporatesCLI)** | Python CLI hitting OC public API | Rate-limited without API key, pure-API path |
| **OpenCorporates Pro API** (`api.opencorporates.com/v0.4/`) | Official paid endpoint | ~$50/mo, instant access |
| **The REAL Chrome profile (fcdp) + manual CAPTCHA solve** | User solves the HAProxy challenge once; cookie persists ~1 hour; drive remaining queries via CDP WebSocket | Free, fastest one-off path; tested working May 2026 |

**Best move:** if you have the REAL Chrome profile driven by fcdp and the user can solve one CAPTCHA, drive subsequent queries via `~/tools/fcdp/fcdp js` with `Runtime.evaluate`. Otherwise pay one month of OC Pro and grep the API.

## 2. Bizapedia (ABShield drag-and-drop human verification)

Block: ABShield drag-and-drop CAPTCHA, then force-redirect to `/pro-search-subscription` on every entity page. No public scraper exists.

| Tool | What it does | Verdict |
|---|---|---|
| **[ScraperHub/goodfirms-scraper](https://github.com/ScraperHub/goodfirms-scraper)** | Adaptable pattern using Crawlbase Crawling API for JS render + CAPTCHA + anti-bot | Crawlbase free tier 1,000 req/mo |
| **Bizapedia Pro Subscription** | $12.95/mo, no CAPTCHAs | Cleanest paid path |
| **Wayback Machine** (`web.archive.org/web/*/bizapedia.com/<state>/<entity>.html`) | Cached profile snapshots | Tested for `bizapedia.com/de/rose-lake-capital-llc.html` and `dc/rose-lake-capital-llc.html` — CDX returned empty (not archived). Bizapedia entity pages are rarely indexed |
| **Camoufox via [gov_websites_collector](#3-dc-dlcp-corporate-registry-access-dc-oauth)** | Anti-detect browser used for state SoS sites | Will likely also defeat ABShield since both use behavioral fingerprinting |

## 3. DC DLCP corporate registry (Access DC OAuth)

Block: `corponline.dlcp.dc.gov` redirects all unauthenticated requests to `accessdc.dcra.dc.gov` OAuth login. The legacy `corponline.dcra.dc.gov` is dead (DNS NXDOMAIN).

| Tool | What it does | Verdict |
|---|---|---|
| **[promisingcoder/gov_websites_collector](https://github.com/promisingcoder/gov_websites_collector)** | Python lib + CLI scraping all 50 states + DC SoS via Camoufox anti-detect browser + Playwright + ISP proxy support | MIT licensed; Feb 2026 vintage; on PyPI as `gov-websites-collector` |
| **OpenCorporates `us_dc/<id>` entity pages** | Mirrors DC registrations after their nightly source-data crawl | Subject to OC HAProxy wall — combine with #1 |

**Install (handle PEP 668):**
```bash
pipx install gov-websites-collector
# or, if pipx unavailable:
pip3 install --break-system-packages gov-websites-collector
```

**OC mirror confirmed live for the Rose Lake DC branch:** `opencorporates.com/companies/us_dc/C00007470247` returns Status: Revoked, Branch of Delaware parent, registered address 80 M St SE FL 1 Washington DC 20008, business classification "private equity and venture capital management and holding company", filed 29 Sep 2022 (Initial). 2 inactive officers locked behind OC login.

## 4. Liberia Business Registry (`lbr.gov.lr` hosting suspended)

Block: HTTPS endpoint returns 503/cert error; HTTP returns 301→suspended-account page. Hosting bill unpaid since at least Apr 2026.

| Tool | What it does | Verdict |
|---|---|---|
| **[leitidataportal.org](https://www.leitidataportal.org)** | Liberia EITI's parallel data warehouse | Tested live May 2026: search for "Ivanhoe", "HPX", "Iron" in `/MiningOwnership` returns "No result found" — Ivanhoe Liberia / SMFG / HPX have not filed BO disclosures with LEITI; this is a **compliance gap, not an authentication wall** |
| **`/csvdownload/ActiveLicese`** (note typo) | Year-by-year aggregate license counts for the mining sector | Returns yearly totals only, no company names |
| **Other `/csvdownload/*` endpoints** (`BeneficialOwnership`, `LegalOwenership`, `MiningOwnership`, `OilOwnership`, `Revenue`) | All return 6603-byte 404 HTML page | Endpoint doesn't exist server-side |
| **EITI primary data API** (`api.eiti.org/countries/liberia`) | Returns Drupal CMS HTML, not data API | Not a real API — country profile page only |
| **[NRGI/resourcecontracts.org](https://github.com/NRGI/resourcecontracts.org)** | Curated company-name index for resource concession contracts | Useful for canonical naming but not for ownership |

**The story angle here is the absence of data:** Liberia's 2023 Beneficial Ownership Regulation requires disclosure for all extractive concessionaires, and Ivanhoe Liberia Ltd (Liberian Business Registry #050971031) holds the December 2025 ratified rail/port concession, but it does not appear in the LEITI BO portal as of May 6, 2026. That's prima facie non-compliance.

## Bonus tools (cross-cutting)

| Tool | Use |
|---|---|
| **[companieshouse/company-profile-api](https://github.com/companieshouse/company-profile-api)** | Official UK Companies House API (Java/Spring). Bulk-grep PSCs across UK Friedland-orbit entities (Ivanhoe Atlantic UK Ltd 08248083, etc.) |
| **[OpenOwnership Register](https://register.openownership.org)** | Global UBO aggregator that ingests Companies House, EITI countries, and other registers. Cloudflare-walled to curl but works in real Chrome — search via `/search?q=<name>` |
| **[Camoufox](https://github.com/daijro/camoufox)** | Anti-detect browser used by `gov_websites_collector`. Useful standalone for any site with behavioral fingerprinting |
| **Crawlbase / ScrapingBee / Bright Data** | Commercial CAPTCHA-solving proxies; Crawlbase free tier = 1,000 req/mo |

## Field-tested combo for one-off entity lookups

```
1. The REAL Chrome profile (fcdp) + user solves any first-page CAPTCHA
2. CDP WebSocket Runtime.evaluate to grab DOM/JSON from inside the session
3. For data behind login: gov_websites_collector (DC), Jersey FSC myRegistry account (£0 PDFs), UK Companies House public web (free), DE ICIS direct form submit (free, no captcha after first page)
4. For aggregator coverage: OpenCorporates (paid OR live-Chrome), OpenOwnership Register, EITI country pages
```
