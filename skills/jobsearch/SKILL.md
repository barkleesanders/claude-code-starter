---
name: jobsearch
description: Search job listings in the US (USAJOBS federal, Adzuna private market, and Greenhouse/Lever/Ashby company boards) and Denmark (Jobindex, Jobnet, Akademikernes Jobbank, Jobdanmark), then run the AI job-application workflow from the ai-job-search repo. Use when the user says "/jobsearch", "find jobs", "search jobs", "jobs in USA / [US city]", "federal jobs", "USAJOBS", "Adzuna", "jobs at [company]", "Danish jobs", "jobindex/jobnet/jobbank/jobdanmark", wants to look up listings, job categories, occupation codes, or salary benchmarks, or wants to evaluate fit / tailor a CV / write a cover letter for a posting. Wraps nine Bun CLIs (5 US sources + 4 Danish portals) plus the repo's /setup, /scrape, /apply commands.
---

# /jobsearch — US + Danish Job Search + Application Assistant

Thin launcher over the job-portal CLIs in the **ai-job-search** repo. **Default to the US sources** unless the user asks for Denmark. Each CLI emits clean JSON to stdout; errors are JSON on stderr with exit 1. Same run rule everywhere: **`cd` into the CLI's `cli/` dir first** (bun resolves `node_modules` by file location), and never bump `@bunli/core` past `0.7.0`.

---

## 🇺🇸 US jobs — `us-jobs` CLI

```bash
cd ~/ai-job-search/.agents/skills/us-jobs/cli && bun run src/cli.ts <command> [flags]
```

Five sources, one normalized output shape: `{meta, results:[{source,id,title,company,location,remote,salary,url,posted}]}`. All accept `--limit` and `--format json|table|plain`.

### Keyless — company job boards (work immediately, ✅ verified live)
For "jobs at <company>", the **default is `auto`** — it fans out across all three ATSes in parallel so you don't have to know which one the company uses:
```bash
bun run src/cli.ts auto <company> -q engineer --remote --limit 20   # tries greenhouse+lever+ashby, merges, dedupes
```
`meta.sources_hit` tells you which ATS actually had the company. `-q` filters by title text. Use the single-source commands only when you already know the ATS:
```bash
bun run src/cli.ts greenhouse <board>   --limit 20   # e.g. stripe, airbnb, coinbase
bun run src/cli.ts lever      <account>  --limit 20   # e.g. palantir
bun run src/cli.ts ashby      <board>    --remote     # e.g. Notion, Ramp, linear, openai
```
`<company>`/`<board>`/`<account>` is the company's slug in its careers URL (`jobs.lever.co/<account>`, `jobs.ashbyhq.com/<board>`, `boards.greenhouse.io/<board>`). `NOT_FOUND` from `auto` means the company isn't on any of the three keyless ATSes (try Adzuna, or check their careers page for a different ATS).

### Federal — USAJOBS (✅ key configured, verified live)
```bash
bun run src/cli.ts usajobs -q "data scientist" --location "Austin, TX" --remote --limit 20
```

### Broad private market — Adzuna (✅ key configured, verified live)
```bash
bun run src/cli.ts adzuna -q "software engineer" --where "Seattle, WA" --salary-min 120000 --remote --limit 20
```

**Keys are already set up** (2026-06-04) in `us-jobs/cli/.env` — bun auto-loads it, so commands just work from the cli dir with no `export` needed. The same keys are also in `~/.zshrc` for interactive terminals. `.env` is gitignored (keys never commit). If you ever see a `MISSING_KEY` error, the `.env` was moved/lost — re-add `ADZUNA_APP_ID`/`ADZUNA_APP_KEY` (developer.adzuna.com) and `USAJOBS_API_KEY`/`USAJOBS_EMAIL` (developer.usajobs.gov). Never fabricate listings on a key error.

### How to run a US search
1. **Specific company** → `greenhouse`/`lever`/`ashby` (no key, instant).
2. **Federal/government** → `usajobs`.
3. **Broad "X jobs in Y city"** → `adzuna` (needs key). Without an Adzuna key, fall back to querying a few relevant company boards, and tell the user a key unlocks market-wide search.
4. Run sources in parallel (separate Bash calls), dedupe by `title`+`company`, present a ranked shortlist (title — company — location — [remote] — salary — url).
5. Then offer `/apply <url>` to tailor a CV + cover letter for any posting.

---

## 🇩🇰 Danish jobs

## Repo location

```
~/ai-job-search
```

If it's missing, clone it: `git clone https://github.com/MadsLorentzen/ai-job-search ~/ai-job-search`, then for each of the four CLIs run `bun install` (deps are pinned to `@bunli/core@0.7.0` — do NOT bump to "latest", 0.8+ pulls a React/OpenTUI runtime that crashes headless).

## CRITICAL run rule — cd into the CLI dir first

Bun resolves `node_modules` relative to the **file's** location. Always `cd` into the specific `cli/` dir before running, or bun grabs a wrong global-cache version of `@bunli/core` and crashes with `Cannot find module 'react/jsx-dev-runtime'`.

```bash
cd ~/ai-job-search/.agents/skills/<cli>/cli && bun run src/cli.ts <command> [flags]
```

`<cli>` ∈ `jobindex-search`, `jobnet-search`, `jobbank-search`, `jobdanmark-search`.

All commands accept `--format json|table|plain` (default `json`). Pipe JSON to `python3`/`jq` to filter.

---

## The four portals

| CLI dir | Portal | Best for | Live status from this host |
|---|---|---|---|
| `jobdanmark-search` | Jobdanmark.dk | Broad market, all sectors | ✅ fully working |
| `jobnet-search` | Jobnet.dk (govt) | Public-sector, all DK | `suggestions`/`occupations` ✅; `search`/`detail` need a DK/browser session |
| `jobindex-search` | Jobindex.dk | Largest private board | session/cookie-gated (204 from datacenter IPs) |
| `jobbank-search` | Akademikernes Jobbank | Highly-educated / academic | Cloudflare-gated from datacenter IPs |

The gated ones run, parse, and error-handle cleanly — they return data from the user's Mac (residential IP / logged-in), just not from headless cloud hosts. If a gated CLI returns empty/403/204, say so plainly; don't claim no jobs exist.

---

## Command cheat-sheet

### jobdanmark-search (✅ verified live)
```bash
cd ~/ai-job-search/.agents/skills/jobdanmark-search/cli
bun run src/cli.ts search --text "elektriker" --job-type fuldtid --municipality Odense --limit 10
bun run src/cli.ts search --category 227978 --job-type "fuldtid,deltid" --page 2
bun run src/cli.ts detail <slug>                 # slug from search results
bun run src/cli.ts categories                     # live job counts per category
bun run src/cli.ts autocomplete -q "it"           # job-title / category IDs
bun run src/cli.ts locations -q "Odense"          # municipality / zip / region
```

### jobnet-search
```bash
cd ~/ai-job-search/.agents/skills/jobnet-search/cli
bun run src/cli.ts suggestions -q "syge"                                  # ✅ typeahead titles
bun run src/cli.ts occupations --search-string "sygeplejerske" --per-page 5  # ✅ ESCO codes
bun run src/cli.ts search --search-string "udvikler" --region HovedstadenOgBornholm --work-hours FullTime --per-page 10
bun run src/cli.ts detail <jobAdId>              # UUID from search
```
Regions: `HovedstadenOgBornholm`, `Midtjylland`, `Syddanmark`, `OevrigeSjaelland`, `Nordjylland`. Order: `PublicationDate` | `BestMatch` | `ApplicationDate`.

### jobindex-search
```bash
cd ~/ai-job-search/.agents/skills/jobindex-search/cli
bun run src/cli.ts search -q "python" --jobage 7 --sort date --limit 10   # jobage: 1|7|14|30|9999
bun run src/cli.ts detail <id|url>
```
Area filtering isn't reliable via params — put the city in the query: `-q "python aarhus"`.

### jobbank-search (academic)
```bash
cd ~/ai-job-search/.agents/skills/jobbank-search/cli
bun run src/cli.ts search --key "data scientist" --location 2 --type 3 --limit 10
bun run src/cli.ts detail <id>
```
Multi-value filters are comma-separated: `--type 3,6 --industry 10331`. Code tables live in `jobbank-search/cli/README.md` (type/location/work-area/education/industry).

---

## How to run a search

1. Resolve the user's intent → pick portal(s). Broad/any-sector → **jobdanmark** (most reliable). Academic → jobbank. Public-sector → jobnet. Largest private pool → jobindex.
2. For jobdanmark/jobnet, use `autocomplete`/`occupations`/`locations` first to turn free text into IDs when filtering precisely.
3. Run `search` with `--limit` to keep output small; parse the JSON and present a ranked, deduped shortlist (title — company — location — url).
4. Search several portals in parallel (separate Bash calls) when the user wants broad coverage, then dedupe by title+company across results.
5. If a portal returns empty/gated, name which one and why; offer to retry from the logged-in browser.

## Full application workflow (the repo's own commands)

For end-to-end (fit evaluation → tailored LaTeX CV → cover letter → reviewer pass), the repo ships Claude Code slash commands in `~/ai-job-search/.claude/commands/`:

- `/setup` — build the candidate profile (fills `CLAUDE.md`, profile files) from `documents/`, a pasted CV, or an interview.
- `/scrape` — multi-portal search ranked by fit (uses the CLIs above).
- `/apply <url|text>` — evaluate fit, draft CV (`cv/main_<co>.tex`, compile `lualatex`) + cover letter (`cover_letters/`, compile `xelatex`), reviewer critique, revise.

To use those, work **inside** `~/ai-job-search` so the repo's `CLAUDE.md` profile + command files are in scope. The profile is currently a blank template — run `/setup` there first. Optional salary benchmarking: `salary_lookup.py` + `tools/convert_salary_excel.py` (needs a user-supplied `salary_data.json`).

## Quality rules

- Never invent job listings, companies, salaries, or deadlines — every fact comes from CLI JSON output. If gated/empty, report that, don't fabricate.
- Keep Danish characters intact (the CLIs decode HTML entities; don't re-mangle æ/ø/å).
- Don't bump `@bunli/core` past 0.7.0 or remove the per-CLI `tsconfig.json` (typecheck OOMs without it).
