---
name: zi-search
description: Free-only ZoomInfo company search via zi-search CLI (lookup IDs, search companies, find similar). Use for AIVA GTM company lists, ICP sizing, TAM counts, industry/metro/tech filter resolution. Commands: zi-search lookup / search / similar. Never enrich. Never contacts, intent, scoops, news, research, or raw. Trigger on ZoomInfo company search, GTM company lists, ICP, firmographics, "how many companies like X".
---

# zi-search (free ZoomInfo Search Companies)

CLI: `/opt/homebrew/bin/zi-search` (also `~/tools/zi-search/bin/zi-search`).

**Free slice only.** Lookup + Search Companies + Find Similar cost \$0 credits. Enrich costs bulk credits — never call it.

```bash
zi-search enrich    # always refuse — exit 2
```

If a user or plan says "enrich", "full profile", "contacts at these companies", "intent", "scoops", or "research": **stop**. Tell them this CLI will not do that. Do not fall back to `gtm companies enrich` or `gtm raw call enrich_companies`.

## When to use

- AIVA GTM company lists (who fits an ICP)
- ICP sizing / TAM: how many companies match firmographics
- Resolve ZoomInfo industry / metro / tech **IDs** before searching
- Find similar companies to a known account

Not for: people/contacts, buyer intent, news, scoops, conversation intel, account research, or full-profile enrich.

## Auth

Needs a ZoomInfo login. Free ≠ anonymous.

```bash
zi-search auth whoami          # logged-in vs not; never prints tokens
zi-search auth login           # official gtm browser OAuth — only if the user asked to log in
zi-search auth logout
```

If whoami says not logged in, ask the user to run `zi-search auth login` themselves. Do **not** open a browser login on their behalf unless they are already mid-login.

Tokens live in `~/.config/gtm-ai/credentials`. Never read, dump, or print that file.

## Commands

### 1. lookup — get IDs first

`--industry`, `--metro`, `--tech` on search take **IDs**, not names (names 422).

```bash
zi-search lookup --field industries --fuzzy software
zi-search lookup --field metro-regions --fuzzy "san francisco"
zi-search lookup --field tech-products --fuzzy salesforce
```

Parse `.<fieldName>.data[]` → `{ id, attributes.name }`. Pass **`id`** into search.

Metro-regions: US + Canada only.

### 2. search — at least one filter

```bash
zi-search search --name ZoomInfo --page-size 5
zi-search search --industry <ID> --employees 100to249 --country "United States"
zi-search search --domain https://example.com -f table
```

Useful flags: `--name --domain --industry --metro --state --country --continent --zip --employees --employees-min --employees-max --revenue --revenue-min --revenue-max --type --ticker --tech --naics --sic --funding-min --funding-max --funding-start --funding-end --sort --page --page-size -f`

- `--employees` tokens: `100to249,250to499`
- `--revenue` tokens: `1Mto5M`
- `--revenue-min/max` and `--funding-min/max` are integers in **thousands**
- `--type`: `private,public,npo,education,government,other`
- `--sort`: `name|employeeCount|revenue` (prefix `-` = desc)
- `--page-size` max 100
- `-f`: `json|jsonl|csv|table|yaml` (default `json`; prefer json when piping)

### 3. similar — free

```bash
zi-search similar --id <companyId>
zi-search similar --name "ZoomInfo"
```

Prefer `--id` from a prior search hit.

## Workflow (AIVA GTM / ICP)

```bash
# Resolve filters
zi-search lookup --field industries --fuzzy "computer software" -f json

# Size / list (refine freely — search is free)
zi-search search --industry <ID> --employees 100to249 --country "United States" --page-size 25 -f json

# Optional lookalikes
zi-search similar --id <companyId>
```

Result teaser: company name, domain, industry, employee count, location, ZoomInfo company ID. That ID is what enrich would take — **do not enrich**.

## Agent rules

- Pipe for JSON. Do not use `-f table` when you need to parse.
- Require at least one search filter. Do not call search with only `--page`.
- Never invent a login. Never pass tokens as flags or env dumps.
- Never run `gtm raw call` yourself with a tool name outside `lookup`, `search_companies`, `find_similar_companies`.
- If asked for enrich/contacts/intent/scoops/news/research: refuse and cite credits.
