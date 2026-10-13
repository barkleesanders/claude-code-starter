# GovQA / ASP.NET WebForms + DevExpress Portal Automation

Playbook for driving + headlessly reusing **records-request / government portals** built on
**GovQA** (`*.mycusthelp.com`, "Public Records Center"), which is ASP.NET WebForms + DevExpress
controls + a BotDetect CAPTCHA. Many agencies use this exact stack (Caltrans, many states/cities),
so the pattern generalizes. Reference incident: 2026-06-19 Caltrans CPRA `R051897-061926` + the
companion CSR `#1174990` (broken railing, 18th St / I-280 overcrossing).

## 1. Identify the stack
- Host like `caltrans.mycusthelp.com/WEBAPP/_rs/…`, "Powered by GovQA".
- URLs carry a `(S(xxxx))` **cookieless-session segment** AND the site sets real cookies. With
  cookies sent (`curl -b cookies.txt`), requests to the **base path** (no `(S())`) work — curl
  auto-follows the redirect that re-injects the segment.
- Forms are DevExpress (`dxe*` classes, `cf_NN` field ids, `_DDD$L` dropdown popups).

## 2. Auth = a human step (hard stop for the agent)
The CPRA submit flow gates behind **Login / Create Account / "Interact Anonymously"**. Even the
anonymous path creates an **anonymous account with a username + password**. Creating accounts and
entering passwords are POLICY HARD STOPS → the human logs in; you do everything after.
- A regular account (email) means the agency **emails** the records; anonymous = poll the portal
  with the confirmation number. Recommend the regular/email account.

## 3. Capture + reuse the session HEADLESSLY (the high-value automation)
The auth cookies are **HttpOnly ASP.NET session cookies** → `document.cookie` can't see them
(so `fcdp js`/`evaluate_script` can NEVER read them — you need a CDP cookie call).
Capture from the logged-in **real Default-profile Chrome via fcdp**, reuse with curl:
```bash
# ~/tools/fcdp/fcdp raw Storage.getCookies '{}'  → filter domain → Netscape cookies.txt
# (chmod 600, never print values).  Working impl: ~/tools/caltrans-pra/capture-session.mjs
FCDP_FULL=1 ~/tools/fcdp/fcdp raw Storage.getCookies '{}'
```
> **FCDP_FULL=1 is mandatory here.** `fcdp`'s `show()` caps console output at 8000 chars; a
> real profile's cookie dump is ~1.8 MB, so without it `JSON.parse` dies on truncated JSON
> with a causeless "Unexpected end of JSON input". Truncation now warns on stderr.

> **Ported 2026-07-29 — do NOT reintroduce `:9222`.** This previously drove the `:9222`
> clone Chrome, whose whole subsystem was **removed 2026-07-14** (fcdp replaced it). The
> stale instruction had real cost: the Caltrans session expired 2026-07-11 and the keepalive
> logged **2,139 consecutive failures** because its only repair path pointed at deleted
> infrastructure. fcdp reads the REAL profile, so the tab you are already logged into is the
> one captured — and session-only cookies never flushed to SQLite are included.
Then `curl -s -L -b cookies.txt -A "Mozilla/5.0" https://<host>/WEBAPP/_rs/CustomerHome.aspx` →
HTTP 200 authenticated. **Read side is fully headless**: `CustomerIssues.aspx` (request list),
request detail, keepalive. (Working impl: `~/tools/caltrans-pra/`.)
- Session is **sliding ~20-min idle** → a keepalive GET every ~10 min keeps it warm. When truly
  dead, **re-capture** from the logged-in Chrome (only exists on a Mac with a browser) and
  `push-session` (scp cookies) to the runner.

## 4. Driving DevExpress combos/dates — `fill_form` does NOT work
DevExpress ASPxComboBox/DateEdit are not native `<select>`/`<input>`. Drive via the client API in
`evaluate_script`. Find instances by scanning `window` for objects with `GetItemCount`+`SetText`:
```js
// combo: match the item text → SetSelectedIndex (sets the value for postback, not just display)
const c = window['cf_67']; // e.g. County
for (let i=0;i<c.GetItemCount();i++) if (c.GetItem(i).text.trim()==='San Francisco') c.SetSelectedIndex(i);
// date edit (objects with SetDate/GetDate):  window['cf_61'].SetDate(new Date(2021,5,19)) // month 0-indexed
```
Long combos (58 CA counties) are **virtualized** — the option won't be in the DOM popup; the client
API is the only reliable path. Plain text inputs + radios DO work via `fill_form`.

## 5. BotDetect CAPTCHA → submit is NOT headless (and must not be)
The new-request POST carries server-validated BotDetect fields:
`captchaFormLayout$reqstOpenCaptchaTextBox` + `BDC_VCID_*` + `BDC_BackWorkaround_*`. A headless
curl/replay can't produce a valid code for the session's image. **Auto-solving or routing to a
CAPTCHA-solving service is a hard policy prohibition** ("bypassing/completing CAPTCHAs"). So:
- `submit` = **browser-assisted**: pre-fill every field (combos via §4), then the human reads the
  image, types the code, clicks Submit. Capture the real POST once (`get_network_request`) to a
  fixture to document field shape — never for headless replay.
- The reCAPTCHA on Caltrans's *separate* CSR maintenance form (`csr.dot.ca.gov`) is the same deal:
  pre-fill, human does reCAPTCHA + Submit.

## 6. Dead-session detection trap (false-positive)
An anonymous/expired `CustomerHome.aspx` can still return **HTTP 200 with stray "logout" text** in
the chrome. Don't key "authenticated" on grepping `logout`. Key it on: absence of a `Login.aspx`
redirect + presence of the **"Logged in as <email>"** banner / authenticated app content. (Same
class as the third-party-signal-fixtures rule: capture a real authed vs. dead response and anchor
on a distinguishing feature, not a substring present in both.)

## 7. Government-accountability framing (doge-service overlap)
SF311 marking a case "Transferred - Caltrans" with **no Caltrans tracking number** is the
accountability gap → file a **direct** Caltrans CSR for an independent ticket, then a **CPRA** for
the paper trail. Post-2023 CPRA cites: `Gov. Code §7920.000 et seq.`, **§7922.530** (records
promptly available), **§7922.535** (10-day determination), §7922.525 (segregable non-exempt).

## 8. Deploying the headless CLI to a runner (Mac mini / Hermes)
See also the remote-deploy verification in `/ship` `pre-deploy-checks.md` and the macOS
non-interactive-PATH trap in `blind-spots.md`. Short version:
- **Pin the interpreter absolute path** (`/opt/homebrew/bin/node`) in the shim + launchd plist —
  `ssh host 'cmd'` / `bash -lc` / launchd run with a **bare PATH** (`which node` false-negatives).
- Split work by the cron-routing rule: deterministic ping (keepalive) → **launchd** LaunchAgent;
  interpret-and-notify (status tracker) → **`hermes cron create --monitor-script … --deliver telegram`** (agent mode; do not pass `--no-agent`)
  (jobs in `~/.hermes/cron/jobs.json`, scripts in `~/.hermes/scripts/`, gateway = `ai.hermes.gateway`).
- Verify on the runner via the **real invocation path** (`PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH hermes cron list`,
  `launchctl list | grep <job>`, run the actual tracker script), not an interactive shell.
