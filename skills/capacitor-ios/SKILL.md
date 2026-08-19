---
name: capacitor-ios
description: >-
  Phased super-skill that turns a web app (improvebayarea.com or any Cloudflare
  Workers / SPA / PWA site) into a store-ready native iOS app with Capacitor — end
  to end. Use when the user wants to "make this an iOS app", "wrap the site", "ship
  improvebayarea to the App Store", add camera/geolocation/push to a web app, set up
  live web updates without App Store resubmission, build/run/test the app on the iOS
  Simulator, or asks how the web↔app update loop works. Detects the active phase and
  loads only that phase's reference file, the way /carmack loads only the relevant
  mode. Orchestrates the installed Capgo 48 capacitor-skills, awesome-ionic-mcp,
  XcodeBuildMCP + /xcode-test, /ios-ship (greenlight + privacy manifest), context7,
  sosumi, app-store-screenshots and aso-audit. Triggers: "capacitor", "wrap web app",
  "make it an iOS app", "ship to app store", "live updates / OTA", "Capgo".
---

# capacitor-ios — web app → store-ready iOS app (phased super-skill)

The one skill for taking a web app to the App Store with Capacitor. It does **not**
reinvent Capacitor knowledge — like `/carmack`, it **detects the phase, loads only
that phase's reference file**, routes to the specialized skills/MCP that hold the
detail, and enforces two non-negotiable gates.

## Philosophy

1. **Reuse, don't rewrite.** For an existing site, Capacitor wraps it (~90% as-is). Expo = rewrite — only if the user explicitly wants a native-UI rewrite.
2. **Two change-types, two ship-paths.** Classify every change as *web-layer* or *native-shell* before touching anything (GATE 1). Getting this wrong = needless App Store resubmits or shipping a native change as if it were web.
3. **Prove it runs before you gate; gate before you submit.** Build + launch + screenshot on the Simulator (Phase D) → greenlight + privacy manifest (GATE 2) → only then `/ios-ship`.
4. **Earn the right to be an app.** A bare WebView wrapper is rejected (Apple 4.2). Native features (camera/geolocation/push) are what make it an app, not a bookmark.
5. **Outward actions need approval + live verification.** TestFlight, App Store submit, signing, OTA pushes — show the user exactly what will happen, verify against live state, get explicit chat approval.
6. **Pull, don't guess.** Load the relevant Capgo skill, fetch live docs via context7/sosumi, drive the CLI via the MCP. Never assert an Apple-policy fact from memory.

---

## ⛓️ GATE 1 — Update-flow rule (MANDATORY — applies to every change request)

Classify the change FIRST and state which path you're taking:

| Change type | Examples | How users get it | Resubmit to App Store? |
|---|---|---|---|
| **Web layer** | HTML/CSS/JS, content, pages, client logic, copy, styling | Deploy to Workers (live URL) **or** push a Capgo OTA bundle → **instant** | **NO** |
| **Native shell** | `capacitor.config.*`, native plugins, **permissions / Info.plist**, icon/splash, min iOS, native Swift, privacy manifest | New build → GATE 2 → `/ios-ship` | **YES** |

**Why web-layer is OTA-legal:** Apple permits downloading/running interpreted JS that doesn't change the app's primary purpose or add a storefront, via Apple's JS engine. Capgo OTA + a live-URL WebView both rely on this. **Re-verify the current guideline at submission via the `capgo-release-workflows` skill + Apple's guidelines — never assert a guideline number from memory.** Detail: [references/ota-updates.md](./references/ota-updates.md).

## 🚦 GATE 2 — Ship gate (MANDATORY — before ANY archive/submission)

This skill never submits on its own. Before handing to `/ios-ship`:

1. **Build + smoke-test on Simulator** (Phase D) — must launch and run, no crash in logs.
2. **`greenlight preflight .`** → must be **GREENLIT (0 CRITICAL)**. Re-run until clean.
3. **Privacy manifest** — `PrivacyInfo.xcprivacy` present + correct (`greenlight privacy .`); Required-Reason API codes per Apple TN3183; **no fabricated tracking/data-collection declarations**.
4. Only when all green → `/ios-ship` for sign/archive/TestFlight/submit, **with chat approval**.

Detail: [references/build-test-gate.md](./references/build-test-gate.md).

---

## Phase routing — detect the phase, load ONLY that reference file

| Phase | Trigger / intent | Load | Pulls |
|---|---|---|---|
| **A — Wrap** | "make it an app", first-time setup, scaffold, point at the site | [references/wrap-and-native.md](./references/wrap-and-native.md) | `webapp-to-capacitor` skill · awesome-ionic-mcp · CocoaPods · Trapeze |
| **B — Native features** | add camera / geolocation / push; clear Apple 4.2 | [references/wrap-and-native.md](./references/wrap-and-native.md) | `capacitor-features`/`-ui` skills · awesome-ionic-mcp |
| **C — OTA live updates** | Capgo setup, "live updates", "update without App Store" | [references/ota-updates.md](./references/ota-updates.md) | `capgo-release-workflows`/`capgo-cloud` skills · Capgo CLI |
| **D — Build / test / gate** | build, run on sim, screenshot, "does it work", pre-submit gate | [references/build-test-gate.md](./references/build-test-gate.md) | XcodeBuildMCP · `/xcode-test` · xcbeautify · greenlight |
| **E — Ship** | sign, archive, TestFlight, submit, store listing | [references/ship-and-store.md](./references/ship-and-store.md) | `/ios-ship` · asc · `app-store-screenshots` · `aso-audit` |
| **F — Update loop** | steady-state change after launch | [references/ota-updates.md](./references/ota-updates.md) + GATE 1 | classify → Workers/Capgo or rebuild |
| **(any) — exact tool/command** | "what's installed", exact MCP tool name, CLI invocation | [references/tooling-map.md](./references/tooling-map.md) | verified inventory |

Default end-to-end run = A → B → C → **D (+ GATE 2)** → E → then F forever.
For an existing site, the Capacitor-vs-Expo decision is settled: **Capacitor** (ref report `~/Downloads/capacitor-vs-expo-agent-tooling-2026-06-03.html`).

---

## Tooling (summary — full inventory + exact commands in [references/tooling-map.md](./references/tooling-map.md))

- **Skills:** Capgo capacitor-skills (48, both agents) · `/ios-ship` (+ `asc-*`) · `app-store-screenshots` · `aso-audit`.
- **MCP (✓ connected):** `xcodebuildmcp` (build/run/screenshot/logs on sim, 63 tools) · `awesome-ionic-mcp` (Capacitor CLI + plugin docs) · `context7` (live docs) · `sosumi` (Apple docs) · `chrome-devtools` (debug the web layer in the WebView).
- **CLIs:** `pod` (CocoaPods 1.16.2) · `xcbeautify` 3.2.1 · `greenlight` · `asc` · `npx @capgo/cli` (OTA) · `npx @trapezedev/configure` (YAML native config) · `npx cap` (Capacitor).
- **Command:** `/xcode-test [scheme]` — turn-key build→install→launch→screenshot→log-scan→human-verify loop on XcodeBuildMCP.

## Hard rules

- **No outward Apple/Capgo action without explicit chat approval** — submit, TestFlight, signing change, OTA push. Show exactly what will happen first.
- **Accounts are the user's** — the agent never creates an Apple Developer or Capgo account. Prompt the user to sign in (`asc auth login`, Capgo) at the relevant phase.
- **Ground-truth gate:** before asserting an Apple/Capgo policy fact or taking an outward action, verify against a primary source fetched now (sosumi / capgo skill / context7), never a remembered value. Full standard: `~/.claude/skills/shared/ground-truth-standard.md`.
- **No-lie reporting:** "built / runs / GREENLIT / submitted" must each cite the command + result that proves it (build exit + `BUILD SUCCEEDED`, greenlight output, asc confirmation). Don't report the state of your *action*; report the state of the *world* after it.

## Quick start

> "Use capacitor-ios to wrap improvebayarea.com with photo + location reporting, set up Capgo live updates, build + test it on the simulator, and run the ship gate."

Run A→B→C→D(+GATE 2)→E. After launch, every change goes through GATE 1 first.
