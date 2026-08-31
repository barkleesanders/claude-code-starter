---
name: betterauth
description: >-
  Stand up, migrate to, or debug Better Auth on Cloudflare Workers + D1 — the auth
  stack behind improvebayarea.com and example.com. Use when building auth into a
  NEW site from scratch (ordered greenfield path + the verified core D1 schema), when
  adding auth to an existing Worker, migrating off a hosted provider, wiring
  Google/Apple social sign-in, adding
  passkeys/2FA/magic-link/email-OTP, writing a plugin's D1 migration, or debugging
  "Invalid token", "account_not_linked", a native iOS sign-in that fails after the
  OAuth sheet succeeds, a social button that won't appear inside a Capacitor
  webview, a "Turn on two-factor" button that does nothing, a passkey ceremony that
  reports "cancelled or timed out", or a CORRECT password that reports the session
  did not stick. Encodes the traps that cost real deploy cycles on both sites, each
  with the probe that proves it.
---

# Better Auth on Cloudflare Workers + D1

Both of the user's auth-bearing sites declare **better-auth `^1.6.25`** on a Worker
with a D1 binding. This skill is the delta between "the docs" and "what actually
broke."

**Read the traps before writing code.** Every one below cost at least one deploy
cycle, and each carries the command that proves it rather than an assertion.

## Current state (verify, don't trust this table — it is a cache)

Verified 2026-08-05.

| | improvebayarea.com | example.com |
|---|---|---|
| Repo | `~/tools/improvebayarea` | `~/AIVA-Frontend` |
| Auth file | `src/auth.ts` | `src/worker/auth.ts` |
| Shape | Hono SSR, inline client JS in `src/ui.ts` | React SPA + Hono SSR |
| **Installed** better-auth | **1.6.26** | **1.6.25** |
| Plugins | `bearer`, `magicLink`, `emailOTP`, `twoFactor`, `passkey` | `bearer`, `emailOTP`, `twoFactor`, `passkey` |
| Native social | **yes** — `@capgo/capacitor-social-login`, live | plugin installed + SPM-linked, **no JS call site** |
| Native audience fix | Google + Apple (Trap 1) | Apple present; **Google still absent** — no iOS OAuth client exists yet |

⚠️ **Identical `^1.6.25` ranges, different installed versions.** Adding
`@better-auth/passkey@^1.6.26` to IBA let npm re-resolve the caret and float core
to 1.6.26; AIVA never re-installed and sits at 1.6.25. `package.json` therefore
**cannot** tell you what is running — the plugin schema you transcribe a migration
from (Trap 8) is the *installed* one. Always read `node_modules`.

Re-check with:
```bash
node -e "const p=require('./package.json').dependencies;
console.log('range:',p['better-auth'],'| installed:',require('better-auth/package.json').version)"
grep -nE "socialProviders|plugins: \[" -A 20 <auth-file>
```

⚠️ **npm latest has moved past this table — re-check before pinning a NEW project (added 2026-08-30).**
Verified live on 2026-08-30: **`better-auth` latest on npm is `1.7.2`** (published 2026-08-26), while
both sites above are still on **1.6.26 / 1.6.25** — a minor version behind. The table is accurate about
*these two sites*; it is NOT a version recommendation for a greenfield build, and reading it as one is
exactly the mistake it invites. This bit for real: on 2026-08-30 a new Workers project was briefed with
`better-auth ^1.6.26` copied straight out of this file, 25 days stale, and the pin had to be corrected
mid-build.

**So for any NEW site, resolve the version from the registry, not from here:**
```bash
curl -s https://registry.npmjs.org/better-auth | python3 -c "import json,sys;d=json.load(sys.stdin);v=d['dist-tags']['latest'];print(v, d['time'][v][:10])"
```
Then install, and transcribe every plugin migration from the schema in `node_modules` (Trap 8) — a
1.6.x → 1.7.x jump can move a core or plugin table, and this file documents the 1.6.x shape.

## Standing up a NEW site (do it in this order)

Most of this skill is written from two live migrations, so it reads as "fix the
thing that broke." On a greenfield site nothing has broken yet — follow this order
and most traps never fire. Traps 7 (id preservation) and the decommission section
do not apply at all; skip them.

| # | Step | The trap it pre-empts |
|---|---|---|
| 1 | Create the D1 database + binding `DB`; write the **core schema** migration (below) and apply it `--remote` | Plugin/core code writes these tables on first use; a missing column is a generic 500 (Trap 11) |
| 2 | `openssl rand -base64 32 \| wrangler secret put BETTER_AUTH_SECRET` | — |
| 3 | `createAuth(env)` per request + mount both verbs on `/api/auth/*` | Trap 2 |
| 4 | Prove it before adding anything: `/api/auth/ok` → 200, wrong password → 401 | A green build is not a working auth route |
| 5 | Add providers ONE at a time, each with its own migration when it has tables | Trap 11 — transcribe DDL from the **installed** package |
| 6 | Add the Capacitor shell LAST, if there is one | Traps 1, 3, 4, 5 all live here and all need a new binary |

**Decide two things on day one, because changing them later invalidates live
credentials:** `advanced.cookiePrefix` (renaming it signs every user out) and
`PASSKEY_RP_ID` (changing it invalidates every registered passkey — they are bound
to the RP id).

### The core schema — verified against prod, not transcribed from docs

> ⚠️ **THIS DDL IS 1.6.x AND IS WRONG FOR better-auth 1.7.x (added 2026-08-30).**
> Measured by reading the INSTALLED 1.7.2 package — `@better-auth/core/dist/db/get-tables.mjs`
> (`buildAuthTables`) and `.../db/schema/account.mjs` (`accountSchema`) — **not** from docs:
>
> 1. **NEW REQUIRED COLUMN** on `account`: `issuer text NOT NULL` (`accountSchema` declares
>    `issuer: z.string()` with no `.nullish()`, so it is mandatory).
> 2. **NEW UNIQUE INDEX** `(issuer, accountId)`.
> 3. Field **order** changed: `issuer, accountId, providerId, userId, …`.
>
> Apply the DDL below unmodified against 1.7.x and **every account write 500s** with
> `no such column: issuer` — visible only in `wrangler tail`, never in the response body.
> That is Trap 11 biting the *core* schema rather than a plugin's.
>
> **So do what Trap 11 already tells you to do for plugins, and do it for core too:
> transcribe from `node_modules`, not from this file.** The block below is a reference for
> shape and constraints, not a copy-paste source. Re-derive before every new build:
> ```bash
> node -e "console.log(require('better-auth/package.json').version)"
> grep -rn 'issuer' node_modules/@better-auth/core/dist/db/schema/account.mjs
> ```


better-auth needs four tables before any plugin. This is improvebayarea's applied
migration, confirmed live on 2026-08-05 via
`wrangler d1 execute <db> --remote --command 'PRAGMA table_info("user")'`:

```sql
CREATE TABLE IF NOT EXISTS "user" (
  "id" text NOT NULL PRIMARY KEY, "name" text NOT NULL,
  "email" text NOT NULL UNIQUE,   "emailVerified" integer NOT NULL,
  "image" text, "createdAt" date NOT NULL, "updatedAt" date NOT NULL
);
CREATE TABLE IF NOT EXISTS "session" (
  "id" text NOT NULL PRIMARY KEY, "expiresAt" date NOT NULL,
  "token" text NOT NULL UNIQUE,   "createdAt" date NOT NULL, "updatedAt" date NOT NULL,
  "ipAddress" text, "userAgent" text,
  "userId" text NOT NULL REFERENCES "user" ("id") ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS "account" (
  "id" text NOT NULL PRIMARY KEY, "accountId" text NOT NULL, "providerId" text NOT NULL,
  "userId" text NOT NULL REFERENCES "user" ("id") ON DELETE CASCADE,
  "accessToken" text, "refreshToken" text, "idToken" text,
  "accessTokenExpiresAt" date, "refreshTokenExpiresAt" date,
  "scope" text, "password" text, "createdAt" date NOT NULL, "updatedAt" date NOT NULL
);
CREATE TABLE IF NOT EXISTS "verification" (
  "id" text NOT NULL PRIMARY KEY, "identifier" text NOT NULL, "value" text NOT NULL,
  "expiresAt" date NOT NULL, "createdAt" date NOT NULL, "updatedAt" date NOT NULL
);
CREATE INDEX IF NOT EXISTS "session_userId_idx"          ON "session"      ("userId");
CREATE INDEX IF NOT EXISTS "account_userId_idx"          ON "account"      ("userId");
CREATE INDEX IF NOT EXISTS "verification_identifier_idx" ON "verification" ("identifier");
```

`ON DELETE CASCADE` on `session.userId`/`account.userId` is what makes account
deletion actually delete — same reasoning as Trap 11, one level down.

🛑 **Plugins ADD COLUMNS TO `user`, they do not only add tables.** The prod `user`
table has **8** columns against the 7 above: `twoFactor()` appends
`twoFactorEnabled`. So a column-count assertion against this DDL will "fail" on a
correct database once a plugin is enabled — count against the **installed plugin
set**, not this snippet. That is also why the `ALTER TABLE "user" ADD COLUMN` in a
plugin migration must go LAST (Trap 11): SQLite has no `ADD COLUMN IF NOT EXISTS`.

### `trustedOriginsFor` — referenced everywhere, so here it is

```ts
export function trustedOriginsFor(env: AuthEnv): string[] {
  return [
    "https://example.com",
    "https://www.example.com",
    "capacitor://localhost",          // Capacitor webview — see below
  ];
}
```

**`trustedOrigins` and `PASSKEY_ORIGINS` are different lists and must stay
different.** `trustedOrigins` is better-auth's CSRF/redirect allowlist and legitimately
includes `capacitor://localhost`. `passkey({ origin })` is WebAuthn's `expectedOrigin`
and must contain **only** secure HTTPS origins whose registrable domain matches
`rpID` — putting `capacitor://localhost` there is a lie the browser rejects anyway,
and it hides the real failure (Trap 9). Include `www.` in both.

---

## The working baseline

```ts
export function createAuth(env: AuthEnv) {
  if (!env.BETTER_AUTH_SECRET) throw new Error("BETTER_AUTH_SECRET not set");
  if (!env.DB) throw new Error("D1 binding DB is not configured");

  return betterAuth({
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BETTER_AUTH_URL || "https://example.com",
    basePath: "/api/auth",
    database: env.DB,            // see Trap 2
    telemetry: { enabled: false },
    trustedOrigins: trustedOriginsFor(env),
    advanced: { cookiePrefix: "app" },
    plugins: [bearer(), /* … */],
  });
}
```

Mount in Hono — **both verbs**, the whole subtree:
```ts
app.on(["GET", "POST"], "/api/auth/*", async (c) => createAuth(c.env).handler(c.req.raw));
```

Secrets: `BETTER_AUTH_SECRET`, plus `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`,
`APPLE_CLIENT_ID`/`APPLE_CLIENT_SECRET` per provider. `wrangler secret put` each —
never `vars`. **Obtaining them is the actual work — see the next section.**

---

## Provisioning the credentials (the part the docs skip)

Getting these is most of the setup cost. Order matters; each step has a trap.

### 0. `BETTER_AUTH_SECRET`
```bash
openssl rand -base64 32 | wrangler secret put BETTER_AUTH_SECRET
```
Never echo it into the transcript. Verify shape only: `wrangler secret list` shows
`secret_text`.

### 1. Google — you need TWO clients, and only one has a secret

| Client type | Used by | Has a secret? |
|---|---|---|
| **Web application** | browser redirect flow; this is `GOOGLE_CLIENT_ID` | yes → `GOOGLE_CLIENT_SECRET` |
| **iOS** | native `GIDSignIn` in the Capacitor shell | **no** — public by design, ships in the bundle |

Console: `https://console.cloud.google.com/apis/credentials?authuser=1`
(**`authuser=1` matters** — `authuser=0` can land on an MFA-enrollment gate.)

- Web client → Authorized redirect URI `https://<site>/api/auth/callback/google`.
- iOS client → bind to the bundle id + team id. Its **reversed** id is the
  `CFBundleURLScheme` (Trap 3). Put both ids in one shared module so the shell-side
  id and the server-side accepted audience (Trap 1) can never drift.

**🛑 Google caps a client at TWO client secrets, and delete requires disable first.**
The trash icon is inert until the secret is disabled — that is a two-step UI, not a
broken button. So when rotating: confirm the stale secret is unused, **disable** it,
**then** delete, then add the new one. Plan this before you hit the cap.

**Never let a secret value into the transcript.** Pipe it:
```bash
pbpaste | tr -d '\n' | wrangler secret put GOOGLE_CLIENT_SECRET
```
Verify by shape, never by printing: `wrangler secret list | grep GOOGLE_CLIENT_SECRET`.
If you must confirm a value came through, use a boolean test (does string X appear:
true/false) — **never return the surrounding text**, "scrubbed" or otherwise.

### 2. Apple — a Services ID plus a JWT you mint yourself

`APPLE_CLIENT_ID` is the **Services ID** (e.g. `com.improvebayarea.signin`), *not*
the app bundle id. `APPLE_APP_BUNDLE_ID` is separately needed for the native
audience (Trap 1).

Register the return URL under the Services ID → *Sign in with Apple* → Configure:
**the ⊕ button REGISTERS a new Website URL; the dropdown only LISTS what is already
attached.** Editing the visible field and pressing Save is a silent no-op — this
looks exactly like a broken form. Add `https://<site>/api/auth/callback/apple`, then
**reload and re-read the list** to confirm it stuck.

`APPLE_CLIENT_SECRET` is **not issued by Apple** — it is a self-signed **ES256 JWT**
you generate from a `.p8` Sign-in-with-Apple key, and Apple caps it at **6 months**.
The JWT signature must be raw 64-byte `r||s` (ieee-p1363), not DER — hand-rolling
that is where people lose an afternoon.

**Drive the whole Apple side with `siwa`** (`~/tools/siwa/siwa`, on PATH), which
wraps every step below. Add the site once to `~/.config/siwa/sites.json`
(`host, services_id, team_id, key_id, p8, worker_repo, worker_name`), then:

```bash
siwa portal   <site>   # prints the 2 web-only steps (Services ID + Return URL)
siwa domain-file <site> ~/Downloads/apple-developer-domain-association.txt
siwa secret   <site>   # mint JWT -> both APPLE_* secrets -> deploy -> register expiry
siwa probe    <site>   # ask APPLE whether the credential chain is valid
siwa verify   <site>   # live: assoc file + Apple button + flow -> appleid.apple.com
siwa rotate   <site>   # the 6-month re-mint (same as secret + probe)
```

`siwa secret` shells out to the same `apple-client-secret.mjs` generator (one
implementation, one place to fix) and never prints the JWT — only its length and
expiry. **`betterauth` stays read-only and `siwa` owns the mutations**; that split
is deliberate, so don't teach `betterauth` to write secrets.

🛑 **`siwa probe` is the cheapest real proof the credential chain works, and its
PASS is an ERROR string.** It POSTs a deliberately-bogus authorization code to
`https://appleid.apple.com/auth/token`:

| Apple's `error` | Means |
|---|---|
| **`invalid_grant`** | ✅ Apple **accepted** the client secret and refused only the fake code — the `.p8` / `key_id` / `team_id` / Services-ID chain is CORRECT |
| `invalid_client` | ❌ Apple rejected the **credential** itself |

Same shape as the APNs `BadDeviceToken` trick: make the credential the only thing
under test. No browser, no sign-in, no side effect — so it is free to run often.

⚠️ **The Worker's auth gate will break Apple's domain verification if you let it.**
Apple fetches `/.well-known/apple-developer-domain-association.txt`
**unauthenticated**. A session gate that allows only `/login` and `/api/auth/*`
redirects that path to `/login`, and Apple reads the 302 as a failure with nothing
in your logs explaining why. Allow the directory through explicitly:

```ts
if (path.startsWith('/.well-known/')) return next();   // BEFORE the session check
```
Proof it worked, on imessage-bridge: that path went **302 → 404** after the fix
(404 = reaching the asset layer, file not installed yet). Same allowance covers
`security.txt` and ACME challenges. Safe to expose — the directory only ever holds
values that are public by design.

⚠️ **A SIWA `.p8` is a TEAM-level key.** One key signs JWTs for *any* Services ID
in that team, so an existing key (e.g. `~/.asc/keys/AuthKey_Z5JJTW7C94-siwa-improvebayarea.p8`,
team `2KJ8W6N44B`) is reusable for a new site — a new Apple Developer account or key
is NOT required. The Services ID goes in the JWT's `sub`; the key only signs.

### 3. Register every expiring secret for rotation — MANDATORY

Apple gives **no warning** and the failure is opaque: sign-in simply stops, site-wide
*and* in the app. Add an entry to `~/tools/secret-expiry/secrets.json` with `name`,
`expires`, `owner`, `impact`, and a copy-pasteable `renew` command, then **scp it to
the mac-mini** — the mini is the cron host, so an entry only on the laptop never
alerts. Both sites are already registered; copy an existing entry's shape.

Derive `expires` from the **earlier** plausible mint date, so the alert fires early
rather than late.

### 4. Decommission the old provider — no half-configs

After cutover, delete the old secret (`wrangler secret delete CLERK_SECRET_KEY`),
strip its hosts from the CSP, remove the packages, and drop the DNS record. Audit
with `wrangler secret list` — a leftover key is both a live credential and a lie
about which system is in charge.

> **Verified 2026-08-05: both sites are now clean.** `CLERK_SECRET_KEY` deleted from
> both Workers (`wrangler secret list` shows it absent while `BETTER_AUTH_SECRET`
> remains — always assert the control, or you cannot tell "deleted" from "list
> broke"). All 10 dangling DNS records removed across both zones; `dig @1.1.1.1`
> returns NXDOMAIN for `clerk`, `accounts`, `clkmail`, `clk._domainkey`,
> `clk2._domainkey` on each.
>
> **Two lessons worth more than the result:**
>
> 1. **A source grep is the WRONG instrument for decommissioning.** Both codebases
>    had zero `@clerk/*` packages and zero `env.CLERK_*` reads — a grep said "clean"
>    while a live credential was still bound to production and 10 CNAMEs still
>    pointed into a deleted third-party tenant (a textbook subdomain-takeover
>    setup). The binding and the zone are the ground truth; the imports are not.
>    Audit with `wrangler secret list` and `dig`, not `grep`.
> 2. **Check the DKIM/mail records too, not just the auth hosts.** The obvious two
>    are `clerk` and `accounts`; the easy misses are `clkmail` + the two
>    `clk*._domainkey` CNAMEs. Before deleting them, confirm the domain's SPF does
>    not reference the vendor and that the real senders' selectors still resolve —
>    then removing them breaks no mail.

---

## Trap 1 — Native iOS social sign-in: the id token audience is NOT your web client

**The single most expensive trap. It has bitten Apple and Google separately.**

Google/Apple mint an id token whose `aud` is **whichever client asked for it**. The
browser flow asks as your *web* client; a native iOS sheet asks as the *iOS* client
(Google) or the *bundle id* (Apple). Better Auth's default verifiers check
`aud === options.clientId` and nothing else, so a **fully successful** OAuth
round-trip is then rejected by your own server.

The symptom is maximally misleading: the user completes the Google sheet, Google
emails *"You shared some Google Account data with <app>"*, and the app shows
**"Could not sign in with Google. Invalid token."**

🛑 **Corrected 2026-08-05 — the earlier advice here was wrong, and it shipped
the bug to production.** This skill used to say Apple had a "first-class option"
(`appBundleIdentifier`) while Google did not. Reading the installed source,
`@better-auth/core/dist/social-providers/apple.mjs:63`:

```js
audience: options.audience?.length ? options.audience
        : options.appBundleIdentifier ? options.appBundleIdentifier
        : options.clientId,
```

`appBundleIdentifier` **REPLACES** the audience — it does not add one. Setting it
makes the bundle id the *only* valid audience and silently drops the web Services
ID. The `audience` **ARRAY** takes precedence over both and is the only form that
accepts each. So Apple and Google get the **same** shape, not different ones:

```ts
apple: {
  clientId: env.APPLE_CLIENT_ID as string,
  clientSecret: env.APPLE_CLIENT_SECRET as string,
  audience: [env.APPLE_CLIENT_ID as string, APPLE_APP_BUNDLE_ID], // ← BOTH
},
google: {
  clientId: env.GOOGLE_CLIENT_ID as string,
  clientSecret: env.GOOGLE_CLIENT_SECRET as string,
  async verifyIdToken(token: string, nonce?: string) {
    const claims = await verifyGoogleIdToken({
      token,
      audience: [env.GOOGLE_CLIENT_ID as string, GOOGLE_IOS_CLIENT_ID], // jose takes an array
      nonce,
    });
    return Boolean(claims);
  },
},
```
`import { verifyGoogleIdToken } from "better-auth/social-providers"`.

**Two failure modes this exact trap produced on improvebayarea (fixed `e4a486f`):**

1. **An OPTIONAL env var made a REQUIRED audience vanish.** The provider spread
   `appBundleIdentifier` conditionally on `env.APPLE_APP_BUNDLE_ID` — a var never
   set on the Worker. The spread no-opped, the comment above it described a
   configuration that did not exist, and every native Apple sign-in was rejected.
   **A bundle id is public and must always be present, so it belongs in a
   constant, not a secret.** `wrangler secret list` is what proves an env-gated
   config is actually live; the source alone cannot.
2. **Apple can be LIVE-broken while Google is only latent.** Capability gating is
   per-provider: on IBA `nativeSocialAvailable('google')` checks a shell UA token,
   but `nativeSocialAvailable('apple')` is just `Boolean(AUTH_SOCIAL.apple)`
   (`src/ui.ts:1919`) — so Apple takes the native id-token path in *every* in-app
   webview, unconditionally. **Check each provider's gate separately; do not
   assume the one you audited represents the others.**

**This is not a weakening.** It calls Better Auth's own verifier — JWKS signature,
issuer, expiry, 1h max age and nonce all still enforced. Only the audience
allowlist widens, to *your own* second client. That is Google's documented pattern
for a backend serving several platforms. Assert the set is exactly your clients so
a wildcard can never creep in.

**Do NOT "fix" it with the plugin's `iOSServerClientId`.** That maps to GIDSignIn's
`serverClientID`, which the SDK sends as the OAuth **`audience` request parameter**
(`GIDSignIn.m:896`) to obtain a `serverAuthCode`; whether it also rewrites the id
token's `aud` is undocumented — the plugin's own docs tie the field to offline mode.
Accepting both audiences is correct regardless, which is why it is the right fix.

**Probe (proves the deployed verifier, costs nothing — a failed sign-in has no side effect):**
```bash
HDR=$(printf '{"alg":"RS256","kid":"k"}' | base64 | tr '+/' '-_' | tr -d '=')
PAY=$(printf '{"aud":"PROBE.apps.googleusercontent.com","iss":"https://accounts.google.com","exp":%d}' $(($(date +%s)+600)) | base64 | tr '+/' '-_' | tr -d '=')
curl -s -X POST https://<site>/api/auth/sign-in/social -H 'Content-Type: application/json' \
  -d "{\"provider\":\"google\",\"idToken\":{\"token\":\"$HDR.$PAY.sig\"}}"
```
Expect 401. Then read `wrangler tail` for the discriminator (Trap 6).

---

## Trap 2 — Instantiate PER REQUEST; hand D1 in raw

`env.DB` is scoped to one invocation. A module-level singleton captures the first
request's binding and silently breaks on every later one. `createAuth(env)` does no
I/O, so per-request is cheap.

Pass the binding **directly** as `database: env.DB` — `@better-auth/kysely-adapter`
detects the `batch/exec/prepare` surface and wraps it in its own `D1SqliteDialect`
(`@better-auth/kysely-adapter/dist/index.mjs:67-69`). No dialect construction needed.

---

## Trap 3 — Capacitor: no URL scheme means the app CRASHES, not "fails"

Native Google requires the reversed client id in `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLSchemes</key>
  <array><string>com.googleusercontent.apps.NNNN-xxxx</string></array>
</dict></array>
```
Without it GoogleSignIn raises **`NSInvalidArgumentException`** (`GIDSignIn.m:733`)
— an uncaught ObjC exception that kills the app. There is no alternative path and
no graceful degradation: enabling the button in a build lacking the scheme crashes
every install that taps it.

The scheme is **compiled in**, so this always needs a new TestFlight build.

⚠️ `mobile/ios/App/App/capacitor.config.json` is **gitignored** and regenerated by
`npx cap sync ios`. Archiving without syncing produces a binary missing whatever you
just added to `capacitor.config.ts` — with no error anywhere. Verify in the archive:
```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" <App>.app/Info.plist
grep -o '"appendUserAgent"[^,]*' <App>.app/capacitor.config.json
```

---

## Trap 4 — Remote-URL wrap: capability tokens, never a boolean flag

When `server.url` points at the live site, **the web layer is served to every
install at once, old and new.** A site-side `const NATIVE_READY = true` therefore
switches the feature on inside already-installed builds that lack the native
capability — the exact dead-end (or crash) the flag was meant to prevent.

Invert it: the **shell declares** what it can do, the site reacts.
```ts
// capacitor.config.ts — add ONLY in the commit that adds the capability to the binary
appendUserAgent: "MyApp nativeGoogleAuth/1",
```
```js
function shellDeclaresNativeGoogle() {
  try { return (navigator.userAgent || '').includes('nativeGoogleAuth/1'); }
  catch (e) { return false; }
}
```
A build without the capability never emits the token, so a stale install cannot opt
in. No version arithmetic, no deploy ordering. Safari lacks it too — correct, since
browsers use the web flow.

Prove the token actually reaches the page (server-side is ground truth):
```bash
wrangler tail --format json   # then load the app; read event.request.headers['user-agent']
```

---

## Trap 5 — A JS gate is not enough: CSS can override it

Sites that hide social buttons inside webviews often do it in **CSS**:
```css
html[data-native-shell] #btn-social-google { display: none !important; }
```
That beats any JS capability check. On improvebayarea the JS gate returned `true`,
every condition passed, and the button still did not render — `display:none
!important` won, and a test asserted the unconditional rule, locking the bug in.

Fix by excluding capable shells at the selector level and setting the attribute only
when the capability is real:
```css
html[data-native-shell]:not([data-native-google]) #btn-social-google { display: none !important; }
```
**Never conclude a social button works from source review.** Run it and look.

---

## Trap 6 — "Invalid token" is one string for many causes: ship a discriminator

Better Auth collapses audience mismatch, bad signature, and expiry into one
`{"message":"Invalid token","code":"INVALID_TOKEN"}`. Every single-cause fix then
looks byte-identical to no fix — Pattern #32.

Log the measurable properties on the rejection path. **Non-PII only** — an id token
is full of user data:
```ts
if (!claims) {
  let aud = "<unparseable>", iss = "<unparseable>";
  let expired: boolean | "unknown" = "unknown";
  try {
    const j = JSON.parse(atob((token.split(".")[1] ?? "").replace(/-/g,"+").replace(/_/g,"/")));
    if (typeof j.aud === "string") aud = j.aud;
    if (typeof j.iss === "string") iss = j.iss;
    if (typeof j.exp === "number") expired = j.exp * 1000 < Date.now();
  } catch { /* placeholders ARE the signal */ }
  console.warn(JSON.stringify({ event: "google_id_token_rejected", aud, iss, expired,
    audAccepted: [webId, iosId].includes(aud), nonceSupplied: Boolean(nonce), tokenLen: token.length }));
}
```
Log `aud`/`iss`/`exp` — never `sub`, `email`, `name`, or the token. The unverified
decode is for logging only; trust still comes solely from the verifier above it.

---

## Trap 7 — Migrating off Clerk: preserve the user ids

App data is FK'd to the old provider's user id. Import users with
`id = <old provider id>` via direct D1 inserts — **zero FK re-keying**, and social
accounts relink on first sign-in because the OAuth apps (and therefore `sub`) are
unchanged. Set `account.accountLinking.trustedProviders` for providers that verify
the email, or the true owner hits `account_not_linked`.

Password hashes are **dashboard-export only** (the Backend API never exposes
`password_digest`), and Clerk's `password_hasher` is an enum of ~15 algorithms, not
just bcrypt. Import a credential row **only** for hashes you can actually verify;
for anything else send a reset email rather than writing a credential that can never
match — that failure surfaces as a generic "invalid password" with nothing in the logs.

**A provider migration silently drops credential types while leaving their
infrastructure standing.** On IBA the Clerk-era AASA + Associated-Domains
entitlement for passkeys (`dadfdf3`) survived the cutover; the *credentials* did
not — `2ba98c0` carried `bearer`/`magicLink`/`emailOTP` and nothing else. The
honest short-term fix then *hid* the gap: `b96dd0f` rewrote the privacy page to
stop claiming passkeys, which was correct (never overclaim) but left a product
regression looking like a settled decision. **After any auth migration, diff the
OLD provider's enabled credential types against your new `plugins:` array** — the
dashboard's feature list, not your memory of it.

---

## Trap 8 — `twoFactor()` defaults to demanding a password almost nobody has

`/two-factor/enable` calls `shouldRequirePassword`
(`node_modules/better-auth/dist/utils/password.mjs`) and, by default, **refuses to
enrol an account that cannot supply its password**. On a deployment where accounts
arrive by Clerk import (`password_enabled=false`), social, magic link, email OTP,
or passkey — i.e. essentially all of them — 2FA is rendered **visible in the UI and
permanently unreachable**. Nothing errors at deploy time; the button simply never
works, for everyone.

```ts
twoFactor({
  issuer: APP_DISPLAY_NAME,
  allowPasswordless: true,   // ← load-bearing, not a convenience
}),
```

**This is not a weakening.** The flag's other branch still demands the password
whenever a credential account *has* one — it relaxes the check only where there is
nothing to check. Assert both halves, or a future default-flip silently becomes an
account-takeover:

```
enrol with NO password        → 200, secret written
enrol with a WRONG password   → 400, nothing written   ← the half that matters
anonymous caller              → 401
```

Also assert, against a real instance: the stored secret does **not** contain the
plaintext handed to the app (D1 is a separate blast radius from the Worker), and
minting a secret does **not** flip `twoFactorEnabled` (a mistyped setup must not
lock the user out of their own password sign-in).

---

## Trap 9 — `passkey({ origin })` left unset is attacker-controlled

Omit `origin` and the plugin falls back to the request's own `Origin` header — and
that value is handed straight to the verifier as `expectedOrigin`. Verified in the
installed source (`@better-auth/passkey/dist/index.mjs`, 1.6.26):

```js
321:  const origin = options?.origin || ctx.headers?.get("origin") || "";   // register
337:        expectedOrigin: origin,
414:  const origin = options?.origin || ctx.headers?.get("origin") || "";   // authenticate
436:      expectedOrigin: origin,
```

So the check becomes "does the origin match the origin the caller sent" — which is
not a check. Pin it to a literal allowlist:

```ts
export const PASSKEY_RP_ID  = "improvebayarea.com";
export const PASSKEY_ORIGINS = [
  "https://improvebayarea.com",
  "https://www.improvebayarea.com",   // registrable suffix matches the RP id
] as const;

passkey({ rpID: PASSKEY_RP_ID, rpName: APP_DISPLAY_NAME, origin: [...PASSKEY_ORIGINS] }),
```

**Passkey origins are NOT `trustedOrigins`, and the difference is load-bearing.**
WebAuthn requires a secure HTTPS origin whose registrable domain matches `rpID`.
`capacitor://localhost` belongs in `trustedOrigins` and must **never** appear here
— the browser rejects it anyway, so listing it only hides the real failure. Omitting
`www.` is the opposite mistake: a passkey registered there fails verification with an
opaque 400.

Probe the deployed config for free — a failed ceremony has no side effect:
```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  https://<site>/api/auth/passkey/generate-register-options
# 404 = plugin NOT loaded · 401 = loaded, demanding auth (correct)
```
That **404 → 401 transition is the cheapest proof a plugin actually shipped** — far
better than reading the diff. Capture the 404 *before* deploying so you have a
before/after, and re-check after >30s (Worker propagation false-negatives an
immediate curl).

🛑 **The probe's HTTP method is PER-ROUTE — a GET-only sweep reports working plugins
as missing.** Corrected 2026-08-05 after this exact false negative: `GET
/two-factor/enable` returns **404**, `POST` returns **401**. Three live plugins on IBA
read as "not loaded" under a GET-only probe. Use the method the route actually
declares (`betterauth health` encodes the per-route table), and treat a 404 from the
wrong verb as *no information*, not evidence of absence.

---

## Trap 10 — Enabling 2FA makes a CORRECT password look like a broken session

Once 2FA is on, `/sign-in/email` answers **200 with no session** and a
`twoFactorRedirect` payload; better-auth deletes the half-made session
(`.../plugins/two-factor/index.mjs:266`). Client code that infers "signed in" from
`res.ok` therefore tells a user who typed the **right** password that the session
did not stick — an opaque failure on the happy path. Handle `twoFactorRedirect`
explicitly, and surface backup codes from the challenge itself, since that is the
only screen a locked-out user can still reach.

**Scope it honestly in product copy.** better-auth challenges **only**
`/sign-in/email` (`.../two-factor/index.mjs:222`). Magic link, email code, Apple,
Google and passkey sign-in are **not** second-factored. Say the code guards *the
password*, not *the account* — and lock the phrasing with a test so a later
copy-edit cannot widen the claim.

---

## Trap 11 — Plugin tables: transcribe the DDL from installed source, and CASCADE

A plugin's storage is your migration to write. Getting a column wrong does **not**
fail loudly: the adapter throws inside the handler, better-auth returns a generic
500, and `no such column` appears only in `wrangler tail` under `logs[]` — never
`exceptions[]`. Transcribe from the **installed** package (Trap: the two sites are on
different versions):

| Table | Source of truth |
|---|---|
| `passkey` | `node_modules/@better-auth/passkey/dist/index.mjs` (`#region src/schema.ts`) |
| `twoFactor` | `node_modules/better-auth/dist/plugins/two-factor/schema.mjs` |
| `user.twoFactorEnabled` | same twoFactor schema, `user.fields` block |

Type mapping (established empirically against better-auth driving SQLite):
`string`→`text`, `number`→`integer`, `boolean`→`integer` (0/1, **never** a boolean
literal), `date`→`date` (ISO-8601 TEXT at rest).

**`ON DELETE CASCADE` is required, not decorative.** `internalAdapter.deleteUser`
(`better-auth/dist/db/internal-adapter.mjs:164-175`) deletes only session/account/
user rows and knows nothing about plugin tables. Without it, "delete my account"
leaves a live `credentialID` behind — breaking the erasure your privacy page
promises, and 500ing `/passkey/verify-authentication` when it matches a row whose
owner is gone.

**Put the one non-idempotent statement LAST.** SQLite has no
`ADD COLUMN IF NOT EXISTS`, so `ALTER TABLE "user" ADD COLUMN "twoFactorEnabled"`
aborts the batch on a re-run (`duplicate column name` — harmless, but it stops
everything after it). Everything above it is `IF NOT EXISTS`, so a first run has
already created every table and index before this can fail.

**Tests must read `migrations/` — never a hand-copied `CREATE TABLE`.** A second
source of truth in the test file had already drifted a column on IBA, which is how
this change first surfaced as `table user has no column named twoFactorEnabled`.

---

## Trap 12 — "single-tenant" is a comment, not a control: `enabled: true` ships an OPEN SIGNUP route, and authenticating is not authorizing

**Found 2026-08-30 building `agentprofile`. It was a HIGH-severity unauthenticated
full-owner compromise, and the code carried a comment asserting the opposite.**

Two independent halves. Either one alone is the whole vulnerability.

**Half 1 — `emailAndPassword: { enabled: true }` publishes `POST /sign-up/email`.**
The only gate in the installed package is:

```js
// node_modules/better-auth/dist/api/routes/sign-up.mjs
if (!ctx.context.options.emailAndPassword?.enabled ||
    ctx.context.options.emailAndPassword?.disableSignUp) throw APIError.from("BAD_REQUEST", ...)
```

So `enabled: true` without `disableSignUp: true` is a live, public account-creation
endpoint. And it hands back a usable session immediately — `createSession` then
`setSessionCookie` then a body containing `token` — because `autoSignIn` defaults on and
`requireEmailVerification` is unset. With the `bearer()` plugin that token also works as
an `Authorization` header.

**`trustedOrigins` does NOT save you.** The CSRF middleware short-circuits:
`if (headers.has("cookie")) return await validateOrigin(ctx)` — a plain `curl` sends no
cookie — and it then only validates when a `Sec-Fetch-*`, `origin`, or `referer` header is
present. A bare `curl` supplies none of those, so the function returns having validated
nothing and `trustedOrigins` is never consulted.

**Half 2 — a middleware that only checks `session !== null` authenticates without
authorizing.** This shape is the bug:

```ts
const session = await createAuth(c.env).api.getSession({ headers: c.req.raw.headers });
if (session === null) return jsonError(401, ...);
c.set('owner', { userId: session.user.id });   // <-- ANY valid session is now "the owner"
```

There is no comparison against a designated owner. On a single-tenant app that means the
*second* account created — by anyone — has full owner authority: read every stored record,
mint API tokens with every scope, and **approve its own pending approvals**, which defeats
any human-in-the-loop gate you built on top of it.

### The probe (three greps, ~20 seconds)

```bash
grep -rn 'disableSignUp' src/                      # ZERO hits + enabled:true  => signup is LIVE
grep -rn 'session\.user\.id' src/                  # only an assignment, no comparison => no owner
grep -rniE 'owner_?user_?id|ownerUserId' src/ wrangler.jsonc   # ZERO => no owner is configured
```

### The fix — apply BOTH

```ts
emailAndPassword: { enabled: true, disableSignUp: true },
```
then seed the owner out of band (a one-shot CLI insert of `user` + `account` with a hashed
password), **and** make the middleware authorize:
```ts
if (session === null || session.user.id !== c.get('config').ownerUserId) {
  return jsonError(401, 'unauthenticated', 'Owner session required.');
}
```
Also narrow the mount — `app.on([...], `${AUTH_BASE_PATH}/*`, ...)` republishes every route
any future plugin adds. Allowlist `/sign-in/email`, `/sign-out`, `/get-session`.

### Arm the tests by deleting the guard

`POST /api/auth/sign-up/email` must return 4xx — delete `disableSignUp` and it must go red.
A session for a non-owner id must be rejected on every protected route — delete the
`ownerUserId` comparison and it must go red.

### The meta-lesson

The source comment said *"Single-tenant by construction … There is no public signup route to
leave open,"* the README said *"There is no signup route and no second user. That is the
product, not a gap,"* and the middleware docblock called itself *"the one place where 'is
this the owner' is decided."* All three were false, and each **read as verification while
verifying nothing**. A comment asserting an invariant is not an invariant. If a property
matters, there is a test that fails when it stops holding — otherwise it is a wish.

## Passkeys in a Capacitor shell: usually NO new build (contrast Traps 3–4)

Native *social* needs a compiled-in URL scheme, so it always needs a new archive.
Passkeys usually do **not** — and the distinction is the shell's `server.url`:

- **Remote-URL wrap** (`server.url: "https://<site>"`): the webview's WebAuthn origin
  *is* the real HTTPS origin, so the whole ceremony is site-side and reaches
  installed binaries on a Worker deploy.
- The only native prerequisite is the **Associated Domains entitlement**
  (`webcredentials:<domain>`) plus the AASA file. Both are **relying-party based**, so
  they survive an auth-provider migration untouched — Clerk-era bindings work for
  Better Auth with no change.

Verify the binding before debugging any JS ceremony (30 seconds, catches the
"registration was cancelled or timed out" class):
```bash
curl -s https://<site>/.well-known/apple-app-site-association | python3 -m json.tool | grep -A3 webcredentials
grep -A3 associated-domains mobile/ios/App/App/App.entitlements
```
**These are THREE different things — name which you verified.** Entitlement present in
the repo ≠ present in the *signed* build ≠ the capability enabled on the bundle id.

🛑 **The portal capability IS API-checkable — do not claim it is browser-only.**
Corrected 2026-08-05; the earlier version of this skill said it could not be verified
without an archive, and that was wrong:
```bash
asc capabilities --bundle-id com.<app>   # ASSOCIATED_DOMAINS / APPLE_ID_AUTH, ~2s
```
Verified live: both `com.improvebayarea.app` and `com.example.app` report
`ASSOCIATED_DOMAINS` + `APPLE_ID_AUTH` enabled. What genuinely has **no** API is the
Services ID's **Return URLs** (Sign in with Apple config) and Google's OAuth **client
secrets** — those two, and only those, need the browser recipes in `betterauth portal`.

---

## `betterauth` — the enforcement layer for everything below

This skill explains *why*; **`~/tools/betterauth/betterauth` checks it mechanically.**
Read-only by design (it reports, you fix — it never mutates a secret or a schema).
Run it before trusting any claim in the "Current state" table, which is a cache.

```bash
betterauth all                # every check, human-readable
betterauth all --json         # for scripts/cron
betterauth drift              # installed version per site vs npm latest + CROSS-SITE skew
betterauth secrets            # required/missing, stale (CLERK_*), expiry via secret-expiry
betterauth schema             # remote D1 PRAGMA vs the INSTALLED plugin schemas
betterauth health             # /api/auth/ok + per-plugin route probe (correct verb per route)
betterauth portal             # Apple capabilities via asc API + the 2 genuinely-no-API recipes
```

**Two CLIs, one boundary — do not blur it.** `betterauth` DIAGNOSES (read-only:
no `secret put`, no D1 writes, no deploy); **`siwa` REMEDIATES the Apple half**
(mints the JWT, sets `APPLE_*`, deploys, rotates). So `betterauth secrets` telling
you `APPLE_CLIENT_SECRET` is missing or expiring is answered by `siwa secret <site>`
/ `siwa rotate <site>` — that is the intended hand-off, and it is why `betterauth`
must never grow a write path.

| Question | Tool |
|---|---|
| Is Apple configured / expiring / drifted? | `betterauth secrets` · `betterauth portal` |
| Is the *credential chain* actually valid to Apple? | **`siwa probe <site>`** (`invalid_grant` = PASS) |
| Make it work / rotate it | **`siwa secret`** · **`siwa rotate`** |
| Is it live end-to-end right now? | **`siwa verify <site>`** (or `betterauth health` for all routes) |

⚠️ **Sign-in-with-Apple has NO API for the Services ID or its Return URLs — this is
measured, not assumed.** `asc capabilities` (App Store Connect CLI, 24 modelled
capabilities over a 1263-endpoint schema index) has **no entry** for either; the only
Developer-Portal capability it reaches via web session is `PRIVATE_CLOUD_COMPUTE`,
and `bundleIdCapabilities` is the only API-backed signing surface. Probing the
plausible internal endpoints with an owner token also fails:
`oauthconfig.googleapis.com/v1/projects/<p>/clients` → **404**,
`clientauthconfig.googleapis.com/...` → **404**, `iap.googleapis.com` brands → 403
(API disabled, and IAP-created clients carry fixed redirect URIs anyway). So a
"fully automated Apple setup" is not buildable — `siwa portal` printing the two
browser steps IS the correct design, not a shortcoming. Don't try to generate an
API-wrapper CLI for it (the CLI-printing-press route dead-ends here for exactly
this reason).

**Exit codes are the contract**: `0` clean · `1` finding · `2` usage · **`3` could not
determine**. 3 is the important one — a check that could not run must never read as
clean. Config lives in `sites.json`; a third site is one entry, not a code change.

Weekly Hermes cron on the mac-mini (`4e8f2ca8fbca`, Mon 09:00) alerts **only on
change**. It must live on the mini — a job registered only on the laptop never fires.

⚠️ **`wrangler secret list` without `--name` is host-dependent.** Same repo, same
commit, same account: 12 secrets on the laptop, `[]` **with exit 0** on the mini. That
silently produces confident false "secret not set" findings. Always pass `--name`, and
sanity-gate it: zero secrets while `/api/auth/ok` returns 200 is impossible → report
indeterminate, not a finding.

⚠️ **`require('better-auth/package.json')` throws** — the package's `exports` map does
not expose it, so a naive version read reports installed packages as `NOT_INSTALLED`.
Read `node_modules/better-auth/package.json` by path.

---

## Verification recipes

| Claim | Probe |
|---|---|
| Auth routes are live | `curl -o /dev/null -w '%{http_code}' https://<site>/api/auth/ok` |
| Bad creds rejected | `POST /api/auth/sign-in/email` with a wrong password → expect 401 |
| **A plugin actually shipped** | `curl` its route: **404 = not loaded, 401 = loaded**. Capture the 404 *before* deploy for a before/after. |
| The deployed verifier is the new one | Trap 1 probe + `wrangler tail` for the discriminator |
| The shell emits its capability token | `wrangler tail --format json` → request `user-agent` |
| Plugin tables exist **in prod** | `PRAGMA table_info(<t>)` on `--remote`. The migration file and the LOCAL D1 are not proof. |
| A social button actually renders | Run the app; screenshot. Source review cannot see CSS overrides. |
| A passkey/2FA **write** works | Only a real enrolment proves it. Schema + a clean route response do **not** — that is the exact schema-drift shape. Say so rather than implying coverage. |

⚠️ **On an SPA-shaped site, HTTP 200 does NOT prove a path exists — and that can
invalidate a "is it deployed?" check.** Measured 2026-08-05, same account, two shapes:

| Request | example.com (SPA + assets fallback) | improvebayarea.com (Hono SSR, no fallback) |
|---|---|---|
| `/definitely-not-a-real-path-xyz123` | **200 `text/html`** | 404 `text/plain` |
| `/openapi/admin.json` (repo-only file) | **200 `text/html`** | 404 `text/plain` |
| `/api/auth/definitely-not-a-route` | **404** | **404** |

The SPA's catch-all serves `index.html` for anything unmatched, so
`curl -o /dev/null -w '%{http_code}'` reports 200 for a file that was never
deployed. This cost a wrong conclusion in this very session: an OpenAPI spec was
read as "served in production" off a 200 that was really the SPA shell. **Assert
`content_type` (or grep the body for something only the real artifact contains) —
never status alone** when the path is a static file on an SPA.

**This is also exactly why the 404→401 plugin probe above still works:**
`/api/auth/*` is claimed by the Worker *before* the asset fallback, so an unknown
auth route genuinely 404s on both shapes. The probe is safe for `/api/auth/**` and
unsafe for everything else. Confirm your own site's shape once with a nonsense path
before trusting any status-only check.

⚠️ `wrangler tail --format json` is **pretty-printed, not JSONL** — line-wise grep
matches nothing. Parse with a brace-matching decoder and fail loudly at 0 objects; a
tail that wrote 0 bytes never connected, so its silence proves nothing. Check *which*
requests it captured before trusting "0 errors" — a tail that missed the new route
says nothing about the new code.

⚠️ **A post-deploy curl inside ~30s false-negatives** (Worker propagation). Observed
2026-08-05: `/privacy` grepped 0 occurrences of new copy immediately after deploy and
3 occurrences 30s later. Re-check before calling a gate failed.

⚠️ **A health check written in Python gets 403 from Cloudflare on its own User-Agent.**
Measured 2026-08-17 against `imessage.example.com`: default `Python-urllib/3.x`
→ **403**, browser UA → **200**, `curl` → **200**. Every check in the script then
reports a FALSE FAILURE ("association file not served", "no Apple button") against a
perfectly healthy deployment. Set a browser UA, and **positive-control any urllib
result against `curl` before believing a failure** — the 403 is a property of your
client, not of the site. (`siwa` pins a UA for exactly this reason.)

⚠️ **Never detect a social button by searching the page for the provider's name.**
`"apple" in html` matches **`-apple-system`** in the CSS `font-family`, so the check
reported the Apple button PRESENT while both `APPLE_*` secrets were unset — a check
that cannot fail. Anchor on the markup the renderer emits only for a *configured*
provider (here `data-provider="apple"`), and cover it with a negative control that
includes the font-stack string. Same failure family as Trap 5: **source/substring
review cannot tell you what rendered.**

⚠️ **A gate that exits 0 with zero output is indistinguishable from a gate that never
ran.** Socket aliases `npx`, so `npx tsc --noEmit` can emit only Socket's banner.
Prove the instrument: inject a deliberate error, confirm non-zero, remove it, confirm
zero, confirm the tree is clean. Or call the binary directly
(`./node_modules/.bin/tsc`) — and note Socket eats `--dry-run`, so
`npx wrangler deploy --dry-run` never reaches wrangler.

## Hard rules

- **Never** put `KEY|SECRET|TOKEN|PASSWORD` in wrangler `vars` — `wrangler secret put`.
- **Never** widen an audience/issuer set beyond clients you own, and assert the exact set in a test.
- **Never** use Apple's `appBundleIdentifier` — it REPLACES the audience (apple.mjs:63). Use the `audience` array so the web Services ID stays valid, and assert `appBundleIdentifier` is undefined.
- **Never** gate a value that must ALWAYS be present behind an optional env var. A public identifier (bundle id, client id) belongs in a constant; an unset var turns a required audience into no audience, silently.
- **Never** report native social working from source review — the CSS and the binary both get a vote.
- A native-capability change needs a **new build**; a site-side change does not. Say which one you shipped.
- **Never** leave `passkey({ origin })` unset — that hands the verifier's expected origin to the caller (Trap 9).
- **Never** transcribe a plugin migration from memory or a blog — read the **installed** package's schema; the two sites are on different versions (Trap 11).
- **Apply the remote D1 migration BEFORE the code deploys**, and prove it with `PRAGMA table_info` on `--remote`. Plugin code writes these tables on first use.
- **Never** claim an auth feature works from a green route check. Schema present + route reachable ≠ a write succeeds ≠ the iOS ceremony completes. Name which of the three you verified.
- **Never** widen 2FA's advertised scope past `/sign-in/email` — magic link, email code, Apple, Google and passkey are not second-factored (Trap 10).
- **Never** hand-roll the Apple client secret or the Apple setup steps — route through `siwa` (`siwa portal` → `domain-file` → `secret` → `probe` → `verify`), and treat `siwa probe`'s `invalid_grant` as the PASS. Keep `betterauth` read-only; `siwa` owns the writes.
- **Never** let the session gate swallow `/.well-known/` — Apple's domain verification fetches it unauthenticated, and a 302 there fails silently.
- **Never** trust a Python-based auth health check that reports a failure until you have re-run the same URL through `curl` (Cloudflare 403s the default urllib UA), and never detect a provider button by substring — `-apple-system` in the font stack makes `"apple" in html` a check that cannot fail.
