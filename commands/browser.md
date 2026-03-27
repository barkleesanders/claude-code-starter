# Browser Automation Skill

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
