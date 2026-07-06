# Phase C (OTA live updates) + Phase F (steady-state update loop)

Goal: make web-layer changes reach users instantly without an App Store resubmission,
and run the steady-state loop correctly forever after.

## Pull first
- Load the **`capgo-release-workflows`** and **`capgo-cloud`** Capgo skills — they hold
  the current Capgo channel/bundle/CLI workflow and the up-to-date Apple OTA-policy nuance.
- Capgo is the live-update engine (Capacitor's OSS founder's company). CLI runs via npx.

## Account prerequisite (user-side — agent cannot create it)
OTA needs a **Capgo account + API key**. Prompt the user to create it and provide the key
(store it where the CLI expects, not in chat history). The CLI + skills are ready; only the
account is missing.

## Phase C — set up OTA
1. Add the updater plugin + log in:
   ```bash
   npm i @capgo/capacitor-updater
   npx cap sync ios
   npx @capgo/cli@latest login <API_KEY>
   npx @capgo/cli@latest app add com.improvebayarea.app   # register the app
   ```
2. Create a channel (e.g. `production`) and set the app to auto-update from it. Follow the
   exact current commands from the `capgo-release-workflows` skill (don't hardcode flags
   from memory — the CLI is at v7.x and evolves).
3. First bundle is shipped inside the App Store build; subsequent web changes ship as OTA bundles.

## Phase F — steady-state: classify EVERY change (this is GATE 1)
Before any change, decide the path and say which one:

- **Web layer** (HTML/CSS/JS, content, copy, client logic, styling):
  ```bash
  # 1. deploy the web app to Cloudflare Workers (browser users get it instantly)
  # 2. push the same build as an OTA bundle so app users get it too:
  npx @capgo/cli@latest bundle upload --channel production --path dist
  ```
  → **No App Store resubmission.** Verify the bundle is live on the channel.

- **Native shell** (config, plugins, permissions/Info.plist, icon, min iOS, Swift, privacy manifest):
  → bump the build number, go through **GATE 2** (Phase D: build/test + greenlight + privacy),
  then **`/ios-ship`** to resubmit. Get chat approval before submit.

## Apple-policy honesty
OTA of interpreted web assets is allowed only while it doesn't change the app's primary
purpose or add a storefront. **Re-verify the live guideline** via the `capgo-release-workflows`
skill + Apple guidelines (sosumi) at submission time — never assert the rule or a guideline
number from memory. If a "web" change actually alters the app's purpose, treat it as native.

## OTA push is an outward action
Pushing a bundle changes what real users run → show the user what's shipping and get approval,
same as a deploy.
