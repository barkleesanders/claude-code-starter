# Session capture → typed client + MCP server (`fhar`)

Turn a website you're **already logged into** into a typed API client and MCP server,
by recording what its own frontend actually sends. The web analog of the `mimic`
mobile flow. Tool: `~/tools/fcdp-har/fhar` (built on `fcdp`, drives your REAL Chrome).

Verified working 2026-08-03 on this machine (laptop, Chrome via the fcdp bridge).

---

## The protocol

```bash
FHAR=~/tools/fcdp-har/fhar
~/tools/fcdp/fcdp open "https://app.example.com"

$FHAR rec --secs 300 --out ~/re/example.har
```

Then, **by hand in Chrome**, while it records:

1. **Log OUT.** Captures session teardown — the logout endpoint and cookie clearing.
2. **Log back IN.** ← *This is the step that matters.* The login POST, the
   `Set-Cookie` / token response, and any CSRF or refresh handshake are the part you
   cannot reconstruct by guessing. Skipping it is the single most common reason a
   generated client can't authenticate.
3. **Visit every page whose data you want.** Each view fires the endpoints behind it.
   Paginate, open a detail view, apply a filter — variety here is what turns one
   endpoint into a parameterized one.
4. `Ctrl-C` when done (or let `--secs` expire).

```bash
$FHAR distill ~/re/example.har --md     # -> example.api.md  (read THIS)
$FHAR gen     ~/re/example.har          # -> ~/re/example-api/ scaffold + PROMPT.md
```

Then point Claude at the scaffold's `PROMPT.md`.

### Why not hand Claude the raw HAR
A 5-minute session HAR is megabytes: hundreds of duplicate requests, base64'd images,
and every static asset. It buries the signal and blows the context window. `distill`
collapses `/projects/11` + `/projects/12` into one `GET /projects/{id}` with an
inferred schema, drops static assets and noise headers, and keeps one representative
call per endpoint. **Read `api-digest.md`; `grep` the HAR only when the digest is
ambiguous about one specific request.**

---

## 🔐 Security — read before recording

A HAR of a login flow contains **the actual password you typed** and **live session
cookies**. Treat it like a credential file.

| | Behavior |
|---|---|
| `.har` files | `chmod 600` on write; hold full unredacted values (that's the point — it's ground truth) |
| `api-digest.{json,md}` | secret **values** redacted, **field names kept** (so you still know an `Authorization` header is required) |
| `fhar gen` scaffold | ships a `.gitignore` excluding `*.har` and both digests |
| `--keep-secrets` | local debugging only. Never share a file produced with it. |

Redaction covers: `authorization`, `cookie`/`set-cookie`, anything containing `token`,
`session`, `jwt`, `password`, `secret`, `csrf`/`xsrf`, `api[-_]key`, `signature`,
`otp`/`mfa`/`pin`, `ssn`, card fields — plus value-shape detection for JWTs (`eyJ…`),
`sk_live_…`, `AKIA…`, `ghp_…`, `AIza…` regardless of key name.

Never paste a raw HAR into chat, commit it, or upload it to a HAR-analyzer website.

---

## Gotchas (each of these has bitten)

**`fcdp intercept` cannot substitute for `fhar rec`.** It records `{method, url}` only
— no headers, no bodies, no status. It answers "does an endpoint exist"; it can never
answer "how do I call it". Don't try to write a client from its output.

**`--secs N` is mandatory on `fcdp intercept`/`console`/`network`.** A bare positional
number parses as a **tabId**, so `fcdp intercept 8` silently watches nonexistent tab 8
and reports nothing. (`fhar rec` takes `--secs` too; `fhar rec <tabId> <secs>` also works.)

**One debugger per tab.** `fcdp`, `fhar`, and `ccb` all use `chrome.debugger`; only one
can attach to a given tab. If attach fails, `~/tools/fcdp/fcdp detach <tab>` first, or
record in a tab of its own. Chrome will show a "being debugged" infobar — that's normal.

**Response bodies can be evicted.** Chrome drops bodies from the inspector cache under
memory pressure. `fhar` sets a 512 MB total / 64 MB per-resource buffer and fetches each
body the moment `loadingFinished` fires, which makes this rare — but if the digest shows
an endpoint with no response schema, re-record just that page in a short session.

**Service workers.** A response served by a SW may not appear as a network request at
all, or may appear twice (SW fetch + network fetch). If an endpoint you *know* fires is
missing, hard-reload with the SW bypassed (DevTools ▸ Application ▸ Service Workers ▸
Bypass for network) and re-record.

**GraphQL.** Every operation POSTs to one path, so naive grouping would collapse the
whole API into a single entry. `fhar` splits on `operationName` (falling back to the
`query … {` / `mutation … {` name in the document), so you get
`POST /graphql#GetCart`, `POST /graphql#AddItem`, … each with its document verbatim
and its `variables` schema. Batched arrays are keyed off the first operation.

**WebSockets.** Frames are captured into `_webSocketMessages` (Chrome's own HAR
convention) and the digest collapses them to one sample per message *shape*, keyed on
the protocol's discriminator field (`type`/`event`/`op`/`action`/`method`/`kind`),
with counts. Capped at 300 frames per socket — a chatty feed is truncated with an
explicit marker, never silently.

**Multi-host sessions.** Auth often lives on a different host than data
(`accounts.x.com` vs `api.x.com`, plus a CDN). The digest's `Hosts:` line gives counts
— pick the API host, and note that cookies may be set on a parent domain.

**A captured call is not always replayable.** Bot protection (Cloudflare/Akamai
fingerprinting), DPoP/mTLS-bound tokens, and short-lived per-request CSRF nonces can
all reject a replayed request that looked complete in the HAR. If a replay 403s while
the browser succeeds, that's the reason — not a bad capture.

---

## When the digest comes back thin or empty

Not every site *has* a JSON API. Before concluding anything:

1. **Server-rendered / RSC app** (Next.js App Router, Rails/Django HTML, HTMX). The
   data arrives inside the document or an RSC payload, not a JSON endpoint. There is no
   API to wrap — go back to the endpoint-discovery ladder rungs 1–2 in SKILL.md (read
   the backend's routes if open source, or the deployed bundle), or accept that
   extraction means parsing the HTML.
2. **You didn't exercise the app enough.** A capture only contains endpoints you
   triggered. Re-record and click more: paginate, filter, open detail views.
3. **The traffic is WebSocket-only.** Check the `WS` lines in the digest.
4. **A service worker swallowed it** — see above.

State which of these it was. "The site has no API" is a claim that needs evidence, not
an empty digest.

---

## Writing the client (rules for the generated code)

The scaffold's `PROMPT.md` carries these; repeated here because they're where
generated clients go wrong.

1. **The digest is the contract.** Header names, body shapes, and status codes came off
   the wire. Do not invent fields, and do not "fix" a weird-looking parameter name.
2. **Never hardcode a captured secret.** Values are redacted; keep the *name*, read the
   value from env/config at runtime.
3. **Model the auth handshake explicitly** — cookie jar vs `Authorization` header vs
   both, and any CSRF token read from one response and echoed on the next request.
4. **Mutations are separate, narrowly-described MCP tools.** Never expose a generic
   `call_api(path, method, body)` tool — that hands an agent an unbounded write
   primitive against the user's real account.
5. **Uncertainty gets a comment.** A field seen once is typed but flagged.

### Verification gate
Run at least one **read** endpoint against the live API with real credentials and show
the actual response before calling the client done. An unrun client is a hypothesis.
Do **not** auto-fire a captured mutation to "test" it — that's an outward, irreversible
action on the user's real account; dry-run it and get explicit approval first.

---

## If the user already has a HAR

Someone who did the DevTools steps by hand (Network ▸ **Preserve log** ▸ log out/in ▸
visit pages ▸ right-click ▸ **Copy all as HAR**) has the same artifact. Skip `rec`:

```bash
~/tools/fcdp-har/fhar distill /path/to/theirs.har --md
~/tools/fcdp-har/fhar gen     /path/to/theirs.har
```

`distill` reads any HAR 1.2 file, whatever produced it (Chrome, Firefox, Charles,
mitmproxy's `har_dump`). Note their export may lack response bodies — Chrome's "Copy
all as HAR" omits them unless "Allow generating HAR with sensitive data" is enabled;
`fhar rec` always captures them.

---

## Command reference

```
fhar rec [tab] [--secs N] [--out f.har]    record (default 300s; Ctrl-C to stop early)
fhar distill <f.har> [--md] [--out d.json] [--keep-secrets]
fhar gen <f.har> [--out DIR]               scaffold Bun/TS project + PROMPT.md
fhar ls                                    list recorded sessions (~/.fcdp-har)
```

Scope: `fhar` drives **your own** logged-in session against services you already hold an
account on, for interoperability. It is not a tool for probing sites you don't control.
