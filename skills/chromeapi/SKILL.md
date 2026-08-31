---
name: chromeapi
user-invocable: true
description: Capture a site's internal API routes from your REAL logged-in Chrome and replay them browserless (kuri/unbrowse-style, all local). The deeper-level API layer on top of fcdp. Invoke as /chromeapi when the user wants to record the XHR/fetch calls a page makes and re-fire them as plain HTTP with their real cookies — no browser, no telemetry. /chrome (fcdp) remains the tool for ordinary page driving.
---

# /chromeapi — capture & replay a site's internal API (on your real Chrome)

The **deeper-level API layer** built on top of `/chrome` (fcdp). Same real logged-in
Default-profile Chrome — but instead of clicking/reading a page, it **records the internal
API calls the page fires** into a manifest, then **replays them browserless** as plain `curl`
using your real Chrome cookies. This is the local, no-telemetry equivalent of unbrowse/kuri's
capture→replay trick (reverse-engineered 2026-07-22; see memory `reference_fcdp_full_cdp.md`).

`/chrome` (fcdp) stays exactly as-is for ordinary driving (open/read/click/type/js/pdf/…).
`/chromeapi` is when the goal is **"find the API call and replay it without a browser."**

## Step 0 — does the site PUBLISH its API? Check before you capture anything

**Run this first, every time.** A capture window is a guess: you get only the endpoints the
page happened to fire in those N seconds, method+URL only, no schema. If the site publishes
a spec, that's the **entire API surface with parameter names, types and response schemas** —
strictly better data, in one request, with no browser.

Note this is the API analog of `/chrome`'s sitemap-first rule, **not sitemap.xml itself**.
A sitemap enumerates *pages*; it tells you nothing about an API. The right artifacts here
are OpenAPI/Swagger/GraphQL. (Do still glance at `robots.txt` — it sometimes names an
`/api-docs` path.)

```bash
# Prefer the a logged-in browser CLI probe (robots/sitemap/OpenAPI/headers/scripts):
a logged-in browser CLI inspect https://<host>
# Old unbrowse MCP spec-discover is UNINSTALLED — do not invoke it.
# Unpublished / cookie-gated: a logged-in browser CLI capture <url> [--fcdp]
#   or ~/tools/fcdp-api/fapi capture <url> [secs]
# HAR distill: a logged-in browser CLI distill <file.har>
```

Decision rule:
- **Spec found** → read it. You now have every route, its params and its response shape.
  Skip `fapi capture` entirely and go straight to `curl` (still with real cookies for
  authenticated routes). This is also the only way to learn about endpoints the UI never calls.
- **GraphQL** (`/graphql` responds) → introspection may be enabled; that's the whole schema.
  Introspection is often disabled in production — if so, fall through to capture.
- **Nothing published** (the common case for consumer web apps) → proceed to `fapi capture`
  below. That's the normal path, not a failure.

A 404 on all of the above is a 5-second answer, so there's no reason to skip it — and when
it hits, it saves the capture cycle *and* gives you schemas `fapi` structurally cannot infer
(see the "Gap vs unbrowse/kuri" note below: `fcdp intercept` surfaces method+URL, not bodies).

## The tool: `fapi`

`~/tools/fcdp-api/fapi` (also `~/tools/fcdp/fapi`). Built on `fcdp intercept` (capture) +
`~/tools/cookies-txt` (real-profile cookies) + `curl` (browserless replay). Nothing leaves the machine.

```bash
fapi capture <url> [secs]   # open a bg tab in REAL Chrome, intercept the API calls it fires -> manifest
fapi list                   # list captured domains
fapi show <domain>          # print the endpoint manifest (JSON)
fapi replay <domain> [n]    # browserless curl replay of GET endpoint(s), with real Chrome cookies
```

Manifests live in `~/.fcdp-api/<domain>.json`: `{domain, trigger, captured_at, endpoints:[{method,url,idempotency}]}`.

## How to run it

1. **Capture** — pick a URL that fires the API you want (the page, or the API URL itself). Give it
   enough seconds to let the page's XHRs fire (default 8):
   ```bash
   ~/tools/fcdp-api/fapi capture "https://app.example.com/dashboard" 8
   ```
   Report the endpoints it found (`fapi show <domain>`). If it found 0, the page may fire its
   XHRs later than the window — re-run with more seconds, or point `capture` directly at the API URL.
2. **Replay** — re-fire the safe (GET) endpoints without a browser, using the user's real cookies:
   ```bash
   ~/tools/fcdp-api/fapi replay app.example.com
   ```
   This is step 3 of the web-lookup ladder (cached endpoint replay, no live browser) done against
   the user's OWN session.

## Rules & safety

- **GET-only auto-replay.** `fapi replay` fires only `GET` endpoints. POST/PUT/DELETE/PATCH are
  listed but NEVER auto-fired — a mutation is an outward, irreversible action: show the exact
  request and get explicit per-action approval, then fire it by hand with `curl`.
- **Real cookies, local only.** `~/tools/cookies-txt` reads the Default profile's cookie SQLite +
  Keychain. Cookies never leave the machine. Only capture/replay sites the user is lawfully using
  their own account on.
- **One debugger per tab.** `fapi capture` uses `fcdp intercept`, which attaches `chrome.debugger`
  to a fresh background tab and closes it after — it won't fight a tab you're driving with `/chrome`.
- **Gap vs unbrowse/kuri (by design):** stores method+URL only — no response-schema inference or
  ranked semantic resolve, because `fcdp intercept` surfaces method+URL, not response bodies. If
  schema inference is ever wanted, add `Network.getResponseBody` capture to fcdp. Better than kuri
  in the way that matters here: it runs against the user's REAL logins (no separate auth step).

## When to use which

| Want to… | Use |
|---|---|
| inspect / fetch / capture / GET-replay / drive as one stack | a logged-in browser CLI (preferred for new work) |
| open/read/click/type/screenshot/PDF a page, run JS | `/chrome` (fcdp) |
| record a site's internal API calls and replay them browserless | `a logged-in browser CLI capture` + `replay`, or this skill's `fapi` |
| decompile a binary / RE how some app talks to its API | `/decompile` |
| turn a captured HAR/JSON into a **repeatable assert** (jsonpath on unwrap, status, body keys) | `hurl --test file.hurl` (installed 2026-08-14). Capture with `fhar`/`fapi`/a logged-in browser CLI, flatten with `gron` to find the path, then write the Hurl file. Never commit the raw HAR. |

Full RE writeup of how this mirrors unbrowse/kuri: memory `reference_fcdp_full_cdp.md`.
