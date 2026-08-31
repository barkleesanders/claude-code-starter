---
name: ios
description: >
  THE master iOS/macOS skill — one entry point for ALL Apple work except
  production shipping. Develop, build, run, debug, review, test, screenshot,
  ASO, App Store metadata, compliance scanning, Capacitor web-wrap apps,
  native Swift/SwiftUI, Rust-core apps. Routes to the right tool (xcodebuildmcp,
  axiom, asc, greenlight, axe) and the right granular skill. Shipping
  (archive → TestFlight → App Store) lives in /ship's iOS phase. Triggers:
  "ios", "iphone app", "build the app", "run on simulator", "app crash",
  "swiftui", "capacitor", "app store screenshots", "ASO", "app review",
  "TestFlight" (dev questions), "/ios".
---

# /ios — Master iOS Skill (develop · debug · review · test · store assets)

**Division of labor (mirrors /carmack ↔ /ship):** everything up to "put it in
users' hands" lives HERE. Production release — archive, sign, TestFlight,
App Store submit, OTA publish — is **/ship**'s iOS phase
(`~/.claude/skills/ship/references/ios-release.md`). When the user says
ship/release/submit/TestFlight-a-build, invoke /ship.

## Step 0 — Identify the app shape, then route

| App shape | How to tell | Playbook |
|---|---|---|
| **Capacitor web-wrap** (AIVA) | `capacitor.config.ts` + `ios/App/` in a web repo | Web code IS the app: edit web → `npm run build && npx cap sync ios` → run shell. Project doc: `<repo>/docs/mobile-ota.md` (AIVA: `~/AIVA-Frontend`). Plugin skills: `capacitor-core:*`, `capacitor-features:*`, `capacitor-ui:*`, `capacitor-quality:*` |
| **Native Swift/SwiftUI** | `*.xcodeproj` with Swift sources | Dev loop below + `axiom:*` / `all-ios-skills:*` framework skills |
| **Rust-core** | `Rust/` dir, UniFFI, `build_ios_rust.sh` | Rust gate (below) + rust-patterns memory |
| **Expo/React Native** | `app.json` + expo deps | Expo path: `npx expo start` + Expo Go; EAS for builds |

For iOS-version/API questions NEVER answer from memory — `axiom:axiom-apple-docs`,
`axiom:axiom-swiftui`, or sosumi MCP. iOS 26 / Xcode 26 are current (Apple
skipped 19-25); newer may exist — check, don't assume.

**Design/motion craft (installed 2026-07-10, emilkowalski/skills):** when the
work is how the UI *feels* — springs, gestures, sheets, transitions, polish —
load `apple-design` (Apple's fluid-motion approach translated for web/webview;
ideal for Capacitor surfaces that should feel native), `emil-design-eng`
(UI-polish philosophy), and run `review-animations` on motion code before
declaring done. `animation-vocabulary` names a vaguely-described effect.
Full routing lives in the `/design` skill's Cross-Mode Rules.

## Dev loop (xcodebuildmcp — preferred over raw xcodebuild)

1. `session_show_defaults` once per session; set projectPath/scheme/simulatorId/
   bundleId (AIVA: `ios/App/App.xcodeproj`, scheme `App`, `com.example.app`).
2. `build_run_sim` — build+install+launch in one call; the returned runtime
   log captures the app/webview console — **read it instead of guessing**.
3. Iterate: edit → (Capacitor: `npx vite build && npx cap sync ios`) →
   `build_run_sim` → `screenshot`. Crop/zoom details with sharp.
4. New native project: `swift package init` / scaffold per
   `axiom:axiom-xcode-mcp`; SwiftUI patterns via `@Observable` (iOS 17+),
   Swift concurrency over GCD.

## Driving + testing the UI

- Native views: `snapshot_ui` → `tap({elementRef})` / `batch`.
- **WebView content is NOT in the a11y snapshot** — drive by coordinates:
  `axe tap -x <pt> -y <pt> --udid <sim>` · `axe type "..."` (px → pt:
  px/screenshot-width × device-pt-width; iPhone 17 Pro = 402×874pt,
  iPhone 17 Pro Max = 440×956pt, iPad Pro 13" = 1032×1376pt @2x).
- **Universal apps (`TARGETED_DEVICE_FAMILY = "1,2"`)**: iPad is a first-class
  test surface, not an afterthought — check layout-touching changes on the
  iPad Pro 13" sim (same .app installs on both; `xcrun simctl install <ipad-udid>
  <App.app>` reuses the iPhone build). Store screenshots: iPhone 6.9" =
  1320×2868, iPad 13" = 2064×2752. Device-family support is PERMANENT after
  first App Store release (Apple QA1623) — flag before any submission.
- XCUITest runs: `xcode-test` skill / `test_sim` (xcodebuildmcp); Swift
  Testing patterns: `all-ios-skills:swift-testing`.
- Live a11y/VoiceOver: `xcui assert` / `xcui voiceover traverse` (axiom bin);
  deep audit: `axiom:accessibility-auditor` agent.
- **Simulator streaming + agent eyes: `/serve-sim` skill** (installed
  2026-07-10, `~/.claude/skills/serve-sim` → `~/.agents/skills/serve-sim`;
  EvanBacon/serve-sim, verified live on iPhone 17 Pro). Start daemon:
  `npx serve-sim --detach -q` → JSON with MJPEG `streamUrl` (:3100) + ws.
  **Eyes**: grab a frame — `curl -s --max-time 6 <streamUrl> | python3`
  (slice first `\xff\xd8`…`\xff\xd9`) → Read the JPEG. **Semantic eyes**:
  `curl :3100/ax` = labeled a11y tree with point frames (native views only —
  webview content still needs coordinates). **Hands**: `npx serve-sim tap
  <x> <y>` takes NORMALIZED 0..1 coords (pt/402, pt/874 on iPhone 17 Pro) —
  prefer `tap` over `gesture` for plain taps (two `gesture` calls =
  long-press). **Scroll/drag: the `gesture` CLI can NOT do it** (sends ONE
  event per call; array payload = silent no-op — verified vs AIVA webview
  2026-07-10): use `node ~/.agents/skills/serve-sim/scripts/drag.mjs
  <x1> <y1> <x2> <y2> [ms]` (one-socket timed 0x03 frames).
  `button home|lock|app_switcher`, `rotate`, `type`,
  `camera --file/--webcam` injection, `permissions grant/revoke`,
  `ca-debug` overlays, `memory-warning`. Stream in browser: :3200 preview,
  tunnel it for remote review. Stop: `npx serve-sim --kill`. Complements
  xcodebuildmcp `screenshot`/`snapshot_ui` — use serve-sim when you need
  continuous video, camera injection, permissions, CA debug, or a
  shareable live stream.

## Debug routing

| Symptom | Tool |
|---|---|
| Crash log / .ips / TestFlight crash | `axiom:crash-analyzer` (xcsym) |
| Build fails weirdly / stale code / "no such module" | `axiom:build-fixer`; SPM conflicts: `axiom:spm-conflict-resolver` |
| Perf/jank/launch time | `axiom:performance-profiler` (xcprof); SwiftUI: `axiom:swiftui-performance-analyzer` |
| Memory/leaks | `axiom:memory-auditor` |
| Webview JS errors (Capacitor) | runtime log from build_run_sim; temp console probe in native bootstrap → rebuild → read log → REMOVE probe |
| Web-layer bug in Capacitor app | /debug + /carmack — it's web code |
| Any framework question (HealthKit, StoreKit, MapKit, …) | matching `all-ios-skills:*` / `axiom:axiom-*` skill |

## Review & compliance (development-time)

- `greenlight preflight .` early and often — fix CRITICALs as you go, don't
  save them for ship day. False-positive triage: pk_live keys are PUBLIC;
  minified vendor strings (DOMPurify's SVG-attr allowlist contains
  "amplitude") fake "tracking SDK" hits — verify with targeted greps.
- Privacy manifest (`PrivacyInfo.xcprivacy`) is an UPLOAD GATE — create it
  with the app, not at ship time (UserDefaults CA92.1 + FileTimestamp C617.1
  baseline for Capacitor).
- Deep audits by domain: `axiom:security-privacy-scanner`,
  `axiom:concurrency-auditor`, `axiom:swiftui-architecture-auditor`, etc.
- The full **App Review requirements table** (4.8 login services, account
  deletion, age rating, EU DSA, ATT, third-party-AI disclosure …) lives in
  `~/.claude/skills/ship/references/ios-release.md` — consult it while
  DESIGNING features, not just when shipping.

## Store assets & ASO (also pre-ship work)

| Task | Skill |
|---|---|
| Screenshots (generate/frame/upload) | `app-store-screenshots`, `asc-shots-pipeline` |
| Keywords/title/listing optimization | `aso-audit`, `app-store-optimization` (all-ios-skills) |
| Metadata sync / localization | `asc-metadata-sync`, `asc-localize-metadata` |
| ASC CLI anything | `asc-cli-usage` (auth: key R7RQM8U3QY, issuer in ~/.asc/config.json) |

## Rust-core gate (before any release handoff)

`cargo clippy --all-targets -- -D warnings` + FULL `cargo test --no-fail-fast`
+ `cargo build --release --lib` in the crate dir. Bare clippy/test miss
test/bin targets (Goose 2026-06: 45 hidden warnings + a non-compiling test
target). FFI boundary must `catch_unwind`. A tee'd pipeline's exit code is
the tee — grep the log for `error[`/`FAILED`.

## Hard-won traps (verified 2026-06-12, AIVA — generalize)

1. **WKWebView clip bug**: composited `<img>` (filter/drop-shadow) escapes
   ancestor `border-radius`+`overflow:hidden`; computed styles look perfect,
   paint is wrong. Fix: radius the img itself.
2. **In-app-browser detectors flag your own shell**:
   `iPhone.*AppleWebKit(?!.*Safari)` UA sniffing matches Capacitor's webview —
   short-circuit on `window.Capacitor?.isNativePlatform?.()`.
3. **clerk-js rejects custom schemes** (`"capacitor:" is not a valid
   protocol` → bounces to "/"): ClerkProvider `allowedRedirectProtocols:
   ["capacitor:"]` (native only) + instance `allowed_origins` +=
   `capacitor://localhost` via the pre-authenticated `clerk` CLI (never ask
   for sk_live — `clerk doctor` first). Least-privilege: only add origins
   for platforms that EXIST (no `https://localhost` until Android ships).
4. **Clerk social sign-in in a Capacitor webview — the ONLY working answer is
   clerk-js's WEB OAuth (`oauth_apple`), NOT native token (`oauth_token_apple`).**
   (Proven 2026-06-13, improvebayarea, after a multi-hour dead end — read this
   before touching social login so you don't repeat it.)
   - **Native token sign-in via clerk-js is ARCHITECTURALLY IMPOSSIBLE in a
     webview. Do not attempt it.** `oauth_token_apple`/`google_one_tap` are
     Clerk's **Native API** (Expo/React-Native SDK only). The Native API
     requires `_is_native=1` + an `Authorization` Bearer and **forbids the
     `Origin` header** (FAPI error `origin_authorization_headers_conflict`). A
     webview's cross-origin fetch to `clerk.<domain>` is **forced by the browser
     to send `Origin`** — a [Fetch-spec forbidden header](https://developer.mozilla.org/en-US/docs/Glossary/Forbidden_header_name)
     JS can't remove — so the conflict is unavoidable. clerk-js (the browser SDK
     in the webview) also ships **zero** `_is_native` support (grep the bundle).
     Registering the Native Application **and** enabling the "Native API" toggle
     in Clerk does NOT fix it (both needed for Expo, neither defeats the Origin
     wall). The dead-end symptom staircase: button hidden →
     `authorization_invalid` → `native_api_disabled` → `origin_authorization_headers_conflict`.
   - **THE FIX (web-class, zero new build):** Apple's web SIWA **does** run
     inside WKWebView (unlike Google). Un-hide clerk-js's **web** Apple button
     in the shell and keep the whole round-trip in-webview via capacitor.config
     `allowNavigation: ['appleid.apple.com','idmsa.apple.com']`. Google web OAuth
     **is** blocked in webviews (`disallowed_useragent`) — hide it in-app
     (`html[data-iba-native-shell] .cl-socialButtonsBlockButton__google{display:none!important}`)
     or send it to a system browser. For a **remote-URL** Capacitor app this is a
     pure web change (CSS un-hide + don't offer the native button) deployed via
     the Worker — NO `@capgo` plugin, NO `APPLE_ID_AUTH` capability, NO
     entitlement, NO Info.plist, NO native build. (improvebayarea fix: commit
     `68a2994`, `src/ui.ts`.)
   - **⚠ CRITICAL — the web-Apple fix ONLY works on a REMOTE-URL shell. A
     BUNDLED shell (`webDir` + local bundle, origin `capacitor://localhost`)
     gets a NEW wall: clerk-js computes the Apple `redirect_url` from the
     origin → `capacitor://…` → Clerk's web FAPI rejects it
     (`invalid_url_scheme: "Please provide a URL with … https, http"`).** No
     clerk-js option (`allowedRedirectProtocols` included) makes the FAPI
     accept a `capacitor:` redirect for the web oauth flow. **FIX: convert the
     app to remote-URL** — `server.url = "https://<yoursite>"` in
     `capacitor.config.ts` so the webview origin IS the real https site (what
     improvebayarea always was). Three coupled changes (do ALL THREE in one
     native build): (a) `server.url`; (b) **remove `CapacitorHttp`** — same-
     origin now, so fetch + the oauth navigation share ONE webview cookie jar
     (native transport splits the jar and re-breaks the post-oauth session
     read); (c) **`CapacitorUpdater.autoUpdate:false`** — a remote-URL app must
     never hot-swap a local bundle, which would clobber `server.url` and revert
     the origin. Consequence: every Worker deploy IS the app instantly (Capgo
     OTA retires); add a small offline fallback if you need one. AIVA proof:
     bundled build #6 → `invalid_url_scheme` on device; remote-URL build #7 →
     Apple sign-in works (commit `cb2444a`, `~/AIVA-Frontend/capacitor.config.ts`).
     The earlier "B1 web-class, zero new build" applies to apps ALREADY on
     remote-URL; a bundled app needs this native conversion first.
   - **If you truly need a native-feel sheet** (not the in-webview page): the
     only supported path is **system browser** — `@capacitor/browser`
     (= `ASWebAuthenticationSession`, Apple-blessed) + `@capacitor/app`'s
     `appUrlOpen` to catch a custom-scheme redirect +
     `signIn.authenticateWithRedirect({strategy:'oauth_apple', redirectUrl:'<scheme>://…'})`
     + clerk-js `allowedRedirectProtocols:['<scheme>:']` + Info.plist URL scheme.
     THAT is a NATIVE-class change → /ship build. The true OS Apple sheet
     (`ASAuthorizationController` → native token) is **off the table** for any
     webview app.
   - **Decisive 30-second probe BEFORE writing any code** (confirms the wall):
     `curl -X POST 'https://clerk.<domain>/v1/client/sign_ins?_is_native=1' -H 'Origin: https://<site>' -H 'Authorization: x' -d 'strategy=oauth_token_apple&token=x'`
     → `origin_authorization_headers_conflict` = native-in-webview is dead, go web.
   - Hiding social entirely in-app also satisfies Guideline 4.8 (no third-party
     login at all) — a valid instant unblock if web Apple ever regresses.
5. **capgo-updater rolls back without `notifyAppReady()`** (~10s); pending
   OTA bundles install on background→foreground, not force-kill.
6. **SPM targets reject CLI signing overrides** — Manual signing + profile
   go ON THE APP TARGET in pbxproj, never xcodebuild args.
7. **Webview a11y tree is flat** — axe coordinates, not elementRefs.
8. **Content under the status bar?** Don't fight per-widget safe-area CSS
   — set StatusBar `overlaysWebView: false` (+ style/backgroundColor) in
   capacitor.config.ts so the WEBVIEW sits below the bar (iOS support
   verified in the installed plugin's StatusBarPlugin.swift). Third-party
   widget stylesheets load after yours and win every cascade war; the
   `contentInset` option only adjusts scroll insets, not fixed elements.
   NATIVE-class change → new shell build.
9. **OTA bundle masks local dev builds**: once the app has applied a
   downloaded bundle, `cap sync` + rebuild still serves the DOWNLOADED
   bundle. `xcrun simctl uninstall` (or CapacitorUpdater.reset()) before
   judging local web changes in the shell.
10. **Installed-source ground truth** (mandatory, see
   `~/.claude/skills/shared/installed-source-ground-truth.md`): read
   node_modules types/JSDoc + the plugin's Swift/Kotlin source before
   trusting any config option or "platform-only" claim.
11. **`asc builds latest` doesn't exist** — `asc builds info --app ID --latest`.
12. **Passkey (WebAuthn) registration "cancelled or timed out" in the webview** =
   the iOS app has no relying-party↔app binding, so the passkey sheet has nothing
   to attach the credential to and aborts. SAME root-cause family as trap #4 (a
   credential ceremony in a remote-URL WKWebView needs an explicit binding; the
   error is always generic and non-diagnostic). Fix = BOTH halves: (a) serve
   `/.well-known/apple-app-site-association` (application/json, NO redirect)
   listing `<TEAMID>.<bundleID>` under `webcredentials.apps`; (b) add
   `com.apple.developer.associated-domains = ["webcredentials:<domain>"]` to the
   app entitlements + enable the **Associated Domains** capability on the bundle id
   (`asc bundle-ids capabilities …`, regenerates the provisioning profile) + a new
   build. NATIVE-class. Reference: improvebayarea `dadfdf3` (AASA 404 + no
   entitlement → passkeys dead). The cross-file App-ID drift test
   (`src/aasa_passkey.test.ts`) locks AASA↔signing-identity so it can't silently
   re-break.

### Credential-ceremony-in-a-remote-URL-webview binding matrix (probe FIRST)

The recurring lesson across traps #3, #4, #12: **any credential ceremony run inside
a Capacitor WKWebView fails with a GENERIC error until the right app↔domain/origin
binding exists. The error never names the missing binding.** Before debugging the
code, run the cheap probe for the ceremony and confirm the binding is present:

| Ceremony | Generic error you'll see | Missing binding | 30-sec probe |
|---|---|---|---|
| Social OAuth (Apple) | `authorization_invalid` / Safari downloads JSON | Apple auth host not in `allowNavigation` (callback strands in external Safari, splits the cookie jar) | `grep allowNavigation capacitor.config.ts` |
| Social OAuth (Google) | `disallowed_useragent` | none — Google **blocks** OAuth in webviews by policy; hide the button in-app | n/a (architectural; don't chase it) |
| clerk-js custom scheme | `"capacitor:" is not a valid protocol` → bounces to `/` | `allowedRedirectProtocols`/instance `allowed_origins` missing the scheme | `clerk doctor` + grep ClerkProvider |
| Passkey / WebAuthn | "registration was **cancelled or timed out**" | AASA file (`webcredentials`) + Associated Domains entitlement | `curl -sI <domain>/.well-known/apple-app-site-association` + `grep webcredentials ios/**/*.entitlements` |

If the probe shows the binding is absent, that IS the root cause — stop, add the
binding (or, for Google, hide the affordance), don't debug the JS ceremony. This is
the premise-check gate (`~/.claude/skills/shared/premise-check.md`) specialized to
in-webview auth.

## Quality gates before handing to /ship

- Native: clean sim build + greenlight trending to 0 criticals + privacy
  manifest present.
- Capacitor: the web repo's own gates (`npm run check`, targeted vitest —
  NEVER unscoped `vitest run`; `pkill -f "vitest.*forks"` after).
- Rust-core: the gate above.

## Handoff

User wants it on a phone / in review / users updated → **invoke /ship**
(its iOS phase covers: scope detection web-vs-native, OTA publish, greenlight
gate, sign/archive/export, TestFlight distribution incl. the
build-to-group assignment that actually triggers invites, App Store submit).
Don't re-implement shipping here.
