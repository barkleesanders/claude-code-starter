# Deployment

Covers Phase 2 (manual override), Phase 3 (GitHub deployment), Phase 3.5 (README/changelog auto-update), and Phase 4 (downstream deployments to Vercel, Cloudflare, Docker).

---

## Phase 2: MANUAL OVERRIDE PATH

- Accept override ONLY with explicit --force-override flag plus --reason argument
- Display prominent warning about bypassing quality gates
- Require additional user confirmation with clear [YES/NO] prompt
- Log override event with timestamp, reason, and user identifier
- Prefix commit message with [OVERRIDE] marker for audit trail

---

## Phase 3: GITHUB DEPLOYMENT

- Stage all changes with git add
- Generate descriptive commit message based on what was executed:
  - Include test pass count
  - Include lint fix statistics (auto-fixed, AI-fixed, remaining)
  - Include verification status if Phase 1.5 ran
  - Include override markers if any flags used
- Display git diff summary showing what will be pushed
- Require explicit user confirmation: [CONFIRM PUSH] or [CANCEL]
- Push to current branch using git push origin
- Verify push success using gh CLI commands
- Store COMMIT_SHA and TEST_RESULTS for Phase 3.5

---

## Phase 3.5: README & CHANGELOG AUTO-UPDATE

**Execution**: ONLY if Phase 1 tests passed 100%

### How It Works

1. Check if `README.md` exists and has a `## Latest Changes` section
2. If no such section exists, create one after the first heading
3. Find the last commit hash mentioned in the changelog
4. Collect all commits since that last documented commit
5. Group related commits by date
6. Prepend new entries at the top (newest first)

### Entry Format
```markdown
### <Date> - <commit message summary> (Commit: <short-hash>)
- Bullet point describing each meaningful change
- Tests: X passed, Y failed (if tests were run)
- Commit: <short-hash> ([View on GitHub](https://github.com/<owner>/<repo>/commit/<short-hash>))
```

### Auto-Detection
```bash
REMOTE=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's|git@github.com:|https://github.com/|')
LAST_HASH=$(grep -oP 'Commit: \K[a-f0-9]{7}' README.md | head -1)
git log --format="%h %ad %s" --date=short ${LAST_HASH}..HEAD
```

### Rules
- Always run this gate — even for small changes
- Skip docs-only commits (avoid infinite loops)
- Max 20 entries — archive older entries
- Commit and push as separate commit: `docs: update Latest Changes with <commit-hash> deploy`
- **If README update fails: BLOCK Phase 4 deployments**

---

## Phase 4: DOWNSTREAM DEPLOYMENTS

**Deployment Target Logic**:
- **Default (no flags)**: Deploy to PRODUCTION
- **`--staging` or "to staging first"**: Deploy to staging, then prompt for production promotion
- **`--staging-only`**: Deploy to staging only

### VERCEL DEPLOYMENT (if vercel.json exists)

**Production Deployment (DEFAULT)**:
1. Pre-deployment Check: Verify CLI and authentication
2. Execute Deployment: `vercel deploy --prod --yes`
3. Verify Deployment Success: Check exit code, parse output
4. Health Check: Wait 10s, HTTP GET with 3 retries
5. Report Status with URL, deployment ID, response time

**Staging/Preview Deployment (if --staging)**:
1. Execute Preview Deployment: `vercel deploy --yes` (no --prod flag)
2. Health Check: Wait 10s, HTTP GET to preview URL
3. Display staging URL prominently
4. **If "staging first" mode**: Ask user to verify staging, then confirm production promotion
5. **On promotion confirmation**: Run production deployment (`vercel deploy --prod --yes`)

### CLOUDFLARE DEPLOYMENT (if wrangler.toml/json exists)

**Step 0: Detect Deployment Type** — CF Workers vs CF Pages:
```bash
# CF Pages: has pages_build_output_dir in wrangler.toml
grep -q "pages_build_output_dir" wrangler.toml 2>/dev/null && echo "CF_PAGES" || echo "CF_WORKERS"
# Also check for npm run deploy script
grep -q '"deploy"' package.json 2>/dev/null && echo "HAS_DEPLOY_SCRIPT"
```

**Step 1: Auth Verification** — CF has multiple auth methods that conflict:
```bash
# Check for CLOUDFLARE_API_TOKEN in .env files (wrangler loads these via dotenv!)
grep -rn "CLOUDFLARE_API_TOKEN" .env .env.local .env.production 2>/dev/null

# Check wrangler OAuth config
cat ~/.wrangler/config/default.toml 2>/dev/null | grep "scopes"

# Test: does wrangler whoami work?
npx wrangler whoami 2>&1 | head -5
```

**CRITICAL: `.env.local` Token Override Bug**
Wrangler auto-loads `.env.local` via dotenv. If `.env.local` has `CLOUDFLARE_API_TOKEN` with limited permissions, it OVERRIDES the wrangler OAuth token (which may have full permissions including `pages:write`). Symptoms:
- `wrangler pages deploy` fails with "Authentication error [code: 10000]"
- `wrangler whoami` says "authenticating via custom API token"
- But `~/.wrangler/config/default.toml` has `pages:write` in scopes

**Fix**: Remove or comment out `CLOUDFLARE_API_TOKEN` from `.env.local` if the OAuth token has the right permissions. The OAuth token in `~/.wrangler/config/default.toml` is the preferred auth method.

**Step 2: Deploy** (CF Pages):
```bash
# Preferred: use project's deploy script (handles build + deploy)
npm run deploy:full 2>&1  # build + deploy in one command
# OR: just deploy pre-built dist/
npm run deploy 2>&1       # wrangler pages deploy dist
```

If no deploy script exists:
```bash
npm run build && npx wrangler pages deploy dist --project-name=$(grep '^name' wrangler.toml | head -1 | sed 's/.*= *"//;s/"//')
```

**Step 2 (CF Workers — no pages_build_output_dir)**:
```bash
npm run deploy 2>&1  # OR: npx wrangler deploy
```

**Step 3: Verify Deployment Success**:
```bash
# Check exit code from deploy command
# Parse deployment URL from output (e.g., "https://abc123.project.pages.dev")
# Health check production URL
sleep 3
curl -sI "$DEPLOY_URL" | head -5

# CRITICAL: Verify version.json shows current commit (not stale "dev")
curl -s "$DEPLOY_URL/version.json" 2>/dev/null
# Should show: current commit SHA, "production" environment, recent timestamp
# If shows "dev" or old timestamp: version.json is cached or not regenerated during build
```

**Step 4: Version Freshness Check**:
```bash
# Compare deployed version with local git
DEPLOYED_SHA=$(curl -s "$DEPLOY_URL/version.json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('commitSha','unknown')[:7])" 2>/dev/null)
LOCAL_SHA=$(git rev-parse --short HEAD)
if [ "$DEPLOYED_SHA" = "$LOCAL_SHA" ]; then
  echo "Deployed version matches local HEAD"
else
  echo "Version mismatch: deployed=$DEPLOYED_SHA local=$LOCAL_SHA"
  echo "  CF Pages may still be building, or version.json is cached"
fi
```

**Common CF Pages Deployment Failures**:

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Auth error 10000 | `.env.local` has broken `CLOUDFLARE_API_TOKEN` | Remove from `.env.local`, use wrangler OAuth |
| version.json shows "dev" | Committed to git with local values | Add to `.gitignore`, generate at build time |
| Old version after deploy | Service worker caches version.json | Add to SW `NETWORK_ONLY_PATTERNS` |
| CDN serves stale version.json | No cache-control header | Add `Cache-Control: no-store` in `_headers` |
| No auto-deploy on push | No GitHub integration configured | Set up in CF Dashboard or use `npm run deploy` |

**Staging Deployment (if --staging)**:
1. Check for staging environment in wrangler.toml: `[env.staging]`
2. If staging env exists: `wrangler deploy --env staging`
3. If no staging env: `wrangler pages deploy dist --branch preview`
4. **If "staging first" mode**: Ask user to verify, then confirm production promotion

### DOCKER DEPLOYMENT (if Docker credentials configured)
- Push to Docker registry: `docker push`
- Verify push success
- Report registry URL and image tag

### Cloudflare API Access (MCP)

The `cloudflare-api` MCP server provides full access to ~2,500 Cloudflare API endpoints. Use during deployment for operations beyond what `wrangler` CLI covers:
- DNS records, redirects, firewall rules
- Zone settings, SSL, cache config
- KV/D1/R2 operations during deploy verification

| Task | Use |
|------|-----|
| Deploy Worker code | `wrangler deploy` |
| Tail logs | `wrangler tail` |
| DNS, redirects, firewall | **Cloudflare MCP** |
| Zone settings, SSL, cache | **Cloudflare MCP** |

### DEPLOYMENT SUMMARY
Display comprehensive summary table with platform name, environment, status, live URL, response time.
