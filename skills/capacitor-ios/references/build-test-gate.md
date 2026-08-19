# Phase D — Build / run / test on Simulator, then GATE 2

Goal: prove the app actually builds and runs, capture evidence, then clear the
compliance gate before any submission. This is where "looks done" becomes "is done".

## Fastest path: `/xcode-test`
Run **`/xcode-test [scheme|current]`** — the turn-key loop on XcodeBuildMCP:
discover scheme → boot sim → build → install → launch → screenshot each key screen →
scan logs for crashes → human-verify camera/location/push → summary. Use this first.

## Manual loop (XcodeBuildMCP tools — `mcp__xcodebuildmcp__*`)
```
discover_projs({})                                  # find the .xcodeproj/.xcworkspace
list_schemes({ project_path })
list_simulators({}) → boot_simulator({ simulator_id })
build_ios_sim_app({ project_path, scheme })         # build for simulator
install_app_on_simulator({ app_path, simulator_id })
launch_app_on_simulator({ bundle_id, simulator_id })
capture_sim_logs / get_sim_logs({ simulator_id })   # watch for crashes/exceptions
take_screenshot({ simulator_id, filename })         # verify each screen renders
```
- Pipe any raw `xcodebuild` through **xcbeautify** for compact, parseable output:
  `xcodebuild ... | xcbeautify`.
- **No-lie rule:** "builds / runs" is only true if `BUILD SUCCEEDED` appears AND the app
  launches without an error in `get_sim_logs`. Cite the evidence. A green build that
  crashes on launch is NOT done.
- Test the native features specifically: trigger the camera + geolocation report flow on
  the sim and confirm via screenshot + logs (use `/xcode-test`'s human-verify step — sim
  camera/location need a human or a simulated location).

## GATE 2 — compliance (MANDATORY before submission)
1. **greenlight:** `greenlight preflight .` → must be **GREENLIT (0 CRITICAL)**. Re-run until clean.
   Common wrap CRITICALs + fixes:
   | Finding | Fix |
   |---|---|
   | Thin WebView (Guideline 4.2) | Phase B native features must be wired + reachable |
   | Missing privacy purpose strings | add `NSCameraUsageDescription` / `NSLocationWhenInUseUsageDescription` |
   | No account deletion | add in-app account deletion if the app has accounts |
   | HTTP URLs | force `https://` |
   | External payment for digital goods | use StoreKit/IAP, or N/A for a civic app |
2. **Privacy manifest:** `greenlight privacy .` → `PrivacyInfo.xcprivacy` present + correct.
   Declare Required-Reason API codes per Apple TN3183 (UserDefaults `CA92.1`, FileTimestamp
   `C617.1`, etc.). **Never fabricate** a tracking or data-collection declaration to satisfy
   a scanner — declare only what's true.
3. Both green → proceed to Phase E ([references/ship-and-store.md](./ship-and-store.md)).

## Web-layer debugging inside the WebView
The app runs your site in a WebView — if a screen misbehaves, debug the *web layer* with
the `chrome-devtools` skill / `mcp__chrome-devtools__*` (console, network, DOM), same as
debugging improvebayarea.com in a browser. Web bugs are fixed in the web app, not the shell.
