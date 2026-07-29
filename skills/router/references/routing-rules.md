# Routing Rules (curated fast-path)

> High-signal task→skill shortcuts so the router doesn't rescan all 178 catalog entries every time.
> **This file is the part that "learns."** After `scripts/learn.sh` surfaces a misfire, edit the matching
> row here (or add one) so the next identical task routes correctly. Catalog = what EXISTS; these rules = what WINS.

## Decision procedure
1. Match the task against the **Intent → Skill** table below (top-to-bottom, first strong match wins).
2. No match? Grep `references/skill-catalog.md` for domain keywords, pick the closest 1–3.
3. Prefer the **most specific** skill (e.g. `sf-nextrequest` over generic `doge-service` for an SF CPRA).
4. Chain when a task spans domains (e.g. research → report = `deepsearch` then `html-report`).
5. After acting, log it: `scripts/log-decision.sh "<task>" "<skills>" "<worked|partial|wrong>"`.

## Intent → Skill

| If the task is about… | Route to | Notes |
|---|---|---|
| Stalled govt/bureaucracy, force an agency to act, map authority + deadlines + parallel-file | **doge-service** | The accountability engine. Not for a single SF311/CPRA (use those). |
| VA disability claim package from evidence | **va-claims** | Full multi-doc package. `va-appeal` for appeals; `va-submit`/`va-quicksubmit` to file. |
| VA travel reimbursement / mileage | **va-travel** | BTSSS + 10-3542 fax. |
| VA community care / massage / acupuncture auth | **va-community-care** | |
| Explain a VA concept / decision | **va-explain** | |
| SF public records / CPRA / Sunshine request | **sf-nextrequest** | `sf-nr` CLI. NOT `doge-service`. |
| Report an SF city issue (pothole, graffiti, dumping) | **sf311** | |
| Build a feature / fix a bug / deep debug | **carmack** | `debug` for quick known-pattern lookups. |
| Ship / deploy to production | **ship** | Only skill allowed to deploy. |
| iOS/macOS app work (build, run, simulator, ASO, crash) | **ios** | Release (TestFlight/App Store) = /ship phase. |
| Hono site / convert to SSR / new website | **hono** | Default for new sites. |
| Deep multi-source fact-checked research | **deepsearch** or **deep-research** | Verify every load-bearing claim. |
| Report / audit / summary / dashboard / findings deliverable | **html-report** | HTML-Default rule. `magazine` for editorial layout. |
| Grant LOI / proposal / funder outreach | **grant-writer** | Hard pre-send gate. |
| Nonprofit 990 / e-Postcard | **nonprofit-tax** | Preparer+verifier, never e-files. |
| Genealogy / family tree / ancestors / DNA relatives | **autoresearch-genealogy** | |
| Personal health / polygenic risk / labs / blueprint | **healthquant** | `genorisk` for raw PRS. |
| Decompile / reverse-engineer a binary/APK/IPA/extension | **decompile** | Routes to the right RE tool. |
| Sign a document / signature request | **docuseal-cli** | Always DocuSeal, never typed /s/. |
| Physical mail / certified letter / check | **postgrid** | |
| Design a UI / build a component or screen | **design** or **ui-ux-pro-max** | |
| Drive logged-in Chrome (CDP, snapshots, fill forms) | **chrome** | real Chrome profile via fcdp. |
| Talk to Codex / second opinion / delegate | **codex-chat** | |
| Job search (US federal/private, Denmark) | **jobsearch** | |
| Control the local Claude-Science app | **csci** | |
| Set/track a persistent objective | **goal** | |
| Inbox to zero / triage email into actions | **inbox-zero** | |
| Medicaid provider audit | **medicaid-audit** | |
| Brian "Shaq" case ops (CDPAP, Article 81, ExampleInsurer) | **shaq-advocate** | |

## Non-skill tools the router should still reach for (not everything is a skill)
- **Send email** → `~/tools/gog-send-tracked.sh` (gogcli). Find/read threads → Gmail MCP.
- **Send a fax** → DIY fax worker (`~/projects/diy-fax-worker/send.mjs`), never a 3rd-party fax API.
- **Google Drive upload/organize** → `gog drive upload --parent=<id>`.
- **Asana** → `mcp__claude_ai_Asana__*` (search first, then create/comment).
- **Task tracking** → `bd` (beads), never TodoWrite.

## Learned corrections (append as learn.sh surfaces misfires)
<!-- e.g. 2026-07-02: "records request to a non-SF agency" was mis-routed to sf-nextrequest → correct route is doge-service + email/portal for that jurisdiction. -->
