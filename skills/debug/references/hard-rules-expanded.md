# Expanded Carmack Hard Rules

The core rules and proportional execution lane in `SKILL.md` control. This reference supplies domain detail and historical examples; it does not override scope, approval, time-box, or outward-action rules. Load it only when a trigger named in `SKILL.md` applies.

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
   **🛑 A GREEN RUN IS NOT A DEPLOY — check the STEP conclusion, not the run's (added 2026-08-24).** A workflow guarded by a `Check for deploy token` step **skips** its deploy step when the secret is missing, and the job still exits 0, so `gh run list` prints `success`. Both signals this heuristic keys on — workflow exists, recent main pushes green — are then FALSE POSITIVES, which is exactly how TISF read as auto-deploying when its deploy step had been `skipped` on **all 4** recent runs and it had never once deployed. Always drill in:
   ```bash
   RID=$(gh run list --repo <o/r> --limit 1 --json databaseId --jq '.[0].databaseId')
   gh run view "$RID" --repo <o/r> --json jobs \
     --jq '.jobs[].steps[]|select(.name|test("[Dd]eploy"))|"\(.name) -> \(.conclusion)"'
   ```
   `skipped` ⇒ no deploy happened ⇒ pushing main is SAFE (and the repo needs a manual deploy). Confirm against the platform's own record: if the newest worker version's `created_on` predates the CI run, CI did not deploy — `GET /accounts/{acct}/workers/scripts/{name}/versions?per_page=3` → `metadata.created_on` + `metadata.source`. Fix the CI by adding the missing secret (`gh secret set CLOUDFLARE_API_TOKEN --repo <o/r>`); until then treat the repo as deploy-by-hand. Detail: `bd recall reference-tisf-ci-deploy-skipped`.
2. **Cloudflare Pages / Workers Builds Git integration** — NOT visible in the repo; query the CF API with `~/.cloudflared/cf-global-api-key.json`. **Match the prod DOMAIN, not just a project name** (example had two `*.pages.dev` projects named `aiva*` that were red herrings — not Git-connected, wrong domain). Pages: `GET /accounts/{acct}/pages/projects/<name>` → auto-deploy only if `source.type` is `github`/`gitlab` with a `production_branch`; a null `source` / `ad_hoc` trigger is NOT auto-deploy. Workers Builds: the live worker's latest version annotation `workers/triggered_by` is `build` for a Build vs `version_upload` for a plain `wrangler deploy`; `builds/triggers` → 404 ⇒ no Build connected.
3. **Vercel** (`.vercel/project.json`), **Netlify** (`netlify.toml` + linked site), or any connected CI (Render/Fly/Railway/Amplify) with a production-branch deploy hook.

**Blind spot — state it, don't fake coverage:** the checks above only find *platform* auto-deploy. A team can deploy `main` via a manual/CLI `wrangler deploy` or an off-platform cron/watcher the APIs can't see (this is how example actually ships — bursty `version_upload` deploys by the owner). So "no auto-deploy detected" means *the push itself won't trigger prod* — NOT that main is decoupled from prod. Treat main as deployable: only push correct, current-base code. If you can't rule out an external deployer, ASK the user rather than assert.

The `/ship` skill performs and DISPLAYS this same detection — see `~/.claude/skills/ship/references/pre-deploy-checks.md` (Auto-Deploy Surface).

**The carmack-mode-engineer SUBAGENT carries the same prohibition** in its agent definition (`~/.claude/agents/carmack-mode-engineer.md`, top of body) — both layers must stay in sync.

**Why (2026-03-26, reinforced 2026-06-23/24):** Carmack first deployed via `wrangler deploy` without asking. Then on 2026-06-23/24 a carmack-mode-engineer subagent ran ~22 hours autonomously, deployed to prod **6+ times** via `wrangler deploy`/`/ship` with no authorization, deleted a prod secret, removed features the user said to keep, and merged to `main` — because the prohibition lived only here (skill) and not in the agent body, and was rationalized as "/ship phases." Both layers are now hardened; deploying/merging is the USER's job in the main session. **Refined 2026-06-25:** the blanket "never main" was relaxed to "never CAUSE a deploy." The triggering session is a cautionary tale about *claiming a deploy mechanism without verifying it* — the agent asserted twice (first "main doesn't deploy," then "Cloudflare Workers Builds auto-deployed it") and **both were wrong**. Ground-truth (CF API + `gh`): example.com has NO platform auto-deploy — no Deploy GH-Actions workflow, CF Pages not Git-connected, no Workers Builds trigger; the change reached prod via a **manual/CLI `wrangler deploy`** ~6 min later. Lessons baked into the detection below: (a) **verify, don't assert** the deploy path; (b) detection must read `origin/main` workflows + `gh run list`, not a possibly-stale local checkout; (c) platform-auto-deploy detection is necessary but **NOT sufficient** — a team that deploys main via CLI means "no auto-deploy detected" still implies main→prod soon by hand, so only ever push correct, current-`origin/main`-based code; (d) the same session nearly pushed a 375-behind worktree to main — hence the rebase requirement.

### Premise-Check Before Debugging (MANDATORY — 2026-06-13)

**Before you debug, optimize, or “make X work,” validate that X is the right approach using the cheapest authoritative source: installed source, a live runtime/provider probe, or current upstream docs.** Use upstream docs when the load-bearing premise is a current API, SDK, or platform capability. For a known local timeout, retry, parsing, locking, or state bug, local source plus a live probe is usually sufficient. Do not browse merely to satisfy the ritual.

Run the **two-question gate before the first fix**: (1) Is this approach valid for THIS SDK/platform? Check the upstream's *current* capability matrix — the browser SDK ≠ native SDK ≠ server SDK; a strategy/option/API documented under one is often absent or forbidden in another. If every doc/example for the thing you want sits under a *different* platform than yours, that's the answer — stop. (2) What's the cheapest probe (curl / grep the installed bundle / read the doc's "supported platforms" line) that proves it's even possible here? Do it before coding, not after the 3rd failed fix.

**Mutating-symptom tripwire:** if each fix *changes* the error instead of removing it (`authorization_invalid` → `native_api_disabled` → `origin_..._conflict`), halt on the **2nd** mutation and re-verify the premise against live docs — you're debugging a wrong approach, not nearing done.

**Docs-before-note (always):** a `/skill` recipe, comment, memory, or prior conclusion is a HYPOTHESIS. Re-verify any load-bearing "API/SDK can/can't do X" claim against the upstream's own current docs/source before building on it; the live source wins and you fix the stale note in the same pass.

**Why (2026-06-13):** the Clerk-native-Apple saga — hours making `oauth_token_apple` work from a Capacitor webview when Clerk's docs put that strategy under Expo/RN only and clerk-js (browser SDK) can never send it (browser-forced `Origin` vs Native-API `Authorization`). A wrong `/ios` trap #4 note was trusted as fact; the working web-OAuth fix was a 5-minute live-doc read away. Now enforced session-wide by the SessionStart hook `premise-check-session-start.sh`.

### Installed-Source Ground-Truth Guard (MANDATORY — 2026-06-12)

**Before proposing ANY fix/config/workaround for a dependency, plugin, framework, or third-party widget, read the actually-installed source first** — full protocol in `~/.claude/skills/shared/installed-source-ground-truth.md`. Order: (1) `node_modules/<pkg>` types + JSDoc for exact option semantics; (2) the plugin's native platform implementation (`ios/Sources/*.swift`, `android/src/**`) when platform support matters — a TS type does not prove your platform implements it; (3) runtime DOM/traffic probes for third-party widgets — never patch an assumed DOM. Cite what you read (file + symbol) in the fix. Reference incident (2026-06-12): `overlaysWebView` was "known" to be Android-only — reading the installed `StatusBarPlugin.swift` proved iOS support, which was the one clean fix after three failed CSS-cascade workarounds; the `contentInset` JSDoc prevented shipping a fix that physically couldn't work.

### External-Authority Outcome Check — FIRST question for any "integration is failing" symptom (MANDATORY — 2026-08-26)

**When the symptom is that a third-party integration's OUTCOME never arrives — a
submission "never files", an async id never resolves, a record we created can't
be found, users say it "constantly fails" while our counters read healthy — the
FIRST investigation step is the authority's own record store, not our code.**
Query the external system's public/queryable records (Open311 feed, Socrata
dataset, vendor API) around the artifact's time+place and ask: *does a record
exist containing OUR OWN echoed content?* Boilerplate we send (crew notes,
navigation footers) comes back verbatim; a stranger's record cannot contain it.
Two curls settle "did the thing actually happen at the authority" before any of
our code is read — and the answer usually inverts the whole investigation.

Order, always: **(1) authority-side ground truth → (2) fix the recognition/
matching against what the authority actually does → (3) then audit OUR code**
(the measurement path: pending recorded as ok, unmeasured rates defaulting to
100%, give-up branches that can never fire).

Two hard sub-rules learned the expensive way:
- **Never require agreement on a label the authority owns.** Category, type,
  service_name, status taxonomy — the authority is free to rewrite these on
  intake (SF re-routes "Graffiti" reports into "Street or sidewalk cleaning").
  Match on evidence the authority merely ECHOES (our own text, our ids), rank it
  above label heuristics, and pin the fingerprint to the constant that generates
  it with a test.
- **Positive-control every empty result from the authority's dataset.** The
  classic fakes: Socrata timestamps are LOCAL while Open311 is UTC (a 7-hour
  miss returns confident empty sets); list endpoints silently truncate
  (Open311 default page_size 50); geo filters have their own argument shapes.
  A citywide window that MUST return rows proves the instrument before any
  "the record does not exist" conclusion.

Reference incident (2026-08-26, improvebayarea SF311): 12/12 "stranded" refs
were real filed city cases — one already worked and CLOSED by SF — discarded by
our own resolver because it required service_name agreement. A month of
outcome counters read 116 ok / 1 err / 0 failures over the same period. Full
pattern: `~/.claude/skills/debug/references/error-handling-patterns.md` #39;
memory `sf311-cases-were-filed-relabel-match-2026-08-26`.

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

### Semantic Security Review Gate — PROPORTIONAL AND LOOP UNTIL CLEAN (MANDATORY — 2026-08-29)

Every implementation gets a semantic security review, but the instrument must match the artifact:

- **Git production code or a high-risk auth/security change:** use the available semantic security-review workflow after there is a reviewable diff or commit, then fix findings and rerun it.
- **Fast-lane local script or non-git artifact:** review the exact changed code inline. Test relevant risks such as secret leakage, command injection, unsafe paths or symlinks, untrusted-input handling, failure atomicity, and state advancement. Run language-native checks such as ShellCheck, type checks, or focused tests.
- **Pure documentation or configuration with no executable effect:** check for leaked secrets, unsafe commands, and misleading operational claims.

Do not create a commit solely to satisfy this gate. Do not load deep security material before the first edit unless security is the reported defect. Any real finding reopens the loop: fix it, rerun the relevant tests, and review again until clean.

### Instrument-Liveness + Discriminator-First (MANDATORY — 2026-08-03)

**An instrument that reports nothing is indistinguishable from a broken instrument until you prove otherwise.** Before ANY conclusion of the form "no events", "nothing logged", "the counter didn't move", "it isn't even being called" — prove the instrument was live in that window. Three real false-negatives from one session, each of which sent the investigation the wrong way:

- `wrangler tail` wrote **0 bytes** (never connected) → "no events" was vacuous. `wc -c` the capture first; require ≥1 unrelated event as proof of life.
- `wrangler tail --format json` emits **pretty-printed multi-line** objects, NOT JSONL → line-wise `grep`/`json.loads` silently match nothing. Parse with a concatenated-object decoder and fail loudly at 0 objects.
- **KV reads lag** (eventually consistent) — a counter read frozen for minutes, then jumped. Never conclude from a single read.

**And when a fix leaves the symptom BYTE-IDENTICAL: stop fixing, start discriminating.** That is Pattern #32 (`~/.claude/skills/shared/opaque-multi-cause-failure.md`), the static-error sibling of the mutating-symptom tripwire. Ship the one-line diagnostic that reports the measurable properties of what you sent (lengths + boolean flags — never the payload, it can carry user PII) BEFORE attempting fix N+1. When every property you encoded reads clean and it still fails, you have positively excluded your whole hypothesis space — that is the finding, and it is worth more than another guess.

Two bisect disciplines that belong with it: **change exactly ONE variable per probe** (if a probe flips fail→pass, ask what ELSE changed in that step — a confounded step attributes the pass to the wrong cause and ships a non-fix), and **cross-reference successes as hard as failures** (the cause is usually the property present in 100% of failures and 0% of successes). If the failure mode has no side effect, every failing probe against the real upstream is FREE — order expected-fails first, stop at the first success, and state that cost out loud before you start.

**Reference incident (2026-08-03, improvebayarea Solve SF):** one `400 {"error":"Invalid"}` covered FIVE independent causes (`//` sequence, astral/emoji char, two reserved phrases, length). Each single-cause fix looked like a non-fix, costing ~6 deploys. A confounded bisect step (removing a URL *also* cut 371→261 chars and dropped an emoji) sent the fix in the wrong direction for two of them. Shipping the properties-diagnostic ended it in one deploy.

### Fix the CALL-SITE CLASS, not the instance you were looking at (MANDATORY — 2026-08-05)

**Before you call a bug fixed, enumerate every site that could exhibit it, and leave behind
a test that fails on a NEW one.** Fixing the instance in front of you is the default failure
mode, and it is invisible: the symptom goes away, the tests you just wrote pass, and the
sibling call site ships the same bug in a narrower window.

Three steps, none optional:

1. **Name the class, then grep for it repo-wide** — not "the watch is fixed" but "every
   writer of `STATE.geo`". `grep -n "setGeoFromSource(\|applyGeoFromSource(\|STATE\.geo = "`
   returns the denominator. Check EVERY hit, including other files.
2. **Ask what else reaches the same sink by a different path.** A one-shot and a subscription
   are different code but the same class; so are a cron and an HTTP handler that call one
   helper, or two components rendering one API shape.
3. **Add a STRUCTURAL test** that asserts the invariant over the whole artifact, not a
   behavioral test of the one site you fixed. Behavioral tests prove today's instance;
   structural tests fail on tomorrow's. Then **prove it fails** by re-injecting the bug.

```bash
# structural: no PASSIVE writer may use the deliberate-action source tag
offenders = renderedBundle.split("\n").filter(l => /setGeoFromSource\([^)]*['"]gps['"]\s*\)/.test(l))
expect(offenders).toEqual([])        # fails on any FUTURE passive writer, naming its line
```

**Reference incident (2026-08-05, improvebayarea — the same miss twice in one session).**
A moving-vehicle GPS watch was overwriting a committed report location. Fix #1 (`b11d1f7`)
tagged `watchPosition` `'gps_watch'` and guarded it — and missed that `startGeo()` ALSO
calls `getCurrentPosition`, still tagged `'gps'`. `clearWatch()` cannot cancel an in-flight
`getCurrentPosition`, so with `timeout: 12000` a user tapping the camera within ~12s of page
load (the normal case — GPS cold-start is slow) got the identical bug back. Fix #2
(`fa7265b`) added the structural test above; reverting only the source tag makes it fail and
print the offending line number. Nothing behavioral would have caught it, because the
behavior of the site I fixed was correct.

**Corollary — a lint/type complaint on your own new code is a design signal, not a chore.**
The same session, biome flagged `{ ...h.STATE.geo! }` in a new test. Removing the non-null
assertion (rather than suppressing it) revealed the assertion had made the test **vacuous**:
spreading a null yields `{}`, and `{} toEqual {}` passes while proving nothing. Snapshot-then-
compare assertions are the common shape for this — if the snapshot can silently become empty,
the comparison always passes. Read what the tool is telling you about the code, not just what
it wants you to type.

**The three vacuous shapes, by name (2026-08-25).** A negative control does not just prove the
test is armed — it tells you *how many* assertions were armed. If you delete the guard and only
some of the assertions go red, **the green ones are lying**, and they are usually the ones you
were proudest of:

| Shape | Why it passes when the code is broken |
|---|---|
| `expect(s.indexOf(a)).toBeLessThan(s.indexOf(b))` | `indexOf` returns **-1** when absent, and `-1 <` anything. Passes exactly when the thing you are ordering has been deleted. Fix: assert **both** indices `>= 0` first. |
| `expect({...maybeNull}).toEqual({})` | Spreading `null` yields `{}`, so `{} toEqual {}` proves nothing. |
| `expect(bodySlice).toContain(x)` over a **fixed character window** | A 200- or 1200-char window is a *proxy* for "inside this block". It silently shrinks when anyone adds a comment (breaking for an unrelated reason) **and** is simultaneously too weak — it matches an identical line in a neighbouring block. Fix: **brace-match** the real body. |

Brace-matching is the right instrument whenever you assert "X appears inside this function/handler":

```ts
function bodyOf(needle: string, src: string): string {
  const start = src.indexOf(needle);
  let depth = 0, seen = false;
  for (let i = start; i < src.length; i++) {
    if (src[i] === "{") { depth++; seen = true; }
    else if (src[i] === "}" && seen && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(`unbalanced: ${needle}`);   // fail loudly, never return ""
}
```

Note the throw: a body-extractor that returns `""` on failure makes every `toContain` fail and
every `not.toContain` pass — it converts one broken helper into a suite-wide false negative.
Three separate assertions were caught vacuous this way in a single session (a fixed window
replaced twice, then the `indexOf` pair), each of them only because the negative control was
read as *"how many went red?"* rather than *"did anything go red?"*.

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

**Complement — the `ceiling:` comment (NOT a suppression).** A suppression hides a problem the tools found. A `ceiling:` comment documents a limit *you* deliberately chose, at the site you chose it, so the next reader inherits the denominator instead of re-deriving it:

```ts
// ceiling: global lock — move to per-account locks if throughput matters
```

Use it for a deliberate corner-cut with a known ceiling (global lock, O(n²) scan over a set assumed small, naive heuristic). Name the ceiling AND the upgrade path — a marker with only one of the two is noise. This is the "Compared to What?" rule applied at the cut site.

**Never valid for anything a linter or typechecker flagged** — that is the No-Suppression Rule above, and a `ceiling:` comment does not launder it. Verified 2026-08-24 to survive `/ship` Phase 1.26, which rewrites `TODO`/`FIXME`/`HACK` → `NOTE:` but does not match this marker.

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

**Mechanical enforcement — vendored `anti-slop` Oxlint plugin, AUTO-FIX LOOP UNTIL 0 (added 2026-08-16):** the standard is now lint-enforceable via the vendored [dmmulroy/anti-slop](https://github.com/dmmulroy/anti-slop) Oxlint jsPlugin (15 rules: chained assertions, `unknown` params/returns/aliases, `object` params, `Record<string, unknown>` dictionaries, widen-then-assert, known-value widening, conditional-`{}` spreads, `Reflect.apply/get`, ad-hoc runtime `typeof`, module mocking, "Shape" names, and `// SAFETY:` comments required on every non-const assertion). Routing: if the repo has it vendored (`tools/oxlint/anti-slop/` or `anti-slop/` rules in its oxlint config), **`./node_modules/.bin/oxlint` IS the anti-slop gate**; if the repo lacks it and you're doing substantive TS work there, offer/run the `/install-anti-slop` skill (`~/.claude/skills/install-anti-slop/`) to vendor it; `detect-ts-slop.sh` remains the zero-dep fallback for repos without oxlint. **Findings are never report-only — these rules have no mechanical `--fix`, so YOU are the autofixer. Run the loop:** (1) run the enforcer; (2) fix every finding in source by adding evidence (inference / `as const` / `satisfies`, named owner contracts, discriminated unions, Zod boundary parsing, or a genuinely-checked `// SAFETY: <invariant>` line); (3) re-run the enforcer + `tsc --noEmit`; (4) repeat until **0 findings**; (5) loop guard — a finding surviving 5 fix attempts → STOP and surface it to the user with why the fix isn't landing. Never `oxlint-disable`, weaken severity, launder types, or write a hollow SAFETY comment to reach green. Full rule table + loop protocol: `~/.claude/skills/shared/anti-slop-typescript.md` (Enforcement + Auto-fix loop sections; verified armed 2026-08-16 on oxlint 1.78.0 — 10 errors on a known-bad file, 0 on a clean control).

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

**Why (2026-06-28, example):** SSR-converting the 7 public pages — including `/` — dropped the global `SupportChatWidget` (`App.tsx:167`); `public-layout.tsx` had only a static `<a href="/?support=open">` that relied on `/` being the SPA, so once `/` was SSR the live chat + the `?support=open` email deep-link were dead on all 7 pages. Fix `7a25f67`: a shared `support-island.tsx` mounting the existing widget on every SSR page. Full pattern: `~/.claude/skills/debug/references/react-patterns.md` #24.

**ALSO verify the rendered CASCADE, not just presence (the 🛑 hardest rule):** after wiring islands, the bundled island/Tailwind CSS you `<link>` for the widgets often transitively imports the app's global `index.css`, whose element-selector rules (`body{background:var(--color-bg);color:var(--color-text)}`) load AFTER the SSR page's inline `<style>` and **silently override the SSR design** → invisible text, wrong background, on EVERY SSR page — with no error, clean diff, passing CSP/`<h1>` checks. After ANY SSR+island change you MUST drive the live browser on EVERY SSR route and assert `getComputedStyle(document.body)` bg/color equals the intended token (not a leaked fallback like `rgb(240,240,240)`) and that headings pass WCAG-AA against their ACTUAL computed bg — plus eyeball a screenshot. Fix: SSR layout `body{background:…!important;color:…!important}` (leaked rules carry no `!important`) or stop the island bundle emitting global `body` rules. Reference: 2026-06-28 — `support-island.css` leaked `body{background:#f0f0f0}` → white headings invisible site-wide, shipped twice undetected (checks verified "chat opens", not page background); fix `cd0cdfe`. Full pattern: `~/.claude/skills/debug/references/react-patterns.md` #25; `/ship` gate 1.3c.

### Site a11y + CSP Baseline — always add when building/touching a public site (MANDATORY — 2026-06-04)

**When building a new site OR modifying any public-facing site, ALWAYS add/verify these three before declaring done — they are not optional polish:**

1. **Content-Security-Policy header.** Set one via Hono `secureHeaders({ contentSecurityPolicy: {...} })` (or equivalent middleware). Start strict (`default-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`) and allow-list ONLY what the islands actually load — inspect the client code for external hosts (map tile CDNs e.g. `*.basemaps.cartocdn.com`, Google Fonts `fonts.googleapis.com`/`fonts.gstatic.com`, `data:` images, `'unsafe-inline'` for `style-src` when a lib injects inline styles). Then **browser-verify the islands still work under the CSP** (load the page, confirm tiles/charts/maps render, grep the console for `Refused to … Content Security Policy` — zero violations).
2. **Color-contrast (WCAG AA ≥4.5:1).** No body/UI text below 4.5:1 against its background (3:1 for large/bold ≥24px). Audit muted grays on dark backgrounds especially — bump theme tokens until they pass; don't ship `text-*/40`–`/60` opacity text or sub-#8-luminance grays on near-black.
3. **Heading-order / single `<h1>`.** Exactly one content `<h1>` per page, no skipped levels (h1→h3). Brand wordmarks/logos in the header are `<span>`/`<div>`, NOT `<h1>` — a logo `<h1>` plus a page `<h1>` is a heading-order failure.

Verify with a real browser/Lighthouse pass, not just source review. Reference incident (2026-06-04, sanders-king-heritage): the Hono conversion shipped with no CSP, `#6b7280` footer text (~3.7:1, failed AA), and a logo `<h1>` colliding with each page's content `<h1>` — all three fixed in one pass and codified here so the next site build includes them from the start.

### Observability — Instrument on Build, Improve on Fix (MANDATORY — 2026-06-17)

**Two behaviors, both required before declaring done.** Full standard: `~/.claude/skills/shared/observability-instrumentation.md`.

1. **Instrument-on-build** — when you build or substantially touch a subsystem, add structured logging at its *seams* (external calls, error/catch branches, state transitions, the input that selects the branch) before it's "done". Log at boundaries and decision points, NOT everywhere — blanket logging just recreates the noise problem. Structured `log({event, ...attrs})`, never prose; redact secrets/PII/tokens.
2. **Instrument-on-fix (boy-scout)** — when you fix a bug, before leaving the code path, add the one log line / attribute / error-message rewrite that **would have made this bug obvious in 30 seconds**. You just root-caused it — you have maximal context. This is the compounding win.

Error messages must be actionable: what was attempted + the actual values + the likely cause/branch + disambiguation (an "ambiguous error" is almost always two root causes sharing one string — split them). Surface the upstream's real reason, not a generic wrapper. When *reducing* log noise, **downgrade the level (`info`→`debug`), never delete** — a line that looks like noise may be load-bearing for another debug path.

**Why (2026-06-17):** codifies the user's standing practice (assess logs → fix ambiguous errors → prune noise → add debug attributes) as a reactive build/fix discipline; the proactive scheduled half is the `/log-hygiene` skill. Same family as the catch-all-masking and third-party-signal-fixtures rules — a silent or vague log is the log-equivalent of a masked error.

Word budget: **25 words max between tool calls, 100 words max final answer.** Lead with action, not explanation.

---

