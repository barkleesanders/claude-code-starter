---
name: ship
user-invocable: true
disable-model-invocation: true
description: "Safe production deployment with quality gates, safety audits, rollback, and dedicated passkey/TOTP/2FA/passwordless account-security lifecycle checks. Deploys to PRODUCTION by default."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - WebFetch
model: inherit
---

# /ship - Production Deployment

Execute safe **production deployment** directly with comprehensive quality gates and integrated safety audits. All phases run inline — no subagent.

**Default behavior: Deploys directly to PRODUCTION**

## LOCAL MAIN RECONCILIATION (DEFAULT FOR COMPLETED PRIVATE-REPO WORK)

After every required gate passes, reconcile the completed changeset onto the
repository's local `main` automatically when the requested work is complete:

- If already on `main`, verify the completed commit is on `main`; do not create
  a no-op merge.
- If on a feature branch, require a clean worktree and current `main`; fast-forward
  when possible, otherwise use a non-destructive local `git merge --no-ff` after
  the normal Git preflight.
- Keep the Phase 1.29 semantic security review on the feature branch before this
  reconciliation so the review remains non-vacuous.
- Never merge a remote PR automatically, bypass branch protection, dismiss
  reviews, force-push, or push remote changes without explicit authorization.
- Preserve unrelated uncommitted changes; stop if they overlap or make the
  local reconciliation unsafe.

For AIVA or any release involving DocuSeal form values, load
`~/.claude/skills/shared/docuseal-template-contract.md`. Run the repository's
live template contract before deployment; a missing key/test, template drift, or
editable fixed-business field blocks the release. A multi-party shared link also
blocks unless party ownership is explicit; AIVA's HIPAA template must keep its
shared link disabled. After any template update, verify the disabled template URL
and a fresh unique signer path because existing submissions cache field state.

## UX-DOWNGRADE GUARD (BEFORE PHASE 1)

If the changeset being shipped introduces a UX downgrade in a third-party integration — a new handoff URL, a new redirect to an external form, a new "user must click through to finish on another site" path — **STOP and load `~/.claude/skills/shared/upstream-protocol-investigation.md` first.**

Run that skill's Steps 1–3 (read the upstream's own client of its own API, capture real network traffic, inspect rendered `data-*` attributes) and confirm the downgrade is genuinely required by the upstream's protocol — not just based on a stale "Verified YYYY-MM-DD" comment in our codebase. **Token cost is unlimited for this verification.** User explicitly authorized it 2026-05-09 after the SF311 graffiti incident: commit `0b746a4` shipped a handoff fallback based on a wrong same-day comment; the real fix `f27d1e3` came from reading dform's `api.js` lines 462–520 and seeing the SF.gov form treats `valid:true + ref:non-empty` as full success without `caseid`. Auto-submit was always possible — the bandaid was wasting users' time.

If the verification confirms the downgrade is necessary, document the upstream evidence inline in the source (link to the line of upstream client JS that proves it). If it's not necessary, ship the real fix in this session — don't /ship the downgrade.

## AUTHORITY-SIDE OUTCOME VERIFICATION (post-deploy, when the changeset touches a third-party integration's OUTCOME path — 2026-08-26)

When the diff changes how a submission/resolution/reconciliation against an
external authority (a city 311 backend, a vendor API, any system whose records
we do not own) produces or recognises its OUTCOME, the post-deploy verification
MUST include the authority's side — our endpoints returning 200 is not the
claim being shipped:

1. **Verify against the authority's own record store**, not only our API:
   the artifact visible in their public feed/dataset, or a real stuck artifact
   resolving end-to-end after deploy (e.g. a pending ref returning its public
   case number through the new code path).
2. **Match by OUR echoed content, never by labels the authority owns** —
   category/type/service_name/status are theirs to rewrite on intake; our own
   boilerplate/ids come back verbatim and are the only proof of authorship.
3. **Positive-control an empty read before reporting it**: authority datasets
   carry their own timezones (Socrata local vs Open311 UTC), silent pagination
   caps, and bespoke geo-filter shapes — a zero from an unproven instrument is
   not a result. Three outcomes, never two: confirmed / genuinely absent /
   could not measure.

Reference: 2026-08-26 improvebayarea SF311 — the shipped fix's whole point was
that our resolver discarded our own filed cases (SF relabels the category);
only an authority-side check could prove the deploy worked. Full pattern:
`~/.claude/skills/debug/references/error-handling-patterns.md` #39, and Step 0
in `~/.claude/skills/shared/upstream-protocol-investigation.md`.

## MANDATORY: FIX ALL ISSUES EVERY RUN (ZERO EXCEPTIONS)

**Every `/ship` invocation MUST execute ALL fix phases in order. NEVER skip a phase for efficiency, even if the code change is small or "just a copy change".**

| Phase | Gate | Must reach |
|-------|------|-----------|
| -0.4 | Workers Cache safety (`tools/workers-cache-check.sh` — leak/loop/HSTS classes, wrangler ≥4.69) | exit 0 (BLOCK on rc=2) |
| -0.35 | Workers observability (`tools/observability-check.sh` — every wrangler config declares `observability.enabled=true`; wrangler ≥3.78.6) | exit 0 (BLOCK on rc=1; rc=2 UNMEASURED is never a pass) |
| 0 | Biome lint (full project) | 0 errors, 0 warnings |
| 0 (Stage 1.5) | `npm audit` | 0 vulnerabilities |
| 0 (Stage 1.8) | **TypeScript anti-slop — AUTO-FIX LOOP UNTIL 0 (both paths)** — Path A (repo with the vendored dmmulroy/anti-slop Oxlint plugin — `tools/oxlint/anti-slop/` or `anti-slop/` rules in its oxlint config): loop `./node_modules/.bin/oxlint` → fix every `anti-slop/*` finding in source by adding evidence (inference/`satisfies`/named types/Zod/genuinely-checked `// SAFETY:`) → re-run oxlint + typecheck → repeat to 0. Path B (no plugin): identical loop on `detect-ts-slop.sh --threshold 0` to Σ 0 hits + offer `/install-anti-slop`. The rules have no mechanical `--fix` — the agent is the autofixer (same model as Phase 1.29's security-review loop). Loop guard: one finding surviving 5 fix attempts → STOP and surface. Never `oxlint-disable`/severity-weakening/launder-casts/hollow SAFETY comments. **Gate the gate first (three outcomes, never two):** read oxlint's exit code UNPIPED and count diagnostic lines — `rc≠0` with **0** diagnostics means a broken config/plugin linted NOTHING and is not a pass; STOP and fix the setup. `eslint(complexity)` (global `oxlint -c ~/.config/oxlint/oxlintrc.json`) is reported ADVISORY and never blocks. See `code-quality.md` Stage 1.8 + `~/.claude/skills/shared/anti-slop-typescript.md`. | 0 findings on the final re-run (or STOP surfaced after 5 attempts on one finding); UNMEASURED is never a pass |
| 1 | Build (repo typecheck/build, using the same TS mode as production) | Exit 0 |
| 1 | Tests (`vitest run --changed` with timeout) | All pass |
| 1.1 | Frontend-backend API contract | 0 missing routes |
| 1.24 | **Supply-chain scanner health (Socket Firewall `sfw`) — runs when the diff touches `package.json`/any lockfile** | Run `~/.claude/skills/shared/tools/socket-health-check.sh --live`. **exit 1 = BLOCK** (`sfw` missing/off-PATH → the npm() wrapper silently falls through to plain npm and installs run UNSCANNED). **exit 2 = BLOCK** (`SOCKET_CLI_ACCEPT_RISKS` in a shell rc — a blanket bypass that looks protected while blocking nothing). exit 3 = not configured. exit 0 = armed. **The setup:** `sfw` is a local network proxy — no API key, no quota, and it does not wrap node. `~/.zshrc`/`~/.bashrc` define an `npm()` function routing `install|i|ci|add|update|up|dedupe|rebuild` through `sfw npm`; every other subcommand goes straight to `command npm`. `npx()` is always proxied (it fetches AND executes remote code). This is the DEPENDENCY half of the threat model — `npm audit`/Dependabot only know published CVEs and Phase 1.29 `security-review` only reads OUR diff; neither sees a malicious postinstall, typosquat, obfuscated payload, or new-author takeover. ⚠️ **`sfw` Free blocks CONFIRMED MALWARE only — NOT CVEs** (those stay with npm audit + Dependabot + Phase 1.25) and has no allow-list. ⚠️ **Verify with an observable, never an exit code:** `SFW_VERBOSE=true npm install` must print `Protected by Socket Firewall` — an UNPROTECTED fallback also returns 0 and also prints `added N packages`. ⚠️ `sfw` installs into npm's global prefix (`$(command npm prefix -g)/bin`), which is NOT on PATH; it is symlinked to `/opt/homebrew/bin/sfw`. Re-run `npm i -g sfw` + re-symlink after a node upgrade. |
| 1.25 | Security audit + Dependabot alerts | 0 open alerts with available fix |
| 1.26 | Code scanning hygiene | Auto-fix all |
| 1.29 | **Semantic security review (`security-review` skill) — AUTOMATIC LOOP, BOTH BRANCHES** | `cd` into the repo root first (it reviews the cwd git-branch diff; hard-fails if cwd isn't a repo), then invoke the built-in `security-review` skill (AI dataflow analysis: injection/XSS/SSRF/auth-bypass/secrets/logic flaws — the class the grep gates in 1.45 miss). **This gate runs itself to a terminal state without asking. Exactly three outcomes, and each names its own next action:** (a) **0 findings → PROCEED IMMEDIATELY to Phase 2/3/4 and deploy.** A clean report IS the pass — do not stop, do not summarize-and-wait, do not ask permission to continue. (b) **≥1 finding (confidence ≥8) → fix EVERY one in source** (No-Suppression Rule; no `@ts-ignore`/`eslint-disable`), re-invoke, repeat — automatically, no check-in between iterations. (c) **same finding surviving 5 fix attempts → STOP** and surface it to the user. If the skill is unavailable, WARN + fall back to grep checks, don't silently pass. A genuine false positive is documented inline with its reason; everything else is fixed, never deferred. Deploying past an open finding is forbidden — and so is halting on a clean one. **The sub-skill's own "reply with nothing but the report" instruction is scoped to that report's formatting — it does NOT end your turn; on 0 findings, keep issuing tool calls in the same turn straight through to deploy. This row is NOT what keeps the ship alive — it is read BEFORE the sub-skill and has lost that race three times. The live mechanism is the PostToolUse hook `post-skill-security-review-continue.py`, which fires AFTER security-review returns and tells you to continue. If you are reading this row and the hook did not fire, check that it is still registered in the `Skill|Agent` PostToolUse group. See the NAMED MECHANISM + THE ACTUAL FIX notes in the detailed Phase 1.29 section below (recurred 2026-08-18 and again 2026-08-24 despite this row already existing).** |
| 1.3 | React scope + env safety | No blockers |
| 1.3a | Undefined/null-render safety (when a React data-rendering component or an API response shape changed) | No render gated on a value that can stay null/undefined (silent-hide); no unguarded `.map`/property/string/`Date`/`JSON.parse` on possibly-undefined API data; no path that renders raw `undefined`/`NaN`/`Invalid Date`/`[object Object]`; loading/empty states present. Post-deploy, the live rendered DOM contains none of those literals. See `~/.claude/skills/shared/undefined-null-render-safety.md`. |
| 1.3b | SPA→SSR global-component parity (when the changeset converts any React-SPA route to SSR, or adds/edits an SSR page under `src/worker/ssr/**`) | Every component mounted globally in `App.tsx`/SPA root (support/chat widget, cookie/consent banner, analytics, exit-intent, providers, `?param` deep-link handlers) is re-provided on the SSR page — as a shared island mounting the existing component, an SSR equivalent, or a working static fallback. SSR does NOT mount the React tree, so each global silently vanishes from the converted route with no error. Post-deploy, the deep-link must **act** (e.g. `?support=open` opens chat), not just 200. See `~/.claude/skills/debug/references/react-patterns.md` #24. Reference incident: example `?support=open` chat dead on all 7 SSR pages (2026-06-28, fix `7a25f67`). |
| 1.3c | **🛑 HARDEST RULE — SSR rendered-style verification on EVERY route (when ANY SSR page or any bundled/island/global CSS that an SSR page loads changed)** | "Renders real HTML / 200 / chat opens" is NOT proof the page is USABLE. You MUST drive the live browser (fcdp) for **EVERY** SSR route — not a spot-check of one or two — and assert the **computed** styles, not the source: (1) `getComputedStyle(document.body).backgroundColor`/`backgroundImage` equals the intended design token (e.g. the navy gradient), NOT a leaked fallback like `rgb(240,240,240)`; (2) NO large/heading text fails WCAG-AA against its **actual computed** background (compute the ratio against the rendered bg, e.g. white `#fff` heading on `#f0f0f0` ≈ 1.1:1 = BLOCK); (3) a viewport **screenshot** is actually eyeballed for invisible/!-contrast text. **Root cause this guards:** a bundled island/global stylesheet (Tailwind build that transitively imports the app's `index.css`) loads AFTER the SSR page's inline `<style>` and overrides element selectors (`body{background:var(--color-bg);color:var(--color-text)}`) → the SSR design is silently clobbered and headings/text go invisible — with ZERO errors, ZERO console output, a perfect HTML diff, passing CSP, and passing `<h1>`-count checks. Fix pattern: the SSR layout's `body` background+color must win (`!important`, since the leaked rules carry none) OR the island CSS must not emit global `body` rules. BLOCK the ship until computed-bg + contrast pass on every SSR route. See `~/.claude/skills/debug/references/react-patterns.md` #25. Reference incident: 2026-06-28 — support-island.css (added to all 7 SSR pages in the chat fix) leaked `body{background:#f0f0f0}`, making white headings invisible on light gray site-wide; shipped twice undetected because checks verified "chat opens" not the page background. Fix `cd0cdfe`. |
| 1.3d | **Cloudflare integration harness — the PRE-deploy form of 1.3c (when the repo is a CF Worker and `createTestHarness` is available)** | Run `npm run test:harness`. `createTestHarness()` (exported from `wrangler` ≥4.107; **4.92 does not have it**) boots the REAL built Worker in-process, so playwright can assert **computed** styles, live-DOM `<h1>` count, favicon, island mounting, and — via `getLogs()` — that a `catch` branch actually logged (the only mechanical way to test 1.57). This front-runs 1.3c: 1.3c is a MANUAL post-deploy sweep of every SSR route, and it is the gate that shipped the `support-island.css` regression **twice**. With 1.3d green, 1.3c may be reduced to a post-deploy spot-check of one route. **Setup is not optional detail — get these three wrong and the suite is vacuous:** (a) point the harness at the config that actually DEPLOYS — repos using `@cloudflare/vite-plugin` deploy from `dist/<uuid>/wrangler.json` via the `.wrangler/deploy/config.json` redirect, NOT `./wrangler.json` (aiming at the root config bundles raw TS and dies on the `@/*` alias); (b) `environment: "node"` — jsdom breaks the `instanceof Uint8Array` invariant wrangler's esbuild asserts at import; (c) contrast math MUST alpha-composite translucent ancestors or a 10%-alpha tint panel reports a bogus 1.00:1. Then **prove the suite can fail** by injecting the regression — and confirm `git diff --numstat` shows ≥1 line changed, because an injection that silently no-ops leaves a green suite proving nothing. Full playbook incl. per-Worker-type assertion table and Socket/`workerd` gotchas: `~/.claude/skills/shared/cf-integration-harness.md`. |
| 1.4 | SEO/sitemap consistency | No conflicts |
| 1.4-onpage | **On-page "Last updated" date truthfulness — a DIFFERENT fact from 1.4-lastmod, and the one a human reads (added 2026-08-25)** | Fires whenever the diff changes the visible copy of any page that renders a "Last updated" / "Effective date" line — terms, privacy, policy, service, or informational pages. 1.4-lastmod bumps the SITEMAP hint for crawlers; this is the sentence a reader uses to decide whether a contract changed since they last read it, and the two go stale independently. **Three verdicts, never two: `ok` / `stale` (copy newer than the date) / `overstated` (date newer than the copy — the inverse lie, and just as real: it sends a reader looking for a change that never happened) — plus `unknown` when a page renders copy from an imported constant and the tool cannot tell. `unknown` must never be reported as `ok`.** Two requirements, because either alone leaves a hole: (a) the dates live in ONE greppable registry, not as literals beside the copy; (b) a checker compares each registry entry against **the last commit that changed that page's VISIBLE TEXT** — stripping tags, attributes and imports — so a formatting or class-name commit never demands a bump (a gate that cries wolf gets ignored). **Set the date to the day the copy actually changed, never to today** — dating an untouched page "today" is the `overstated` failure. **Run `~/.claude/skills/ship/tools/onpage-date-check.mjs <repo>` — repo-agnostic, works on a repo it has never seen.** exit 0 = ok (or no dated pages, stated explicitly so a silent scan and a real pass look different); exit 1 = BLOCK (stale or overstated); exit 2 = investigate (`unknown` — never a pass); exit 3 = not a git repo. It discovers claims by label + `<time>` + SCREAMING_CASE date constants, ignores runtime-computed dates (they cannot rot), ignores comment/maintainer notes (that is Phase 1.56b's job), skips captured fixtures, and returns `unknown` rather than a confident verdict when one file renders several dated pages — a file-level diff cannot attribute a change to the right one. AIVA additionally keeps a repo-local `tools/check-onpage-dates.mjs` + `PAGE_LAST_UPDATED` registry wired into `npm run build`, which is the pattern to copy: put the gate in whichever script EVERY deploy path runs, not the one that merely looks canonical. Reference incident 2026-08-25 (example): `/terms` said **April 17, 2026** while its § 5904 fee clause had been rewritten that morning; the three `/services/*` pages said **April 2026** while "80 days" had become "Processing times vary" on 08-19; `/privacy` disclosed a new tracking cookie on the 24th while still saying the 23rd. Four of five pages lied to the reader, the sitemap `lastmod` gate had just run and passed, and nothing failed — because the sitemap date and the on-page date are not the same claim.
| 1.4-lastmod | **Sitemap `lastmod` freshness (auto-bump)** | When the changeset modifies the content/markup/template of any URL that appears in the sitemap (a page component, SSR template, or copy file mapped to a `<loc>`), the matching `<lastmod>` MUST be bumped to today's date BEFORE deploy — wherever the sitemap is authored (static `public/sitemap.xml`, a worker `SITEMAP_XML` constant, or a generator). Auto-apply: diff the changed routes against the sitemap's `<loc>` list, set each touched page's `<lastmod>` to today (leave untouched pages alone), commit. A stale `lastmod` tells crawlers "nothing changed" and delays re-indexing of exactly the pages you just improved. Reference incident (2026-06-28, example): the 7 SSR-converted pages shipped with `lastmod` still at 2026-03-08/04-01 — fixed in a follow-up commit `e9fcee8`; this gate makes it automatic. |
| 1.4a | OG/social preview metadata | Public sites have title, description, canonical URL, OG/Twitter tags, and a 1200x630 share image; create them if missing. **improvebayarea:** every ship MUST OCR `public/og.jpg` vs `CITIES.length` (`vitest run src/ui_cities.test.ts`) — HTML tags can say 25 while the JPEG still says 21. |
| 1.4b | **Favicon presence (EVERY HTML site — MANDATORY)** | Every site `/ship` deploys must serve a favicon. Verify the served `<head>` carries a `<link rel="icon">` (or a `/favicon.ico`/`/favicon.svg`/`/favicon.png` route returning `image/*`). Check the live URL when public; when the page is auth-gated (CF Access 302 → can't curl the HTML), verify presence in the repo's rendered head template (`grep -rniE 'rel=.icon\|favicon' src/`) AND on the deployed page via the logged-in REAL Chrome (fcdp) (`document.querySelector('link[rel=icon]')`). If absent, AUTO-FIX: add a self-contained **inline SVG data-URI** `<link rel="icon">` to the `<head>` — base64-encode the SVG (`data:image/svg+xml;base64,…`) for bulletproof cross-browser rendering, pick a glyph that fits the app; if the page sets a CSP, add `data:` to `img-src` (safe — data images can't execute). Redeploy, then browser-verify the link is present, decodes to valid SVG (DOMParser, no `parsererror`), and renders. Skip ONLY for pure non-HTML workers (API/CLI only, no served HTML). Codified 2026-07-13 after adding favicons to seal + fax + diy-fax by hand three times in one session. |
| 1.42 | Deploy session invalidation | Handlers exist |
| 1.45 | Third-party config, XSS, auth guards | No blockers |
| 1.45a | Production auth instance + Worker binding dry-run | No dev auth fingerprints; provider domain complete |
| 1.45b | External municipal form fallback regression + structured-location shape (backend-agnostic) | Changed category/form submit paths have fallback tests AND, when ANY 311 backend's structured-location code changed (Verint `sf_full_address`/`Location_description`/`sf_*`; SCF `address`/`location_details[*]`; future backends), a regression test exercises (a) a **long-form** `"NNN Street, City, ST, NNNNN"` input, (b) an **empty** input, (c) a **coord-string** `"<lat>, <lng>"` input — none of which can land in a structured slot. Pattern #21. |
| 1.45c | Third-party response signal-extraction fixtures (success + failure) | Any parser that classifies a third-party HTTP response into `{ok, ...}` (DBI complaint replay, Verint dform save, OAuth callback, webhook verifier, scraper detector) must ship with a captured **real success** AND a captured **real failure** response under `__fixtures__/`, plus a `tools/repro/<integration>-probe.{sh,mjs}` script. Tests must `readFileSync` the fixtures — synthetic hand-written HTML cannot detect heuristic drift between success and failure pages that share 99% of their structure. Pattern #23 + `~/.claude/skills/shared/third-party-signal-fixtures.md`. |
| 1.45d-prec | **Implicit-precedence merge (when the diff touches a collection filled from 2+ sources, or a payload carrying overlapping representations of one value)** | Run `~/.claude/skills/shared/tools/single-winner-merge-check.sh <repo-root>` — exit 1 BLOCKS. Flags any collection filled from ≥2 sources and consumed at index 0 with no precedence comment at the declaration and no test pinning the order. Clear it by declaring the winner and adding an order test **proven armed by re-injecting the original order** — not by silencing the check. Order is not a type, so tsc/lint/tests are all green while the wrong value ships. Pattern #37. Reference incident 2026-08-24: reposting a 311 report with a new photo filed the ORIGINAL image to the city, silently. |
| 1.45d | **External link integrity — EVERY ship of a site that renders external citations, NOT only when the diff touches a URL** | Run `~/tools/linkcheck.sh <repo>`: it greps all `https?://` links from `src/`, curls each, and on any non-200 re-tests through the REAL Chrome profile (fcdp) to separate a **genuine 404/410 (BLOCK + fix)** from a **government/WAF bot-block of curl (403/000 but 200 in a browser → fine)**. Curl-only checking false-positives on `.gov` (ag.ny.gov, health.ny.gov, otda, nysenate, congress.gov). ⚠️ **The trigger is deliberately NOT diff-conditioned, and that is the whole point: link rot happens with NO diff.** A URL that was correct when written goes dead because the agency reorganised its site, so the citations most likely to be broken are the OLDEST ones — exactly the ones no changeset ever touches. Gating this on "the diff edited a URL" guarantees you only ever check the links that were just verified. ⚠️ **200 ≠ supports the claim.** A replacement that merely resolves is still a broken citation if the page does not contain the cited fact — check the number is actually in it, following a linked PDF when the landing page is only a wrapper (apply the Full-Document Read text-layer gate before grepping that PDF). ⚠️ **Never construct the replacement URL.** Read the site's own sitemap (`robots.txt` → `sitemap.xml`, following a sitemap INDEX one level down) or its rendered hrefs. Reference incidents: 2026-06-05 NYIA `/help` shipped a malformed POA URL (`...short-formpdf` → 403) guarded by a "do not alter" comment. 2026-08-26 16bedlimit shipped TWO dead citations neither of which the changeset had touched — an FEC super-PAC page (404, agency reorganised) and a TAC report host (dead AND unarchived at that path); the FEC replacement's landing page returned 200 while the cited figure lived only in a linked PDF, and two guessed replacement slugs 404'd before reading the sitemap produced the real one. |
| 1.45e | **Embed + rendered-href integrity (when the changeset touches an `<iframe>`, a prose→HTML renderer, or any URL literal)** | (a) Every `<iframe>` whose `src` is a **referrer-sensitive host** (`youtube.com`, `youtube-nocookie.com`, `player.vimeo.com`, `open.spotify.com`, `w.soundcloud.com`, `players.brightcove.net`) MUST carry `referrerpolicy="strict-origin-when-cross-origin"` **if the site sends `Referrer-Policy: no-referrer`** — which is Hono `secureHeaders()`'s DEFAULT. Without it YouTube renders "Error 153: Video player configuration error" (CSP `frame-src` being correct does not save you). Check the header with `curl -sI https://<prod>/ \| grep -i referrer-policy`. (b) No **rendered** `href` may contain whitespace — that means a markdown/prose renderer swallowed trailing text into the URL (`…/watch?v=ID - explains fault indicator`), which only "works" because YouTube truncates ids at 11 chars. (c) No malformed URL literal (`https://.join.slack.com` → NXDOMAIN) and every YouTube id is exactly 11 chars of `[A-Za-z0-9_-]` (catches `watch?v=_SiFQ_4m0\|E`). **Verify against the DEPLOYED artifact, not source** — `hono/jsx` vs React attribute casing can drop `referrerpolicy` silently — then load it in a real browser and confirm the player renders. Allow >30s for Worker propagation before calling a post-deploy curl a failure. **If a fix autolinks previously-inert prose URLs, every newly-created anchor must be validated before deploy** — inert bad text becomes a live broken link. Reference impl: `tools/check-links.mjs` in the TISF repo (static + `--url` rendered mode, wired into `bun run build`); reference incident 2026-07-09 (Error 153 on the homepage; 3 hrefs with prose inside them and 7 dead-text URLs on `/blog`). Full pattern: `~/.claude/skills/debug/references/csp-cache-patterns.md` #27. |
| 1.45f | **Account-security lifecycle (when auth, session, passkey, TOTP/2FA, password, recovery, or sign-out code changes)** | Load `~/.claude/skills/shared/account-security-lifecycle.md`. BLOCK until the installed SDK source is inspected; every session-creation path challenges enrolled users; challenge responses expose no provisional session/bearer; sensitive management requires a fresh server session; passwordless and credential accounts both have negative/positive tests; actual passkey reauth, same-origin return routing, returned-error handling, reset revocation, and authoritative status verification are covered. |
| 1.45g | **Experience Cloud / Aura 311 catalog + submit envelope (when Salesforce/Aura catalog, `fetchCaseTypeDetails`, `submitCase`, or KV catalog cache changed)** | Structural tests must prove: (a) toast/`validateAddress` fixture unwraps to locator keys (`address`/`location`), **not** `toastPayload`; (b) every id-bearing type has `caseConfigId`+`sCaseType` **or** explicit `captureFailure` — 0 dummy `modelFlags`; (c) refuse strings name official field API names (`Permit_Number__c`), not class stubs; (d) catalog schema change bumped the KV cache key. Post-deploy: cache-busted `GET /api/categories` matches those counts. Pattern #36. |
| 1.46 | Admin-user portal sync verification | No BLOCK findings |
| 1.54 | **Partial-wiring gate — one config value, several consumers (added 2026-08-24)** | Fires when the diff adds a config/env value that MORE THAN ONE consumer must read (a URL used by both a rendered tag and a CSP; a flag read by both a route and a cron; a key used by both the client snippet and the server). **Enumerate the consumers and prove EACH one receives it** — `grep` the new identifier and count the read sites, then confirm every builder/config object that feeds a consumer actually passes it through. Order and threading are not types: TypeScript, lint, and the whole test suite pass while one consumer silently falls back to its default. The tell is a live page that is internally inconsistent — e.g. a CSP naming host A while the script tag still points at host B. Only a post-deploy read of the served artifact exposes it. Reference incident 2026-08-24 (improvebayarea): `TRAKS_COLLECTOR_URL` was threaded into the per-request CSP builder but never into the `AnalyticsConfig`, so the snippet kept the default `*.workers.dev` origin under a CSP that allow-listed only the first-party host — `tsc` 0 errors, biome clean, 2,438 tests green, caught solely by curling production. |
| 1.55 | Hot-path data-volume & cache-topology (when route handlers / crons / caches / queries changed) | No per-request query reads >~100k rows; every cache-key read has a writer; cache-warmer crons warm the *exact* keys the routes read; lagged-source trailing windows anchored on `MAX(ts)` not `now()`; TEXT-timestamp range scans use the index. **PLUS the account-wide D1 read budget** — a single repo's scan can consume the whole account's included allowance and surface as a surprise invoice on an *unrelated* project. Query it: `d1AnalyticsAdaptiveGroups{sum{rowsRead} dimensions{databaseId}}` over 30d via the CF GraphQL API. WARN at >25% of the 25,000,000,000/mo Workers-Paid inclusion; investigate any single database that is >90% of the account total. Reference finding (2026-07-10): `improvebayarea` read **8.72 billion** rows in 30 days — 99.99% of the account and 34.9% of the inclusion — while AIVA read 1.0 million. |
| 1.55a | **Self-inflicted load — a scheduled job that hammers your own origin (when the diff touches a `scheduled()`/cron body, a prewarm/warmer, a poller, or a self-directed health check)** | Three checks, all cheap, all missed by every other gate because a self-request is indistinguishable from a visitor's per-request. **(a) NO SELF-FETCH OF A CUSTOM DOMAIN.** A Worker cannot `fetch()` its own Custom Domain: Cloudflare does not re-dispatch a same-zone subrequest into the Worker, it forwards to the *zone origin*, and a Workers-only zone has none — `AAAA 100::` (RFC 6666 discard) ⇒ **522 / origin=0 on every call, forever**. Grep the diff for a `fetch()` whose host is any `custom_domain = true` route in `wrangler.toml`; the guard must compare the **exact** canonicalised host (strip one trailing root dot — `https://example.com./x` parses to hostname `example.com.` and slips past a plain list test — but never suffix-match, or `example.com.evil.com` matches). CF docs: `workers/configuration/routing/routes`; workerd#787. **(b) EVERY scheduled `fetch` CARRIES A TIMEOUT** (`AbortSignal.timeout`) — an unbounded subrequest is how a cron converts one slow upstream into a wall of 522/524. **(c) THE WARM MUST ACTUALLY WARM.** Read `cf-cache-status` on a warmed URL well after the run (not seconds after); still `MISS` ⇒ the warmer has never worked and its cost is pure loss. **And attribute post-deploy:** the proof a cron fix landed is the NEXT scheduled run producing zero 5xx — group `httpRequestsAdaptiveGroups` by `datetimeMinute` across it. Reference incident 2026-08-29 (improvebayarea): the hourly prewarm self-fetched all 43 cities + `/map/oakland`, producing **523/523 of the zone's 522s at :02–:03 past the hour** = a measured 32.5% 5xx rate, zero users affected — while every manual probe returned 200. Its unit test asserted the self-fetches *should happen* and passed for months because a mocked `fetch` returns 200 and cannot observe the failure. Pattern #40. |
| 1.56 | **D1 schema-drift / migration-applied-to-prod (when the diff touches any D1 `INSERT`/`UPDATE`/`SELECT` column set, adds a `migrations/*.sql` file, or references a new column/table)** | Every column the changed worker code writes MUST exist in the **remote** D1 (`PRAGMA table_info` — the migration FILE and the local D1 are NOT proof), and `wrangler d1 migrations list --remote` must be clean. Run `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>` — BLOCK on any code-referenced column/table missing in prod (it will 500 every write to that table) or unapplied migrations. Fix: apply only the missing DDL additively to remote, `INSERT OR IGNORE` its filename into `d1_migrations`; NEVER bulk `wrangler d1 migrations apply` (re-runs non-idempotent data migrations → corruption). See `~/.claude/skills/shared/d1-schema-drift.md`. Reference incident: 2026-07-05 AIVA `POST /api/intake` 500'd for every user — `mos` in code + migration file but never applied to prod. |
| 1.56b | **Negative-control gate (#33) — fires when the diff adds/changes a health check, liveness probe, validator, drift/reconciliation job, monitor, verification sweep, or a scheduled job whose output is a pass/fail claim; ALSO when the ship's rationale cites a green result ("N/N verified", "all healthy", "the sweep is clean")** | **BLOCK until the instrument has been shown to FAIL on a known-bad input.** A check that cannot fail is not a check, and the green direction is the dangerous one — nothing about a passing board prompts anyone to look. Require: (a) a named known-bad input (corrupted token, mutated id, nonexistent resource, malformed payload) that makes the probe go RED; (b) that control **committed as a test**, with its reason in the test body so a future reader doesn't delete it as redundant; (c) three outcomes in the result type, never two — `ok` / `genuinely bad` / `could not measure` (collapsing the third into the second fires false alarms on an upstream redesign; into the first is the vacuous case). **Echo is not validation** — an upstream that reflects your value back has not checked it. If the changeset RETRACTS a prior finding on the strength of a new clean measurement, that measurement gets this gate too. Corollaries also blocking: a hardcoded `verified:`/`lastChecked:` date on upstream-harvested data shipped as a health signal (rename to `harvestedAt` + add the scheduled re-check + mark stale past ~2 intervals); a join on an upstream id without checking published ALIAS keys; a dataset field whose absence degrades silently with no completeness invariant. Reference incident 2026-08-10 nps-report: the planned probe (`GET sendemail.cfm?o=<token>` → is a form returned?) reported 20/20 park mailboxes healthy and was killed by one negative control — `o=DEADBEEF00` returns HTTP 200 and a full form, so 435 dead tokens would have scored 435/435. The replacement (is the token still published on the park's own contacts page, following redirects) found **5 of 435 drifted**. See `~/.claude/skills/shared/negative-control-gate.md`. |
| 1.56a | **Management-API-vs-authoritative-state (#31) — fires when the changeset DELETES or disables any cloud/provider resource (DNS record, certificate, cert pack, route, binding, bucket, queue, cron trigger, worker), or when the ship's rationale rests on a management-API read ("the API shows X is missing", "nothing references this")** | **BLOCK any deletion whose justification is a management-API read alone.** That API returns what was *declared* — not what the platform *injected on your behalf*, and never *why* a resource exists. Two proofs required before the delete ships: (1) **provenance** — `GET /audit_logs` (or the platform equivalent) names what created it; `actor.type: system` means the platform provisioned it and something depends on it. (2) **consumer view** — probe what actually consumes the state (`dig` not `dns_records`; `openssl s_client` not the cert list; `PRAGMA table_info --remote` not the migration file; `wrangler secret list` not `vars`; a delivered message's `Authentication-Results` not your SPF record). A count mismatch between the declared and authoritative views **is the finding** — resolve it before shipping. **You cannot delete a resource you cannot name the creator of.** See `~/.claude/skills/shared/management-api-vs-authoritative-state.md`. Reference incident 2026-07-28: 20 advanced cert packs read as "redundant" from the cert-pack API were Cloudflare's auto-provisioned Worker custom-domain certs (8 packs ↔ 8 Worker domains; 11 zones with 0 Workers had 0 packs) — the recommended cleanup would have dropped TLS on `fax`/`seal`/`ecobee`/`vatoken`/`nydoc`/`susu`. Same session, same API: CF `dns_records` reported 5 CAA records missing `issuewild "pki.goog"` while `dig` returned 11 including it → a phantom outage that would have "fixed" a healthy zone. |
| 1.56c | **SQL constraint validation (when the diff adds/changes any `INSERT`/`UPDATE` writing an enumerated, bounded, or otherwise constrained value)** | `PRAGMA table_info` and `EXPLAIN` are BOTH structurally blind to CHECK constraints — PRAGMA reports columns (a CHECK is table-level, not a column), `EXPLAIN` plans without evaluating. Two green instruments, and the write still throws on every execution. **Read the real DDL**: `SELECT sql FROM sqlite_master WHERE type='table' AND name='<t>'`, then prove the value satisfies the predicate WITH A NEGATIVE CONTROL — `SELECT '<new>' IN (...) AS new_ok, '<old>' IN (...) AS old_ok` must return `new_ok=1, old_ok=0`; if the control also passes, the test proves nothing. Extra weight when the write sits inside a best-effort `.catch()` (audit logs, analytics, telemetry): a constraint violation there is **silent**, so the symptom is not an error but an empty table nobody looks at until it is needed as evidence. Also confirm any `ON CONFLICT(col)` target is genuinely UNIQUE from the DDL, not PRAGMA. Reference incident 2026-08-12 (AIVA): `sms_consent_log.consent` is `CHECK (consent IN ('granted','declined','revoked'))` while the code wrote `"1"`/`"0"` — EXPLAIN-validated and PRAGMA-verified clean, would have recorded zero consent records while reporting success. See `~/.claude/skills/shared/d1-schema-drift.md`. |
| 1.57 | Observability / instrumentation (when the diff adds/changes external calls, `catch` branches, state transitions, or new error paths) | **OPAQUE-UPSTREAM DISCRIMINATOR (Pattern #32, added 2026-08-03): if the changed code calls an upstream that can reject for MORE THAN ONE reason with the SAME error string/status, the failure path MUST report the measurable properties of what was sent** (lengths + boolean flags — never the payload, it can carry user PII), e.g. `[desc len=664 dslash=false astral=false http=false]`. Without it, each single-cause fix looks byte-identical to no fix and every diagnosis costs a deploy cycle (reference: Solve SF `/submit` — 5 causes behind one `400 {"error":"Invalid"}`, ~6 deploys). See `~/.claude/skills/shared/opaque-multi-cause-failure.md`. Changed code is debuggable in prod BEFORE it ships: structured logs at those boundaries (`log({event, ...attrs})`, secrets/PII redacted); every new `catch` records what was attempted + the real upstream reason (nothing swallowed); no new catch-all/ambiguous error message (split two-root-cause strings). Deploy-gate form of /carmack's instrument-on-build rule. See `~/.claude/skills/shared/observability-instrumentation.md`. Skip for pure docs/test/copy diffs. **Now mechanically testable, not just reviewable:** the CF integration harness (Phase 1.3d) exposes `getLogs(): WorkerdStructuredLog[]` + `clearLogs()`, so you can assert a `catch` branch actually emitted the right structured event instead of eyeballing the diff — e.g. `clearLogs()` → trigger the failure path → `expect(getLogs().filter(l => l.level === "error"))`. Prefer asserting **diagnosability** over a specific status: a route that 503s locally because a binding is absent is fine; a route that fails with an empty body AND no logs is the actual defect, because an operator has nothing to debug from. |
| 1.58 | **Provider / SDK swap safety (when the diff replaces a third-party provider — email, auth, payments, storage, SMS, LLM gateway — or does a major SDK bump within one vendor)** | Run `~/.claude/skills/shared/tools/provider-swap-check.sh <repo> --old-prefix <OLD> --new-binding <NEW> --seam <path>` (exit 2 = BLOCK; verified to fire on all breakage classes 2026-07-10) plus the 7-item checklist in `~/.claude/skills/shared/provider-migration-safety.md`. BLOCK on any of: (a) any feature guard still naming the OLD provider's env var (`rg "env\.OLD_[A-Z_]+"` must be empty — including `CRITICAL_ENV_VARS`/startup validators, which will brick boot once the secret is deleted); (b) more than one module calling the new SDK directly (there must be exactly one seam) or a result type that is not a discriminated union — a non-throwing `{data,error}` SDK turns every failure into a silent success (11/13 AIVA call sites never checked `error`); (c) any lookup by a persisted legacy identifier that does not discriminate on id SHAPE before querying — the new provider returns zero rows for old ids, which becomes a confident wrong status (see #29); (d) reliance on emulator behavior (`wrangler dev` does NOT enforce Cloudflare's header allowlist) without a captured real success + real failure fixture; (e) any re-enabled cron whose blast radius against **prod** data was not counted and human-approved before its first fire. Also: `rg -l "<vendor>" ~/projects ~/tools` before decommissioning the old account — another repo may hold a live key on the same verified domain. Reference incident: AIVA Resend→Cloudflare, 2026-07-10, all four breakages shipped before being found by hand. |
| 1.59 | **Consent / audit-evidence integrity (Pattern #35 — fires when the diff adds or changes a field whose STORED value is later offered as proof: SMS/TCPA consent, ToS acceptance, HIPAA authorization, cookie/GDPR consent, e-signature attestation, age verification, any opt-in/opt-out)** | Full pattern: `~/.claude/skills/shared/consent-evidence-integrity.md`. BLOCK on any of: (a) **collectors ≠ writers** — count consent-collecting UI surfaces vs code paths that actually persist, and require one shared writer with a `source` column (a checkbox whose value is discarded is WORSE than no checkbox: the user affirmatively believes they consented and no record exists); (b) an **exhaustive-deps warning on an evidence value** — a `useCallback`/`useEffect` closing over a stale consent boolean records a checked box as a DECLINE, so treat that lint as a P1 correctness bug, never a nit; (c) **schema-strictness mismatch** — a non-strict zod object SILENTLY STRIPS the new field (evidence vanishes, request succeeds) while a `.strict()` one 400s the entire form; check the specific schema and land the server field first; (d) **dedup that discards evidence** — `INSERT OR IGNORE`/`ON CONFLICT DO NOTHING` skips a returning user who consents today; consent is an EVENT, so the primary store must be append-only with an explicit `DO UPDATE` only for queryable current state; (e) **client-supplied disclosure text** — the wire carries the boolean only, the server writes the canonical text+version from a shared constant, or the record is forgeable and worthless; (f) **affirmatives-only logging** — declines must be recorded too, else an absent row cannot distinguish *declined* from *never asked* from *the writer is broken*. Verify by round-tripping BOTH outcomes per surface, confirming an unchecked box still submits (consent may never gate unrelated service — TCPA non-conditioning), and `EXPLAIN`-validating the SQL against the REMOTE schema (`tsc` and `--dry-run` do not execute SQL; a malformed statement breaks every submission) plus confirming the `ON CONFLICT(col)` target is actually UNIQUE. Reference incident 2026-08-12 (AIVA A2P 10DLC): three consent checkboxes shipped, **two wrote their value nowhere**, the third would have recorded opt-ins as declines via a stale closure, `INSERT OR IGNORE` was dropping returning users' consent, and the four D1 columns + a purpose-built `sms_consent_log` had existed unwired in prod the whole time — all of it typechecking, linting, and passing 106 tests. |
| 4.07 | **Email deliverability (when the diff touches email-send code: a `send_email` binding, an email provider seam, a From address/`NOTIFY_FROM`, or SPF/DKIM/DMARC config)** | `~/.claude/skills/ship/tools/email-deliverability-check.sh <repo> --domain <sender-domain> --accounts <dest mailboxes>` — STATIC: BLOCK any From literal on an APEX domain whose MX is a hosted mailbox (Google/Microsoft) — same-domain strict SPF/DMARC junks it (the 2026-07-13 diy-fax class: send() resolved, mail landed in SPAM); WARN if the sender domain isn't in `wrangler email sending list`. LIVE (post-deploy): trigger a REAL send via the app's own event, then BLOCK if the newest message from the sender domain is labeled SPAM in the destination mailbox or `Authentication-Results` lacks `dmarc=pass`; no-message-found = UNVERIFIED warn (absence isn't proof — re-trigger). "Send resolved" ≠ "delivered to inbox"; only reading the destination mailbox proves placement. |
| 4.08 | Workers-Cache post-deploy verification (when the `cache` block was enabled/modified) | Staged enable; t+15/45/90s multi-route-class monitoring (<60s checks are NOT evidence — propagation >30s); semantic Cache-Control per class + HSTS present; sitewide-3xx tripwire → auto-disable + `wrangler tail` scheme probe |
| 4.09 | Worker surface exposure + AUTO-HEAL (CF API probe: `tools/worker-surface-check.sh --apply`, runs EVERY ship — the surface regresses on each `wrangler deploy`) | previews_enabled=false everywhere; workers.dev disabled on custom-domain workers; re-probe confirms closed + canonical URL 200 |
| 4.05 | Site security defaults (live URL) | All baseline items pass — security.txt, **sitemap.xml (must exist if robots.txt advertises it)**, HSTS, CSP, X-*, COOP/CORP. Cloudflare API items (TLS min, DNSSEC, CAA) auto-fix when creds available. |
| 4.05a | **CF zone-level security enforcer** | always_use_https=on, automatic_https_rewrites=on, min_tls_version=1.2, tls_1_3=on, opportunistic_encryption=on, ssl≥full, zone-HSTS on (preload), 0-RTT=on — auto-PATCHed via CF API. **Bot protection excluded by design.** |
| 4.05d | **Account-wide CF Security Insights sweep** (replaces the paused `cf-security-watch` cron) | `~/.claude/skills/carmack/tools/cf-security-insights.sh --apply` — sweeps ALL zones AND all Workers (not just the deployed one). Zone fix: edge security.txt. **Worker fix: `previews_enabled=false` on EVERY worker** — the `<name>.cloudflare.app` preview hostnames are what CF flags as "missing TLS Encryption" / "without Always Use HTTPS" / "without HSTS" (2026-07-07: 17 workers alerted; 13 more were one scan-wave away — Phase 4.09 alone only covers the deployed repo). **AI-bots-block + AI Labyrinth are NO LONGER applied** (user directive 2026-07-07: AI bots must reach the sites for AI/LLM SEO — both hurt that; report-only now). Auto-SKIPS the judgment-call classes (Bot Fight, unproxied-CNAME, dangling-A, DMARC). Advisory (never blocks the ship). |
| 4.05e | **Account-wide CF zone/DNS security-harden** (`~/.claude/skills/carmack/tools/cf-account-harden.py`) | `DRY_RUN=0 python3 …/cf-account-harden.py` — sweeps ALL zones and applies the free zone/DNS security layer, idempotently: **DNSSEC** (enable where off — CF-registrar auto-publishes the DS), **Free WAF Managed Ruleset** (deploy `id=77454fe2d30c4220b5701f6fdfb893ba` in `http_request_firewall_managed` — Free plan, high-impact/zero-day CVE coverage), **Leaked-Credential detection** (`leaked-credential-checks.enabled=true`), **CAA** (add the CF Universal-SSL partner-CA union so cert renewal never breaks). Mail-touching fixes (no-mail-domain SPF/DKIM/DMARC lockdown; a `p=none→quarantine` bump) are GATED behind `INCLUDE_MAIL=1` (account-specific; a real sender must not get `p=reject` blind). Verified live 2026-07-07 across 18 zones. Advisory. |
| 4.05b | **CSP header + a11y baseline (every public site)** | Live response carries a `Content-Security-Policy` header (not just the other security headers) — if absent, AUTO-FIX inline (Hono `secureHeaders({contentSecurityPolicy})` or equivalent), allow-list ONLY what islands load, **browser-verify islands still render under it (0 `Refused to…Content Security Policy` console violations)**, redeploy. AND a11y: exactly one content `<h1>` per page + no skipped heading levels (a logo/wordmark must be `<span>`/`<div>`, never `<h1>`); all text WCAG-AA contrast (≥4.5:1; 3:1 for large/bold ≥24px). Auto-fix in source + redeploy + re-verify on any failure. |
| 4.05f | **Organization entity anchors (`sameAs`) — EVERY public site, every ship** | Run `~/.claude/skills/ship/tools/entity-sameas-check.sh <live-url> [--min N] [--forbid REGEX]`. The live page must carry a schema.org Organization/NGO node with a non-empty `sameAs`, and every URL in it must resolve. Google lists `sameAs` under Organization's RECOMMENDED properties — "the URL of a page on another website with additional information about your organization" (checked 2026-08-24). It is the cheapest entity-reconciliation signal there is: one JSON block, free, no third-party script. **State the claim honestly in any report — it is a HINT for entity understanding, NOT a ranking factor and NOT a Knowledge Panel guarantee.** Three outcomes: ok / bad (no node, empty `sameAs`, or a 404/410 URL) / unknown (page unreachable, no ld+json — never reported green). A 403 or 000 from LinkedIn/X/SAM is **UNVERIFIED**, not dead — a WAF wall is not a missing profile. ⛔ **NEVER invent a URL to satisfy this gate.** A plausible slug is a fabrication with a valid shape: verified 2026-08-24, `linkedin.com/company/example-nonprofit` 404s while `linkedin.com/company/example` is real, and only a browser check told them apart. Legitimate sources for a candidate are exactly three: a link the site ALREADY publishes, an authoritative registry looked up by a real identifier (EIN → ProPublica/Candid; UEI → SAM), or the user. ⛔ **ENTITY-CONFUSION IS THE WORSE FAILURE.** Use `--forbid` to keep one legal entity's identifiers off another's site. Live example: Example Nonprofit Inc. (501(c)(3), EIN 00-0000000) and Example Tech / Example LLC (for-profit) share a brand — copying the nonprofit's IRS/ProPublica/Candid links onto `example.org` would assert tax-exempt status for a consulting business. That is a misrepresentation, not an SEO tweak, and it outranks any coverage benefit. Personal profiles (a founder's own LinkedIn/GitHub) belong on a Person node, never in an Organization `sameAs`. |
| 4.05b-edge | **🛑 EDGE-INJECTED SCRIPTS — a CSP written from your source is INCOMPLETE by construction (added 2026-08-24)** | **Cloudflare injects `static.cloudflareinsights.com/beacon.min.js` into HTML responses AT THE EDGE, after your Worker returns.** It is NOT in your origin HTML, so `curl \| grep` finds nothing, no test sees it, and a CSP you derived from reading `src/` **silently blocks it**. Nothing fails server-side; the ONLY symptom is a browser-console violation. Any zone with CF Web Analytics on is affected, whether or not the repo ships a `CF_BEACON_TOKEN`. **So: writing or tightening ANY CSP REQUIRES a live browser console check — a source review can never be sufficient.** Baseline allowances for a CF-fronted site: `script-src https://static.cloudflareinsights.com` + `connect-src https://cloudflareinsights.com`. Verify with `fcdp open <url>` then `fcdp console --secs 5 \| grep -ic "violates the following content security policy"` → must be **0**, on EVERY site touched, not a spot-check. Same family as edge-injected Rocket Loader / Email Obfuscation / Bot Fight JS. Reference incident 2026-08-24: adding a first CSP to `diy-fax` blocked the beacon, and the same sweep found the identical violation **pre-existing** on 4 other sites whose CSPs had never been console-verified — invisible for months because every check had been `curl`-based. |

**If a phase finds issues, FIX THEM INLINE before moving to the next phase.** Do not defer. Do not warn-and-continue for fixable issues. The goal is: every `/ship` run leaves the repo in a strictly better state than it found it.

**Warnings are NOT acceptable.** `biome check .` must return 0 errors AND 0 warnings. Fix warnings by: (1) auto-fixing with `biome check --fix`, (2) manually fixing remaining issues, or (3) suppressing false positives in biome.json overrides with justification. "Pre-existing warnings" is not an excuse — fix them all.

**Dependabot is NOT optional.** If `gh api repos/{owner}/{repo}/dependabot/alerts` returns open alerts with available fixes, add overrides to `package.json`, run install, verify build, commit, and push — all within this run.

**Transitive Dependabot alerts need `overrides`, not removal (MANDATORY — 2026-05-19).** If an alert stays open after the package was removed as a *direct* dependency, it is still pulled *transitively* — run `npm ls <pkg>` to see the path (e.g. `wrangler → miniflare → ws`). `npm uninstall` of the direct dep does NOT clear it. Pin the safe version with an `overrides` block in `package.json`, `npm install`, then verify the resolved version with `npm ls <pkg>` AND `npm audit`. Note `npm audit --omit=dev` can read 0 while Dependabot still shows the alert — Dependabot scans the whole lockfile incl. dev. Reference incident: `ws@8.18.0` alert stayed open after `npm uninstall ws` because `wrangler → miniflare` still pulled it; `overrides: {"ws": "^8.20.1"}` resolved it.

**Stale lockfile check (MANDATORY).** Before fixing Dependabot alerts, check which lockfile(s) the alerts reference (`manifest_path` in the API response). If alerts reference a lockfile the project doesn't use (e.g., `pnpm-lock.yaml` when project uses `bun.lock`), the stale lockfile MUST be deleted from git and added to `.gitignore`.

```bash
# Detect active package manager
ACTIVE_LOCK=""
[ -f bun.lock ] && ACTIVE_LOCK="bun.lock"
[ -f pnpm-lock.yaml ] && ACTIVE_LOCK="pnpm-lock.yaml"
[ -f package-lock.json ] && ACTIVE_LOCK="package-lock.json"

# Remove any OTHER tracked lockfiles that aren't the active one
for STALE in pnpm-lock.yaml package-lock.json bun.lock yarn.lock; do
  if [ "$STALE" != "$ACTIVE_LOCK" ] && git ls-files --error-unmatch "$STALE" 2>/dev/null; then
    git rm --cached "$STALE"
    echo "$STALE" >> .gitignore
    echo "Removed stale lockfile: $STALE (was causing false Dependabot alerts)"
  fi
done
```

## AIVA / Cloudflare Worker Hard Gates

When shipping AIVA or any Cloudflare Worker/static-assets site, `/ship` must verify the real production path, not just a clean local build:

1. **Prove the deploy target** — inspect `wrangler.json`/`wrangler.toml` routes and recent `wrangler deployments list` output before changing production.
2. **Use a clean build path** — remove stale `dist`, run the same TypeScript mode the repo uses for production (`tsc -b` when project references exist), run `vite build`, and run the repo asset guard before `wrangler deploy`.
3. **Block plaintext Worker secrets** — names matching `KEY|SECRET|TOKEN|PASSWORD` must not live as literal values in `wrangler.json` `vars`; they belong in `wrangler secret` bindings.
4. **Handle binding-name conflicts deliberately** — if `wrangler secret put` reports that a binding name is already in use, remove the plaintext var from config, deploy without `--keep-vars`, immediately put the secret, then verify `wrangler secret list` reports `secret_text`.
5. **Do not use `--keep-vars` when cleaning plaintext vars** — it preserves the stale plaintext binding you are trying to remove.
6. **Verify live HTML and CSP** — fetch the production URL with a cache buster and prove expected prod domains are present while dev fingerprints are absent. **AIVA and improvebayarea now run FIRST-PARTY Better Auth (cutover 2026-08; the old vendor account is deleted)** — so the assertion is INVERTED from what it used to be: the live HTML/CSP must contain NO `clerk.*` host, no `pk_live_`/`pk_test_`, and no `.clerk.accounts.dev`. Auth lives at `/api/auth/*` on the site's own origin. ⚠️ improvebayarea legitimately renders the string "City Clerk" ~17 times (municipal public-records URLs) — match on `clerk\.<domain>`/`clerk-js`/`@clerk/`/`pk_(live|test)_`, never a bare case-insensitive `clerk`.
7. **Run the account-security lifecycle gate when applicable** — distinguish enrollment, challenge enforcement, enrollment policy, and recovery; test every session-creation path and sensitive management path; and verify authoritative status without selecting secret material.
8. **Verify OG/social preview readiness** — every public site must expose `title`, `description`, canonical URL, `og:*`, `twitter:*`, and an absolute 1200x630 share image URL that returns `200` with an `image/*` content type. If missing, add the metadata and image before deploying.
9. **Run production integration** — when the repo has it, run `npm run test:integration:prod` after deploy and before reporting success.
10. **Check D1 headroom against the ceiling, not against last week** — for every D1 bound in the deploy, read `meta.size_after` (returned on every D1 response) and report it as a **% of the 10 GB per-database cap**. That cap is the one D1 limit with no documented increase path — the limits-page footnotes cover database *count* and *account* storage only. **>50% ⇒ surface it in the ship report with the percentage**, and treat >80% as blocking. Cold append-only history belongs in R2 Data Catalog + R2 SQL, not D1. Full standard, the four measured query-shape traps, and the archive runbook: `~/.claude/skills/shared/cloudflare-data-ceilings.md`. ⚠️ Do NOT claim an archive will shrink the database — D1 documents no `VACUUM` and blocks `pragma_freelist_count`; measure on a copy first.
11. **Profile Worker startup when the bundle changed** — `npx wrangler check startup` reports raw + compressed bundle size and a CPU summary (sampled / active / GC / idle) and writes a `.cpuprofile`. Requires Wrangler ≥ 4.116.0. Report bundle size against a budget; "it built fine" is not a cold-start result.

Audit output from ClawPatch, Codex, or manual review is not complete until it becomes a regression guard where practical: package-script checks, full asset scanning, secret-list verification, peer-dependency checks, bounded overrides, real a11y gating, and a local Worker integration harness with readiness/cleanup.

## Worker Preview Hostnames — LOCKED by Default (user policy 2026-07-07)

**Every worker's `<name>.cloudflare.app` preview hostname stays DISABLED (`previews_enabled=false`) unless the user explicitly approves exposing it — a bare `/ship` or task instruction is NEVER preview-publish consent.** Preview hostnames bypass ALL zone security (Always-HTTPS/HSTS/WAF/Access are zone-level; `cloudflare.app` is not your zone) and are exactly what CF Security Insights flags as "Domains missing TLS Encryption" / "without Always Use HTTPS" (17 workers alerted 2026-07-07).

- **To expose a preview**: AskUserQuestion first, offering (a) **Access-gated** (RECOMMENDED — enable preview + Cloudflare Access on preview URLs: dash → Workers & Pages → *worker* → Settings → Domains & Routes → Enable Cloudflare Access, policy = you@example.com / named collaborators; supported per developers.cloudflare.com/workers/configuration/previews/, fetched 2026-07-07) or (b) fully public temporarily. Only after an explicit yes, run the enabling command prefixed `CLAUDE_ALLOW_PREVIEW_PUBLIC=1`.
- **Enforcement (3 layers)**: PreToolUse hook `pre-preview-lock-guard.sh` blocks any Bash/Edit/Write that sets `previews_enabled`/`preview_urls` true without the env override; Stop hook `preview-lock-stop-check.sh` sweeps the account after any deploy session and blocks stop while a preview is open; Phases 4.09 + 4.05d re-close previews on every ship (wrangler deploy silently re-enables them).
- **User-approved exposures**: re-apply AFTER the Phase 4.09/4.05d sweeps in the same run, and state the still-open preview in the final report.

**After fixing Dependabot alerts, VERIFY they actually closed.** Wait 60s after push, then re-check:
```bash
sleep 60
REMAINING=$(gh api "repos/${REPO}/dependabot/alerts" --jq '[.[] | select(.state=="open")] | length')
if [ "$REMAINING" -gt 0 ]; then
  gh api "repos/${REPO}/dependabot/alerts" --jq '.[] | select(.state=="open") | "\(.number): \(.dependency.manifest_path)"'
fi
```

---

## Usage

```
/ship [optional instructions]
```

## Deployment Targets

| Command | Target |
|---------|--------|
| `/ship` | **PRODUCTION** (default) |
| `/ship --staging` | Staging first, then prompt for production |
| `/ship --staging-only` | Staging only, no production |
| `/ship --audit` | Run safety audit tiers only (no deploy) |
| `/ship --audit tier2` | Run specific audit tier |
| `/ship --audit full` | Run all audit tiers |
| `/ship --watch-ci` | Block until all CI checks complete after push |
| `/ship --no-ci` | Skip Phase 4.6 CI monitoring entirely |
| `/ship --skip-review` | Skip Phase 4.2 multi-agent code review |
| `/ship --skip-perf` | Skip Phase 4.3 web performance audit |
| `/ship --skip-visual` | Skip Phase 4.35 visual regression check |
| `/ship --skip-loghygiene` | Skip Phase 5.2 post-deploy log-hygiene pass |

## Examples

- `/ship` — Deploy to **production** with full verification
- `/ship the auth feature` — Deploy specific feature to **production**
- `/ship --staging` — Deploy to staging first, then promote to prod
- `/ship --allow-lint-errors` — Override lint failures (with audit trail)
- `/ship --audit` — Run safety audit only, no deployment
- `/ship --audit tier2` — Run Tier 2 investigation audit

## Tools Available

### osgrep — Code Search During Gates
```bash
osgrep query "throw.*module scope" --mode fulltext   # Find risky patterns
osgrep query "validateClientEnv" -n 20               # Find all validation calls
```

### qmd — Documentation Search
```bash
qmd query "deployment checklist"    # Search project docs
qmd query "rollback procedure"      # Find rollback docs
```

### bd — Task Tracking (MANDATORY)
```bash
bd create --title="Deploy: run quality gates" --type=task --priority=1   # Track deployment
bd update <id> --status=in_progress                                       # Claim
bd close <id> --reason="Deployed to production"                           # Close
```

**Before running /ship**: Create a beads issue for the deployment itself (`bd create --title="Deploy <feature>" --type=task`) if one doesn't already exist. Close it only after post-deploy verification passes.

**If `.beads/` does not exist** and this is a git repo:
```bash
git config beads.role maintainer && bd init --quiet --skip-hooks
```

If `bd` is not installed, warn the user once and continue (don't block the deploy).

## CRITICAL: NO TASK MANAGEMENT TOOLS

**DO NOT use TodoWrite, TaskCreate, or TaskUpdate tools.** Use `bd` (beads) for task tracking instead. This is a project-wide rule — see CLAUDE.md "Beads Task Tracking Rule".

Print a short status line when transitioning phases:
```
-- Phase 0 OK -> Phase 1: Build & Test --
```

Just execute the phases in order. Do the work, don't track the work in TodoWrite.

## DEPLOYMENT TARGET (DEFAULT: PRODUCTION)

**Default behavior**: Deploy directly to production. The `/ship` command deploys to production unless explicitly told otherwise.

**Staging-first workflow**: If user specifies "staging first", "to staging", or `--staging`:
1. Deploy to staging/preview environment first
2. Display staging URL and verification steps
3. Wait for explicit "promote to production" confirmation
4. Then run production deployment

**Flags**:
- (default): Deploy to production
- `--staging` or "to staging first": Deploy to staging, then prompt for production
- `--staging-only`: Deploy to staging only, skip production
- `--prod` or `--production`: Explicit production deploy (same as default)
- `--no-babysit`: Skip Phase 6 PR babysitter
- `--babysit`: Force Phase 6 even on default branch (monitor CI after direct push)

## EXECUTION PROTOCOL

### CODE SEARCH

Use standard tools (Grep, Glob, Read) for code discovery. Use `osgrep` if available for AST-aware search, but never block on it — fall back to Grep/Glob immediately if unavailable.

---

## Reference Files Index

All reference files are in `~/.claude/skills/ship/references/`. Read the relevant ones for each phase.

| File | Phases | Content |
|------|--------|---------|
| `pre-deploy-checks.md` | -1, -0, 0.5 | Repo context verification, merge conflict resolution, Vercel rate limit check |
| `code-quality.md` | 0 | Biome lint auto-setup/fixing, zero-tolerance policy, AI-powered fix loop, npm audit |
| `build-and-test.md` | 1, 1.1 | Build verification, smart test execution (timeout/pkill), API contract check |
| `security-audit.md` | 1.25, 1.26 | Security audit, Dependabot auto-fix, code scanning hygiene (OpenSSF, DevSkim) |
| `react-safety.md` | 1.3, 1.35 | React scope/env safety checks, useEffect abuse detection |
| `~/.claude/skills/shared/undefined-null-render-safety.md` | 1.3a | **Undefined/null-render bug class** — 9 patterns (null-gate hides UI, unguarded property/`.map`/string/`Date`/`JSON.parse` on possibly-undefined, raw-undefined render, missing loading/empty states, backend omits a field) + post-deploy live DOM grep for rendered `undefined`/`NaN`/`[object Object]`. Cross-refs the admin blind-spot class. Reference incident: AIVA `isTest !== null` toggle silently hidden (2026-06-01). |
| `seo-and-session.md` | 1.4, 1.42 | SEO/sitemap consistency, FOUC prevention, session invalidation (chunk load recovery) |
| `infra-and-admin.md` | 1.45, 1.46, 1.5, 1.55, 1.56 | Third-party config, CSP audit, XSS checks, admin auth, infra protection, admin-user sync, risky change verification, hot-path data-volume & cache-topology gate, **D1 schema-drift / migration-applied-to-prod gate** |
| `deployment.md` | 2, 3, 3.5, 4 | Override path, GitHub push, README/changelog, Vercel/Cloudflare/Docker deploy |
| `post-deploy.md` | 4.1-4.6, 5, 6 | Post-deploy verification, multi-agent review, web perf, visual regression, rollback, CI gate, monitoring, PR babysitter |
| `ios-release.md` | 4.7 | **iOS app surface release** (absorbed /ios-ship + /app-ship 2026-06-12): scope detection (web-class → Capacitor OTA publish only; native-class → greenlight gate → manual-distribution signing → archive/export → TestFlight upload + group assignment → App Store submit → MIN_SHELL_VERSION OTA resync), App Review requirements table (live-verified), blocking rules. Development work routes to /ios. |
| `~/.claude/skills/shared/ant-verification-protocol.md` | 1.27, 1.28 | **Ant-level quality gates**: OWASP Top 10 sweep, supply chain audit, enhanced security review |
| `~/.claude/skills/shared/opaque-multi-cause-failure.md` | 1.57, 4.1 | **Pattern #32 — one opaque error, N causes**: the discriminator-first requirement for upstreams that reject for multiple reasons with one error string; instrument-liveness rules (dead `tail`, pretty-printed JSON, lagging KV) for every silence-based post-deploy claim; why a probe that stops before the failing step is blind. |
| `~/.claude/skills/shared/observability-instrumentation.md` | 1.57, 5.2 | **Observability / log hygiene**: Phase 1.57 pre-deploy instrumentation gate (changed code logs at boundaries, actionable errors, no swallowed catches); Phase 5.2 post-deploy `/log-hygiene` pass over the just-shipped worker's live logs. Downgrade-noise-never-delete; no fabricated volume. |
| `~/.claude/skills/shared/site-security-defaults.md` | 4.05, 4.05a | **Site security defaults**: 12-item baseline (security.txt, HSTS, CSP, COOP/CORP, etc.) — runs post-deploy against live URL, blocking. **Phase 4.05a** auto-PATCHes CF zone settings (always_use_https, min_tls_version, zone-HSTS, etc.) via CF API; bot protection excluded. |

---

## Phase Execution Order

**Load reference files PER-PHASE, not upfront.** Read a `references/*.md` when you reach the
phase that cites it, and only if that phase actually applies to this repo. Reading everything
first costs ~86,000 tokens before gate #1 runs (SKILL.md ~26k + `references/` ~38k + the cited
`shared/*.md` ~22k, measured 2026-07-30) — which is what degrades execution into skimming, and
a skimmed gate is a skipped gate. Most phases are N/A for any given repo: state which ones
you skipped and why, rather than pretending 58 gates ran.

### 🛑 Run every BLOCKING gate as its own command — never `&&`-chain one behind a deploy

`biome && tsc && vitest && wrangler deploy` deploys when tsc or vitest FAILS, because the
shell's exit status is not the gate's verdict and a multi-command line hides which link
broke. **Run the gate, read its result, then decide.** This is not hypothetical: in the
2026-07-30 recipe-flow ship the agent chained the gates twice and shipped past 2 failing
tests and then a tsc error — in a run whose whole purpose was to run the gates.

#### 🛑 …and never read `$?` through a pipe — it reports the LAST stage, not the gate

Same root cause, different disguise, and this one looks like it worked:

```bash
tsc -b 2>&1 | tail -5;  echo "TSC=$?"      # ← reports TAIL's status. ALWAYS 0.
```

`tail`/`head`/`grep`/`tee` succeed on the failing gate's own error text, so the
gate prints red and the line right under it prints `TSC=0`. Worse: `tail -5` can
scroll the diagnostics off-screen entirely, so you see a clean `0` and no errors.
**Capture to a file, read the real code, then look:**

```bash
tsc -b > /tmp/gate.log 2>&1; RC=$?     # RC is the GATE's
tail -20 /tmp/gate.log; echo "RC=$RC"
```

In zsh the array is `$pipestatus[1]` (1-indexed); in bash `${PIPESTATUS[0]}` — and
the Bash tool here runs **zsh**, so a copy-pasted bash idiom silently yields the
empty string, which reads as "no error". Prefer the redirect form; it is
shell-agnostic. **Rule: a gate's verdict is the number you captured on the gate's
own command — never a number printed after a pipeline, and never the absence of
visible output.**

Reference incident (2026-08-03, AIVA GV-rotation ship): `tsc -b | tail -5; echo
"TSC=$?"` printed `TSC=0` while hiding three real errors (TS2307 `node:fs`,
TS2307 `node:path`, TS2304 `__dirname` — a test placed under a Workers-scoped
tsconfig). It passed vitest, which runs in Node, so only the typecheck knew. The
gate was "run" and reported green for a full cycle.

Execute phases in this order:

0. **Phase -2**: World-state refresh (from `~/.claude/skills/shared/no-lie-verification.md` Check 1) — **MANDATORY FIRST STEP.** Run `git fetch origin --prune`, then `git log --oneline @{u}..origin/main 2>/dev/null | head -10` and `git status`. If `origin/main` has commits not in the current branch's history (other developers / other agents pushed during this session), BLOCK and rebase before any other phase. If the current branch is a PR branch and its base moved, rebase + `git push --force-with-lease` + re-verify `gh pr view <N> --json mergeable` returns MERGEABLE before continuing. **Why:** the 2026-05-18 hospital-ledger incident — /carmack agent pushed PR #2, main moved during the session (3 commits including one that touched `src/routes/home.tsx`), the PR went CONFLICTING, the agent reported "PR opened, branch tracking origin" because it never re-fetched. /ship caught it in this session; this gate makes it the FIRST thing /ship does next time.
1. **Phase -1**: Repository context verification (from `pre-deploy-checks.md`)
1.5. **Phase -0.5**: Worktree safety gate (from `pre-deploy-checks.md`) — blocks deploy if any active worktree has uncommitted or unpushed work. Last line of defense behind the auto-push hook (`post-bash-worktree-autopush.sh`).
1.7. **Phase -0.4**: Workers Cache safety gate (from `pre-deploy-checks.md` Phase -0.4; full pattern `~/.claude/skills/shared/workers-cache-safety.md`) — fires when the repo's wrangler config sets `cache.enabled: true`. Run `~/.claude/skills/ship/tools/workers-cache-check.sh <repo>`: BLOCKs the cookie-auth heuristic-cache cross-user leak (no global `no-store` default) and the request-scheme-sniff redirect-loop class (`url.protocol === "http:"` without cf-visitor — the 2026-07-06 example ~25-min sitewide 301-loop outage); WARNs on wrangler <4.69 (flag silently inert) and HSTS gated on request-URL protocol (silently dropped under the cache layer's `http://` presentation). No-op when no cache config.
1.75. **Phase -0.35**: Workers observability gate — run `~/.claude/skills/ship/tools/observability-check.sh <repo>`. Requires every wrangler config in the repo (depth 3, so a second Worker in a subdir counts) to declare `observability.enabled = true`. **This is a REGRESSION guard, not the initial fix**: on 2026-08-29 all 51 Workers on the account were switched ON directly via `PATCH /accounts/<acct>/workers/scripts/<name>/settings`, and **deploying from a config with no observability block resets that Worker to OFF** — so a green dashboard is not evidence this config is safe to ship. BLOCKs (rc=1) on missing/`false` observability and on wrangler <3.78.6 with observability set (below that the key parses and is silently ignored at deploy — a false green worse than a missing config). rc=2 = UNMEASURED (unparseable config, no Python ≥3.11) and is never a pass. `head_sampling_rate`/`logs.invocation_logs` are INFO-only, since `head_sampling_rate` defaults to 1. After deploying, re-run with `--verify-deployed` to read the LIVE setting from the Cloudflare API — the only check that proves observability survived the deploy. No-op (exit 0, stated) when the repo has no wrangler config.
2. **Phase -0**: Merge conflict auto-resolution (from `pre-deploy-checks.md`)
3. **Phase 0**: Code quality / lint auto-fixing (from `code-quality.md`)
4. **Phase 0.5**: Deployment rate limit check (from `pre-deploy-checks.md`)
5. **Phase 1**: Build & test (from `build-and-test.md`)
6. **Phase 1.1**: API contract verification (from `build-and-test.md`)
7. **Phase 1.25**: Security audit (from `security-audit.md`)
7.5. **Phase 1.24**: Supply-chain scanner health — fires when the changeset touches `package.json` or any lockfile. Run `~/.claude/skills/shared/tools/socket-health-check.sh --live`. BLOCK on exit 1 (`sfw` missing/off-PATH → installs silently unscanned) or exit 2 (disarmed via `SOCKET_CLI_ACCEPT_RISKS` in a shell rc). Protection is Socket Firewall (`sfw`), a network proxy with no API key and no quota, wired via an `npm()` shell function that routes only install-class commands through it. Verify with the observable (`SFW_VERBOSE=true npm install` → `Protected by Socket Firewall`), not an exit code. Complements, does not duplicate: Dependabot/`npm audit` = known CVEs; Phase 1.29 `security-review` = OUR code; `sfw` = confirmed malware in what the DEPENDENCY ships. Skip when no dependency file changed.
8. **Phase 1.26**: Code scanning hygiene (from `security-audit.md`)
9. **Phase 1.3**: React scope & env safety (from `react-safety.md`)
10. **Phase 1.35**: useEffect abuse check (from `react-safety.md`)
11. **Phase 1.4**: SEO & sitemap consistency (from `seo-and-session.md`)
11.5. **Phase 1.4-onpage**: On-page "Last updated" date truthfulness — BLOCKING when the diff changes visible copy on any page rendering a "Last updated"/"Effective date" line. Distinct from 1.4-lastmod (sitemap/crawler hint): this is the sentence a human reads to decide whether a legal document changed. Run `~/.claude/skills/ship/tools/onpage-date-check.mjs <repo>` (repo-agnostic; no per-repo setup). exit 1 = BLOCK (stale OR overstated), exit 2 = investigate (unknown), exit 3 = not a git repo. Never pass `unknown` as clean. The date must name the day the copy changed, not today. When it reports `stale`/`overstated`, move the date into a single registry constant in the same fix rather than hand-editing the literal — a literal beside the copy is the shape that let four of five example pages drift for four months, and the next edit will re-break it.
12. **Phase 1.4a**: OG/social preview metadata and share image gate (from `seo-and-session.md`)
12.5. **Phase 1.4b**: Favicon presence gate (MANDATORY, every served-HTML site) — verify the deployed `<head>` carries a `<link rel="icon">` (or a `/favicon.*` route returning `image/*`). Public site → curl the live HTML; auth-gated site → grep the repo head template + confirm on the deployed page via the logged-in REAL Chrome (fcdp). If missing, AUTO-FIX with a self-contained base64 inline-SVG `<link rel="icon">` in the `<head>` (add `data:` to `img-src` if a CSP is set), redeploy, and browser-verify it decodes to valid SVG (DOMParser, no `parsererror`) and renders. Skip only for non-HTML API/CLI workers.
13. **Phase 1.42**: Session invalidation check (from `seo-and-session.md`)
14. **Phase 1.45**: Third-party config & infra protection (from `infra-and-admin.md`) — includes production auth Worker binding dry-run and municipal form fallback regression gates
14.1. **Phase 1.27**: OWASP Top 10 sweep on changed files (from `ant-verification-protocol.md` Section 1)
14.2. **Phase 1.28**: Supply chain & enhanced review on new deps (from `ant-verification-protocol.md` Section 5)
14.6. **Phase 1.45e**: Embed + rendered-href integrity — fires when the diff touches an `<iframe>`, a prose→HTML renderer, or any URL literal. Referrer-sensitive embeds need `referrerpolicy` when the site sends `Referrer-Policy: no-referrer` (the Hono `secureHeaders()` default → YouTube "Error 153"); no rendered `href` may contain whitespace; YouTube ids must be 11 chars; newly-autolinked prose URLs must each be validated before deploy. Reference impl `tools/check-links.mjs` (TISF). Pattern: `~/.claude/skills/debug/references/csp-cache-patterns.md` #27.
14.7. **Phase 1.45f**: Account-security lifecycle gate (from `~/.claude/skills/shared/account-security-lifecycle.md`) — fires when the diff touches auth/session/passkey/TOTP/password/recovery/sign-out code or when the ship report will claim enrollment/enforcement status
14.8. **Phase 1.45g**: Experience Cloud / Aura 311 catalog + submit envelope (from `infra-and-admin.md` 1c-ter, Pattern #36) — fires when the diff touches Salesforce/Aura catalog JSON, `fetchCaseTypeDetails` parse, `submitCase`/`addressDetails`/`sObjCase`, or the KV catalog cache key. BLOCK until structural tests prove toast unwrap, real-model-or-`captureFailure`, named refuse, and (if schema changed) a cache-key bump. Post-deploy: cache-busted `/api/categories` matches those counts.
15. **Phase 1.46**: Admin-user sync verification (from `infra-and-admin.md`)
15.3. **Phase 1.5**: Deployment verification for risky changes (from `infra-and-admin.md`)
15.4. **Phase 1.55**: Hot-path data-volume & cache-topology gate (from `infra-and-admin.md`) — fires when the changeset touches an HTTP route handler, a `scheduled()`/cron body, a cache read/write, or any SQL/D1 query. Enumerate every query that runs before the response; BLOCK on any per-request query reading >~100k rows (measure with `wrangler d1 execute --json` → `meta.rows_read`); for every cache-key read, confirm a writer exists; for every cache-warmer, confirm something reads those exact keys; lagged-source trailing windows must anchor on `MAX(ts)` not `now()`. Skip only for pure CLI/docs/test changes with no route/cron/cache/query in the diff.
15.44. **Phase 1.55a**: Self-inflicted-load gate (Pattern #40, `~/.claude/skills/debug/references/error-handling-patterns.md`) — fires when the diff touches a `scheduled()`/cron body, a prewarm/cache-warmer, a poller, or a self-directed health check. BLOCK on: (a) any `fetch()` in the scheduled path whose host matches a `custom_domain = true` route in `wrangler.toml` — a Worker cannot fetch its own Custom Domain (CF forwards the same-zone subrequest to the zone origin; a Workers-only zone has none, so it is a guaranteed 522/origin=0), and the guard must canonicalise a trailing root dot while comparing the EXACT host, never a suffix; (b) any scheduled `fetch()` with no `AbortSignal.timeout`; (c) a warmer whose warmed URL still reads `cf-cache-status: MISS` long after the run — it has never worked. Also treat a unit test that asserts the *current* scheduled behavior as suspect: a mocked `fetch` returns 200 and cannot observe a platform-level refusal, so such a test pins the bug rather than the requirement. Post-deploy, prove it with the NEXT scheduled run: group `httpRequestsAdaptiveGroups` by `datetimeMinute` and require zero 5xx across the cron window. Skip only for diffs with no scheduled/self-directed request. Reference incident 2026-08-29 (improvebayarea): 523/523 of the zone's 522s at :02–:03 past the hour, ~44/run = 43 cities + `/map/oakland`, a measured 32.5% 5xx rate entirely self-generated, invisible to manual probing because every probe returned 200.
15.45. **Phase 1.56**: D1 schema-drift / migration-applied-to-prod gate (from `infra-and-admin.md`, full pattern `~/.claude/skills/shared/d1-schema-drift.md`) — fires when the diff touches any D1 `INSERT`/`UPDATE`/`SELECT` column set, adds/edits a `migrations/*.sql` file, or references a new column/table. Run `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>`: (A) `wrangler d1 migrations list --remote` must be clean; (B) every column the changed worker code writes must exist in the **remote** `PRAGMA table_info`. The migration FILE existing and the LOCAL D1 having the column are NOT proof — only remote is. BLOCK on any code-referenced column/table missing in prod (it 500s every write to that table with a generic error) or unapplied migrations. Fix by applying ONLY the missing DDL additively to remote (`ALTER … ADD COLUMN`/`CREATE … IF NOT EXISTS`), verify with `PRAGMA table_info`, then `INSERT OR IGNORE` the filename into `d1_migrations`. NEVER run `wrangler d1 migrations apply` to catch up a drifted DB — it re-runs non-idempotent data migrations (e.g. `UPDATE steps SET order_index = order_index + 1`) and corrupts data. Skip only for diffs with no D1 write/migration change. Reference incident: 2026-07-05 AIVA `POST /api/intake` 500'd for every user (`mos` in code + migration file, never applied to prod).
15.47. **Phase 1.56a**: Management-API-vs-authoritative-state gate (from `~/.claude/skills/shared/management-api-vs-authoritative-state.md`, Pattern #31) — fires when the changeset **deletes or disables** any cloud/provider resource (DNS record, cert, cert pack, route, binding, bucket, queue, cron trigger, worker), or when the ship's rationale rests on a management-API read ("the API shows X is missing", "nothing references this, safe to remove"). **BLOCK the deletion until two proofs exist**: (A) **provenance** — the audit log (`GET /accounts/{acct}/audit_logs?since=…` or platform equivalent) names what created the resource; `actor.type: system` means the *platform* provisioned it and something almost certainly depends on it, so the deletion needs an affirmative reason beyond "I don't see a reference." (B) **consumer view** — the state was probed where it is actually consumed, not where it was declared: `dig` for DNS, `openssl s_client` for the served certificate, `PRAGMA table_info --remote` for schema, `wrangler secret list` for bindings, a really-delivered message's `Authentication-Results` for mail auth, cache-busted `curl` for deployed code. **A count mismatch between the declared and authoritative views IS the finding** — resolve it before shipping, never average the two. Skip only for diffs that delete nothing and make no absence claim. Reference incident 2026-07-28 (both conclusions wrong on the first pass): 20 advanced cert packs looked redundant from the cert-pack API but were CF's auto-provisioned Worker custom-domain certs (8 packs ↔ 8 Worker domains; 11 zones with 0 Workers had 0 packs) — the cleanup would have dropped TLS on six live subdomains; and CF `dns_records` reported 5 CAA records missing `issuewild "pki.goog"` while `dig` returned 11 including it (CF auto-injects partner-CA CAA, documented as not appearing in the dashboard) — a phantom outage against a healthy zone.
15.48. **Phase 1.56b**: Negative-control gate (from `~/.claude/skills/shared/negative-control-gate.md`, Pattern #33) — fires when the diff adds or changes a health check, liveness probe, validator, drift/reconciliation job, monitor, or verification sweep, **or** when the ship's rationale rests on a green result ("N/N verified", "all healthy", "the sweep came back clean"). **BLOCK until the instrument has been demonstrated to go RED on a named known-bad input**, and that control is committed as a test. Verify three outcomes exist in the result type (`ok` / `genuinely bad` / `could not measure`) — two is either a false-alarm generator or a vacuous pass. Remember **echo is not validation**: an upstream that reflects your value back into its response has validated nothing. Extends to (a) a hardcoded `verified:`/`lastChecked:` date on upstream-harvested data being shipped as a health signal — require `harvestedAt` naming plus a scheduled re-check that marks itself stale past ~2 intervals, since a dead cron otherwise looks identical to all-healthy; (b) a join on an upstream identifier without checking that upstream's published alias keys; (c) a dataset field whose absence degrades silently, which needs a completeness invariant with written exemptions. Also applies when this ship RETRACTS an earlier finding on the strength of a new clean measurement — the replacement gets more scrutiny than the original, not less. Skip only for diffs that add no pass/fail claim. Reference incident 2026-08-10 (nps-report): a probe reported 20/20 park mailboxes healthy; `o=DEADBEEF00` returned the same HTTP 200 + full form, so the check could never fail. The replacement found 5 of 435 tokens genuinely drifted — including one whose earlier, correct drift report had been retracted in favour of the vacuous probe.
15.5. **Phase 1.57**: Observability / instrumentation gate (from `~/.claude/skills/shared/observability-instrumentation.md`) — fires when the diff adds or changes external calls (`fetch`/DB/queue/3rd-party), `catch` branches, state transitions, or new error paths. Verify the changed code is debuggable in production BEFORE it ships: structured logs at those boundaries (`log({event, ...attrs})`, secrets/PII redacted), every new `catch` records what was attempted + the real upstream reason (nothing swallowed), and no new catch-all/ambiguous error message (a vague error is usually two root causes sharing one string — split them). FIX inline, don't warn-and-continue (fix-all rule). This is the deploy-gate form of /carmack's instrument-on-build behavior; the changed code's first production failure must be diagnosable from its logs alone. Skip only for pure docs/test/copy diffs with no logic change.
15.6. **Phase 1.59**: Consent / audit-evidence integrity gate (from `~/.claude/skills/shared/consent-evidence-integrity.md`, Pattern #35) — fires when the diff adds or changes any field whose STORED value is later offered as proof (SMS/TCPA consent, ToS acceptance, HIPAA authorization, cookie/GDPR consent, e-signature attestation, age verification, opt-in/opt-out). Run the §Verification recipe: (1) count consent-collecting UI surfaces vs code paths that persist — a mismatch is the finding, and the fix is ONE shared writer with a `source` column so the next surface fails loudly instead of silently; (2) round-trip BOTH outcomes on every surface (checked → row with `consent=1` + canonical text + timestamp + IP; unchecked → row with `consent=0`, and the submission still succeeds — consent may never gate unrelated service); (3) POST a forged `consent_text` and assert the stored value is the server's canonical constant; (4) `EXPLAIN`-validate the SQL against the REMOTE schema and confirm any `ON CONFLICT(col)` target is genuinely UNIQUE. BLOCK on: an exhaustive-deps warning over an evidence value (stale closure ⇒ opt-in recorded as decline — P1, not a lint nit); a schema-strictness mismatch (non-strict silently strips the field; `.strict()` 400s the whole form); `INSERT OR IGNORE`/`DO NOTHING` on the evidence path (consent is an EVENT — append-only primary store); client-supplied disclosure text; affirmatives-only logging. Skip only for diffs with no evidence-bearing field. Reference incident 2026-08-12 (AIVA A2P 10DLC) — see the gate table row for the full failure set.
15.9. **Phase 1.29**: **Semantic security review gate — BLOCKING, loop until clean.** The FINAL pre-deploy gate: invoke the built-in `security-review` skill (Skill tool). It does AI/semantic dataflow analysis (SQLi, XSS, SSRF, auth bypass, hardcoded secrets, business-logic flaws) — the vulnerability class /ship's grep-based Phase 1.45 checks and `npm audit`/Dependabot cannot see. **⚠️ OPERATIONAL (verified 2026-07-22): (a) `security-review` runs against the CURRENT WORKING DIRECTORY's git repo — NO path argument; it hard-fails `"needs to run inside a git repository"` if cwd isn't the repo. `cd <repo-root>` FIRST (the session cwd is normally the repo when /ship is invoked, but verify it hasn't drifted). (b) It reviews the COMMITTED branch diff vs the base (merge-base with origin/main) — NOT uncommitted working-tree edits (proven: a repo with 4 unstaged-modified files produced an EMPTY diff because HEAD == origin/main). So the changeset MUST be committed before this gate, or it reviews nothing and passes trivially. In the normal ship flow the feature code is already committed (you deploy committed code); if any part of this ship is still uncommitted at 1.29, commit it first. (c) An empty diff = 0 findings — which is a correct pass ONLY when the ship genuinely has no changeset, and a VACUOUS pass in every other case (see the mandatory pre-flight below). It returns a markdown report (file:line, severity, category, confidence 1–10) and self-filters false positives at confidence ≥8, so an "actionable finding" = any HIGH/MEDIUM in that report.**

**🛑 MANDATORY PRE-FLIGHT — compute the review range BEFORE invoking, and BLOCK on a vacuous gate.** `security-review` diffs `HEAD` against `merge-base(HEAD, origin/HEAD)`. Run this FIRST:
```bash
cd <repo-root>
BASE=$(git merge-base HEAD origin/HEAD 2>/dev/null || git merge-base HEAD origin/main)
git diff --stat "$BASE" HEAD | tail -3          # what the gate will actually see
git log --oneline "$BASE"..HEAD | head          # commits it will actually read
```
If that range is **EMPTY but this ship has a real changeset**, the gate is VACUOUS — zero findings over zero code — and you MUST NOT record it as a pass. This is not an edge case; it is the DEFAULT whenever `HEAD == origin/main`, which happens on: (i) shipping directly from `main` after the feature commits were already pushed, (ii) **resuming or re-running `/ship` on an already-pushed repo** (the 2026-07-30 improvebayarea run — two real commits, `f9142b1` + `4da7798`, both already on `origin/main`, so the gate reviewed nothing and reported clean), (iii) a first push (Phase 2.95). In all three the code is real and unexamined.

**When the range is empty and a changeset exists, do ALL of:**
1. **Identify the true ship base** — the commit production is currently running (`wrangler deployments list` / `version.json` SHA / the last deployed tag), or the session's starting `HEAD`. Call it `$SHIP_BASE`.
2. **Review that explicit range instead** — `git diff $SHIP_BASE..HEAD`. `security-review` takes no path/range argument, so either (a) re-run this gate from a feature branch *before* merging (the workflow it is built for — strongly preferred), or (b) perform the semantic review directly against `git diff $SHIP_BASE..HEAD` using the same categories (injection, XSS, SSRF, auth bypass, secrets, logic flaws) and report it explicitly as a **manual** review, never as a `security-review` result.
3. **Label the evidence honestly in the final report** — "Phase 1.29: VACUOUS (empty diff, HEAD == origin/main); reviewed `$SHIP_BASE..HEAD` manually instead" is acceptable. "Phase 1.29: clean, 0 findings" is a FABRICATION when the tool saw no code.

**Structural fix (do this once per repo, don't keep paying the tax):** run `/ship` from a feature branch and merge after the gate passes. A post-merge `main` ship can never make this gate non-vacuous, so if the repo's workflow is push-to-main, treat step 2(b) as the standing requirement rather than an exception.

**Run the loop**: (1) `cd` into the repo (ensure the changeset is committed), run the pre-flight above, invoke `security-review`; (2) read its markdown report; (3) FIX every reported (confidence-≥8) finding in source inline — obey the No-Suppression Rule (never `@ts-ignore`/`eslint-disable`/`biome-ignore` a finding away); (4) re-invoke `security-review`; (5) repeat 1–4 until the report is **empty (0 findings)**. Document any finding you deem a genuine false positive inline with its reason. If `security-review` is unavailable in this environment (Skill returns unknown-skill), do NOT silently pass — WARN the user the semantic gate could not run and fall back to the Phase 1.45 grep checks. Skip ONLY for pure docs/README/comment diffs with zero code change.

**🔁 THE LOOP IS AUTOMATIC AND SO IS ITS EXIT. Every outcome has exactly one next action, and none of them is "wait for the user":**

| Report | Next action | Ask the user first? |
|---|---|---|
| **0 findings** | **CONTINUE to Phase 2/3/4 and deploy, in the same turn** | **NO** |
| ≥1 finding (confidence ≥8) | Fix all in source → re-invoke → repeat | NO |
| Same finding after 5 fix attempts | STOP the ship, surface the finding + why the fix isn't landing | yes — this is the only halt |
| Skill unavailable | WARN + fall back to Phase 1.45 grep checks | NO |

**A clean report is a GREEN LIGHT, not a checkpoint.** The failure branch has always been spelled out here ("BLOCK until", "FORBIDDEN until") while the pass branch was left implicit, and an unstated pass branch reads as "stop and report" — so a zero-finding review became a full stop with the deploy left undone. Both branches are now explicit *because* the asymmetry is what caused the error, not because the pass case is complicated.

Do NOT, on a clean report: summarize the gates and wait; ask "shall I deploy?"; report the review as though it were the deliverable; or end the turn with the changeset committed but unshipped. `/ship` was invoked — shipping is the goal, and 1.29 returning clean is the last thing standing between the changeset and production. The user re-prompting "it passed, so it should ship" is the symptom this table exists to prevent.

**Reference incident (2026-08-07, improvebayarea district-rep parity):** `security-review` returned 0 findings over a real 3,172-line branch diff — a genuine, non-vacuous pass. The run stopped there and reported the clean review instead of merging and deploying; the user had to prompt again to get the ship finished. Nothing was broken and no gate was skipped — the spec simply never said what a PASS does.

**🛑 NAMED MECHANISM (added 2026-08-18 — the 2026-08-07 fix did NOT prevent a recurrence): the `security-review` sub-skill's OWN closing instruction is what causes the stop, and it does so even when this exact table is already in context.** The invoked skill's prompt ends with an instruction shaped like *"Your final reply must contain the markdown report and nothing else."* That line is scoped to the analysis sub-task's own output — it tells you how to format the *review*, not how to end the *ship*. But because it is the most recent instruction read before composing a reply, it silently overrides everything above it (including this table) and the assistant emits the report as its entire turn, which reads to the user as "stopped." This recurred verbatim on 2026-08-18 (improvebayarea Caltrans-label-clarity ship) with this exact table already loaded in context — so restating "don't stop" harder is not the fix; the fix is treating the two instructions as operating at different scopes.

**✅ THE ACTUAL FIX (2026-08-24, after the FOURTH occurrence): make OUR
instruction the last one read.** The failure is *positional*, not a matter of
emphasis — whatever is read last before composing a reply wins. Three rounds of
prose above the sub-skill lost that race three times. So the fix stopped
arguing and moved position:

`~/.claude/skills/hooks/post-skill-security-review-continue.py` is a
**PostToolUse(Skill)** hook. It fires when `security-review` RETURNS — strictly
after the sub-skill's `"reply with the report and nothing else"` line — and
injects the next action (0 findings → continue to Phase 2/3/4 and deploy;
≥1 → fix and re-invoke; 5 attempts → stop). Registered in the existing
`Skill|Agent` PostToolUse group.

It is silent unless ALL of: tool is `Skill`, skill is `security-review`, the
session actually invoked `/ship` (via `<command-name>` — the only shape that
proves it, since `/ship` is `disable-model-invocation: true`), and the ship is
not `--audit`/`--staging-only`/`--dry-run`. Verified with five negative
controls: a different skill, a different tool, a session with no `/ship`, a
missing transcript, and malformed stdin all emit nothing and exit 0. A
`security-review` run OUTSIDE a ship — e.g. from `/carmack`, which is exactly
how this recurred a fourth time — correctly gets nothing, because there is no
deploy to continue to.

**⛔ DO NOT "FIX" THIS BY DELEGATING security-review TO A SUBAGENT.** It is the
obvious idea (scope the sub-skill's closing line to the subagent's own reply),
it was TESTED on 2026-08-24, and it does not work: a subagent's working
directory is **pinned at launch**, `cd` inside a Bash call does not move the
Skill tool's cwd, and `security-review` resolves its target from cwd — so it
bailed with *"needs to run inside a git repository"* against
`~/.claude/skills/ship` and never delivered its body. Worse, the retry is a
dead end: a second `Skill` call returns *"already loaded above; instructions
unchanged"*, so the supplied path argument is accepted syntactically and then
ignored, and the preflight never re-runs. Both failure modes have to be solved
before that route is viable; the hook above needs neither.

**MECHANICAL BACKSTOP (and the reason it was absent until 2026-08-24).** The
Stop hook `~/.claude/skills/hooks/ship-security-clean-stop-check.sh` exists to
catch this exact stop. It was written after the 2026-08-07 incident and it
**never once fired**, because its trigger was `if "ship" not in <Skill tool_use
names>: SKIP`. `/ship` is `disable-model-invocation: true`, so the model cannot
Skill-invoke it and a user-typed `/ship` arrives as a `<command-name>` slash
expansion — a shape that gate could not see. Verified on the 2026-08-24
transcript: Skill names were `['carmack','security-review']` while
`<command-name>` held `/ship`. So BOTH layers were dark at once: the prose said
"don't stop" and the guard silently skipped. Fixed by matching either
invocation path (and reading `--audit`/`--staging-only` from `<command-args>`
too), then proven by replaying the real transcript truncated at the stop point
— it BLOCKS there, stays silent on the completed ship, and stays silent on an
unrelated session.

Lesson that generalizes past this hook: **a guard whose trigger is the tool-call
shape of an invocation will miss every invocation that arrives another way.**
When a skill is `disable-model-invocation: true`, its tool-call shape is exactly
the one that never occurs.

**The rule, stated as an override:** when a Phase 1.29 sub-invocation's own prompt tells you to reply with "nothing else" / "only the report" / any equivalent exclusive-output instruction, that instruction governs ONLY the content of the paragraph containing the findings. It does NOT end the assistant turn and does NOT mean stop calling tools. The moment the report is read and shows 0 findings (or all findings fixed), in the SAME turn, with NO intervening reply-and-wait: emit the one-line phase-transition banner (`-- Phase 1.29 OK (0 findings) -> Phase 2: merge & deploy --`) and immediately issue the next tool call (merge/push/deploy). Do not produce a standalone assistant message whose entire content is the security-review report — the report is an intermediate artifact of this phase, not a deliverable to the user, and must always be followed by further tool calls in the same turn, right up until the ship is actually deployed and verified.
16. **Phase 2**: Manual override path (from `deployment.md`)
16.5. **Phase 2.95**: No-remote auto-provision (from `deployment.md` Phase 2.95) — fires when `git remote` is empty. /ship requires GitHub before any platform deploy, so a remote-less repo used to hard-block; now it auto-creates one. **Order is the safety property:** (1) secret sweep FIRST — filenames *and* content across `git ls-files`, because a first push publishes the whole history and a secret in commit #1 ships even if a later commit deleted it (BLOCK on any hit; deleting the file in a new commit does NOT remove the blob); (2) confirm `.gitignore` covers `.dev.vars`/`.env`; (3) `gh repo create --private` — **never** `--public`, never omit the flag; (4) **verify** `gh repo view --json isPrivate` returns true rather than trusting the flag you passed; (5) `git push -u origin <branch>`; (6) `git remote set-head origin -a` so Phase 1.29 can resolve `origin/HEAD` (a fresh create+push does not always set it). **A fork of a public upstream is PUBLIC** — check `isPrivate` before ANY push to a repo you did not just create (`feedback_never_push_personal_work_to_public_repos.md`). **Then flag the Phase 1.29 vacuity:** after a first push `HEAD == origin/HEAD`, so `security-review` sees an EMPTY diff and reports 0 findings — the whole codebase, auth included, was never examined. Review the security surface directly and report that as the evidence, or state plainly the gate was vacuous and deferred. Never present an empty first-push diff as a clean review.
17. **Phase 3**: GitHub deployment (from `deployment.md`)
18. **Phase 3.5**: README & changelog auto-update (from `deployment.md`)
18.5. **Phase 3.55**: README config-sync auto-regen (from `deployment.md`) — BLOCKING. Run `scripts/regen-readme-status.sh` (or any project-equivalent regen script). If it produces a diff, commit + push as `docs: regen README current-setup [skip auto-readme]` BEFORE deploying. Catches drift between deployed code and the README's "how the site works" block. Added 2026-05-10 after the user shipped 3 architectural changes that the GitHub Action's path-allowlist trigger missed.
19. **Phase 4**: Downstream deployments (from `deployment.md`)
19.5. **Phase 4.7**: iOS app surface release (from `ios-release.md`) — fires when the repo ships an iOS surface (`ios/` + `capacitor.config.ts`, or an `*.xcodeproj`/`*.xcworkspace` app target, or Expo `app.json`). Web-class changes in a Capacitor repo: verify the OTA publish ran (web deploys and app updates come from ONE build — web first, then app) and closed-loop-check `/api/app/updates` + a sim relaunch — no native build, no ask needed. Native-class changes: **Phase 4.7.0a ask gate FIRST** — AskUserQuestion which channel (TestFlight only / TestFlight + App Store submission / hold); App Store submission NEVER runs without an explicit same-session "App Store" answer (user rule 2026-06-12). Then full greenlight → sign → archive → TestFlight pipeline with the build-to-group assignment that actually notifies testers. BLOCK on OTA pushes that include native-affecting changes.
19.7. **Phase 4.07**: Email deliverability verification — BLOCKING when the changeset touches email-send code (a `send_email` binding, email provider seam, From address/`NOTIFY_FROM`, or SPF/DKIM/DMARC records). Run `~/.claude/skills/ship/tools/email-deliverability-check.sh <repo> --domain <sender-domain> --accounts <dest mailboxes>`. Pre-deploy: the static half (apex-sender-into-hosted-mailbox MX check + Email Sending onboarding). Post-deploy: trigger a REAL send through the app's own event path, then verify the message landed in the destination INBOX (not SPAM) with `Authentication-Results: dmarc=pass`. A resolved `send()` is NOT delivery evidence — the 2026-07-13 diy-fax incident sent successfully via Resend from the apex `sender@example.com` and every inbound-fax alert was silently spam-foldered by the same domain's Google Workspace. Three-verdict discipline: INBOX+dmarc=pass = pass; SPAM or dmarc!=pass = BLOCK; no message found = UNVERIFIED (re-trigger, don't pass).
19.8. **Phase 4.08**: Workers-Cache post-deploy verification (from `post-deploy.md` Phase 4.08; pattern `~/.claude/skills/shared/workers-cache-safety.md`) — BLOCKING when the deployed changeset **enables or modifies** the wrangler `cache` block. (1) **Staged enable**: if the diff changes worker code AND newly enables cache, deploy the code first with `cache.enabled: false`, verify healthy, then enable in a second deploy. (2) **t+15/45/90s monitoring** across route classes (HTML page, authed/JSON API, public opt-in asset) — a <60s check is NOT evidence either way: cache-layer engage/disengage propagates in >30s (the 2026-07-06 incident's 3-second post-disable check false-negatived and triggered an unnecessary rollback). (3) **Semantic header checks**: authed/JSON → `private, no-store`; public opt-ins keep `public, max-age`; HTML matches repo policy; HSTS present on an HTTPS response. (4) **Sitewide 3xx tripwire**: ANY route 301/302-ing to its own URL → immediately redeploy with `cache.enabled: false`, wait ≥60s, then diagnose via `wrangler tail --format json` → `event.request.url` scheme (http:// for HTTPS visitors = the scheme-presentation class; fix with cf-visitor, never url.protocol).
19.9. **Phase 4.09**: Worker surface-exposure probe + AUTO-HEAL (ANY Cloudflare Worker repo) — **MANDATORY, runs with `--apply` on every ship** (not conditional): `~/.claude/skills/ship/tools/worker-surface-check.sh <repo> --apply`. **Why every time, not a cron:** `wrangler deploy` silently RE-ENABLES the worker's `.cloudflare.app` preview hostname (and workers.dev subdomain) on essentially every deploy — so this class *regresses each ship*. /ship owning it with `--apply` is what makes it un-accumulate: the deploy that re-opened the surface is the same run that closes it again, before CF's scanner ever emails about it. The probe asks the CF API what wrangler won't tell you (`GET /accounts/{acct}/workers/scripts/{name}/subdomain`): (a) `previews_enabled: true` → the `<name>.cloudflare.app` preview hostname (half-provisioned, 522, un-securable) that trips CF Security Insights alert emails (7 workers flagged 2026-07-06); (b) a custom-domain worker with workers.dev `enabled: true` → an **unprotected full duplicate of prod** (the AIVA twin — a class CF's own Insights does NOT flag). `--apply` POSTs `previews_enabled:false` everywhere and `enabled:false` on custom-domain workers (the API POST is required — `wrangler deploy` does NOT disengage an already-enabled subdomain even with `workers_dev:false` in config, observed wrangler 4.104); then mirror `workers_dev`/`preview_urls` in the wrangler config for declarative parity. workers.dev-canonical sites (no custom routes) keep `enabled:true` — only previews are closed. Verify: re-probe shows `previews=false` (+ `enabled=false` for custom-domain) and the canonical URL still 200s. This makes a standing background cron unnecessary for the surface class — the guarantee lives at the deploy boundary.
20. **Phase 4.1**: Post-deploy verification (from `post-deploy.md`) — start with the multi-signal battery `~/.claude/skills/ship/tools/fleet-verify.sh <name> <url>` (status/Cache-Control/cf-cache-status/HSTS/CSP/DOM-literals/h1/og/security.txt; grep for `FAIL:`), then the content-specific checks.
20.5. **Phase 4.05**: Site security defaults (from `~/.claude/skills/shared/site-security-defaults.md`) — BLOCKING. Run the 12-item curl-based baseline check against the live URL. If items 1-11 fail, AUTO-FIX inline (add Worker route / middleware), commit, redeploy, re-check. Items 12-16 (TLS min, DNSSEC, CAA, SPF/DMARC) require Cloudflare API or registrar access — apply auto-fix recipes if `CLOUDFLARE_API_KEY`+`CF_ZONE_ID` are set, otherwise warn loudly with the exact command for the user to run.
20.55. **Phase 4.05c**: Copy-truth gate (from `~/.claude/skills/shared/no-lie-verification.md` "Live-Artifact Re-Verification") — BLOCKING **when the changeset modifies user-facing copy with numbers, percentages, dates, or counts.** Auto-detect with `git diff --name-only origin/main..HEAD | grep -E '\\.(tsx|jsx|html|md|astro|svelte|vue)$|public/.*\\.(js|html)$'` and `git diff origin/main..HEAD -- <those-files> | grep -E '\\+.*[0-9],?[0-9]{3,}'`. If matches found, BLOCK until: (a) cache-busted `curl https://<prod>/?cb=$(date +%s)` returns every NEW number you added, (b) cache-busted curl returns ZERO matches for every OLD number you removed. Format: `curl -s "https://<URL>/?cb=$CB" -H "Cache-Control: no-cache" | grep -oE "<old>|<new>" | sort -u`. **Why:** the 2026-05-18 hospital-ledger incident — /carmack reported "no '10,000' strings remain — rg clean" against source, but `rg` doesn't see the deployed Worker output. The deployed artifact is what users see; source code is not. This gate proves the new copy is live and the old copy is gone.
20.6. **Phase 4.05a**: Cloudflare zone-level security enforcer (from `~/.claude/skills/shared/site-security-defaults.md` § Phase 4.05a) — MANDATORY when `CLOUDFLARE_API_KEY`+`CLOUDFLARE_EMAIL` are set. Idempotently PATCHes Z1–Z8 zone settings (always_use_https=on, automatic_https_rewrites=on, min_tls_version=1.2, tls_1_3=on, opportunistic_encryption=on, ssl≥full, zone-HSTS enabled with preload, 0-RTT=on) so no domain can ship with CF Security Center–flagged defaults. **Bot protection is intentionally excluded** (false-positive risk on agent traffic). Closed-loop-verifies HTTP→HTTPS redirect + TLS 1.1 rejection. Added 2026-05-14 after CF flagged hospitalledger.com for always_use_https=off + min_tls_version=1.0 + HSTS disabled.
20.65. **Phase 4.05b**: CSP header + a11y baseline (every public site) — BLOCKING. (1) `curl -sI https://<prod>/ | grep -i content-security-policy` MUST return a CSP header. If absent, AUTO-FIX in source (Hono `secureHeaders({contentSecurityPolicy:{...}})` or equivalent middleware), allow-listing ONLY hosts the islands actually load (inspect `src/client/*` for tile/font/CDN hosts; `data:` for inline images; `'unsafe-inline'` on `style-src` only when a lib injects inline styles — never on `script-src`), then drive the logged-in REAL Chrome (fcdp) to load each island page and BLOCK if the console shows any `Refused to … Content Security Policy` violation OR an island fails to render (map tiles/markers, charts) — widen the CSP minimally and re-verify. (2) a11y: for each route, evaluate the live DOM — `document.querySelectorAll('h1').length` MUST equal 1 and there must be no skipped heading levels (logo/wordmark must be `<span>`/`<div>`, not `<h1>`); run a contrast check (Lighthouse a11y or computed-style audit) and BLOCK on any text below WCAG-AA (≥4.5:1 normal, 3:1 large/bold ≥24px) — fix the theme tokens in source. Auto-fix → redeploy → re-verify. **Static-count trap (2026-07-06):** a curl+grep h1 count includes inert `<template>` content that is NOT in the rendered/a11y DOM — a template-driven UI can grep as 5 h1s while the runtime DOM has exactly 1 (xbox-nxe: grep said 5, `agent-browser eval` said 1 → no fix needed). Never BLOCK on the static count alone; the live-DOM `querySelectorAll` result is the verdict. Added 2026-06-04 (sanders-king-heritage Hono ship: no CSP, `#6b7280` footer text ~3.7:1, logo `<h1>` colliding with page `<h1>`).
20.68. **Phase 4.05f**: Organization entity anchors — BLOCKING for any public HTML site. `~/.claude/skills/ship/tools/entity-sameas-check.sh <live-url>`. exit 1 = BLOCK (no Organization node, empty `sameAs`, dead URL, or a `--forbid` hit); exit 2 = UNKNOWN, investigate rather than pass. Fill a missing list ONLY from links the site already publishes, an authoritative registry keyed to a real identifier, or the user — never from a guessed slug, and never with another legal entity's identifiers. Skip only for non-HTML API/CLI workers.

20.7. **Phase 4.05e**: Account-wide CF zone/DNS security-harden (advisory) — MANDATORY when `~/.cloudflared/cf-global-api-key.json` exists. Run `DRY_RUN=0 python3 ~/.claude/skills/carmack/tools/cf-account-harden.py`. Idempotent; applies the free zone/DNS security layer account-wide: DNSSEC (enable where off), Free WAF Managed Ruleset (deploy on every zone), Leaked-Credential detection (enable), CAA (add CF Universal-SSL partner-CA union). Mail-touching fixes (parked-domain no-mail lockdown; `p=none→p=quarantine`) stay OFF unless `INCLUDE_MAIL=1` — they are account-specific and a live sender must not get a blind `p=reject`. Complements 4.05a (per-zone TLS/HSTS enforcer) and 4.05d (insights sweep / security.txt / worker previews). Report what changed; NEVER block the ship. Reference: applied clean across 18 zones 2026-07-07 (see `~/Claude-Reports/cloudflare-security-audit-2026-07-07.html`).

20.75. **Phase 4.05d**: Account-wide CF Security Insights sweep (advisory — replaces the `cf-security-watch` Hermes cron, paused 2026-07-06) — MANDATORY when `~/.cloudflared/cf-global-api-key.json` exists. Run `~/.claude/skills/carmack/tools/cf-security-insights.sh --apply`. Unlike Phase 4.05/4.05a (which secure ONLY the zone of the site being deployed) and Phase 4.09 (which closes ONLY the deployed worker's preview surface), this sweeps the **entire Cloudflare account** — every zone AND every Worker — applying the zero-perf-cost fixes: zone-level AI-bots block + AI Labyrinth + edge-served `/.well-known/security.txt`, and **`previews_enabled=false` on every Worker** (the `<name>.cloudflare.app` preview hostnames are exactly what CF Security Insights flags as "Domains missing TLS Encryption" / "without Always Use HTTPS" / "without HSTS" / "Security.txt not configured" — reference incident 2026-07-07: 17 workers alerted while 13 more sat un-flagged with previews on, because 4.09 is per-repo and the old sweep was zones-only). Custom-domain workers with workers.dev enabled are reported, not auto-fixed (needs repo context — run `worker-surface-check.sh <repo> --apply`). It **auto-SKIPS the false-positive / judgment-call classes** (Bot Fight Mode = hurts Lighthouse; unproxied CNAME = Clerk/Brevo need DNS-only; dangling A/AAAA = Google-forwarding origins are live; DMARC = CF over-counts a usually-valid record) — those still require a human `dig`/`curl` verify, so the sweep never touches them. **Why in /ship, not a cron:** folding it here gives account-wide coverage on **every deploy** (event-driven) instead of a daily cron — the user chose this so there's no standing background job. Trade-off (state it, don't hide it): if you go a long stretch without shipping, the account-wide sweep doesn't run in that window; Cloudflare still emails raw Security Insights to the inbox as the backstop. Report what it changed; NEVER block the ship on it. Skip only when CF creds are absent. Full triage map: `~/.claude/skills/shared/site-security-defaults.md` (Cloudflare Security Insights section).
21. **Phase 4.2**: Multi-agent code review (from `post-deploy.md`)
22. **Phase 4.3**: Web performance audit (from `post-deploy.md`)
23. **Phase 4.35**: Visual regression check (from `post-deploy.md`)
24. **Phase 4.5**: Deployment failure rollback (from `post-deploy.md`)
25. **Phase 4.6**: GitHub Actions CI gate (from `post-deploy.md`)
26. **Phase 5**: Post-deploy monitoring (from `post-deploy.md`)
26.2. **Phase 5.2**: Post-deploy log-hygiene pass (invokes the `/log-hygiene` skill) — **advisory, non-blocking.** Fires when the changeset touched a route handler, a `scheduled()`/cron body, or an external integration. After Phase 5 monitoring confirms the deploy is healthy, run `/log-hygiene <worker> --hours 1 --report-only` against the **now-live** logs of what you just shipped — catch ambiguous errors / noisy lines the new code emits under real traffic (the instrumentation you gated at Phase 1.57, now observed in production). Report findings; `bd create` a follow-up for any cluster worth fixing — do NOT block the ship on fresh-traffic noise, and NEVER delete log lines (downgrade). Skip with `--skip-loghygiene`. The recurring scheduled version of this loop is the Phase-2 Hermes cron (`bd HOME-w1xq`).
26.5. **Phase 5.5**: Skill/config backup gate (user rule 2026-06-12) — BLOCKING before the final report. (a) Repo: `git log @{u}..HEAD` must be empty (every commit pushed to GitHub — wrangler deploy alone does NOT track anything). (b) Skills/config: if this session edited ANY file under `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/CLAUDE.md`, or `~/.claude/settings.json`, run `~/claude-code-boilerplate/scripts/backup-claude-config.sh` and confirm it prints a pushed commit URL — the SessionStart auto-backup only captures the previous session's state, so mid-session skill improvements are invisible on GitHub until this runs. The final report cites both proofs.
27. **Phase 6**: PR babysitter (from `post-deploy.md`)

---

## Pre-Ship Verification Checklist (Non-Negotiable)

Before declaring ANY deploy complete, verify ALL of these:

1. **Bundle hash changed** — `curl -s <URL> | grep 'index-'` must show a NEW hash vs. previous deploy
2. **Page loads correctly** — curl the actual page, verify it returns 200 and contains expected content
3. **API endpoints work** — test at least one authenticated endpoint returns data, not "Unauthorized"
4. **New routes reachable** — if you added a route, verify it doesn't 404 or get swallowed by a catch-all
5. **No stale cache** — if `cf-cache-status: HIT`, verify it's serving the new content not old
6. **OG/social preview works** — curl the live HTML and prove title/description/canonical, `og:image`, and `twitter:image` are present; curl the image URL and prove `200` plus `image/*` content type. Create them if absent.
7. **Clean build** — for Cloudflare Workers: `rm -rf dist && tsc -b && vite build && wrangler deploy` (never just `wrangler deploy`)
8. **Type definitions correct** — for CF Workers, edit `worker-configuration.d.ts` (ambient), not just `src/worker/env.d.ts` (module)
9. **Worker secrets are secrets** — sensitive bindings show as `secret_text` in `wrangler secret list`; no plaintext key/token/password remains in `wrangler.json` `vars`
10. **Prod integration passes** — if available, run `npm run test:integration:prod` against the live domain before success
11. **PR mergeability re-verified** — for every PR opened/touched in this session: `gh pr view <N> --json mergeable,mergeStateStatus` must be MERGEABLE / CLEAN. CONFLICTING / BLOCKED / BEHIND blocks the final report.
12. **Every numeric claim in the final report has an inline proof citation** — SQL query, curl output, file:line, build exit code + timestamp. Forbidden without proof: "verified", "confirmed", "all clean", "shipped", "deployed successfully", "PR opened ready to merge", any specific count/percentage. (See `~/.claude/skills/shared/no-lie-verification.md` "Wording Discipline".)
13. **Triggered behavior was actually exercised, not just configured** — if the changeset adds/modifies a failover, retry/backoff, fallback chain, circuit-breaker, rate-limit cooldown, error/`catch` branch, conditional cron, or feature-flag gate, you must have **induced the trigger and observed the path fire** (Check 6 in `no-lie-verification.md`) — force the 429 / fail the dependency / trip the breaker on an isolated copy, confirm the right downstream component served, confirm the live instance is untouched. "The fallback is configured" ≠ "the fallback fires." Do this BEFORE reporting deployed.

14. **No conclusion rests on an unproven instrument** — every "no errors in the logs", "the counter is flat", "nothing was retried" claim in the final report must cite an instrument proven ALIVE in that window (`wc -c` the tail capture; count parsed objects — `wrangler tail --format json` is PRETTY-PRINTED, not JSONL; re-poll KV, whose reads lag). Silence from a dead instrument is not evidence of health. Pattern #32.
15. **Account-security claims are separated and proven** — when applicable, report enrollment, challenge enforcement, enrollment policy, and recovery separately; verify TOTP/passkey status with PII-minimal authoritative counts and never select seeds, backup codes, credential IDs, session tokens, or recovery links.

**If ANY check fails: do NOT say "deployed successfully". Fix it first.**

## Safety Audit Tiers

### Tier 1 — Critical (always runs on deploy)
- Silent failure detection — env vars without validation
- Silent React startup failures — env validation throwing before mount
- Security audit — vulnerabilities, exposed secrets
- Test execution verification

### Tier 2 — Investigation (`--audit tier2`)
Uses `systematic-debugging`:
- Blind spot auditor — edge cases missing test coverage
- Test quality gate — tests that pass but don't verify real behavior
- Rate limit protector — public endpoints missing rate limiting

### Tier 3 — Deep Analysis (`--audit tier3`)
Uses `carmack-mode-engineer`:
- Code archaeology — "old/legacy" code that's actually critical
- Critical systems guard — unprotected auth/payment/data-deletion paths
- Build reproduction harnesses for complex issues

### Full (`--audit full`)
Runs all three tiers in sequence.

---

## 🛑 "It deployed" is a claim about PRODUCTION, not about your command (added 2026-08-24)

Three separate ways a deploy reported success while production kept serving old
code — all in one session, all invisible to the deploy command's own output.
The unifying rule: **a deploy is verified by re-reading the live artifact, never
by the exit code, the CI badge, or the printed Version ID.**

**1. A green CI run whose deploy step was SKIPPED.** A workflow guarded by
`Check for deploy token` skips its deploy step when the secret is missing and
the job still exits 0 — `gh run list` shows `success`. TISF's workflow had
skipped on **all 4** recent runs and had therefore never deployed once. Check
the STEP, not the run:
```bash
RID=$(gh run list --repo <o/r> --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RID" --repo <o/r> --json jobs \
  --jq '.jobs[].steps[]|select(.name|test("[Dd]eploy"))|"\(.name) -> \(.conclusion)"'
```
Cross-check against the worker's own version history — if the newest version's
`created_on` predates the CI run, CI did not deploy:
`GET /accounts/<acct>/workers/scripts/<name>/versions?per_page=3` →
`metadata.created_on` + `metadata.source`. **This also makes /carmack's
Auto-Deploy Detection produce a false POSITIVE**: workflow present + runs green
does NOT mean pushes deploy.

**2. A bare `wrangler deploy` that shipped a stale `dist/`.** Repos with a build
step (`vite build`, a `scripts/deploy.sh` wrapper, a prices-stash) must be
deployed **through their own script**. A generic
`for repo in …; do wrangler deploy; done` loop silently publishes the last build
— wrangler reports success and a fresh Version ID for unchanged bytes. Read
`package.json` `scripts.deploy` per repo before looping; never assume
`wrangler deploy` is the whole deploy.

**3. Another session overwrote the deploy 68 seconds later.** See
`bd recall feedback-concurrent-session-deploy-race`. Re-verify from served HTML
at the END of the run, not immediately after your own deploy.

**Therefore Phase 4.1 verification must, for EVERY host touched — not a
spot-check of one:** re-fetch the live artifact cache-busted, assert the new
content is present AND the old content is gone, and open a real browser to read
the console. The 2026-08-24 sweep found: one host still serving the previous
snippet under a CSP that named the new one (a config value threaded into one
consumer but not the other — typechecked, linted, 2,438 tests green), one host
never deployed at all, and one host serving a stale build.

**For PRs to open source Rust projects with multi-platform CI matrices:**

```bash
# 1. Format check (CI rejects ANY formatting diff)
cargo fmt --all -- --check

# 2. Clippy with warnings-as-errors
cargo clippy --all-targets --all-features

# 3. Check for conditional compilation blind spots
grep -n "let mut" src/**/*.rs | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  var=$(echo "$line" | grep -oP 'let mut \K\w+')
  if grep -A20 "let mut $var" "$file" | grep -q '#\[cfg(target_os'; then
    echo "WARNING: $file — $var may need #[allow(unused_mut)]"
  fi
done
```

After push: `gh pr checks <PR_NUMBER> --watch`

---

## OUTPUT REQUIREMENTS

- Always show clear phase headers marking current stage
- Use visual indicators for success, failure, warnings
- Display progress bars for multi-step operations
- Provide actionable error messages when builds or tests fail
- Show deployment summary table with service name, status, and live URL
- Include estimated time for each phase
- Display comprehensive banners at phase transitions

---

## SAFETY CONSTRAINTS

### Critical Rules:
- **FAIL FAST**: Terminate immediately on build errors or test failures
- **GitHub deployment ALWAYS happens before any other platform**
- **Multiple confirmation gates prevent accidental shipping**
- **All override actions are permanently logged**
- **Never silently skip tests or quality checks**
- **Refuse ambiguous commands that might bypass gates**
- **Data verification is mandatory for risky changes unless explicitly overridden**
- **NEVER execute destructive infrastructure commands** — these require human execution
- **NEVER modify or replace .tfstate files**
- **ALWAYS show terraform plan output to user** before any terraform apply

### Phase-Specific Rules:
- Phase -1: NEVER proceed if not in git repo or remote unreachable
- Phase -0.4: BLOCK (rc=2 from `tools/workers-cache-check.sh`) on cookie-auth + no global no-store default (cross-user leak) or request-scheme sniff without cf-visitor (redirect-loop class). WARN on wrangler <4.69 (flag inert) and request-URL-gated HSTS.
- Phase -0.35: BLOCK (rc=1 from `tools/observability-check.sh`) when any wrangler config lacks `observability.enabled=true` or sets it false, or when wrangler <3.78.6 has observability set (silently ignored at deploy). rc=2 UNMEASURED is never a pass. Deploying an observability-less config RESETS a currently-instrumented Worker to OFF — that regression is the whole point of the gate. Post-deploy, `--verify-deployed` reads the live setting from the CF API.
- Phase 4.08: When the `cache` block was enabled/modified: staged enable (code deploy first, cache-enable second); NEVER conclude from a <60s post-deploy/post-disable check (propagation >30s — the 2026-07-06 3s false-negative caused an unneeded rollback); monitor t+15/45/90 across route classes; BLOCK-and-auto-disable on any route 301/302-ing to its own URL, then `wrangler tail --format json` scheme probe before re-enabling.
- Phase 1: NEVER run `npm test` or full `npx vitest run` — always use `--changed` and `timeout`
- Phase 1: NEVER retry tests more than 3 times — stop and report failures
- Phase 1: ALWAYS run `pkill -f vitest 2>/dev/null` after every test invocation
- Phase -0: NEVER push or tag during merge conflict resolution
- Phase 0: NEVER deploy with lint errors unless explicit override
- Phase 0: After Biome auto-fix on inline-HTML projects (CF Workers, SSR), ALWAYS run embedded JS string safety check (Stage 1.7 in code-quality.md) — Biome's noUselessEscapeInString silently breaks JS inside HTML template strings
- Phase 0.5: BLOCK on 20+ deployments unless --force-override
- Phase 1: BLOCK on ANY test failure
- Phase 1.1: BLOCK if frontend calls API endpoints with no backend handler
- Phase 1.25: BLOCK on MODERATE+ vulnerabilities unless override
- Phase 1.26: WARN on TODO/FIXME/HACK comments in changed files (auto-fix to NOTE:)
- Phase 1.26: WARN on workflow files missing top-level permissions (auto-fix to read-only)
- Phase 1.26: BLOCK on `permissions: write-all` at workflow top level (must narrow to job-level)
- Phase 1.3: BLOCK if env validation throws at module scope without fallbacks
- Phase 1.3a: When the changeset touches a React component that renders fetched/API data OR a backend handler whose JSON shape the frontend destructures, load `~/.claude/skills/shared/undefined-null-render-safety.md` and run its 9-pattern sweep. BLOCK if any of: (a) a render is gated on a `useState<T|null>`/optional value that can stay null/undefined when the API field is missing/NULL → the control silently vanishes (the `isTest !== null` toggle bug); (b) unguarded `.map`/`.length`/property access on a value that can be undefined (API returned `{}` not `[]`, or an error/404 shape); (c) `.toLowerCase`/`.trim`/`split`/`new Date(...)`/`parseInt`/`JSON.parse` on a possibly-undefined value (renders `NaN`/`Invalid Date` or throws); (d) JSX that can render raw `undefined`/`NaN`/`null`/`[object Object]`. TypeScript does NOT catch these when the response is `any`/`unknown`/`Record<string, unknown>`. Fix every instance (no `@ts-ignore`/`biome-ignore`), do NOT warn-and-continue.
- Phase 1.3a (post-deploy live gate, runs in Phase 4.1): for each changed admin/dashboard/detail view, drive the logged-in REAL Chrome (fcdp) (chrome-devtools MCP or CDP `Runtime.evaluate`) and BLOCK if `document.body.innerText` of the rendered page contains the literal `undefined`, `NaN`, `Invalid Date`, or `[object Object]`, or if the console logged a `TypeError: Cannot read propert(y|ies) of undefined`. The deployed render is the proof — source review alone is not sufficient.
- Phase 1.4: BLOCK if noindex pages appear in sitemap or sitemaps are out of sync
- Phase 1.4-lastmod: AUTO-BUMP the `<lastmod>` of every sitemap URL whose page content/template/copy changed in this changeset, to today's date, before deploy (find the sitemap source — `public/sitemap.xml`, a worker `SITEMAP_XML` const, or a generator — and edit only the touched `<loc>` entries, never the unchanged ones). Commit with the deploy. Do NOT bump pages that didn't change. Post-deploy: `curl` the live `/sitemap.xml` and confirm the changed pages show today's date.
- Phase 5.x reindex (post-deploy, when sitemap `lastmod` changed): the fresh sitemap IS the durable reindex signal — Google picks it up on next crawl. Google's `/ping?sitemap=` GET endpoint was **deprecated in 2023 (returns 404)** — do NOT rely on it. Programmatic GSC resubmit needs a Search-Console-scoped credential on the property (plain `gcloud auth print-access-token` returns 403 — wrong scope). If no scoped credential is available, TELL THE USER the exact manual step: Google Search Console → Sitemaps → resubmit `sitemap.xml`, and URL Inspection → Request Indexing for the top changed pages. Optional: IndexNow (Bing/Yandex) — POST the changed URLs to `https://api.indexnow.org/indexnow` with a key file hosted at the domain root (a separate one-time setup + deploy). Never claim "reindexed" — you can only refresh the sitemap + submit; the search engine decides when to recrawl.
- Phase 1.4-onpage: BLOCK if any page's rendered "Last updated"/"Effective date" is older than the last commit that changed that page's visible copy (`stale`) OR newer than it (`overstated`). Do NOT satisfy this by setting every page to today — that converts a stale date into a false one. Do NOT treat `unknown` as a pass. A page whose date is a hand-typed literal beside the copy is the defect; move it to a registry so it can be audited mechanically.
- Phase 1.4a: BLOCK if a public HTML site lacks OG/Twitter metadata, canonical URL, or a project-specific share image URL that returns `200 image/*`
- Phase 1.4b: BLOCK if any served-HTML site has no favicon — no `<link rel="icon">` in the deployed `<head>` AND no `/favicon.*` route returning `image/*`. AUTO-FIX inline (base64 inline-SVG `<link rel="icon">` added to the `<head>`; add `data:` to `img-src` when a CSP is present), redeploy, and browser-verify the icon decodes to valid SVG and renders before declaring done. Auth-gated pages (CF Access 302) are verified via the repo head template + the logged-in REAL Chrome (fcdp), not an unauth curl. Skip only for pure non-HTML (API/CLI) workers.
- Phase 1.42: BLOCK if no vite:preloadError handler (deploy will log users out)
- Phase 1.42: BLOCK if no CDN-Cache-Control: no-store header on HTML responses
- Phase 4.2: Run multi-agent review when changes span 3+ files or touch security paths
- Phase 4.2: BLOCK if any reviewer finds CRITICAL security/performance issue
- Phase 4.3: WARN if Lighthouse score drops below 50 (severe perf regression)
- Phase 4.35: BLOCK if mobile screenshot shows blank page (broken rendering)
- Phase 4.35: WARN if mobile screenshot shows horizontal scroll (responsive bug)
- Phase 4: WARN if deployed version.json SHA doesn't match local HEAD (stale deploy)
- Phase 4: BLOCK if `CLOUDFLARE_API_TOKEN` in `.env.local` overrides wrangler OAuth (auth conflict)
- Phase 4: Verify `version.json` is in `.gitignore` and not git-tracked (prevents stale commits)
- Phase 4: Verify service worker has `version.json` in NETWORK_ONLY patterns (prevents SW caching)
- Phase 1.46: BLOCK if visibility refetch triggers loading spinner (full-screen flash on tab switch)
- Phase 1.46: WARN if user data hooks lack background refresh (admin changes invisible until reload)
- Phase 1.46: WARN if admin status-change endpoints don't clean up dependent fields
- Phase 1.46: WARN if optimistic updates don't re-sync with server after success
- Phase 1.45: BLOCK if CSP img-src/script-src/connect-src missing third-party CDN domains (broken icons with no console errors)
- Phase 1.45: BLOCK if critical third-party env vars missing from wrangler config
- Phase 1.45: BLOCK if sensitive Worker bindings (`KEY|SECRET|TOKEN|PASSWORD`) are stored as plaintext `vars` instead of `secret_text`
- Phase 1.45: BLOCK if `wrangler secret put` fails with binding-name conflict and the workflow has not removed the plaintext var, deployed without `--keep-vars`, re-put the secret, and re-listed secrets
- Phase 1.45: BLOCK if production Worker dry-run or live HTML contains `pk_test`, `sk_test`, `.accounts.dev`, or a dev auth issuer/JWKS
- Phase 1.45: BLOCK if AIVA or improvebayarea live HTML/CSP contains ANY retired-auth-vendor fingerprint — `clerk.<domain>`, `clerk-js`, `@clerk/`, `.clerk.accounts.dev`, `prime-rhino-99`, `pk_live_`, `pk_test_`, `sk_test`. (This gate previously REQUIRED `clerk.example.com` to be present; that is now exactly backwards — corrected 2026-08-05 after the Better Auth decommission, verified by `dig` NXDOMAIN on all 10 vendor DNS records and `wrangler secret list` showing the vendor secret absent on both Workers.) Do NOT grep a bare `clerk` — improvebayarea renders "City Clerk" municipal records URLs.
- Phase 1.45: BLOCK if a first-party auth deploy cannot answer `GET /api/auth/ok` → 200 and a wrong-password `POST /api/auth/sign-in/email` → 401 (not 500) on the live origin after deploy
- Phase 1.45f: BLOCK an auth/session/passkey/TOTP/password/recovery/sign-out deploy until `~/.claude/skills/shared/account-security-lifecycle.md` is satisfied: every session-creation path challenges enrolled users; no challenge exposes a live session/bearer; sensitive management requires freshness; passwordless and credential cases both pass; actual passkey reauth and safe return routing are tested; returned SDK errors stop navigation; password creation/reset revokes old sessions.
- Phase 1.45f: BLOCK a claim that "the site requires 2FA" when evidence proves only one account is enrolled. Enrollment, challenge enforcement, enrollment policy, and recovery are distinct claims.
- Phase 1.45f: BLOCK secret-removal-only remediation. A committed token remains compromised through Git history until revoked/rotated; store only the replacement in Bitwarden/platform secret storage and verify metadata without printing the value.
- Phase 1.45: BLOCK if municipal submit/category code changed without a regression proving category/form 500 fallback
- Phase 1.45b: BLOCK if ANY 311 backend submitter changed how it forwards address/lat/lng to the city's API without regression tests covering: (a) a LONG-FORM `input.address` with comma+city+state+zip, (b) an EMPTY `input.address` (frontend didn't pass one), (c) a COORD-STRING `input.address` like `"37.77, -122.41"` (legacy fallback shape — must never reach a structured slot). Applies to `src/sf311.ts` Verint slots (`sf_full_address`, `Location_description`, `sf_address_number`, `sf_primary_street_name`, `sf_zip_code`, `sf_city`, `sf_state_code`), `src/seeclickfix.ts` SCF slots (`address`, `location_details[*]`), and any future backend. Verint silently drops structured-location fields when these slots carry long-form strings — Pattern #21 (`error-handling-patterns.md`). Short-address tests do NOT reproduce the bug. The frontline guard is `looksLikeCoordinateString()` in `src/sf311.ts` — any new structured-location-touching code must route through it (or document why the destination accepts coord strings safely).
- Phase 1.45g: BLOCK if Salesforce/Aura 311 catalog, `fetchCaseTypeDetails` parser, `submitCase` envelope, or KV catalog cache changed without structural tests proving: (a) a toast/`validateAddress` fixture unwraps to locator keys (`address`/`location` / `locatorDetails`) — **not** `toastPayload` (that NPE is live); (b) every id-bearing type has `caseConfigId`+`sCaseType` **or** explicit `captureFailure` — 0 dummy `modelFlags`; (c) refuse paths name official field API names (`Permit_Number__c`, `Receptacle_ID__c`, `Type_of_DeadAnimal__c`), not "permit field/question present" / "extra step" stubs; (d) a catalog schema change (new model fields, `captureFailure`, remint) bumped the KV cache key. Post-deploy BLOCK until cache-busted `GET /api/categories` matches those counts (ids / captured / captureFailure / dummy=0 / CSRF=0 / submittable). Pattern #36 (`error-handling-patterns.md`). `/carmack` must not have been the deployer.
- Phase 1.45c: BLOCK if a third-party-response parser (function that returns `{ok, ...}` after reading `response.text()`/`response.json()` from a city form, OAuth callback, webhook, or scraper) was modified AND there is no captured real-success + real-failure fixture under `__fixtures__/` AND/OR the test file doesn't `readFileSync` the fixture. Synthetic hand-written success HTML in tests cannot catch heuristic drift: success and failure pages of ASP.NET WebForms / Verint dform / aspx replays often share 99% of their structure and differ only in a small dynamic element (e.g. `<span id="InfoReq1_lblError">…</span>`). See `~/.claude/skills/shared/third-party-signal-fixtures.md` for the capture protocol and `error-handling-patterns.md` Pattern #23 for the 2026-05-27 DBI reference incident (every IBA-submitted DBI complaint reported as `validation` error for ~10 days while the city actually recorded all of them).
- Phase 1.45d: BLOCK if `~/tools/linkcheck.sh <repo>` reports a browser-confirmed dead external link (genuine 404/410, not a curl bot-block). **Runs on EVERY ship of a site that renders external citations — it is NOT conditioned on the diff touching a URL, because link rot produces no diff.** The checker curls each link and, on any non-200, re-tests via the REAL Chrome profile (fcdp) so government/WAF curl-403s are NOT false-flagged — only links that fail in a real browser block. Report three outcomes, never two: `ok` / `DEAD` / `bot-blocked`; folding bot-blocks into failures trains everyone to ignore the gate, and folding them into passes hides real deaths. When you replace a rotted URL: read the publisher's own sitemap or hrefs rather than guessing a slug, and confirm the new page actually CONTAINS the cited fact — a 200 that does not support the claim is still a broken citation. Treat any source comment like "URLs are used EXACTLY as provided — do not alter" as a hypothesis to re-verify, not a reason to ship a 404.
- Phase 1.45d: **Classify with THREE verdicts, never two.** An HTTP status from a plain client does not classify a link (measured 2026-07-09): `nytimes.com` curl-403 / browser-200 = ALIVE; `fcc.gov` curl-000 (`HTTP/2 stream … INTERNAL_ERROR`) / browser-200 = ALIVE; `calwavetech.com` curl-000 = DEAD (NXDOMAIN); `militarypoisons.org/…` = DEAD behind a *styled* 404 page. Only **NXDOMAIN** proves dead and only a final **2xx** proves alive — everything else is **UNVERIFIED**: warn, do not block (a gate that cries wolf on every WAF gets disabled). Resolve the unverified set in a real browser and read the authoritative status via `performance.getEntriesByType('navigation')[0].responseStatus` (`fcdp open <url>` → `fcdp js`). Two traps: `fcdp js` pretty-prints JSON across lines (match `/\{[\s\S]*\}/` on full stdout, never `tail -1`), and key off `responseStatus`, NOT `readyState === 'complete'` — the latter never fires on JS-challenge pages. Reference impl: `tools/check-links.mjs --check-liveness [--browser]` (TISF).
- Phase 1.45d: **Never substitute a replacement URL you cannot prove points at the same resource.** `calwavetech.com` (dead, a *solar* developer) vs `calwave.energy` (live, an *ocean-wave* company) is a one-character-plausible swap and a fabrication. Confirm by page title/content, else leave it dead and track it. An accepted-dead allowlist entry must carry a reason + tracking id, and a link that comes back to life must be reported as RESURRECTED and fail — otherwise the ledger rots into a mute button.
- Phase 1.45d: Do NOT put liveness checking in `build`/`predeploy` — a network probe fails the build on someone else's outage. Run it on a cadence and block only on the shape checks at build time.
- Phase 1.45e: BLOCK if a referrer-sensitive `<iframe>` (youtube / youtube-nocookie / player.vimeo / open.spotify / w.soundcloud / players.brightcove) lacks `referrerpolicy` while the live site returns `Referrer-Policy: no-referrer` (Hono `secureHeaders()` default) — the embed renders "Error 153: Video player configuration error". Fix on the iframe, never by weakening the global header. Verify on the DEPLOYED HTML (attribute casing differs between `hono/jsx` and React) plus a browser screenshot showing the player; a post-deploy curl within ~30s can still show the old version (propagation), so poll rather than conclude.
- Phase 1.45e: BLOCK if any rendered `href` contains whitespace (a prose renderer swallowed the description into the URL) or if any YouTube id in source/rendered HTML is not exactly 11 chars of `[A-Za-z0-9_-]`, or if a URL literal has a malformed host (`https://.example.com`).
- Phase 1.45e: BLOCK if a change autolinks previously-inert prose URLs without validating every newly-created anchor — diff the anchor set before/after and curl each new href (a browser re-check distinguishes a WAF 403 bot-block from a genuine 404).
- Phase 1.29: BLOCK the deploy until the `security-review` skill returns 0 findings — **and the moment it does, CONTINUE to Phase 2/3/4 in the same turn without asking.** **`cd` into the repo root FIRST** — `security-review` reviews the current working directory's git-branch DIFF and hard-fails `"needs to run inside a git repository"` if cwd is wrong (verified 2026-07-22). Run it in a LOOP: `cd <repo>` → invoke `security-review` → fix every reported finding (confidence ≥8) in source (No-Suppression Rule — no `@ts-ignore`/`eslint-disable`/`biome-ignore`) → re-invoke → repeat until the report is empty. Never deploy past an open security finding; a genuine false positive must be documented inline with its reason. Loop guard: same finding surviving 5 fix attempts → STOP and surface to the user, do not deploy. If `security-review` is unavailable (unknown-skill), WARN + fall back to Phase 1.45 grep checks — do not silently pass. Skip only for pure docs/comment diffs.
- Phase 1.29: **A clean report is NOT a stopping point.** Halting on 0 findings is a defect of this gate in exactly the way deploying on ≥1 finding is — the first leaves the ship undone, the second ships a vulnerability. The 5-attempt loop guard is the ONLY condition under which 1.29 hands control back to the user. Reference incident 2026-08-07 (improvebayarea): a genuine non-vacuous 0-finding review over 3,172 changed lines was treated as the end of the task; the user had to re-prompt to get the merge and deploy done.
- Phase 1.29: **BLOCK on a VACUOUS gate.** Before invoking, compute `BASE=$(git merge-base HEAD origin/HEAD)` and check `git diff --stat "$BASE" HEAD`. If that range is EMPTY while this ship has a real changeset (the default whenever `HEAD == origin/main` — shipping from main post-push, re-running/resuming `/ship` on an already-pushed repo, or a first push), the tool reviews ZERO code and its "0 findings" is arithmetic, not assurance. Do NOT record it as a pass: identify `$SHIP_BASE` (the commit prod is actually running), review `git diff $SHIP_BASE..HEAD` — preferably by re-running the gate from a feature branch pre-merge, otherwise manually against the same categories — and label it in the report as VACUOUS + manually reviewed. Reporting "Phase 1.29 clean" when the diff was empty is a fabrication. Reference incident 2026-07-30 (improvebayarea): commits `f9142b1` and `4da7798` were both already on `origin/main`, so the gate returned 0 findings over 0 lines and would have been recorded as a clean security review.
- Phase 1.45: BLOCK if raw `.innerHTML =` without escapeHtml() (XSS risk — especially entry points outside src/)
- Phase 1.45: BLOCK if dangerouslySetInnerHTML without DOMPurify (XSS risk)
- Phase 1.45: BLOCK if JSON.stringify in script tag without `</` escaping (script breakout)
- Phase 1.45: WARN if async onClick without disabled state (double-click risk)
- Phase 1.45: WARN if pages call secureFetch without frontend auth guard (degraded UX)
- Phase 1.45: WARN if admin routes throw Error instead of HTTPException(403)
- Phase 1.56b: BLOCK any new/changed health check, probe, validator, monitor, drift job or verification sweep that has not been shown to FAIL on a named known-bad input, with that negative control committed as a test. A green board is not evidence the instrument works; "consumer-path" framing does not make a probe valid (the reference incident's probe *was* the consumer path). **Echo is not validation.**
- Phase 1.56b: BLOCK a pass/fail result type with only two outcomes when "could not measure" is reachable — `ok` / `genuinely bad` / `unreadable` must be distinct, or an upstream redesign becomes 435 false alarms and a bot-block becomes a clean bill of health.
- Phase 1.56b: BLOCK shipping a hardcoded `verified:`/`lastChecked:` date on upstream-harvested data as a health signal. Rename it to `harvestedAt`, add the scheduled re-verification, expose the last result, and mark it stale past ~2 intervals — otherwise a dead cron is indistinguishable from all-healthy. WARN when a claim rests on a sample rather than the population (a 30-of-435 sample read `stale=0` against a real 1.1% drift rate); state which one was measured.
- Phase 1.56b: BLOCK a retraction of a prior finding whose only support is that a *different* measurement came back clean — apply this gate to the replacement measurement first.
- Phase 1.57: BLOCK if a changed call site talks to an upstream with MULTIPLE independent rejection causes sharing ONE error string and the failure path reports only that string. Attach the sent payload's measurable properties (lengths + boolean flags, never the content). Rationale: a static error is not a discriminator, so N causes cost N deploys — Pattern #32, `~/.claude/skills/shared/opaque-multi-cause-failure.md`.
- Phase 1.57: A health/status probe that deliberately STOPS BEFORE the step that actually fails (e.g. exercises auth+presign but not submit, to avoid creating a record) is blind by construction and MUST say so in its own return shape — callers may not treat its `ok:true` as end-to-end health. Pair it with a real-outcome counter (failures/fallbacks today) and alert on the COUNTER. Reference: `/api/admin/solvesf-health` read green through a 100% submit failure for a full day, partly because an intermediate step accepted a value the final step rejected.
- Phase 1.5: NEVER skip verification if migrations/backfills detected
- Phase 1.55: BLOCK if a per-request query (esp. `COUNT(*)`/`SUM(CASE...)`/`ORDER BY x LIMIT 1 OFFSET N/2` over `WHERE <partition_key>=?`) reads >~100k rows — measured via `wrangler d1 execute --json`; fix = cache it, drop it, or scope it to the window
- Phase 1.55: BLOCK if a `readCached*`/`KV.get`/`caches.match` has no corresponding writer in the codebase (permanent cache miss in prod) — grep for the writer
- Phase 1.55: BLOCK if a cache-warmer cron warms keys nothing reads, or warms a different key-shape than the route reads (e.g. `oak311:open_data:...` vs `agg:...`) — the route never gets a cache hit
- Phase 1.55: BLOCK if a query that runs before the cache check stays expensive on a cache HIT — fold it into the cached payload, move it after the check, or cache it separately
- Phase 1.55: BLOCK if a `WHERE ts >= now() - <interval>` filter targets a lagged data source (Socrata/DataSF/batch ETL) — anchor on `MAX(ts)` instead and label "latest N of published data"; verify against the live source's `MAX(ts)`
- Phase 1.55: WARN if a TEXT-timestamp range scan's stored format ≠ the comparison literal's format (ISO-with-`Z` vs floating-no-`Z`) — `EXPLAIN QUERY PLAN` should show `USING INDEX`, not `SCAN`
- Phase 1.56: BLOCK if any column referenced in a changed `INSERT INTO`/`UPDATE … SET` (or a newly-referenced table) does NOT exist in the **remote** D1 `PRAGMA table_info` — this 500s every write to that table in prod with a generic "Internal Server Error". Verified by `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>` (exit 1 = drift). The migration file existing and the local D1 having the column are NOT proof; only remote `PRAGMA` is. Fix the prod schema (additive `ALTER … ADD COLUMN`/`CREATE … IF NOT EXISTS`) BEFORE the code deploys.
- Phase 1.56: BLOCK if `wrangler d1 migrations list --remote` is not clean ("No migrations to apply") — unapplied entries mean drift. Reconcile by applying only genuinely-missing DDL then `INSERT OR IGNORE`-ing filenames into `d1_migrations`. NEVER `wrangler d1 migrations apply` to catch up a drifted DB (re-runs non-idempotent data migrations like `UPDATE steps SET order_index = order_index + 1` → data corruption; bare `CREATE`/`ALTER` error on existing objects).
- Phase 1.56: BLOCK if a changed D1 write handler leaves its `.run()` outside a try/catch — a schema/D1 error must be logged with its real cause (`sanitizeError(err)`) and returned as clean JSON, never thrown uncaught into the framework's generic 500 (ties to Phase 1.57).
- Phase 1.56a: BLOCK any resource DELETION (DNS record, cert/cert pack, route, binding, bucket, queue, cron trigger, worker) whose justification is a management-API read alone. Require BOTH: (a) audit-log provenance naming what created it — `actor.type: system` means the platform provisioned it and something depends on it; (b) a consumer-view probe (`dig`, `openssl s_client`, `PRAGMA table_info --remote`, `wrangler secret list`, `Authentication-Results` on a delivered message, cache-busted `curl`) rather than the config table. **Never delete a resource you cannot name the creator of.**
- Phase 1.56a: BLOCK any ship whose rationale contains an absence claim ("the API shows X is missing", "nothing references this") that was not confirmed against the authoritative consumer view. A count mismatch between the declared and authoritative views IS the finding — resolve it, don't average it. Pattern #31: `~/.claude/skills/shared/management-api-vs-authoritative-state.md`.
- Phase 4.05d: Run `cf-security-insights.sh --apply` (account-wide: all zones + all Workers) when CF creds exist — applies AI-bots-block/AI-Labyrinth/security.txt per zone AND `previews_enabled=false` on every Worker (the `.cloudflare.app` preview class behind the TLS/Always-HTTPS/HSTS insight emails); auto-skips Bot-Fight/unproxied-CNAME/dangling-A/DMARC (false-positive classes); reports (never auto-fixes) workers.dev-enabled custom-domain workers. ADVISORY — report changes, never block. Replaces the paused cf-security-watch cron; coverage is now per-ship (event-driven), with CF's native insight emails as the between-ships backstop.
- Phase 4.7: BLOCK if a Capacitor repo's OTA publish includes native-affecting changes (ios/, capacitor.config.ts, @capacitor*/@capgo* deps) without a prior native release + MIN_SHELL_VERSION bump
- Phase 4.7: BLOCK "shipped to TestFlight" claims until the build is VALID AND assigned to a tester group (IN_BETA_TESTING) — upload alone notifies nobody
- Phase 4.7: BLOCK native archive without greenlight preflight 0-CRITICALs + PrivacyInfo.xcprivacy present + IPA scan GREENLIT
- Phase 4.7.0a: BLOCK any native build/TestFlight upload until the release-channel ask (TestFlight only / + App Store / hold) is answered; BLOCK App Store submission without an explicit same-session "App Store" answer — bare "/ship" is never App Store consent (web-class OTA-only changes skip this gate; nothing reaches App Review)
- Phase 3.5: NEVER update README if tests didn't pass 100%
- Phase 3.55: ALWAYS run `scripts/regen-readme-status.sh` (or project equivalent) when present — commit + push the diff with `[skip auto-readme]` BEFORE deploy. BLOCK Phase 4 if regen fails or the diff isn't pushed.
- Phase 4: NEVER report success without URL verification
- Phase 4.5: NEVER auto-rollback without user confirmation
- Phase 6: NEVER merge a remote PR automatically — only humans merge remote PRs.
  Local branch-to-main reconciliation follows LOCAL MAIN RECONCILIATION above
  and may run automatically after all gates pass.
- Phase 6: NEVER force-push, dismiss reviews, or override branch protection
- Phase 6: NEVER modify files outside the PR's changeset
- Phase 6: Max 5 fix-push cycles, max 30 min runtime — then exit with report
- Phase 1.5: NEVER run terraform destroy or apply -auto-approve
- Phase 1.5: BLOCK if terraform plan shows resources being destroyed

---

## Output Discipline (from internal conciseness anchors)

Between tool calls: **max 1-2 sentences** explaining the next action.
Final deployment summary: concise bullet points, no preamble.
When fixing issues inline: state what was wrong and what was done in one line each.
Never repeat tool output back to the user — they already see it.
Phase transitions: one-line banner only (e.g., `-- Phase 0 OK -> Phase 1: Build & Test --`).

## TONE

Be authoritative and safety-focused. Be firm about quality requirements while remaining helpful when errors occur. Emphasize that quality gates protect the user, their data, and their users. When blocking deployment, clearly explain why and provide specific remediation steps.

---

## Instructions

When this skill is invoked:

**STEP 1 — Read all reference files:**

Read all 9 reference files from `~/.claude/skills/ship/references/` PLUS `~/.claude/skills/shared/ant-verification-protocol.md` (ant-level quality gates) to have full deployment protocol available. If auth/session/passkey/TOTP/password/recovery/sign-out code changed, also read `~/.claude/skills/shared/account-security-lifecycle.md` completely.

**STEP 2 — Execute phases in order:**

Follow the Phase Execution Order above, reading the detailed instructions from the corresponding reference file for each phase. Fix all issues inline before advancing to the next phase.

**STEP 3 — Verify before declaring success (Ant-Level Truthfulness Protocol):**

Run the Pre-Ship Verification Checklist. Apply the Truthfulness Protocol from ant-verification-protocol.md Section 2:
- Every claim must be backed by command output (curl, build log, test result)
- Never say "deployed successfully" without curl evidence of new bundle hash
- If ANY check fails, fix it — don't report success with caveats
