# Phase A (Wrap) + Phase B (Native features)

Goal: turn the existing web app into a Capacitor iOS project that builds, and add
the native capabilities that clear Apple's minimum-functionality bar.

## Pull first
- Load the **`webapp-to-capacitor`** Capgo skill — the canonical migration guide
  (static-build readiness, safe areas, permissions, offline, account deletion,
  billing risk, thin-WebView rejection avoidance). Start here.
- For specific plugins/APIs, load `capacitor-features` / `capacitor-ui` skills and
  fetch live docs with `context7` (`resolve-library-id` → `query-docs` for `@capacitor/*`).

## Phase A — Wrap

> ⚠️ **STEP 0 — Static vs SSR (decide this BEFORE anything else).** Capacitor's bundled
> mode needs a folder of **static** built assets (`webDir`). **improvebayarea is Hono SSR
> on a Cloudflare Worker** (`main = src/index.ts`, deps `hono`+`jose`; `public/` holds only
> OG/favicons) — it renders HTML server-side and emits **no static `dist/` of the app**.
> So `--web-dir=dist` does NOT apply as-is. Verify per project: `grep main wrangler.*` +
> check for a client build script. An SSR Worker has three honest options:
>
> | Option | What it takes | Trade-off |
> |---|---|---|
> | **Remote-URL mode** (realistic default for SSR) | `server.url` → the live Worker | No static export needed; **but** higher Apple-4.2 scrutiny (must pair with real native features), needs network (no offline), and Capgo bundle-OTA does NOT apply — web updates come from deploying the Worker. |
> | **Build a static client bundle** | Add a static SPA/client build the Worker doesn't currently produce | Real front-end work; then bundled+Capgo path opens up (offline + OTA). |
> | **Pre-render/snapshot routes** | Snapshot rendered HTML to a static dir | Brittle for dynamic routes; partial. |
>
> Pick the mode WITH the user — it changes Phases C/F. For improvebayarea today,
> remote-URL + native features is the path of least resistance; bundled+Capgo requires
> building a static client first.

1. **Scaffold** (drive via `awesome-ionic-mcp`, or run directly). `--web-dir` only matters
   for bundled mode; for remote-URL mode you set `server.url` in `capacitor.config` instead:
   ```bash
   npm i @capacitor/core @capacitor/cli
   npx cap init "Improve Bay Area" com.improvebayarea.app
   npm i @capacitor/ios && npx cap add ios
   ```
2. **Set the content mode** chosen in Step 0:
   - **Remote-URL:** `server: { url: "https://improvebayarea.com", cleartext: false }` in
     `capacitor.config.ts`. Web updates = deploy the Worker (no Capgo bundle push). Pair
     with Phase B native features so it's not a bare wrapper (Apple 4.2).
   - **Bundled (only if a static client build exists):** point `webDir` at it; then Capgo
     OTA (Phase C) applies for web-layer pushes + offline.
   - In BOTH modes the website stays fully live for browser users — the app is an added channel.
4. **Sync native project:**
   ```bash
   npx cap sync ios     # runs `pod install` (CocoaPods 1.16.2 is installed)
   ```
5. **Scripted native config with Trapeze** (instead of hand-editing in Xcode) — version,
   bundle id, Info.plist purpose strings, entitlements from a YAML file:
   ```bash
   npx @trapezedev/configure --help
   ```

## Phase B — Native features (clears Apple 4.2)

A wrapper with no native capability is rejected. Add the features that make it an app
AND match improvebayarea's purpose (photo + GPS at the point of an issue report):

| Feature | Plugin | Info.plist purpose string (required) |
|---|---|---|
| Camera | `@capacitor/camera` | `NSCameraUsageDescription` |
| Geolocation | `@capacitor/geolocation` | `NSLocationWhenInUseUsageDescription` |
| Push | `@capacitor/push-notifications` | (capability + APNs setup) |

```bash
npm i @capacitor/camera @capacitor/geolocation @capacitor/push-notifications
npx cap sync ios
```
- Add each purpose string (via Trapeze YAML or Info.plist). Missing purpose strings = a
  guaranteed greenlight CRITICAL and an Apple rejection.
- Wire the JS side in the web app so the report flow calls Camera + Geolocation; degrade
  gracefully to web APIs when running in a browser (same codebase, two runtimes).
- **Adding any of these is a NATIVE-shell change** (new permission) → it goes through
  GATE 2 + `/ios-ship`, not OTA.

## Done-when
- `npx cap sync ios` succeeds (pods installed), project opens, camera+geolocation+push
  wired with purpose strings. Proceed to Phase C (OTA) then Phase D (build/test/gate).
