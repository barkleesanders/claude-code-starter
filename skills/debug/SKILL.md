---
name: debug
user-invocable: true
description: "Quick debugging patterns and known production failure traps. Reference guide for common issues."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
model: inherit
---

# /debug - Debugging Quick Reference

Fast reference for known production failure patterns. For deep debugging, use `/carmack`.

## Mandatory upstream-protocol check (third-party integrations)

When the symptom involves a third-party integration falling back to a worse path (handoff, redirect, "manual step required") — Verint dform, Clerk, Stripe, SeeClickFix, OAuth, any SaaS — load `~/.claude/skills/shared/upstream-protocol-investigation.md` BEFORE proposing a fix. Read the upstream's primary client source, capture real network traffic, inspect rendered `data-*` attributes. Treat any "Verified YYYY-MM-DD" comment in our codebase as a hypothesis to re-verify, not a fact. Token cost is unlimited for this; user explicitly authorized it (2026-05-09 SF311 graffiti incident: bandaid `0b746a4` → real fix `f27d1e3` after reading dform's `api.js` lines 462–520).

## Mutating symptom across fixes = wrong premise (MANDATORY — 2026-05-19)

When each fix makes the symptom *change* instead of *disappear* — `fetch_error` → `handshake_rejected` → `publicid_timeout`, every "fix" peeling back to reveal a new failure one layer deeper — STOP. That staircase is the tell that the whole feature premise is wrong, not that you are three fixes from done. Before fixing layer N+1, verify the premise itself: does the real client even use this code path? Capture live traffic and confirm. Reference incident: the SF311 cable chain — four green-tested fixes (`wss://`→`https://`, missing `Origin` header, subscription identifier, publicId timeout) each surfaced the next layer; a live mitm capture then proved the real app never opens the WebSocket at all — the whole path was dead code. Many round-trips of "fix the next layer" should have been one round-trip of "verify the premise."

**PREMISE-CHECK GATE — run BEFORE the first fix (not just on the staircase). Full rule: `~/.claude/skills/shared/premise-check.md`.** Two questions, answered against LIVE upstream docs (not a cached `/skill` note): (1) **Is this approach even valid for THIS runtime/SDK/platform?** The browser SDK ≠ native SDK ≠ server SDK — a strategy/option/API documented under one is routinely absent or *forbidden* in another. If every doc/example for the thing you want sits under a *different* platform than yours, that's your answer — stop. (2) **What's the cheapest probe** (curl the API / grep the installed bundle / read the doc's "supported platforms" line) that proves it's possible here? Run it before coding. **Docs-before-note (always):** a `/skill` recipe, comment, memory, or prior conclusion is a HYPOTHESIS — re-verify any load-bearing "API/SDK can/can't do X" claim against the upstream's own *current* docs/source before building on it; live source wins, fix the stale note in the same pass. **2026-06-13 reference incident:** hours spent debugging Clerk native `oauth_token_apple` from a Capacitor webview — clerk-js (browser SDK) can never send it (browser-forced `Origin` vs Clerk Native-API `Authorization` conflict), a fact Clerk's docs state plainly under "Expo only." A wrong `/ios` trap-#4 note was trusted as fact; the working web-OAuth fix was a 5-minute live-doc read away. Now also enforced session-wide by the `premise-check-session-start.sh` SessionStart hook.

## No-Lie Post-Fix Gate (MANDATORY — 2026-05-18)

A "fixed" symptom is one that fails to reproduce on the *deployed/built artifact*, not in the source. After EVERY fix, before declaring root cause resolved, run the **No-Lie Verification Protocol** from `~/.claude/skills/shared/no-lie-verification.md` Checks 3 + 4:

1. **Symptom re-test on the artifact**, not the source. Examples:
   - "Stale copy" bug → cache-busted `curl https://prod-url/path` for the OLD string. Expected: 0 matches.
   - "API 500 on category X" bug → `curl -X POST` reproducing the original request with a fresh cache-buster. Expected: 200 or the deliberate fallback, never a regression.
   - "Race condition in worker" bug → run the original repro harness (`tools/repro/*.sh`) under load and confirm the failure no longer reproduces over N runs (N≥10).
2. **Whole-repo symptom re-grep**, not just touched files. Proves "fixed all instances", not "fixed the ones I noticed". The whole-repo grep must return 0 matches OR only matches that are demonstrably unrelated (JSON values, log files, third-party node_modules).
3. **If the fix is in TRIGGERED behavior** (failover, retry, fallback, circuit-breaker, rate-limit cooldown, error/`catch` branch, conditional cron) — **induce the trigger and watch the path fire** (Check 6 in `no-lie-verification.md`). Don't infer it from "the parts work": force the 429 / fail the dependency N times / feed the exact bad input on an isolated copy, confirm the fallback/retry/error-path actually executed, then confirm the live instance is untouched. "Configured" ≠ "fires."
4. **Every claim in the final report cites the command that proves it.** Forbidden without proof: "fixed", "verified", "root cause confirmed", any specific count.

**Reference incident (2026-05-18):** /carmack agent reported "no stale '10,000' strings — `rg` clean" but never curl'd the live URL. Old build was still serving until /ship deployed. The fix wasn't a fix until the deployed artifact was re-tested.

## Usage

```
/debug [pattern name or symptom]
```

## Examples

- `/debug catch-all` -- Catch-all error handling masking root cause
- `/debug react undefined` -- React "X is not defined" scope bug
- `/debug silent startup` -- React silently fails to mount
- `/debug auth failed` -- Generic auth error hiding real cause
- `/debug broken icons` -- Third-party icons/images missing (CSP blocking)
- `/debug text overflow` -- Text escaping card boundaries on mobile
- `/debug stale data` -- Admin changes not visible to users
- `/debug deploy logout` -- Users logged out after every deploy
- `/debug cloudflare security alert` -- Cloudflare flagged site for missing security.txt / HSTS / CAA / DNSSEC
- `/debug slow page` -- Page/route slow: full-table scan on the hot path, cron warming the wrong cache, or a lagged-source window returning empty
- `/debug cookies` -- Need cookies for curl/yt-dlp/scrape from a logged-in browser session (see "Cookie extraction" below)

---

## Pattern numbering (read before adding one)

Pattern numbers are **globally unique across all reference files**, not per-file. Before adding
`## Pattern N:`, claim the next free N:

```bash
grep -rhoE "^## Pattern [0-9]+:" ~/.claude/skills/debug/references/*.md \
  | grep -oE "[0-9]+" | sort -n | tail -1        # highest in use
grep -rhoE "^## Pattern [0-9]+:" ~/.claude/skills/debug/references/*.md \
  | grep -oE "[0-9]+" | sort -n | uniq -d        # existing collisions
```

`#12` and `#15` are **legacy collisions** (two distinct patterns each). Always cite a pattern as
*file + number* (`error-handling-patterns.md #29`), never a bare number, so a collision can never
misroute an agent.

---

## Pattern Routing

Match the user's symptom to the right reference file, then load ONLY that file.

| Symptom / Keyword | Pattern | Reference File |
|--------------------|---------|----------------|
| iOS app, simulator, Xcode, Swift crash, .ips crash log, Capacitor shell misbehaving, WKWebView rendering wrong (e.g. border-radius not clipping a composited img), in-app sign-in bounced to Safari, app stuck on splash / OTA rollback, webview UA flagged as in-app browser, **Clerk/Apple/Google social sign-in failing in a Capacitor app — `authorization_invalid` / `native_api_disabled` / `origin_authorization_headers_conflict` / `oauth_token_apple` / "native social login won't work in the app", OR a passkey/WebAuthn ceremony failing in the webview — "passkey registration was cancelled or timed out", `webcredentials`, associated domains, AASA 404** | iOS App Symptoms — route to the `/ios` skill (dev/debug loop, axiom crash/build/perf agents, webview driving via axe, simulator streaming/eyes + taps + `:3100/ax` a11y tree via the `/serve-sim` skill, AIVA Capacitor traps incl. clerk-js `allowedRedirectProtocols`, notifyAppReady rollback, WKWebView clip bug). **Any in-webview auth/credential ceremony fails with a GENERIC error until the app↔domain binding exists — read /ios trap #12's binding matrix and PROBE FIRST: social-OAuth Apple → trap #4 (`allowNavigation`); Google → policy-blocked, hide it; clerk-js scheme → `allowedRedirectProtocols`; passkey "cancelled or timed out" → `curl <domain>/.well-known/apple-app-site-association` + grep entitlements for `webcredentials` (improvebayarea `dadfdf3`). Don't debug the JS ceremony before the 30-sec probe.** | `/ios` skill (`~/.claude/skills/ios/SKILL.md`) |
| catch-all, generic error, wrong status code, misleading error | Catch-All Error Masking (#1) | `error-handling-patterns.md` |
| SF311 save 500, Verint save 500, Improve AI resubmit, category changed 500, request_type_id 500 | External Municipal Form Category Hard-500 (#15) | `error-handling-patterns.md` |
| ticket description truncated, navFooter dropped, map links missing, address missing on filed ticket, description ends abruptly, external form truncation, Verint dform Request_description, bracket truncation, square bracket strip | External Form Description Truncation by Character (#19) | `error-handling-patterns.md` |
| 311 ticket missing Location box, Open311 address null, mobile311 viewer shows description but no Location dt/dd, "one ticket has location another doesn't", sf_full_address dropped, Location_description ignored, structured location empty, lat/long null in Open311, address only in description body not the actual location field, scf location_details, address forwarding broken, coord-string in structured slot, "hardening 311 address forwarding", multi-city address never break | 311 Structured-Location Dropped by Long-Form / Coord-String Address (#21, backend-agnostic) | `error-handling-patterns.md` |
| DBI complaint reported as validation but city has it, "DBI re-rendered the form (validation rejected the submission)" but DataSF shows the case, third-party form rejected but actually recorded, form echoed back on success, parser says failure but the agency received it, external form 200 OK we classified as failure, complaintNumber undefined but submission worked, dform/Verint/aspx false-negative on success, success-detection heuristic matches both success AND failure pages, lblError success vs failure span, signal-extraction tests use synthetic HTML, every IBA-submitted DBI complaint fails | Third-party signal-extractor false-negative due to synthetic fixtures (#23) | `error-handling-patterns.md` + `~/.claude/skills/shared/third-party-signal-fixtures.md` |
| CI false positive, grep wrong, CI still fails | CI False Positives (#11) | `error-handling-patterns.md` |
| admin 403, requireAdmin, metadata-only | Admin Auth Missing DB Fallback (#14) | `error-handling-patterns.md` |
| admin 500 instead of 403 | Admin Route Wrong Status | `error-handling-patterns.md` |
| react undefined, scope bug, not defined | React Scope Bug (#2) | `react-patterns.md` |
| silent startup, blank page, no console errors, module-level throw | Silent React Startup (#3) | `react-patterns.md` |
| useEffect, renders twice, state lags, derived state | useEffect Abuse (#15) | `react-patterns.md` |
| localStorage, preference lost, resets on refresh | Preference Lost on Reload (#13) | `react-patterns.md` |
| double click, duplicate API call, async button | Async Button Double-Click | `react-patterns.md` |
| chat/support widget gone after SSR, cookie banner missing on SSR page, `?support=open`/deep-link does nothing, global widget vanished after Hono/Astro/RSC conversion, "worked on every page before SSR", floating launcher dead, analytics/exit-intent dropped on SSR route | Global App.tsx Component Vanishes After SPA→SSR Conversion (#24) | `react-patterns.md` |
| invisible text after SSR, white headings on light/gray bg, page background wrong color after conversion, "colors got messed up on conversion", body background overridden, SSR design clobbered by Tailwind/island CSS, text disappeared but HTML is there, computed bg ≠ design token, low contrast only on SSR pages, island/global CSS leaks `body` styles | Bundled Island/Global CSS Clobbers SSR Inline Design — Invisible Text (#25) | `react-patterns.md` |
| auth guard, unauthenticated error, no redirect | Missing Frontend Auth Guard | `react-patterns.md` |
| renders undefined, shows NaN, "Invalid Date", "[object Object]", toggle/section/control disappeared or silently vanished, "make sure nothing is undefined", Cannot read properties of undefined, is not iterable, null-gate hides UI, `useState<T\|null>` gates a render, `.map`/property access on possibly-undefined API data, admin/dashboard renders garbage, optional chaining missing | Undefined / Null-Render Safety (9-pattern catalog + live DOM grep for `undefined`/`NaN`/`[object Object]`) — also re-sweeps the adjacent admin blind-spot class (default-LIMIT truncation, NULL-aggregate sort burial, count-source mismatch, inner-JOIN row drop, admin-auth DB fallback) | `~/.claude/skills/shared/undefined-null-render-safety.md` |
| generic `isRecord`/`isObject` guard, `as unknown as T`, `(x as any).field`, repetitive type-guard boilerplate, "vibe coding" / AI-slop TypeScript, loose `unknown`-everywhere, no schema validation at boundary, `Record<string, unknown>` everywhere | Anti-Slop TypeScript — replace generic guards/casts with named types, discriminated unions, or Zod (`z.infer`); detector: `~/.claude/skills/carmack/tools/detect-ts-slop.sh` | `~/.claude/skills/shared/anti-slop-typescript.md` |
| text overflow, min-w-0, flex escape, card boundary | Text Overflow Flex+Grid (#12) | `css-layout-patterns.md` |
| grid mobile, grid-cols, responsive breakpoint | Fixed Grid Breaks Mobile | `css-layout-patterns.md` |
| iOS Safari, blank iPhone, PDF iframe, vh units | iOS Safari Rendering | `css-layout-patterns.md` |
| og image, twitter card, social cache, stale card | Social Card Cache (#5) | `csp-cache-patterns.md` |
| CSP, embed blank, frame-src, img-src, broken icons | CSP Blocking (#9) | `csp-cache-patterns.md` |
| **YouTube "Error 153", "Video player configuration error", embed shows gray panel / "Watch video on YouTube", Vimeo/Spotify/SoundCloud embed won't load, video plays on youtube.com but not on my site, embed broke after adding security headers / `secureHeaders()` / Hono** | **Embed Dies With No `Referer` (#27)** — NOT CSP, NOT the video. The page sends `Referrer-Policy: no-referrer` (Hono `secureHeaders()` **default**; also .htaccess / WP security plugins / ad blockers). YouTube has refused Referer-less embeds since late 2025. Probe FIRST, 30s: `curl -sI https://<site>/ \| grep -i referrer-policy` (→ `no-referrer` = confirmed) and `curl -s -o /dev/null -w "%{http_code}" "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<ID>&format=json"` (200 = video is fine; 401 = embed disabled; 404 = dead). Fix = `referrerpolicy="strict-origin-when-cross-origin"` **on the iframe** — never weaken the global header. Verify on the DEPLOYED artifact (`hono/jsx` vs React attribute casing can drop it) + a real browser screenshot; allow >30s for Worker propagation before concluding. Sweep the repo for the sibling bugs: rendered `href`s containing whitespace (renderer swallowed prose into the URL) and bare URLs rendering as dead text. | `csp-cache-patterns.md` (Pattern 27) |
| Cloudflare security alert, **Security Insights CSV**, security.txt missing, /.well-known/security.txt 404, securityheaders.com low score, observatory grade D, missing HSTS/CSP/COOP/CORP, CAA records, DNSSEC, RFC 9116, sitemap.xml 404, robots.txt advertises sitemap that doesn't exist | Site Security Baseline (#16) | `~/.claude/skills/shared/site-security-defaults.md` |
| **CF Security Insights flags: "Dangling A/AAAA", "Unproxied CNAME", "DMARC Record Error", "Bot Fight Mode not enabled"** — DO NOT blindly apply CF's recommended fix; ~16% are false positives that break Clerk/SaaS CNAMEs, delete live Google-forwarding DNS, or duplicate valid DMARC. `dig`/`curl`-verify the OFTEN-FALSE classes first. Apply only the 3 safe fixes (security.txt + block AI bots + AI Labyrinth). | CF Security Insights triage map | `~/.claude/skills/shared/site-security-defaults.md` (triage section) + `~/.claude/skills/carmack/tools/cf-security-insights.sh` |
| **DMARC failing from a sender IP, custom-domain mail bouncing / landing in spam, "send-as alias DMARC fail", Gmail "Send mail as", `p=reject` rejecting my OWN mail, "SPF passes but DMARC fails", "can't send from my domain", forwarded mail failing DMARC, a DMARC aggregate (RUA) report flags a source** — this is OUTBOUND auth alignment, NOT broken records. Records are usually fine; the *sending path* is wrong (Gmail send-as / a relay signs as the wrong domain → no aligned identifier → DMARC fail). `dig` the real SPF/DMARC/DKIM/MX FIRST; adding the relay's IP to SPF usually does NOTHING (SPF aligns on the envelope domain). **Check the platform's CURRENT native send capability before recommending a 3rd-party — verify live, not from memory**: a Cloudflare domain can now SEND via Email Sending (`wrangler email sending list/settings`; `smtp.mx.cloudflare.net:465`, user `api_token`, pwd = CF token w/ `Email Sending Write`). Fix = route the From-domain's sending through a DKIM-aligned sender; verify with a REAL send (`gog send --from <alias>` → grep `dmarc=pass`). | Email Deliverability / DMARC Alignment | `~/.claude/skills/shared/email-deliverability-dmarc.md` |
| **provider swap, replace Resend/Auth0/Stripe/S3/Twilio with X, migrate email/auth/payments provider, "switch from X to Y", removed the old SDK, deleted the old API key, feature silently stopped after swapping providers, `if (!env.OLD_KEY)` gate, legacy ids unresolvable, old provider ids in DB** | **Provider Migration Safety** — four silent breakages, none of which throw: (1) feature gates still testing the OLD provider's env var (incl. `CRITICAL_ENV_VARS`) → feature disabled forever once the secret is deleted; (2) persisted legacy identifiers the new API can't resolve → zero rows → a confident wrong status; (3) the new SDK returns `{data,error}` instead of throwing → every failure reads as success; (4) the local emulator (`wrangler dev`) doesn't enforce the new provider's server-side rules → local green ≠ prod accepted. Run the 7-item checklist. **Never decommission the old account off one repo's grep** — another project may hold a live key on the same verified domain. | `~/.claude/skills/shared/provider-migration-safety.md` |
| **status chip says "expired"/"not found" on rows that are fine, freshly-created record reads as missing, a uniform block of rows all show the same scary status, status derived from analytics/GraphQL/search backend, zero rows treated as a reason, `retention_expired` on brand-new data** | **Absent Data Reported As A Confident Wrong State (#29)** — `rows.length === 0` has ≥4 causes (ingestion lag, wrong id namespace/provider, real retention expiry, never created, query failed) and they need different words. Discriminate on identifier SHAPE before querying (free), use the system of record's `created_at` vs the backend's ingestion grace window to separate lag from expiry, model reasons as a union, and never render a raw enum in the UI. | `error-handling-patterns.md` (Pattern 29) |
| **third-party submit "worked" (200 + id, no error) but the ticket/record never went live — never got a public number, never opened, never associated, `openedAt: null`, `publicId: null`, `submittedTickets: 0`; guest/anonymous create dead-ends silently; A/B-tested a flag/category/field and the symptom stayed IDENTICAL; "why does spotmobile/guest submit never get a case number"; freshly-minted guest token; shadow-limited actor; "is it the payload or something else"** | **False-Positive Success — async lifecycle is the real signal + IDENTITY is the hidden variable (#30)** — a synchronous 200+id is a *pending* state, not *done*; gate success on the lifecycle transition (public number / `opened` / row in public dataset), polled, against a known-good baseline. When fix-A/fix-B/fix-C leave the symptom byte-identical, STOP editing the request — the actor/identity/account you held constant is the variable; re-run the SAME payload under a known-good established identity FIRST. Prove the working backend by RUNNING THE REAL FUNCTION LIVE (repro harness → real id), never from old code or a "Verified" comment. | `error-handling-patterns.md` (Pattern 30) |
| **"the deploy broke prod", `Failed to load module script ... MIME type "text/html"`, SPA won't mount after deploy, only SEO fallback text renders, `ERR_BLOCKED_BY_CLIENT`, page worked 5 min ago, verifying a deploy in a `:9222`/clone browser** | **Your Verification Browser Is Stale — False "Prod Is Broken" (#28)** — a cached HTML shell references pre-deploy asset hashes; the SPA fallback serves `index.html` for the missing `.js`; the browser refuses HTML as a module script. **Production is fine; only your tab is broken.** NEVER conclude a bad deploy from a browser alone: curl the live HTML for its asset refs, confirm each returns `200 text/javascript` (not `text/html`), and grep the deployed chunk for a string only your new code has. `location.reload(true)` is a no-op; use `navigate_page {ignoreCache:true}` or a cache-busting query param. `ERR_BLOCKED_BY_CLIENT` = ad blocker, not your code. | `csp-cache-patterns.md` (Pattern 28) |
| dependabot alert, npm audit, CVE, GHSA-xxxx, "vulnerable dependency", transitive vuln, "fix the security/dependabot page", overrides, esbuild/tar/minimatch/ws/vite/uuid vuln, `npm install` fails on override version | Dependency Vulnerability Audit & Fix (7-step: BOTH dependabot-api + per-manifest npm-audit, scan EVERY lockfile, scoped overrides for multi-major packages, verify patched version is published, never blind `npm audit fix --force`, verify build with project's real build) | `~/.claude/skills/shared/dependency-audit.md` |
| www redirect, cookies lost, auth break | WWW Redirect Auth Break (#4) | `csp-cache-patterns.md` |
| deploy logout, chunk hash, preloadError | Deploy Logs Users Out | `csp-cache-patterns.md` |
| stale version, failed deploy, CF Pages | CF Pages Stale Deploy | `csp-cache-patterns.md` |
| terraform destroy, infra deleted, catastrophic | AI Agent Destroys Infra (#6) | `infrastructure-patterns.md` |
| prod auth, pk_test, accounts.dev, Clerk production, Wrangler binding, wrong auth instance | Production Auth Instance Drift (#12) | `infrastructure-patterns.md` |
| prime-rhino, clerk.example.com missing, live HTML/CSP differs from dist, prod integration fails | AIVA Live Artifact/Auth Drift (#12a) | `infrastructure-patterns.md` |
| wrangler secret put binding already in use, plaintext Worker var, secret_text missing, BREVO_API_KEY in vars | Worker Secret Binding Drift (#12b) | `infrastructure-patterns.md` |
| **D1 route 500s with generic "Internal Server Error", `no such column`/`no such table`, `D1_ERROR`, intake/any-write save fails for everyone, migration file exists but column missing in prod, `wrangler tail` shows outcome Ok + empty exceptions, schema drift, migration not applied to remote** | **D1 Schema Drift — migration-file-exists-but-not-applied-to-prod** (#26). Detect: `wrangler tail --format json` → grep logs for `D1_ERROR`/`no such column` (it's in `logs[]`, not `exceptions[]`); confirm with `PRAGMA table_info(<t>)` on `--remote` (the file/local-D1 are NOT proof). Fix: additive `ALTER … ADD COLUMN`/`CREATE … IF NOT EXISTS` on remote, then `INSERT OR IGNORE` the filename into `d1_migrations` — NEVER bulk `migrations apply` (re-runs non-idempotent data migrations → corruption). Gate: `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>`. | `~/.claude/skills/shared/d1-schema-drift.md` |
| rust clippy, cross-platform, cfg, unused_mut | Rust Cross-Platform Lint (#7) | `infrastructure-patterns.md` |
| homebrew, keg-only, launchd, cron PATH | Homebrew Keg-Only PATH (#8) | `infrastructure-patterns.md` |
| launchd/cron watchdog false alerts, "job-not-loaded" but service is up, gateway DOWN alert spam, bootstrap rc=5, `launchctl list` empty in launchd context, health-check passes interactively but fails on schedule, watchdog restarting a healthy service | launchd-Context Health-Check False Positive (#19) | `infrastructure-patterns.md` |
| serde, deny_unknown_fields, config crash | Serde Config Crash (#10) | `infrastructure-patterns.md` |
| innerHTML, XSS, dangerouslySetInnerHTML | XSS via innerHTML | `infrastructure-patterns.md` |
| JSON-LD, script breakout | JSON-LD Breakout | `infrastructure-patterns.md` |
| **Python SIGABRT / "Abort trap: 6" at finalization, parent `sshd-session`, `_enter_buffered_busy`, `Py_Finalize`/`_io_TextIOWrapper_close` in the stack, a Thread blocked in `read()`, recurring `Python-*.ips`, "crash over SSH", MCP bridge/server crashes on disconnect, cross-device `ssh host python …`, crash survives swapping the python interpreter** | Python finalization SIGABRT over SSH — daemon-thread-blocked-in-read SCRIPT bug, usually a cross-device MCP stdio server (NOT the interpreter; NOT scheduled — on-demand). Forensic capture via `~/.zshenv` SSH-cmd logger + WatchPaths crash-watcher correlated by **parentPid**. Fix: run the MCP server locally where the resource lives + `os._exit(0)` after the work loop (#22) | `infrastructure-patterns.md` |
| cannot find module, postinstall, npm install broke, every update breaks | File Extension Mismatch / Broken Postinstall (#17/#18) | `infrastructure-patterns.md` |
| npm-cli.js, shell script, SyntaxError unexpected string | npm-cli.js Shell Script Corruption (#17) | `infrastructure-patterns.md` |
| installing deps one by one, each reveals another missing | Non-Fatal Postinstall Cascade (#18) | `infrastructure-patterns.md` |
| stale data, admin user sync, visibilitychange | Data Stale Admin/User (#16) | `debugging-discipline.md` |
| slow page, slow route, slow dashboard, 8M rows, COUNT(*) on every request, full table scan, why is X so slow, route reads wrong cache, cron warms wrong KV key, prewarm warms wrong thing, 24h/last-N window empty, lagged data source, requested_datetime lag | Hot-Path Data-Volume & Cache-Topology (#20) | `debugging-discipline.md` |
| systematic, 4-phase, root cause, discipline | Debugging Discipline | `debugging-discipline.md` |
| lint, biome, npm audit, security cleanup | Lint & Security Cleanup | `debugging-discipline.md` |
| **Workers Cache leak / wrong data after enabling `cache.enabled`** — user A sees user B's data, authed JSON route returns someone else's response, `cf-cache-status: HIT` on a per-user route, stale per-user data exactly ~2h old, data leak after enabling the new CF Workers Cache, cache flag "not doing anything" (wrangler <4.69 silently ignores it), `Unexpected fields found in top-level field: "cache"` | Workers Cache heuristic-caching cross-user leak — a 200 with NO Cache-Control is heuristically cached 2h; cookie auth (Clerk `__session`) does NOT auto-bypass. Fix: fail-safe default `private, no-store` + explicit `public` opt-ins; verify with `~/.claude/skills/ship/tools/workers-cache-check.sh <repo>` + live `curl -sI \| grep -i cf-cache-status`. Wrangler must be ≥4.69 in the repo's node_modules or the flag is inert. | `~/.claude/skills/shared/workers-cache-safety.md` |
| **Sitewide redirect loop / site down right after enabling Workers Cache** — `ERR_TOO_MANY_REDIRECTS`, every path 301s to its own URL, all UAs affected, `Location:` equals the requested URL, 301s explode in zone analytics right after a cache-enable deploy, HSTS header disappeared, worker logs show `http://` in `request.url` while `cf-visitor` says `{"scheme":"https"}`, "I disabled the flag and it didn't fix it" (checked within seconds) | Workers Cache **scheme-presentation** class (2026-07-06 exampleapp ~25-min outage): the cache front-layer hands the Worker `http://` for HTTPS visitors → any `url.protocol === "http:"` canonicalize middleware 301-loops the whole site, and `url.protocol === "https:"`-gated HSTS silently never fires. **Diagnose in ONE probe**: `wrangler tail --format json` → `event.request.url` scheme for a live HTTPS request. **Fix**: derive the client scheme from `cf-visitor` (authoritative) — `visitorIsHttps()` pattern, AIVA `src/worker/middleware/securityHeaders.ts`; `url.protocol` only as local-dev fallback. **Triage rules**: disable/rollback propagates in >30s — a <60s check is NOT evidence (a 3s check false-negatived during the incident and caused an unneeded rollback; verify over ≥60s); zone SSL mode, Page Rules, and Config Rules are red herrings (the presentation comes from the cache layer itself). | `~/.claude/skills/shared/workers-cache-safety.md` |
| error too vague to act on, ambiguous error message, "can't tell what failed", same error fires 100s of times, log noise / superfluous log entries, no log at the failure point, silent failure, "why are these errors so unclear", add debug attributes, clean up the logs, assess the logs, improve log output | Observability / Log Hygiene — make ambiguous errors actionable (what was attempted + actual values + likely cause/branch + disambiguation: a vague error is usually two root causes sharing one string — split them), reduce noise by *downgrading* level (never delete), add the one attribute that names the failure. For a **proactive scheduled** pass over a window of logs, use the `/log-hygiene` skill instead. | `~/.claude/skills/shared/observability-instrumentation.md` (+ `/log-hygiene` skill) |

All reference files are in `~/.claude/skills/debug/references/`.

---

## Reference Files Index

| File | Content |
|------|---------|
| `error-handling-patterns.md` | Catch-all masking (#1), external municipal form hard-500 (#15), CI false positives (#11), admin auth DB fallback (#14), admin 500 vs 403 |
| `react-patterns.md` | Scope bug (#2), silent startup (#3), useEffect abuse (#15), localStorage persistence (#13), async double-click, missing auth guard |
| `~/.claude/skills/shared/undefined-null-render-safety.md` | **Undefined/null-render bug class** — 9 patterns (null-gate hides UI, unguarded property access, `.map`/string/`Date` on possibly-undefined, JSON.parse, raw-undefined render, missing loading/empty states, backend omits a field) + live DOM grep for rendered `undefined`/`NaN`/`[object Object]`. Cross-refs the admin blind-spot class (truncation, NULL-aggregate sort, count mismatch, inner-JOIN drop, admin-auth DB fallback). Reference incident: AIVA admin "Test account" toggle hidden by an `isTest !== null` gate (2026-06-01) |
| `~/.claude/skills/shared/anti-slop-typescript.md` | **Anti-slop TypeScript** — ban generic `isRecord`/`isObject` guards, `as unknown as T` launder-casts, `(x as any).field` reach-casts; require named types / discriminated unions / Zod schemas (`z.infer`) at trust boundaries; targeted predicate only as last resort. Detector: `~/.claude/skills/carmack/tools/detect-ts-slop.sh`. |
| `css-layout-patterns.md` | Text overflow flex+grid (#12), fixed grid mobile, iOS Safari rendering (PDF, vh, fixed) |
| `csp-cache-patterns.md` | Social card cache (#5), CSP multi-layer blocking (#9), www redirect (#4), deploy chunk invalidation, CF Pages stale deploy |
| `infrastructure-patterns.md` | Infra destruction (#6), Rust cross-platform lint (#7), Homebrew keg-only (#8), serde config crash (#10), XSS innerHTML, JSON-LD breakout |
| `debugging-discipline.md` | 4-phase workflow, diagnostic checklist (23 items), lint/security cleanup, data stale admin/user (#16), hot-path data-volume & cache-topology (#20) |
| `~/.claude/skills/shared/observability-instrumentation.md` | **Observability / log hygiene**: 4-part actionable error-message design, boundary/decision-point logging, downgrade-noise-never-delete, instrument-on-fix attribute heuristic, stack log sources. Proactive scheduled counterpart: `/log-hygiene` skill. |
| `~/.claude/skills/shared/ant-verification-protocol.md` | **Ant-level quality gates**: OWASP sweep, truthfulness protocol, closed-loop verification |

---

## Cookie extraction (curl / yt-dlp / scrape with logged-in session)

When you need browser cookies for a non-browser tool (curl `--cookie`, yt-dlp `--cookies`, requests `cookies={}`, scrapers, n8n nodes), pick by where the live session is:

| Where the session is | Best tool | Why |
|---|---|---|
| Live REAL Chrome (fcdp-driven) | **`~/tools/fcdp/fcdp raw Network.getCookies '{"urls":[…]}'`** | Includes session-only cookies not yet flushed to SQLite; no Keychain prompt; aligned with `/feedback_browser_default_chrome_profile`. |
| Regular Chrome profile (`~/Library/Application Support/Google/Chrome/Default`) | **`~/tools/cookies-txt <url>`** | Reads SQLite + macOS Keychain. Works headless / from cron / without :9222 attached. Outputs Netscape, JSON, or `Cookie:` header. |
| Brave / Edge / Chromium | `~/tools/cookies-txt --browser brave \| edge \| chromium <url>` | Same code, different Keychain entry. |
| One-shot, don't care about reuse | `yt-dlp --cookies-from-browser chrome:Default <url>` | Already installed; bypasses the question entirely if all you need is yt-dlp. |

**`~/tools/cookies-txt` reference** (ported from the "Get cookies.txt LOCALLY" Chrome extension, source at `~/re/cookies-txt-locally/`):

```bash
cookies-txt github.com                            # Netscape → stdout
cookies-txt github.com -o /tmp/cookies.txt        # → file
cookies-txt --all -f json                         # every cookie, JSON
cookies-txt example.com -f header                 # "name=value; name=value;"
cookies-txt --browser brave --profile "Profile 1" foo.com
```

Exit codes: `0` ok, `3` no DB at expected path, `4` Keychain entry missing/denied, `5` decrypt failure.

**chrome-devtools MCP path** for the `:9222` Chrome — request CDP `Network.getCookies` with `{urls: ["https://github.com"]}`; format the returned cookie array with the same Netscape mapper the extension uses (`<domain>\t<TRUE/FALSE includeSubDomain>\t<path>\t<TRUE/FALSE secure>\t<expiry>\t<name>\t<value>`).

**Don't use `unbrowse` / `agent-browser`** for cookie extraction — those launch separate browser instances with no logged-in state.

---

## Quick Diagnostic Checklist

When debugging any production error, check in order:

1. Is the error message accurate? (catch-all masking?)
2. Check runtime logs: `wrangler tail` or Cloudflare dashboard
3. Reproduce locally with same endpoint + token
4. Check external services (Clerk/Stripe/DB responding?)
5. Check env vars in deployment environment
6. Check www redirect (losing cookies?)
7. Check third-party IDs (stale template/product IDs?)
8. Check CSP (all six directives for embeds?)
9. Text overflow on mobile? (`min-w-0` missing, `grid-cols-2` without `sm:`)
10. Preference not persisting? (localStorage writer without App.tsx reader)
11. "Cannot find module" after every update? Run `file <path>.js` — may be a shell script (#17)
12. Installing missing deps one-by-one, each reveals another? STOP — postinstall is broken (#18)
13. External city form 500 after category change? Probe the failing category and a known-good category through the same first-party save path before blaming auth/photo.
14. Production auth configured? Verify Worker dry-run bindings and live HTML do not expose `pk_test`, `sk_test`, or `.accounts.dev`.
15. Live artifact matches production? Fetch cache-busted HTML and CSP headers; compare live response, not only local `dist`.
16. Worker secrets correct? Sensitive bindings must appear as `secret_text` from `wrangler secret list`; no key/token/password literal should remain in `wrangler.json` `vars`.
17. `wrangler secret put` says binding already exists? Remove the plaintext var from config, deploy without `--keep-vars`, put the secret, and re-list secrets before trusting it.
18. AIVA deployed? Verify `clerk.example.com` is present, `prime-rhino-99`/`.clerk.accounts.dev`/`pk_test`/`sk_test` are absent, and `npm run test:integration:prod` passes if available.
19. **Page/route slow?** (a) Enumerate every query that runs *before the response* — measure each `COUNT(*)`/`SUM(CASE...)`/whole-partition aggregate with `wrangler d1 execute --json` → `meta.rows_read`; >~100k rows on a per-request path = the bug. (b) Does it read a cache? Then `grep` for who *writes* that exact key — if nothing does (or only a manual script, no cron), it's a permanent MISS. (c) Cron warming a cache? `grep` for who *reads* those keys — a warmer that warms keys nothing reads (or a different key-shape than the route reads) is the bug. (d) `WHERE ts >= now() - N` against a lagged source returns empty — anchor on `MAX(ts)`. See Pattern #20.
20. **Third-party submit reported as failed but the agency received it?** (DBI complaint flow, Verint dform save, OAuth callback, any webhook receiver, any reverse-engineered API replay.) Run `ls src/__fixtures__/<integration>/ 2>/dev/null`. If there is no `*-success.*` AND `*-failure.*` pair captured from the LIVE system, you cannot trust the detector — the test suite is asserting against fiction. Write `tools/repro/<integration>-probe.{sh,mjs}`, run it once for a known-good and a known-bad request, save both responses, then diff them to find the actual distinguishing feature (anchored DOM id / JSON field, NOT a substring that appears in both). Don't ship detector code without real fixtures. See Pattern #23 + `~/.claude/skills/shared/third-party-signal-fixtures.md`. Reference incident (2026-05-27): every IBA-submitted DBI complaint was reported as `validation` error for ~10 days while the city actually recorded every one of them — synthetic test fixture (`<html><body><h1>Thank you</h1>...`) didn't contain the form layout strings (`Sub_Button0`, `CheckBox1`) that the real DBI success page does contain, so the detector's `looksLikeEchoedForm` heuristic was never exercised against reality.

21. **Error too vague to act on, firing repeatedly, or no log at the failure point?** Don't just patch this one instance — make the message actionable (what was attempted + actual values + likely cause/branch + disambiguation; a vague error is usually two root causes sharing one string), add the one attribute that would have named the failure, and *downgrade* noisy lines rather than deleting them. Standard: `~/.claude/skills/shared/observability-instrumentation.md`. For a scheduled sweep over a window of logs, use the `/log-hygiene` skill.

For the full checklist, load `debugging-discipline.md`.

---

## Hard Rules

### Deployment Prohibition (MANDATORY)

`/debug` is for investigation, local reproduction, local/reviewable fixes, and verification only. Production release authority belongs to `/ship`, not this skill.

NEVER deploy, promote, release, or mutate production traffic while operating under `/debug`, even if the user also mentions "ship", "prod", "deploy", "push live", or "fix and deploy" in the same request. Do not run production deployment commands and do not invoke `/ship` autonomously.

Forbidden examples include `wrangler deploy`, `wrangler versions deploy`, `wrangler pages deploy`, `npm run deploy`, `pnpm deploy`, `vercel deploy --prod`, `netlify deploy --prod`, `firebase deploy`, `fly deploy`, `railway up`, `render deploy`, Docker image push/promote commands, production migration/apply commands, and any Cloudflare/Vercel/GitHub release promotion that changes live traffic.

Allowed under `/debug`: inspect logs, reproduce failures, patch locally, run bounded tests, and commit changes if the user asked for code changes and git safety checks pass. After implementing a fix, STOP and tell the user: "Fix is committed and ready. Run `/ship` to deploy to production." If the user wants production deployment, they must invoke `/ship` explicitly in a separate step.

### Installed-Source Ground-Truth Guard (MANDATORY — 2026-06-12)

Before proposing any fix that touches a dependency/plugin/framework/third-party widget, load `~/.claude/skills/shared/installed-source-ground-truth.md` and follow it: read the installed package's types+JSDoc in `node_modules/` for real option semantics, read the native platform implementation when platform support matters, and probe the live DOM/traffic for third-party widgets. Cite file+symbol in the fix. (2026-06-12: three CSS workarounds failed against the Brevo widget; the real fix — StatusBar `overlaysWebView:false` on iOS — was found by reading the installed plugin's Swift source.)

### Test Safety (CRITICAL)

Vitest fork workers leak ~5GB memory each when they hang:
1. ALWAYS wrap test commands: `timeout 120 npx vitest run src/specific/test.ts 2>&1`
2. NEVER run full test suite (`npm test`, `npx vitest run` with no args)
3. Maximum 3 test runs per investigation phase
4. Clean up: `pgrep -f vitest | xargs kill 2>/dev/null`

### Infrastructure Safety

- NEVER execute `terraform destroy`, `terraform apply -auto-approve`, `DROP TABLE/DATABASE`, or cloud CLI delete/terminate commands
- NEVER modify .tfstate files
- ALWAYS show `terraform plan` output and get approval before any `apply`

---

## Instructions

When this skill is invoked:

1. Parse the user's symptom or pattern name against the **Pattern Routing** table above
2. Read ONLY the matching reference file from `~/.claude/skills/debug/references/`
3. **Load `~/.claude/skills/shared/ant-verification-protocol.md`** and apply:
   - Truthfulness Protocol (Section 2): never guess root causes — gather evidence first
   - Closed-Loop Verification (Section 3): reproduce failure BEFORE and AFTER fix
   - Security Review Gate (Section 1): if symptom touches auth/input/data handling
4. Show the relevant pattern section to the user
5. If the symptom doesn't match any pattern, show the **Quick Diagnostic Checklist** and recommend `/carmack` for deep investigation
6. If a fix is needed, follow the 4-phase debugging discipline (load `debugging-discipline.md`)
7. After any fix: run lint + security cleanup (load `debugging-discipline.md` for the commands)
8. **Ant verification**: never say "fixed" without running the verification checklist from Section 2

```
Load the matching reference file and show the relevant pattern.
If the issue needs deep investigation beyond known patterns, recommend /carmack.
CRITICAL: Do NOT deploy, promote, release, or invoke /ship from /debug. Production shipping belongs only to /ship, invoked separately by the user.
```


## Non-interactive / remote PATH false-negatives (ssh · launchd · cron · Hermes) — MANDATORY (2026-06-19)

`ssh host 'cmd'` (BatchMode), launchd agents, and cron run with a **bare PATH** that excludes
Homebrew (`/opt/homebrew/bin`) and `~/.local/bin`. The failures below are NOT real — they are PATH:

- `ssh host 'which node'` / `which hermes` / `which brew` → "not found" even when installed
  (`/opt/homebrew/bin/node`, `~/.local/bin/hermes`). **Probe explicit absolute paths**; never
  conclude "not installed" from `which` in a non-interactive shell.
- A tool invoked by launchd/cron dies with "command not found" → **pin the absolute interpreter
  path** in the shim/plist (`/opt/homebrew/bin/node script.mjs`) and set `PATH` in the plist
  `EnvironmentVariables`. A `#!/usr/bin/env node` shebang fails under launchd.
- Verifying a remote agent job: `ssh host 'PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH <tool> ...'`
  — a plain `ssh host '<tool> ...'` false-negatives ("NO-JOB" when the job exists).
- Remote **zsh aborts the whole `ssh 'script'`** on an unmatched glob (`/path/*/bin`) — quote globs
  or wrap in `bash -lc`.

Reference incident (caltrans-pra → mac-mini): `ssh mac-mini 'which node'` said "not found" (node was
`/opt/homebrew/bin/node v26`); `hermes cron list | grep caltrans` said NO-JOB (hermes at
`~/.local/bin`, off the BatchMode PATH) — the job WAS registered. Both were PATH false-negatives,
not missing artifacts. Verify on the runner via the **real invocation path**, with an explicit PATH.
