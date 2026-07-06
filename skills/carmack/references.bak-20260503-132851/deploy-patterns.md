# Deploy & CI Patterns

## Deploy Session Invalidation (SPA + Cloudflare Workers)

**#5 production crash cause.** Users are logged out after every deployment because old JS chunks return HTML instead of 404.

### Root Cause
1. `wrangler deploy` uploads new assets with new content hashes
2. User's cached `index.html` references old chunk filenames
3. `not_found_handling: "single-page-application"` returns HTML (200) for missing `.js` files
4. React's `import()` gets HTML instead of JS → syntax error → crash → session lost

### Required Defenses (ALL THREE must exist)

**1. Client: `vite:preloadError` handler in main.tsx**
```typescript
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault();
  if (!sessionStorage.getItem('chunk-reload')) {
    sessionStorage.setItem('chunk-reload', '1');
    window.location.reload();
  }
});
// After React mounts successfully:
sessionStorage.removeItem('chunk-reload');
```

**2. Client: ErrorBoundary chunk detection**
```typescript
isChunkLoadError(error) {
  return /dynamically imported module|Loading chunk|ChunkLoadError/.test(
    error?.message || error?.name || ''
  );
}
// In componentDidCatch: auto-reload once using same sessionStorage flag
```

**3. Server: `CDN-Cache-Control: no-store` on HTML responses**
```typescript
// In securityHeaders middleware
c.header("CDN-Cache-Control", "no-store");
```

### Quick Detection
```bash
# All three must exist:
grep "vite:preloadError" src/react-app/main.tsx
grep -E "ChunkLoadError|dynamically imported module" src/react-app/components/ErrorBoundary.tsx
grep "CDN-Cache-Control" src/worker/middleware/securityHeaders.ts
```

### Incident (2026-03-15)
Every `wrangler deploy` logged out all active users. CF edge cached stale HTML (`cf-cache-status: HIT` despite `Cache-Control: no-store`), old HTML referenced old chunks, SPA fallback served HTML for missing `.js` → React crash → Clerk session lost.

---

## CF Pages Stale Deployment / version.json Debugging

**#6 production debugging trap.** Production shows old version, stale timestamp, or `"version": "dev"` after pushing code.

### Root Causes (check in order)

| # | Symptom | Root Cause | Fix |
|---|---------|-----------|-----|
| 1 | `version.json` shows `"dev"` | File committed to git with local build values | Add `public/version.json` to `.gitignore`, `git rm --cached` |
| 2 | `version.json` shows old SHA | Service worker caches it | Add to SW `NETWORK_ONLY_PATTERNS` |
| 3 | CDN serves stale `version.json` | No cache-control header | Add `Cache-Control: no-store` in `_headers` file |
| 4 | Deploy command fails auth | `.env.local` has `CLOUDFLARE_API_TOKEN` that overrides wrangler OAuth | Remove token from `.env.local` |
| 5 | Push doesn't trigger deploy | No CF Pages GitHub integration | Use `npm run deploy` or set up in CF Dashboard |
| 6 | `generate-version.js` outputs `"dev"` | No CF env vars AND no git fallback | Add `execSync('git rev-parse HEAD')` fallback |

### Quick Diagnosis
```bash
# What does production serve?
curl -s "https://YOUR_SITE.pages.dev/version.json"

# What does local build produce?
npm run build && cat public/version.json

# Is version.json git-tracked? (should NOT be)
git ls-files public/version.json

# Does wrangler auth work?
npx wrangler whoami 2>&1 | head -5

# Is .env.local overriding wrangler OAuth?
grep "CLOUDFLARE_API_TOKEN" .env.local 2>/dev/null

# Does the service worker cache version.json?
grep "version.json\|NETWORK_ONLY" public/sw.js
```

### The `.env.local` Token Override Bug (Critical)

Wrangler loads `.env.local` via dotenv internally. If `.env.local` has `CLOUDFLARE_API_TOKEN` with limited permissions, it **overrides** the wrangler OAuth token from `~/.wrangler/config/default.toml` — even if the OAuth token has full permissions including `pages:write`.

**Detection**: `wrangler pages deploy` fails with "Authentication error [code: 10000]" but `~/.wrangler/config/default.toml` shows `pages:write` in scopes.

**Fix**: Remove or comment out `CLOUDFLARE_API_TOKEN` from `.env.local`. The wrangler OAuth token is the correct auth method.

**Important**: `env -u CLOUDFLARE_API_TOKEN` does NOT work because wrangler loads the token from the file, not from the shell environment.

### version.json Architecture (Correct Setup)

```
public/version.json     → in .gitignore (never committed)
scripts/generate-version.js → runs during prebuild
  → reads: CF_PAGES_COMMIT_SHA || git rev-parse HEAD
  → writes: public/version.json with real commit SHA
public/_headers         → Cache-Control: no-store for /version.json
public/sw.js            → version.json in NETWORK_ONLY_PATTERNS
vite.config.ts          → __BUILD_VERSION__ uses same git fallback
```

### Incident (2026-03-17)
Version display showed `"dev"` / `"development"` / 2 hours stale despite 6 pushes to main. Five interacting causes: (1) version.json committed to git with local values, (2) vite.config.ts fell back to `'dev'` without CF env vars, (3) no cache-control header for version.json, (4) service worker cached version.json, (5) no CF Pages GitHub integration (only Vercel webhook existed). Fixed by removing version.json from git, adding git fallback to generate-version.js and vite.config.ts, adding cache bypass headers, and removing broken API token from .env.local.

---

## Cross-Platform CI Safety (Rust Projects)

When submitting PRs to Rust projects with multi-platform CI (Linux, Windows, macOS, FreeBSD, NetBSD, Android):

### Pre-Submit Checklist
1. **`cargo fmt --all -- --check`** — CI is strict about formatting, especially line wrapping in chained `||`/`&&` expressions
2. **`cargo clippy --all-targets`** — Check for unused variables/mutability that only exist due to `#[cfg(target_os)]` blocks
3. **`#[allow(unused_mut)]`** — Add above any `let mut` that's only reassigned inside a platform-specific cfg block
4. **`#[allow(dead_code)]`** — Add above functions only called from cfg blocks

### Common Trap: Conditional Compilation
```rust
// ❌ Passes clippy on macOS, FAILS on Linux/Windows/FreeBSD/NetBSD/Android
let mut value = get_default()?;
#[cfg(target_os = "macos")]
if let Some(override_val) = macos_specific() { value = override_val; }

// ✅ Works on ALL platforms
#[allow(unused_mut)]
let mut value = get_default()?;
#[cfg(target_os = "macos")]
if let Some(override_val) = macos_specific() { value = override_val; }
```

## Launchd/Cron PATH Debugging

When debugging tools that work interactively but fail in automated environments:

### Root Cause
launchd and cron don't load shell profiles (`~/.zshrc`, `~/.bash_profile`). They inherit a minimal PATH: `/usr/bin:/bin:/usr/sbin:/sbin`.

### Investigation Steps
1. **Check what PATH the automated job sees**: Add `echo "PATH=$PATH" >> /tmp/debug-path.txt` to the script
2. **Find all tools the script needs**: `grep -oP '\b(brew|npm|claude|gem|ruby|cargo|rustup)\b' script.sh`
3. **Check if each tool is at a standard Homebrew path**: `which -a <tool>` — if it's only at `/opt/homebrew/bin/` or a keg-only path, it won't be found
4. **Test with stripped PATH**: `env -i PATH="/usr/bin:/bin" bash -c 'which <tool>'`

### Fix Template
```bash
#!/bin/bash
# Always set full PATH in launchd/cron scripts
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:/opt/homebrew/sbin"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

## Code Scanning Auto-Fix (Pre-Push)

**MANDATORY before pushing to any repo with GitHub code scanning enabled.** Check for and auto-fix the three categories of code scanning alerts that OpenSSF Scorecard, DevSkim, and similar scanners flag.

### Detection
```bash
# Check if repo has code scanning enabled
gh api repos/{owner}/{repo}/code-scanning/alerts --jq 'length' 2>/dev/null
```

### Category 1: GitHub Actions Token Permissions (OpenSSF Scorecard)

**Problem**: Workflows with overly broad `permissions` (e.g., `write-all` or no top-level `permissions` defined).

**Auto-fix**:
```bash
# Find all workflow files
ls .github/workflows/*.yml

# For each workflow, ensure:
# 1. Top-level permissions block exists with read-only defaults
# 2. Job-level permissions are narrowed to minimum required

# Pattern: Add/change top-level permissions
# permissions:
#   contents: read
#
# Then only add write permissions at JOB level where needed:
#   jobs:
#     release:
#       permissions:
#         contents: write    # Only for release asset uploads
```

**Rules**:
- Top-level `permissions` MUST default to read-only (`contents: read` or `read-all`)
- Job-level `permissions` ONLY where write access is genuinely needed
- Security scan jobs need `security-events: write` at job level, NOT top level
- Release jobs need `contents: write` at job level for asset uploads
- Never use `write-all` at top level

### Category 2: RUSTSEC / Dependency Vulnerabilities

**Auto-fix**:
```bash
# For Rust projects
cargo audit 2>&1

# For Node projects
npm audit --omit=dev 2>&1

# For Python projects
pip-audit 2>&1
```

**Rules**:
- If the advisory is a real vulnerability with a fix available: update the crate/package
- If the advisory is informational (unmaintained crate): evaluate migration cost
  - If migration is trivial (<20 code changes): migrate to maintained alternative
  - If migration is expensive (100+ code changes): add to ignore config with rationale and 1-year expiry
- ALWAYS prefer updating to a maintained alternative over ignoring

### Category 3: TODO/FIXME/HACK Comments (DevSkim)

Code scanners flag `TODO`, `FIXME`, `HACK`, and similar comments as "suspicious" — incomplete functionality indicators.

**Auto-fix**:
```bash
# Find all flagged comments
grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.rs" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" src/

# For each match:
# 1. If the TODO describes work already done → DELETE the comment
# 2. If the TODO describes a trivial improvement → IMPLEMENT it
# 3. If the TODO describes future work → Convert to "NOTE:" with context
# 4. If the TODO is a known limitation → Convert to "NOTE: Known limitation:"
```

**Conversion patterns**:
```rust
// ❌ Flagged by scanner
// TODO: handle error case
// FIXME: this is a workaround
// HACK: temporary fix

// ✅ Not flagged
// NOTE: Error case handled by caller via Result propagation
// NOTE: Workaround for upstream issue #123 — revisit when fixed
// NOTE: Simplified approach — full implementation tracked in issue #456
```

### Pre-Push Scan (Run After All Changes)
```bash
# Scan for remaining TODO/FIXME/HACK in changed files
git diff --name-only HEAD~1 | xargs grep -n "TODO\|FIXME\|HACK" 2>/dev/null

# Verify workflow permissions are restrictive
grep -l "permissions:" .github/workflows/*.yml | while read f; do
  echo "=== $f ==="
  grep -A2 "^permissions:" "$f"
done

# Run dependency audit
cargo audit 2>/dev/null || npm audit --omit=dev 2>/dev/null || true
```

### Dependabot Alert Auto-Fix (MANDATORY before push)

**ALWAYS check and fix open Dependabot alerts before pushing.** Never leave HIGH/CRITICAL alerts unfixed when a patched version exists.

```bash
# 1. Check for open alerts
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/${REPO}/dependabot/alerts" \
  --jq '.[] | select(.state=="open") | "\(.number): \(.security_advisory.severity) — \(.dependency.package.name)@\(.security_vulnerability.vulnerable_version_range) → \(.security_vulnerability.first_patched_version.identifier)"'

# 2. For each alert with a fix: add override + reinstall
# npm: package.json → "overrides": {"pkg@vuln_range": ">=fix_ver"}
# pnpm: package.json → "pnpm.overrides": {"pkg@vuln_range": ">=fix_ver"}
# Then: pnpm install (or npm install)

# 3. Verify fix in lockfile
grep "<package>" pnpm-lock.yaml  # should show patched version

# 4. Commit: "fix: patch <pkg> <CVE> (Dependabot #N)"
```

**Rules:**
- AUTO-FIX any alert where `first_patched_version` exists
- If fix breaks the build, revert and document as known issue
- Never skip HIGH/CRITICAL with available fixes
- Dev-only deps with no prod impact: fix anyway (keeps alert count at zero)

---

## GitHub Actions CI Gate (Post-Push Verification)

**MANDATORY after every `git push` to a repo with GitHub Actions workflows.** After pushing code (feature, fix, or PR), detect if the repo has CI workflows and wait for all checks to pass. If checks fail, investigate the failure logs, fix the issue, and re-push — up to 3 retry cycles.

### Detection
```bash
# Check for workflow files or recent runs
ls .github/workflows/ 2>/dev/null
gh run list --limit 3 2>/dev/null
```

If either returns results, CI verification is active.

### Post-Push Monitoring
```bash
# Wait for checks to register
sleep 5

# If there's a PR, watch PR checks
PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)
if [ -n "$PR_NUM" ]; then
  gh pr checks "$PR_NUM" --watch --fail-fast
else
  # Watch workflow runs for this commit
  for RUN_ID in $(gh run list --commit "$(git rev-parse HEAD)" --json databaseId --jq '.[].databaseId'); do
    gh run watch "$RUN_ID"
  done
fi
```

### On Failure: Fix-and-Retry Loop (Max 3 Attempts)
```bash
# 1. Get failure logs
FAILED_RUNS=$(gh run list --commit "$(git rev-parse HEAD)" --json databaseId,conclusion,name \
  --jq '.[] | select(.conclusion=="failure") | .databaseId')
for RUN_ID in $FAILED_RUNS; do
  gh run view "$RUN_ID" --log-failed 2>&1 | tail -50
done

# 2. Investigate and fix the issue (use 5-phase workflow for complex failures)
# 3. Commit fix and push
# 4. Watch new checks — repeat until green or 3 attempts exhausted
```

### Common CI Failure Fixes
| Pattern | Fix |
|---------|-----|
| `cargo fmt` diff | `cargo fmt --all` locally |
| Lint/style errors | Run linter with `--fix` flag |
| Test failures | Fix test or source code |
| Type errors | Fix TypeScript/type issues |
| Missing i18n | Add translations for all locales |
| `unused_mut` / `dead_code` | Add `#[allow(...)]` for cfg-gated code |
| Code scanning TODO alerts | Convert `TODO`/`FIXME`/`HACK` to `NOTE:` or resolve them |
| Token-Permissions alerts | Add top-level `permissions: read-all`, narrow job-level writes |
| RUSTSEC vulnerability | `cargo audit`, update crate or add exception with rationale |

### Integration
- This gate runs after EVERY `git push` during a `/carmack` session
- Applies to feature implementation, bug fixes, and PR submissions
- Do NOT consider the task complete until all CI checks are green
- After 3 failed attempts, stop and report the persistent failure to the user

## Session Files

Investigations are saved to `tools/debug-sessions/{issue-name}/`:
- `{issue-name}-state.md` — Current phase, what's proven/disproven
- `{issue-name}-evidence.md` — Collected evidence and logs
- `{issue-name}-hypothesis.md` — Tested hypotheses and results

Resume: "Resume the {issue-name} investigation"
