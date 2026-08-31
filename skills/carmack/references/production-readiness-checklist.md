# Production Readiness Checklist

Run this checklist before any production deploy, when onboarding a new project, or when the user asks "is this ready to ship?". Each item has a concrete detection command or audit step. Partial coverage lives in `code-review-security.md` (XSS), `preflight-checks.md` (lint/audit), and `deploy-patterns.md` (CI/cache). This file fills the remaining gaps.

---

## SECURITY

### S1. No API keys or secrets in frontend code

```bash
# Scan frontend for leaked secrets
grep -rEn "sk_live_|sk_test_|AIza[0-9A-Za-z_-]{35}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|xoxb-[0-9]+-[0-9]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+" \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.html" src/ public/ 2>/dev/null | grep -v node_modules

# Verify frontend envs only use VITE_/NEXT_PUBLIC_ prefixes (public by design)
grep -rEn "process\.env\.[A-Z_]+|import\.meta\.env\.[A-Z_]+" src/ --include="*.ts*" | grep -vE "VITE_|NEXT_PUBLIC_|PUBLIC_"
```

Rule: Any secret in frontend bundle is compromised the moment you deploy. Move to server/Worker only.

### S2. Every route checks authentication

```bash
# List all API/Worker route handlers
grep -rEn "app\.(get|post|put|patch|delete)|router\.(get|post|put|patch|delete)|export (default |const )(GET|POST|PUT|PATCH|DELETE)" \
  --include="*.ts" --include="*.tsx" src/

# For each handler, verify an auth guard runs BEFORE business logic:
# - requireAuth / requireAdmin / authMiddleware / clerkClient.verifyToken / getAuth(req)
# A handler with none of these is a public endpoint — confirm that's intentional.
```

Rule: Audit EVERY endpoint, not just obvious ones. The 2026-03-13 adminClerk.ts incident proved silent auth gaps ship unnoticed.

### S3. HTTPS enforced, HTTP redirected

```bash
# Cloudflare: Always Use HTTPS should be on
# Verify at runtime:
curl -sI http://$DOMAIN | grep -E "^(HTTP|location)"
# Expected: HTTP/1.1 301, location: https://...

# In code — no http:// URLs in fetch/redirect targets
grep -rEn "fetch\([\"']http://|redirect\([\"']http://" src/ --include="*.ts*" | grep -v localhost | grep -v 127.0.0.1
```

### S4. CORS locked to your domain — not wildcard

```bash
# Find CORS config — wildcard is a bug outside truly public APIs
grep -rEn "Access-Control-Allow-Origin|cors\(|corsOptions" --include="*.ts" --include="*.tsx" src/
# Flag any `origin: "*"` or `Access-Control-Allow-Origin: *`
# Exception: truly public APIs (rare) — document the rationale
```

### S5. Input validated and sanitized server-side

```bash
# Find POST/PUT/PATCH handlers that read req.body/c.req.json() without a schema validator
grep -rEn "req\.body|c\.req\.json\(\)|await request\.json\(\)" --include="*.ts" src/
# For each hit, verify a schema (zod, valibot, yup) validates BEFORE DB/external calls
# Server trusts nothing from the client.
```

### S6. Rate limiting on auth and sensitive endpoints

```bash
# Auth, password reset, signup, payment, admin — these need rate limits
grep -rEn "signin|login|signup|forgot-password|reset-password|/admin/|checkout|webhook" --include="*.ts" src/
# For each, verify a rate limiter runs (express-rate-limit, hono rate-limiter, CF Rate Limiting rule, Upstash)
# Cloudflare: check Security → WAF → Rate limiting rules for the zone
```

### S7. Passwords hashed with bcrypt or argon2

```bash
# If you store passwords yourself (not Clerk/Auth0/Supabase)
grep -rEn "password" --include="*.ts" src/ | grep -iE "insert|update|create.*user" | head -20
# Every password write should go through bcrypt.hash() or argon2.hash()
# Flags: plaintext storage, md5, sha1, sha256 (fast hashes = crackable)
# Recommended: argon2id, cost ≥ 3, memory ≥ 64MB; or bcrypt cost ≥ 12
```

Skip if using a hosted auth provider — they handle this.

### S8. Auth tokens have expiry

```bash
# JWT signing should specify expiresIn
grep -rEn "jwt\.sign|new SignJWT|jose\.SignJWT" --include="*.ts" src/
# Every sign() call needs expiresIn (access: 15m–1h, refresh: 7–30d)
# Session cookies: Max-Age or Expires attribute set, not session-only unless intentional
```

### S9. Sessions invalidated on logout (server-side)

```bash
# Logout handler must destroy server-side session, not just clear the cookie
grep -rEn "logout|sign-out|signout" --include="*.ts" src/
# Verify:
# - Session row deleted from sessions table / Redis / KV, OR
# - JWT jti added to revocation list, OR
# - Refresh token revoked in provider (Clerk: sessions.revoke)
# Clearing only the client cookie = session still valid if leaked.
```

---

## DATABASE

### D1. Backups configured and tested (restore, not just backup)

```bash
# Check backup schedule exists (platform-specific)
# Postgres/Supabase: Dashboard → Database → Backups → Daily backups ON
# Cloudflare D1: wrangler d1 backup list <db-name>
# Turso: turso db show <db> --no-color | grep -i backup
# Self-hosted: cron job writing to s3/b2/gdrive — find it:
crontab -l 2>/dev/null | grep -iE "pg_dump|mysqldump|sqlite3 .dump|backup"

# CRITICAL: When was the last restore test? Untested backups often don't restore.
# Schedule: restore to staging quarterly.
```

### D2. Parameterized queries everywhere

See `code-review-security.md` §1. Quick re-scan:
```bash
# String-concatenated SQL — dangerous
grep -rEn "query\(\s*[\"'\`].*\\\$\{|query\(\s*[\"'\`].*\+.*\)" --include="*.ts" src/
# D1 / better-sqlite3: use .prepare().bind() — never string interpolate
```

### D3. Separate dev and production databases

```bash
# Verify prod DATABASE_URL differs from dev
# .env.local / .env / .dev.vars → should point to a dev DB
# Production secrets (CF Workers: wrangler secret list; Vercel: vercel env ls) → point to prod DB

# Red flag: both envs share the same DB host+name
```

### D4. Connection pooling configured

```bash
# Node/edge: if using raw pg or mysql2, check pool
grep -rEn "new Pool\(|createPool\(" --include="*.ts" src/
# Pool must have max, idleTimeoutMillis set — never `new Client()` per request
# Serverless (Vercel/CF Workers): use Hyperdrive, PgBouncer, Prisma Accelerate, or a pooled driver
```

### D5. Migrations in version control, not manual changes

```bash
# Migrations live in repo
ls migrations/ db/migrations/ drizzle/ prisma/migrations/ 2>/dev/null

# No `ALTER TABLE` run by hand on prod — check schema matches migrations
# Drizzle: drizzle-kit check
# Prisma: prisma migrate diff --from-schema-datamodel prisma/schema.prisma --to-schema-datasource prisma/schema.prisma
# Red flag: production schema has columns/tables not represented by any migration file
```

### D6. App uses a non-root DB user

```bash
# Application DATABASE_URL should NOT be the superuser / postgres / root account
# Create app-scoped user with least privilege:
#   GRANT SELECT, INSERT, UPDATE, DELETE ON app_schema.* TO app_user;
#   NO CREATE, DROP, ALTER, GRANT permissions.
# Check current user: SELECT current_user; — must not be `postgres` / `root` / `admin`
```

---

## DEPLOYMENT

### DP1. All environment variables set on production server

```bash
# Compare .env.example against actual prod secrets
# CF Workers:
npx wrangler secret list
# Vercel:
vercel env ls production
# Fly / Railway / Render: platform-specific

# Any var in .env.example missing from prod = silent runtime failure waiting to happen
# Also verify: no var with placeholder value ("your_key_here", "xxx", "todo")
```

### DP2. SSL certificate installed and valid

```bash
# Validity + expiry
echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -dates
# notAfter must be ≥30 days away; renewal automation (LE/CF) should handle it

# Chain complete?
curl -sI https://$DOMAIN -o /dev/null -w "%{http_code}\n"
# 200 OK with no SSL warning in browser = OK
```

### DP3. Firewall configured (only 80/443 public)

```bash
# VPS (Linux):
sudo ufw status verbose              # or: sudo iptables -L -n
# Expected public inbound: 22 (SSH, ideally Tailscale-only or key-only), 80, 443
# Everything else: DENY from 0.0.0.0/0

# Cloud: check security group / network rules
# AWS: aws ec2 describe-security-groups
# GCP: gcloud compute firewall-rules list
# Hetzner: hcloud firewall list

# Databases, Redis, internal APIs must NEVER be public
```

### DP4. Process manager running (PM2, systemd)

```bash
# VPS — service must be supervised (auto-restart on crash, start on boot)
systemctl list-units --type=service --state=running | grep -iE "node|app|worker"
# Or: pm2 list

# Red flag: app running under `nohup`, `screen`, or a detached shell — will not survive reboot
```

### DP5. Rollback plan exists

Before every prod deploy, know the answer to "how do I undo this in 60 seconds?":

- **CF Pages / Workers**: `wrangler rollback` or previous deployment in dashboard
- **Vercel**: instant rollback from Deployments UI
- **DB migration**: a `down` migration exists and is tested on staging
- **Feature flag**: can the feature be turned off without redeploy?
- **Tag the release**: `git tag -a v1.2.3 -m "..." && git push --tags` — trivial to check out and redeploy

### DP6. Staging test passed before production deploy

```bash
# Staging env exists and was deployed with the same commit
# CF Pages: preview URL for the PR → hit critical paths
# Vercel: preview deployment on the PR

# Smoke test the staging URL before promoting:
# - login works
# - a write operation succeeds
# - feature under change behaves correctly
# Only THEN promote to prod.
```

---

## CODE

### C1. No console.logs in production build

```bash
# Source sweep
grep -rEn "console\.(log|debug|info)" --include="*.ts" --include="*.tsx" src/ | grep -v "^.*//" | grep -v __tests__

# Built artifact sweep (catches compiled-through logs)
grep -oE "console\.(log|debug|info)" dist/**/*.js 2>/dev/null | wc -l
# Should be 0. Use vite `drop: ['console']` or tsc `removeComments` + a logger that no-ops in prod.
```

### C2. Error handling on all async operations

```bash
# Find awaits without surrounding try/catch OR .catch()
# Rough heuristic — read each hit to judge
grep -rEn "^\s*(const |let |return )?await " --include="*.ts" --include="*.tsx" src/ | head -50

# In React components: every async effect needs an error path
# Route handlers: must return a non-500 response for expected failures
# Background jobs: must catch + log, never let a rejection escape
```

### C3. Loading and error states in UI

```bash
# Every data-fetching component needs both
grep -rEn "useQuery\(|useSWR\(|useFetch\(|fetch\(" --include="*.tsx" src/
# For each hit, verify the component renders:
# - loading UI (skeleton/spinner) while pending
# - error UI (with retry) when the call fails
# - empty state when data is [] or null
# Missing any of these = "page looks broken" bug reports.
```

### C4. Pagination on all list endpoints

```bash
# Find API endpoints that return arrays
grep -rEn "findMany|findAll|\.all\(\)|SELECT \* FROM" --include="*.ts" src/
# For each: is there a LIMIT / take / first param? A cursor or page token?
# Unbounded lists = O(N) memory, slow responses, eventual OOM.

# Default pattern:
#   - max page size = 100
#   - default page size = 20
#   - cursor-based for high-volume tables (no OFFSET on big tables)
```

### C5. npm audit run, critical issues resolved

Covered in `preflight-checks.md` Pre-4 and `deploy-patterns.md` (Dependabot Auto-Fix).

```bash
npm audit --omit=dev
# 0 HIGH, 0 CRITICAL required before deploy
# Use package.json `overrides` for stubborn transitive deps
```

---

## Running This Checklist

```bash
# Quick report mode — emit [PASS]/[FAIL] per item:
bash ~/.claude/skills/carmack/scripts/production-readiness.sh   # if present
# Otherwise walk sections S1–S9, D1–D6, DP1–DP6, C1–C5 in order.
# Track failures, fix highest-severity first (S > D > DP > C).
```

This checklist is additive to `code-review-security.md` and `preflight-checks.md` — run those first for full-coverage scans, then use this file for the production-specific items they don't cover.
