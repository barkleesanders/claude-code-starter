---
name: unbrowse
description: >-
  Web content + endpoint discovery without the browser-driving overhead. Use for
  clean markdown fetch of any URL (libcurl-impersonate Chrome JA4, auto-pulls
  cookies from your real browser), one-shot intent-driven scraping (`unbrowse
  run`), and capture/replay of authenticated JSON endpoints so you don't have
  to drive a UI every time. Primary surface is the CLI (`unbrowse <cmd>`);
  MCP server is available at `npx -y unbrowse mcp` as an alternative for hosts
  that have it wired up.
user-invocable: true
metadata: {"openclaw": {"requires": {"bins": ["unbrowse"]}, "install": [{"id": "npm", "kind": "node", "package": "unbrowse", "bins": ["unbrowse"]}], "emoji": "🔍", "homepage": "https://github.com/unbrowse-ai/unbrowse"}, "version": "7.1.0", "updated": "2026-05-27"}
---

# Unbrowse — Web fetch, intent-driven scrape, endpoint capture/replay

Unbrowse is a CLI (and optional MCP server) that gives an agent three things the regular fetch tool can't:

1. **Realistic HTTP fingerprint** — every request goes through libcurl-impersonate (Chrome 131 JA4) and auto-pulls cookies from your actual installed Chrome/Edge/Brave/etc. profile. Most "WAF-blocked when scripted" pages just work.
2. **HTML → clean markdown by default** — `unbrowse fetch <url>` returns body-only readable text, no nav chrome, no scripts. Better signal-to-noise than raw `curl | pandoc`.
3. **Capture-and-replay of authenticated JSON endpoints** — `unbrowse run` (or `resolve` + `execute`) opens a real browser exactly once, discovers the API call behind a page, caches it, and replays it as a plain HTTP request on every subsequent run. Skills accumulate in a local index keyed by domain + intent.

## When to use unbrowse

| Use unbrowse for | Use something else for |
|---|---|
| Clean-markdown read of any public URL → `unbrowse fetch <url>` | Reading a local file → Read tool |
| Page that's WAF/cookie-gated and `curl` returns 403 | Page in your already-open Chrome tab → chrome-devtools MCP at :9222 |
| First-time scrape of an authenticated UI ("download my X from Y") → `unbrowse run <url> "task"` | Sending email → `gog send -a <addr>` |
| Discovering the JSON API behind a page → `unbrowse resolve --intent "..." --url "..."` | Bulk Composio integrations → Composio CLI |
| Replaying a captured endpoint with new params → `unbrowse execute --skill ID --endpoint ID -p key=val` | Greping the codebase → Grep/Glob |
| Live HAR capture while you click around → `unbrowse capture --url ... --intent ...` | Image/PDF inspection → Read tool |

### When NOT to use unbrowse
- **Don't use to extract cookies for another tool.** Use `~/tools/cookies-txt` or chrome-devtools CDP per the cookie-handling rules.
- **Don't use as a Grep substitute.** It fetches the network — Grep/osgrep is for local files.
- **Don't use for image or PDF content.** The Read tool handles those natively.
- **Don't use for already-open browser tabs.** chrome-devtools MCP at `:9222` is faster and sees the live DOM state.

## The 5 commands an agent uses 95% of the time

### 1. `unbrowse fetch <url>` — clean markdown of any URL
```bash
unbrowse fetch "https://example.com/article"
# → body-only markdown, no nav, no scripts, cookies from your real browser
```

Flags worth knowing: `--raw` keeps HTML bytes (no markdown conversion). For sandboxed JS evaluation in the page context, use the advanced mode: `unbrowse fetch <url> --bundle-source <js|-> --post-eval <expr>` which returns the full envelope (cookies, post_eval result, observed routes).

### 2. `unbrowse run <url> "<task>"` — one-shot intent
```bash
unbrowse run "https://sanfrancisco.nextrequest.com" "list my open records requests"
```
First call: opens a real browser, captures the API. Subsequent calls: replays cached endpoint. Falls back to interactive only when needed.

### 3. `unbrowse resolve --intent "..." --url "..." [--no-execute]` — endpoint discovery
```bash
unbrowse resolve --intent "fetch latest releases" --url "https://github.com/owner/repo"
# → auto-executes the top-ranked safe GET. Add --no-execute for just the shortlist.
```
Use `--no-execute` to inspect what's available, then `unbrowse execute --skill ID --endpoint ID -p key=val` to actually call it.

### 4. `unbrowse capture --url <url> --intent <intent>` — explicit live HAR
```bash
unbrowse capture --url "https://app.example.com/dashboard" --intent "download monthly report"
```
Opens a visible browser, you do whatever you'd do manually, unbrowse logs the requests and indexes them as replayable endpoints.

### 5. `unbrowse auth <url>` — first-time login
```bash
unbrowse auth "https://app.example.com"
# Opens a visible browser. You sign in. Cookies persist for all future fetch/run/resolve.
```

## Quick global flag reference

| Flag | What it does |
|------|--------------|
| `--pretty` | Pretty-print JSON output (indented) |
| `--raw` | On `fetch`: keep HTML bytes (skip markdown). On `resolve`/`execute`: skip server-side projection |
| `--no-auto-start` | Don't auto-spawn the local server if it's down |
| `--path "data.items[]"` | Drill into the result before extract/output (resolve/execute) |
| `--extract "field1,alias:deep.path"` | Pick specific fields without piping |
| `--limit N` | Cap array output to N items |
| `--dry-run` | Preview mutations without applying |

Full command/flag dump (auto-generated, kept here for completeness):

<!-- CLI_REFERENCE_START -->
### All commands

| Command | Description |
|---------|-------------|
| `fetch <url>` | Primary URL → markdown. Add `--bundle-source <js>` + `--post-eval <expr>` for sandboxed JS evaluation. |
| `run <url> "task"` | One-shot intent. Cached replay first, capture+index on miss, browser only when needed. |
| `resolve --intent "..." [--url "..."]` | Resolve intent against marketplace + local cache. Auto-executes top safe GET; `--no-execute` for metadata only. |
| `execute --skill ID --endpoint ID -p k=v` | Call a specific endpoint after `resolve --no-execute`. |
| `capture --url <url> --intent "..."` | Live-browser HAR capture; discovers + indexes API endpoints. |
| `auth <url>` | Open a visible browser for sign-in; cookies persist for future calls. |
| `explain --intent "..." --url "..."` | Print top-N candidate endpoints + evidence (no verdict, just primitives). |
| `note <read\|write\|list> --domain <d>` | Per-domain LLM notes consumed by augment on next capture. |
| `skills` | List all locally-cached skills. |
| `skill <id>` | Full SkillManifest for one skill. |
| `feedback --skill ID --endpoint ID --rating 1-5` | Submit feedback after presenting results (mandatory after resolve+execute). |
| `annotate --skill ID --endpoint ID --text 'tip'` | Contribute best practices/gotchas. |
| `review --skill ID --endpoints '[...]'` | Push reviewed descriptions/schema back to a captured skill. |
| `index --skill ID` | Recompute local graph/contracts (no network). |
| `publish --skill ID` | Publish reviewed skill to marketplace (gated by `unbrowse mode`). |
| `cleanup-stale [--skill ID]` | Verify skills against live endpoints; evict stale entries. |
| `health` | Local server health check (version, uptime). |
| `account [--register] [--json]` | Show local account, wallet, contribution mode. |
| `mode` | Re-prompt for private / share / share+earn. |
| `settings` | Show/update local capture/publish policy. |
| `dashboard` | Open website dashboard, pair this CLI install. |
| `setup` | Bootstrap browser engine + /unbrowse command. Idempotent. |
| `upgrade` | Print the right upgrade command. |
| `stats [--flywheel \| --earnings]` | Time/tokens/cost saved + earnings. |

### Browse-session commands (when `run` falls back to interaction)

`go <url>`, `snap`, `click <ref>`, `fill <ref> <value>`, `type <text>`, `press <key>`, `select <ref> <value>`, `scroll <dir>`, `submit`, `screenshot`, `text`, `markdown`, `cookies`, `eval <expr>`, `back`, `forward`, `sync`, `close`, `inspect`, `sessions --domain <d>`.

### resolve/execute extras

| Flag | Description |
|------|-------------|
| `--no-execute` | Resolve only; return shortlist without auto-executing |
| `--schema` | Show response schema + extraction hints (no data) |
| `--endpoint ID` | Pick a specific endpoint by ID |
| `--params '{...}'` | Extra params as JSON |
| `-p key=val` | Single param via repeated flag |
| `--require-proof` | Filter to endpoints with independently verified proofs |
<!-- CLI_REFERENCE_END -->

## MCP option (alternative to CLI)

If your host has it wired up, `npx -y unbrowse mcp` exposes the same capabilities as MCP tools (`unbrowse_resolve`, `unbrowse_execute`, `unbrowse_fetch`, `unbrowse_run`, `unbrowse_capture`, plus the browse-session tools `unbrowse_go`/`snap`/`click`/etc., and `unbrowse_publish`/`unbrowse_review` for the marketplace flow). Result size is capped at 25 KB per call.

Add to your MCP host config (Claude Desktop, Cursor, Codex, etc.):
```json
{ "mcpServers": { "unbrowse": { "command": "npx", "args": ["-y", "unbrowse", "mcp"] } } }
```

The CLI is the same binary that backs MCP, so any host with shell access already has full unbrowse — MCP just makes the surface discoverable as typed tools.

## Help

- Repo: https://github.com/unbrowse-ai/unbrowse
- Docs: https://unbrowse.ai
- Issues: https://github.com/unbrowse-ai/unbrowse/issues

---

**NOTE — historical:** Earlier versions of this skill (≤ v6.14.0) declared themselves deprecated in favor of MCP-only. That guidance is reversed as of v7.1.0 (2026-05-27): the CLI is the primary agent surface, the MCP server is an equal alternative, and shell-only environments (subagents, CI, /carmack, /debug) should reach for `unbrowse <cmd>` directly.
