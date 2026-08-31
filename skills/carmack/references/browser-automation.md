# Browser Automation

## Choosing the Right Tool (decision ladder)

**Default = `fcdp`** for driving the user's REAL logged-in Chrome. `fcdp` (`~/tools/fcdp/fcdp`,
`/chrome` Step 0) is the ONE tool: full CDP on the real Default profile — everyday driving
(`open/read/find/click/type/fill/nav/js/shot/wait`) AND the advanced domains (`pdf/intercept/
throttle/trace/raw`). No clone, no consent popups, tabId optional. It replaced the old `:9222`
clone subsystem and the `chrome-cdp` skill entirely (both REMOVED 2026-07-14); `ccb` (Claude-for-
Chrome extension, curated subset) is the fallback when fcdp's bridge is down. Per-tab: only one
`chrome.debugger` client per tab — give fcdp its own tab. Ref: memory `reference_fcdp_full_cdp.md`.

| Situation | Tool |
|-----------|------|
| **Drive the user's REAL logged-in Chrome** (read/click/fill/js + intercept/throttle/trace/PDF) | **`fcdp`** (primary — `/chrome`) |
| **fcdp bridge down, or a second tab needs driving concurrently** | **`ccb`** (`~/tools/claude-browser/ccb`) |
| **Page never reaches "network idle" / DOM re-renders mid-action** (MCP `navigate`/`evaluate_script` time out; `fill` says *"element no longer exists"*; perpetual spinner; ASP.NET WebForms / RentCafe / SecureCafe) | **`cdp-fill`** (raw CDP — see below) |
| **Testing a fresh URL** (headless, no session needed) | agent-browser |
| **Unauthenticated/WAF-gated fetch → clean markdown** | unbrowse (`unbrowse fetch <url>`) |
| **Performance tracing** (Core Web Vitals, traces) | `fcdp trace`, or chrome-devtools-mcp |

**Hard rails (all browser tools):** never bypass Cloudflare/CAPTCHA/bot-detection; never auto-fill **SSN / government-ID / payment / signature**; never auto-**submit** a form on the user's behalf — show content + get approval first. unbrowse spawns its OWN browser (hits Cloudflare on gated sites) — for an already-open, already-past-Cloudflare tab, use `fcdp`/`ccb` or `cdp-fill`, NOT unbrowse.

**fcdp connects to your actual running Chrome session** -- tabs already open, cookies intact, no re-login. Use it first when debugging or inspecting real pages.

### Two cross-cutting rules (WebFetch fallthrough + full-path calling)

- **WebFetch `403` / "response body not retrieved" / auth-required = a WAF bot-block, NOT a dead page.** The page loads fine in a real browser — fall through to `/chrome` (`fcdp`), which drives real Chrome AND runs page JS, so it reads the page and any JS-rendered tool a raw fetch can't. (Verified 2026-07-07: WebFetch 403'd health.ny.gov's "Find A Health Home By County" map; fcdp opened it, selected a county, and read the result.) **Distinguish from a real `404`/`410`** — that page is genuinely gone; don't waste a browser round-trip retrying it.
- **`fcdp` and `ccb` are NOT on PATH in the agent's non-interactive Bash shell** (no `~/.zshenv`/login PATH) — a bare `fcdp …`/`ccb …` returns `command not found` / `permission denied`. **Always call them by full path:** `~/tools/fcdp/fcdp …` and `~/tools/claude-browser/ccb …` (or `FCDP=~/tools/fcdp/fcdp; $FCDP …`). The bridge/extension are fine; only the PATH lookup fails.

---

## cdp-fill — fill forms on never-idle / re-rendering pages (raw CDP)

**When to reach for it:** chrome-devtools MCP (and Playwright/agent-browser) fail on pages that **never reach network-idle** (a tracking beacon or hanging XHR stays `[pending]`, so the MCP's wait-for-idle times out) AND/OR **re-render the form DOM** fast enough that MCP element handles (uids) detach between snapshot and fill (`"element with uid X no longer exists"` — fails even back-to-back). Classic offender: **Yardi RentCafe / SecureCafe** `oleapplication.aspx` (ASP.NET WebForms partial-postback loop).

**Why it works:** talks straight to Chrome DevTools Protocol via fcdp (real profile) and runs `Runtime.evaluate` — executes against the LIVE DOM **immediately** (no idle-wait), targeting fields by **stable `name`/`id`/`aria-label`** (immune to re-render). Tool: `~/tools/cdp-fill/cdp-fill.mjs` (on PATH as `cdp-fill`). Requires fcdp against the REAL Default profile (the user's logged-in profile, already past any Cloudflare check) and Node ≥21.

```bash
cdp-fill probe --match <url-substring>                 # dump every field: tag,name,id,label,value,disabled
cdp-fill fill  --match <url-substring> --values f.json  # set fields by name/id/aria; returns {ok,value|reason} per field
echo '{"FieldName":"value","StateSelect":"CA"}' | cdp-fill fill --match securecafe --values -
cdp-fill eval  --match <url-substring> --expr "<js returning a string>"   # e.g. read a <select>'s options
```

- SELECT matches by option **value OR visible text** (e.g. a state dropdown's option is often `"CA"`, not `"California"` — probe/eval the options first).
- `fill` readback is built-in closed-loop verification — confirm each field's returned `value` matches intent.
- It's `.mjs` (use `import`, not `require`). Probe first to get the real `name=` attributes (visual labels lie — e.g. a field labelled "Apartment Community" was actually `name=ManagementCompany` = "Landlord Email").
- **Never** put SSN/ID/payment/signature through it; never auto-submit.

Reference incident (2026-06-01): Mission Rock/Verde RentCafe leasing app blocked chrome-devtools MCP (eval/navigate timeout; `fill` stale-handle even back-to-back) and unbrowse (its own browser hit Cloudflare). `cdp-fill` filled + readback-verified the current-residence block in one shot. Full write-up: `~/tools/cdp-fill/README.md`, memory `reference_cdp_fill_tool.md`.

## fcdp (Live Chrome Session -- Preferred for Debugging)

```bash
FCDP=~/tools/fcdp/fcdp

$FCDP tabs                          # List all open tabs -> tabId, url, title
$FCDP read   [tab]                  # Interactive-element outline (best for page structure)
$FCDP js     [tab] "expr"           # Run JS in page context
$FCDP shot   [tab] [file.png]       # Screenshot
$FCDP find   [tab] "<css|text>"     # Matching elements -> tag, text, coords
$FCDP click  [tab] <css|text|x,y>   # Click element by selector, visible text, or coords
$FCDP type   [tab] "text"           # Type at focused element
$FCDP nav    [tab] <url>            # Navigate
$FCDP intercept [tab] [secs]        # Network capture (Fetch.enable + reload)
$FCDP close  [tab]                  # Close the tab
```

**Prerequisite:** the fcdp Chrome extension must be loaded once (`chrome://extensions` → Load-unpacked `~/tools/fcdp/extension`) and the bridge running (`launchctl kickstart -k gui/$(id -u)/com.barklee.fcdp-bridge` if `bridge socket not found`). No `--remote-debugging-port` flag, no clone profile — it rides `chrome.debugger` on the REAL Default profile.

---

## agent-browser (Headless -- for Fresh Sessions / E2E Tests)

Uses Vercel's `agent-browser` CLI -- headless browser automation designed for AI agents with ref-based element selection.

### Setup Check

```bash
# Check installation
command -v agent-browser >/dev/null 2>&1 && echo "Installed" || echo "NOT INSTALLED"

# Install if needed
npm install -g agent-browser
agent-browser install  # Downloads Chromium
```

### Core Workflow

1. **Navigate** to URL
2. **Snapshot** to get interactive elements with refs
3. **Interact** using refs (@e1, @e2, etc.)
4. **Re-snapshot** after navigation or DOM changes

```bash
# Step 1: Open URL
agent-browser open https://example.com

# Step 2: Get interactive elements with refs
agent-browser snapshot -i --json

# Step 3: Interact using refs
agent-browser click @e1
agent-browser fill @e2 "search query"

# Step 4: Re-snapshot after changes
agent-browser snapshot -i
```

### Key Commands

**Navigation:**
```bash
agent-browser open <url>       # Navigate to URL
agent-browser back             # Go back
agent-browser forward          # Go forward
agent-browser reload           # Reload page
agent-browser close            # Close browser
```

**Snapshots (Essential for AI):**
```bash
agent-browser snapshot              # Full accessibility tree
agent-browser snapshot -i           # Interactive elements only (recommended)
agent-browser snapshot -i --json    # JSON output for parsing
agent-browser snapshot -c           # Compact (remove empty elements)
agent-browser snapshot -d 3         # Limit depth
```

**Interactions:**
```bash
agent-browser click @e1                    # Click element
agent-browser dblclick @e1                 # Double-click
agent-browser fill @e1 "text"              # Clear and fill input
agent-browser type @e1 "text"              # Type without clearing
agent-browser press Enter                  # Press key
agent-browser hover @e1                    # Hover element
agent-browser check @e1                    # Check checkbox
agent-browser uncheck @e1                  # Uncheck checkbox
agent-browser select @e1 "option"          # Select dropdown option
agent-browser scroll down 500              # Scroll
agent-browser scrollintoview @e1           # Scroll element into view
```

**Get Information:**
```bash
agent-browser get text @e1          # Get element text
agent-browser get html @e1          # Get element HTML
agent-browser get value @e1         # Get input value
agent-browser get attr href @e1     # Get attribute
agent-browser get title             # Get page title
agent-browser get url               # Get current URL
agent-browser get count "button"    # Count matching elements
```

**Screenshots & PDFs:**
```bash
agent-browser screenshot                      # Viewport screenshot
agent-browser screenshot --full               # Full page
agent-browser screenshot output.png           # Save to file
agent-browser pdf output.pdf                  # Save as PDF
```

**Wait:**
```bash
agent-browser wait @e1              # Wait for element
agent-browser wait 2000             # Wait milliseconds
agent-browser wait "text"           # Wait for text to appear
```

### Semantic Locators (Alternative to Refs)

```bash
agent-browser find role button click --name "Submit"
agent-browser find text "Sign up" click
agent-browser find label "Email" fill "user@example.com"
agent-browser find placeholder "Search..." fill "query"
```

### Sessions (Parallel Browsers)

```bash
agent-browser --session browser1 open https://site1.com
agent-browser --session browser2 open https://site2.com
agent-browser session list
```

### Debug Mode

```bash
# Run with visible browser window
agent-browser --headed open https://example.com
agent-browser --headed snapshot -i
```

### Example: Login Flow

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i
# Output shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Sign in" [ref=e3]
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait 2000
agent-browser snapshot -i  # Verify logged in
```

### JSON Output

```bash
agent-browser snapshot -i --json
# Returns: { "success": true, "data": { "refs": { "e1": {"name": "Submit", "role": "button"} } } }
```
