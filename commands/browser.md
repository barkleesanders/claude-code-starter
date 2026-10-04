# Browser Automation Skill

## Tool Selection

| Use case | Tool |
|----------|------|
| **Live page debugging** (logged-in, real data, current state) | **fcdp** (`/chrome`) ← prefer |
| **E2E / headless testing** (fresh session, no login needed) | agent-browser |
| **Performance tracing** (Core Web Vitals, traces) | `fcdp trace` / `fcdp throttle` (real profile) or chrome-devtools-mcp on a disposable browser |

### fcdp — your REAL logged-in Chrome (Preferred; full recipe in `/chrome`)

Drives the actual Default profile through our own extension + bridge: tabs already open,
cookies intact, no re-login, no clone. The old `chrome-cdp` (`cdp.mjs`, `:9222`) was REMOVED
2026-07-14 — do not use it.

```bash
F=~/tools/fcdp/fcdp                # NOT on PATH in the agent shell — full path
$F tabs                            # list tabs -> tabId,url,title
$F open <url> [--reuse]            # new tab (cached active); --reuse re-navigates an existing one
$F read | text | find "<css|text>" | shot [file.png]
$F click "<css|text|x,y>" | type "<text>" | fill "<css>" "<v>" | key Enter | nav <url>
$F js "<code>" | wait "<jsExpr>" [ms]
$F console --secs 8 --reload | network --secs 8 --reload
$F pdf | intercept --secs 5 | throttle | trace | raw <CDP.Method> '<json>'
```

**Prereq:** the launchd bridge `com.barklee.fcdp-bridge` running (`bridge socket not found` →
see `/chrome` Step 0). Unattended/concurrent runs use `fcdp-job <url> <cmd…>` for an isolated tab.

---

### agent-browser — Headless Chromium (for Fresh Sessions)

Use `agent-browser` CLI to automate browser interactions for testing, scraping, and verification.

## Quick Reference

### Navigation
```bash
agent-browser open <url>          # Navigate to URL
agent-browser back                # Go back
agent-browser forward             # Go forward
agent-browser reload              # Reload page
```

### Get Page State (AI-Optimized)
```bash
agent-browser snapshot            # Get accessibility tree with @refs (BEST FOR AI)
agent-browser snapshot -i         # Interactive elements only (buttons, inputs, links)
agent-browser snapshot -c         # Compact mode (remove empty elements)
agent-browser snapshot -i -c      # Both: interactive + compact
```

### Interact with Elements (use @refs from snapshot)
```bash
agent-browser click @e2           # Click element by ref
agent-browser fill @e3 "text"     # Fill input field
agent-browser type @e4 "text"     # Type into element
agent-browser check @e5           # Check checkbox
agent-browser select @e6 "value"  # Select dropdown option
agent-browser hover @e7           # Hover over element
```

### Get Information
```bash
agent-browser get text @e1        # Get element text
agent-browser get html @e1        # Get element HTML
agent-browser get title           # Get page title
agent-browser get url             # Get current URL
agent-browser get value @e1       # Get input value
```

### Screenshots & PDFs
```bash
agent-browser screenshot          # Take screenshot
agent-browser screenshot -f       # Full page screenshot
agent-browser screenshot out.png  # Save to specific path
agent-browser pdf output.pdf      # Save as PDF
```

### Keyboard & Mouse
```bash
agent-browser press Enter         # Press key
agent-browser press Control+a     # Key combo
agent-browser mouse move 100 200  # Move mouse
```

### Sessions (for parallel testing)
```bash
agent-browser --session test1 open site.com
agent-browser --session test2 open other.com
agent-browser session list        # List active sessions
```

### Wait & Scroll
```bash
agent-browser wait @e1            # Wait for element
agent-browser wait 2000           # Wait 2 seconds
agent-browser scroll down 500     # Scroll down 500px
agent-browser scrollintoview @e1  # Scroll element into view
```

### Network & Storage
```bash
agent-browser cookies get         # Get cookies
agent-browser storage local get   # Get localStorage
agent-browser network requests    # View network requests
```

## Workflow Example

1. Open page and get snapshot:
```bash
agent-browser open https://example.com
agent-browser snapshot -i -c
```

2. Parse the output to find element refs like @e1, @e2, etc.

3. Interact using refs:
```bash
agent-browser fill @e3 "user@example.com"
agent-browser fill @e4 "password123"
agent-browser click @e5
```

4. Verify result:
```bash
agent-browser snapshot -i
agent-browser get url
agent-browser screenshot result.png
```

## For Subagents

When testing web applications:
1. Always start with `agent-browser snapshot -i -c` to get interactive elements
2. Use @refs from snapshot output for interactions
3. Take screenshots before and after important actions
4. Use `--session <name>` for parallel test isolation
