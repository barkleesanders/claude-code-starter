# Phase 4.7 — iOS App Surface Release (formerly /ios-ship + /app-ship)

Runs when the repo ships an iOS surface. **Detection:** repo contains
`ios/` + `capacitor.config.ts` (Capacitor web-wrap), or `*.xcodeproj` /
`*.xcworkspace` with an app target, or `app.json` with Expo. Skip for pure
web/CLI repos. Development work belongs to **/ios** — this phase only
releases.

## 4.7.0 — Scope detection (which release path)

| Changeset touches | Class | Path |
|---|---|---|
| Only web code (`src/`, `public/`, CSS, copy) in a Capacitor repo | **Web** | 4.7.1 OTA only — NO App Store release |
| `ios/`, `capacitor.config.ts`, `@capacitor*`/`@capgo*` deps, Swift sources, entitlements, Info.plist | **Native** | 4.7.0a ask → 4.7.2 TestFlight (and App Store ONLY if user chose it), then OTA republish with bumped MIN_SHELL_VERSION |
| Both | **Mixed** | 4.7.0a ask → Native FIRST, then web+OTA |

## 4.7.0a — Release-channel ask gate (MANDATORY before any native build — user rule 2026-06-12)

When scope detection lands on **Native** or **Mixed** (i.e. a new shell
build/archive is warranted), **STOP and ASK the user which channel** via
AskUserQuestion BEFORE archiving anything:

1. **TestFlight only** (safe default — internal testers get the build)
2. **TestFlight + App Store submission** (full App Review)
3. **Neither** (build locally, hold release)

Hard rules:
- **NEVER run 4.7.2 step 6 (App Store submit) unless the user explicitly
  chose option 2 in THIS session** — "ship it", "/ship", or a prior session's
  approval do NOT count as App Store consent. App Review submissions are
  outward, slow to reverse (developer-reject + resubmit), and burn review
  goodwill.
- TestFlight distribution also goes through this ask — don't auto-upload a
  native build just because the changeset is native-class.
- **Web-class changes skip this gate entirely**: OTA publish is automatic
  (4.7.1), no native build occurs, nothing reaches App Review — that's the
  whole point of the OTA architecture. State in the report that the app
  updated via OTA with no TestFlight/App Store action.
- If the user pre-specified the channel in their /ship invocation (e.g.
  "/ship to TestFlight", "ship and submit to the App Store"), that counts as
  the answer — don't re-ask.

## 4.7.1 — Capacitor OTA publish (web-class; the AIVA pattern)

**Web first, then app, one build.** The same `dist/client` the web deploy
shipped gets zipped and published to the self-hosted capgo-updater backend.

For AIVA this is automatic: `./ship.sh` already runs
`scripts/publish-ota-bundle.sh` after `wrangler deploy` (zip → R2
`app-bundles/` → KV `app_updates:channel:production` → cache-busted live
verify). Project doc: `~/AIVA-Frontend/docs/mobile-ota.md`.

Gates (BLOCKING):
- The publisher's git-diff guard REFUSES the OTA push if native-affecting
  files changed since the last published bundle (`OTA_FORCE=1` only after a
  native release shipped + `MIN_SHELL_VERSION` bumped).
- Post-publish closed loop: `curl -s "https://<host>/api/app/updates?cb=$(date +%s)"`
  must report the new version; sim relaunch ×2 (download on 1st launch,
  apply on background→foreground or 2nd launch) shows the change.
- `notifyAppReady()` must remain in the boot path — without it every OTA
  bundle auto-rolls back ~10s after launch.
- Universal apps (`TARGETED_DEVICE_FAMILY = "1,2"`): when the changeset
  touches layout/breakpoints, add ONE iPad sim screenshot to the verify
  loop (iPad Pro 13"; same install+launch+screenshot flow) — App Review
  tests on iPad and device-family support is permanent post-release
  (QA1623), so tablet rendering is a forever review surface.
- Rollback = repoint the KV record at the previous bundle (zips are
  immutable in R2).

## 4.7.2 — Native release (TestFlight / App Store)

1. **Version bump**: `MARKETING_VERSION` (+ `CURRENT_PROJECT_VERSION`) in the
   pbxproj. Capacitor: `npm run build && npx cap sync ios` first.
2. **Compliance gate (BLOCKING)**: `greenlight preflight .` in the iOS dir →
   0 CRITICALs. Known false positives: pk_live publishable keys (public by
   design); minified vendor strings faking "tracking SDK" hits (DOMPurify's
   SVG-attr allowlist contains "amplitude") — verify with targeted greps,
   document the triage. Privacy manifest `PrivacyInfo.xcprivacy` must exist
   (upload gate since May 2024; Capacitor baseline: UserDefaults CA92.1 +
   FileTimestamp C617.1) and match reality.
3. **Signing** (verified flow 2026-06-12): App Store profile via
   `asc profiles create --profile-type IOS_APP_STORE --bundle <BUNDLE_REG_ID>
   --certificate <DIST_CERT_ID>`; install the .mobileprovision to
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Set Manual
   signing + cert + profile **ON THE APP TARGET ONLY in pbxproj** — CLI
   `PROVISIONING_PROFILE_SPECIFIER` overrides break SPM package targets
   ("does not support provisioning profiles"). "Your team has no devices"
   on archive = automatic signing minting a DEV profile; switch to the
   manual distribution setup above. `ITSAppUsesNonExemptEncryption=false`
   in Info.plist pre-answers export compliance (HTTPS-only apps).
4. **Archive + export + binary scan**:
   ```bash
   xcodebuild archive -project <proj> -scheme <scheme> -configuration Release \
     -archivePath /tmp/App.xcarchive -destination "generic/platform=iOS"
   xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
     -exportPath /tmp/Export -exportOptionsPlist <ExportOptions.plist>
   greenlight ipa /tmp/Export/*.ipa     # BLOCKING: GREENLIT required
   ```
   ExportOptions: method `app-store-connect`, teamID, signingStyle manual,
   provisioningProfiles map.
5. **Upload + TestFlight distribution**:
   ```bash
   asc builds upload --app <APP_ID> --ipa /tmp/Export/*.ipa
   asc builds info --app <APP_ID> --latest          # poll until VALID
   asc builds add-groups --app <APP_ID> --latest --group <GROUP_ID>
   ```
   **Testers are only notified when a PROCESSED build is ASSIGNED to their
   group** — uploading alone sends nothing. Verify distribution view shows
   `internalBuildState: IN_BETA_TESTING`. New app records can't be created
   via the API — use the logged-in ASC web session (Apps → New App; bundle
   ID must be registered first via `asc bundle-ids create`). Expire stale
   apps' builds: `asc builds expire --app <ID> --latest --confirm`.
   **Public TestFlight link** (share with anyone, no per-tester approval):
   create an EXTERNAL group (`asc testflight groups create` without
   `--internal`), then PATCH `publicLinkEnabled:true` (+`publicLinkLimit`)
   on `/v1/betaGroups/<id>` — link comes back immediately, but it is INERT
   until a build is added to the external group, and that add triggers
   Apple's TestFlight **beta review** (lighter + separate from App Store
   review, ~<24h) — treat it as an outward submission needing user consent.
   Internal groups: no review, but testers must be ASC team members (≤100).
5b. **Listing prep via API (no web UI needed for most of it)** — verified
   2026-06-12, AIVA: version metadata via `asc localizations update`
   (description/keywords/urls/promo); subtitle + privacyPolicyUrl via
   `asc metadata pull` → edit `app-info/<locale>.json` → `asc metadata push`;
   categories via raw PATCH `/v1/appInfos/<id>` relationships; age rating via
   `asc age-rating edit --all-none`; content rights via
   `asc apps content-rights edit`; screenshots via `asc screenshots upload
   --version-localization <id> --device-type IPHONE_69|IPAD_PRO_3GEN_129`
   (6.9" = 1320×2868 stored under APP_IPHONE_67); availability via POST
   `/v2/appAvailabilities` — included territoryAvailabilities MUST use
   `${local-id}` placeholder ids, not territory codes (409 otherwise);
   review details via POST `/v1/appStoreReviewDetails` — `contactPhone` is
   REQUIRED (never fabricate; get from user). Mint API JWTs with openssl
   only (ES256) — see `~/AIVA-Frontend/scripts/asc-prep.sh` (`status` audit
   + guarded `submit`). Universal apps (`TARGETED_DEVICE_FAMILY = "1,2"`)
   REQUIRE 13" iPad screenshots (2064×2752). App Privacy nutrition labels
   + EU DSA trader status have NO public API — ASC web UI only.
6. **App Store submit** (when going past TestFlight):
   `asc publish appstore --app <ID> --ipa <ipa> --version <v> --wait --submit
   --confirm`, or manual versions/attach-build/submit flow. Monitor:
   `asc submit status --version-id <ID>`.
7. **Post-native OTA resync (Capacitor)**: once the new shell is live,
   `MIN_SHELL_VERSION=<new shell version> ./scripts/publish-ota-bundle.sh`
   so old shells get `shell_update_required` instead of an incompatible
   bundle.

## 4.7.3 — App Review approval requirements (live-verified 2026-06-12; re-verify if >14 days)

⚠ = NOT checked by greenlight; verify via asc/ASC web.

| Requirement | Guideline | Key point |
|---|---|---|
| Login services | 4.8 | Third-party social login ⇒ must ALSO offer a privacy-compliant alternative (SIWA qualifies; no longer required by name). Apps with ONLY their own account system are exempt — hiding social login in-app keeps you exempt |
| Account deletion | 5.1.1(v) | In-app initiable Delete Account for any app with account creation |
| Privacy policy URL + nutrition labels | 1.5 / ASC gate | Required to submit; set in ASC App Privacy |
| Privacy manifests + Required Reason APIs | upload gate | PrivacyInfo.xcprivacy (greenlight checks) |
| ⚠ SDK signatures | upload gate | Binary deps from Apple's ~100-SDK list must be signed |
| ATT | 5.1.2(i) | Only if actually tracking (cross-company ad linking) |
| ⚠ Third-party AI disclosure (Nov 2025) | 5.1.2(i) | Disclose + get permission before sending personal data to third-party AI APIs |
| Purpose strings | 5.1.1(i) | Specific NS*UsageDescription per protected resource |
| ⚠ EU DSA trader status | ASC gate | Without it: EU updates blocked / apps removed |
| Encryption export | ASC gate | ITSAppUsesNonExemptEncryption=false for HTTPS-only |
| Minimum functionality | 4.2 | Webview apps need native value (haptics, push, offline shell, share) |
| Metadata/screenshots | 2.3.x | Screenshots show app IN USE; review notes must be specific |
| Demo account | 2.1(a) | Login apps need working demo creds in review notes |
| ⚠ Age rating (2026 system) | 2.3.6 | New questionnaire answers required since 2026-01-31 or updates blocked |
| IAP | 3.1.1 | Digital goods through IAP; ⚠ US storefront now allows external purchase links without entitlement (post-Epic) — other storefronts still need the entitlement |
| ⚠ Accessibility labels / clone branding / mini-apps | ASC / 4.1(c) / 4.7 | Check before submit |

Stale-tooling notes: greenlight's 4.8 text ("SIWA mandatory") and
external-payment rule (US change) are stale; greenlight checks NONE of the ⚠
rows.

## Blocking rules for this phase

- BLOCK any native build/upload until the 4.7.0a release-channel ask is
  answered; BLOCK App Store submission (4.7.2 step 6) without an explicit
  same-session "App Store" answer from the user.
- BLOCK if greenlight preflight has CRITICALs (after false-positive triage)
  or the IPA scan is not GREENLIT.
- BLOCK if PrivacyInfo.xcprivacy is missing or contradicts actual data
  collection.
- BLOCK OTA publish when native-affecting files changed (guard) — native
  release first.
- BLOCK "shipped to TestFlight" claims until `asc builds info` shows VALID
  AND the build is assigned to a group (IN_BETA_TESTING) — upload alone is
  not distribution.
- BLOCK native release without bumping MARKETING_VERSION (duplicate build
  numbers are rejected at upload).
- Auth ground truth: asc key R7RQM8U3QY + issuer in `~/.asc/config.json`;
  Clerk origin changes via the pre-authenticated `clerk` CLI (`clerk doctor`
  first — never ask for sk_live). Least-privilege on Clerk
  `allowed_origins`: only origins for platforms that exist.
