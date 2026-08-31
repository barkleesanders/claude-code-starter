---
name: debug
user-invocable: true
description: "Quick debugging patterns and known production failure traps, including passkey, TOTP/2FA, passwordless-account, session-freshness, reauthentication, and recovery-code failures. Use for common production and account-security issues."
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Skill
model: inherit
---

# /debug - Debugging Quick Reference

Fast reference for known production failure patterns. For deep debugging, use `/carmack`.

## Mandatory upstream-protocol check (third-party integrations)

When the symptom involves a third-party integration falling back to a worse path (handoff, redirect, "manual step required") — Verint dform, Clerk, Stripe, SeeClickFix, OAuth, any SaaS — load `~/.claude/skills/shared/upstream-protocol-investigation.md` BEFORE proposing a fix. Read the upstream's primary client source, capture real network traffic, inspect rendered `data-*` attributes. Treat any "Verified YYYY-MM-DD" comment in our codebase as a hypothesis to re-verify, not a fact. Token cost is unlimited for this; user explicitly authorized it (2026-05-09 SF311 graffiti incident: bandaid `0b746a4` → real fix `f27d1e3` after reading dform's `api.js` lines 462–520).

## DocuSeal template-vs-submission gate

When a DocuSeal form is missing fixed business values, load
`~/.claude/skills/shared/docuseal-template-contract.md`. Prove whether the signer
used a unique submission URL or the template shared link; inspect both the live
submission and live template because mocked payload tests cannot detect template
default drift. For multi-party templates, a public shared link is unsafe unless
party ownership is explicit; AIVA's HIPAA template must keep it disabled.
`/debug` remains read-only for production state.

## Mutating symptom across fixes = wrong premise (MANDATORY — 2026-05-19)

When each fix makes the symptom *change* instead of *disappear* — `fetch_error` → `handshake_rejected` → `publicid_timeout`, every "fix" peeling back to reveal a new failure one layer deeper — STOP. That staircase is the tell that the whole feature premise is wrong, not that you are three fixes from done. Before fixing layer N+1, verify the premise itself: does the real client even use this code path? Capture live traffic and confirm. Reference incident: the SF311 cable chain — four green-tested fixes (`wss://`→`https://`, missing `Origin` header, subscription identifier, publicId timeout) each surfaced the next layer; a live mitm capture then proved the real app never opens the WebSocket at all — the whole path was dead code. Many round-trips of "fix the next layer" should have been one round-trip of "verify the premise."

## Recurring symptom after a DOCUMENTED remediation = the runbook's causal model is wrong (MANDATORY — 2026-08-03)

The third sibling of the two rules above. Mutating error = wrong premise. Static
error = missing discriminator (#32). **A symptom that keeps COMING BACK on a
schedule, after you keep applying the documented fix, = the runbook is wrong
about what causes it.**

The trap is that the remediation *appears* to work every time. It restores
service, so it never reads as a failed fix — it reads as an unlucky recurrence.
That is what lets a wrong causal model survive N repetitions. **Executing a
runbook is not debugging, and "the alert told me to" is not a diagnosis.**

**Tripwire — fires on the SECOND repetition, not the fifth:** if a documented
remediation has been applied ≥2 times and the symptom returned, stop executing
it and ask the two questions that the runbook is silently answering for you:

1. **What actually MINTS the thing I keep replacing, and does my system ever
   call it?** Replacing an artifact is not the same as participating in its
   lifecycle. If nothing in your code ever calls the issuer, you are refilling a
   bucket with a hole and the interval between refills is the hole's size.
2. **Measure the true survival time, don't inherit the folklore number.** Time
   the interval yourself; the remembered figure is usually the longest one
   anyone noticed, and the real number is a much sharper clue.

**Reference incident (2026-08-03, AIVA Google Voice).** An alert said "session
expired — reseed the cookies," with a copy-paste command. It was followed three
times in 18 hours. Each reseed restored SMS, so each expiry read as bad luck.
The runbook was wrong: `__Secure-1PSIDTS`/`__Secure-3PSIDTS` are minted ONLY by
`accounts.google.com/RotateCookies` on a ~600s cadence and gate every RPC, while
the Worker talked only to `clients6.google.com`, which never returns them.
Nothing in the system ever called the issuer, so reseeding could never have
fixed it — it just restarted the same clock. The cookie-refresh code was present
and correct; it simply had nothing to persist. Question 2 mattered too: the
folklore said "about an hour," but timing it gave **~20 minutes** (21:51 ok →
22:11 alerted), which matches the 600s rotation cadence and pointed straight at
the mechanism. Fix = call the issuer on the cadence it declares.

**Corollary — "SAPISID present=true" class of false-healthy signal.** The alert
reported the long-lived credential as present while the short-lived one that
actually gates access had already expired. When a health line reports a
credential/resource as OK during a confirmed outage, check whether it is
reporting a *different-lifetime* component than the one that fails. Enumerate
the credential set by lifetime before trusting any "present=true".

**PREMISE-CHECK GATE — run BEFORE the first fix (not just on the staircase). Full rule: `~/.claude/skills/shared/premise-check.md`.** Two questions, answered against LIVE upstream docs (not a cached `/skill` note): (1) **Is this approach even valid for THIS runtime/SDK/platform?** The browser SDK ≠ native SDK ≠ server SDK — a strategy/option/API documented under one is routinely absent or *forbidden* in another. If every doc/example for the thing you want sits under a *different* platform than yours, that's your answer — stop. (2) **What's the cheapest probe** (curl the API / grep the installed bundle / read the doc's "supported platforms" line) that proves it's possible here? Run it before coding. **Docs-before-note (always):** a `/skill` recipe, comment, memory, or prior conclusion is a HYPOTHESIS — re-verify any load-bearing "API/SDK can/can't do X" claim against the upstream's own *current* docs/source before building on it; live source wins, fix the stale note in the same pass. **2026-06-13 reference incident:** hours spent debugging Clerk native `oauth_token_apple` from a Capacitor webview — clerk-js (browser SDK) can never send it (browser-forced `Origin` vs Clerk Native-API `Authorization` conflict), a fact Clerk's docs state plainly under "Expo only." A wrong `/ios` trap-#4 note was trusted as fact; the working web-OAuth fix was a 5-minute live-doc read away. Now also enforced session-wide by the `premise-check-session-start.sh` SessionStart hook.

## "Every subset passes" / "it looks intermittent" = your manipulation never applied (MANDATORY — 2026-08-25)

The fourth sibling of the three rules above. Mutating error = wrong premise.
Static error = missing discriminator (#32). Recurring-after-remediation = wrong
runbook. **Every arm passing, no single change reproducing it, and a growing urge
to call the bug "intermittent" = the change you think you applied never reached
the system, and you are A/B-ing A against A.**

A deterministic bug measured through a no-op'd manipulation *presents exactly as
flakiness*, because you are re-sampling one unchanged condition. So **"it's
intermittent" is a claim requiring evidence**, not a fallback explanation.

**Tripwire — before writing the word "intermittent", and before any bisect round
2:** name an observable that MUST differ between arms, read it back after each
apply, and abort the run if the arms look identical. Not "the apply exited 0" —
an observable in the running system.

**Reference incident (2026-08-25, SmartTube 403).** Bisected 21 profile files to
find which setting 403'd every video stream. Every subset passed; the full set
failed once then passed twice; I concluded "the PoToken mint is intermittent, not
a config bug" and posted it publicly. It was one deterministic line
(`preferred_dns_type=2` → Google DoH resolver). The app's own *Auto backup*
rewrote the staged fixture on every launch, so each "restore" was a silent no-op
and every run tested a fresh profile — and I had suppressed the restore step's
output, so nothing surfaced it. One post-restore read of the sidebar order
(custom vs default) would have caught it on run 1. With the fixture-rewriter
disabled and each restore verified, the bisect converged in **three rounds**.

Full gate + instrument-trap table: `~/.claude/skills/shared/experiment-manipulation-check.md`.

## Route-coverage bugs: get the site's route list before you sample (2026-07-31)

When the symptom is **about which pages/endpoints exist or work** — "page X 404s in prod",
"some routes broke after the deploy", "the new pages aren't live", "search can't find our
docs" — do NOT debug from the handful of URLs you happened to click. Get the declared
inventory first, then diff it against reality:

```bash
curl -sL https://<host>/robots.txt | grep -i sitemap
curl -sL https://<host>/sitemap.xml | grep -o '<loc>[^<]*' | sed 's|<loc>||' > /tmp/declared.txt
# now diff DECLARED against DEPLOYED — the bug is usually in the gap
while read -r u; do printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -m 10 "$u")" "$u"; done < /tmp/declared.txt | grep -v '^200'
```

For an **API**, the analog is the published spec (`/openapi.json`, `/swagger.json`,
`/api-docs`, GraphQL introspection, or `unbrowse_eval_spec_discover`) — not a sitemap.

This is the **"Compared to What?"** rule applied to debugging: a sampled set of working
URLs is a delta, the declared route list is the denominator. Two failures it prevents:
declaring "routes are fine" after checking the three you remembered, and declaring "page X
doesn't exist" when it exists but 404s (a very different bug).

Distinct from the security-baseline check below, where a **missing** `sitemap.xml` is itself
the finding (#16). Here the sitemap is the *instrument*, not the defect.

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
| run something on the mini, mac-mini, the cron host, remote Mac, "check the mini", Hermes cron, ssh to the mini, Screen Sharing, why does X work on my laptop but not the mini | **remote-mini** | `~/.claude/skills/shared/mac-mini-remote-control.md` — the 6-surface ladder (ssh -> scp -> hermes cron -> launchctl -> fcdp -> Screen Sharing). Climb it; don't start at the GUI. Covers the context traps that make a working tool look broken over SSH (Keychain/`cookies-txt`, `open -a` -600, `osascript` 1002), the nested-heredoc credential hazard (write locally + `scp`), zsh not word-splitting, `hermes cron create` taking a POSITIONAL schedule + bare script filename, and which Chrome profile you actually hit (integer tab id = real Default, hex = headless :9222). |
| catch-all, generic error, wrong status code, misleading error | Catch-All Error Masking (#1) | `error-handling-patterns.md` |
| my edit didn't take, reposted/resubmitted with the OLD value, stale photo filed, repost reuses previous photo/category, edited field reverted silently, user's new value replaced by the default, "it saved but used the old one", no error shown | **Implicit precedence — N sources, one winner (#37)** — a collection filled from 2+ sources and consumed at `[0]`/`.find()`; append order picks the winner and nothing declares it. Every gate is green because order is not a type. Run `~/.claude/skills/shared/tools/single-winner-merge-check.sh <repo>`. **Date the mechanism before blaming the latest deploy** (`git log -L`/`-S`): introduced and became-reachable are usually months apart and different commits. | `error-handling-patterns.md` (Pattern 37) |
| SF311 save 500, Verint save 500, Improve AI resubmit, category changed 500, request_type_id 500 | External Municipal Form Category Hard-500 (#15) | `error-handling-patterns.md` |
| ticket description truncated, navFooter dropped, map links missing, address missing on filed ticket, description ends abruptly, external form truncation, Verint dform Request_description, bracket truncation, square bracket strip | External Form Description Truncation by Character (#19) | `error-handling-patterns.md` |
| 311 ticket missing Location box, Open311 address null, mobile311 viewer shows description but no Location dt/dd, "one ticket has location another doesn't", sf_full_address dropped, Location_description ignored, structured location empty, lat/long null in Open311, address only in description body not the actual location field, scf location_details, address forwarding broken, coord-string in structured slot, "hardening 311 address forwarding", multi-city address never break | 311 Structured-Location Dropped by Long-Form / Coord-String Address (#21, backend-agnostic) | `error-handling-patterns.md` |
| MyLA311, myla311.lacity.gov, C-04342632, caseAddress blank, ", , CA.", locator_gis_returned_address missing, All Service Requests vs My Requests, data.lacity.org 2026 2cy6-i7zn, Street_Address__c, addressDetails, LA_AddressController.validateAddress, toastPayload NPE, empty objCaseConfigWrapper, captureFailure, dummy modelFlags, Permit_Number__c, Receptacle_ID__c, fetchCaseTypeDetails, remint IssueTypeId, listed types not fileable, invalid_csrf guest mint | Experience Cloud catalog-and-submit envelope (#36) — listed ≠ fileable; SUCCESS-empty = captureFailure; unwrap toast/`objCaseConfigWrapper`; remint IDs; classify on field API names; named refuse; Apex NPE ≠ city rejection | `error-handling-patterns.md` |
| DBI complaint reported as validation but city has it, "DBI re-rendered the form (validation rejected the submission)" but DataSF shows the case, third-party form rejected but actually recorded, form echoed back on success, parser says failure but the agency received it, external form 200 OK we classified as failure, complaintNumber undefined but submission worked, dform/Verint/aspx false-negative on success, success-detection heuristic matches both success AND failure pages, lblError success vs failure span, signal-extraction tests use synthetic HTML, every IBA-submitted DBI complaint fails | Third-party signal-extractor false-negative due to synthetic fixtures (#23) | `error-handling-patterns.md` + `~/.claude/skills/shared/third-party-signal-fixtures.md` |
| CI false positive, grep wrong, CI still fails | CI False Positives (#11) | `error-handling-patterns.md` |
| admin 403, requireAdmin, metadata-only | Admin Auth Missing DB Fallback (#14) | `error-handling-patterns.md` |
| admin 500 instead of 403 | Admin Route Wrong Status | `error-handling-patterns.md` |
| passkey, WebAuthn, TOTP, 2FA, passwordless, social login, email OTP, `SESSION_NOT_FRESH`, recovery codes, security setup, reauthentication, alternate login bypass, "is 2FA enabled", "does the site require 2FA" | Account-Security Lifecycle — separate enrollment, challenge enforcement, enrollment policy, and recovery; inspect the installed SDK; verify authoritative state without reading secrets | `~/.claude/skills/shared/account-security-lifecycle.md` |
| consent recorded wrong, checkbox says checked but DB says declined, opt-in not saved, consent checkbox does nothing, TCPA/GDPR/HIPAA proof-of-consent missing, "we can't prove they agreed", audit trail empty, exhaustive-deps warning on a consent value | **Consent-Evidence Integrity (#35)** — 6 shapes: collected-but-never-persisted (N checkboxes, 1 writer); **stale closure records an opt-IN as a DECLINE** (#26); zod strictness mismatch (non-strict SILENTLY STRIPS the field, `.strict()` 400s the form); `INSERT OR IGNORE` dropping a returning user's consent (consent is an EVENT → append-only store); client-supplied disclosure text (forgeable); affirmatives-only logging. Start by counting collectors vs writers — the mismatch IS the bug. Beware the greps that hide it: case-sensitivity (`smsConsent` misses `contactSmsConsent`) and single-line grep vs formatter-wrapped JSX prose; always pair a probe with a positive control. | `~/.claude/skills/shared/consent-evidence-integrity.md` + `react-patterns.md` (#26) |
| react undefined, scope bug, not defined | React Scope Bug (#2) | `react-patterns.md` |
| **page is blank / client JS never runs / a feature silently stopped, and the BUILD IS GREEN** — `tsc` 0, bundler 0, tests all pass, clean diff; site emits HTML with inline `<script>` from a template literal (CF Worker/SSR); symptom appeared right after a lint auto-fix, a sed/`python3 -c` replace, or an agent editing a comment | **Code Inside A String Is Invisible To Every Compiler** — nothing in your toolchain parses a template literal's contents, so a syntax error there ships with every gate green and fails only in the user's browser. A backtick or `${` in a COMMENT terminates the literal; Biome's `noUselessEscapeInString` is one cause among many. Do NOT grep for patterns — run a cause-agnostic PARSE gate (`new Function(code)` over every inline `<script>` in the RENDERED output; parses without executing). Make it a unit test over the render function so it runs every `vitest`, and prove it fails by re-injecting the corruption. Recipe + the 0-blocks-means-vacuous branch: `~/.claude/skills/ship/references/code-quality.md` Stage 1.7. Reference incident 2026-08-05 improvebayarea: a replace aimed at a comment rewrote real code; tsc/build/dry-run and 56 tests all passed on a bundle whose client script could not parse. | `~/.claude/skills/ship/references/code-quality.md` (Stage 1.7) |

| silent startup, blank page, no console errors, module-level throw | Silent React Startup (#3) | `react-patterns.md` |
| useEffect, renders twice, state lags, derived state | useEffect Abuse (#15) | `react-patterns.md` |
| localStorage, preference lost, resets on refresh | Preference Lost on Reload (#13) | `react-patterns.md` |
| double click, duplicate API call, async button | Async Button Double-Click | `react-patterns.md` |
| chat/support widget gone after SSR, cookie banner missing on SSR page, `?support=open`/deep-link does nothing, global widget vanished after Hono/Astro/RSC conversion, "worked on every page before SSR", floating launcher dead, analytics/exit-intent dropped on SSR route | Global App.tsx Component Vanishes After SPA→SSR Conversion (#24) | `react-patterns.md` |
| invisible text after SSR, white headings on light/gray bg, page background wrong color after conversion, "colors got messed up on conversion", body background overridden, SSR design clobbered by Tailwind/island CSS, text disappeared but HTML is there, computed bg ≠ design token, low contrast only on SSR pages, island/global CSS leaks `body` styles | Bundled Island/Global CSS Clobbers SSR Inline Design — Invisible Text (#25) | `react-patterns.md` |
| auth guard, unauthenticated error, no redirect | Missing Frontend Auth Guard | `react-patterns.md` |
| renders undefined, shows NaN, "Invalid Date", "[object Object]", toggle/section/control disappeared or silently vanished, "make sure nothing is undefined", Cannot read properties of undefined, is not iterable, null-gate hides UI, `useState<T\|null>` gates a render, `.map`/property access on possibly-undefined API data, admin/dashboard renders garbage, optional chaining missing | Undefined / Null-Render Safety (9-pattern catalog + live DOM grep for `undefined`/`NaN`/`[object Object]`) — also re-sweeps the adjacent admin blind-spot class (default-LIMIT truncation, NULL-aggregate sort burial, count-source mismatch, inner-JOIN row drop, admin-auth DB fallback) | `~/.claude/skills/shared/undefined-null-render-safety.md` |
| generic `isRecord`/`isObject` guard, `as unknown as T`, `(x as any).field`, repetitive type-guard boilerplate, "vibe coding" / AI-slop TypeScript, loose `unknown`-everywhere, no schema validation at boundary, `Record<string, unknown>` everywhere, `input as object as User`, missing `// SAFETY:` on a cast, widen-then-assert, `vi.mock` module mocking, "anti-slop findings" / oxlint `anti-slop/*` errors | Anti-Slop TypeScript — replace generic guards/casts with named types, discriminated unions, or Zod (`z.infer`). Enforcers: repo-vendored **dmmulroy/anti-slop Oxlint plugin** (`./node_modules/.bin/oxlint` when `tools/oxlint/anti-slop/` exists; vendor via the `/install-anti-slop` skill) or fallback detector `~/.claude/skills/carmack/tools/detect-ts-slop.sh`. **AUTO-FIX LOOP UNTIL 0**: fix every finding in source by adding evidence (inference, `satisfies`, boundary parsing, genuinely-checked `// SAFETY:` invariant), re-run enforcer + `tsc --noEmit`, repeat to 0; a finding surviving 5 attempts → surface to the user. Never fix by weakening rule severity, `oxlint-disable`, or laundering types | `~/.claude/skills/shared/anti-slop-typescript.md` |
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
| **third-party submit "worked" (200 + id, no error) but the ticket/record never went live — never got a public number, never opened, never associated, `openedAt: null`, `publicId: null`, `submittedTickets: 0`; guest/anonymous create dead-ends silently; A/B-tested a flag/category/field and the symptom stayed IDENTICAL; "why does spotmobile/guest submit never get a case number"; freshly-minted guest token; shadow-limited actor; "is it the payload or something else"** | **False-Positive Success — async lifecycle is the real signal + IDENTITY is the hidden variable (#30)** — a synchronous 200+id is a *pending* state, not *done*; gate success on the lifecycle transition (public number / `opened` / row in public dataset), polled, against a known-good baseline. When fix-A/fix-B/fix-C leave the symptom byte-identical, STOP editing the request — the actor/identity/account you held constant is the variable; re-run the SAME payload under a known-good established identity FIRST. Prove the working backend by RUNNING THE REAL FUNCTION LIVE (repro harness → real id), never from old code or a "Verified" comment. **Fastest confirmer that it's the ACCOUNT, not your code: does the vendor's OWN first-party client (their official app/site) show the SAME stuck symptom under the same identity?** If yes, it's an account/identity-level block (shadow-ban/write-limit) — stop debugging payload/version/token and switch identity or backend. Reference (2026-08-12): Solve SF `/submit` 403'd for improvebayarea AND the official iOS app stalled on "pending" for the same account → account write-block; fix was to abandon the authenticated backend for the account-less Verint public form (nothing to shadow-ban). | `error-handling-patterns.md` (Pattern 30) |
| **async id never resolves / report stuck at "getting case number" forever; a resolver/reconciler/poller cannot find the record OUR OWN system created; matching by category/type/service_name/status returns nothing while the user says the integration "constantly fails"; "did the city/vendor actually receive it?"; authority relabeled our category; outcome counters read all-ok while users see failure** | **The authority relabels your artifact — match on YOUR echoed content, never on labels the authority owns (#39)** — investigation order is MANDATORY: (1) query the AUTHORITY'S OWN record store first (Open311/Socrata/vendor API) around the submit time+place and look for OUR OWN echoed boilerplate in the record body — two curls settle "did it actually happen" before any code is read; (2) fix the matcher to rank fingerprint evidence (our echoed text) above label agreement, and pin the fingerprint to the constant that generates it with a test; (3) THEN audit our measurement path (pending recorded as ok, success_rate defaulting to 100% when unmeasured, give-up branches that can never fire). Instrument traps that fake "the record does not exist": Socrata datasets use LOCAL time while Open311 uses UTC (a 7h miss returns confident empty sets — positive-control every zero); list endpoints silently truncate (Open311 default page_size 50). Reference: 2026-08-26 improvebayarea — 12/12 "stranded" SF refs were REAL filed cases (one already closed by the city) under relabeled service names; a day-old memory asserting "submissions never file" was the tz-blind instrument talking. | `error-handling-patterns.md` (Pattern 39) |
| **a route family shows a high 5xx/error rate but every manual probe returns 200; 522 / 524 / `originResponseStatus: 0`; "origin unreachable" on a Workers-only zone; errors cluster at :00/:02/:30; empty User-Agent; single-colo errors; error count ≈ a fleet size (cities/tenants/shards); "is this users or us?"; an outage nobody can reproduce; a cron/prewarm/warmer/poller/self-health-check is in the picture** | **Your own cron is the caller — ATTRIBUTE before you diagnose (#40).** The first question is **WHO** is making the requests, not why they fail — one `httpRequestsAdaptiveGroups` query grouped by `datetimeMinute` + UA + colo + `cacheStatus` either kills the entire user-facing hypothesis or confirms it, *before* the handler is opened. Self-inflicted signature: clustering at the cron boundary + **empty UA** (Worker subrequests carry none) + one colo + `cacheStatus: bypass` + count ≈ fleet size. Platform fact: **a Worker cannot `fetch()` its own Custom Domain** — CF forwards the same-zone subrequest to the *zone origin*, and a Workers-only zone has none (`AAAA 100::`, RFC 6666 discard) ⇒ 522/origin=0 every time (`workers/configuration/routing/routes`; workerd#787); probe with `curl --resolve host:443:[100::]` → exit 28. Then check the two siblings: a test that **asserts the buggy behavior** (a mocked `fetch` returns 200 and *cannot observe* a platform refusal — it pins the bug and stays green for months), and a warmer that **warms nothing** (`cf-cache-status` still `MISS` an hour after the run). Beware "intermittent" — that is a causal claim needing #38's evidence; here the failures were perfectly periodic and the probes passed only because they never coincided with the cron. Reference: 2026-08-29 improvebayarea — 523/523 of the zone's 522s at :02–:03, ~44/run = 43 cities + `/map/oakland`, 32.5% measured 5xx, zero users affected. | `error-handling-patterns.md` (Pattern 40) |
| **`iba` CLI / improvebayarea.com 311 filing** — "did my 311 ticket actually file", submit returned 200 but no case number, `mobile311.sfgov.org/services/case/<id>` 404s, ticket missing from the recent feed, "the CLI only lists 20 categories", no steam-clean/power-wash category, wrong category filed, `recategorized_from` in the response | **`iba` traps (verified 2026-08-01) — three of the four "it failed" signals are FALSE.** (1) **`--mode prefill` is the DEFAULT and it FILES** — all three modes file; only `--dry-run` doesn't. (2) **ref-vs-caseid:** Verint assigns a public caseid synchronously for *some* forms only. `pw_street_cleaning` → real `101004…`; `pw_graffiti` → `valid:true` + a UUID **ref**, `caseid_pending:true`, and a `lookup_caseid_url` (improvebayarea `src/sf311.ts:1768-1774`, `src/index.ts:5142`). Resolve with `iba lookup <ref>` (takes a **ref**, NOT a caseid — passing a caseid returns `ref_not_found`) or `iba submit --wait <secs>`. (3) **False failure signals:** `mobile311.sfgov.org/services/case/<ref>` **404s by design** for ref-format ids (`src/sf311.ts:1770`) and even 404s for real filed caseids; `/api/recent` is a **narrow 25-item sample** (had zero Graffiti-category rows) so absence ≠ failure — use `?q=<term>`; DataSF `vw6y-z8j6` lags **1-2 days** and is the only real confirmation. (4) **Capture the FULL submit response** — the id is unrecoverable afterward; `iba` now prints a SUBMIT RESULT banner on **stderr** so `\| head` can't destroy it. (5) **Registry drift:** the baked category map silently ran 20-of-42 — run `iba categories --check` (diffs vs the live API, exit 1 on drift) before trusting it; `--live [--city oakland]` for the authoritative list. No steam-clean/power-wash category exists — do NOT force it into `missed_street_cleaning` (920010 = "the sweeper skipped my route"). | `~/.claude/projects/-Users-<you>/memory/reference_local_tools.md` + `error-handling-patterns.md` (Pattern 30) |
| **"the deploy broke prod", `Failed to load module script ... MIME type "text/html"`, SPA won't mount after deploy, only SEO fallback text renders, `ERR_BLOCKED_BY_CLIENT`, page worked 5 min ago, verifying a deploy in a clone browser** | **Your Verification Browser Is Stale — False "Prod Is Broken" (#28)** — a cached HTML shell references pre-deploy asset hashes; the SPA fallback serves `index.html` for the missing `.js`; the browser refuses HTML as a module script. **Production is fine; only your tab is broken.** NEVER conclude a bad deploy from a browser alone: curl the live HTML for its asset refs, confirm each returns `200 text/javascript` (not `text/html`), and grep the deployed chunk for a string only your new code has. `location.reload(true)` is a no-op; use `navigate_page {ignoreCache:true}` or a cache-busting query param. `ERR_BLOCKED_BY_CLIENT` = ad blocker, not your code. | `csp-cache-patterns.md` (Pattern 28) |
| **`npm install` blocked or behaving oddly**, "Socket npm exiting due to risks", `429 Insufficient quota`, install works with `SOCKET_CLI_ACCEPT_RISKS=1` but not without, deps missing after a "successful" `npm ci`, `Cannot find type definition file for '@cloudflare/workers-types'` right after install, vitest/tsc missing though they're in package.json | **Supply-chain wrapper triage.** Protection is **Socket Firewall `sfw`** — a local network proxy (no API key, no quota), wired via an `npm()` function in `~/.zshrc`/`~/.bashrc` that routes only `install|i|ci|add|update|up|dedupe|rebuild` through `sfw npm`; everything else goes straight to `command npm`. Diagnose: `~/.claude/skills/shared/tools/socket-health-check.sh --live` (0 = armed, 1 = sfw missing → UNPROTECTED, 2 = disarmed, 3 = not configured). **Verify with an observable, not an exit code:** `SFW_VERBOSE=true npm install` must print `Protected by Socket Firewall` — an unprotected fallback also returns 0. ⚠️ A **`429 Insufficient quota`** means something still calls the OLD `socket npm` API path (free plan = 100 units/scan, and it fails closed when exhausted); `sfw` never calls that API. ⚠️ A partial install leaves node_modules half-populated, so the next symptom is a missing type package or test runner — re-run a full install rather than debugging that. **Never** `SOCKET_CLI_ACCEPT_RISKS=1` (blanket disarm; `pre-bash-socket-disarm-guard.sh` blocks persisting it) — use `command npm` for a scoped, visible bypass. | `~/.claude/skills/shared/tools/socket-health-check.sh` |
| dependabot alert, npm audit, CVE, GHSA-xxxx, "vulnerable dependency", transitive vuln, "fix the security/dependabot page", overrides, esbuild/tar/minimatch/ws/vite/uuid vuln, `npm install` fails on override version | Dependency Vulnerability Audit & Fix (7-step: BOTH dependabot-api + per-manifest npm-audit, scan EVERY lockfile, scoped overrides for multi-major packages, verify patched version is published, never blind `npm audit fix --force`, verify build with project's real build) | `~/.claude/skills/shared/dependency-audit.md` |
| www redirect, cookies lost, auth break | WWW Redirect Auth Break (#4) | `csp-cache-patterns.md` |
| deploy logout, chunk hash, preloadError | Deploy Logs Users Out | `csp-cache-patterns.md` |
| stale version, failed deploy, CF Pages | CF Pages Stale Deploy | `csp-cache-patterns.md` |
| terraform destroy, infra deleted, catastrophic | AI Agent Destroys Infra (#6) | `infrastructure-patterns.md` |
| prod auth, pk_test, accounts.dev, Clerk production, Wrangler binding, wrong auth instance | Production Auth Instance Drift (#12) | `infrastructure-patterns.md` |
| AIVA auth drift, retired Clerk fingerprint, `clerk.*`/`pk_live_` still in live HTML or CSP, `/api/auth/ok` fails, wrong-password sign-in returns 500, live artifact differs from dist | AIVA First-Party Better Auth Artifact Drift — old Clerk presence is now the failure, not its absence | `~/.claude/skills/shared/account-security-lifecycle.md` + `infrastructure-patterns.md` |
| wrangler secret put binding already in use, plaintext Worker var, secret_text missing, BREVO_API_KEY in vars | Worker Secret Binding Drift (#12b) | `infrastructure-patterns.md` |
| **D1 route 500s with generic "Internal Server Error", `no such column`/`no such table`, `D1_ERROR`, intake/any-write save fails for everyone, migration file exists but column missing in prod, `wrangler tail` shows outcome Ok + empty exceptions, schema drift, migration not applied to remote** | **D1 Schema Drift — migration-file-exists-but-not-applied-to-prod** (#26). Detect: `wrangler tail --format json` → grep logs for `D1_ERROR`/`no such column` (it's in `logs[]`, not `exceptions[]`); confirm with `PRAGMA table_info(<t>)` on `--remote` (the file/local-D1 are NOT proof). Fix: additive `ALTER … ADD COLUMN`/`CREATE … IF NOT EXISTS` on remote, then `INSERT OR IGNORE` the filename into `d1_migrations` — NEVER bulk `migrations apply` (re-runs non-idempotent data migrations → corruption). Gate: `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>`. | `~/.claude/skills/shared/d1-schema-drift.md` |
| **"the API shows only N records so X is missing", "this cert/record/route is redundant, safe to delete", DNS record missing from the dashboard but working in production, CAA/SPF/DKIM "absent" per the provider API, duplicate certificate packs, orphaned resource nothing seems to reference, "nothing in the repo references this", a config table that disagrees with observed behavior** | **A Management API Is Not Authoritative State (#31)** — the API returns what was DECLARED; it does not show what the platform INJECTED on your behalf, nor WHY a resource exists. Two modes: (a) **false "absent"** — CF `dns_records` returned 5 CAA records with no `issuewild "pki.goog"` while `dig` returned 11 including it (CF auto-injects partner-CA CAA, documented as not appearing in the dashboard) → a phantom outage; (b) **false "redundant"** — 20 "stray" advanced cert packs were Worker custom-domain certs (8 packs ↔ 8 Worker domains; 11 zones with 0 Workers had 0 packs) → deleting them drops TLS on live services. **Probe the CONSUMER view before concluding**: `dig` not `dns_records`; `openssl s_client` not the cert list; the audit log's `actor.type` (`system` = platform-provisioned, something needs it) before calling anything redundant. | `~/.claude/skills/shared/management-api-vs-authoritative-state.md` |
| **same opaque error after a fix you PROVED is deployed, "my fix didn't work" but the error string is byte-identical, `400 {"error":"Invalid"}` / bare `500` / `{"ok":false}` for several unrelated causes, upstream rejects a payload with no field saying WHICH rule broke, fix-probe-fix loop across multiple deploys, "no events in tail" / "the counter didn't move", a health probe green while 100% of writes fail** | **One Opaque Error, N Independent Causes (#32)** — a static (never-changing) error means your INSTRUMENT is too coarse, not that your premise is wrong (contrast the mutating-symptom tripwire above: `errA→errB→errC` = wrong premise; identical error = missing discriminator). **Stop bisecting and ship a discriminator first** — make the failure report the measurable PROPERTIES of what it sent (flags + lengths, never the payload: PII). When every flag reads false and it still fails, you have positively excluded your hypothesis space, which is the finding. Then: bisect by COMPONENT not character, change exactly ONE variable per probe (a confounded step attributes the pass to the wrong cause), and cross-reference successes as hard as failures (the cause is the property in 100% of failures / 0% of successes). If the failure has no side effect, every failing probe is FREE — order expected-fails first and stop at the first success. **Silence is not evidence**: prove the instrument is alive before trusting "nothing logged" (a `wrangler tail` that wrote 0 bytes; `--format json` emitting PRETTY-PRINTED multi-line objects that line-wise grep never matches; KV reads that LAG). | `~/.claude/skills/shared/opaque-multi-cause-failure.md` |
| **a bisect where EVERY subset passes, no single change reproduces the bug, the same config gives PASS then FAIL, you are about to call it "intermittent"/"flaky", a restore/import/apply step that "succeeded" but changed nothing, config-restore or backup-restore debugging, an A/B whose arms you never confirmed differ** | **The Manipulation Silently No-Op'd — You A/B'd A Against A (#38)** — a deterministic bug measured through a no-op'd manipulation presents *exactly* as flakiness. **"Intermittent" is a claim requiring evidence, not a fallback.** Gate 1: name an observable that MUST differ between arms and read it back after each apply (not "the apply exited 0"). Gate 2: the success signal must be direct state or a progression across two samples — never a lagging derived proxy (decoder logs, async counters) or a compositor screenshot (hardware-overlay video screenshots BLACK while playing). Gate 3: >=2 interleaved runs per arm before any causal claim. Gate 4: publish nothing causal until 1-3 pass. Never suppress the output of an apply/restore/deploy step you will draw conclusions from, and disable anything that can rewrite your fixture mid-run. Sibling of #33 (there the check can't fail; here the variable never changed). | `~/.claude/skills/shared/experiment-manipulation-check.md` |
| **"everything is green but users report it's broken", a health check / validator / drift job that has NEVER gone red, "N/N verified", "30 of 30 match", "all healthy", 100% pass rate, a monitor that missed a real outage, about to RETRACT a finding because a different measurement came back clean, a hardcoded `verified:`/`lastChecked:` date on data harvested from an upstream, a record "missing" from an upstream you join by id, a dataset field whose absence degrades silently (`continue`, `?? undefined`, skipped row)** | **A check that cannot fail is not a check (#33)** — the mirror of the Negative-Result Rule: that one runs a *positive* control on a negative result; this runs a **negative** control on a positive one. Feed the instrument a known-bad input (corrupted token, mutated id, nonexistent resource) and require RED. If the known-bad also passes, the instrument is vacuous and every green it ever produced is worthless. Always three outcomes, never two: `ok` / `genuinely bad` / `could not measure`. **Echo is not validation** — an upstream that reflects your value back has not checked it. Corollaries: `verified:` stamps decay (re-ask on a cadence, mark stale past ~2 intervals); check upstream ALIAS keys before concluding absence; silently-degrading dataset fields need a completeness invariant. Reference incident 2026-08-10 nps-report: a probe reported 20/20 park mailboxes healthy while `o=DEADBEEF00` also returned HTTP 200 + a full form; the real sweep found 5 of 435 drifted, and an earlier CORRECT drift finding had been retracted in favour of that vacuous probe. | `~/.claude/skills/shared/negative-control-gate.md` |
| **report/upload attributed to the wrong place or time, "it picked the wrong location", location correct on the phone but wrong on the record, EXIF, geotag, DateTimeOriginal, metadata gone after a resize/optimise/convert, a slow async GPS/lookup overwriting a good value** | **Use the artifact's own provenance, not ambient state (#34)** — derive the attribute from the uploaded artifact (EXIF GPS/timestamp, document date, mail `Date`), not from `navigator.geolocation`/`now()` at processing time. Read provenance from the ORIGINAL bytes BEFORE any re-encode (canvas/optimiser strips metadata) and assert that ordering in a test; funnel every writer through one precedence helper so a late async value can't clobber the artifact's; show the user which source won. Reference incident: reports photographed on a trail and submitted from a hotel routed to the park nearest the hotel — silently, with a plausible park name on screen. | `~/.claude/skills/shared/negative-control-gate.md` (Pattern #34) |
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
| **Sitewide redirect loop / site down right after enabling Workers Cache** — `ERR_TOO_MANY_REDIRECTS`, every path 301s to its own URL, all UAs affected, `Location:` equals the requested URL, 301s explode in zone analytics right after a cache-enable deploy, HSTS header disappeared, worker logs show `http://` in `request.url` while `cf-visitor` says `{"scheme":"https"}`, "I disabled the flag and it didn't fix it" (checked within seconds) | Workers Cache **scheme-presentation** class (2026-07-06 example ~25-min outage): the cache front-layer hands the Worker `http://` for HTTPS visitors → any `url.protocol === "http:"` canonicalize middleware 301-loops the whole site, and `url.protocol === "https:"`-gated HSTS silently never fires. **Diagnose in ONE probe**: `wrangler tail --format json` → `event.request.url` scheme for a live HTTPS request. **Fix**: derive the client scheme from `cf-visitor` (authoritative) — `visitorIsHttps()` pattern, AIVA `src/worker/middleware/securityHeaders.ts`; `url.protocol` only as local-dev fallback. **Triage rules**: disable/rollback propagates in >30s — a <60s check is NOT evidence (a 3s check false-negatived during the incident and caused an unneeded rollback; verify over ≥60s); zone SSL mode, Page Rules, and Config Rules are red herrings (the presentation comes from the cache layer itself). | `~/.claude/skills/shared/workers-cache-safety.md` |
| error too vague to act on, ambiguous error message, "can't tell what failed", same error fires 100s of times, log noise / superfluous log entries, no log at the failure point, silent failure, "why are these errors so unclear", add debug attributes, clean up the logs, assess the logs, improve log output | Observability / Log Hygiene — make ambiguous errors actionable (what was attempted + actual values + likely cause/branch + disambiguation: a vague error is usually two root causes sharing one string — split them), reduce noise by *downgrading* level (never delete), add the one attribute that names the failure. For a **proactive scheduled** pass over a window of logs, use the `/log-hygiene` skill instead. | `~/.claude/skills/shared/observability-instrumentation.md` (+ `/log-hygiene` skill) |

All reference files are in `~/.claude/skills/debug/references/`.

---

## Reference Files Index

| File | Content |
|------|---------|
| `error-handling-patterns.md` | Catch-all masking (#1), external municipal form hard-500 (#15), CI false positives (#11), admin auth DB fallback (#14), admin 500 vs 403, Experience Cloud catalog-and-submit (#36) |
| `react-patterns.md` | Scope bug (#2), silent startup (#3), useEffect abuse (#15), localStorage persistence (#13), async double-click, missing auth guard |
| `~/.claude/skills/shared/undefined-null-render-safety.md` | **Undefined/null-render bug class** — 9 patterns (null-gate hides UI, unguarded property access, `.map`/string/`Date` on possibly-undefined, JSON.parse, raw-undefined render, missing loading/empty states, backend omits a field) + live DOM grep for rendered `undefined`/`NaN`/`[object Object]`. Cross-refs the admin blind-spot class (truncation, NULL-aggregate sort, count mismatch, inner-JOIN drop, admin-auth DB fallback). Reference incident: AIVA admin "Test account" toggle hidden by an `isTest !== null` gate (2026-06-01) |
| `~/.claude/skills/shared/anti-slop-typescript.md` | **Anti-slop TypeScript** — ban generic `isRecord`/`isObject` guards, `as unknown as T` launder-casts, `(x as any).field` reach-casts; require named types / discriminated unions / Zod schemas (`z.infer`) at trust boundaries; targeted predicate only as last resort. Enforcers: repo-vendored dmmulroy/anti-slop Oxlint plugin (15 rules; `/install-anti-slop` skill vendors it, then `./node_modules/.bin/oxlint` is the gate) or fallback `~/.claude/skills/carmack/tools/detect-ts-slop.sh`. |
| `css-layout-patterns.md` | Text overflow flex+grid (#12), fixed grid mobile, iOS Safari rendering (PDF, vh, fixed) |
| `csp-cache-patterns.md` | Social card cache (#5), CSP multi-layer blocking (#9), www redirect (#4), deploy chunk invalidation, CF Pages stale deploy |
| `infrastructure-patterns.md` | Infra destruction (#6), Rust cross-platform lint (#7), Homebrew keg-only (#8), serde config crash (#10), XSS innerHTML, JSON-LD breakout |
| `debugging-discipline.md` | 4-phase workflow, diagnostic checklist (23 items), lint/security cleanup, data stale admin/user (#16), hot-path data-volume & cache-topology (#20) |
| `~/.claude/skills/shared/account-security-lifecycle.md` | Passkey/TOTP/passwordless lifecycle: alternate-login enforcement, fresh-session management, safe recovery, authoritative status, recovery-code custody, and leaked-token response |
| `~/.claude/skills/shared/observability-instrumentation.md` | **Observability / log hygiene**: 4-part actionable error-message design, boundary/decision-point logging, downgrade-noise-never-delete, instrument-on-fix attribute heuristic, stack log sources. Proactive scheduled counterpart: `/log-hygiene` skill. |
| `~/.claude/skills/shared/opaque-multi-cause-failure.md` | **Pattern #32 — one opaque error, N independent causes**: discriminator-first protocol (ship the properties-report before the next fix), free-bisect rule when failures have no side effect, one-variable-per-probe (anti-confound), component bisect, cross-reference successes, instrument-liveness table (dead `tail`, pretty-printed JSON, lagging KV), and why a health probe that stops before the failing step is blind by construction. Reference incident 2026-08-03: Solve SF `/submit` — five causes behind one `{"error":"Invalid"}`, ~6 deploys. |
| `~/.claude/skills/shared/experiment-manipulation-check.md` | **Pattern #38 — the manipulation silently no-op'd**: the four gates (applied / not-lagging / repeated / don't-publish), why "it looks intermittent" is the tell, and an instrument-trap table (`set -o pipefail` + `grep -q` SIGPIPE false-failures, suppressed apply output, silently-failing alert paths, lagging derived signals, overlay screenshots, features that rewrite your fixture). Reference incident 2026-08-25: SmartTube 403 — 21-file bisect invalidated because the app's own Auto backup clobbered the staged fixture on every launch; real cause was one line, `preferred_dns_type=2`. |
| `~/.claude/skills/shared/management-api-vs-authoritative-state.md` | **Pattern #31 — management API ≠ authoritative state**: declared-vs-consumer probe table (DNS, TLS, secrets, schema, deps, email auth, deployed code), the two questions before any "absent"/"redundant" conclusion, audit-log provenance check (`actor.type`). Reference incidents 2026-07-28: phantom CAA outage (API 5 records vs `dig` 11) and 20 "redundant" cert packs that were live Worker custom-domain certs. |
| `~/.claude/skills/shared/ant-verification-protocol.md` | **Ant-level quality gates**: OWASP sweep, truthfulness protocol, closed-loop verification |
| `~/.claude/skills/shared/cloudflare-data-ceilings.md` | **Cloudflare storage ceilings + D1 query-shape traps** — the 10 GB/db cap (no documented increase path), 30 s query timeout, and four MEASURED traps: combined `MIN(x), MAX(x)` disables SQLite's sole-aggregate index optimization (9,984,941 rows read vs **1** when split into two queries); `COUNT(*)` walks the heap (~37× costlier/row than an indexed range scan); `dbstat` and `pragma_freelist_count` are unavailable/`SQLITE_AUTH`-blocked in D1, so per-table bytes and free-page bloat are **unmeasurable** — use `meta.size_after` (returned on every D1 response); and D1 never documents whether `DELETE` reclaims space, so a post-archive size drop is unverified until measured on a copy. Also the agent-facing tooling: **Local Explorer API at `/cdn-cgi/explorer/api`** (auto-captured OTel traces under `wrangler dev` — query it BEFORE adding temporary logging and redeploying). Reference measurements 2026-08-13: `improvebayarea` D1 at 57.5% of cap, `reports` = 9,984,941 rows, `COUNT(*)` = 21,957 ms. |

---

## Cookie extraction (curl / yt-dlp / scrape with logged-in session)

When you need browser cookies for a non-browser tool (curl `--cookie`, yt-dlp `--cookies`, requests `cookies={}`, scrapers, n8n nodes), pick by where the live session is:

| Where the session is | Best tool | Why |
|---|---|---|
| Live REAL Chrome (fcdp-driven) | **`~/tools/fcdp/fcdp raw Network.getCookies '{"urls":[…]}'`** | Includes session-only cookies not yet flushed to SQLite; no Keychain prompt; aligned with `/feedback_browser_default_chrome_profile`. |
| Regular Chrome profile (`~/Library/Application Support/Google/Chrome/Default`) | **`~/tools/cookies-txt <url>`** | Reads SQLite + macOS Keychain. Works headless / from cron / without any browser attached. Outputs Netscape, JSON, or `Cookie:` header. |
| Brave / Edge / Chromium | `~/tools/cookies-txt --browser brave \| edge \| chromium <url>` | Same code, different Keychain entry. |
| One-shot, don't care about reuse | `yt-dlp --cookies-from-browser chrome:Default <url>` | Already installed; bypasses the question entirely if all you need is yt-dlp. |

### ⚠️ Which machine — fcdp runs BOTH, but by different transports (verified 2026-07-29)

| Machine | How fcdp reaches Chrome | Notes |
|---|---|---|
| **Laptop** (interactive) | **extension + bridge** — the REAL Default profile | The only way in: Chrome 136+ refuses `--remote-debugging-port` on the Default profile. Includes session-only cookies. |
| **mac-mini** (crons) | **BOTH** — extension+bridge by default; direct CDP opt-in | On PATH (`~/.local/bin/fcdp`). **Default (unset `FCDP_CDP_URL`) = extension+bridge → the REAL Default profile**, same as the laptop. Opt into the headless instance per-command with `FCDP_CDP_URL=http://127.0.0.1:9222` (Chrome headless on `--user-data-dir ~/.kuri/chrome-cdp-nextrequest`, KeepAlive-supervised by `com.barklee.kuri-cdp-nextrequest`; holds the logged-in NextRequest session). Note `[::1]:9222` does NOT answer — use the IPv4 form. |

**Both transports are live on the mini (2026-07-29).** `--load-extension` really is INERT on Chrome 150 (scratch profile registered 0 extensions, no service-worker target) — but the manual `chrome://extensions → Load unpacked` route **works over Screen Sharing** against the mini's *GUI* Default Chrome (only its `:9222` instance is headless). Bridge agent `com.barklee.fcdp-bridge` is loaded; `bridge.log` shows `ext#1 connected (1 profile(s) live)`.

So on the mini: **bridge/extension → the real Default profile** (`chrome.tabs` **integer** ids), **direct CDP → the headless `:9222` profile** (**hex** target ids). The id shape tells you which profile you actually hit — check it before trusting a result.

⚠️ **`FCDP_CDP_URL` was briefly pinned in `~/.zshenv` + `~/.hermes/.env`, and that was wrong — REMOVED 2026-07-29.** A global pin silently routed *every* Hermes cron to the **headless** profile, which does not have the user's real logins. Anything cookie- or session-dependent would read a logged-out browser and report "logged out" instead of failing loudly. Set the variable **per command**, never globally.

### 🛑 Concurrency + memory rules for cron-driven fcdp (mandatory — 2026-07-29)

Two failure modes, both verified on the mini, both silent:

1. **Clobbering.** fcdp caches "the active tab" in **one shared file** (`~/.cache/fcdp-tab`), last-writer-wins. Two concurrent jobs: A opens (cache=A), B opens (cache=B), then **A's next tabId-less command drives B's tab** — A scrapes B's page with no error and wrong data. Proven by watching the file change under two sequential opens.
2. **Tab leaks → memory.** A job that opens a tab and dies before closing leaks it permanently. Chrome on the mini runs ~4 GB across ~30 processes of **16 GB total**; three duplicate `chrome://extensions` tabs accumulated from setup work alone.

**Always drive cron browser work through `fcdp-job`** (`~/tools/fcdp/fcdp-job`, on PATH). It gives the job a private tab cache (`FCDP_TAB_CACHE`, the anti-clobber mechanism), exports `$FCDP_JOB_TAB`, and closes the tab via `trap EXIT` on **any** exit path — success, failure, timeout, or Ctrl-C:

```bash
fcdp-job https://example.com bash -c 'fcdp js "$FCDP_JOB_TAB" "document.title"'
fcdp-job --keep <url> <cmd>      # leave the tab open while debugging
FCDP_CDP_URL=http://127.0.0.1:9222 fcdp-job <url> <cmd>   # headless profile
```

Verified: two concurrent jobs each read their own page; a job exiting `1` still leaves the tab count unchanged.

**Backstop:** `~/tools/fcdp-tabkeep/fcdp-tabkeep.sh` prunes junk (`about:blank`, `chrome://newtab`), duplicate URLs, and anything past `MAX_TABS` (default 10) on **both** profiles. It **never** closes a URL matching `PROTECT` (default `nextrequest\.com` — sf-nr depends on that session) and never closes a profile's last tab. Dry-runs by default; `--apply` to act. Hermes cron `fcdp-tabkeep` (`04a06f080be9`) runs it hourly at :37 via `~/.hermes/scripts/fcdp-tabkeep-cron.sh` (the wrapper exists because the script dry-runs by default). Log: `~/Library/Logs/fcdp-tabkeep.log`, which also records Chrome's RSS + process count each run.

**Layering:** `fcdp-job` *prevents* leaks; the pruner only *catches repeated* ones (duplicates + cap). A single stale non-duplicate tab under the cap survives by design — that conservatism is what keeps the NextRequest session safe. Don't "fix" it by making the pruner more aggressive.

**Trap when closing on direct CDP:** Chrome's `/json/close/<id>` replies with the plain string `Target is closing`, **not JSON**. fcdp used to crash on it *after* the close had already succeeded — so callers logged `FAILED` for tabs that were in fact closed. Fixed 2026-07-29 (`_http_text`, 404 = already-closed = success). If you see a close "fail", re-list the tabs before believing it.

**Driving Screen Sharing (hard-won, 2026-07-29):**
- `left_click` does **not** forward to the remote. `mouse_move` + separate `left_mouse_down` / `left_mouse_up` **does**. A ~1s hold between them opens Dock context menus — press fast.
- Typing forwards but **drops characters** on longer strings, and `~` triggers the accent picker which then **swallows all input** (Escape will not clear it). Navigate with AppleScript over ssh instead: `osascript -e 'tell application "Google Chrome" to set URL of active tab of front window to "chrome://extensions"'`.
- `osascript` can *query* System Events but **cannot send keystrokes** (`error 1002`) without Accessibility; `launchctl asuser` fails with `Could not switch to audit session`.
- If the remote window renders stale/invisible, **reconnect Screen Sharing** — it forces a fresh framebuffer.
- Drop a symlink where the file picker lands (`ln -s <target> ~/Desktop/<name>`) to cut deep folder navigation to two clicks.

**Cookies specifically:** `cookies-txt` remains the right tool for a *file* of cookies on the mini — but note it **fails over SSH** (`keychain: could not read 'Chrome Safe Storage'`) while succeeding under launchd in the GUI session. That is an SSH-session artifact, not a broken tool; run the probe in the context the cron will actually use before concluding cookies are unavailable.

**The mini's trap:** `cookies-txt` **fails over SSH** with `keychain: could not read 'Chrome Safe Storage'` — an SSH-session artifact, NOT a broken tool. The same binary **succeeds under launchd** in the user's GUI session (verified: 24 cookies returned via `launchctl submit`). So never conclude "cookies are unavailable on the mini" from an ssh test; run the probe in the context the cron will actually use.

**Corollary for portable tooling:** a capture step that requires a browser belongs on the laptop; ship the result to the cron host (e.g. `caltrans-pra push-session mac-mini`) rather than trying to run the browser where the cron lives.


**`~/tools/cookies-txt` reference** (ported from the "Get cookies.txt LOCALLY" Chrome extension, source at `~/re/cookies-txt-locally/`):

```bash
cookies-txt github.com                            # Netscape → stdout
cookies-txt github.com -o /tmp/cookies.txt        # → file
cookies-txt --all -f json                         # every cookie, JSON
cookies-txt example.com -f header                 # "name=value; name=value;"
cookies-txt --browser brave --profile "Profile 1" foo.com
```

Exit codes: `0` ok, `3` no DB at expected path, `4` Keychain entry missing/denied, `5` decrypt failure.

**fcdp path** for the REAL Chrome profile — request CDP `Network.getCookies` with `{urls: ["https://github.com"]}`; format the returned cookie array with the same Netscape mapper the extension uses (`<domain>\t<TRUE/FALSE includeSubDomain>\t<path>\t<TRUE/FALSE secure>\t<expiry>\t<name>\t<value>`).

**Don't use `unbrowse` / `agent-browser`** for cookie extraction — those launch separate browser instances with no logged-in state.

---

## Quick Diagnostic Checklist

When debugging any production error, check in order:

1. Is the error message accurate? (catch-all masking?)
2. Check runtime logs: `wrangler tail` or Cloudflare dashboard
3. Reproduce locally with same endpoint + token
4. Check external services and the installed auth adapter/provider (Better Auth/Stripe/DB responding?)
5. Check env vars in deployment environment
6. Check www redirect (losing cookies?)
7. Check third-party IDs (stale template/product IDs?)
8. Check CSP (all six directives for embeds?)
9. Text overflow on mobile? (`min-w-0` missing, `grid-cols-2` without `sm:`)
10. Preference not persisting? (localStorage writer without App.tsx reader)
11. "Cannot find module" after every update? Run `file <path>.js` — may be a shell script (#17)
12. Installing missing deps one-by-one, each reveals another? STOP — postinstall is broken (#18)
13. External city form 500 after category change? Probe the failing category and a known-good category through the same first-party save path before blaming auth/photo.
13a. Experience Cloud / Aura 311 catalog or submit NPE (`toastPayload`, empty `objCaseConfigWrapper`, dummy `modelFlags`, "listed types not filing")? Load Pattern #36 **before** another envelope guess. Listed ≠ fileable; SUCCESS-empty = `captureFailure`; unwrap before send; remint IDs; classify on field API names; named refuse; Apex NPE ≠ city rejection. Flatten the live JSON with `gron` (`gron body.json | rg toastPayload`) before guessing keys; replay with `hurl --test`.
14. Production auth configured? Verify Worker dry-run bindings and live HTML do not expose `pk_test`, `sk_test`, or `.accounts.dev`.
15. Live artifact matches production? Fetch cache-busted HTML and CSP headers; compare live response, not only local `dist`.
16. Worker secrets correct? Sensitive bindings must appear as `secret_text` from `wrangler secret list`; no key/token/password literal should remain in `wrangler.json` `vars`.
17. `wrangler secret put` says binding already exists? Remove the plaintext var from config, deploy without `--keep-vars`, put the secret, and re-list secrets before trusting it.
18. AIVA deployed? AIVA uses first-party Better Auth. Verify retired Clerk fingerprints are absent from live HTML/CSP/bindings, `GET /api/auth/ok` returns 200, wrong-password sign-in returns 401 rather than 500, and `npm run test:integration:prod` passes if available.
18a. Passkey/TOTP/2FA problem or status claim? Load `account-security-lifecycle.md`; enumerate every session-creation and security-management path; distinguish account enrollment from sign-in enforcement and site-wide enrollment policy; reproduce a stale session; and use only PII-minimal authoritative counts for production status.
19. **Page/route slow?** (a) Enumerate every query that runs *before the response* — measure each `COUNT(*)`/`SUM(CASE...)`/whole-partition aggregate with `wrangler d1 execute --json` → `meta.rows_read`; >~100k rows on a per-request path = the bug. (b) Does it read a cache? Then `grep` for who *writes* that exact key — if nothing does (or only a manual script, no cron), it's a permanent MISS. (c) Cron warming a cache? `grep` for who *reads* those keys — a warmer that warms keys nothing reads (or a different key-shape than the route reads) is the bug. (d) `WHERE ts >= now() - N` against a lagged source returns empty — anchor on `MAX(ts)`. See Pattern #20.
20. **Third-party submit reported as failed but the agency received it?** (DBI complaint flow, Verint dform save, OAuth callback, any webhook receiver, any reverse-engineered API replay.) Run `ls src/__fixtures__/<integration>/ 2>/dev/null`. If there is no `*-success.*` AND `*-failure.*` pair captured from the LIVE system, you cannot trust the detector — the test suite is asserting against fiction. Write `tools/repro/<integration>-probe.{sh,mjs}`, run it once for a known-good and a known-bad request, save both responses, then diff them to find the actual distinguishing feature (anchored DOM id / JSON field, NOT a substring that appears in both). Don't ship detector code without real fixtures. See Pattern #23 + `~/.claude/skills/shared/third-party-signal-fixtures.md`. Reference incident (2026-05-27): every IBA-submitted DBI complaint was reported as `validation` error for ~10 days while the city actually recorded every one of them — synthetic test fixture (`<html><body><h1>Thank you</h1>...`) didn't contain the form layout strings (`Sub_Button0`, `CheckBox1`) that the real DBI success page does contain, so the detector's `looksLikeEchoedForm` heuristic was never exercised against reality.

21. **Error too vague to act on, firing repeatedly, or no log at the failure point?** Don't just patch this one instance — make the message actionable (what was attempted + actual values + likely cause/branch + disambiguation; a vague error is usually two root causes sharing one string), add the one attribute that would have named the failure, and *downgrade* noisy lines rather than deleting them. Standard: `~/.claude/skills/shared/observability-instrumentation.md`. For a scheduled sweep over a window of logs, use the `/log-hygiene` skill.

22. **About to conclude "X is absent" or "X is redundant / safe to delete" from a provider/management API?** STOP — that API shows what was *declared*, not what the platform *injected*, and never *why* a resource exists. Two questions before the conclusion: (1) **Is my view complete?** Name the consumer (resolver / CA / browser / runtime / MTA) and probe it directly — `dig` not `dns_records`, `openssl s_client` not the cert list, a real delivered message's `Authentication-Results` not your SPF records. A count mismatch between the declared and authoritative views **is the finding**. (2) **Do I know what created it?** Check the audit log's `actor.type` — `system` means the platform provisioned it and something probably depends on it. **You cannot call a resource redundant until you can name what created it.** Deletion recommendations built on a management-API read are the dangerous output here: the false-"absent" mode wastes a cycle, the false-"redundant" mode causes an outage. Pattern #31: `~/.claude/skills/shared/management-api-vs-authoritative-state.md`.

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

### Semantic Security Review Gate — LOOP UNTIL CLEAN (MANDATORY — 2026-07-22)

**When a `/debug` session lands a code fix, run the built-in `security-review` skill on the fix before declaring it resolved, and loop until it is clean.** A debug fix that patches the symptom but introduces (or leaves) an injection / XSS / SSRF / auth-bypass / secret-exposure / logic flaw is not done. This is AI/semantic dataflow analysis — it catches the vulnerability class the pattern-routing tables above do not.

**⚠️ OPERATIONAL (verified 2026-07-22):** `security-review` runs against the CURRENT WORKING DIRECTORY's git repo (no path arg; hard-fails `"needs to run inside a git repository"` if cwd is wrong — `cd <repo-root>` FIRST) and reviews the **COMMITTED** branch diff vs the base, NOT uncommitted working-tree edits (proven: unstaged changes → empty diff). **Commit the fix before running this gate**, or it reviews nothing. It returns a markdown report (file:line, severity, confidence 1–10) with its own false-positive filter at confidence ≥8. If the Skill returns unknown-skill, tell the user the gate couldn't run rather than passing silently.

**The loop:** (1) `cd` into the repo root, invoke the `security-review` skill (Skill tool) on the changed code; (2) triage its reported (confidence-≥8) findings real vs. genuine-false-positive; (3) FIX every real finding inline, obeying the No-Suppression Rule (no `@ts-ignore`/`eslint-disable`/`biome-ignore` — remove the actual vulnerability); (4) re-invoke `security-review`; (5) repeat until the report is **empty**. Document any genuine false positive inline with its reason; fix everything else, never defer. **Loop guard:** same finding surviving 5 attempts → STOP and surface it to the user. This runs entirely within `/debug`'s allowed scope (local fix + verify) — it does NOT deploy (Deployment Prohibition still holds); the code is left security-clean and committed, and `/ship`'s Phase 1.29 re-runs the same loop at deploy time. Skip only when the session made no code change (pure investigation/reference).

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
   - For account-security symptoms, the matching file is `~/.claude/skills/shared/account-security-lifecycle.md`; also read the installed auth SDK/plugin source before proposing a fix.
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


## Script false-failures that make a WORKING thing look broken — MANDATORY (2026-08-25)

Sibling of the PATH section below: there the script can't find a binary; here the
script finds it, runs it correctly, and **reports failure anyway**. Both waste a
debugging session on a non-bug.

- **`set -o pipefail` + `grep -q` / `head` = guaranteed false failure on valid input.**
  `grep -q` exits at the first match, the upstream producer gets **SIGPIPE**, and
  `pipefail` propagates that as a failed pipeline. Signature: *"it fails inside my
  script but the exact same command works when I paste it in the terminal"* (your
  shell has no `pipefail`). **⚠️ INPUT-SIZE DEPENDENT — the producer must still be
  writing when grep exits, so a SMALL test fixture will NOT reproduce it.** Measured
  2026-08-25: a 2-entry zip reproduced 0/3; a 4,007-line listing with the match early
  reproduced 3/3. Size the repro like production or you will 'disprove' a real bug.
  Fix — count instead of short-circuiting, since `grep -c`
  drains all input:
  ```bash
  if ! unzip -l "$f" | grep -q AndroidManifest; then   # ❌ SIGPIPE -> false failure
  n=$(unzip -l "$f" | grep -c AndroidManifest || true) # ✅ drains input
  [ "${n:-0}" -ge 1 ] || die "not a valid APK"
  ```
- **Never `>/dev/null 2>&1` an apply / restore / deploy / install step** you will draw
  conclusions from. A silent no-op is indistinguishable from success.
- **An alert path that can fail silently is worse than no alert.** Capture rc + output
  of the send and log `alert sent: …` vs `ALERT-FAILED rc=…`; otherwise "alerting is
  configured" is untested folklore. (Configured ≠ fires — see the No-Lie gate Check 6.)
- **Downloading a GitHub release asset:** `curl` with an `Authorization:` header
  following the redirect to S3 is flaky (the header is re-sent to a host that rejects
  it). Use `gh release download` — it handles auth + redirect.

Reference incident 2026-08-25: a valid 25 MB APK was rejected as "not a valid APK"
by the first rule above, in a cron script that was otherwise correct.
Full table of instrument traps: `~/.claude/skills/shared/experiment-manipulation-check.md`.

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

24. **Is the thing telling you "healthy" capable of ever saying otherwise?** Before you accept a green probe / validator / drift-job / "N/N verified" sweep — or retract a finding because a second measurement came back clean — construct a **known-bad input** and require the instrument to go RED. A corrupted token, a mutated id, a nonexistent resource. If the known-bad also passes, stop: the instrument is vacuous, that is now the P0, and every green it has produced is worthless. This is the mirror of the Negative-Result Rule (positive control on a *negative*; negative control on a *positive*) — and the green direction is more dangerous, because nothing about it prompts you to look. **Echo is not validation**: an upstream that reflects your value back into its response has not checked it. Report three outcomes, never two — `ok` / `genuinely bad` / `could not measure` — and commit the negative control as a test with its reason in the body. Also: a clean *sample* is not a clean *population* (a 30-park sample read `stale=0` against a real 1.1% drift rate), and a `verified:` date on harvested data is a decaying claim, not a health signal. Pattern #33: `~/.claude/skills/shared/negative-control-gate.md`.

23. **Did your fix leave the error string byte-identical?** That is Pattern #32, not a failed fix — the error is not a discriminator. Do NOT attempt fix N+1 blind. (a) Ship a **discriminator**: have the failure path report the measurable properties of what it sent (`len=`, boolean flags; never the payload — PII). Every flag reading false while it still fails positively excludes your hypothesis space. (b) Bisect by **component**, one variable per probe — if a probe flips fail→pass, ask what ELSE changed in that step (a confounded step is the most expensive error in this class). (c) Build a **property→result table** across all probes; the cause is the property in 100% of failures and 0% of successes. (d) If failures have no side effect, probing prod is **free** — order expected-fails first, stop at the first success, and say so. (e) **Never conclude from an instrument you haven't proven alive** — `wc -c` the tail capture, count parsed objects (`wrangler tail --format json` is PRETTY-PRINTED, not JSONL), and re-poll KV (reads lag). Pattern #32: `~/.claude/skills/shared/opaque-multi-cause-failure.md`.
