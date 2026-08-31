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

## Phase 2.95: NO-REMOTE AUTO-PROVISION (added 2026-07-30)

**Fires when `git remote` is empty.** /ship's rule is "GitHub deployment ALWAYS happens
before any other platform", so a repo with no remote previously hard-blocked every ship.
Auto-provision it instead — but a *first* push publishes the entire history at once, so the
ordering below is the safety property, not bureaucracy.

**Run in exactly this order. Do not reorder — steps 1–2 are what make step 4 safe.**

```bash
# 1. SECRET SWEEP FIRST — before anything leaves the machine.
#    A first push ships every commit, so a secret in commit #1 is published even if
#    later commits removed it. Filenames AND content.
git ls-files | grep -iE 'dev\.vars$|\.env$|secret|credential|\.pem$|\.p12$|\.key$'   # must be empty
git ls-files -z | xargs -0 grep -lniE \
  'AIza[0-9A-Za-z_-]{20,}|sk_live_|ghp_[A-Za-z0-9]{30,}|-----BEGIN (RSA|OPENSSH|PRIVATE)'  # must be empty
# BLOCK on any hit. Do not "fix" by deleting the file in a new commit — the blob is still
# in history; rewrite or start a fresh repo.

# 2. Confirm .gitignore covers the local-secret conventions before the first push.
git check-ignore -v .dev.vars .env .env.local 2>/dev/null

# 3. Create PRIVATE. Never omit --private, never use --public.
gh repo create "$NAME" --private --source=. --remote=origin --description "<one line>"

# 4. VERIFY the visibility from the API — do not trust the flag you passed.
gh repo view "$OWNER/$NAME" --json isPrivate,visibility
#    isPrivate MUST be true. If false: `gh repo edit --visibility private` and re-verify.

# 5. Push and set upstream.
git push -u origin "$(git branch --show-current)"

# 6. Set origin/HEAD — Phase 1.29's security-review resolves `origin/HEAD...` and
#    hard-fails with "ambiguous argument 'origin/HEAD...'" without it. A fresh
#    `gh repo create` + push does NOT always set it.
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || git remote set-head origin -a
```

**Standing rule this enforces:** personal work is PRIVATE. A fork of a public upstream is
PUBLIC by default — check `gh repo view --json isPrivate` before ANY push to a repo you did
not just create. See `feedback_never_push_personal_work_to_public_repos.md`.

### ⚠️ Phase 1.29 is VACUOUS on the first push — say so, don't call it a pass

After a first push `HEAD == origin/HEAD`, so `security-review` sees an **empty diff** and
reports 0 findings. The skill documents "empty diff = 0 findings (a genuine no-change ship
passes correctly)" — true for a no-change ship, and **misleading here**: the entire
codebase, including any auth code, has never been through the gate.

On a first push you MUST either:
- review the security surface directly (auth/authz, `dangerouslySetInnerHTML`, script-tag
  JSON embedding, template interpolation, any string reaching a shell/SQL/HTML sink) and
  report *that* as the evidence, or
- state plainly that the semantic gate was vacuous and is deferred to the next push.

Never report "security-review: 0 findings" from an empty first-push diff as if the code was
examined. Generalizes: **a gate whose pass state is indistinguishable from its
not-run state needs its own gate.**

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

## Phase 3.55: README CONFIG-SYNC AUTO-REGEN (MANDATORY — added 2026-05-10)

**Run after Phase 3.5, BEFORE any production deploy.** Catches drift between
the deployed code and the README's "how the site works" section. The user's
explicit ask: README must stay current with reality after every `/ship`.

### Trigger
Always run when the repo contains BOTH:
- `scripts/regen-readme-status.sh` (or any `regen-readme*.sh` / `update-readme*.sh`)
- A `README.md` with `<!-- auto-status:start -->` / `<!-- auto-status:end -->` markers
  (or any equivalent managed-block convention the project documents)

### Procedure
```bash
# 1. Run the project's README regeneration script
if [ -x scripts/regen-readme-status.sh ]; then
  bash scripts/regen-readme-status.sh
elif [ -x scripts/update-readme.sh ]; then
  bash scripts/update-readme.sh
fi

# 2. If the script produced a README diff, commit + push it BEFORE deploying
if ! git diff --quiet README.md; then
  git add README.md
  git commit -m "docs: regen README current-setup [skip auto-readme]"
  git push origin "$(git rev-parse --abbrev-ref HEAD)"
fi
```

### Rules
- The commit message MUST include `[skip auto-readme]` if a GitHub Action
  re-runs the same regen on push (prevents infinite loops with workflows
  like `auto-readme.yml`)
- The README block must reflect the deployed state — if a deploy ships
  new routes, new backends, new architecture, the README block updates BEFORE
  prod gets the code, not after
- The Stop hook checks this — if `README.md` is out of sync with the regen
  script's output at session-end, it prompts to push before allowing exit
- **If README config-sync fails: BLOCK Phase 4 deployments** (same as 3.5)

### Why
2026-05-10: User shipped multi-city `/case` route, Socrata-primary lookup,
"View ticket →" button redesign, and visual map filters across 3 separate
`/ship` runs without the public README mentioning any of them. The
GitHub Action `auto-readme.yml` only triggers on a fixed file allowlist, and
the architectural changes touched files outside that list. Adding this
phase to /ship guarantees the README config-sync runs every deploy
regardless of which files changed.

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

**🚨 Step 0: MANDATORY Wrangler Version Pre-Flight** — RUN THIS BEFORE ANY OTHER WRANGLER COMMAND, EVERY TIME.

Wrangler ships breaking deploy bugs frequently and posts security/CVE patches on minor versions. An outdated wrangler can silently corrupt deploys, fail auth in subtle ways, or upload mis-bundled assets. The version check is non-negotiable — do not skip it because "the deploy worked last time".

```bash
# Detect both LOCAL (devDep) and GLOBAL wrangler versions
LOCAL_WRANGLER=""
GLOBAL_WRANGLER=""
[ -f node_modules/wrangler/package.json ] && LOCAL_WRANGLER=$(node -p "require('./node_modules/wrangler/package.json').version" 2>/dev/null)
GLOBAL_WRANGLER=$(command -v wrangler >/dev/null && wrangler --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
LATEST_WRANGLER=$(npm view wrangler version 2>/dev/null)

echo "Wrangler versions — local: ${LOCAL_WRANGLER:-none}, global: ${GLOBAL_WRANGLER:-none}, latest: ${LATEST_WRANGLER:-unknown}"

# `npm run deploy:prod` (and most npm scripts) use the LOCAL wrangler from node_modules,
# NOT the global one. Both must be current.
NEEDS_LOCAL_UPDATE=0
NEEDS_GLOBAL_UPDATE=0
[ -n "$LOCAL_WRANGLER" ] && [ "$LOCAL_WRANGLER" != "$LATEST_WRANGLER" ] && NEEDS_LOCAL_UPDATE=1
[ -n "$GLOBAL_WRANGLER" ] && [ "$GLOBAL_WRANGLER" != "$LATEST_WRANGLER" ] && NEEDS_GLOBAL_UPDATE=1
# If wrangler is in package.json devDeps but node_modules/wrangler is missing, that's also a needs-install
grep -q '"wrangler"' package.json 2>/dev/null && [ -z "$LOCAL_WRANGLER" ] && NEEDS_LOCAL_UPDATE=1

if [ "$NEEDS_LOCAL_UPDATE" = "1" ]; then
  echo "Updating LOCAL wrangler to ${LATEST_WRANGLER}..."
  # Detect package manager from lockfile — npm install can EOVERRIDE on bun/pnpm projects
  if [ -f bun.lock ] || [ -f bun.lockb ]; then
    bun add -d wrangler@latest 2>&1 | tail -3
  elif [ -f pnpm-lock.yaml ]; then
    pnpm add -D wrangler@latest 2>&1 | tail -3
  elif [ -f yarn.lock ]; then
    yarn add -D wrangler@latest 2>&1 | tail -3
  else
    npm install wrangler@latest --save-dev 2>&1 | tail -3
  fi
fi
if [ "$NEEDS_GLOBAL_UPDATE" = "1" ]; then
  echo "Updating GLOBAL wrangler to ${LATEST_WRANGLER}..."
  npm install -g wrangler@latest 2>&1 | tail -3
fi

# Verify post-update
[ "$NEEDS_LOCAL_UPDATE" = "1" ] && node -p "require('./node_modules/wrangler/package.json').version"
[ "$NEEDS_GLOBAL_UPDATE" = "1" ] && wrangler --version
```

**Why both local and global**: `npm run deploy:prod` resolves wrangler from `./node_modules/.bin/`. Updating only the global binary leaves the project pinned to an outdated version that npm scripts will use. ALWAYS update both if either is stale.

**If `npm view wrangler version` fails** (no network, npm registry down): log a warning and continue with the current version — do not block deployment over a metadata fetch failure. But if a known-needed update is suggested by inline wrangler output ("update available X.Y.Z"), retry the npm install.

**After update, commit the package.json/lockfile changes** if `npm install --save-dev` modified them — these go in the same deploy commit so the deployed bundle's lockfile matches the wrangler that built it.

**Step 0.1: Detect Deployment Type** — CF Workers vs CF Pages:
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

**🔑 PRIMARY AUTH METHOD (this account): Global API Key**

For you@example.com (account `<CLOUDFLARE_ACCOUNT_ID>`), the persistent auth is the **Cloudflare Global API Key** stored at `~/.cloudflared/cf-global-api-key.json`. It is exported automatically by `~/.zshrc` as `CLOUDFLARE_API_KEY` + `CLOUDFLARE_EMAIL` and has FULL account permissions (Workers, Pages, DNS, KV, D1, R2, Zone — everything). This bypasses per-token permission gaps.

This is the source of truth — DO NOT prompt the user for `wrangler login` if `wrangler whoami` already shows "Global API Key, associated with the email you@example.com". Just deploy.

```bash
# If wrangler whoami fails in a non-interactive shell, source zshrc env vars manually:
export CLOUDFLARE_API_KEY="$(python3 -c 'import json;print(json.load(open("$HOME/.cloudflared/cf-global-api-key.json"))["global_api_key"])')"
export CLOUDFLARE_EMAIL="you@example.com"
unset CLOUDFLARE_API_TOKEN  # narrower-scope tokens override the global key — unset them
```

Why Global API Key, not OAuth: the OAuth token in `~/.wrangler/config/default.toml` expires every ~90 days. The Hetzner VPS that previously kept it refreshed was deleted 2026-04-29. Until/unless `wrangler login` is re-run interactively, the Global API Key is the working auth path.

**CRITICAL: `.env.local` Token Override Bug**
Wrangler auto-loads `.env.local` via dotenv. If `.env.local` has `CLOUDFLARE_API_TOKEN` with limited permissions, it OVERRIDES the global API key + OAuth token. Symptoms:
- `wrangler deploy` fails with "Authentication error [code: 10000]"
- `wrangler whoami` says "authenticating via custom API token"
- But the global key in env has full permissions

**Fix**: Remove or comment out `CLOUDFLARE_API_TOKEN` from `.env.local`, or `unset CLOUDFLARE_API_TOKEN` in the deploy shell.

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

**Step 2.5: Record the deploy (durable, repo-native tracking)** — right after a
successful `wrangler deploy`, if the repo has a deploy-record hook, run it so
"when did commit `<sha>` go to prod" is answerable forever (Cloudflare only
retains recent deployment history):
```bash
[ -f scripts/record-deploy.sh ] && bash scripts/record-deploy.sh   # appends deploy-log.jsonl + registers a GitHub Deployment
```
If you deployed via `npm run deploy`/`deploy:prod`/`deploy:skip-tests`, this is
already chained in — skip. Reference: AIVA-Frontend `DEPLOYS.md` (born from the
2026-07-05 intake outage whose start date was unrecoverable). A repo without the
hook should add one (git-tracked `deploy-log.jsonl` line: sha, ts, worker version, actor).

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
