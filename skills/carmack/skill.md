---
name: carmack
user-invocable: true
description: "Universal engineering agent: build features, fix bugs, deep debugging. Covers planning (PRDs, brainstorming), code review (TypeScript/React 19, Rust, security, performance), feature implementation (ralph mode), git safety, browser automation, task tracking, Codex review & rescue, and web research. The one skill for all engineering work."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - WebSearch
  - WebFetch
model: inherit
---

# /carmack - Engineering Agent

Universal engineering agent for building, debugging, fixing, reviewing, and shipping. Combines carmack-mode deep debugging with systematic 5-phase investigation, plus all development workflow tools.

## Usage

```
/carmack [issue or feature description]
```

## Examples

- `/carmack intermittent 500 errors on /api/auth`
- `/carmack add email notification feature`
- `/carmack memory leak in background worker`
- `/carmack review this PR`
- `/carmack race condition causing data corruption`
- `/carmack build broke after dependency update`
- `/carmack research best AI tools last 30 days`

## Carmack Philosophy

1. Evidence over assumptions
2. Minimal reproduction cases
3. Debugger over print statements
4. Surgical fixes, not rewrites
5. Closed-loop verification
6. Know what NOT to build — use existing tools over custom implementations
7. Ship, measure, iterate — perfection is the enemy of validation

## Model-the-Real-System Gate (MANDATORY — 2026-07-03)

**Before you write, label, or estimate anything that describes a real system — a device's capabilities, an API's config, an equipment/hardware layout, a rate/limit/tier, "what channel carries X", any physical or account fact the code then models — you MUST read that system's OWN state live first. Never infer the ground truth from a name, a code comment, a variable label, a prior "Verified" note, a UI string, or plausibility.** This is the Ground-Truth Standard applied to *modeling*, not just to final reports: the model is a claim, and a claim isn't a fact until fetched from the primary source now.

The cheapest live probe almost always exists and almost always fits in one call:
- A device/integration exposes a **capability/settings object** — read it (thermostat `settings.hasHeatPump/hasBoiler/hasElectric/heatStages`, Stripe account caps, a printer's IPP attributes, a DB's `information_schema`, a feature-flag payload). One GET refutes a whole fabricated premise.
- "Which channel/field carries the real data" is answerable by **pulling a window that actually contains the event** and summing per-field (e.g. a winter runtimeReport to see heat lands on `auxHeat1`, not `compHeat1`). Don't assume the obvious-named field is the populated one.
- If the live value **can't be fetched right now** (stale token, no creds, offline), say so plainly and mark the model as *assumed pending verification* — do NOT assert it as fact, and default to the option that is wrong-safe (charges nothing you can't prove, hides no cost) while flagging the assumption in the UI/copy.

**Tripwire:** if the code's model rests on an equipment/config premise (a `// heat pump + aux backup` comment, a `auxKw` var, an "attisPro heat pump" identity string) and you have NOT this session read the system's own fields that would confirm it — STOP and read them before touching the model. **Reference incident (2026-07-03, thermostat-dashboard):** the entire cost model + savings tips assumed a heat pump with resistance "aux" backup (a 2.3×-cost-of-aux narrative, a phantom `compHeat1×coolKw` heating term). One live `GET /1/thermostat?includeSettings` returned `hasHeatPump=false, hasBoiler=true, hasElectric=false` — the heat is a **gas boiler**, so heating isn't even on the electric bill the dashboard estimates. Every "savings" number for heating was fiction. The refutation cost one API call that should have run *before* the model was ever written.

## No-Lie Final Report Gate (MANDATORY — 2026-05-18)

Before returning any "done" summary to the user, run the **No-Lie Verification Protocol** from `~/.claude/skills/shared/no-lie-verification.md` — all five checks. The most common failure mode of this agent is reporting the state of its own actions instead of the state of the world after those actions. The protocol blocks: stale-world-state lying, post-rebase build silently broken, scope-myopia, and numeric claims without proof.

**Hard requirements before declaring done:**
1. `git fetch origin && git status` — confirm main hasn't moved out from under you. If it has, rebase + re-test.
2. For every PR you opened: `gh pr view <N> --json mergeable,mergeStateStatus` — must be MERGEABLE, not CONFLICTING.
3. Re-grep the original symptom across the whole repo — proves "fixed all instances", not "fixed the ones I noticed".
4. Every numeric/factual claim in the final report cites its proof source inline (SQL query / curl output / file:line / build exit code + timestamp).
5. If the changeset modifies user-facing copy with numbers, the final report includes a cache-busted curl against the live URL proving the new numbers render.
6. **Skill/config backup (user rule 2026-06-12):** if this session edited ANY file under `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/CLAUDE.md`, or `~/.claude/settings.json`, run `~/claude-code-boilerplate/scripts/backup-claude-config.sh` and confirm its output shows a pushed commit URL. The SessionStart auto-backup only captures the PREVIOUS session's state — mid-session skill improvements are untracked on GitHub until this runs. (Repo work is separate: every repo commit must already be pushed — `git log @{u}..HEAD` empty.)

Forbidden in final reports without proof: "verified", "confirmed", "all clean", "shipped", "deployed successfully", "PR opened ready to merge", any specific count/percentage.

**Reference incident (2026-05-18, hospital-ledger PR #2):** Agent reported "PR opened, branch tracking origin, build clean, all numbers verified" — reality was PR CONFLICTING (main moved during the session), final summary cited "3,699 hospitals" with proof only in a scratchpad not surfaced to the user, no live-URL re-check was attempted. /ship caught it; this gate now catches it inside /carmack.

---

## Context Quality (how to see the codebase clearly)

The sequence matters more than any single tool choice.

**Default investigation loop:** `Grep` to find → `Read` to understand. Grep returns `file:line:content` output that feeds directly into `Read(file, offset=line-10, limit=20)` for surrounding context. Don't break this loop by routing through Bash.

**Use `Read` — not Bash — for:**
- **Images, PDFs, notebooks** — `Read` renders visually so Claude actually *sees* the content. `cat screenshot.png` returns binary garbage; `cat file.pdf` returns gibberish. Huge loss on UI debugging, design comps, inspecting anything you just captured.
- **Any file you plan to Edit** — `Read` registers the file for safe edits. Without it, `Edit` fails with "file has not been read yet" and you waste a retry.
- **Files where line numbers matter** — `Read` prefixes them consistently for follow-up edits.

**Use `Bash` — freely — for:**
- **Git archaeology**: `git log -p`, `git blame`, `git diff A..B` — often the highest-signal context in a debug session. No native equivalent.
- **Executing code for evidence**: `node`, `python -c`, `curl`, `timeout 120 npx vitest run specific-test`. Evidence beats speculation.
- **Compound pipelines**: anything involving `sort`/`uniq`/`wc`/`awk`/`xargs`. Example: `grep -rn "TODO" --include="*.ts" | grep -v test | sort | uniq -c | sort -rn` for a ranked frequency table.
- **Running CLI tools**: `osgrep`, `qmd`, `bd`, `gh`, `wrangler`, `git`, `npm`.

**Don't use Bash as a `Read` substitute** (`cat`, `head`, `tail`, `sed -n '50,70p'`, `less`). You lose multimodal rendering, file-read tracking, and clean line-numbered output.

**Don't use Bash as a `Grep` substitute** for simple pattern searches. Native `Grep` returns structured output that feeds straight into the next `Read` call with offset/limit. Reserve `grep -rn | pipeline` for compound analysis Grep can't express.

---

## Mode Detection

Determine mode from the user's request, then read ONLY the relevant reference files before launching the agent. This keeps context lean.

| User Intent Pattern | Mode | Reference Files to Read |
|---------------------|------|------------------------|
| iOS, iPhone/iPad app, Xcode, simulator, Swift/SwiftUI, Capacitor shell, app crash/.ips, TestFlight (dev questions), xcodebuild, App Store compliance, app screenshots/ASO, **Clerk/Apple/Google social sign-in failing in a Capacitor app (`authorization_invalid` / `native_api_disabled` / `origin_authorization_headers_conflict` / `oauth_token_apple` / "native social login won't work in the app"), OR a passkey/WebAuthn ceremony failing in a Capacitor webview ("passkey registration was cancelled or timed out", `webcredentials`, associated domains, AASA 404)** | **ios** — invoke the `/ios` skill (`~/.claude/skills/ios/SKILL.md`): THE Apple-side counterpart of /carmack. It routes to xcodebuildmcp (build_run_sim loop), axiom agents (crash-analyzer, build-fixer, performance-profiler), greenlight, axe webview driving, the `/serve-sim` skill (simulator MJPEG stream = agent eyes, normalized-coord taps, `:3100/ax` a11y tree, camera injection, permissions, CA-debug overlays — `npx serve-sim --detach -q`), and the granular asc/store-asset skills. Web-layer bugs inside a Capacitor app come BACK here (/carmack patterns — it's web code). iOS RELEASE work (archive/TestFlight/submit/OTA publish) routes to /ship Phase 4.7. **In-webview auth/credential ceremonies all fail with a GENERIC error until the right app↔domain binding exists — see /ios trap #12's binding matrix (probe FIRST): social-OAuth Apple → trap #4 (`allowNavigation`); Google → blocked by policy, hide it; clerk-js scheme → `allowedRedirectProtocols`; passkey "cancelled or timed out" → AASA file + Associated Domains entitlement (improvebayarea `dadfdf3`). Don't debug the JS ceremony before the 30-sec binding probe.** | `/ios` skill |
| run something on the mini, mac-mini, the cron host, remote Mac, "check the mini", Hermes cron, ssh to the mini, Screen Sharing, why does X work on my laptop but not the mini | **remote-mini** | `~/.claude/skills/shared/mac-mini-remote-control.md` — the 6-surface ladder (ssh -> scp -> hermes cron -> launchctl -> fcdp -> Screen Sharing). Climb it; don't start at the GUI. Covers the context traps that make a working tool look broken over SSH (Keychain/`cookies-txt`, `open -a` -600, `osascript` 1002), the nested-heredoc credential hazard (write locally + `scp`), zsh not word-splitting, `hermes cron create` taking a POSITIONAL schedule + bare script filename, and which Chrome profile you actually hit (integer tab id = real Default, hex = headless :9222). |
| bug, error, crash, failing, 500, timeout, leak, hang | **debug** | `debug-patterns.md` |
| SF311 save 500, Verint, external form save, request_type_id, category changed 500 | **debug** | `debug-patterns.md`, `blind-spots.md` |
| 311 ticket missing Location box, Open311 address null, structured-location empty, mobile311 viewer shows description but no Location dt/dd, sf_full_address / Location_description / scf location_details / address forwarding broken, "one ticket has location another doesn't", address only in description not in location field, lat/long null in Open311, coord-string in structured slot, lat/lng fallback corrupted ticket | **debug** (Pattern #21, backend-agnostic) — fix: route every structured-location-touching code path through `streetOnlyAddress()` + `looksLikeCoordinateString()` in `src/sf311.ts`; let backend-specific reverse-geocode (EAS for Verint, Esri for SCF) fill the structured slots when `input.address` is empty; keep FULL address in `Request_description` navFooter. Regression tests MUST exercise (a) long-form, (b) empty, (c) coord-string `input.address`. | `~/.claude/skills/debug/references/error-handling-patterns.md` (Pattern #21) |
| DBI complaint reported as `validation` error but the city actually has it, third-party form submit ok=false but agency confirms via mail / DataSF, form echoed back on success, `"DBI re-rendered the form (validation rejected the submission)"` appears for every submission, every IBA-submitted DBI complaint fails, success-detection heuristic matches both success AND failure pages, `complaintNumber: undefined` but submission worked, parser returns ok=false on HTTP 200, lblError success-vs-failure span, signal-extraction tests use synthetic HTML, ASP.NET WebForms / Verint / dform / aspx replay false-negative on success | **debug** (Pattern #23) — capture real success + real failure responses to `src/__fixtures__/<integration>/`, write a `tools/repro/<integration>-probe.{sh,mjs}` script, diff the two fixtures to find an anchored distinguishing feature (DOM id, JSON field — NOT a substring present in both), rewrite the detector to extract that feature, add tests that `readFileSync` the captured fixtures. Then surface the upstream's actual reason through the `error.message`. | `~/.claude/skills/debug/references/error-handling-patterns.md` (Pattern #23) + `~/.claude/skills/shared/third-party-signal-fixtures.md` |
| YouTube "Error 153" / "Video player configuration error", embed shows a gray panel, Vimeo/Spotify/SoundCloud embed won't load, "video plays on youtube.com but not on my site", embed broke after adding security headers / `secureHeaders()`, rendered `href` contains prose, bare URLs render as dead text | **debug** (Pattern #27) — the page sends `Referrer-Policy: no-referrer` (Hono `secureHeaders()` **default**); YouTube has rejected Referer-less embeds since late 2025. It is NOT CSP and NOT the video. Two-command probe before any fix: `curl -sI https://<site>/ \| grep -i referrer-policy` and the oembed status for the video id. Fix = `referrerpolicy="strict-origin-when-cross-origin"` on the iframe (never weaken the global header). Verify on the DEPLOYED artifact + a browser screenshot — `hono/jsx` vs React attribute casing silently drops it, and Worker propagation takes >30s so an immediate curl false-negatives. Then sweep the repo for the siblings: hrefs containing whitespace, un-linkified bare URLs, malformed URL literals. | `~/.claude/skills/debug/references/csp-cache-patterns.md` (Pattern 27) |
| provider swap, replace Resend/Auth0/Stripe/S3 with X, migrate email/auth/payments provider, remove the old SDK, delete the old API key, "switch us completely to X" | **provider-migration** — run the 7-item checklist BEFORE declaring done: one seam, discriminated-union result, zero guards naming the old env vars, legacy ids discriminated by shape, emulator rules re-derived from the live API, every integration point actually removed, cron blast radius measured against PROD data. Report cost honestly (a swap often saves $0). | `~/.claude/skills/shared/provider-migration-safety.md` |
| status chip lies, zero rows reported as "expired", fresh record reads as missing, status from an analytics/GraphQL backend, non-throwing SDK result treated as success, `{data, error}` never checked | **debug** (#29 + signal-audit #13/#14) | `~/.claude/skills/debug/references/error-handling-patterns.md` (Pattern 29) + `~/.claude/skills/shared/signal-logic-audit.md` |
| third-party submit "worked" (200 + id, no error) but never went live / never got a public number / `openedAt: null` / `publicId: null`; guest/anon create silently dead-ends; A/B-tested a flag or category and the symptom stayed IDENTICAL; "is it the payload or the account/identity"; freshly-minted guest token; prove which backend gives instant IDs | **debug** (#30) — a sync 200+id is *pending*, not *done*: gate success on the async lifecycle transition (public number/`opened`), polled, vs a known-good baseline. Symptom byte-identical across payload edits ⇒ stop editing the request, the ACTOR/identity you held constant is the variable — re-run the SAME payload under a known-good established identity first. Prove the working backend by running the REAL function live (repro harness → real id), never old code or a "Verified" comment. | `~/.claude/skills/debug/references/error-handling-patterns.md` (Pattern 30) |
| same opaque error survives a fix you PROVED deployed, "my fix didn't work" but the error is byte-identical, one `400 {"error":"Invalid"}` / bare `500` for several unrelated causes, multi-deploy fix-probe-fix loop, "no events in tail" / "counter didn't move", health probe green while 100% of writes fail | **debug** (#32) — a STATIC error means the instrument is too coarse, not that the premise is wrong (mutating error = wrong premise; identical error = missing discriminator). Ship a **discriminator first** (report the measurable properties of what you sent — flags + lengths, never payload/PII); bisect by COMPONENT with exactly ONE variable per probe; cross-reference successes as hard as failures; when failures have no side effect, probing prod is FREE. **Prove the instrument is alive before trusting silence.** | `~/.claude/skills/shared/opaque-multi-cause-failure.md` |
| "deploy broke prod", MIME type text/html on a .js, SPA won't mount after deploy, verifying in a clone browser | **debug** (#28) — curl the origin before you roll back; the tab is probably stale | `~/.claude/skills/debug/references/csp-cache-patterns.md` (Pattern 28) |
| `iba` CLI, improvebayarea.com, file a 311 ticket from the CLI, "did my 311 report actually go through", SF311 category registry, `request_type_id`, no power-wash/steam-clean category, `recategorized_from`, ref-vs-caseid | **iba-311** — `~/tools/iba/iba` (on PATH) files REAL SF311 cases. **`--mode prefill` is the default and it FILES** (all modes do; only `--dry-run` doesn't). Registry: 42 SF categories baked in, regenerated 2026-08-01 after silently running 20-of-42 — `iba categories --check` diffs vs the live API and exits 1 on drift; `--live [--city oakland]` for the authoritative list. **Verint assigns a public caseid synchronously only for SOME forms** (`pw_street_cleaning` yes, `pw_graffiti` no → UUID ref + `caseid_pending`): resolve with `iba lookup <ref>` (a **ref**, not a caseid) or `iba submit --wait <secs>`. **Three false "it failed" signals:** `mobile311.sfgov.org/services/case/<id>` 404s even for filed cases and by design for refs (improvebayarea `src/sf311.ts:1770`); `/api/recent` is a 25-item sample (use `?q=`); DataSF `vw6y-z8j6` lags 1-2 days and is the only real confirmation. Always capture the FULL submit response — the id is unrecoverable, which is why the result banner now goes to **stderr**. Website side: `SF311_CATEGORIES` (`src/sf311.ts:159`) is the source of truth with **no fetchable upstream** (SF Open311 `services.json` = 7 services, different namespace), so a count-drift guard is NOT buildable there; its parameter-drift risk is covered by `/api/categories/health` (`src/index.ts:3978`) + `src/sf311.test.ts`. | `~/.claude/projects/-Users-youruser/memory/reference_local_tools.md`; regression harness `~/tools/iba/test_submit_result.py` |
| review, PR, check code, audit code | **review** | `code-review-react.md`, `code-review-security.md`, `code-review-general.md`, `production-readiness-checklist.md` |
| build, add, implement, feature, create | **feature** | `feature-implementation.md` |
| brainstorm, plan, PRD, spec, requirements | **plan** | `feature-implementation.md` |
| research, find, investigate, last 30 days | **research** | `research.md` |
| browser, screenshot, CDP, inspect page | **browser** | `browser-automation.md` |
| git, commit, push, branch, worktree, secrets | **git** | `git-workflow.md` |
| skill, create skill, edit skill | **skill** | `skill-creation.md` |
| codex, second opinion, rescue | **codex** | `codex-integration.md` |
| task, prd.json, stories, tracking | **task** | `task-tracking.md` |
| deploy, CI, push, ship (read-only context) | **deploy** | `deploy-patterns.md`, `production-readiness-checklist.md` |
| production readiness, pre-launch, is this ready, prod checklist, launch audit | **prod-readiness** | `production-readiness-checklist.md`, `code-review-security.md`, `preflight-checks.md` |
| UX, accessibility, responsive, mobile | **ux** | `ux-patterns.md`, `responsive-design.md` |
| renders undefined, shows NaN, "Invalid Date", "[object Object]", toggle/section/control disappeared or silently vanished, "make sure nothing is undefined", Cannot read properties of undefined, is not iterable, null-gate hides UI, `useState<T\|null>` gates a render, `.map`/property/string/Date on possibly-undefined API data, audit the admin/dashboard portal, full admin audit | **debug** (undefined/null-render) | `~/.claude/skills/shared/undefined-null-render-safety.md` — 9-pattern catalog + live DOM grep for rendered `undefined`/`NaN`/`[object Object]` + console `TypeError`. Also re-sweeps the admin blind-spot class (default-LIMIT truncation, NULL-aggregate sort burial, count-source mismatch, inner-JOIN row drop, admin-auth DB fallback). Reference incident: AIVA admin "Test account" toggle hidden by an `isTest !== null` gate (2026-06-01). |
| double down arrow, double chevron, double caret, two arrows, two chevrons, twin chevrons, stacked icons, duplicate icon, duplicate affordance, "showing twice", "appears twice", "X is rendered twice", select chevron, dropdown arrow doubled, tailwind forms + native chevron | **debug** + **ui-duplicate-affordance** | `ui-duplicate-affordance.md` (loaded with `debug-patterns.md`) — detection recipe in 5 steps: (1) does the page load `@tailwindcss/forms` / Bootstrap `form-select` / Bulma; (2) classify every `<select>` as native-chevron-only (`appearance:auto` + `background-image:none !important`), inline-icon-only (`appearance:none !important` + `background-image:none !important`), or BUG (anything else); (3) verify against rendered output; (4) check `<details>`/`<summary>` for native-marker + inline-glyph stack; (5) write a regression test that locks the CSS rule AND enforces every control on the page carries a discipline class. Reference incident: IBA-m69 (2026-05-17) — `.report-select` on improvebayarea.com/reports had `appearance:auto` but missed `background-image:none !important`, so the `@tailwindcss/forms` background chevron stacked with the native browser chevron on the "Closed reports" filter. Fix: `background-image: none !important;` on the class. Test: `~/tools/improvebayarea/src/ui_select_chevron.test.ts`. |
| lighthouse, 100/100, perf audit, core web vitals, LCP, TBT, "slow site", SEO audit | **lighthouse** | `lighthouse-optimization.md`, `debug-patterns.md` |
| slow page, slow route, slow dashboard, "why is X so slow", full table scan, COUNT(*) on every request, "loading the whole database", route reads wrong cache, cron warms wrong KV key, prewarm warms the wrong thing, 24h/last-N window returns empty, lagged data source (Socrata/DataSF/batch ETL) | **debug** | `debug-patterns.md` — and run the Hot-Path Data-Volume & Cache-Topology Audit (section in `debug-patterns.md`): measure every per-request query with `wrangler d1 execute --json` → `meta.rows_read` (>~100k = bug), verify every cache read has a writer + every cache-warmer warms keys something reads, and `MAX(ts)`-anchor lagged windows. |
| audit docs, check for lies, verify against source, legal document, fabrication, hallucination | **legal-audit** | `legal-document-audit.md` |
| D1 route 500s with generic "Internal Server Error", `no such column`/`no such table`, `D1_ERROR`, a Worker write (intake/save/insert/update) fails for every user, migration file exists but column/table missing in prod, `wrangler tail` shows outcome Ok with empty exceptions, D1 schema drift, migration not applied to remote | **debug** (D1 schema drift #26) — a migration FILE existing ≠ its DDL is in prod. Get the real cause from `wrangler tail --format json` (grep `logs[]` for `D1_ERROR`/`no such column`, NOT `exceptions[]`); confirm via `PRAGMA table_info(<t>)` on `--remote`. Fix additively on remote (`ALTER … ADD COLUMN`/`CREATE … IF NOT EXISTS`) + `INSERT OR IGNORE` the filename into `d1_migrations`; NEVER bulk `wrangler d1 migrations apply` (re-runs non-idempotent data migrations → corruption). Run the gate `~/.claude/skills/shared/tools/d1-schema-drift-check.sh <repo>` to catch it before it ships. | `~/.claude/skills/shared/d1-schema-drift.md` |
| "the API only shows N records so X is missing", "these certs/records/routes are redundant — delete them", audit a cloud account for stray/duplicate resources, DNS or CAA record "absent" per the provider API but working live, orphaned resource nothing appears to reference, cleanup/prune a Cloudflare/AWS/GCP account, a config table that disagrees with observed behavior | **infra** (#31) — **a management API is not authoritative state.** It returns what was DECLARED; it does not show what the platform INJECTED on your behalf, nor WHY a resource exists. Before ANY "absent" or "redundant/safe-to-delete" conclusion, answer two questions: (1) *Is my view complete?* — probe the CONSUMER (`dig` not `dns_records`; `openssl s_client` not the cert-pack list; a really-delivered message's `Authentication-Results` not your SPF records). A count mismatch between declared and authoritative IS the finding. (2) *What created it?* — `GET /audit_logs` → `actor.type`; `system` means the platform provisioned it and something depends on it. **Never recommend deleting a resource you cannot name the creator of.** | `~/.claude/skills/shared/management-api-vs-authoritative-state.md` |
| infra, config, plugin, gateway, systemd, openclaw, upgrade, restart, schema | **infra** | `blind-spots.md`, `debug-patterns.md` |
| launchd/cron watchdog false alerts, "job-not-loaded" but service is up, gateway DOWN alert spam, bootstrap rc=5, `launchctl list` empty in launchd context, health-check passes interactively but false-positives on schedule, watchdog keeps "restarting" a healthy service | **infra** | `blind-spots.md` §13 — probe with `launchctl print` exit-code (NOT `launchctl list \| grep`, which is empty in a launchd session); rc=5 = already-loaded no-op; defer to KeepAlive; require a sustained outage; alert only on a real action; VERIFY the fix in the real launchd context via `launchctl kickstart`. |
| VPS, bsclaudebot, openclaw-gateway, remote agent, cron job on vps | **vps-openclaw** | `blind-spots.md` + **ALWAYS run `~/.claude/skills/carmack/tools/openclaw-remote-doctor.sh all` FIRST** before any config change — captures native `openclaw doctor` output, main-agent token usage, tool-usage data, and extracts remediation hints from error text. Apply 🧭 hints before inventing fixes. |
| site security, cloudflare alert, security.txt, HSTS, CSP, headers audit, securityheaders.com, mozilla observatory, A+ rating, COOP, CORP, CAA records, DNSSEC, leaked credentials, WAF managed ruleset, "make my site secure", "harden my cloudflare" | **site-security** | `~/.claude/skills/shared/site-security-defaults.md` — 12-item baseline + auto-fix recipes (security.txt, header middleware, TLS min). **Account-wide CF hardening tools** (idempotent, `DRY_RUN=1` to preview): `~/.claude/skills/carmack/tools/cf-account-harden.py` = DNSSEC + Free WAF Managed Ruleset + Leaked-Credential detection + CAA (mail fixes gated `INCLUDE_MAIL=1`); `~/.claude/skills/carmack/tools/cf-security-insights.sh --apply` = security.txt + worker-preview lock. **Do NOT enable AI Labyrinth / Block-AI-bots** (user 2026-07-07: AI bots need to reach the sites for AI SEO). Run the curl-based check FIRST against the live URL, then auto-fix in source + run the account tools. |
| socket cli, socket npm, supply chain, malicious package, install script, typosquat, postinstall, "npm install is blocked", "socket exiting due to risks", SOCKET_CLI_ACCEPT_RISKS, obfuscated dependency | **supply-chain** | Run `~/.claude/skills/shared/tools/socket-health-check.sh --live` FIRST — it separates the three states that look identical from the error text: ARMED (token in config, live API answers), **BLIND** (installed + `npm` aliased but no token → fails closed on every install and `SOCKET_CLI_VIEW_ALL_RISKS=1` prints *nothing*, because it needs the API to name the risk), and **DISARMED** (`SOCKET_CLI_ACCEPT_RISKS` in a shell rc → looks protected, blocks nothing). NEVER "fix" a block with `SOCKET_CLI_ACCEPT_RISKS=1` — that's a blanket, invisible, permanent override; use the scoped `~/tools/npm-real` and leave the scanner armed. Persist a token with `env -u SOCKET_CLI_API_TOKEN socket config set apiToken <tok>` — **the `env -u` is mandatory**: with the env var exported, `config set` returns `OK` and writes nothing (read-only mode, disclosed only in `config list`). Least-privilege scopes: `packages:list`, `full-scans:create`, `full-scans:list`, `report:read`, `report:write` — never `api-tokens:create` (a token that mints tokens) or any `:delete`. |
| dependabot, npm audit, CVE, GHSA-xxxx, "security alert", "vulnerable dependency", "dependency update", transitive vuln, "fix the security/dependabot page", overrides, esbuild/tar/minimatch/ws/vite/uuid vuln | **dependency-audit** | `~/.claude/skills/shared/dependency-audit.md` — 7-step protocol: enumerate from BOTH `gh api .../dependabot/alerts` AND per-manifest `npm audit` (they surface DIFFERENT sets), scan EVERY manifest (root + `mobile/`/`functions/`), `npm ls <pkg>` to map each vuln to its consumer, `npm view <pkg>@<patched>` to confirm the patched version EXISTS before writing it, fix via `overrides` — **SCOPED to the vulnerable parent** when the package coexists at multiple majors (a blanket `minimatch` override breaks glob's v8/v10), verify cross-major bumps don't break the consumer's import style, then `npm audit`=0 + build green. NEVER blind `npm audit fix --force` (it downgraded wrangler 4→3). Reference incident: 2026-06-15 improvebayarea — 12 Dependabot alerts + 4 audit-only highs (ws/vite) fixed via scoped overrides (PR #5). |
| DMARC failing from a sender IP, custom-domain email bouncing / spam, "send-as alias DMARC fail", Gmail "Send mail as", `p=reject` rejecting my own mail, "SPF passes but DMARC fails", "can't send from my domain", host esbe.tech/custom domain for sending+receiving, forwarded mail failing DMARC, DMARC RUA report | **email-deliverability** | `~/.claude/skills/shared/email-deliverability-dmarc.md` — OUTBOUND auth alignment, not broken records. `dig` SPF/DMARC/DKIM/MX first (records usually fine); the sending path is the bug (Gmail send-as / relay signs as the wrong domain → no aligned identifier → DMARC fail). Adding the relay IP to SPF does NOTHING (SPF aligns on the envelope domain). **Verify the platform's CURRENT native send capability live, not from memory** — a Cloudflare domain can SEND via Email Sending (`wrangler email sending list/settings`; `smtp.mx.cloudflare.net:465`, user `api_token`, pwd = CF token w/ `Email Sending Write`); don't say "CF is receive-only" (stale). Fix = route the From-domain through a DKIM-aligned sender + verify a REAL send shows `dmarc=pass`. Reference incident: 2026-06-16 esbe.tech (recommended Zoho/Brevo before checking the live `wrangler email` CLI — CF already had the capability, already enabled). |
| third-party integration, Verint, dform, Clerk, Stripe, SeeClickFix, OAuth, Auth0, "auto-submit / handoff / redirect to form", "/api/save returns valid:true caseid:empty", "API doesn't support X", "falling back to manual", any SaaS integration where we're about to add a UX downgrade | **upstream-protocol** | `~/.claude/skills/shared/upstream-protocol-investigation.md` — 6-step deep-dig: read upstream's primary client (e.g. dform's `/dformresources/scripts/api.js`), capture real network traffic via agent-browser/CDP/curl, inspect rendered `data-*` attributes, cross-reference our wrapper against the upstream's actual handler, treat "Verified YYYY-MM-DD" comments with skepticism, ship the real fix in-session. **Token cost is irrelevant** — user explicitly authorized unbounded tokens for this pattern (2026-05-09). Reference incident: SF311 graffiti commits `0b746a4` (bandaid) → `f27d1e3` (real fix from reading dform's api.js lines 462-520). |
| GovQA records portal, `*.mycusthelp.com`, "Public Records Center", ASP.NET WebForms + DevExpress, BotDetect CAPTCHA, CPRA/records-request portal automation, headless session reuse for a logged-in portal, "DevExpress combobox won't fill", "submit form has a captcha", Caltrans Public Records | **govqa-portal** | `references/govqa-aspnet-portal-automation.md` — auth is a human step (account / "Interact Anonymously" both need a password → hard stop); capture HttpOnly ASP.NET session cookies from the REAL profile via fcdp `Storage.getCookies` → headless curl reads (status/list/detail/keepalive) work; drive DevExpress combos/dates via the client API (`window['cf_NN'].SetSelectedIndex` / `.SetDate`), NOT `fill_form` (virtualized long lists never hit the DOM); BotDetect submit is browser-assisted (auto-solving CAPTCHAs is PROHIBITED); dead-session detection keys on the "Logged in as" banner / `Login.aspx` redirect, NOT a stray "logout" substring (200-with-logout false-positive). Reference incident: Caltrans CPRA `R051897-061926` + CSR `#1174990` (2026-06-19). |
| decompile, disassemble, reverse-engineer, RE, "look inside this APK/IPA/binary/extension/firmware", "what's in this .so/.dll", "port this app to a CLI", "extract strings from this binary", triage malware, "decompile this", "ghidra", "jadx", binary diff between two firmware versions, BLE protocol RE from companion app | **decompile** | invoke the `/decompile` skill (formerly `/ghidra`, renamed 2026-05-28). Routes to the right tool per artifact class: `jadx`/`apktool`/`apkeep` for Android, `ipsw`/`otool` for iOS, `cfr-decompiler` for JVM, `prettier`/`webcrack` for browser extensions, `binwalk` for firmware, `hermes-dec` for React Native, `decompyle3` for Python, `wasm2wat` for WebAssembly, Ghidra for native/PE/raw firmware. Tool inventory + routing table lives in `~/.claude/skills/decompile/SKILL.md`. Reference incident: Whoop RE 2026-05-28 — correctly routed to `jadx` (not Ghidra) because Whoop's Android app is Java/Kotlin; 22 min to find 3 GATT service families including previously-undocumented Whoop 5.0/MG family. |
| watcher, cron, poller, webhook, diff against state, signal-emitting, alert-on-change, state-file dedup, `seen_X: set`, `if id in seen`, status transitions, va-watch, va-supervisor | **signal-logic-audit** | `~/.claude/skills/shared/signal-logic-audit.md` — 12 anti-patterns for diff/poller/cron code: pre-finalized-as-terminal, set-based-dedup-misses-flip-back, deadline-without-expiry-probe, ID-only-dedup-ignores-status, no-allowlist-for-benign-novel, upstream-permissive-needs-business-rules, opaque-IDs-as-keys, forward-only-diff, ID-only-ignores-version, population-wide-as-individual, unbounded-state, upstream-permissive-needs-policy-gate. Grep each smell against the changed file; fix every match in the same pass (fix-all rule). Reference incident: 2026-05-13 — 11 bugs in `~/tools/va-watchers/va-watch.py`, each an instance of one of these 12 patterns. |
| Hono framework, "make it Hono", "convert/remake to Hono", "Hono site", Hono SSR, `@hono/jsx`, `hono/jsx`, `hono/jsx/dom`, islands/hydration, new site on Cloudflare Workers, React-SPA → Hono SSR migration, server-render an existing SPA | **hono** | invoke the `/hono` skill (`~/.claude/skills/hono/SKILL.md`) — full-leverage Hono reference: core routing/Context/middleware (`core-routing-middleware.md`), server JSX SSR (`ssr-jsx.md`, `hono/jsx` + `html` helper + `jsxRenderer`), client islands (`client-islands.md`, `hono/jsx/dom` + `render()`/`useState`, mounting D3/Leaflet without React), Cloudflare Workers + dual server/client Vite build (`cloudflare-workers-vite.md`), and the page-by-page React-SPA→Hono migration playbook (`react-spa-to-hono-migration.md`). All import paths/APIs verified against hono.dev 2026-06-04. Hard rule: never mix `hono/jsx` (server) and `hono/jsx/dom` (client) in one module; verify any unfamiliar Hono API against live docs before using it (memory-invented middleware/hooks are the #1 failure mode). |
| build on Cloudflare, Cloudflare Workers, Pages, Durable Objects, R2, KV, D1, Queues, Workers AI, Vectorize, AI Gateway, Wrangler, Cloudflare One / Zero Trust, "build an MCP server on Workers", "build an agent on Workers", Agents SDK, Sandbox SDK, Turnstile | **cloudflare-build** — invoke the **cloudflare plugin** (official Apache-2.0, marketplace `cloudflare/skills`; `claude plugin details cloudflare@cloudflare`): its 11 skills auto-load by description (`agents-sdk`, `cloudflare`, `cloudflare-email-service`, `cloudflare-one`, `cloudflare-one-migrations`, `durable-objects`, `sandbox-sdk`, `turnstile-spin`, `web-perf`, `workers-best-practices`, `wrangler`), plus the `/cloudflare:build-agent` and `/cloudflare:build-mcp` commands and 5 remote CF MCP servers (`cloudflare-docs`, `-bindings`, `-builds`, `-observability`, `-api`). This **COMPLEMENTS** the "Cloudflare API Access (MCP)" section below (which is for raw API calls) — the plugin is for BUILDING on Cloudflare. Deploying still belongs to /ship. **For deploying a Cloudflare _Container_ from this Docker-free Mac (apple/container only)** — build linux/amd64 with apple/container, push to the CF registry with **crane** (CF registry is HTTP Basic auth, credential needs `--push --pull`), run the image **non-root**: see `references/cloudflare-containers-no-docker.md` (verified `claude-worker` build 2026-06-28). | cloudflare plugin (skills auto-load; verify with `claude plugin list`) + `references/cloudflare-containers-no-docker.md` |
| Workers Cache, `cache.enabled`, "enable caching on my Worker", cf-cache-status wrong/HIT on authed route, per-user data served to the wrong user after enabling cache, heuristic caching, cross-user cache leak, `ctx.cache.purge`, Cache-Tag, cross_version_cache, "should I turn on the new CF cache" | **workers-cache** | `~/.claude/skills/shared/workers-cache-safety.md` — THE leak class: with `cache.enabled:true`, CF heuristically caches any 200 with NO Cache-Control for 2h, and cookie-authed requests (Clerk `__session` etc.) do NOT trigger the Authorization auto-bypass → cross-user leak. Safe-enable recipe: fail-safe default `private, no-store` (Hono post-next middleware / json() helper), public routes opt in explicitly, wrangler ≥4.69 or the flag is SILENTLY ignored. Gate: `~/.claude/skills/ship/tools/workers-cache-check.sh <repo>` (also /ship Phase -0.4). Re-verify facts against developers.cloudflare.com/workers/cache/configuration/ — the surface is new (2026-07). Reference near-miss: 2026-07-06 AIVA (~150 cookie-authed no-header GET routes almost blanket-enabled). **ALSO the scheme-presentation OUTAGE class** (sitewide 301 loop / `ERR_TOO_MANY_REDIRECTS` right after enabling cache, HSTS disappeared, worker sees `http://` while cf-visitor says https): the cache layer presents `http://` in request.url for HTTPS visitors — any `url.protocol === "http:"` canonicalize 301-loops the site (2026-07-06 exampleapp, ~25 min down) and `url.protocol === "https:"`-gated HSTS silently drops. One-probe diagnosis: `wrangler tail --format json` → `event.request.url` scheme. Fix: cf-visitor-derived scheme (`visitorIsHttps()`, AIVA `src/worker/middleware/securityHeaders.ts`), never url.protocol. Propagation rule: enable/disable takes >30s — never conclude from a <60s check. Carmack PREPARES the config+code and must see the gate PASS locally; the staged enable+verify deploy belongs to /ship (Phase 4.08). |
| assess the logs, clean up the logs, log hygiene, observability pass, "improve log output", "why are these errors so vague", prune log noise, superfluous log entries, add debug attributes, audit the logs of `<service>`, last-24h log review | **log-hygiene** — invoke the `/log-hygiene` skill (`~/.claude/skills/log-hygiene/SKILL.md`): the PROACTIVE loop (ingest last-N hours from a real source → cluster by stable event → rewrite ambiguous errors to actionable, downgrade noise NEVER delete, add the attribute that names silent failures → report, then apply if asked). This is distinct from the reactive instrument-on-build / instrument-on-fix rule in Hard Rules (which fires automatically while building/fixing) — this mode is when the user explicitly wants a log *assessment* pass over a window of real logs. Ground-truth: count from the source, never fabricate volume. | `/log-hygiene` skill + `~/.claude/skills/shared/observability-instrumentation.md` |

**Additional context (load when applicable):**
- **For ANY new-site build, or any "convert/remake to Hono" / Hono SSR / React-SPA → Hono work** (feature, plan, OR deploy mode): load the `/hono` skill (`~/.claude/skills/hono/SKILL.md`) and the relevant `references/*.md`. It is the source of truth for `hono/jsx` (server SSR) vs `hono/jsx/dom` (interactive islands), the dual client/server Vite build on Cloudflare Workers, and the page-by-page SPA→Hono migration (convert one route at a time, curl each SSR page, keep the build green). Don't invent Hono middleware/hook names from memory — the skill's references are verified against hono.dev and tell you what actually exists.
- If working in an AIVA project (cwd contains "aiva" or project references example.com): also read `aiva-guidelines.md` — and note AIVA ships an iOS Capacitor surface from the same repo (`~/AIVA-Frontend/docs/mobile-ota.md`): web changes are OTA-synced to the app by ship.sh, so client-code changes must respect the app invariants (native fetch shim, isNativeApp() webview-detector short-circuit, notifyAppReady).
- **For ANY iOS/macOS app work** (Xcode project, simulator, Swift, Capacitor shell): load the `/ios` skill as the phase playbook — it owns the build/run/debug loop (xcodebuildmcp), crash + perf triage (axiom agents), webview driving (axe), and compliance scanning; /carmack supplies the investigation discipline on top.
- For all modes except research/browser: also read `preflight-checks.md`
- **For ALL modes**: also read `~/.claude/skills/shared/ant-verification-protocol.md` (ant-level quality gates)
- **For ALL modes**: also read `~/.claude/skills/shared/tool-error-recovery.md` (catalog of tool errors and recovery patterns — consult on any tool failure, and APPEND a new entry whenever you hit a novel one)
- **For ALL modes**: run `~/.claude/skills/carmack/tools/scan-tool-errors.sh` once when invoked. If it prints novel patterns, read `~/.claude/tool-errors-pending.md`, classify each, append entries to `tool-error-recovery.md`, then run the scanner with `--clear` to archive the log. This keeps the error catalog self-updating.
- **For ANY infra/config/plugin/service work**: always read `blind-spots.md` — covers schema-validation-before-restart, self-upgrade traps, "gateway started ≠ working", compaction telemetry, adjacent-system breakage, guardrail-alert-vs-enforcement patterns learned from real incidents
- **For ANY conclusion drawn from a cloud/provider management API — and ALWAYS before recommending a deletion, a cleanup, or reporting something "missing"**: load `~/.claude/skills/shared/management-api-vs-authoritative-state.md` (Pattern #31). A management API tells you what was *declared*; it does not tell you what the platform *added on your behalf*, nor *why* a resource exists — so it is a hypothesis, not ground truth. Probe the consumer view (`dig` for DNS, `openssl s_client` for the served cert, `PRAGMA table_info --remote` for schema, `wrangler secret list` for bindings, a delivered message's `Authentication-Results` for mail auth, cache-busted `curl` for deployed code) and establish provenance from the audit log (`actor.type`: `user` vs `system`) **before** concluding "absent" or "redundant". Reference incidents (2026-07-28, both wrong on the first pass): CF `dns_records` showed 5 CAA records with no `issuewild "pki.goog"` while `dig` showed 11 including it (CF auto-injects partner-CA CAA, invisible to the API) → a phantom renewal outage; and 20 "redundant" advanced cert packs turned out to be Worker custom-domain certs (8 packs ↔ 8 Worker domains; 11 zones with 0 Workers had 0 packs) → the recommended cleanup would have dropped TLS on every live Worker subdomain. This is the infra instance of the Ground-Truth Standard and the sibling of `installed-source-ground-truth.md` (deps), `d1-schema-drift.md` (#26, schema), and `email-deliverability-dmarc.md` (mail).
- **For ANY change to an HTTP route handler, a `scheduled()`/cron body, a cache (read or write/warm), or a SQL/D1 query** (in feature, debug, review, OR deploy mode): run the **Hot-Path Data-Volume & Cache-Topology Audit** (section in `debug-patterns.md`). Three quick checks: (1) every query that runs *before the response* must be bounded (`LIMIT`/indexed range/fixed-cardinality `GROUP BY`) or cache-served — measure any `COUNT(*)`/`SUM(CASE...)`/whole-partition aggregate over `WHERE <partition_key>=?` with `npx wrangler d1 execute <DB> --remote --json --command "..."` → `meta.rows_read`; >~100k on a per-request path is a bug, even if it predates your change (fix-all rule). (2) For every `readCached*`/`KV.get`/`caches.match`, `grep` for the *writer* of that exact key; for every `prewarm*`/cache-warmer, `grep` for what *reads* those keys — a reader with no writer (or a warmer warming a different key-shape than the route reads) is a latent perf bug. (3) `WHERE ts >= now() - <interval>` against a lagged source returns empty — anchor on `MAX(ts)`. This is the lesson from the 2026-05-12 improvebayarea incident (`coverageForCity` scanned 8.6M rows on every request; the cron warmed `oak311:open_data:...` but the route read `agg:...`; the 24h window was `now()`-anchored against DataSF's 1-2-day-lagged data) — three round-trips that this audit collapses to one.
- **For ANY new subsystem build OR any bug fix** (feature, debug, OR review mode): load `~/.claude/skills/shared/observability-instrumentation.md` and apply both behaviors before declaring done — **instrument-on-build** (structured logs at external calls / catch branches / state transitions / the branch-deciding input — boundaries and decision points, not everywhere; redact secrets/PII) and **instrument-on-fix** (add the one attribute/message that would have named *this* bug in 30s). Rewrite ambiguous errors to actionable (attempted + actual values + likely cause/branch + disambiguation); reduce noise by *downgrading* level, never deleting. The proactive, scheduled counterpart is the `/log-hygiene` skill (assess last-24h logs on a cadence).
- **For Clerk/auth cutovers on Cloudflare Workers**: verify both provider state and effective Worker bindings. `clerk env pull` is not enough; dry-run Wrangler and live HTML must prove no `pk_test`, `sk_test`, or `.accounts.dev`.
- **For external city form integrations**: a 500 after category change may be category/form-specific, not global auth/photo failure. Reproduce against the failing category and a known-good category, then add fallback plus regression coverage.
- **For ANY production-deployed site work** (not just security mode): also load `~/.claude/skills/shared/site-security-defaults.md` — the 12-item baseline catches gaps Cloudflare Security Center alerts on, with copy-paste auto-fix recipes for Workers / Next.js / static. Skip only when working purely on internal CLI/non-HTTP code.
- **For ANY npm/Node project, OR any "fix the Dependabot/security page / npm audit" request** (debug, review, deploy, OR infra mode): load `~/.claude/skills/shared/dependency-audit.md` and run its 7-step protocol. Traps it encodes (each bit us once): Dependabot and `npm audit` surface DIFFERENT vulns — run BOTH and fix the union; every sub-app manifest has its own lockfile (`find . -name package-lock.json -not -path '*/node_modules/*'` — scan all); an existing override floor can itself be vulnerable (`ws ^8.20.1` was still `<8.21.0`); a blanket override across majors breaks non-vulnerable consumers — SCOPE it to the parent (`"replace": { "minimatch": "^3.1.4" }`) and confirm glob's v8/v10 stay put; verify the patched version is published (`npm view <pkg>@<v> version`) before writing it; `npm audit fix --force` will downgrade a major runtime dep — never run it blind. Verify build with the project's REAL build (Workers → `wrangler deploy --dry-run`, lib → `tsc --noEmit`) + one `vitest run`. Reference: 2026-06-15 improvebayarea (12 alerts + ws/vite, PR #5).
- **For ANY site that renders external links** (help pages, resource lists, footers, "official forms" links): before declaring done, run `~/tools/linkcheck.sh <repo>` to prove every external `href` resolves to HTTP 200. It curls each link and, on any non-200, re-tests via the REAL Chrome profile (fcdp) — so a real 404/410 BLOCKS and gets the URL fixed, while a government/WAF bot-block of curl (403/000 but 200 in a browser) is correctly passed. **Never trust a "URLs are used EXACTLY as provided — do not alter" comment** — that exact comment guarded a malformed 403 POA link on the NYIA portal `/help` (2026-06-05). Verify, don't assume. Pairs with /ship Phase 1.45d.
- **For ANY third-party integration work where the proposed fix involves a UX downgrade** (handoff, redirect, manual step, "for safety"): always load `~/.claude/skills/shared/upstream-protocol-investigation.md` and run Steps 1–3 (read upstream's primary client, capture real network traffic, inspect rendered data-attributes) BEFORE shipping the downgrade. Token cost is unlimited for this. Reference incident: SF311 `0b746a4` (bandaid based on a wrong "verified today" comment) → `f27d1e3` (real fix from reading dform's `api.js` lines 462–520). Treat any "Verified YYYY-MM-DD that X can't be done" comment in our codebase as a hypothesis to re-verify, not a fact.
- **For ANY change to a React component that renders fetched/API data, ANY backend handler whose JSON shape the frontend destructures, OR ANY admin/dashboard/detail-page audit** (feature, debug, OR review mode): always load `~/.claude/skills/shared/undefined-null-render-safety.md` and run its 9-pattern undefined/null-render sweep (null-gate-hides-UI, unguarded property access, `.map`/string/`Date` on possibly-undefined, JSON.parse, raw-undefined render, missing loading/empty states, backend omits a field) + the live DOM check (drive the logged-in REAL Chrome (fcdp), grep `document.body.innerText` for rendered `undefined`/`NaN`/`Invalid Date`/`[object Object]` and capture console `TypeError`s). Fix every real instance in the same pass (fix-all). TypeScript does NOT catch these when the response is typed `any`/`unknown`/`Record<string, unknown>`. Reference incident: 2026-06-01 — AIVA shipped four instances (admin clients LIMIT-truncation, `MAX(NULL)` sort burial, Dashboard 20-of-457 docs, the `isTest !== null` toggle that silently vanished); codified so the next render-data change catches all nine in one pass.
- **For ANY TypeScript authored or reviewed** (feature, debug, OR review mode): load `~/.claude/skills/shared/anti-slop-typescript.md` and run `~/.claude/skills/carmack/tools/detect-ts-slop.sh [path|--diff <base>]`. Never default to a generic `isRecord`/`isObject` guard or a blanket `as any`/`as unknown as T` — define a named type, a discriminated union, or a Zod schema (`type X = z.infer<typeof Schema>`) at the trust boundary, and write a targeted predicate only as a last resort. Fix every detector hit in the same pass (fix-all). This is the runtime-guard sibling of the No-Suppression Rule and the upstream cause of the undefined/null-render bug class.
- **For ANY watcher / cron / poller / webhook / diff-against-state code** (debug, review, OR feature mode): always load `~/.claude/skills/shared/signal-logic-audit.md` and run its 12-pattern checklist against the changed code. Grep each pattern's smell, classify matches as real-instance vs deliberate-and-correct, and fix every real instance in the same pass (fix-all rule). The 12 patterns: pre-finalized-as-terminal, set-based-dedup-misses-flip-back, deadline-without-expiry-probe, first-seen-ID-ignores-status, no-allowlist-for-benign-novel, upstream-permissive-needs-business-rules, opaque-IDs-as-keys, forward-only-diff, ID-only-ignores-version, population-wide-as-individual, unbounded-state-no-TTL, upstream-permissive-needs-policy-gate. Reference incident: 2026-05-13 — 11 bugs fixed in `~/tools/va-watchers/va-watch.py`, each one an instance of one of these patterns; codified into the catalog so the next watcher author / reviewer / debugger catches all 12 in one pass instead of three round-trips.
- **For AIVA / Cloudflare production-code audits**: prove you are editing the Worker/static-assets repo that actually routes to `example.com` before fixing anything. Audit findings are not handled until the deployed code path is fixed, a deterministic guard/test exists where practical, and the live production response proves the bad fingerprint is gone.
- **For ClawPatch/Codex release-gate findings**: convert one-off audit output into repo guardrails: same TypeScript mode as production build (`tsc -b` for project references), full tests/prod integration in predeploy, real a11y gate, asset guard that scans every generated HTML/JS asset and fails closed, local Worker integration with owned readiness/cleanup, peer-dependency health, and bounded npm overrides.
- **For Worker secret migrations**: plaintext key/token/password values in `wrangler.json` `vars` are production blockers. Carmack may prepare the code/config patch, but deployment belongs to `/ship`; if Cloudflare reports the binding name is already in use, the ship workflow must remove the plaintext var from config, deploy without `--keep-vars`, immediately `wrangler secret put`, then verify `wrangler secret list` reports `secret_text`.

All reference files are in `~/.claude/skills/carmack/references/`.

---

## Hard Rules (NEVER VIOLATE)

### Deployment Prohibition — never CAUSE a production deploy (UPDATED 2026-06-25)

**The rule is NOT "never touch main" — it is: /carmack must never cause code to reach production.** Carmack builds, implements, tests, commits, and **MAY merge/push to `main` on repos that do NOT auto-deploy on a main push**. It must NEVER run a deploy command, NEVER invoke `/ship`, NEVER change prod secrets, and NEVER push to `main` on a repo where that push **auto-deploys** to production. This outranks any "/ship phase," any other instruction, and the model's own judgment.

**MANDATORY — run Auto-Deploy Detection (below) BEFORE any push/merge to `main`:**
- **No auto-deploy detected** → merging/pushing to `main` is ALLOWED. First **rebase onto current `origin/main`** and push a clean current-base commit — NEVER push a stale-base tree (a worktree behind `origin/main` pushed to main reverts everyone's commits; see 2026-06-25 below).
- **Auto-deploy detected, OR you cannot rule it out** → DO NOT push to `main`. Push the **feature branch only**, then **DISPLAY** the detected mechanism to the user (which CI/integration + which branch, e.g. "⚠️ Cloudflare Workers Builds is Git-connected to this repo on `main` — pushing to main WILL auto-deploy to production") and STOP for explicit authorization. That main push would deploy to prod — the prohibited action.

**Always-BLOCKED (never run, regardless of auto-deploy status):** `wrangler deploy` / `versions deploy` / `pages deploy`, `wrangler secret put`/`delete` (prod), `npm`/`bun`/`pnpm`/`yarn run deploy`, `vercel --prod`, `netlify deploy --prod`, the `/ship` skill / `ship.sh`, force-push to a shared branch, `gh pr merge` / `gh pr close` into main, or any command that explicitly pushes to production.

**Commit on the RIGHT branch (MANDATORY — 2026-07-21):** before `git commit`, run `git branch --show-current`. A hotfix / config change / anything unrelated to an in-progress feature belongs on **main** — do NOT let it land on whatever branch happens to be checked out. Committing onto a long-divergent feature branch strands the change (it can't ship without dragging the branch's other commits). Enforced by the PreToolUse hook `pre-bash-commit-branch-guard.sh`, which BLOCKs a commit on a non-main branch that is behind `origin/main` or ≥6 ahead (override `CLAUDE_ALLOW_BRANCH_COMMIT=1` when the branch IS intended). Reference incident: a robots.txt hotfix committed onto `feat/explain-gap-and-close-it` (11 ahead of main) → needed a cherry-pick + full branch reconciliation to ship.

#### Auto-Deploy Detection (run before any main push — if ambiguous, assume YES = don't push, display, ask)
A repo auto-deploys on a main push if ANY of these holds:
1. **GitHub Actions** — read **`origin/main`** workflows, NOT the local checkout (a behind worktree shows stale/deleted workflows — this misled the 2026-06-25 session, which grepped a 375-behind tree). Broad pattern (must catch `cloudflare/wrangler-action`/`pages-action`, which contain no literal "wrangler deploy"):
   `git fetch -q origin; for f in $(git ls-tree -r --name-only origin/main .github/workflows/); do git show "origin/main:$f" | grep -qiE 'wrangler-action|pages-action|wrangler (deploy|pages)|CLOUDFLARE_API_TOKEN|command:\s*(deploy|pages)|run deploy|vercel|netlify deploy|actions/deploy-pages' && echo "$f"; done`
   then confirm a hit's `on:`/`branches:` includes main. **Empirical cross-check (most reliable):** `gh workflow list --repo <o/r>` and `gh run list --repo <o/r> --limit 10` — did a deploy run actually fire on a recent main push? (A `workflow_run: ["Deploy"]` reference can be orphaned — confirm the workflow is registered AND runs.)
2. **Cloudflare Pages / Workers Builds Git integration** — NOT visible in the repo; query the CF API with `~/.cloudflared/cf-global-api-key.json`. **Match the prod DOMAIN, not just a project name** (exampleapp had two `*.pages.dev` projects named `aiva*` that were red herrings — not Git-connected, wrong domain). Pages: `GET /accounts/{acct}/pages/projects/<name>` → auto-deploy only if `source.type` is `github`/`gitlab` with a `production_branch`; a null `source` / `ad_hoc` trigger is NOT auto-deploy. Workers Builds: the live worker's latest version annotation `workers/triggered_by` is `build` for a Build vs `version_upload` for a plain `wrangler deploy`; `builds/triggers` → 404 ⇒ no Build connected.
3. **Vercel** (`.vercel/project.json`), **Netlify** (`netlify.toml` + linked site), or any connected CI (Render/Fly/Railway/Amplify) with a production-branch deploy hook.

**Blind spot — state it, don't fake coverage:** the checks above only find *platform* auto-deploy. A team can deploy `main` via a manual/CLI `wrangler deploy` or an off-platform cron/watcher the APIs can't see (this is how exampleapp actually ships — bursty `version_upload` deploys by the owner). So "no auto-deploy detected" means *the push itself won't trigger prod* — NOT that main is decoupled from prod. Treat main as deployable: only push correct, current-base code. If you can't rule out an external deployer, ASK the user rather than assert.

The `/ship` skill performs and DISPLAYS this same detection — see `~/.claude/skills/ship/references/pre-deploy-checks.md` (Auto-Deploy Surface).

**The carmack-mode-engineer SUBAGENT carries the same prohibition** in its agent definition (`~/.claude/agents/carmack-mode-engineer.md`, top of body) — both layers must stay in sync.

**Why (2026-03-26, reinforced 2026-06-23/24):** Carmack first deployed via `wrangler deploy` without asking. Then on 2026-06-23/24 a carmack-mode-engineer subagent ran ~22 hours autonomously, deployed to prod **6+ times** via `wrangler deploy`/`/ship` with no authorization, deleted a prod secret, removed features the user said to keep, and merged to `main` — because the prohibition lived only here (skill) and not in the agent body, and was rationalized as "/ship phases." Both layers are now hardened; deploying/merging is the USER's job in the main session. **Refined 2026-06-25:** the blanket "never main" was relaxed to "never CAUSE a deploy." The triggering session is a cautionary tale about *claiming a deploy mechanism without verifying it* — the agent asserted twice (first "main doesn't deploy," then "Cloudflare Workers Builds auto-deployed it") and **both were wrong**. Ground-truth (CF API + `gh`): example.com has NO platform auto-deploy — no Deploy GH-Actions workflow, CF Pages not Git-connected, no Workers Builds trigger; the change reached prod via a **manual/CLI `wrangler deploy`** ~6 min later. Lessons baked into the detection below: (a) **verify, don't assert** the deploy path; (b) detection must read `origin/main` workflows + `gh run list`, not a possibly-stale local checkout; (c) platform-auto-deploy detection is necessary but **NOT sufficient** — a team that deploys main via CLI means "no auto-deploy detected" still implies main→prod soon by hand, so only ever push correct, current-`origin/main`-based code; (d) the same session nearly pushed a 375-behind worktree to main — hence the rebase requirement.

### Premise-Check Before Debugging (MANDATORY — 2026-06-13)

**Before you debug, optimize, or "make X work," validate that X is the RIGHT approach for this runtime/SDK/platform — against LIVE upstream docs, NOT a cached `/skill` note. Debugging a wrong approach thoroughly is the most expensive way to fail.** Full rule: `~/.claude/skills/shared/premise-check.md`.

Run the **two-question gate before the first fix**: (1) Is this approach valid for THIS SDK/platform? Check the upstream's *current* capability matrix — the browser SDK ≠ native SDK ≠ server SDK; a strategy/option/API documented under one is often absent or forbidden in another. If every doc/example for the thing you want sits under a *different* platform than yours, that's the answer — stop. (2) What's the cheapest probe (curl / grep the installed bundle / read the doc's "supported platforms" line) that proves it's even possible here? Do it before coding, not after the 3rd failed fix.

**Mutating-symptom tripwire:** if each fix *changes* the error instead of removing it (`authorization_invalid` → `native_api_disabled` → `origin_..._conflict`), halt on the **2nd** mutation and re-verify the premise against live docs — you're debugging a wrong approach, not nearing done.

**Docs-before-note (always):** a `/skill` recipe, comment, memory, or prior conclusion is a HYPOTHESIS. Re-verify any load-bearing "API/SDK can/can't do X" claim against the upstream's own current docs/source before building on it; the live source wins and you fix the stale note in the same pass.

**Why (2026-06-13):** the Clerk-native-Apple saga — hours making `oauth_token_apple` work from a Capacitor webview when Clerk's docs put that strategy under Expo/RN only and clerk-js (browser SDK) can never send it (browser-forced `Origin` vs Native-API `Authorization`). A wrong `/ios` trap #4 note was trusted as fact; the working web-OAuth fix was a 5-minute live-doc read away. Now enforced session-wide by the SessionStart hook `premise-check-session-start.sh`.

### Installed-Source Ground-Truth Guard (MANDATORY — 2026-06-12)

**Before proposing ANY fix/config/workaround for a dependency, plugin, framework, or third-party widget, read the actually-installed source first** — full protocol in `~/.claude/skills/shared/installed-source-ground-truth.md`. Order: (1) `node_modules/<pkg>` types + JSDoc for exact option semantics; (2) the plugin's native platform implementation (`ios/Sources/*.swift`, `android/src/**`) when platform support matters — a TS type does not prove your platform implements it; (3) runtime DOM/traffic probes for third-party widgets — never patch an assumed DOM. Cite what you read (file + symbol) in the fix. Reference incident (2026-06-12): `overlaysWebView` was "known" to be Android-only — reading the installed `StatusBarPlugin.swift` proved iOS support, which was the one clean fix after three failed CSS-cascade workarounds; the `contentInset` JSDoc prevented shipping a fix that physically couldn't work.

### Reverse-Engineering Pre-flight (MANDATORY — 2026-05-08)

Before ANY integration work where you'd reach for `jadx`, `apktool`, `frida`, or "I'll just import this RE'd library on disk":

1. **Climb the API ladder in order:**
   - Rung 1: public docs (Open311, OData, vendor REST docs)
   - Rung 2: unauth-probe first-party endpoints (open the real site in Chrome, DevTools→Network, capture the real form submission)
   - Rung 3: RE the official thin client
   - Rung 4: RE a third-party client
   - Rung 5: browser automation
   - **Stop at the first rung that works.** Document why earlier rungs didn't.

2. **Before importing a found RE'd library on disk:**
   - Capture the official client's network traffic for the SAME operation (DevTools→Network preserve log, or mitmproxy)
   - Count requests. If the library makes fewer than the real client, the library is incomplete.
   - `null` and empty-string return fields are red flags, not features. `valid: true, resource_id: null` means *"validated, never finalized"*, not *"async assignment, trust the doc-comment."*
   - Look for "post-save" / "finalize" / "complete" calls the library may have missed.

3. **TOS posture preference (always):**
   - First-party documented public API > unauth-probe of first-party site > RE'd official client > RE'd third-party client
   - Never ship production code that depends on a static API key lifted from someone else's APK if a first-party path exists.

4. **A decompiled string/symbol is NOT proof of runtime use.** A function name, GraphQL operation, endpoint, or channel that appears in an APK's JS bundle or `strings` output proves the app *can* reference it — never that it *does* at runtime. Before building or extending an integration on a found symbol, confirm the real client actually invokes it: capture live traffic (mitmproxy / CDP) and watch for it. Reference incident (2026-05-19): `TicketChangeSubscription` existed only as a string in the SF311 APK bundle; `spotmobile_cable.ts` (~2,500 lines) plus four successive bug-fix layers were spent making a WebSocket reach a `/cable` endpoint — then a live mitm capture of the real app proved it opens **zero** WebSockets and resolves the value by HTTP/2 polling. The string was capability, never usage.

5. **Android-app mitm — hard-won operational notes:** runtime `settings put global http_proxy` and the `-http-proxy` boot flag are both unreliable on the Android 14 emulator — apps ignore them. What works: a rooted (`google_apis`, not `google_apis_playstore`) AVD + mitmproxy in regular mode (force-stop the app so it re-reads the proxy), OR a rooted `iptables` transparent redirect. Android 14 moved the trust store off `/system/etc/security/cacerts/` — the mitm CA must be bind-mounted into the conscrypt APEX cacerts via `nsenter` into zygote's mount namespace. Frida unpinning is usually still needed on top.

**Reference incident:** `feedback_first_party_api_first.md`, `feedback_capture_traffic_before_extending.md`. SF311 RE failure 2026-05-08 — I jumped to APK reverse-engineering, missed `/api/custom` post-save hooks, shipped a partial submitter; Codex went first-party + captured traffic, shipped clean. Codex's was correct.

### Browser Cookies for Non-Browser Tools (curl / yt-dlp / scrape / n8n)

When code or scripts need cookies from a logged-in browser session, pick by where the session lives — do **not** spawn a separate browser (unbrowse / agent-browser) hoping it has the session, it won't:

| Session location | Tool | Output |
|---|---|---|
| Live REAL Chrome (fcdp-driven) | `~/tools/fcdp/fcdp raw Network.getCookies '{"urls":[…]}'` | Includes session-only cookies not yet flushed to SQLite. No Keychain prompt. |
| Regular Chrome (`~/Library/Application Support/Google/Chrome/Default`) | `~/tools/cookies-txt <url>` | Reads SQLite + Keychain. Headless-safe, cron-safe. |
| Brave / Edge / Chromium | `~/tools/cookies-txt --browser brave\|edge\|chromium <url>` | Same code, different Keychain entry. |
| Any browser, yt-dlp only target | `yt-dlp --cookies-from-browser chrome:Default <url>` | Bypasses the question entirely. |

`~/tools/cookies-txt` is a Python port of the "Get cookies.txt LOCALLY" Chrome extension (source unpacked at `~/re/cookies-txt-locally/`). Three formats: `netscape` (default), `json`, `header` (`name=value; …`). Exit codes: `3` no DB, `4` Keychain miss, `5` decrypt failure.

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

When porting any browser-extension behavior to a CLI, see the **`/decompile` skill's "Browser extension" workflow** (renamed from `/ghidra` on 2026-05-28; the skill is now a universal RE router covering APKs, IPAs, .NET, Hermes, WASM, firmware, browser extensions, etc.). Ghidra itself is the wrong tool for extensions (no compiled code), but the skill routes you to the right JS toolkit (`prettier`, `webcrack`, etc.). For ANY reverse-engineering task — decompile, disassemble, "look inside this binary/app/firmware" — invoke `/decompile` first; it handles tool routing.

### Test Safety (CRITICAL)

Vitest fork workers leak ~5GB memory each when they hang:

1. **ALWAYS** wrap test commands: `timeout 120 npx vitest run src/specific/test.ts 2>&1`
2. **NEVER** run full test suite (`npm test`, `npx vitest run` with no args)
3. **Maximum 3 test runs** per investigation phase
4. **Clean up**: `pgrep -f vitest | xargs kill 2>/dev/null`

### Infrastructure Safety

- **NEVER** execute `terraform destroy`, `terraform apply -auto-approve`, `DROP TABLE/DATABASE`, or cloud CLI delete/terminate commands
- **NEVER** modify .tfstate files
- **ALWAYS** show `terraform plan` output and get approval before any `apply`
- Before ANY infra command: what resources are affected? Is it reversible? Could it affect unintended resources?
- **Worker preview hostnames are LOCKED by default (user policy 2026-07-07)** — never set `previews_enabled: true` (CF API) or `preview_urls: true` (wrangler config), and never share a `<name>.cloudflare.app` URL, without an explicit same-session user "yes" (AskUserQuestion; offer the Access-gated option first — CF supports Cloudflare Access on preview URLs). Preview hostnames bypass all zone security. Hook `pre-preview-lock-guard.sh` blocks the attempt; after user approval, prefix `CLAUDE_ALLOW_PREVIEW_PUBLIC=1`. The stop hook `preview-lock-stop-check.sh` re-sweeps after any deploy session; /ship Phases 4.09/4.05d re-lock on every ship.

### Post-Change Verification (MANDATORY — from internal VERIFICATION_AGENT pattern)

After implementing ANY code change:
1. **Read the changed file(s) back** — verify the edit was applied correctly
2. **If tests exist**, run them (with `timeout 120`)
3. **If the change affects a build**, run the build and confirm exit 0
4. **If the change is a bug fix**, verify the original symptom no longer reproduces
5. **If the change adds/modifies TRIGGERED behavior** (failover, retry, fallback chain, circuit-breaker, rate-limit cooldown, error/`catch` branch, conditional cron, feature-flag gate) — **induce the trigger and watch the behavior fire end-to-end on an isolated copy.** "Each component works in isolation" is NOT proof the behavior fires: "the fallback is configured" ≠ "the fallback fires." Force the 429 / kill the primary / trip the breaker / feed the bad input, confirm the right downstream component served, then confirm the live instance is untouched. Don't wait for the user to ask. See `~/.claude/skills/shared/no-lie-verification.md` **Check 6** (reference incident: 2026-06-19 Hermes 429→DeepSeek failover wired + each hop verified but never exercised until the user prompted; a forced-429 throwaway-config test then proved it).
6. **Never report "done" based on the edit alone** — verify the outcome with evidence

### Semantic Security Review Gate — LOOP UNTIL CLEAN (MANDATORY — 2026-07-22)

**Before declaring ANY implementation or fix "done", run the built-in `security-review` skill on the changeset and loop until it is clean.** This is AI/semantic dataflow analysis (SQL injection, XSS, SSRF, auth bypass, hardcoded secrets, business-logic flaws) — the vulnerability class that grep-based checks and `npm audit` cannot see, and that the carmack subagent's own review passes are not a substitute for.

**⚠️ OPERATIONAL (verified 2026-07-22):** `security-review` runs against the CURRENT WORKING DIRECTORY's git repo — NO path argument; hard-fails `"needs to run inside a git repository"` if cwd isn't the repo, so `cd <repo-root>` FIRST. It reviews the **COMMITTED** branch diff vs the base (merge-base with origin/main) — NOT uncommitted working-tree edits (proven: unstaged changes produce an empty diff). **So commit your fix before running this gate**, or it reviews nothing. It returns a markdown report (file:line, severity, category, confidence 1–10) and self-filters false positives at confidence ≥8 — a "real finding" = any HIGH/MEDIUM in that report. If the Skill call returns unknown-skill (unavailable in this environment), do NOT silently pass — tell the user the semantic gate couldn't run.

**The loop (do not skip, do not defer):**
1. `cd` into the repo root, then invoke the `security-review` skill (Skill tool) on the current branch diff/changeset.
2. Triage each finding: real vulnerability vs. genuine false positive.
3. **FIX every real finding in source, inline** — obey the No-Suppression Rule (never `@ts-ignore`/`eslint-disable`/`biome-ignore`/`as any` a finding away; refactor to remove the actual vulnerability).
4. Re-invoke `security-review`.
5. Repeat 1–4 until it reports **0 actionable findings**.

A genuine false positive is documented inline with its reason; everything else is fixed, never deferred (this composes with the Fix-All-Issues-Found Rule below). **Do NOT report the work complete while a real security finding is open.** Loop guard: if the same finding survives 5 fix attempts, STOP and surface it to the user with the finding + why the fix isn't landing — don't declare done past an unresolved vulnerability. The carmack subagent still NEVER deploys (Deployment Prohibition) — this gate makes the code security-clean before the user runs `/ship`, whose Phase 1.29 re-runs the same loop as the deploy-time backstop. Skip only for pure docs/comment/test-copy diffs with zero code change.

**A finding's PREMISE is a hypothesis too — measure it on THIS runtime before you
act on it (2026-08-03).** Findings routinely assert an engine/library behavior
("V8 embeds the input in that error", "this SDK throws", "that header is
forwarded"). Docs-before-note applies to the reviewer exactly as it applies to a
`/skill` comment. **Run the cheapest experiment that would falsify it** — usually
one `node -e` over the real failure inputs — *before* writing the fix.

Then take one of three dispositions, and **name which one in the code comment and
the commit** so the record is not overstated:

| Premise holds | → | fix it; it is a real vulnerability |
| Premise fails, mitigation is cheap | → | keep the change as **defense-in-depth**, and say plainly it closes no live leak — the value is not depending on an engine detail you neither chose nor control |
| Premise fails, mitigation is costly | → | do not implement; record the measurement that refutes it |

This is **not** licence to dismiss findings. The default is still "fix it"; the
bar to downgrade is a *reproducible measurement*, never an argument. A reviewer's
finding you cannot falsify is a finding you fix.

Reference incident: a review flagged that a `JSON.parse` SyntaxError could carry
cookie bytes into an error `detail` field. Testing five malformed shapes on the
actual runtime (Node 26 / V8) showed all produce positional messages only
(`"Unterminated string in JSON at position 70"`) — no input bytes, so no live
leak. The constant-string change shipped anyway as defense-in-depth, with the
comment and commit stating the measurement rather than implying a leak was
closed. Writing "fixed a token leak" there would have been a fabrication in the
permanent record.

### Instrument-Liveness + Discriminator-First (MANDATORY — 2026-08-03)

**An instrument that reports nothing is indistinguishable from a broken instrument until you prove otherwise.** Before ANY conclusion of the form "no events", "nothing logged", "the counter didn't move", "it isn't even being called" — prove the instrument was live in that window. Three real false-negatives from one session, each of which sent the investigation the wrong way:

- `wrangler tail` wrote **0 bytes** (never connected) → "no events" was vacuous. `wc -c` the capture first; require ≥1 unrelated event as proof of life.
- `wrangler tail --format json` emits **pretty-printed multi-line** objects, NOT JSONL → line-wise `grep`/`json.loads` silently match nothing. Parse with a concatenated-object decoder and fail loudly at 0 objects.
- **KV reads lag** (eventually consistent) — a counter read frozen for minutes, then jumped. Never conclude from a single read.

**And when a fix leaves the symptom BYTE-IDENTICAL: stop fixing, start discriminating.** That is Pattern #32 (`~/.claude/skills/shared/opaque-multi-cause-failure.md`), the static-error sibling of the mutating-symptom tripwire. Ship the one-line diagnostic that reports the measurable properties of what you sent (lengths + boolean flags — never the payload, it can carry user PII) BEFORE attempting fix N+1. When every property you encoded reads clean and it still fails, you have positively excluded your whole hypothesis space — that is the finding, and it is worth more than another guess.

Two bisect disciplines that belong with it: **change exactly ONE variable per probe** (if a probe flips fail→pass, ask what ELSE changed in that step — a confounded step attributes the pass to the wrong cause and ships a non-fix), and **cross-reference successes as hard as failures** (the cause is usually the property present in 100% of failures and 0% of successes). If the failure mode has no side effect, every failing probe against the real upstream is FREE — order expected-fails first, stop at the first success, and state that cost out loud before you start.

**Reference incident (2026-08-03, improvebayarea Solve SF):** one `400 {"error":"Invalid"}` covered FIVE independent causes (`//` sequence, astral/emoji char, two reserved phrases, length). Each single-cause fix looked like a non-fix, costing ~6 deploys. A confounded bisect step (removing a URL *also* cut 371→261 chars and dropped an emoji) sent the fix in the wrong direction for two of them. Shipping the properties-diagnostic ended it in one deploy.

### Fix-All-Issues-Found Rule (MANDATORY — 2026-04-12)

**When an audit/review/diagnostic step surfaces issues, FIX THEM — do not only report.** This overrides the "don't refactor beyond scope" global rule for issues uncovered during carmack's own investigations.

Triggers (non-exhaustive):
- `tsc --noEmit` reports errors → fix every error, even if unrelated to the task
- `biome check` reports lint errors or warnings → auto-fix with `--fix`, then resolve remaining manually
- `npm audit` reports vulnerabilities → apply overrides and verify
- Code review uncovers bugs in adjacent code → fix them
- Security sweep finds XSS/injection risks in files you didn't edit → fix them
- Build warnings → resolve, don't ignore

Behavior:
1. Enumerate every finding (count them, don't truncate)
2. Fix in batches, rebuilding / re-running the diagnostic after each batch
3. Loop until count reaches 0 OR a finding is genuinely not fixable (documented with reason)
4. Only then report "done" — and only after re-running the diagnostic one final time to confirm 0

**Escape hatches** (narrow):
- If fixing would require a breaking API change or major version upgrade → create a beads issue describing the blocker and continue with the rest
- If fixing is >10x the cost of the original task → pause, report the finding, ask the user before continuing
- "Pre-existing" is NOT a valid excuse. "Unrelated to my change" is NOT a valid excuse.

**Why (2026-04-12):** Session ended with 93 pre-existing `tsconfig.worker.json` TypeScript errors merely reported, not fixed. User set this as a permanent rule: if carmack sees it, carmack fixes it.

### No-Suppression Rule (MANDATORY — 2026-04-12)

**NEVER use `@ts-expect-error`, `@ts-ignore`, `// eslint-disable`, `// biome-ignore`, `// @ts-nocheck`, or equivalent suppressions as a "fix".** Suppressions hide bugs — they don't resolve them.

When a type-system complaint appears legitimate:
1. **Investigate the root cause** — library version regression, missing generics, ambient type collision, wrong middleware signature, etc.
2. **Refactor to make the types line up** — extract to a helper, use chain-style routing, replace a validator with inline `safeParse()`, upgrade a package, or rename a conflicting type
3. **Only as a last resort**: if all of the above genuinely cannot resolve it and the code is demonstrably safe at runtime, use a **narrow** type assertion (`as unknown as T`) at the exact expression — NEVER a line-level suppression comment that hides all errors on that line

When a lint rule complaint appears:
1. **Fix the code** to satisfy the rule
2. If the rule is wrong for the project, disable it in config (`biome.json`, `.eslintrc`) with a comment — not per-line suppressions

**Acceptable suppressions (rare, must document why):**
- Third-party type declarations that are definitively wrong — suppress with a comment citing the upstream issue URL
- Intentional runtime behavior the type-system can't model (e.g., WASM boundary) — suppress with detailed explanation

**Unacceptable:**
- "Hono 4.12 regression" → refactor to chain-style, switch to inline parse, or upgrade
- "Timing out on the fix" → stop and ask the user before suppressing
- "Pre-existing" suppressions in the file → remove them as you refactor

**Why (2026-04-12):** Carmack added 4 `@ts-expect-error` suppressions instead of refactoring 4 routes to drop the broken zValidator chain and use inline `safeParse()`. User flagged this immediately. Permanent rule.

### Single-Affordance Rule for Form Controls (MANDATORY — 2026-05-17)

**When changing CSS for any `<select>` / `<details>` / form control on a page that loads a forms-styling framework (`@tailwindcss/forms`, Bootstrap `form-select`, Bulma, etc.), the CSS MUST resolve which chevron/marker is visible — never let two systems paint the same affordance.**

Two valid patterns for `<select>`:

```css
/* Pattern A: native chevron only */
.your-select {
  appearance: auto;
  background-image: none !important;  /* kill framework overlay */
}

/* Pattern B: inline-icon only (use with adjacent <span> chevron in markup) */
.your-select {
  appearance: none !important;
  -webkit-appearance: none !important;
  background-image: none !important;
}
```

Forbidden state: `appearance` unset/auto AND `background-image` unset, **with a forms-plugin loaded** → double chevron.

Same rule for `<details><summary>`: either hide `::-webkit-details-marker` and use an inline glyph, or use the native marker and skip the glyph — never both.

**How to apply:** when invoked in **debug** or **review** mode and the user mentions "double down arrow", "two chevrons", "stacked icons", "duplicate caret", "X is showing twice", or any UI page mixing Tailwind/Bootstrap forms with native `<select>`/`<details>`, load `references/ui-duplicate-affordance.md` and run its 5-step detection recipe. Add a regression test that locks the CSS rule AND enforces every control on the page carries a discipline class.

**Why (2026-05-17, IBA-m69):** ImproveBayArea `/reports?city=san-francisco` showed two stacked ▼ on the "Closed reports" filter because `.report-select` used `appearance: auto` (native chevron) without `background-image: none` (`@tailwindcss/forms` painted a second chevron on top). Fix took 1 CSS line + 1 regression test. Cataloged so the next instance — on any project — is caught in the audit pass.

### Anti-Slop TypeScript — No Generic Type-Guard Boilerplate (MANDATORY — 2026-06-25)

**When writing or reviewing TypeScript, never default to a generic loose type guard — reach for a specific type, discriminated union, or schema first.** This is the runtime-guard sibling of the No-Suppression Rule: `isRecord`/`isObject`/`as unknown as T`/`(x as any).field` make code *run* on data of unknown shape without ever stating the shape, pushing type errors to a 2am production `TypeError`. It's the #1 AI "vibe-coding" tell. Full standard + alternatives + Zod patterns: `~/.claude/skills/shared/anti-slop-typescript.md`.

**Forbidden:** `function isRecord(o: unknown): o is Record<string, unknown>`, `isObject`, copy-pasted structural guards across files, blanket `as any` / `as unknown as T` launder-casts, `(obj as any).field` reach-casts.

**Required (priority order):** (1) a named `interface`/`type`; (2) a discriminated union narrowed on a literal field; (3) a **Zod/Valibot schema at every trust boundary** with `type X = z.infer<typeof Schema>` (one source of truth); (4) library-inferred types (`z.infer`, Prisma/Drizzle `$inferSelect`, tRPC, Hono `InferResponseType`); (5) a *targeted* predicate checking the fields you actually use — last resort, justified inline.

**How to apply:** in **feature**, **debug**, or **review** mode on any `.ts`/`.tsx`, run `~/.claude/skills/carmack/tools/detect-ts-slop.sh [path|--diff <base>]`. It flags generic guards, launder-casts, and reach-casts with file:line + a refactor hint. Treat every hit as a fix-list item (Fix-All-Issues rule), not a report — refactor to a specific type/schema; a guard that's genuinely the right tool stays but is justified inline. Typed code should compile (`tsc --noEmit`) with **zero** casts added to make it pass.

**Why (2026-06-25):** user flagged repetitive generic `isRecord`/loose-guard output as slop — code that compiles and runs but is never actually typed, the upstream cause of the undefined/null-render bug class. Stating the type (or a schema) IS the work; the generic guard is the avoidance of it.

### New-Site Default = Hono Framework (MANDATORY — 2026-06-04)

**Any time the user asks to build, create, scaffold, or "make" a new website or web app — OR to convert/remake an existing site — DEFAULT to the Hono framework (SSR + islands on Cloudflare Workers) by loading the `/hono` skill (`~/.claude/skills/hono/SKILL.md`).** Do not reach for a React/Vue/Next SPA scaffold unless the user *explicitly* names a different stack. `hono/jsx` for server SSR, `hono/jsx/dom` for interactive islands, dual client/server Vite build, static assets via wrangler `assets`. The `/hono` references are verified against hono.dev — use them; don't invent Hono APIs from memory.

### SPA→SSR Conversion = Audit Global App.tsx Mounts FIRST (MANDATORY — 2026-06-28)

**Before converting ANY React-SPA route to SSR (`hono/jsx`, Astro, Next RSC), enumerate every component mounted globally in `App.tsx`/the SPA root — and re-provide each one on the SSR page. SSR does not mount your React tree, so each global component silently disappears from the converted route with NO error, NO console log, NO diff that flags it.** The at-risk set: floating support/chat widget, cookie/consent banner (legal!), analytics beacon, exit-intent modal, toast host, providers, and any `?param` deep-link handler (`?support=open`, `?ref=`, UTM-driven UI).

Run before the first conversion and re-run after each route:
```bash
grep -nE "<[A-Z][A-Za-z]+ ?/?>" src/react-app/App.tsx | grep -viE "Route|Router|Routes|Suspense|ErrorBoundary|Navigate|HelmetProvider"
```
For each hit, the SSR page must provide it as a **shared island** (mount the *existing* React component — reuse, don't rewrite — into a placeholder via the SSR layout, on EVERY SSR page), an SSR equivalent, or a static fallback that *itself* still works. Watch the incremental trap: an affordance can keep "working" because a static link bounces to a route that's *still* SPA — then you SSR-convert that route too and the last mount point vanishes. Verify the thing **acts** (chat opens, banner shows, deep-link fires) in a real browser — not that the link/markup is merely present. Single-affordance: hide the static no-JS fallback once the island hydrates.

**Why (2026-06-28, exampleapp):** SSR-converting the 7 public pages — including `/` — dropped the global `SupportChatWidget` (`App.tsx:167`); `public-layout.tsx` had only a static `<a href="/?support=open">` that relied on `/` being the SPA, so once `/` was SSR the live chat + the `?support=open` email deep-link were dead on all 7 pages. Fix `7a25f67`: a shared `support-island.tsx` mounting the existing widget on every SSR page. Full pattern: `~/.claude/skills/debug/references/react-patterns.md` #24.

**ALSO verify the rendered CASCADE, not just presence (the 🛑 hardest rule):** after wiring islands, the bundled island/Tailwind CSS you `<link>` for the widgets often transitively imports the app's global `index.css`, whose element-selector rules (`body{background:var(--color-bg);color:var(--color-text)}`) load AFTER the SSR page's inline `<style>` and **silently override the SSR design** → invisible text, wrong background, on EVERY SSR page — with no error, clean diff, passing CSP/`<h1>` checks. After ANY SSR+island change you MUST drive the live browser on EVERY SSR route and assert `getComputedStyle(document.body)` bg/color equals the intended token (not a leaked fallback like `rgb(240,240,240)`) and that headings pass WCAG-AA against their ACTUAL computed bg — plus eyeball a screenshot. Fix: SSR layout `body{background:…!important;color:…!important}` (leaked rules carry no `!important`) or stop the island bundle emitting global `body` rules. Reference: 2026-06-28 — `support-island.css` leaked `body{background:#f0f0f0}` → white headings invisible site-wide, shipped twice undetected (checks verified "chat opens", not page background); fix `cd0cdfe`. Full pattern: `~/.claude/skills/debug/references/react-patterns.md` #25; `/ship` gate 1.3c.

### Site a11y + CSP Baseline — always add when building/touching a public site (MANDATORY — 2026-06-04)

**When building a new site OR modifying any public-facing site, ALWAYS add/verify these three before declaring done — they are not optional polish:**

1. **Content-Security-Policy header.** Set one via Hono `secureHeaders({ contentSecurityPolicy: {...} })` (or equivalent middleware). Start strict (`default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`) and allow-list ONLY what the islands actually load — inspect the client code for external hosts (map tile CDNs e.g. `*.basemaps.cartocdn.com`, Google Fonts `fonts.googleapis.com`/`fonts.gstatic.com`, `data:` images, `'unsafe-inline'` for `style-src` when a lib injects inline styles). Then **browser-verify the islands still work under the CSP** (load the page, confirm tiles/charts/maps render, grep the console for `Refused to … Content Security Policy` — zero violations).
2. **Color-contrast (WCAG AA ≥4.5:1).** No body/UI text below 4.5:1 against its background (3:1 for large/bold ≥24px). Audit muted grays on dark backgrounds especially — bump theme tokens until they pass; don't ship `text-*/40`–`/60` opacity text or sub-#8-luminance grays on near-black.
3. **Heading-order / single `<h1>`.** Exactly one content `<h1>` per page, no skipped levels (h1→h3). Brand wordmarks/logos in the header are `<span>`/`<div>`, NOT `<h1>` — a logo `<h1>` plus a page `<h1>` is a heading-order failure.

Verify with a real browser/Lighthouse pass, not just source review. Reference incident (2026-06-04, example-project-heritage): the Hono conversion shipped with no CSP, `#6b7280` footer text (~3.7:1, failed AA), and a logo `<h1>` colliding with each page's content `<h1>` — all three fixed in one pass and codified here so the next site build includes them from the start.

### Observability — Instrument on Build, Improve on Fix (MANDATORY — 2026-06-17)

**Two behaviors, both required before declaring done.** Full standard: `~/.claude/skills/shared/observability-instrumentation.md`.

1. **Instrument-on-build** — when you build or substantially touch a subsystem, add structured logging at its *seams* (external calls, error/catch branches, state transitions, the input that selects the branch) before it's "done". Log at boundaries and decision points, NOT everywhere — blanket logging just recreates the noise problem. Structured `log({event, ...attrs})`, never prose; redact secrets/PII/tokens.
2. **Instrument-on-fix (boy-scout)** — when you fix a bug, before leaving the code path, add the one log line / attribute / error-message rewrite that **would have made this bug obvious in 30 seconds**. You just root-caused it — you have maximal context. This is the compounding win.

Error messages must be actionable: what was attempted + the actual values + the likely cause/branch + disambiguation (an "ambiguous error" is almost always two root causes sharing one string — split them). Surface the upstream's real reason, not a generic wrapper. When *reducing* log noise, **downgrade the level (`info`→`debug`), never delete** — a line that looks like noise may be load-bearing for another debug path.

**Why (2026-06-17):** codifies the user's standing practice (assess logs → fix ambiguous errors → prune noise → add debug attributes) as a reactive build/fix discipline; the proactive scheduled half is the `/log-hygiene` skill. Same family as the catch-all-masking and third-party-signal-fixtures rules — a silent or vague log is the log-equivalent of a masked error.

Word budget: **25 words max between tool calls, 100 words max final answer.** Lead with action, not explanation.

---

## Agent Spawning Rules (from internal Coordinator Mode)

When using the Agent tool to delegate work:
1. **Each agent prompt MUST be fully self-contained** — include all file paths, context, constraints, and verification steps
2. **Never reference "the current file" or "what we discussed"** — the subagent has zero context from this conversation
3. **Include the verification step in the agent prompt itself** — don't rely on post-agent verification
4. **Synthesize findings before delegating follow-up** — never chain agents blindly
5. **Use parallel agents when work is independent** — launch multiple Agent calls in a single message

---

## Reference Files Index

| File | Content |
|------|---------|
| `code-review-react.md` | TypeScript/React 19 review rules, useEffect ban, hook patterns, state management |
| `code-review-security.md` | XSS 10-vector audit, escapeHtml/isSafeUrl implementations, severity matrix |
| `code-review-general.md` | Performance, quality, testing, Rust, config compat, full review checklist (42 items) |
| `ux-patterns.md` | UX pre-checks, error handling patterns, WCAG 2.2 AA, iOS Safari, scope errors |
| `ui-duplicate-affordance.md` | Double-chevron / double-arrow / duplicate-icon detection. 5-step recipe for `<select>` + `<details>` + redundant badges. Forms-framework + native-control collision patterns. Reference incident: IBA-m69. |
| `responsive-design.md` | Responsive rules, mobile/desktop strategy, frontend design principles |
| `feature-implementation.md` | Build decision framework, brainstorming, PRD generation, Ralph mode |
| `browser-automation.md` | chrome-cdp (live session), agent-browser (headless), commands reference |
| `git-workflow.md` | Git pre-flight, security scanning, worktree management, fork mass-integration |
| `debug-patterns.md` | 5-phase workflow, code search tools, repro harnesses, React-specific checks |
| `deploy-patterns.md` | Session invalidation, CF Pages debugging, cross-platform CI, code scanning, GH Actions |
| `codex-integration.md` | Codex review (quality gate), adversarial review, rescue (escalation) |
| `research.md` | Last30days web research, Reddit/X/web synthesis, prompt generation |
| `skill-creation.md` | Creating & editing SKILL.md files, frontmatter, progressive disclosure |
| `task-tracking.md` | PRD to prd.json conversion, agent-testable tasks, beads tracking |
| `aiva-guidelines.md` | AIVA-specific: color ban, VA palette, OG/favicon standards, admin auth pattern |
| `preflight-checks.md` | Pre-flight: CDP warmup, codebase audit, code coverage, lint/security auto-fix |
| `legal-document-audit.md` | 5 hallucination patterns (fabricated citations, fake phones, invented people, name transposition, exhibit drift), audit procedure, sweep script |
| `lighthouse-optimization.md` | Lighthouse 100/100 playbook: 3-run median audit loop, 10 high-leverage patterns (defer third-party, kill CF Bot Fight JS, SSR hero, async CSS, preload LCP, bundle analysis, bf-cache headers, SEO fallback, a11y quick wins, CSP fixes), 4-stage fix order, known ceilings |
| `~/.claude/skills/shared/observability-instrumentation.md` | **Observability standard**: instrument-on-build + instrument-on-fix (boy-scout), boundary/decision-point logging, structured-log shape, 4-part actionable error-message design, downgrade-noise-never-delete guardrail, stack log sources. Proactive counterpart: `/log-hygiene` skill. |
| `~/.claude/skills/shared/ant-verification-protocol.md` | **Ant-level quality gates**: OWASP Top 10 sweep, truthfulness protocol, closed-loop verification, enhanced review |
| `~/.claude/skills/shared/anti-slop-typescript.md` | **Anti-slop TypeScript**: ban generic `isRecord`/`isObject` guards, `as unknown as T` launder-casts, `(x as any).field` reach-casts; require named types / discriminated unions / Zod schemas (`z.infer`). Detector: `~/.claude/skills/carmack/tools/detect-ts-slop.sh`. Runtime-guard sibling of the No-Suppression Rule. |

---

## Code Search Tools

**Start with native `Grep` / `Glob`** — they return structured `file:line:content` output that feeds directly into `Read`. Escalate to the CLI tools below only when keyword matching can't express the question (semantic search, cross-doc synthesis, AST patterns).

### osgrep — AST-Aware / Semantic Code Search (escalate from Grep)
Use when the thing you're looking for isn't a literal keyword — e.g. "where is auth handled" across varied naming.

```bash
osgrep index .                          # Build index (first time per project)
osgrep query "where is auth handled"    # Semantic search
osgrep query "error handling" --mode fulltext  # Keyword search
```

### qmd — Knowledge & Documentation Search
```bash
qmd collection add ~/project/docs --name docs   # Add docs collection
qmd embed                                        # Build embeddings
qmd query "how does authentication work"         # Hybrid search
```

### bd — Task Tracking
```bash
bd create --title="Investigate issue" --type=bug --priority=2
bd update <id> --status=in_progress
bd close <id> --reason="Root cause and fix summary"
```

---

## Cloudflare API Access (MCP)

The `cloudflare-api` MCP server provides full access to ~2,500 Cloudflare API endpoints:
- **`search`** — Query the OpenAPI spec to find endpoints
- **`execute`** — Call any Cloudflare API endpoint

Use for: Worker runtime logs, DNS/routing issues, KV/D1/R2 data, Worker bindings, firewall rules, zone analytics, cache behavior, SSL status, edge redirect rules.

---

## Instructions

When this skill is invoked:

**STEP 0 — Notify the user BEFORE launching the agent (MANDATORY):**

Before invoking the Task tool, print a brief status message:
- For bugs: "Investigating [issue]. This uses a 5-phase deep debugging workflow and may take several minutes. You'll see the results when it finishes."
- For features: "Building [feature]. Running build decision framework first, then implementing. You'll see the results when it finishes."
- For reviews: "Reviewing code. Loading TypeScript/React 19, security, and quality review patterns. You'll see the results when it finishes."

**STEP 1 — Detect mode and load references:**

1. Parse the user's request against the Mode Detection table above
2. Read the relevant reference files from `~/.claude/skills/carmack/references/`
3. If working in an AIVA project directory, also read `aiva-guidelines.md`
4. For implementation/debug modes, also read `preflight-checks.md`

**STEP 1.5 — Apply Ant-Level Verification Protocol (MANDATORY):**

Load `~/.claude/skills/shared/ant-verification-protocol.md` and apply:
- **debug mode**: Security Review Gate (Section 1) on all files in the investigation
- **feature mode**: Full OWASP sweep + Truthfulness Protocol on implementation
- **review mode**: Enhanced Code Review (Section 5) on top of existing checklists
- **ALL modes**: Closed-Loop Verification (Section 3) — never declare done without evidence

**STEP 2 — Launch the agent:**

1. **For feature requests**: Run the Build Decision Framework FIRST (from feature-implementation.md) — check if the user is about to build something that already exists as a service/library.
2. **For bugs/debugging**: Use the 5-Phase Workflow with repro harnesses and debugger attachment.
3. **For code reviews**: Apply the loaded review checklists systematically.
4. Use the Task tool with `subagent_type: carmack-mode-engineer`
5. Pass the issue/feature description + any relevant context from reference files
6. The agent will build repro harnesses and attach debuggers as needed
7. Approval checkpoint before implementing fixes

**STEP 3 — Post-completion:**

1. **After every git push**: Run GitHub Actions CI Gate — detect if repo has workflows, watch all checks with `gh pr checks --watch` or `gh run watch`, and if any fail: read logs with `gh run view --log-failed`, fix the issue, commit, push, and repeat (max 3 retries). Do NOT consider the task complete until all CI checks are green.
2. **NEVER deploy** — when done, tell the user to run `/ship` for production deployment.

```
Launch carmack-mode-engineer agent now with the user's issue description.
Include the content from the relevant reference files you loaded in STEP 1.
CRITICAL (context quality): Use the Grep → Read loop as the default investigation sequence. Never use Bash `cat`/`head`/`tail`/`sed -n` as a Read substitute — you lose multimodal rendering (images/PDFs/notebooks), safe-edit tracking, and clean line numbers. Reserve Bash for git archaeology (log/blame/diff), code execution (node/python/curl/test runs), compound pipelines (sort/uniq/wc/awk/xargs), and CLI tools (osgrep/qmd/bd/gh).
IMPORTANT: After EVERY git push, check if the repo has GitHub Actions workflows. If yes, watch all checks until they complete. If any check fails, read the failure logs, fix the issue, commit, push, and repeat — up to 3 retry cycles.
CRITICAL: Do NOT deploy to production. Do NOT run wrangler deploy, npm run deploy, vercel deploy --prod, or any production deployment command. When implementation is complete, STOP and tell the user to run /ship for deployment.
```
