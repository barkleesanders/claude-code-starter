# Phase E — Ship (sign, archive, TestFlight, submit) + store listing

Goal: get the GATE-2-passed build signed, archived, and into TestFlight / the App Store,
with the store listing prepared. **Every step here is an outward action — chat approval required.**

## Precondition
GATE 2 is green (build runs on sim, greenlight GREENLIT, privacy manifest correct). If not,
go back to [build-test-gate.md](./build-test-gate.md). Do not submit an ungated build.

## Account precondition (user-side)
Submission needs an **Apple Developer Program** membership + a signing identity. The agent
never creates Apple accounts. Prompt the user: `asc auth login` (interactive, opens browser),
or set `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` for CI.

## Hand to `/ios-ship` for the Apple toolchain
Invoke **`/ios-ship`** — it owns Phases 4–8 (sign → archive → export → TestFlight → submit)
via `xcodebuild` + the `asc` CLI + the `asc-*` sub-skills. Key steps it runs:
- `asc bundle-ids create` / capabilities (push, etc.)
- certificates + provisioning profile (`asc-signing-setup`)
- `xcodebuild clean archive` → `-exportArchive` with ExportOptions.plist
- `greenlight ipa <path>.ipa` — post-archive binary scan
- `asc publish testflight` / `asc publish appstore` — **show the user exactly what will
  upload/submit and get explicit approval before running.**

## Store listing assets
- **`/app-store-screenshots`** — generate the required App Store screenshot set (device
  frames, marketing images) from the running app / key screens.
- **`/aso-audit`** — audit + optimize the listing (title, subtitle, keywords, description)
  before first submission. `asc-metadata-sync` / `asc-localize-metadata` apply + translate.

## After approval lands
- Capture the build id / submission confirmation (no-lie: "submitted" must cite the asc
  confirmation, not just "I ran the command").
- First public build includes the initial Capgo OTA bundle; thereafter web-layer updates
  ship via Capgo without re-submission (Phase F / [ota-updates.md](./ota-updates.md)).
