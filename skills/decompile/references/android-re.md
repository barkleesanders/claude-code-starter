# Android RE deep-dive — static + **mandatory dynamic capture**

The #1 RE failure on Android apps is **stopping at static analysis** (jadx + grep +
reconstructing the request by hand) and reporting a decompiled endpoint as if it were
proven. A decompiled endpoint is *capability*; only a **captured live request+response**
is *proof of the contract*. This file is the runtime-capture playbook, verified working on
this machine 2026-08-01.

## ⛔ MANDATORY-STEP RULE (do not skip)

**If the task is "prove what request the app makes" or "does endpoint X return data / can we
pull it" — you MUST run the dynamic capture (emulator + mitmproxy), not just the static
reconstruction.** Reporting "endpoint is dead / returns Y" from `curl` alone, when you have
NOT captured the real app issuing it, is the exact overclaim this rule exists to prevent
(2026-08-01: an OCV/Appriss inmate endpoint was declared "GLOBALLY DEAD" off a `curl` test
that used the wrong identifier — the app passes a *feature-level* appID, not the app's
global `app_id`. Static reading alone hid that.)

The static path answers *what endpoint exists*. The dynamic path answers *what the app
really sends and what comes back*. **Run both.** The only acceptable reasons to stop before
the dynamic capture:
1. You captured it (done — report the real request+response).
2. A hard external blocker you name explicitly (e.g. cannot obtain an APK of the app that
   provisions the feature; cert-pinning + DPoP that `objection`/`mimic unpin` can't defeat).
   Say exactly which, and what would unblock it.

## Toolchain on THIS machine (verified 2026-08-01)

| Piece | Location / fact |
|---|---|
| Android SDK | `~/Library/Android/sdk` (Android Studio installed). Export `ANDROID_HOME=$HOME/Library/Android/sdk`. |
| `adb` | `$ANDROID_HOME/platform-tools/adb` (also `/opt/homebrew/bin/adb`) |
| `emulator` | `$ANDROID_HOME/emulator/emulator` (NOT on PATH) |
| `sdkmanager`/`avdmanager` | `$ANDROID_HOME/cmdline-tools/latest/bin/` |
| system image | `android-34` `google_apis` **arm64-v8a** installed |
| **rootable AVD** | **`sf311_root`** — a `google_apis` (NOT playstore) image → `adb root` + writable `/system` works. Use this one for CA install. |
| Play AVD | `pixel_test` — `google_apis_playstore`; can install from Play but **cannot `adb root`** (verity). |
| mitmproxy | `~/.local/bin/mitmdump` 12.2.3; venv python at `~/.local/pipx/venvs/mitmproxy/bin/python` (use it to read `.mitm` flow files — system python3 can't `import mitmproxy`). |
| frida / objection | `~/.local/bin/frida` 17.x, `~/.local/bin/objection` |

## The full capture procedure (copy-paste, verified)

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"; ADB="$ANDROID_HOME/platform-tools/adb"

# 1) Boot the ROOTABLE google_apis AVD, writable-system, headless
"$ANDROID_HOME/emulator/emulator" -avd sf311_root -no-window -no-audio \
  -writable-system -no-snapshot-load -http-proxy 127.0.0.1:8080 >/tmp/emu.log 2>&1 &
#    ^ -http-proxy on the EMULATOR FLAG is more reliable than `settings put global http_proxy`
#      (the global setting is ignored by many apps / system HTTPS). Prefer the flag.
until [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 5; done

# 2) mitmproxy CA into the SYSTEM trust store (apps trust user CAs only via
#    network_security_config; system store works for everything).
#    Android filename = the OLD subject hash + ".0".
HASH=$(openssl x509 -inform PEM -subject_hash_old -in ~/.mitmproxy/mitmproxy-ca-cert.pem -noout)
cp ~/.mitmproxy/mitmproxy-ca-cert.pem "/tmp/$HASH.0"
$ADB root; sleep 3            # "restarting adbd as root"
$ADB remount                  # "Successfully disabled verity / Remounted /system as RW"
$ADB push "/tmp/$HASH.0" /system/etc/security/cacerts/
$ADB shell chmod 644 "/system/etc/security/cacerts/$HASH.0"
#    (if remount fails: `$ADB shell avbctl disable-verification` then `$ADB reboot` once, retry)

# 3) Start mitmdump capturing to a flow file
~/.local/bin/mitmdump -q -w ~/re/cap/flows.mitm --set stream_large_bodies=1 -p 8080 &

# 4) Install the target app  (⚠️ ABI GOTCHA — see below) and launch it
$ADB install-multiple -r ~/re/app/*.apk        # split APK (base + config.<abi>/<dpi>/<lang>)
$ADB shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1
#    …then DRIVE THE UI to the feature (tap Inmate Search, type a name). Headless: use
#    `$ADB shell input tap X Y` / `input text "smith"`, or run with -no-window off to watch.

# 5) Read the captured request+response with the mitmproxy venv python
~/.local/pipx/venvs/mitmproxy/bin/python - <<'PY'
from mitmproxy.io import FlowReader
with open('/Users/<you>/re/cap/flows.mitm','rb') as f:
    for fl in FlowReader(f).stream():
        if fl.response:
            print(fl.response.status_code, fl.request.method, fl.request.pretty_url)
            # dump headers + body for the target host to see the REAL contract
PY

# 6) Teardown
$ADB emu kill 2>/dev/null; $ADB shell settings put global http_proxy :0 2>/dev/null
kill %1 %2 2>/dev/null    # emulator + mitmdump
```

## Gotchas that cost real time (2026-08-01)

1. **ABI mismatch = `INSTALL_FAILED_NO_MATCHING_ABIS` (res=-113).** APKPure/apkeep often
   hand you the **`armeabi_v7a` (32-bit)** split. The `android-34` **arm64-v8a** emulator
   has **no 32-bit support**, so any app with a required native lib crashes on launch (and
   base-only install crashes when the lib is first touched — often before the network call,
   so you capture nothing). Fixes, in order: (a) get the **arm64-v8a** split or a
   **universal** APK; (b) boot an **x86_64** `google_apis` image (has libnativebridge/arm
   translation for many apps); (c) `apkeep` with `--arch` if the source honors it.
2. **APK acquisition is the usual hard wall.** `apkeep 1.0.0`'s APKPure backend **silently
   returns nothing** (their API drifted); apkcombo 404s / JS-gates the final link; APKPure
   and the direct CDN are **Cloudflare-403** to `curl` and even stall `fcdp` real-Chrome on
   the challenge; F-Droid/Huawei don't carry proprietary US gov apps. **Reliable routes:**
   (a) **Play Store on the `pixel_test` AVD** (needs the user's Google login once — then
   `adb shell pm path <pkg>` → `adb pull` the APK, and you can extract resources even if you
   can't root that image); (b) the user hands you the APK; (c) an aurora/gplay token for
   `apkeep -d google-play`. **You often need the user for this one — say so.**
3. **`settings put global http_proxy` is unreliable** — many apps and system HTTPS ignore
   it. Use the emulator **`-http-proxy` launch flag** instead (routes everything).
4. **Reading `.mitm` files:** only the mitmproxy **venv** python can `import mitmproxy`
   (`~/.local/pipx/venvs/mitmproxy/bin/python`). System `python3` will `ModuleNotFoundError`.
5. **You don't always need the app.** If the captured/decompiled request has **no dynamic
   token** (plain GET + a static header key — confirm by reading the HTTP client: e.g.
   `HttpClients.createDefault()` with no interceptors ⇒ nothing dynamic), then a `curl`
   with the **correct** parameters == the app's request. The emulator's value is then only
   to (a) reveal a parameter you can't get statically (e.g. a per-feature id fetched from a
   server-side manifest at runtime) and (b) serve as the positive control. Decide which you
   actually need before spending 30 min booting an emulator.

## Cert-pinning

If capture shows TLS handshake failures / the app refuses to talk through the proxy despite
the system CA, it's **certificate pinning**. Defeat it with frida:

```bash
objection -g <pkg> explore -c 'android sslpinning disable'     # one-liner
# or a frida universal-unpinning script:
frida -U -f <pkg> -l ~/.local/share/frida-scripts/android-unpinning.js --no-pause
```
`mimic unpin <app.ipa|bundle-id>` does the same for iOS. **DPoP-bound tokens still won't
replay** even after unpinning — those are cryptographically bound to the device key.

## btsnoop / BLE (for wearables etc.)

```bash
$ADB shell settings put secure bluetooth_hci_log 1
$ADB shell svc bluetooth disable && $ADB shell svc bluetooth enable
# …exercise the BLE feature…
$ADB bugreport bugreport.zip && unzip bugreport.zip -d br/
find br/ -name '*.cfa' -o -name '*.btsnoop' 2>/dev/null    # locate the capture
# Read it with tshark (installed 4.6.7 — btatt/btle/bthci_acl dissectors present), filter by service UUID:
tshark -r <btsnoop-file> -Y btatt -T fields -e btatt.uuid128 -e btatt.value | sort -u
```

## Static path (do this first, then the dynamic capture above)

```bash
apkeep -a <pkg> -d apk-pure ~/re/app/        # (unreliable — see gotcha 2)
unzip <pkg>.xapk -d unpacked/                # split-APK bundle
jadx --no-res -d jadx-out unpacked/<base>.apk
apktool d -f -s -o at unpacked/<base>.apk    # `-s` = resources only (fast); read res/values/strings.xml
#   → app_id / api keys live in strings.xml; ABI-INDEPENDENT (extract from ANY split, even wrong-ABI)
grep -rhoE 'https?://[a-z0-9.\-]+/[a-zA-Z0-9/_.{}$\-]*' jadx-out/sources | sort -u   # endpoints
# find where the request is BUILT (headers, appID source, method) and read the HTTP client
# to decide if there's a dynamic token → dictates whether you need the emulator (gotcha 5).
```

## PairIP (Google Play app-protection) — the token-extraction catch-22

If a sideloaded app launches into `com.pairip.licensecheck` → "Something went wrong", it's
**PairIP** (Play's licensing/anti-tamper). The app runs ONLY when Play-installed, i.e. only
on a Play-image emulator (un-rootable). So you can't have both "app runs" AND "root to read
/data" at once. And patching PairIP out requires re-signing, which breaks any Google-Sign-In /
Firebase auth that verifies the app's registered signing SHA. Net: an in-app auth token for a
Play-protected app is generally NOT extractable via local emulators. Name this wall and stop.

## Firebase Google-auth token capture — DEVICE-FREE (defeats PairIP/FBE/Play-image)

**The winning move when an Android app uses Firebase Auth + Google Sign-In and you need a
token to drive its API from a CLI, but the device path is blocked** (PairIP won't run it
sideloaded, Play image can't root, /data is FBE-encrypted, backup neutered). Don't fight the
device — mint the token **device-free** via Google's OIDC implicit flow, because Firebase
Google sign-in is just `signInWithIdp` under the hood. Verified end-to-end 2026-08-01 on
Solve SF (`com.woahfinally.solvesf`).

**1. Extract 3 values from the APK** (`apktool d -s base.apk` → `res/values/strings.xml`, or google-services):
   - `google_api_key` (Firebase apiKey), `project_id` → authDomain = `<project_id>.firebaseapp.com`
   - the **web OAuth client** = the `oauth_client` with the sender-id prefix, form
     `<SENDER_ID>-xxxx.apps.googleusercontent.com` (grep the APK: `[0-9]{12}-[a-z0-9]+\.apps\.googleusercontent\.com`).

**2. Open this URL in the user's logged-in Chrome (`fcdp open`):**
```
https://accounts.google.com/o/oauth2/v2/auth?client_id=<WEB_CLIENT>&redirect_uri=https%3A%2F%2F<PROJECT>.firebaseapp.com%2F__%2Fauth%2Fhandler&response_type=id_token&scope=openid%20email&nonce=<rand32hex>&state=<rand16hex>&prompt=consent&login_hint=<user@gmail.com>
```
`login_hint` skips the account chooser. If a chooser appears anyway, its rows are plain DIVs
that `fcdp click` won't match — click the **jsaction-carrying** element via raw CDP:
`fcdp raw <tab> Input.dispatchMouseEvent '{"type":"mousePressed","x":X,"y":Y,"button":"left","buttons":1,"clickCount":1}'` (+ mouseReleased).

**3. Read the Google id_token straight from the redirect fragment.** It lands on
`https://<PROJECT>.firebaseapp.com/__/auth/handler#...&id_token=...` — that page shows a
harmless **"Unable to process request due to missing initial state"** error; the token is in
the URL regardless: `fcdp js <tab> "new URLSearchParams(location.hash.slice(1)).get('id_token')"`.

**4. Verify + exchange for a Firebase refreshToken:**
```bash
curl -s "https://oauth2.googleapis.com/tokeninfo?id_token=$G"    # aud == web client, email correct, email_verified
curl -s -H 'Content-Type: application/json' \
  --data-binary "{\"postBody\":\"id_token=$G&providerId=google.com\",\"requestUri\":\"http://localhost\",\"returnSecureToken\":true}" \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$FIREBASE_API_KEY"
#  -> { idToken, refreshToken, localId, email }  ← refreshToken is long-lived; refresh via
#     securetoken.googleapis.com/v1/token (grant_type=refresh_token) forever.
```

**Gotchas that cost time:**
- `response_type=id_token` (implicit) — **no client secret needed** (and the secret isn't in the APK anyway).
- **Only the app's OWN Firebase web client works.** OAuth-Playground / `gcloud auth print-access-token` / device-code tokens are all rejected by signInWithIdp with `INVALID_IDP_RESPONSE: audience is not for this project`. Device-code also 401s (`invalid_client` — client isn't "TV/limited-input" type). Loopback/OOB redirects aren't registered. The `firebaseapp.com/__/auth/handler` is the only accepted redirect.
- **In automated Chrome, `signInWithPopup` → `auth/popup-blocked`, and `signInWithRedirect` + `getRedirectResult` is flaky** (storage partitioning eats the pending-state; the page's `initializeApp` can also lose a script race). The **raw OIDC fragment read (step 3) is the robust path** — it needs no page JS at all.
- Backends often mix auth: **public/submit routes take `x-api-key` + `Authorization: Bearer <Firebase idToken>`, but user-account routes use AWS_IAM/SigV4** (Cognito-federated from the Firebase token) and reject a Bearer with `Invalid key=value pair … Authorization header (hashed with SHA-256)`. Don't assume one scheme for all routes.

This is strictly better than the emulator dance for Firebase-Google apps: no APK, no root, no
frida, no PairIP fight. The user does one Google consent (their own account) in their own browser.

### ⚠️ The token is only HALF of it — find the post-auth REGISTRATION call

Minting the Firebase token (above) authenticates you, but many Firebase-backed
backends **key their own data on a backend userUUID that is NOT the Firebase
localId**. The app makes a **registration/login call right after Google sign-in**
that maps `googleID → backend userUUID` and creates the user row. Skip it and
lightly-authed endpoints (presigned-URL, public reads) work while **any
user-scoped write silently 404s** — e.g. Solve SF `/submit` → `404 {"error":"Invalid"}`
even though auth, headers, and body were byte-perfect. The tell: the failing
endpoint is a *write keyed on userUUID*, the token itself is fine (other calls
200), and the error is a bare app-level "Invalid"/"not found", not a 401/403.

Find it by grepping the decompile for the sign-in screen's backend POST:
```bash
grep -rhoE 'execute-api[^"]*/prod/[a-z-]+' jadx/ | sed 's#.*/prod/##' | sort -u   # enumerate ALL routes
grep -rln 'login-android-user\|create-user\|register\|signin' jadx/sources/**/screens/  # the sign-in call
```
Read its request (body fields + response). Solve SF (`GoogleLoginScreenKt`):
`POST /prod/login-android-user` `{idToken, isGoogleSign:true}` (+ x-api-key +
`Authorization: Bearer <idToken>`) → `{userUUID, googleID, ...}`. **That
`userUUID` is what every subsequent data/submit call must send** — store it, not
the Firebase uid. Verified 2026-08-02: sending the Firebase localId 404'd; the
backend userUUID `d106835c-…` (≠ localId `0soVuLt…`) submitted cleanly (HTTP 200,
"state machine triggered"). Lesson: **replay the app's FULL post-auth handshake,
not just the token mint** — enumerate every `/prod/*` route and read the sign-in
screen's own registration POST before concluding a write endpoint is broken.
