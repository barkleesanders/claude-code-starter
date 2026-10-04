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
| `ios/`, `capacitor.config.ts`, `@capacitor*`/`@capgo*` deps, Swift sources, entitlements, Info.plist | **Native** | 4.7.0a authority → 4.7.0b feasibility → 4.7.2 approved channel; OTA only where present and authorized |
| Both | **Mixed** | 4.7.0a authority → 4.7.0b feasibility → Native FIRST, then authorized web+OTA |

These OTA paths apply to packaged web assets with an actual updater. Inspect the
Capacitor config and publisher first. A remote-URL WKWebView loads its configured
server; a public server deploy can affect existing app installations and website
users immediately. **TestFlight only limits native distribution.** Determine web
deployment authority from the full task: do not assume the native channel choice
either grants or revokes a separately authorized website release. If the user
requires all changes to stay beta-only, a shared production server is not beta
isolation. Use an existing beta environment only when authorized and its app identity,
authentication, and native-domain bindings are verified. Do not silently create
a new environment or change the architecture to get around a release blocker.

## 4.7.0a — Release-channel authority (before native build or upload)

Recover the user's explicit channel choice from the ongoing task before asking.
Record the app/bundle ID, channel, tester audience, and approval evidence in the
existing bead. A choice already supplied in a message is the answer. It remains
valid through scoped fixes, retries, and context recovery until the user changes
it; a fresh unrelated release cannot inherit consent from an old memory entry.

If no channel was specified, ask once — scoped explicitly to NATIVE distribution:
"Native channel for this release: (a) TestFlight (internal testers), (b) TestFlight
plus App Store submission, (c) hold native. The web/Worker deploy proceeds under
the original ship request either way." Never label an option "TestFlight only":
on 2026-09-09 that label was recorded as the whole-release approval, relayed as
"TestFlight-only approval accepted", and the web deploy the user had requested was
deferred to a follow-up bead instead of shipped (SKILL.md SCOPE HANDOFF RULE).
Record the answer as `native_channel:` in the bead, next to the `scope:` line
written before the question. Continue permitted read-only preparation while that
decision is pending. An explicit request to build locally
authorizes the local build without distribution approval.

Hard rules:
- **NEVER run 4.7.2 step 6 (App Store submit) unless the user explicitly
  authorized App Store submission for this ongoing release.** Bare `/ship`
  is not App Store consent; “TestFlight only” excludes App Store submission
  and nothing else — it does not touch the web/Worker or OTA surfaces.
- When TestFlight is already authorized, proceed through build and distribution
  without another confirmation. Use the established internal tester group unless
  the user specified another audience. Public links/external beta review require
  authorization for that wider audience.
- Web-only releases use the approved web/OTA audience; they do not require a
  native-channel question. Preserve any explicit restriction on that audience.
- Approval does not override session restrictions. Report an exact restriction
  once, keep the original approval, and resume dependent work only when the
  blocking condition changes. Never ask the user to repeat an already accepted
  approval as a proposed remedy for a higher-priority prohibition.

## 4.7.0b — Native feasibility (before lengthy release gates)

1. Inspect the actual native project location, Xcode/SDK, distribution signing,
   ASC app identity, and existing build numbers. Check tool availability without
   printing credentials. Reuse valid signing assets; don't recreate them by default.
2. Read package manifests and lockfiles, including native/transitive dependencies
   added by a JavaScript plugin. Compare required packages with the actual local
   checkouts/artifacts. `cap sync ios`, a lockfile, a JS build, or a successful
   privacy preflight does not prove that the native dependency graph can compile.
3. Apply RELEASE AUTHORITY to the operations the resolver actually performs.
   A missing workspace remote or a no-publication/no-sync rule is not a
   dependency-download prohibition. For an authorized build, retrieve declared
   SwiftPM packages normally when no active rule prohibits retrieval. Record the
   exact instruction and scope before claiming a developer rule blocks fetching.
   An explicit restriction on all remote Git operations also covers a resolver
   that fetches Git remotes.
   Do not broaden a Git-only restriction to all provider APIs, nor bypass an
   actual prohibition with source archives, another transport, or another host.
4. When retrieval is allowed, resolve dependencies and fix resolution errors
   before long gates. When retrieval is prohibited, inspect existing caches first;
   do not launch a resolver that might fetch. Read the installed tool's flag help:
   `-disableAutomaticPackageResolution` and `-skipPackageUpdates` are not proof of
   offline operation. Bound and name cache searches; don't claim universal absence.
5. If a required package is unavailable under the active restrictions, record the
   package/version, manifest path, searched locations, exact restriction, candidate
   SHA, and accepted channel. Finish independent authorized preparation. Leave the
   archive/upload and physical-device checks open; do not substitute a public web
   deploy, a stale IPA, or a feature downgrade for the requested native release.
6. **iOS 27 scene-lifecycle gate (BLOCKING, before any archive):**
   `/bin/bash ~/.claude/skills/ship/tools/ios-scene-lifecycle-check.sh <repo>` must exit 0.
   Exit 1 = the app will crash AT LAUNCH on iOS 27 (no UIScene adoption) or will silently
   lose OAuth/universal-link returns (no scene URL forwarding). Exit 2 = unmeasured — not a
   pass. This is what shipped ImproveBayArea build 14 as a launch crash on 2026-09-28: it was
   VALID in TestFlight and launched on the iOS 26.5 simulator. Fix recipe:
   `~/.claude/skills/shared/ios-app-dev-release-traps.md` §1–2.
7. **ASC + signing plumbing:** prefix every `asc` command with `ASC_BYPASS_KEYCHAIN=1` (creds
   in `~/.asc/config.json`; the login-keychain prompt otherwise blocks unattended runs — never
   type that password). Search BOTH profile dirs before declaring a profile missing:
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (Xcode 27) and
   `~/Library/MobileDevice/Provisioning Profiles/`.

On a continuation, recheck the specific blocker first. Keep still-valid gate
results attached to their candidate SHA and inputs; rerun invalidated checks and
refresh ASC state before upload. Do not restart every completed gate just because
the user repeated `/ship`.

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

1. **Version/build identity**: choose an unused higher `CURRENT_PROJECT_VERSION`
   from live ASC state before archiving. Keep `MARKETING_VERSION` for another
   TestFlight build of the same app version; increment it when creating a new app
   version. Follow the repo's actual web build and Capacitor sync commands first.
   [Apple version/build guidance](https://help.apple.com/xcode/mac/current/en.lproj/devba7f53ad4.html)
   (checked 2026-09-10).
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
4. **Archive + export + binary scan** — archive only from a COMMITTED, pushed SHA (build 15
   was once archived from an uncommitted tree); record that SHA next to the ASC build number:
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
   Capture the returned build ID and verify its app, version, build number, and
   upload time against the exported IPA. Use that exact ID for polling and group
   assignment when supported by the installed CLI. If only `--latest` is available,
   recheck identity immediately before mutation and stop on a mismatch; another
   release may have uploaded a different build. Never expire existing builds as
   incidental cleanup for this release.
   **Testers are only notified when a PROCESSED build is ASSIGNED to their
   group** — uploading alone sends nothing. Verify distribution view shows
   `internalBuildState: IN_BETA_TESTING`. New app records can't be created
   via the API — use the logged-in ASC web session (Apps → New App; bundle
   ID must be registered first via `asc bundle-ids create`).
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
5c. **Physical iOS-27 launch + acceptance (BLOCKING before "shipped"/"fixed")**: install the
   processed build on the physical iPhone (TestFlight Update, or drive TestFlight with
   controlphone), then prove it launched on the newest iOS — not the simulator you happen to
   have:
   ```bash
   xcrun devicectl device info apps --device <UDID> | grep <bundle>    # new build number present
   xcrun devicectl device info processes --device <UDID> | grep '/App.app/App'   # running PID
   xcrun devicectl device info crashes --device <UDID>                 # no new .ips
   ~/projects/iphonectl/bin/controlphone screenshot launched.png        # rendered UI
   ```
   For UI fixes, run the change's acceptance on the device with controlphone
   (`iphonectl-setup wda` once, then `controlphone tap/swipe/screenshot`). Native-modal /
   safe-area fixes must open AND cancel the iOS full-screen modal (file input → Take Photo),
   then scroll and open every top-nav menu. Device-driving traps (mobile-mcp times out on
   iOS 27, stale tunnel, ports 8100/8101): `shared/ios-app-dev-release-traps.md` §4.
   If the phone is unavailable, report the release as UPLOADED, not verified.
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

- BLOCK distribution without the 4.7.0a channel authorization. Reuse an explicit
  answer already given for this ongoing task. BLOCK App Store submission (4.7.2
  step 6) unless that answer expressly includes App Store submission.
- BLOCK if greenlight preflight has CRITICALs (after false-positive triage)
  or the IPA scan is not GREENLIT.
- BLOCK if PrivacyInfo.xcprivacy is missing or contradicts actual data
  collection.
- BLOCK OTA publish when native-affecting files changed (guard) — native
  release first.
- BLOCK "shipped to TestFlight" claims until `asc builds info` shows VALID
  AND the build is assigned to a group (IN_BETA_TESTING) — upload alone is
  not distribution.
- BLOCK archive/upload when `ios-scene-lifecycle-check.sh` exits non-zero (1 = launch
  crash on iOS 27 or dead OAuth return; 2 = unmeasured). Exit 4 (no iOS project) is only
  acceptable when the release has no native build.
- BLOCK "shipped"/"fixed" claims for a native build until step 5c shows the new build
  running on a physical device on the newest iOS with no new crash report. A simulator on
  an older runtime is not launch proof.
- BLOCK native upload with a duplicate build identity; increment the build number
  for another TestFlight build. A marketing-version bump alone is not the rule.
- Auth ground truth: asc key R7RQM8U3QY + issuer in `~/.asc/config.json`;
  Clerk origin changes via the pre-authenticated `clerk` CLI (`clerk doctor`
  first — never ask for sk_live). Least-privilege on Clerk
  `allowed_origins`: only origins for platforms that exist.
