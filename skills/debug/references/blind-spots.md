# Blind-Spot Checklist (Infra / Config Work)

When fixing infra, configs, plugin settings, or anything touching a running service, run these checks before declaring done. Each pattern below was learned from a real incident.

## 1. Config-schema validation BEFORE restart

Adding a new field to a JSON config and restarting the service can restart-loop if the field isn't in the schema. Always:

```bash
# dry-run validate if the tool supports it
openclaw doctor 2>&1 | grep -i 'invalid\|unknown'
# then restart
systemctl restart <service>
sleep 5 && systemctl is-active <service>
```

**Real incident (2026-04-17):** Added `maxOutputTokens: 8000` to featherless model configs. Schema rejected it with "Unrecognized key", gateway restart-looped. Had to revert.

## 2. Self-upgrade failures (OpenClaw pattern)

**NEVER run `openclaw update` from a chat session** — it kills its own process mid-install, destroys `/usr/bin/openclaw` symlink, orphans chrome processes, and aborts mid-telegram-bundle-rebuild.

Safe pattern: run it as a separate shell session the user controls, or via a standalone script that stops the gateway first.

**Real incident (2026-04-17):** `openclaw update --yes --channel stable` broke telegram channel bundle, left openclaw command gone for ~90s during restart cycle.

## 3. "Gateway started" is NOT "gateway working"

A ready-log line only proves the process booted. Must verify with real traffic:

```bash
openclaw agent --agent main --message 'test' --json --timeout 60 | grep -i 'error\|usage'
# check token usage actually changed
```

**Real incident (2026-04-17):** LCM plugin loaded fine (`threshold=0.75, mode=deferred`), but compaction wasn't actually reducing tokens — summaries were empty stubs. Only real traffic revealed this.

## 4. Compaction telemetry — always check tokensAfter

When testing a summarizer, look at the telemetry row, not just "compaction event fired":

- `tokens_before`: should be > threshold
- `tokens_after`: should be < `tokens_before` — **if null, compaction isn't actually compressing**
- `summary_len`: high is fine, but read the summary — boilerplate template ("No prior history. None.") means the summarizer isn't being given real content

## 5. Adjacent systems that can break

When changing config A, check adjacent systems B/C/D:

| Changed | Could Break |
|---------|-------------|
| Model config | Cron jobs using that model |
| Plugin config | Other plugins depending on its output |
| Channel config | Bot bundles, sidecars |
| Binary version | Symlinks, global npm/cargo bins |
| Context window | Compaction math downstream |

**Real incident (2026-04-17):** Bumped `contextWindow` from 32768 to 48000 without checking if `maxOutputTokens`, `reserveTokensFloor`, or cron job prompt budgets assumed the smaller number.

## 6. Guardrail alerts vs. guardrail enforcement

"Audit script detected X" ≠ "X was removed". Read the actual script:

```bash
# check if it's purely alerting or also cleaning
grep -E 'rm|unlink|delete|mv.*bak' <guardrail-script>
```

**Real incident (2026-04-17):** `APPROVED_AGENTS` guardrail detected ghost `voice` agent dir at 10:54:04 and wrote `GUARDRAIL_ALERT` file — but never removed the dir. Kept alerting every 10min.

## 7. Cron failure status ≠ context overflow

"Failing cron" can look like context overflow but often isn't. Pull the actual error:

```bash
openclaw cron runs --id <id> --limit 2 | grep -E 'error|status'
```

**Real incident (2026-04-17):** 3 crons marked `status=error`. Assumed compaction problem. Real cause: `⚠️ API rate limit reached` from the model provider.

## 8. Lossless-claw deferred mode is a no-op

Default `proactiveThresholdCompactionMode: "deferred"` means LCM defers compaction to background — never actually shrinks the context the next turn sees. For agents hitting context overflow every turn, set `"inline"`:

```json
"plugins": {
  "entries": {
    "lossless-claw": {
      "config": { "proactiveThresholdCompactionMode": "inline" }
    }
  }
}
```

Verify with a turn showing `input >> context_window` → `input sent to model < context_window`.

## 9. System prompt size budget

Before tuning compaction, measure the system prompt. If the system prompt alone exceeds the model's context, no amount of compaction helps. Check:

```bash
# from a real turn's JSON output
agentMeta.usage.input  # turn 1 input == approx system prompt size
```

Plugins (browser, exa, active-memory, etc.) each add to system prompt. Disable unused ones before fighting compaction.

## 10. Measurement-first rule (MANDATORY for any config/removal decision)

**NEVER remove, disable, or resize something because you assume it's "unused" or "too big." Measure first.** Saying "disable unused plugins" without reading tool-use events is a guess, not a fix.

### Pattern — measure BEFORE touching config

| Decision | Measurement to run first |
|---|---|
| "Disable plugin X" | Grep session JSONL for `tool_use` / `toolCall` events naming X's tools over last 14 days |
| "System prompt is too big" | `openclaw agent --message 'size check' --json \| grep '"input"'` — record before/after each config change |
| "This skill isn't used" | Check `~/.claude/skill-usage.jsonl` or run `skill-usage-report.py` |
| "This command rotted" | `skill-drift-check.sh` — don't delete a reference without evidence |
| "This compaction knob turns left" | Read the plugin source: `grep -oE 'toKnobName[^}]+' $HOME/.openclaw/extensions/<plugin>/dist/*.js` to see the enum / direction |

### Real incident (2026-04-17)

Lowered `reserveTokensFloor` from 20000 → 12000 to "trigger compaction earlier." OpenClaw's own error message later said "set it to 20000 or higher." The knob turned the opposite direction of what I assumed. Fixed by measuring first next time.

Then proposed "disable browser + exa plugins (unused)." Tool-usage scan showed browser had 8 calls + exa had 13 calls in 14 days — both used. Only `anthropic` plugin (0 calls) was safe to disable. Saved 440 tokens per turn.

### Pre-decision checklist

Before committing to a config change:
1. What is the baseline number? (tokens, errors, latency — whatever the change claims to affect)
2. How will I re-measure the SAME number after the change?
3. If the number didn't improve, will I revert or double down?

If step 3 is "double down," you're about to make a mistake. Revert.

---

## 11a. Don't grep stdout for "error" when stdout contains the close reason

A reaper/closer that uses `grep -qiE 'error|failed'` against `bd close` output will false-positive when the close reason text itself contains "error" (e.g., closing a cron-tracking bead with reason `"Cron run error: timed out"` triggers the grep even though the close succeeded).

Fix: check the **exit code** of `bd close`, not the stdout text. Or grep for a positive marker (`✓ Closed`).

```bash
# WRONG
close_out=$(bd close "$id" --reason="$reason" 2>&1)
if echo "$close_out" | grep -qiE 'error|failed'; then ...

# RIGHT
if ! close_out=$(bd close "$id" --reason="$reason" 2>&1); then
  log "FAIL: $close_out"; ERRORS=$((ERRORS + 1)); continue
fi
```

**Real incident (2026-04-25):** cron-bead-reaper logged `WARN: close may have failed for HOME-8d1f` even though the bead was successfully CLOSED in the DB. The close reason contained the word "error" (it was reporting that the cron job had timed out), and the reaper grep matched it.

## 12. Auth provider cutover (dev → prod instance) blind spots

> **Tooling shortcut for Clerk specifically**: the `clerk` CLI (npm `clerk` package, currently 1.0.3) is the supported way to manage everything in this section without writing curl. `clerk skill install` already loaded an agent skill at `~/.claude/skills/clerk/`. Useful commands:
> - `clerk doctor [--fix]` — single-shot health check (auth, link, env, instance reachability)
> - `clerk env pull --instance prod` — write `pk_live_*` + `sk_live_*` directly into `.env.local`
> - `clerk config pull --instance prod` — dump live instance config as JSON (alternative to `/v1/environment`)
> - `clerk config patch --instance prod --json '{"...": ...}'` — partial config update (alternative to dashboard click-through)
> - `clerk api /v1/users --instance prod` — authenticated Backend API call
> - `clerk apps list` — find app/instance IDs without dashboard
>
> Auth: `clerk auth login` (OAuth, host-only) OR per-command `--secret-key sk_live_...` for agent/CI mode. When the CLI prints "Host-only Clerk state ... unavailable in agent mode", treat any auth/link/env failure as untrusted and rerun on the host shell.


When migrating an auth provider from a development instance to a production instance (Clerk, Auth0, Supabase, Firebase, etc.), these are the gotchas — every one of them appeared in a single 2026-04-30 cutover:

### 12a. Hardcoded fallback in source bypasses every env mechanism
CI builds run without the gitignored `.env`, so any `import.meta.env.X || HARDCODED_FALLBACK` pattern ships the **fallback** value to production — even when local `.env` and CF Worker secrets are correctly set. If the fallback is a dev-instance key (`pk_test_*`, `*.accounts.dev`, etc.), prod silently runs against the dev provider with its rate caps and broken email deliverability.

```bash
# Sweep source + built bundle for dev-flavored auth refs that would ship to prod
grep -rEn 'pk_test_|sk_test_|\.clerk\.accounts\.dev|prime-rhino' src/ \
  | grep -vE '\.test\.|__tests__|/node_modules/|"(pk|sk)_(test|live)_"\s*[,;)]'
grep -rE 'pk_test_|prime-rhino|\.clerk\.accounts\.dev' dist/client/assets/*.js | grep -v '\.map:'
```
**Fix**: replace fallback with prod value (publishable keys are public-by-design) OR throw at module scope so CI fails loudly on missing env.

### 12a-1. Worker binding dry-run is mandatory for Worker-only auth cutovers
Cloudflare Worker apps can ship dev auth through `wrangler.toml` / `wrangler.json` bindings even when `.env.local`, Clerk CLI output, and local tests look correct. `clerk env pull --instance prod` only updates local env files; it does not prove the Worker upload will use prod bindings.

```bash
# Static scan for dev auth fingerprints and auth binding names
rg -n 'pk_test_|sk_test_|\.accounts\.dev|CLERK_PUBLISHABLE_KEY|CLERK_JWT_ISSUER|CLERK_JWKS_URL' \
  wrangler.toml wrangler.json src --glob '!*.test.*' 2>/dev/null

# Effective upload scan
npx wrangler deploy --env="" --dry-run --outdir /tmp/worker-dryrun 2>&1 | tee /tmp/worker-dryrun.log
rg 'CLERK_PUBLISHABLE_KEY.*pk_test|CLERK_JWT_ISSUER.*accounts\.dev|CLERK_JWKS_URL.*accounts\.dev|pk_test_|sk_test_' \
  /tmp/worker-dryrun.log
```

If the dry-run shows `pk_test_*`, `sk_test_*`, or `.accounts.dev`, production is still wired to dev auth. Fix Worker vars before deploy.

ImproveBayArea incident (2026-05-09): production Clerk existed, but the effective Worker deploy still exposed development auth fingerprints. The fix was to target the real production Clerk application/domain, create/verify Clerk DNS records until the Platform domain status was complete, set the Worker secret last, run `wrangler deploy --dry-run --env=""`, then fetch live HTML and prove it showed `pk_live_*` with no `pk_test_*` or `.accounts.dev`.

### 12b. Custom-domain auth providers need DNS records BEFORE the cutover
Most prod-tier auth providers expose a custom subdomain (`clerk.<root>`, `auth.<root>`, `accounts.<root>`). Without the matching CNAMEs, the prod publishable key resolves to **nothing** — the frontend SDK fails to load entirely, breaking sign-in worse than the dev-instance state did.

For Clerk specifically, **5 CNAMEs** are required (frontend-api, accounts portal, mail, 2× DKIM):
```
clerk          → frontend-api.clerk.services
accounts       → accounts.clerk.services
clkmail        → mail.<instance>.clerk.services
clk._domainkey → dkim1.<instance>.clerk.services
clk2._domainkey → dkim2.<instance>.clerk.services
```
All must be DNS-only (`proxied:false` on Cloudflare) — proxy-orange-cloud breaks SSL handshake. After adding, verify:
```bash
for h in clerk accounts clkmail; do dig +short "$h.<root>" CNAME; done
curl -sI -m 8 "https://clerk.<root>/v1/environment" | head -1   # expect HTTP/2 200
echo | openssl s_client -servername "clerk.<root>" -connect "clerk.<root>:443" 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName 2>/dev/null   # cert must cover the subdomain
```

### 12c. Worker JWT secret swap creates an atomic-cutover window
Setting the worker's auth secret to `sk_live_*` while the bundle still ships `pk_test_*` (or vice versa) makes EVERY currently signed-in user 401 instantly: their dev-instance JWT fails verification against the prod JWKS. The bundle deploy and worker secret swap must happen in a tight window. Do the secret last, immediately before redeploy + cache purge, and accept the brief logout window.

### 12d. DB user-id orphans across instance migrations
Every Clerk/Auth0/Firebase instance issues its own user IDs. After cutover, the new prod instance issues **NEW** IDs — your existing rows in `users.id` (and every FK pointing at it) are now orphans. On first sign-in, the new ID won't match anything and the user appears to have lost all data.

Audit every FK that references the auth user id:
```bash
# SQLite/D1 — find every column that references users(id) or user_id
sqlite3 db.sqlite "SELECT m.name, p.name FROM sqlite_master m JOIN pragma_table_info(m.name) p WHERE m.type='table' AND p.name LIKE '%user_id%' ORDER BY m.name"
# Postgres equivalent:
psql -c "SELECT table_name, column_name FROM information_schema.columns WHERE column_name ~ 'user_id|^user$' ORDER BY 1,2"
```
**Fix pattern**: add an email-keyed reconciliation step in your auth middleware — when a JWT's `sub` doesn't match any `users.id` but the email does match an existing row, atomically remap `users.id` and every FK column to the new auth-provider ID in one batch with `PRAGMA defer_foreign_keys=ON` (SQLite/D1) or a single transaction (Postgres). Order: update FK columns first, `users.id` LAST. Keeps case data attached to the right user without forcing a destructive migration.

### 12e. OAuth providers (Google/Apple/etc.) cannot be carried from dev
Dev auth instances use the auth-platform-vendor's own shared OAuth client (`Clerk Inc.`'s GCP project for Google, etc.). Prod instances **require your own** OAuth client per provider, registered in the provider's console (`console.cloud.google.com`, `developer.apple.com`, etc.) with the prod auth subdomain in the redirect URI. There is nothing to "copy" — the dev shim's credentials are owned by the auth vendor. Plan for per-provider setup: Google ~10 min, Apple ~30 min (Services ID + key + JWT generation).

### 12f. OAuth consent screen "Testing" status caps users at the test list
Even after creating a Google OAuth Web client, if the consent screen is in **Testing**, only emails on the test-user list can authenticate (max 100). Production traffic gets a 400 "access blocked." Always **publish the app** (Audience → Publish app → Confirm) immediately after creating the client. If you're requesting only basic scopes (`email`, `profile`, `openid`), no Google verification is required to publish.

### 12g. Prod auth instance default settings can block migration
Some providers default a fresh prod instance to require fields a dev instance didn't (Clerk's prod instance shipped with `phone_number.required=true` and `username.required=true`). This blocks Backend-API user creation with `[\"username\" \"phone_number\"] data doesn't match user requirements set for this instance`. Check the public env config FIRST:
```bash
curl -s "https://clerk.<root>/v1/environment" \
  | jq '.user_settings.attributes | {phone:.phone_number.required, username:.username.required, email:.email_address.required}'
```
Toggle off in the dashboard before bulk migration, save, re-verify the env config flipped to `false`.

### 12g-1. Clerk production domain status is the source of truth
For Clerk, DNS records existing in Cloudflare is not enough. Before pointing a Worker/frontend at `pk_live_*`, verify the production app domain is complete through Clerk Platform status:

```bash
clerk apps list --json
clerk api --platform "/platform/applications/<app_id>/domains/<domain>/status"
```

Require the domain/status response to show complete DNS/SSL/mail readiness. If local DNS lags, use a browser or `curl --resolve` probe against `https://clerk.<root>/v1/environment`, but do not treat `pk_live_*` as safe until Clerk itself reports the domain complete.

### 12h. Auth dashboard React inputs need native event dispatch (not click)
For dashboards that render switches as `<input role=switch>` controlled by React state, `.click()` updates the DOM but doesn't fire React's `onChange` — settings revert silently after Save. The fix:
```js
const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'checked').set;
setter.call(input, false);
input.dispatchEvent(new Event('input', {bubbles:true}));
input.dispatchEvent(new Event('change', {bubbles:true}));
```
Or just use Kuri/CDP `click` (real CDP click events bubble correctly through React). Confirm the change persisted by re-reading the public env config endpoint, NOT by re-snapshotting the dashboard.

### 12i. Hardware-bound Google sessions can't be cookie-extracted
Modern Chrome stores Google session cookies (SID, HSID, `__Secure-1PSID`, etc.) bound to the OS keychain via DBSC (Device-Bound Session Credentials). Tools like unbrowse that read Chrome's SQLite cookie DB get the account-list cookies but not the auth tokens — every request lands on the passkey challenge. `gcloud` works because it has its own OAuth refresh token cached at `~/.config/gcloud/`, separate from Chrome.

To drive Google Cloud Console (or any Google product) headlessly, the realistic options are:
1. CDP-attach to the user's existing logged-in Chrome — but Chrome refuses CDP on the default user-data-dir for security ("DevTools remote debugging requires a non-default data directory")
2. Drive the REAL Default profile with fcdp (`~/tools/fcdp/fcdp`) — sign-in already exists there; no separate profile, no `--remote-debugging-port`
3. For things `gcloud` covers, prefer `gcloud auth application-default print-access-token` + the Cloud REST API (works headlessly forever once user has done `gcloud auth login` once)

For "Sign in with Google" Web App OAuth client creation specifically, there is **no public CLI/REST API** — it's Cloud Console UI only. `gcloud iam oauth-clients` is for Workforce Identity Federation (different product) and `gcloud iap oauth-clients` is for IAP-protected services with restricted redirect URIs. Plan for browser-driven setup.

### 12j. Build cache + CDN cache + browser cache compound
After fixing prod auth and redeploying, three caches can each independently serve the broken old bundle:
- `dist/` from a previous build (fix: `rm -rf dist && npm run build` always)
- CF edge cache (fix: zone purge + verify `cf-cache-status` is no longer `HIT`)
- Browser HTTP cache + Service Worker (fix: hard reload + `await navigator.serviceWorker.getRegistrations().then(rs=>rs.forEach(r=>r.unregister())); await caches.keys().then(ks=>ks.forEach(k=>caches.delete(k)))`)

A successful `wrangler deploy` is necessary but not sufficient. Always verify by curl-fetching the live page with a cache-bust query string and grepping the served bundle for the dev fingerprints from §12a.

### 12l. Stale-worktree / sibling-checkout clobber pattern (MANDATORY pre-deploy sweep)

The most insidious cutover bug is **not** the original silent-fallback in App.tsx — it's that fixing main doesn't reach **other on-disk checkouts of the same repo**. Background agents (evo's autonomous loop, conductor task workspaces, other Claude Code sessions running with `--allow-dangerously-skip-permissions`, codex-app sessions, manual `git worktree add`) can `npm run build && wrangler deploy` from any of them. A single stale checkout at a pre-cutover commit silently re-ships `pk_test_*` to prod.

Real incident (2026-04-30): 4+ hours after the prod cutover, a deploy at 21:09 UTC re-clobbered prod with bundle `index-KhTJ795w.js` shipping `pk_test_*`. Source: 28 `.evo/run_*/worktrees/exp_*` worktrees + 2 `~/conductor/.../aiva-frontend` checkouts + 2 `~/<other>/AIVA-Frontend-*` checkouts, all at pre-cutover commits with the old `pk_test` fallback baked into `App.tsx`. Worker logs showed `kid='ins_34kspu...'` (dev) doesn't match `JWKS available: ins_3D5KcapfxW...` (prod) — every authenticated `/api/*` 401'd for every signed-in user.

**Pre-deploy sweep — run BEFORE every cutover-adjacent deploy** to enumerate all on-disk checkouts and catch any that still have the dev fingerprint:

```bash
# 1. List all git worktrees of the current repo (these inherit the same git dir)
git worktree list

# 2. Sweep machine-wide for ANY checkout matching the auth fingerprint pattern.
#    Don't trust the worktree list alone — cloned-elsewhere checkouts won't appear there.
find ~ -maxdepth 6 -name "App.tsx" -path "*react-app*" 2>/dev/null \
  | xargs grep -l "pk_test_cHJpbWUtcmhpbm8" 2>/dev/null

# 3. Same regex against the Vite-baked dist/ in each checkout (catches cases where the
#    source has been patched but a stale dist/ still contains the dev key).
find ~ -maxdepth 8 -path "*/dist/client/assets/index-*.js" 2>/dev/null \
  | xargs grep -l "pk_test_cHJpbWUtcmhpbm8\|prime-rhino-99\|\.clerk\.accounts\.dev" 2>/dev/null
```

**Fix all hits before deploying.** Three options per hit:
- Disposable experiment worktree → `git worktree remove --force <path>` + `git worktree prune`
- In-use sibling checkout → `sed -i.bak 's|"pk_test_<...dev base64...>"|"pk_live_<...prod base64...>"|g' <file>`
- Unrelated repo with same filename → leave alone (verify with `git -C <dir> remote -v`)

**Permanent guard — commit two layers**:

1. **Module-level throw in `App.tsx`** (or equivalent entry point): refuse to compile dev fingerprints into a prod build.
   ```ts
   const CLERK_KEY_FALLBACK = "pk_live_<base64>";
   if (!CLERK_KEY_FALLBACK.startsWith("pk_live_")) {
     throw new Error("CLERK_KEY_FALLBACK must be pk_live_* — refusing to compile dev-instance key into production bundle");
   }
   ```

2. **`package.json` post-build grep** that exits 2 on any dev-instance fingerprint in `dist/`:
   ```json
   "build": "tsc -b && vite build && bash -c 'if grep -rEq \"pk_test_[A-Za-z0-9_-]{20,}|prime-rhino-99|\\.clerk\\.accounts\\.dev\" dist/client/assets/index-*.js 2>/dev/null; then echo BUILD ABORT: dev-instance Clerk fingerprint detected in production bundle 1>&2; exit 2; fi'"
   ```
   This stops `wrangler deploy` from running even if it gets invoked from a stale checkout that bypasses #1 somehow.

Both layers are necessary. Layer 1 catches dev-key reverts in source. Layer 2 catches dev-key strings smuggled in via dependencies, codegen, or any path that doesn't go through `App.tsx`. Both are committed in main so every checkout that pulls main automatically inherits them.

### 12k. Live verification: hit the actual /sign-in flow, not just the env config
Public env config (`/v1/environment` for Clerk) only proves the **instance** is reachable. The real test is clicking "Continue with Google" in a fresh browser session and observing the redirect chain:
- Lands on `accounts.google.com/o/oauth2/v2/auth?client_id=<YOUR PROD CLIENT>` (verify client_id is the one you just created, NOT a vendor-shared one)
- Returns to `clerk.<root>/v1/oauth_callback` with code
- Redirects to your app at the post-signin URL
- App's worker accepts the prod JWT (no 401 on `/api/users/me`)
- Database row exists or got reconciled by email

Skip any of these and you'll ship a "fixed" cutover that's still broken for a subset of users.

---

## 11. JSON config backups before every patch

```bash
cp <config>.json <config>.json.bak-$(date +%Y%m%d-%H%M%S)
```

Makes post-incident rollback trivial. Already a memory rule; include it in every infra fix commit.

---

## 13. launchd / cron health checks behave DIFFERENTLY than your interactive shell (MANDATORY — 2026-05-30)

A health-check / watchdog that passes when you run it by hand over SSH can **false-positive in its real launchd/cron context**. Verify it where it actually runs, not just interactively.

**The trap (2026-05-30, Hermes gateway watchdog):** the watchdog judged "is the job loaded?" with
```bash
launchctl list 2>/dev/null | grep -q "$LABEL"   # WRONG inside a launchd-spawned process
```
In its long-lived launchd `StartInterval` session, **`launchctl list` emits zero stdout** (the session/bootstrap port doesn't resolve the GUI domain the way an interactive shell does). With stderr `>/dev/null`, `grep` saw empty input → returned false on EVERY tick → declared a perfectly-healthy gateway (pid stable, runs=1, never exited) "DOWN" every 300s. It then `bootstrap`ped, got **rc=5**, and wrongly alerted "auto-reload FAILED." 32 false alerts, zero real outages.

**Rules for any launchd/cron liveness check or watchdog:**
1. **Use exit-code probes, not stdout-parsing of `launchctl list`.** Context-independent: `launchctl print "gui/$(id -u)/<label>" >/dev/null 2>&1` (exit 0 = loaded). For a process: `pgrep -f "<stable-substring>"`. Never `launchctl list | grep`.
2. **`launchctl bootstrap` rc=5 = "Input/output error" = the label is ALREADY loaded.** Treat as a healthy no-op — never as a failure to alert on. (To restart an already-loaded job use `launchctl kickstart -k gui/$UID/<label>`, NOT bootstrap.)
3. **Defer to KeepAlive.** If the job is loaded, launchd KeepAlive owns the process lifecycle (restarts within `ThrottleInterval`). A watchdog should only `bootstrap` when the job is GENUINELY unloaded (`print` rc≠0) — not when the process is momentarily gone. Two managers double-bootstrapping = churn + false alerts.
4. **Require a SUSTAINED abnormal state** (e.g. 2–3 rechecks several seconds apart, all failing) before acting/alerting, to absorb restart windows and launchctl settling.
5. **Alert ONLY after an action you actually took, reflecting the verified after-state** (`print`+`pgrep`), never on the action's return code alone. Silent no-op when healthy.
6. **Verify the fix in the REAL context:** `launchctl kickstart gui/$UID/<watchdog-label>` to run it as launchd does, then confirm the log shows a silent no-op (no new alert) — running it from your interactive SSH shell would NOT reproduce the launchd-session bug.

KeepAlive note: `KeepAlive=true` restarts on ANY exit (including clean drains); `KeepAlive={SuccessfulExit:false}` will NOT restart a clean (exit-0) shutdown — pick `true` for an always-on agent, and add `ThrottleInterval` to avoid crash-loops.


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

## Agent-driven / on-demand bug — don't declare "resolved" from a quiet window

When a crash/failure is triggered by an **agent or client connecting on demand** (an MCP server spawned when Claude/Codex connects, a webhook, a user action) instead of a schedule, its timing is **irregular** — clusters when the driver is active, silence when it sleeps. Two traps:
1. **`launchctl kickstart`/cron-trigger tests find nothing** — the bug isn't a scheduled job, so triggering every job proves nothing. Absence under job-triggering ≠ fixed.
2. **A quiet window reads as "resolved."** NEVER conclude resolved from "no recurrence in N minutes" for an agent-driven bug — wait for the real trigger, or plant a **self-reporting trap** that names the cause on the next occurrence (a chokepoint command-logger + a crash/`WatchPaths` watcher correlated by **parentPid**).

Real: the `hoptodesk-mcp-bridge.py` SSH finalization crash (2026-06-24) looked "resolved" for 96 min because the laptop's MCP client simply wasn't connecting; it recurred at 00:21. A PPID-correlated trap named the exact command instantly. See `infrastructure-patterns.md` #22.
