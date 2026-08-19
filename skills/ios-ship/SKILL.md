---
name: ios-ship
user-invocable: true
description: >
  MERGED (2026-06-12) — kept as a redirect for muscle memory. iOS development
  (build/run/debug/review/test/screenshots/ASO) is now the /ios super skill;
  iOS release (greenlight → sign → archive → TestFlight → App Store → OTA
  sync) is /ship's Phase 4.7 (references/ios-release.md). Invoking /ios-ship
  routes to those.
---

# /ios-ship → merged into /ios + /ship

This skill's content moved on 2026-06-12 (user-requested consolidation so the
major skills mirror each other: /carmack ↔ /ship, with /ios as the Apple
counterpart of /carmack):

- **Developing, building, debugging, reviewing, testing, store assets** →
  invoke **/ios** (`~/.claude/skills/ios/SKILL.md`). It routes to
  xcodebuildmcp, axiom skills, greenlight, asc sub-skills
  (asc-cli-usage, asc-shots-pipeline, asc-metadata-sync, aso-audit,
  app-store-screenshots, capacitor-ios, xcode-test, …).
- **Releasing** (archive, signing, TestFlight, App Store submit, Capacitor
  OTA web-first sync, App Review requirements table) → invoke **/ship**;
  its Phase 4.7 loads `~/.claude/skills/ship/references/ios-release.md`.
- **Simulator streaming / agent eyes** (MJPEG stream, taps, a11y tree,
  camera injection, permissions) → the `/serve-sim` skill
  (`~/.claude/skills/serve-sim`), documented in /ios's
  "Driving + testing the UI" section.

When invoked: decide which side of the line the user's ask is on and invoke
/ios or /ship accordingly. Do not duplicate their content here.
