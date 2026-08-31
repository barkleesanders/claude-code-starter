# Auth Cookies — Diagnostic Guide

> Load when debugging 401/403 errors, "session expired" symptoms, or any "this worked yesterday" login-adjacent bug. Companion to the a cookie-export CLI.

## Fast triage

Symptom: script gets 401/403 from a site that was working.

```bash
# 1. Does the jar have cookies for this domain?
cookies list | grep -i <domain>

# 2. Are they still valid?
cookies validate <domain>
#   exit 0 → cookies are fine, bug is elsewhere
#   exit 1 → cookies are stale, go to step 3

# 3. Can we refresh autonomously?
cookies refresh <domain>
#   success → retry the script
#   "no headless module" → user must click extension (below)

# 4. Manual refresh fallback
#    User logs into site in Chrome → clicks Get-cookies.txt-LOCALLY → Save.
#    Watcher imports within 5s. Retry.
```

## Common root causes for auth failures

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| 401 on every request to domain | Session expired (TTL or server-side invalidation) | `cookies refresh <domain>` or manual re-import |
| 403 "Forbidden" only on some endpoints | CSRF token stale, not the session itself | Site may need CSRF refresh in site module — see `sanfrancisco.nextrequest.com.mjs` pattern |
| Redirect loop to `/login` | Session cookie missing entirely | Check `~/.cookies/<domain>.txt` is non-empty; if it is, cookie scope/path may be wrong |
| Works logged in to Chrome, fails from script | Extra cookies Chrome sets (Cloudflare `cf_clearance`, PerimeterX `_px`) not in jar | Re-export via extension (captures all cookies for domain) |
| Works from Mac, fails on VPS | Jar didn't rsync, or VPS has a stale copy | `ls -la $HOME/.cookies/<domain>.txt` via SSH; re-trigger local watcher by touching a download |
| Intermittent 401s | Site rotates session ID mid-flow (seen on some Verint forms) | Site module needs to preserve session across navigations — don't `newContext()` between steps |

## When cookies aren't the root cause

Rule out cookies before deep-debugging elsewhere:

1. `cookies validate <domain>` exits 0
2. `curl -b ~/.cookies/<domain>.txt <endpoint>` manually returns expected status
3. Script's HTTP layer is actually loading the cookie file (log the path it's using)

If all three pass, the bug is in request construction (headers, body, method), not auth state.

## "This domain has no module" → decision tree

```
Does the site require MFA / captcha / device challenge?
├── Yes → leave source=manual. User clicks extension when cookies go stale.
│          Document the expected re-auth cadence in metadata.
└── No → write a site module:
         1. Open devtools Network tab, log in by hand once
         2. Note the form selectors and the POST endpoint
         3. Copy ~/tools/<cookie-cli>/lib/sites/sanfrancisco.nextrequest.com.mjs
         4. Adapt selectors and validateUrl
         5. Add creds to ~/.config/<cookie-cli>/credentials.env
         6. Set source=headless in metadata
         7. Test: cookies refresh <domain> → cookies validate <domain>
```

## Don't do this

- Don't hardcode cookies in source files. Always read via `cookies get` / `cookies.py` / `cookies.cjs`.
- Don't store credentials in site modules. They read from env (`credentials.env`).
- Don't suppress 401 errors with retry logic. Let them bubble so refresh logic fires.
- Don't add a new site module for a Composio-owned service (Gmail, Calendar, Drive). Use Composio actions instead.

## Server-side cookie not reaching browser (Hono / CF Workers)

Symptom: middleware calls `setCookie(c, ...)` or `c.header("Set-Cookie", ...)` but `Set-Cookie` is missing from the actual HTTP response. End-to-end attribution silently breaks.

**Three traps, in order of frequency:**

### 1. `c.header()` defaults to OVERWRITE — must use `{append: true}` for cookies

```ts
// ❌ WRONG — outer middleware silently clobbers inner middleware's cookie
c.header("Set-Cookie", `aiva_cf=...; Path=/`);

// ✅ CORRECT — both cookies coexist in the final response
c.header("Set-Cookie", `aiva_cf=...; Path=/`, { append: true });
```

Hono middleware order matters: outer middleware's post-`next()` `c.header()` runs LAST and overwrites inner cookies if not appended. Real bug 2026-05-05: `securityHeaders` (outer) clobbered `visitTracking` (inner) `aiva_visit` for ~3 hours of debugging.

**Rule of thumb:** Any `c.header("Set-Cookie", ...)` call MUST use `{append: true}`. Same for any header that supports multiple values (`Set-Cookie`, `Vary`, `Link`).

### 2. SPA catch-all returns `ASSETS.fetch()` directly — set cookie AFTER `await next()`

```ts
// ❌ WRONG — c.header() before next() is dropped when handler returns
// `c.env.ASSETS.fetch(c.req.raw)` directly
return async (c, next) => {
  c.header("Set-Cookie", "...");  // lost
  return next();
};

// ✅ CORRECT — set after next() returns; same pattern securityHeaders uses
return async (c, next) => {
  await next();
  c.header("Set-Cookie", "...", { append: true });  // merges into final response
};
```

### 3. `hono/cookie`'s `setCookie(c, ...)` only works for handler-built responses

For middlewares wrapping a handler that returns `Response` directly (e.g. `c.env.ASSETS.fetch`), prefer `c.header("Set-Cookie", ..., {append: true})` AFTER `await next()`. `setCookie()` writes to the context's pending response builder which is discarded when a handler returns a Response object.

### Diagnostic ladder

```bash
# 1. Real-browser-shaped curl (NOT default curl — Accept *⁄* breaks Accept-gated middleware)
curl -sI \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/147.0.0.0 Safari/537.36" \
  "https://yourdomain.com/?cb=$(openssl rand -hex 4)" | grep -iE "set-cookie|cf-cache"

# 2. If Set-Cookie is missing but cf-cache-status: HIT → response is cached pre-fix.
#    Purge zone cache:
curl -sX POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/purge_cache" \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_API_KEY" \
  -H "Content-Type: application/json" -d '{"purge_everything":true}'

# 3. If Set-Cookie still missing but ANOTHER Set-Cookie IS present →
#    you're being clobbered. Search for c.header("Set-Cookie" without {append:
grep -rn 'c\.header("Set-Cookie"' src/worker/ | grep -v "append: true"

# 4. If middleware path-gates on Accept header, verify your test request actually
#    matches. curl default is `Accept: */*` which fails `accept.includes("text/html")`.
```

**Note**: CF Workers Static Assets has its OWN cache layer separate from zone-level Cache Rules. A `set_cache_settings: { cache: false }` rule in `http_request_cache_settings` does NOT bypass the static-asset cache. The fix is in worker code (`run_worker_first: true` + worker-set `Cache-Control: private` + `CDN-Cache-Control: no-store`), not in zone Cache Rules.

## Related CLI

```bash
cookies status                 # jar health overview
cookies list                   # all domains + age
cookies validate <domain>      # check this one
cookies refresh <domain>       # force refresh
cookies refresh-stale          # sweep all (what the cron runs)
```

Full reference: a cookie-export CLI at your own install.

## Firebase Google-auth token capture (device-free) — for driving an app's API from a CLI

When an Android/iOS app authenticates with **Firebase Auth + Google Sign-In** and you need its
token to call the backend from a CLI, you do NOT need the device (and it's the way around
PairIP / FBE / un-rootable Play images). Firebase Google sign-in is `signInWithIdp`; mint the
token via Google's OIDC **implicit** flow in the user's logged-in Chrome:

1. From the APK get: Firebase `apiKey`, `project_id` (→ authDomain `<project>.firebaseapp.com`),
   and the **web OAuth client** (`<sender_id>-xxx.apps.googleusercontent.com`).
2. `fcdp open` →
   `accounts.google.com/o/oauth2/v2/auth?client_id=<WEB>&redirect_uri=https://<project>.firebaseapp.com/__/auth/handler&response_type=id_token&scope=openid%20email&nonce=<rand>&state=<rand>&prompt=consent&login_hint=<email>`
3. Read the Google id_token from the redirect **fragment** on `.../__/auth/handler#…id_token=…`
   (that page shows a harmless "missing initial state" error — token's still there):
   `fcdp js <tab> "new URLSearchParams(location.hash.slice(1)).get('id_token')"`.
4. Exchange: `POST identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=<apiKey>`
   `{postBody:"id_token=<G>&providerId=google.com",requestUri:"http://localhost",returnSecureToken:true}`
   → `{idToken, refreshToken}`. Refresh forever via `securetoken.googleapis.com/v1/token`.

Traps: only the app's OWN web client works (Playground/gcloud/device-code tokens are rejected
`audience is not for this project`); in automated Chrome `signInWithPopup`→`popup-blocked` and
`getRedirectResult` is flaky (use the raw fragment read); backends often mix `Bearer` (public/
submit) with AWS-IAM/SigV4 (user-account routes). **Full playbook:**
`~/.claude/skills/decompile/references/android-re.md` §"Firebase Google-auth token capture".
Verified 2026-08-01 on Solve SF (`com.woahfinally.solvesf`).
