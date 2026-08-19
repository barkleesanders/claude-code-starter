# iOS App Store Submission — External Tools & Patterns

Reference companions to the existing `ios-ship` toolchain (`asc`, `greenlight`, `xcodebuild`, `agent-browser`, `sosumi MCP`, `xcode-test`).

Captured from Notion link-inbox triage on 2026-04-28. None of these are installed automatically — they're documented here so you know they exist and can pull them in if `ios-ship`'s built-in tools aren't enough.

## Alternative App Store Connect tools

| Tool | URL | Compared to your existing `asc` CLI |
|---|---|---|
| **Helm for App Store Connect** | https://helm-app.com/ | Native macOS app — adds metadata/localization/ASO UI on top of ASC. Use when manual visual editing is faster than scripting. Your `asc` CLI handles everything programmatically already, so Helm is GUI-only nice-to-have. |
| **rudrank's ASC automation** | https://x.com/rudrank/status/2034897560549433680 | Different ASC CLI — same problem space as your `asc` (homebrew). Stay with `asc`; rudrank's is a duplicate. |

## Pre-submission scanners

| Tool | URL | Compared to your existing `greenlight` |
|---|---|---|
| **App Store Preflight** | https://x.com/truongduy2611/status/2034515540279267506 | Open-source scanner that checks 100+ Apple Review Guidelines before submission. Built on top of rudrank's `asc` CLI. Your `greenlight` (homebrew) covers the same ground. If you ever hit a rejection `greenlight` missed, evaluate switching. |

## App-onboarding skill (INSTALLED 2026-04-28)

| Skill | What it does |
|---|---|
| **`/app-onboarding-questionnaire`** | Generates a 14-screen psychological-framework onboarding flow based on Mob, Headspace, Noom, Cal AI patterns. Works on SwiftUI / React Native / Flutter / Expo. **This is different from the `onboarding-cro` skill** (which optimizes web post-signup activation). Use this for the in-app questionnaire flow new users see when they first open the app. |

```bash
# Already installed at ~/.claude/skills/app-onboarding-questionnaire/
# Trigger by saying: "build an onboarding flow" or "/app-onboarding-questionnaire"
```

## 7-minute App Store approval checklist (Wasim, March 2026)

Bookmark from a viral Reddit post: a dev got their iOS app approved in 7 minutes by getting these right *before* submission. Your `ios-ship` covers most of this; this is the audit list.

### App Store Connect setup
- [ ] Developer account fully verified (Apple takes 24-48hr)
- [ ] Tax + banking details 100% complete
- [ ] All paid-app agreements signed
- [ ] App ID matches bundle ID exactly (case-sensitive)
- [ ] Provisioning profiles current (not expired)

### Metadata (most-rejected)
- [ ] App name doesn't claim functionality the app doesn't have
- [ ] Description matches actual features (no future-promises)
- [ ] Screenshots from current build (not mockups, not stale)
- [ ] Keywords don't include competitor names or "best/free" superlatives
- [ ] Privacy policy URL is reachable + current
- [ ] Support URL is reachable
- [ ] Age rating questionnaire matches actual content

### Build hygiene
- [ ] Build runs without warnings on a clean device
- [ ] Crash on launch tested on lowest supported iOS version
- [ ] All `Info.plist` permissions have clear usage descriptions
- [ ] No private API usage (run `greenlight` to verify)
- [ ] Demo account credentials provided if app requires login

### Common rejection traps
- Sign-in with Apple required if you offer any third-party login
- Subscription terms must match StoreKit configuration
- Camera/photos/contacts: usage description must explain the *exact* user-facing benefit
- Background modes only for legitimate use cases — Apple checks
- IPv6-only network compatibility (App Store reviews on IPv6)

### Phased release
- [ ] Plan a phased rollout (default 7-day phased) so a regression doesn't hit 100% of users immediately

**Auto-check via existing tools:**
```bash
# Compliance scan (pre-submission)
greenlight scan ./MyApp.xcarchive

# ASC validation
asc validate ./MyApp.ipa

# TestFlight upload (last sanity check before submission)
asc upload ./MyApp.ipa --type ios
```

Sources:
- App Store Connect docs (sosumi MCP can search live)
- @WasimShips, March 2026
- @truongduy2611 App Store Preflight, March 2026
