# Browser Automation

## Choosing the Right Tool

| Situation | Tool |
|-----------|------|
| **Debugging a live page** (logged in, real data, current state) | **chrome-cdp** <- prefer this |
| **Testing a fresh URL** (headless, no session needed) | agent-browser |
| **Performance tracing** (Core Web Vitals, traces) | chrome-devtools-mcp |

**chrome-cdp connects to your actual running Chrome session** -- tabs already open, cookies intact, no re-login. Use it first when debugging or inspecting real pages.

## chrome-cdp (Live Chrome Session -- Preferred for Debugging)

```bash
CDP="node ~/.claude/skills/chrome-cdp/scripts/cdp.mjs"

$CDP list                           # List all open tabs (shows targetId prefixes)
$CDP snap   <targetPrefix>          # Accessibility tree (best for page structure)
$CDP eval   <targetPrefix> "expr"   # Run JS in page context
$CDP shot   <targetPrefix>          # Screenshot -> /tmp/screenshot.png
$CDP html   <targetPrefix> ".sel"   # HTML of element matching selector
$CDP click  <targetPrefix> ".sel"   # Click element by CSS selector
$CDP type   <targetPrefix> "text"   # Type at focused element
$CDP nav    <targetPrefix> <url>    # Navigate and wait for load
$CDP net    <targetPrefix>          # Network resource timing
$CDP stop                           # Stop all daemons
```

**Prerequisite:** Chrome must have remote debugging enabled at `chrome://inspect/#remote-debugging`. Once enabled, the daemon per tab persists 20min -- "Allow debugging" modal fires once per tab.

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
