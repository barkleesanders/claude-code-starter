---
name: ios-ship
user-invocable: true
description: >
  End-to-end iOS/macOS app development and deployment super skill. Covers the full lifecycle:
  create Swift/SwiftUI projects, write code, build & test on simulator, run App Store compliance
  scans, sign & archive, upload to TestFlight, submit to App Store. Combines greenlight (compliance),
  asc CLI (App Store Connect), xcodebuild, Apple docs (sosumi MCP), and agent-browser (UI automation).
  Triggers on: "build an iOS app", "ship to App Store", "deploy to TestFlight", "create a Swift app",
  "check App Store compliance", "submit my app", "ios-ship", "/ios-ship".
---

# /ios-ship — iOS Development & Deployment Super Skill

You are an expert iOS/macOS developer and deployment engineer. You can take an app from
zero to App Store submission in a single session. You have access to the full Apple toolchain.

## Available Tools

| Tool | Purpose | Installed |
|------|---------|-----------|
| `xcodebuild` | Build, test, archive, export | Xcode 26.3 |
| `swift` | Swift 6.2.4 compiler + SPM | System |
| `xcrun simctl` | iOS Simulator management | Xcode |
| `greenlight` | App Store compliance scanner | Homebrew |
| `asc` | App Store Connect CLI (builds, TestFlight, releases, signing) | Homebrew |
| `agent-browser` | Browser automation for ASC web UI + iOS Safari (v0.9+) | PATH |
| `sosumi MCP` | Apple Developer documentation search | MCP server |
| `rmp` | Rust Multi-Platform (iOS + Android + Desktop from shared Rust core) | Cargo |

## Workflow Phases

### Phase 1: CREATE — New Project Setup

```bash
# Create a new SwiftUI app project
mkdir -p ~/Projects/MyApp && cd ~/Projects/MyApp
swift package init --type executable --name MyApp

# OR create an Xcode project structure
mkdir -p MyApp.xcodeproj MyApp MyAppTests
```

For SwiftUI apps, create the standard structure:
```
MyApp/
├── MyApp.xcodeproj/
├── MyApp/
│   ├── MyAppApp.swift          # @main App entry point
│   ├── ContentView.swift       # Root view
│   ├── Info.plist
│   └── Assets.xcassets/
├── MyAppTests/
└── MyAppUITests/
```

**Apple Documentation**: Use `mcp__sosumi__searchAppleDocumentation` and
`mcp__sosumi__fetchAppleDocumentation` to look up any SwiftUI view, modifier,
framework API, or HIG guideline while writing code.

### Phase 2: BUILD — Write Code & Iterate

Write Swift/SwiftUI code following Apple's patterns:
- Use `@Observable` (iOS 17+) or `@ObservableObject` for state
- Use `@Environment` for dependency injection
- Follow MVVM or MV pattern per Apple's guidance
- Use Swift concurrency (`async/await`, `actor`) over GCD

**Build and check for errors:**
```bash
xcodebuild build \
  -scheme "MyApp" \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -quiet 2>&1 | tail -20
```

**Run tests:**
```bash
xcodebuild test \
  -scheme "MyApp" \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  -resultBundlePath /tmp/TestResults.xcresult \
  -quiet 2>&1 | tail -30
```

**List available simulators:**
```bash
xcrun simctl list devices available | grep -E "iPhone|iPad" | head -10
```

**Boot and install on simulator:**
```bash
xcrun simctl boot "iPhone 16 Pro"
xcrun simctl install booted /path/to/MyApp.app
xcrun simctl launch booted com.example.MyApp
```

**Take simulator screenshot:**
```bash
xcrun simctl io booted screenshot /tmp/sim-screenshot.png
```

**Browser automation on iOS Safari (agent-browser v0.9+):**
```bash
agent-browser -p ios open <url>          # Open URL in iOS Safari
agent-browser -p ios snapshot -i -c      # AI-optimized element refs
agent-browser -p ios click @e2           # Interact by ref
agent-browser -p ios screenshot          # Capture Safari screenshot
```

### Phase 3: SCAN — App Store Compliance Check

**Run greenlight BEFORE archiving.** This catches rejection risks early.

```bash
greenlight preflight .
```

Fix every finding by severity:
1. **CRITICAL** — Will be rejected. Must fix before submission.
2. **WARN** — High rejection risk. Should fix.
3. **INFO** — Best practice. Consider fixing.

Common fixes:
| Finding | Fix |
|---------|-----|
| Hardcoded secrets | Move to Keychain or env vars |
| External payment for digital goods | Replace with StoreKit/IAP |
| Social login without Sign in with Apple | Add `AuthenticationServices` |
| No account deletion | Add "Delete Account" in Settings |
| Platform references ("Android") | Remove cross-platform mentions |
| HTTP URLs | Change to `https://` |
| Missing privacy purpose strings | Add specific Info.plist descriptions |
| Console logs in release | Gate behind `#if DEBUG` |

**Re-run until GREENLIT (zero CRITICAL findings).**

```bash
greenlight preflight .  # Loop until clean
```

Additional scans:
```bash
greenlight codescan .                    # Code-only analysis
greenlight privacy .                     # Privacy manifest check
greenlight ipa /path/to/build.ipa        # Binary inspection (post-archive)
greenlight guidelines search "privacy"   # Search Apple guidelines
```

### Phase 4: SIGN — Certificates & Profiles

**Set up signing with `asc`:**

```bash
# Authenticate (interactive — opens browser for Apple ID)
asc auth login

# OR set env vars for CI
export ASC_KEY_ID="your-key-id"
export ASC_ISSUER_ID="your-issuer-id"
export ASC_KEY_PATH="./AuthKey.p8"
```

**Register bundle ID:**
```bash
asc bundle-ids create \
  --identifier "com.yourcompany.myapp" \
  --name "MyApp" \
  --platform IOS
```

**Add capabilities:**
```bash
asc bundle-ids capabilities add \
  --bundle "BUNDLE_ID" \
  --capability PUSH_NOTIFICATIONS
```

**Create signing certificate (if needed):**
```bash
asc certificates list --certificate-type IOS_DISTRIBUTION
asc certificates create --certificate-type IOS_DISTRIBUTION --csr "./cert.csr"
```

**Create provisioning profile:**
```bash
asc profiles create \
  --name "MyApp AppStore" \
  --profile-type IOS_APP_STORE \
  --bundle "BUNDLE_ID" \
  --certificate "CERT_ID"
```

### Phase 5: ARCHIVE — Build for Distribution

```bash
# Clean and archive
xcodebuild clean archive \
  -scheme "MyApp" \
  -configuration Release \
  -archivePath /tmp/MyApp.xcarchive \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates

# Export IPA
xcodebuild -exportArchive \
  -archivePath /tmp/MyApp.xcarchive \
  -exportPath /tmp/MyAppExport \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

**ExportOptions.plist** (create this):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

**Post-archive binary scan:**
```bash
greenlight ipa /tmp/MyAppExport/MyApp.ipa
```

### Phase 6: TESTFLIGHT — Beta Distribution

```bash
# Upload build
asc builds upload --app "APP_ID" --ipa "/tmp/MyAppExport/MyApp.ipa"

# OR one-command TestFlight publish
asc publish testflight \
  --app "APP_ID" \
  --ipa "/tmp/MyAppExport/MyApp.ipa" \
  --group "BETA_GROUP_ID" \
  --wait --notify

# Add test notes
asc builds test-notes create \
  --build "BUILD_ID" \
  --locale "en-US" \
  --whats-new "Bug fixes and performance improvements"

# Manage testers
asc testflight beta-testers add \
  --app "APP_ID" \
  --email "tester@example.com" \
  --group "Beta Testers"
```

**Monitor builds:**
```bash
asc builds latest --app "APP_ID" --platform IOS
asc builds list --app "APP_ID" --sort -uploadedDate --limit 5
```

### Phase 7: SUBMIT — App Store Release

**Pre-submission health check:**
```bash
# Verify build is processed
asc builds info --build "BUILD_ID"

# Check encryption compliance
asc encryption declarations list --app "APP_ID"

# Content rights
asc apps update --id "APP_ID" \
  --content-rights "DOES_NOT_USE_THIRD_PARTY_CONTENT"
```

**Submit to App Store:**
```bash
# One-command submission
asc publish appstore \
  --app "APP_ID" \
  --ipa "/tmp/MyAppExport/MyApp.ipa" \
  --version "1.0.0" \
  --wait --submit --confirm

# OR manual flow for more control
asc versions create --app "APP_ID" --version "1.0.0" --platform IOS
asc versions attach-build --version-id "VERSION_ID" --build "BUILD_ID"
asc submit create --app "APP_ID" --version "1.0.0" --build "BUILD_ID" --confirm
```

**Monitor review:**
```bash
asc submit status --version-id "VERSION_ID"
```

### Phase 8: MONITOR — Post-Launch

```bash
# Crash reports
asc crashes --app "APP_ID" --sort -createdDate --limit 10

# Beta feedback
asc feedback --app "APP_ID" --sort -createdDate --limit 10

# Performance diagnostics (hangs, disk writes, launches)
asc performance diagnostics list --build "BUILD_ID" --diagnostic-type "HANGS"

# Download metrics
asc performance download --build "BUILD_ID" --output ./metrics.json
```

## Quick Reference

### Common `asc` Commands
```bash
asc auth login                                    # Authenticate
asc apps list                                     # List your apps
asc apps list --bundle-id "com.example.app"       # Find by bundle ID
asc builds upload --app ID --ipa path.ipa         # Upload build
asc publish testflight --app ID --ipa path.ipa    # TestFlight
asc publish appstore --app ID --ipa path.ipa      # App Store
asc submit status --version-id ID                 # Review status
asc crashes --app ID --limit 10                   # Crash reports
```

### Common `greenlight` Commands
```bash
greenlight preflight .                            # Full compliance scan
greenlight codescan .                             # Code-only scan
greenlight privacy .                              # Privacy manifest scan
greenlight ipa /path/to/build.ipa                 # Binary inspection
greenlight guidelines search "keyword"            # Search guidelines
```

### Apple Documentation (MCP)
```
mcp__sosumi__searchAppleDocumentation("SwiftUI NavigationStack")
mcp__sosumi__fetchAppleDocumentation("/documentation/swiftui/view")
mcp__sosumi__fetchAppleDocumentation("design/human-interface-guidelines/foundations/color")
```

## Sub-Skills Available

These granular skills are auto-loaded and available for specific tasks:

| Skill | When to use |
|-------|-------------|
| `asc-workflow` | Multi-step CI/CD automation |
| `asc-xcode-build` | Build, archive, export details |
| `asc-release-flow` | TestFlight + App Store release |
| `asc-signing-setup` | Certificates, profiles, bundle IDs |
| `asc-testflight-orchestration` | Beta groups, testers, test notes |
| `asc-submission-health` | Pre-submission checks, encryption compliance |
| `asc-crash-triage` | Crash reports, feedback, diagnostics |
| `asc-metadata-sync` | App Store metadata, screenshots, descriptions |
| `asc-app-create-ui` | Create new app in ASC (browser automation) |
| `asc-ppp-pricing` | Regional pricing, purchasing power parity |
| `asc-notarization` | macOS notarization |
| `asc-localize-metadata` | Multi-language metadata |
| `asc-subscription-localization` | IAP/subscription localization |
| `asc-revenuecat-catalog-sync` | RevenueCat + ASC sync |
| `asc-shots-pipeline` | Screenshot automation |
| `greenlight` | App Store compliance scanning |

## RMP — Rust Multi-Platform Apps

For cross-platform apps sharing a Rust core with native UI (SwiftUI for iOS, Jetpack Compose for Android, iced for Desktop).

**Architecture**: Single Rust business logic layer → UniFFI bindings → Native platform UI.

### Setup

```bash
# Install RMP CLI
cargo install --git https://github.com/rust-multiplatform/rmp rmp-cli

# Create new multi-platform project
rmp init my-app --org com.example --ios --android --iced --flake

# Verify prerequisites
rmp doctor
```

### Build & Run

```bash
# Generate UniFFI bindings for all platforms
rmp bindings all

# Run on iOS Simulator
rmp run ios

# Run on Android Emulator
rmp run android

# Run desktop (iced)
rmp run iced
```

### Project Structure (RMP)

```
my-app/
├── core/              ← Shared Rust business logic
│   ├── src/lib.rs     ← State, Actions, Update (TEA/Elm pattern)
│   └── Cargo.toml
├── bindings/          ← UniFFI generated FFI layer
├── ios/               ← SwiftUI native UI
├── android/           ← Jetpack Compose native UI
├── desktop/           ← iced Rust GUI
└── flake.nix          ← Nix dev environment (optional)
```

### Pattern: TEA (The Elm Architecture)

RMP uses TEA for state management across all platforms:
- **Model** — App state (Rust struct)
- **Message** — Actions/events (Rust enum)
- **Update** — Pure function: `(Model, Message) → Model`
- **View** — Platform-native rendering (SwiftUI/Compose/iced)

## Expo Path — React Native (No Xcode Required)

For rapid prototyping or when you don't need native Swift, use the Expo stack.
Claude already knows Tailwind, making this the fastest path to a good-looking app.

### Stack
| Tool | Purpose |
|------|---------|
| **Expo** | React Native framework — handles project setup, dev server, builds |
| **Expo Go** | Phone app for live testing via QR code scan |
| **NativeWind** | Tailwind CSS for React Native — Claude writes great Tailwind |
| **EAS Build** | Cloud builds + App Store submission — no Xcode needed |

### Setup
```bash
npx create-expo-app@latest MyApp
cd MyApp

# Add NativeWind (Tailwind for RN)
npx expo install nativewind tailwindcss
npx tailwindcss init
```

### Dev Loop
```bash
npx expo start
# Scan QR code with Expo Go on your phone — live reload on device
```

### Ship to App Store
```bash
npm install -g eas-cli
eas login
eas build:configure

# Build for iOS in the cloud (no local Xcode)
eas build --platform ios --profile production

# Submit to App Store
eas submit --platform ios
```

### When to Use Expo vs Native
| Choose Expo when... | Choose Native (Swift) when... |
|---------------------|-------------------------------|
| Rapid prototype / interview demo | Need platform-specific APIs |
| Already know React/Tailwind | Performance-critical (games, AR) |
| Want live device testing fast | Need custom native modules |
| Don't have/want Xcode | Enterprise with existing Swift codebase |

## Instructions

When this skill is invoked:

1. **Determine the phase** — What does the user need? New project? Build? Deploy? Fix?
2. **Choose the path** — If user wants rapid prototyping, knows React, or says "no Xcode", use the **Expo path**. Otherwise default to native Swift.
3. **Use the right tool for each phase** — Don't skip steps.
3. **Always run `greenlight preflight .` before archiving** — Catch rejections early.
4. **Use sosumi MCP for Apple docs** — Look up APIs, HIG guidelines, framework details.
5. **Use `asc` CLI for all App Store Connect operations** — Not the web UI.
6. **Use `agent-browser` only for operations that require web UI** (e.g., creating new app records).
7. **Build incrementally** — Write code → build → fix errors → test → repeat.
8. **Gate deployment on green compliance scan** — No CRITICAL findings = safe to ship.
