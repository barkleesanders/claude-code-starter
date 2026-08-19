# Tooling map — verified inventory + exact invocations (status 2026-06-03)

Everything below was installed/verified this session. Agent side is fully equipped except
two user-side accounts (Apple Developer, Capgo).

## MCP servers (both Claude Code + Codex)
| Server | Claude tool namespace | Run command | Purpose |
|---|---|---|---|
| **xcodebuildmcp** (✓ connected) | `mcp__xcodebuildmcp__*` (63 tools) | `npx -y xcodebuildmcp@latest mcp` | Build/install/launch/screenshot/log on the Simulator; discover projs/schemes/sims. Name is lowercase so `/xcode-test` resolves. |
| **awesome-ionic-mcp** (✓ connected) | `mcp__awesome-ionic-mcp__*` | `npx -y awesome-ionic-mcp@latest` | ~28 Capacitor/Ionic CLI tools + live plugin docs |
| **context7** | `mcp__context7__*` | (already configured) | Live Capacitor/plugin docs (`resolve-library-id` → `query-docs`) |
| **sosumi** | `mcp__sosumi__*` | (already configured) | Apple Developer docs + HIG |
| **chrome-devtools** | `mcp__chrome-devtools__*` | (already configured) | Debug the web layer running in the WebView |

- Claude Code config: `~/.claude.json` (user scope). Re-add if needed: `claude mcp add -s user xcodebuildmcp -- npx -y xcodebuildmcp@latest mcp`.
- Codex config: `~/.codex/config.toml` — `[mcp_servers.xcodebuildmcp]` + `[mcp_servers.awesome-ionic-mcp]`.

## CLIs
| CLI | Version / path | Use |
|---|---|---|
| `pod` (CocoaPods) | 1.16.2 | `npx cap sync ios` runs `pod install` for native plugins |
| `xcbeautify` | 3.2.1 | `xcodebuild ... | xcbeautify` → parseable build logs |
| `greenlight` | installed | `greenlight preflight .` / `privacy .` / `ipa <file>` — App Store compliance gate |
| `asc` | installed | App Store Connect CLI (signing, builds, TestFlight, submit) |
| `xcodebuild` | Xcode 26.5 | native build/archive |
| `npx @capgo/cli@latest` | v7.x | OTA bundle upload + channels (needs Capgo account/API key) |
| `npx @trapezedev/configure` | latest | YAML-driven native config (version, bundle id, Info.plist, entitlements) |
| `npx cap` | per-project | Capacitor CLI (`init`, `add ios`, `sync`) |

## Skills
| Skill / command | Role |
|---|---|
| **Capgo capacitor-skills** (48) | Capacitor APIs/plugins/UI/quality/deployment/OTA/migrations/upgrades. Claude: installed as 11 plugins via `Cap-go/capgo-skills` marketplace. Codex: 48 dirs in `~/.codex/skills/`. Browse: `ls ~/.claude/plugins/marketplaces/capgo-skills/skills`. |
| `webapp-to-capacitor` | The migration guide — Phase A start |
| `capgo-release-workflows`, `capgo-cloud` | OTA engine — Phase C |
| `/ios-ship` (+ `asc-*`) | Apple toolchain — Phase E |
| `/xcode-test` | Build/test loop on XcodeBuildMCP — Phase D (from compound-engineering plugin) |
| `app-store-screenshots`, `aso-audit` | Store listing assets + ASO — Phase E |

## User-side accounts (agent cannot create — prompt at the relevant phase)
- **Apple Developer Program** + signing identity → Phase E submit. `asc auth login`.
- **Capgo account + API key** → Phase C OTA push.

## Re-verify before asserting
Versions/flags drift (Capgo CLI especially). Before asserting a command or an Apple/Capgo
policy fact, re-check via `--help`, the owning Capgo skill, context7, or sosumi — never from
memory. This file is a hypothesis to confirm, not gospel.
