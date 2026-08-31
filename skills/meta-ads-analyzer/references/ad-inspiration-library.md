# AIVA Ad Inspiration Library

Curated competitive ads + landing pages from Notion link-inbox triage on 2026-04-28.
Loaded automatically by `a brand-voice skill` and `meta-ads-analyzer` (per a brand-voice skill SKILL.md wiring).

## How to use this with skills

| When you're doing... | Reference these patterns |
|---|---|
| **Analyzing AIVA campaign performance** (`meta-ads-analyzer`) | Use the legal-niche CPC benchmarks below to sanity-check whether AIVA's CPC is reasonable |
| **Generating new AIVA ad creative** (`a brand-voice skill`, `ad-creative` from marketingskills) | Pull hook patterns from "Hook patterns observed" |
| **Auditing AIVA landing pages** (`page-cro`, `signup-flow-cro`) | Compare against the SaaS positioning + DTC trust-marker examples |
| **Writing AIVA copy** (`copywriting`) | Use the headline structures from the SaaS / lead-magnet sections |
| **Profiling a competitor** (`competitor-profiling`) | Use any URL below as a starting point for a deeper profile |

---

## 1. Highest-leverage references for AIVA

### 1a. Legal-niche CPC economics (DIRECT BENCHMARK)

> Divorce lawyers pay $350–500 per click on Google Ads. DUI attorneys pay $200–400 per click. AI content funnels on TikTok cost almost nothing to operate.
> — @levikov, March 2026

**Action for AIVA:** Compare current AIVA CPC against this $200–500 legal benchmark. If we're paying close to it, validate quality. If much less, we have headroom. If higher, urgent optimization.

### 1b. Military / Veteran audience overlap (DIRECT AUDIENCE)

| Source | URL | What | Why |
|---|---|---|---|
| MilWallet | https://milwallet.polsia.app | "Free Military Pay Calculator & Financial Optimizer 2026" — BAH by ZIP, TSP optimizer, PCS entitlements | Exact AIVA target audience. Their lead-magnet structure (free calculator → email capture) is a proven pattern. **Build an AIVA equivalent: free VA-disability-rating calculator?** |

### 1c. "AI [field] software" SaaS positioning

| Brand | Positioning | What AIVA can borrow |
|---|---|---|
| [Instead](https://www.instead.com) | "AI tax software for tax planning and filing" | Headline structure: "AI [domain] software for [outcome]" |
| [TaxQuotes](https://go.taxquotes.com) | "Get a free quote to resolve your tax issue" | Lead-magnet wording — frame AIVA as resolving a problem, not selling a service |
| Cash App Taxes | "100% free tax product" | Pricing-as-hook |

### 1d. Adjacent benefit-positioning (HSA/FSA → VA benefits)

| Brand | URL | Positioning | Why relevant |
|---|---|---|---|
| Hammock | https://www.usehammock.co/lmn | "Just What The Doctor Ordered — spend HSA/FSA on stuff you actually want" | AIVA could position as "claim what you've already earned" using same emotional hook |

---

## 2. Hook patterns observed (paste-ready for ad-creative skill)

| Pattern | Real example | AIVA-adapted |
|---|---|---|
| **Authority-stamp** | "Awarded the #1 Best Anti-Snoring Pillow by Forbes Vetted" | "Used by 10,000+ veterans who increased their disability rating" |
| **Spec density** | "5-Star Virginia Tech rated, Mips, integrated lights, turn signals & Crash Alert" | "Free C&P prep, denial-letter analysis, evidence-package generator" |
| **Pain-question UGC** | "If you hate carrying your helmet everywhere, check this out" | "If your VA claim has been pending more than 6 months, this is for you" |
| **Free-tool-just-pay-X** | "Free Unlimited Postcards, Just Pay Postage" | "Free disability rating estimate, just answer 5 questions" |
| **Authority + clinical** | "Professional strength L-Methylfolate, designed based on clinical research" | "VA-form-compliant evidence package, designed by accredited claims agents" |
| **Free quote / lead magnet** | "Get a free quote to resolve your tax issue" | "Get a free analysis of your VA denial letter" |

---

## 3. Production / format patterns observed

- **All Meta DTC ads use `utm_id = ad_set_id` and `_v2_sNN` variant suffixes** → suggests aggressive variant iteration. AIVA should do the same and let `meta-ads-analyzer` track per-variant performance.
- **Vertical video UGC dominates** Feed/Stories placements (4:5 / 9:16). Hero shot → benefit copy → CTA in <3s.
- **Landing pages have minimal hero copy + single CTA**. Benchmark AIVA landing pages against this minimalism (`page-cro` skill).
- **Most successful DTC use named "campaign families"** like `ACQ - CBO - HELMETS - USA - tROAS > 2.5 - IF: 1.2` — structured naming makes performance comparison trivial. AIVA should adopt similar conventions.

---

## 4. Full reference list (25 ads/pages)

| ID | Brand | Vertical | URL | Notes |
|---|---|---|---|---|
| `agh` | @levikov | Legal/CPC | https://x.com/levikov/status/2037160193986093146 | $350-500 divorce CPC reference |
| `b34` | MilWallet | Military finance | https://milwallet.polsia.app | Direct audience, lead-magnet calc |
| `iex` | Instead | AI tax SaaS | https://www.instead.com | "AI tax software for tax planning" |
| `o17` | TaxQuotes | Tax services | https://go.taxquotes.com | "Free quote to resolve tax issue" |
| `q4r` | Cash App Tax | Tax SaaS | https://x.com/ryanmorey/status/2043390856300782008 | "100% free tax product" |
| `dg5` | Olarry | Real estate leads | https://olarry.com/pricing | December 2025 leads campaign |
| `fos` | Semper Solutus | Unknown | https://sempersolutus.co/home | Unknown — need to deep-dive |
| `o6k` | ClosrStaff | Sales VAs | https://closrstaff.com | "Expert Sales Virtual Assistants" |
| `lbo` | Dub.co | SaaS link attr | https://dub.co | Modern Link Attribution Platform |
| `mgb` | Mailbox Power | Direct mail | https://go.mailboxpower.com/eg1 | "Free Postcards, Just Pay Postage" |
| `736` | Hammock | HSA/FSA | https://www.usehammock.co/lmn | Health benefits positioning |
| `7sh` | Fernando | Long-form content | https://x.com/zetalyrae/status/1933650594964910367 | 8k-word ADHD guide template |
| `e0i` | katexbt | SMM stack | https://x.com/katexbt/status/2037370343237800250 | Excalidraw + xnapper for free SMM |
| `xcl` | Damon Chen | Email infra | https://x.com/damengchen/status/2036707159812325604 | $1.66 to broadcast 16k contacts (AWS-based) |
| `jyy` | UNIT 1 NEON | DTC helmet | https://www.unit1gear.com/products/neon | Spec-density hero copy, $159.90 |
| `o4a` | Thousand Heritage 2.0 | DTC helmet | https://www.explorethousand.com/products/bike-helmet-2 | UGC video w/ pain-hook |
| `aff` | Thousand Heritage 2.0 (variant) | DTC helmet | https://www.explorethousand.com/products/bike-helmet-2 | Different ad creative same product |
| `tfj` | Tokyoviva | DTC apparel | https://www.tokyoviva.com/collections/washed-t-shirts | Multi-ad set test |
| `xqs` | HER+ Glow Balm | DTC beauty | https://tryher.com/products/glow-balm | Mother's Day creative |
| `n0p` | Triquetra L-Methylfolate | DTC supplement | https://triquetrahealth.com/products/l-methylfolate-15-mg-plus-methyl-b12 | Clinical-research framing |
| `20z` | Snorinator | DTC sleep | https://thesnorinator.com | "#1 by Forbes Vetted" authority |
| `njt` | True North Inflatables | DTC marine | https://www.truenorthinflatables.com/collections/catamarans | IG link-in-bio funnel |
| `e1m` | Maison Noir SF | Event tix | https://posh.vip/e/maison-noir-sf-edition | Local event marketing |
| `6mk` | Zeffy / KOHO Carnaval | Charity event | https://www.zeffy.com/en-US/ticketing/world-dance-2-bahia-gala | Free fundraising platform |
| `sx3` | sexynerds.net | Event (404) | https://sexynerds.net/bayarea | Page since taken down |

---

## 5. Open questions for AIVA marketing

1. **CPC benchmark** — What are we actually paying per VA claim lead? Compare to $200-500 legal benchmark.
2. **Free-tool lead magnet** — Should we build a free disability-rating calculator like MilWallet's military-pay calculator? Same audience, proven pattern.
3. **Positioning test** — Should we A/B test "AI VA disability claim software" framing (Instead-style) vs current positioning?
4. **Content marketing** — Fernando's 8k-word ADHD guide drove engagement; should we publish "8k-word VA disability claims survival guide" as a pillar piece?
5. **Direct mail** — Mailbox Power's "free postcards, just pay postage" is interesting for veteran outreach; cost vs digital ad CPC?

---

## 6. How to refresh this library

Set on a quarterly cycle:
1. Run `~/tools/notion-link-triage/triage.py` to capture latest competitive saves
2. Filter to `marketing` tag: `bd query 'labels includes "src-tag:marketing" AND status=open'`
3. Re-enrich + extract patterns into this file (append to relevant sections)
4. Use `competitor-profiling` skill on any high-signal entry to deepen
