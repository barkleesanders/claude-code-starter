# Post-Deploy Verification & Monitoring

Covers Phase 4.1 (post-deploy verification), Phase 4.2 (multi-agent code review), Phase 4.3 (web performance audit), Phase 4.35 (visual regression check), Phase 4.5 (rollback), Phase 4.6 (CI gate), Phase 5 (monitoring), and Phase 6 (PR babysitter).

---

## Phase 4.1: POST-DEPLOY VERIFICATION

**Purpose**: Verify production deployment serves correct content after deploy.

### Part 0: Chrome CDP Live Screenshot (if available)

After deploy, take a screenshot of the live production site to visually verify:

```bash
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"
TARGET=$($CDP list 2>/dev/null | grep "$DEPLOY_URL" | awk '{print $1}' | head -1)

if [ -n "$TARGET" ]; then
  # Reload the page to pick up new deploy
  $CDP nav "$TARGET" "$DEPLOY_URL" 2>/dev/null
  sleep 3
  $CDP shot "$TARGET" 2>/dev/null
  echo "Screenshot saved to /tmp/screenshot.png — verify visually"
else
  echo "No Chrome tab open for $DEPLOY_URL — skipping visual check"
fi
```

If a tab is open and CDP daemon is warm, this gives instant visual verification with no popups. If not available, skip to curl checks.

### Part A: HTML Meta Tag Checks (curl)
```bash
# Verify twitter meta tags use name= (Twitter ignores property=)
curl -s "$DEPLOY_URL" | grep -i "twitter:" | head -10
# Verify og:image URL returns image content-type
OG_URL=$(curl -s "$DEPLOY_URL" | grep -oP 'og:image" content="\K[^"]+')
curl -sI "$OG_URL" | grep -E "^(HTTP|content-type)"
# Verify cache-bust param exists on image URLs
curl -s "$DEPLOY_URL" | grep -oP '(og|twitter):image" content="\K[^"]+'
```
- If `property=` on twitter tags: WARN — Twitter ignores them
- If no `?v=` param on image URLs: WARN — social platforms cache old images
- If image URL returns 404: Report error

### Part B: Visual Verification via agent-browser (CDP) — MANDATORY
```bash
# Open OG preview service
agent-browser open "https://www.opengraph.xyz"
sleep 2
agent-browser snapshot -i -c
agent-browser fill "@eN" "https://your-app.com"
agent-browser press Enter
sleep 5
agent-browser screenshot --path /tmp/og-preview-twitter.png
agent-browser scroll down 500
agent-browser screenshot --path /tmp/og-preview-full.png

# Also screenshot direct OG image
agent-browser open "https://your-app.com/images/og-social-card.png?v=20260306"
sleep 2
agent-browser screenshot --path /tmp/og-image-direct.png

# Trigger Twitter re-scrape
agent-browser open "https://x.com/intent/tweet?text=https://your-app.com"
sleep 3
```

**Fallback preview services** (if opengraph.xyz rate-limits):
1. `https://metatags.io/`
2. `https://socialsharepreview.com/`

### Part C: Download & Compare (When Card Shows Wrong Image)
```bash
# Download Twitter's cached card image
curl -s -o /tmp/twitter-cached.jpg "https://pbs.twimg.com/card_img/XXXXX/XXXXX?format=jpg&name=medium"
# Download what our server actually serves
curl -s -H "User-Agent: Twitterbot/1.0" -o /tmp/served.png "$(curl -s -H 'User-Agent: Twitterbot/1.0' https://your-app.com/ | grep -oP 'twitter:image" content="\K[^"]+')"
# Compare: if different = cache issue (add ?v=), if same = image file needs updating
```

### Two Cache Layers (Critical)
| Layer | What | Bust With |
|-------|------|-----------|
| **Page metadata** | og:image URL for page | Card Validator or `?v=N` on page URL |
| **Image CDN** | Image bytes at CDN | `?v=YYYYMMDD` on image URL in meta tags |

### Production Integration Tests (replaces CI `test-production` job)
```bash
# Run the same integration tests the CI ran against live production
timeout 60 TEST_BASE_URL=https://your-app.com npx vitest run tests/worker-integration.test.ts 2>&1
pkill -f vitest 2>/dev/null
# If fails: WARN (already deployed) — flag for investigation, do not auto-rollback
```

### Sitemap Live Check
```bash
# Verify production sitemap has no auth/noindex pages
curl -s "$DEPLOY_URL/sitemap.xml" | grep -E "sign-in|sign-up|dashboard|admin"
```

### WWW Redirect Check (if applicable)
```bash
curl -sI "https://www.$(echo $DEPLOY_URL | sed 's|https://||')" | grep -E "^(HTTP|location)"
```
If www returns 200 instead of 301, auth will break. Use Cloudflare MCP to update redirect ruleset.

### GitHub README Image Cache-Busting (if images changed)
```bash
CHANGED_IMAGES=$(git diff --name-only HEAD~1 | grep -E '\.(png|jpg|jpeg|gif|svg|webp)$' || true)
if [ -n "$CHANGED_IMAGES" ] && [ -f README.md ]; then
  for img in $CHANGED_IMAGES; do
    BASENAME=$(basename "$img")
    if grep -q "$BASENAME" README.md; then
      TODAY=$(date +%Y%m%d)
      sed -i.bak -E "s|(${BASENAME})(\?v=[0-9]+)?\"|\1?v=${TODAY}\"|g" README.md
      rm -f README.md.bak
      echo "Cache-busted $BASENAME in README.md"
    fi
  done
fi
```

---

## Phase 4.2: MULTI-AGENT CODE REVIEW (PRE-MERGE QUALITY GATE)

**Purpose**: Run parallel specialized code reviews before changes reach production. Catches security, performance, architecture, and mobile issues that single-pass reviews miss.

**Trigger**: Automatically when changes span 3+ files or touch security-sensitive paths (`src/worker/routes/`, `src/worker/middleware/`, auth, payment, or admin code). Skip for single-file copy/config changes.

**Execution**: Launch 3 parallel review agents using the Agent tool. Each agent gets the diff (`git diff HEAD~1`) and reviews from a different perspective:

1. **Security Reviewer** — XSS vectors, auth bypass, injection, secrets exposure, OWASP top 10
2. **Performance Reviewer** — N+1 queries, bundle size impact, unnecessary re-renders, memory leaks
3. **Mobile/UX Reviewer** — Responsive breakpoints, touch targets, text overflow at 375px, a11y

```
Launch 3 Agent tools in parallel (single message):
- Agent 1 (subagent_type: code-reviewer): "Review this diff for security issues: [diff]"
- Agent 2 (subagent_type: performance-oracle): "Review this diff for performance: [diff]"
- Agent 3 (subagent_type: general-purpose): "Review this diff for mobile/responsive issues at 375px: [diff]"
```

**Decision logic**:
- If ANY reviewer finds a CRITICAL issue: **BLOCK** deployment, display findings
- If only WARNings: Display findings, continue deployment
- If all clear: Continue silently

**Override**: `--skip-review` to bypass (logged to audit trail)

---

## Phase 4.3: WEB PERFORMANCE AUDIT (POST-DEPLOY)

**Purpose**: Baseline and monitor Core Web Vitals after every production deploy. Catches performance regressions before users notice.

**Trigger**: After successful deployment (Phase 4 complete). Runs automatically.

**Execution**: Use the `/web-perf` skill via Chrome DevTools MCP to measure production performance.

```
1. Open production URL in headless Chrome
2. Run Lighthouse audit (Performance category)
3. Capture Core Web Vitals:
   - FCP (First Contentful Paint) — target: < 1.8s
   - LCP (Largest Contentful Paint) — target: < 2.5s
   - TBT (Total Blocking Time) — target: < 200ms
   - CLS (Cumulative Layout Shift) — target: < 0.1
   - Speed Index — target: < 3.4s
4. Compare against previous baseline (if stored)
5. Flag regressions > 20% from baseline
```

**Display format**:
```
-- Phase 4.3: Web Performance --
Metric  | Current  | Target  | Status
--------|----------|---------|--------
FCP     | 1.2s     | < 1.8s  | PASS
LCP     | 2.1s     | < 2.5s  | PASS
TBT     | 150ms    | < 200ms | PASS
CLS     | 0.05     | < 0.1   | PASS
Score   | 85       | > 70    | PASS
```

**Decision logic**:
- Lighthouse score < 50: **WARN** — severe regression, consider rollback
- Lighthouse score 50-70: **WARN** — investigate before next deploy
- Lighthouse score > 70: PASS
- Any metric regression > 50% from previous: **WARN**

**Fallback**: If Chrome DevTools MCP is unavailable, skip with message: "Web perf audit skipped — run `/web-perf` manually to baseline."

---

## Phase 4.35: VISUAL REGRESSION CHECK (POST-DEPLOY)

**Purpose**: Screenshot the live production site at desktop and mobile viewports to catch visual regressions.

**Trigger**: After successful deployment, runs automatically if `agent-browser` or Chrome CDP is available.

**Execution**: Use `/test-browser` approach — screenshot key pages at multiple viewports.

```
1. Screenshot production at 3 viewports:
   a. Desktop (1440px) — full page
   b. Tablet (768px) — full page
   c. Mobile (375px) — full page

2. Key pages to check (detect from router or sitemap):
   - Homepage / Landing page
   - Dashboard (if auth available)
   - Admin pages (if admin)

3. For each screenshot:
   - Check for horizontal overflow (page wider than viewport)
   - Check for blank/empty content areas
   - Check for overlapping elements
   - Verify no broken images (alt text visible instead of image)
```

**Using Chrome CDP (preferred — uses live session)**:
```bash
CDP="node $HOME/.claude/skills/chrome-cdp/scripts/cdp.mjs"
TARGET=$($CDP list 2>/dev/null | grep "$DEPLOY_URL" | awk '{print $1}' | head -1)

if [ -n "$TARGET" ]; then
  $CDP nav "$TARGET" "$DEPLOY_URL"
  sleep 3

  # Desktop screenshot
  $CDP shot "$TARGET"  # saves to /tmp/screenshot.png
  # Read the screenshot to check for visual issues

  # For mobile: use agent-browser with viewport setting
  agent-browser open "$DEPLOY_URL" --viewport 375x812
  agent-browser screenshot --path /tmp/mobile-screenshot.png
  agent-browser close
fi
```

**Using agent-browser (fallback — headless)**:
```bash
# Desktop
agent-browser open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-desktop.png --full
agent-browser close

# Mobile
agent-browser --viewport 375x812 open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-mobile.png --full
agent-browser close
```

**Decision logic**:
- If screenshots show blank page: **BLOCK** — deployment broke rendering
- If mobile screenshot shows horizontal scroll: **WARN** — responsive issue
- If all screenshots look normal: PASS
- If browser tools unavailable: Skip with message, not a blocker

**Override**: `--skip-visual` to bypass

---

## Phase 4.5: DEPLOYMENT FAILURE ROLLBACK (CONDITIONAL)

**Trigger**: If any critical platform deployment fails (Vercel or Cloudflare)

1. Display failure summary with specific error details
2. Offer rollback options:
   1. Revert last commit and force push (recommended)
   2. Deploy previous working commit to platforms
   3. Keep current state and fix manually
   4. Cancel (code stays on GitHub, site broken)
3. Execute chosen rollback option
4. Verify rollback deployment success
5. Log rollback action in deployment history
6. Update README/CHANGELOG with rollback note if executed

---

## Phase 4.6: GITHUB ACTIONS CI GATE (POST-PUSH)

**Purpose**: Watch for CI failures after push. Fix and retry up to 3 times.

**Trigger**: After every `git push` if repo has `.github/workflows/` or `gh run list` returns results.

**Default behavior (non-blocking)**: Local checks (build, lint, type-check, targeted tests) already ran before pushing. CI is monitored for **failures only** — do NOT block waiting for slow full test suites to complete.

**Flags**:
| Flag | Behavior |
|------|----------|
| (default) | Quick fail scan only — non-blocking |
| `--watch-ci` | Block until all CI checks complete (old behavior) |
| `--no-ci` | Skip Phase 4.6 entirely |

```bash
# Wait for CI to register
sleep 30

COMMIT=$(git rev-parse HEAD)

if [ "${WATCH_CI}" = "true" ]; then
  # --watch-ci flag: block until all checks complete (old behavior)
  PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)
  if [ -n "$PR_NUM" ]; then
    gh pr checks "$PR_NUM" --watch --fail-fast
  else
    for RUN_ID in $(gh run list --commit "$COMMIT" --json databaseId --jq '.[].databaseId'); do
      gh run watch "$RUN_ID"
    done
  fi
else
  # Default: quick failure scan (non-blocking)
  # Wait another 60s for fast-failing jobs (syntax errors, missing files, import failures)
  sleep 60
  FAILED=$(gh run list --commit "$COMMIT" --json conclusion,databaseId \
    --jq '.[] | select(.conclusion=="failure") | .databaseId' 2>/dev/null)

  if [ -n "$FAILED" ]; then
    # CI failed — read logs and fix
    for RUN_ID in $FAILED; do
      gh run view "$RUN_ID" --log-failed 2>&1 | tail -50
    done
    # Proceed to fix cycle below
  else
    # No failures detected in quick window — proceed without blocking
    echo "CI running in background (no failures detected in quick scan). Fix will auto-apply if it fails."
    # Exit Phase 4.6 — do not block
  fi
fi
```

**On CI Failure** (max 3 retry cycles):
1. Get failure logs: `gh run view <id> --log-failed | tail -50`
2. Identify and fix the issue
3. Commit fix and push
4. Wait for new checks
5. If still failing after 3 attempts: STOP and report to user

| Failure Pattern | Likely Cause | Quick Fix |
|----------------|-------------|-----------|
| `cargo fmt` diff | Formatting mismatch | `cargo fmt --all` |
| `unused_mut` / `dead_code` | Cross-platform cfg blocks | Add `#[allow(...)]` |
| `npm test` / `vitest` failure | Test regression | Fix test or source code |
| Lint errors | Style violations | Auto-fix with `--fix` flag |
| Type errors (tsc) | TypeScript strict mode | Fix types |
| Missing translations | New strings not localized | Add translations for all locales |

---

## Phase 5: POST-DEPLOY MONITORING (CONDITIONAL)

**Trigger**: Only if Phase 1.5 verification checklist was generated

Display persistent monitoring reminder with time-based checkpoints:
- Within 5 minutes: Run post-deploy verification SQL queries
- At +1 hour: Check error dashboard for anomalies
- At +4 hours: Spot check random records
- At +24 hours: Run final data integrity audit

Provide specific commands/links for each checkpoint.

---

## Phase 6: PR BABYSITTER (FIRE-AND-FORGET)

**Trigger**: Automatically after Phase 3 push completes, when ALL of these are true:
- Current branch is NOT main/master/production/prod
- A PR exists: `gh pr view --json number,url` succeeds
- CI checks are configured (`.github/workflows/` exists or `gh pr checks` returns results)

**Skip when**: Direct push to default branch, `--no-babysit` flag, or no PR exists.

**Execution**: Launch as a **background agent** (`run_in_background: true`) immediately after Phase 3 push. The main `/ship` pipeline continues to Phase 3.5+ without waiting. Display:
```
-- Phase 6: PR Babysitter launched in background --
Monitoring PR #<number> for CI failures, reviews, and merge blockers
Will auto-fix what it can; you'll be notified when done or blocked.
```

### Background Agent Loop

**1. Status Check** (each iteration):
```bash
gh pr view --json number,url,state,mergeable,reviewDecision,statusCheckRollup,reviews
gh pr checks
```

**2. Triage & Act** (priority order):

| Priority | Condition | Action |
|----------|-----------|--------|
| 1 | **PR merged or closed** | Exit loop. Report final status. |
| 2 | **New review comments** | Read feedback. If actionable: fix, commit, push. If ambiguous: reply, flag for human. |
| 3 | **CI failure (PR-related)** | Read failure logs. Identify root cause. Fix, commit, push. |
| 4 | **CI failure (flaky)** | Rerun only failed jobs: `gh run rerun <id> --failed`. Max 2 retries per run. |
| 5 | **Merge conflict** | `git fetch origin main && git merge origin/main`, resolve conflicts, push. |
| 6 | **All green, approved** | Report "PR is merge-ready" and exit. |

**3. Flaky vs Real Failure Detection**:
- **Flaky**: Test passed locally, failure in unrelated file, known flaky pattern (timeout, network, race)
- **Real**: Failure in files changed by this PR, compile/type error, deterministic across retries

**4. Polling Cadence** (adaptive backoff):
- CI pending: every 30 seconds
- CI just failed (fixing): every 15 seconds
- CI green, waiting on review: every 2 minutes
- All green + approved: exit
- Max total runtime: 30 minutes

**5. Exit Conditions**:

| Condition | Output |
|-----------|--------|
| PR merged | "PR #N merged successfully" |
| PR closed | "PR #N was closed without merging" |
| All checks pass + approved | "PR #N is merge-ready — waiting for you to merge" |
| 30 min timeout | "Babysitter timed out. Run `/ship --babysit` to resume." |
| Stuck on required approval | "PR #N needs human review approval — pausing" |
| 3+ failed fix attempts | "Could not auto-fix CI after 3 attempts. Manual intervention needed." |

**6. Safety Rules**:
- NEVER force-push or rewrite history
- NEVER dismiss reviews or override branch protection
- NEVER merge the PR automatically (leave that to the human)
- NEVER modify files unrelated to the PR's changeset
- All commits use descriptive messages
- Max 5 fix-push cycles per session
- ALWAYS `pkill -f vitest 2>/dev/null` after any local test runs

**Override**: `--no-babysit` to skip, `--babysit` to force even on default branch
