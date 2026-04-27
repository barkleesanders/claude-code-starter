# Global Claude Code Configuration

## Read-Before-Edit Rule (MANDATORY for agents)

**The Edit tool requires that the file has been Read with the Read tool in the current session. `cat`, `head`, `tail`, `grep`, and even `Write` do NOT count. Only the Read tool counts.**

- **Always Read before Edit** — even if you just created the file with Write.
- **If you see `File has not been read yet`** — that means you haven't called Read on that exact path in this session. Fix: call Read, then retry Edit.
- **PreToolUse hook warns** — `~/.claude/skills/hooks/pre-edit-check.sh` prints a reminder if you Edit a file that wasn't tracked as Read. Advisory only; won't block.
- **File-read tracking** — `~/.claude/skills/hooks/track-file-reads.sh` (PostToolUse on Read/Write/Edit/NotebookEdit) maintains `/tmp/claude-file-reads/<session>.txt`.

Pattern for creating then editing:
```
Write(file_path="/path/new.md", content="...")   # create
Read(file_path="/path/new.md")                   # MANDATORY before Edit
Edit(file_path="/path/new.md", old_string="foo", new_string="bar")  # now works
```

## Beads Task Tracking Rule (MANDATORY)

**ALWAYS use `bd` (beads) for ALL task tracking. NEVER use TodoWrite, TaskCreate, or markdown files for tracking work.**

### Core commands (use daily)

- **Before coding**: `bd create --title="What you're doing" --description="Why" --type=task|bug|feature --priority=2`
- **Starting work**: `bd update <id> --claim`
- **Done**: `bd close <id>` (close multiple: `bd close <id1> <id2> ...`)
- **Find work**: `bd ready` (unblocked), `bd list --status=open` (all open)
- **Dependencies**: `bd dep add <child> <parent>` (types: `blocks`, `related`, `parent`, `duplicate`)
- **Persistent notes**: `bd remember "insight"` (NOT MEMORY.md)
- **Park for later**: `bd defer <id>` (restore with `bd undefer`)
- **Park-then-clear**: avoid `--status=pending` (not valid — use `open` or `deferred`)

### Labels (use for cross-cutting taxonomy)

Apply labels for fast filtering. Current taxonomy:

| Category | Examples |
|---|---|
| `domain:*` | `domain:legal`, `domain:records`, `domain:aiva`, `domain:va`, `domain:finance`, `domain:infra`, `domain:journalism`, `domain:personal` |
| `area:*` | `area:cpra`, `area:foia`, `area:cloudflare`, `area:vps`, `area:mac`, `area:drive` |
| `workflow:*` | `workflow:records-request`, `workflow:bill-track`, `workflow:va-claim`, `workflow:deploy`, `workflow:browser-test` |
| `actor:*` | `actor:agent`, `actor:human` |
| `template` | Formula/molecule template issues |

Commands:
- `bd label add <id> domain:legal` — add label
- `bd label list <id>` — see labels on issue
- `bd label list-all` — see all labels in DB
- `bd query 'labels includes "domain:legal" AND status=open'` — filter

### Molecules (work templates for repeatable workflows)

Pre-built templates in `~/.beads/formulas/`:

| Formula | Use for |
|---|---|
| `records-request` | CPRA/FOIA lifecycle (draft → file → track → receive → analyze → followup) |
| `bill-track` | Track CA/federal bill through committees, votes, final action |
| `va-claim` | VA disability claim lifecycle (evidence → nexus → submit → C&P → decision) |
| `ship-deploy` | /ship deployment with gates, audit, verify (vapor phase — ephemeral) |

Spawn a template:
```bash
bd mol pour records-request --var agency=SFPUC --var subject="Treasure Island outages" --var jurisdiction=sf --var filer_entity="ESBE Inc"
# Creates 6 linked issues with the full CPRA workflow, ready to work
```

List available: `bd formula list` · Inspect: `bd formula show <name>`

### Epic / Swarm (multi-issue projects)

For work spanning 5+ issues with shared goal:
- `bd create --type=epic ...` — epic parent
- `bd dep add <child> <epic> --type parent` — link children
- `bd epic status` — overview
- `bd epic close-eligible` — auto-close epics whose children are all done
- `bd children <epic-id>` — list issues under an epic

### Agent attribution

The `BEADS_ACTOR` env var tags writes with who did them:
- Human: `export BEADS_ACTOR="<you>"` (set in `~/.zshrc`)
- Agent: override inline: `BEADS_ACTOR="claude" bd create ...`

View history: `bd history <id>` shows actor per change.

### Backup

Local filesystem backup runs **daily at 4:23am via launchd**:
- Script: `~/tools/beads-backup.sh`
- Destination: `~/.beads/backups/beads-YYYYMMDD-HHMM.db` (+.jsonl export)
- Retention: 14 days
- Manual run: `~/tools/beads-backup.sh`

For cloud backup, see `bd backup init https://doltremoteapi.dolthub.com/...` (requires Dolt backend).

### Bootstrap a new repo

```bash
cd /path/to/repo
git config beads.role maintainer
bd config set issue_prefix PROJ
```

### Priority

0-4 (0=critical, 4=backlog). NOT "high"/"medium"/"low".

### Query language (bd query)

```bash
bd query 'status=open AND priority<=1'               # urgent open work
bd query 'labels includes "workflow:records-request"' # all CPRA work
bd query 'updated_at > 7d ago'                       # recent activity
bd query 'owner="<you>" AND status=in_progress'   # my active work
```

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
# ❌ WILL HIT RATE LIMITS — unauthenticated
curl -s https://api.github.com/repos/owner/repo/releases/latest

# ✅ CORRECT — authenticated via gh CLI
gh api repos/owner/repo/releases/latest --jq '.tag_name'
```

When writing code that calls GitHub APIs (Rust, Python, JS, shell scripts):
1. **Check for `gh` CLI first** (`which gh`)
2. **Use `gh api`** for version checks, release lookups, repo queries
3. **Fall back gracefully** if `gh` is not installed (skip or warn, don't error)
4. **For tools with built-in updaters** (e.g., yt-dlp): use `gh api` to get the version tag, then pass it to the tool's `--update-to` flag to avoid the tool's own unauthenticated API calls

## Email Sending Rule (MANDATORY)

**When the user tells you to send an email from a specific address, USE THAT ADDRESS. Do not substitute a different sender.**

- **From <you>@example.com**: Use `GMAIL_SEND_EMAIL` via Composio
- **From help@<your-domain.com>**: Use `RESEND_SEND_EMAIL` via Composio
- **NEVER send from a different address than what the user specified**
- **NEVER use Resend when the user says "send from my Gmail"** — Resend cannot send from gmail.com

```bash
# Send from personal Gmail (<you>@example.com)
node ~/tools/composio/composio-client.cjs execute GMAIL_SEND_EMAIL '{"recipient_email":"to@example.com","subject":"Subject","body":"Body text"}'

# Send from AIVA (help@<your-domain.com>)
node ~/tools/composio/composio-client.cjs send-email "to@example.com" "Subject" "Body text"
```

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
- `/medicaid-audit <NPI>` - Audit Medicaid providers for billing anomalies, generate OIG complaints
- `/visualise` - Render inline interactive visuals — SVG diagrams, HTML widgets, charts, flowcharts, explainers

### CLI Tools (available to all agents)

**osgrep** — AST-aware code search (fulltext mode, no API key needed)
```bash
osgrep index .                                    # Index codebase (first time per project)
osgrep query "where is auth handled" --mode fulltext  # Keyword search
osgrep query "error handling" -n 10               # More results
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
// ❌ WILL SILENTLY KILL REACT — throws before mount
validateClientEnv();
const KEY = import.meta.env.VITE_KEY || "fallback";

// ✅ CORRECT — validation knows about fallbacks, won't throw
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
<!-- ❌ FOUC: JS-dependent hiding -->
<style>body[data-app-loaded="true"] .seo-fallback { display: none; }</style>

<!-- ✅ CORRECT: CSS hidden by default, noscript reveals for no-JS users -->
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

See memory file `rust-patterns.md` for detailed patterns.

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

## Document Fabrication Prevention (MANDATORY for all generated documents)

**When generating or auditing any document containing facts about real people, cases, or organizations**, apply these checks. Discovered from auditing legal filings (April 2026) — AI fabricated case citations, phone numbers, and a person who doesn't exist.

### The Five Fabrication Patterns

| Pattern | Real Example Found | Detection |
|---------|-------------------|-----------|
| **Fabricated case citations** | `In re S.B., 72 Misc.3d 1205(A)` — not in any source | Grep for citation patterns, verify each against source |
| **Fabricated phone numbers** | Dr. Levine's phone `<REDACTED-PHONE>` — not in any source (had email only) | Grep all phone numbers, verify each in source |
| **Completely fabricated people** | `Dr. Douglas A. Rahner` as PCP — didn't exist in any source doc | Every person named must appear in source or be user-stated |
| **Party name transposition** | Petitioner called `<you> Shaquille-Ali` (AIP's middle name) | Grep every party name occurrence, verify full name |
| **Exhibit cross-reference drift** | Para 10 said "Exhibit A" for item that was renumbered to Exhibit B | Extract all "Exhibit X" refs, compare against exhibit list |

### Quick Verification Sweep

```bash
python3 << 'EOF'
import re
doc = open('document.txt').read()
print("PHONES:", re.findall(r'\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}', doc))
print("CITATIONS:", re.findall(r'\d+\s+[A-Z][a-z]+\.\w+\s+\d+', doc))
print("DOCTORS:", list(set(re.findall(r'Dr\. [A-Z][a-z]+ [A-Z][a-z]+', doc))))
print("EXHIBITS:", re.findall(r'Exhibit [A-Z]', doc))
EOF
```

### Hard Rules
- **Never add a phone number** unless it appears in a source document
- **Never add a case citation** unless it appears in a source document the user provided
- **Never name a person** who doesn't appear in source documents (or wasn't named by user)
- **Every "Exhibit X" reference** must match the exhibit list in the same document
- When in doubt: omit the fact, don't invent it

For full audit procedure: `/carmack` → loads `legal-document-audit.md`

---

# 1. Verify www redirects at edge (should return 301)
curl -sI "https://www.<your-domain.com>" | grep -E "^(HTTP|location)"
# Expected: HTTP/2 301, location: https://<your-domain.com>/

# 2. Verify path + query preservation
curl -sI "https://www.<your-domain.com>/dashboard?ref=test" | grep location
# Expected: location: https://<your-domain.com>/dashboard?ref=test

# 3. Check Cloudflare ruleset exists
TOKEN="<your-token>"
ZONE_ID="<CF_ZONE_ID>"
curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.result.rules'
```

### Fix Command (if redirect missing)
```bash
TOKEN="<your-dynamic-redirect-token>"
ZONE_ID="<CF_ZONE_ID>"
RULESET_ID=$(curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/phases/http_request_dynamic_redirect/entrypoint" \
  -H "Authorization: Bearer ${TOKEN}" | jq -r '.result.id')

curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/rulesets/${RULESET_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "description": "WWW Redirect Rules",
    "rules": [{
      "expression": "(http.host eq \"www.<your-domain.com>\")",
      "description": "Redirect www to non-www",
      "action": "redirect",
      "action_parameters": {
        "from_value": {
          "status_code": 301,
          "target_url": {
            "expression": "concat(\"https://<your-domain.com>\", http.request.uri.path)"
          },
          "preserve_query_string": true
        }
      }
    }]
  }'
```

### Required Token Permissions
- Zone → Dynamic URL Redirects → Write
- Zone → Zone Rulesets → Edit


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
