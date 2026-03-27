# Global Claude Code Configuration

## Git Pre-Flight Rule (MANDATORY)

**ALWAYS run `git status` BEFORE any of these commands:**
- `git commit` - verify staging
- `git push` - verify commits exist
- `git pull` - check for uncommitted changes
- `git checkout/switch` - check dirty state
- `git merge/rebase` - verify clean tree
- `git reset` - understand impact

```bash
# Pattern: Always check first
git status && git <command>
```

See `/git-preflight` skill for full checklist.

## GitHub API Rate Limit Rule (MANDATORY)

**ALWAYS use `gh api` for GitHub API calls instead of unauthenticated `curl`/HTTP requests.**

- Unauthenticated: 60 requests/hour (hits rate limits fast)
- Authenticated via `gh` CLI: 5,000 requests/hour

```bash
# WILL HIT RATE LIMITS - unauthenticated
curl -s https://api.github.com/repos/owner/repo/releases/latest

# CORRECT - authenticated via gh CLI
gh api repos/owner/repo/releases/latest --jq '.tag_name'
```

When writing code that calls GitHub APIs (Rust, Python, JS, shell scripts):
1. **Check for `gh` CLI first** (`which gh`)
2. **Use `gh api`** for version checks, release lookups, repo queries
3. **Fall back gracefully** if `gh` is not installed (skip or warn, don't error)
4. **For tools with built-in updaters** (e.g., yt-dlp): use `gh api` to get the version tag, then pass it to the tool's `--update-to` flag to avoid the tool's own unauthenticated API calls

## Tool Integration Template

<!-- Add your tool integrations here. Example format:

### Your Tool Name
| App | Action | Usage |
|-----|--------|-------|
| **ServiceName** | `action-name <args>` | Description of what it does |

### Shortcuts
```bash
your-tool-cli list          # List resources
your-tool-cli status        # Check health
your-tool-cli execute ACTION '{"key":"val"}'  # Run action
```
-->

## Long-Running Agent Communication Rule (MANDATORY)

**ALWAYS tell the user what's about to happen BEFORE launching a subagent via the Task tool.** Long-running agents (ship, carmack, ralph) can take 3-10+ minutes. If the user sees nothing during that time, they'll think the process is stuck and cancel -- losing completed work.

**Before every Task tool invocation, print a brief message:**
- What the agent will do (1 sentence)
- Approximate duration ("typically takes 3-7 minutes", "may take several minutes")
- That they'll see results when it finishes

Example: "Deploying to production. This runs 12+ quality gates and typically takes 3-7 minutes. You'll see the results when it finishes."

**Never launch a long-running subagent silently.**

## Quick Commands

### Skills (Slash Commands)
- `/carmack [issue]` - Universal engineering: build features, fix bugs, deep debugging
- `/ship` - Safe production deployment with quality gates and safety audits
- `/browser` - Browser automation docs
- `/ralph [feature]` - Autonomous feature implementation
- `/code-review` - AI-powered code review
- `/typescript-react-reviewer` - React 19 + TypeScript expert review
- `/git-safety [mode]` - Git security: scan, clean, prevent
- `/git-preflight` - **INTERNAL**: Pre-flight checks before git commands
- `/visualise` - Render inline interactive visuals — SVG diagrams, HTML widgets, charts, flowcharts, explainers

### CLI Tools (available to all agents)

**ogrep** — AST-aware code search (fulltext mode, no API key needed)
```bash
ogrep index .                                    # Index codebase (first time per project)
ogrep query "where is auth handled" --mode fulltext  # Keyword search
ogrep query "error handling" -n 10               # More results
```

**qmd** — Local semantic search for docs/notes (models auto-download, no API key)
```bash
qmd collection add ~/project/docs --name docs    # Add collection
qmd embed                                         # Build embeddings
qmd query "how does deployment work"              # Hybrid search
```

**bd** — Task tracking with dependency graphs (beads)
```bash
bd create "task description" -p 1                 # Create task (priority 1)
bd list                                            # Show tasks
bd ready                                           # Show unblocked tasks
bd done <id>                                       # Complete task
bd dep add <child> <parent>                        # Add dependency
```

## Core Skills & Agents

| Name | Use When | Invoke |
|------|----------|--------|
| `ship` (skill) | Ready to deploy to production | `/ship` or "ship my changes" |
| `carmack-mode-engineer` | Build features, fix bugs, deep debugging | `/carmack` or "use carmack" |
| `git-safety` | Check for secrets, clean history | `/git-safety` |
| `git-preflight` | **AUTO**: Before ANY git command | Used internally |

## React "X is not defined" Error - Quick Fix Guide

**This is the #1 production crash cause.** When you see "X is not defined" in React:

### Root Cause
Inner/child component references a variable from parent scope without receiving it as a prop.

### How to Fix
1. **Find the component** where the error occurs (check component stack)
2. **Identify the undefined variable** (e.g., `precedentInfo`)
3. **Check if it's passed as a prop** - if not, that's the bug
4. **Either pass it as a prop or move the code** to where the variable exists

### Quick Detection
```bash
# Find nested components that might reference parent scope
grep -n "const.*= (" components/*.tsx | grep -v "export"

# Find variables used without optional chaining
grep -rn "{[a-z][a-zA-Z]*\." --include="*.tsx" | grep -v "\?."
```

### Prevention Checklist
- [ ] Child components ONLY use: props, local state, imports, context
- [ ] All nullable values have `?.` optional chaining
- [ ] No inline component definitions that close over parent state

Full investigation: `/carmack` | Deploy gate: `/ship` Gate 6

## Silent React Startup Failure - Quick Fix Guide

**This is the #2 production crash cause.** React silently fails to mount — only SSR/SEO fallback HTML visible, zero console errors.

### Symptoms
- Page loads but shows only static HTML (SEO fallback)
- `#root` div is empty or has no React content
- Zero errors in console, network tab looks normal
- Works locally but fails in production (or vice versa)

### Root Cause
Module-level code (like `validateClientEnv()`) throws BEFORE React mounts. The error is swallowed because it happens during module evaluation, not inside React's error boundary.

### Quick Detection
```bash
# 1. Find module-level code that throws before React mounts
grep -n "throw\|throw new Error" src/react-app/App.tsx src/shared/envValidation.ts

# 2. Find validation calls at module scope (before component definition)
grep -Bn5 "export default function\|export function App" src/react-app/App.tsx | grep "validate\|throw\|assert"

# 3. Check if env vars used in code have fallbacks
grep -rn "import.meta.env.VITE_" --include="*.ts" --include="*.tsx" src/ | grep -v node_modules

# 4. Browser console: manually try importing the module
# In Chrome DevTools console:
# import('/src/react-app/App.tsx').catch(e => console.error('Module failed:', e))
```

### Fix Pattern
```typescript
// WILL SILENTLY KILL REACT - throws before mount
validateClientEnv();
const KEY = import.meta.env.VITE_KEY || "fallback";

// CORRECT - validation knows about fallbacks, won't throw
validateClientEnv({ VITE_KEY: "fallback" });
const KEY = import.meta.env.VITE_KEY || "fallback";
```

### Prevention Checklist
- [ ] All `validateClientEnv()` calls pass fallbacks for vars that have hardcoded defaults
- [ ] No `throw` statements at module scope without try/catch
- [ ] After deploy: verify `#root` has React content (not just SEO fallback)
- [ ] `.env.local` changes are documented in `.env.example`

Full investigation: `/carmack` | Deploy gate: `/ship` Gate 7

## SEO Fallback FOUC (Flash of Unstyled Content) - Quick Fix Guide

**This is the #4 production UX issue.** SSR/SEO fallback HTML flashes visibly before React mounts.

### Root Cause
SEO fallback content is visible by default and hidden by JS after load — but JS loads after HTML renders, causing a flash.

### Quick Detection
```bash
# Check if SEO fallback depends on JS to hide
grep "data-app-loaded\|data-loaded" index.html
# If these control SEO visibility → FOUC bug

# Verify CSS hides it by default
grep -A3 "\.seo-fallback" index.html | grep "display.*none"
```

### Fix Pattern
```html
<!-- FOUC: JS-dependent hiding -->
<style>body[data-app-loaded="true"] .seo-fallback { display: none; }</style>

<!-- CORRECT: CSS hidden by default, noscript reveals for no-JS users -->
<style>.seo-fallback { display: none; }</style>
<noscript><style>.seo-fallback { display: block !important; }</style></noscript>
```

### Prevention Checklist
- [ ] SEO fallback has `display: none` in CSS (no JS dependency)
- [ ] `<noscript>` block reveals fallback for no-JS accessibility
- [ ] Worker serves separate pre-rendered HTML for bot user-agents
- [ ] After deploy: verify no text flash on page load

Full investigation: `/carmack` | Deploy gate: `/ship` Gate 7.5

## Rust Project Development

### Pre-Push (MANDATORY for multi-platform Rust CI)
```bash
cargo fmt --all -- --check       # Formatting (CI rejects any diff)
cargo clippy --all-targets       # Lints (warnings = errors in CI)
```

### Common Traps
- **`deny_unknown_fields`** + removed config keys = crash for existing users. Add ignored stubs instead.
- **`#[cfg(target_os)]`** blocks: variables only mutated inside cfg blocks need `#[allow(unused_mut)]`
- **i18n strict checking**: New strings need ALL locales, not just English
- **Homebrew vs cargo**: `brew unlink <tool>` when testing local `cargo install --path .` builds

### CI Debugging (when local grep fails)
```bash
gh run view <RUN_ID> --log-failed       # Actual CI failure logs
gh pr checks <PR_NUMBER> --watch        # Monitor checks live
```

### Fork Mass-Integration
1. Audit PRs/issues (`gh pr list`, `gh issue list`)
2. Merge bot/dependency PRs first, then simple features, then complex refactors
3. Batch issue fixes by theme, run CI after each batch
4. Test locally with YOUR existing config (backwards compat bugs hide here)

## Browser Automation
```bash
agent-browser open <url>
agent-browser snapshot -i -c    # AI-optimized element refs
agent-browser click @e2         # Interact by ref
agent-browser screenshot
```

## Debug Session Persistence

Investigations saved to `tools/debug-sessions/{issue-name}/`:
- `{issue-name}-state.md` - Phase & findings
- `{issue-name}-evidence.md` - Logs & traces
- `{issue-name}-hypothesis.md` - Tested theories

Resume: "Resume the {issue-name} investigation"

## Safety Audit Tiers

| Tier | Checks | Invoke |
|------|--------|--------|
| 1 | Silent failures, security, tests | `/ship` (always runs) |
| 2 | Blind spots, test quality, rate limits | `/ship --audit tier2` |
| 3 | Code archaeology, critical paths | `/ship --audit tier3` |
