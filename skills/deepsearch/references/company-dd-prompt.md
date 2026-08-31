# Company Due-Diligence Prompt (`company-dd`)

**What this is:** a reusable investigation prompt that drives `/deepsearch` (multi-provider research + adversarial verification) and `/doge-service` (authority mapping + exact reporting URLs), escalating to `/chrome` (fcdp) for bot-walled sources. Built 2026-07-10 from the Roundtable Ventures investigation; grounded in how professionals do it: GIJN's corporate-research methodology, the ILPA DDQ domains LPs use on fund managers, ACFE fraud red-flag framing, and the FinCEN CDD beneficial-ownership standard (identify 25%+ owners + one control person).

**How to invoke:** `/deepsearch run company-dd on <company name or URL>` — or paste the prompt block below with TARGET filled in. Works on VC firms, startups, agencies, "investment clubs," coaching outfits — any company whose legitimacy/claims need checking.

---

## THE PROMPT

> Investigate **TARGET = <company name + domain>** with full due-diligence rigor. Load `/deepsearch` and `/doge-service` methods. Run every track below; classify every finding as **CONFIRMED (≥2 independent sources)** / **SELF-REPORTED** / **SINGLE-SOURCED** / **CONTRADICTED** / **UNVERIFIABLE**. Never promote self-reported marketing to fact. Absence of a filing is not illegal per se — the finding is the *gap between marketing claims and the public record*. Deliver an HTML report (verdict grid → timeline → claims-vs-record → people table → red flags/mitigants → reporting authority map → sources table with confidence + retrieved dates). curl-verify every report URL (a WAF 403 with a real-browser load is OK — note it).

### Track 1 — Identity & age (cheap, do first)
- `whois <domain>` — creation date, registrant org/state, registrar.
- Wayback CDX month-collapsed timeline: `https://web.archive.org/cdx/search/cdx?url=<domain>&output=json&fl=timestamp,statuscode&collapse=timestamp:6` — **look for ownership gaps**: snapshots long before the WHOIS creation date = a *prior unrelated owner* (read an old capture to confirm; don't attribute its history to the current company).
- LinkedIn company page: "Founded" year, employee band, associated-member count (compare against team-size claims later).

### Track 2 — Legal entity & registered footprint
- State SOS registry (CA: bizfileonline.sos.ca.gov — **API 403s even in-browser; drive the UI via fcdp**: `fcdp open` the search page → set input via native setter + `dispatchEvent(new Event('input'))` → Enter → scrape `document.body.innerText`; click the row to expand: filing date, status, standings, principal address, agent). Other states: Delaware ICIS, OpenCorporates (needs API token; its pages are also indexed by search engines — `websearch "opencorporates \"<name>\""`).
- **Exact entity name vs marketing name** ("The X LLC" vs "X"); note if a fictitious-business-name (county FBN) filing would be required and whether checked.
- **Characterize the principal address**: Redfin/Zillow/Google. A single-family house ≠ fraud, but weighs against "institutional firm" branding. Note who the registered agent is (a founder at a home address = self-filed micro entity).
- Related entities: search the SOS for sibling/fund entities (LP, GP, "Fund I", "Management", "SPV").

### Track 3 — Regulatory footprint (the hard evidence layer)
- **SEC EDGAR full-text** (Form D is the tell for any real US fund raise): `curl "https://efts.sec.gov/LATEST/search-index?q=%22<name>%22" -H "User-Agent: research <email>"` — also query the domain string. Zero hits since 2001 = no Form D under that name (caveat: SPVs file under other names).
- **SEC/state adviser registry (IAPD — covers RIAs, state advisers, AND exempt-reporting advisers)**: `curl "https://api.adviserinfo.sec.gov/search/firm?query=<name>&nrows=20&wt=json"` — parse `firm_name`/`firm_other_names`; verify any hit is actually the target (address/state), not a same-name stranger.
- **FINRA BrokerCheck individuals**: `curl "https://api.brokercheck.finra.org/search/individual?query=<person>&nrows=12&wt=json" -H "Referer: https://brokercheck.finra.org/"` — expect fuzzy matches; require exact-name hits.
- State securities/financial regulator (CA: DFPI — licensee search is bot-walled; check enforcement via web search; know current law status, e.g. FIPVCC VC-reporting suspended 2026-03-18).
- OFAC sanctions (sanctionssearch.ofac.treas.gov), court records (CourtListener/RECAP free; PACER), UCC filings (state SOS), BBB.

### Track 4 — Money & scale claims (the math layer)
- Collect **every self-published number** (site, LinkedIn, FAQ, decks): AUM, "deal volume", # investments, check size, team size, valuations. **Cross-check them against each other first** — new/loose operations contradict themselves across surfaces.
- **The deal-volume trick**: "deal volume" usually counts the *entire rounds* they claim to have joined, not their capital. Compute the honest ceiling: stated check size × claimed deal count. Compare to the marketed figure.
- Third-party financial record: Crunchbase/PitchBook (snippets via search are free), press releases, Form D amounts. No profile anywhere + no filings + big claims = flag.

### Track 5 — People (FinCEN-style: identify the beneficial owners/control people, then verify each)
For each founder/GP/partner (and note undisclosed relationships — shared surnames, same addresses):
- Claims inventory: every prior company, exit, employer ("ex-Google"), degree named anywhere (site, LinkedIn, event bios, podcasts).
- Verification: does the claimed company exist (registry + site + press)? Is there ANY record of the claimed exit? Do event-bio claims match their own LinkedIn history? FINRA/IAPD individual records? Litigation (CourtListener)? 
- Classify each person: verified operator / thin-but-real / unverifiable claims.

### Track 6 — Portfolio & partnership claims (date-vs-entity forensics)
For each named portfolio company/customer/partner:
- Did the round/deal happen, per press + PitchBook/Crunchbase? **Who is actually credited as the investor?**
- **Date check**: did the deal close before TARGET's entity even existed? (Kills the claim.)
- Language check: "partnering with" / "supporting" ≠ "invested in".
- Name-dropped affiliates (accelerators, funds, universities): are they real, and does *their side* acknowledge TARGET anywhere? One-way affiliation = SELF-REPORTED only.

### Track 7 — Solicitation & marketing behavior
- **Meta Ad Library** (JS-rendered → fcdp): `https://www.facebook.com/ads/library/?active_status=all&ad_type=all&country=ALL&q=<handle>&search_type=keyword_unordered` — paid ads, spend, targeting. Zero ads + tiny following = organic reach only.
- Interpret inbound URLs: `fbclid` is appended to ALL in-app link clicks (organic too); `utm_content=link_in_bio` = bio-link click, not proof of a paid ad.
- Who do they solicit? Founders (deal flow) vs investors (LP money). **Public solicitation of investment + no Form D = Rule 506(c)/§5 problem → reporting paths.** Fees charged to founders ("pay-to-pitch", "diligence fee", "listing fee") = walk-away flag.
- Social footprint reality check: followers/posts vs claimed scale; AI-copy artifacts left in public text (a strong tell of thin operations).

### Track 8 — Reputation & adverse media
- `websearch "\"<name>\" scam OR complaint OR fraud OR lawsuit"` + variations; Reddit/HN; BBB; state AG actions; news archives. **Too-new-to-have-a-reputation is itself a finding** (absence of complaints ≠ clean history).
- If deeper ownership tracing is needed: OpenCorporates, OCCRP Aleph (aleph.occrp.org), ICIJ Offshore Leaks (offshoreleaks.icij.org), Open Ownership register (per GIJN guide).

### Track 9 — Synthesis & delivery (deepsearch Phase 5–6)
- Verdict grid (age / raised money? / legal status), verified timeline, claims-vs-record two-column, people track-record table, red flags vs mitigants, and a **reporting authority map** (doge-service style — exact URLs, verified live): SEC TCR (sec.gov/tcr), state regulator complaint portal (CA: dfpi.ca.gov/submit-a-complaint/), FTC (reportfraud.ftc.gov), platform reporting.
- Sources table: URL, what it established, confidence class, retrieved date. State what was NOT checked (county FBN, paywalled DBs) — calibrated uncertainty over silent gaps.

### Escalation rules (bot-walls)
`WebSearch/WebFetch → websearch CLI / Exa crawl → fcdp real Chrome` on any 403/JS-wall. Known bot-walled-but-fine-in-browser: sec.gov, dfpi.ca.gov, bizfileonline.sos.ca.gov, Crunchbase, PitchBook, Meta/Instagram, most news WAFs. A real 404/410 = actually gone; don't browser-retry.

### Hard rules
- Cite or don't claim; every stakes-bearing assertion = live URL + retrieved date.
- Try to REFUTE each load-bearing claim before trusting it (search "<claim> wrong/scam/criticism").
- Never fabricate a statistic, filing, person, citation, or URL. Omit over invent.
- "No public record" ≠ "illegal" — a micro-VC investing members' own money needs no registration. Report the *marketing-vs-record gap*, not a legal conclusion.
- This is research, not legal/investment advice; no outreach/filing without explicit user approval.

---

## Field notes (verified 2026-07-10, Roundtable Ventures run)
- CA SOS `businesssearch` API returns 403 even from a logged-in browser fetch — only the SPA's own token works; **driving the UI via fcdp works** (native value setter + input event + Enter, then innerText scrape; row-click expands full record incl. standings + agent).
- EDGAR full-text (`efts.sec.gov/LATEST/search-index?q="phrase"`) covers 2001+ and includes Form D bodies; needs a `User-Agent: <contact>` header.
- IAPD firm API field: `firm_ia_scope` ACTIVE/INACTIVE; `firm_other_names` catches DBAs.
- BrokerCheck API needs `Referer: https://brokercheck.finra.org/` and returns fuzzy hits — verify exact names.
- Wayback CDX `collapse=timestamp:6` gives a clean per-month timeline for spotting domain-ownership gaps.
- Meta Ad Library and Instagram render only in a real browser; Ad Library keyword search ≠ advertiser search (try the exact handle too).
