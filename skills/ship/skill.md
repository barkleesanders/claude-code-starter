---
name: ship
user-invocable: true
description: "Safe production deployment with quality gates, safety audits, and rollback. Deploys to PRODUCTION by default."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - WebFetch
model: inherit
---

# /ship - Production Deployment

Execute safe **production deployment** directly with comprehensive quality gates and integrated safety audits. All phases run inline — no subagent.

**Default behavior: Deploys directly to PRODUCTION**

## MANDATORY: FIX ALL ISSUES EVERY RUN (ZERO EXCEPTIONS)

**Every `/ship` invocation MUST execute ALL fix phases in order. NEVER skip a phase for efficiency, even if the code change is small or "just a copy change".**

| Phase | Gate | Must reach |
|-------|------|-----------|
| 0 | Biome lint (full project) | 0 errors, 0 warnings |
| 0 (Stage 1.5) | `npm audit` | 0 vulnerabilities |
| 1 | Build (`tsc --noEmit` + `vite build`) | Exit 0 |
| 1 | Tests (`vitest run --changed` with timeout) | All pass |
| 1.1 | Frontend-backend API contract | 0 missing routes |
| 1.25 | Security audit + Dependabot alerts | 0 open alerts with available fix |
| 1.26 | Code scanning hygiene | Auto-fix all |
| 1.3 | React scope + env safety | No blockers |
| 1.4 | SEO/sitemap consistency | No conflicts |
| 1.42 | Deploy session invalidation | Handlers exist |
| 1.45 | Third-party config, XSS, auth guards | No blockers |
| 1.46 | Admin-user portal sync verification | No BLOCK findings |

**If a phase finds issues, FIX THEM INLINE before moving to the next phase.** Do not defer. Do not warn-and-continue for fixable issues. The goal is: every `/ship` run leaves the repo in a strictly better state than it found it.

**Warnings are NOT acceptable.** `biome check .` must return 0 errors AND 0 warnings. Fix warnings by: (1) auto-fixing with `biome check --fix`, (2) manually fixing remaining issues, or (3) suppressing false positives in biome.json overrides with justification. "Pre-existing warnings" is not an excuse — fix them all.

**Dependabot is NOT optional.** If `gh api repos/{owner}/{repo}/dependabot/alerts` returns open alerts with available fixes, add overrides to `package.json`, run install, verify build, commit, and push — all within this run.

**Stale lockfile check (MANDATORY).** Before fixing Dependabot alerts, check which lockfile(s) the alerts reference (`manifest_path` in the API response). If alerts reference a lockfile the project doesn't use (e.g., `pnpm-lock.yaml` when project uses `bun.lock`), the stale lockfile MUST be deleted from git and added to `.gitignore`.

```bash
# Detect active package manager
ACTIVE_LOCK=""
[ -f bun.lock ] && ACTIVE_LOCK="bun.lock"
[ -f pnpm-lock.yaml ] && ACTIVE_LOCK="pnpm-lock.yaml"
[ -f package-lock.json ] && ACTIVE_LOCK="package-lock.json"

# Remove any OTHER tracked lockfiles that aren't the active one
for STALE in pnpm-lock.yaml package-lock.json bun.lock yarn.lock; do
  if [ "$STALE" != "$ACTIVE_LOCK" ] && git ls-files --error-unmatch "$STALE" 2>/dev/null; then
    git rm --cached "$STALE"
    echo "$STALE" >> .gitignore
    echo "Removed stale lockfile: $STALE (was causing false Dependabot alerts)"
  fi
done
```

**After fixing Dependabot alerts, VERIFY they actually closed.** Wait 60s after push, then re-check:
```bash
sleep 60
REMAINING=$(gh api "repos/${REPO}/dependabot/alerts" --jq '[.[] | select(.state=="open")] | length')
if [ "$REMAINING" -gt 0 ]; then
  gh api "repos/${REPO}/dependabot/alerts" --jq '.[] | select(.state=="open") | "\(.number): \(.dependency.manifest_path)"'
fi
```

---

## Usage

```
/ship [optional instructions]
```

## Deployment Targets

| Command | Target |
|---------|--------|
| `/ship` | **PRODUCTION** (default) |
| `/ship --staging` | Staging first, then prompt for production |
| `/ship --staging-only` | Staging only, no production |
| `/ship --audit` | Run safety audit tiers only (no deploy) |
| `/ship --audit tier2` | Run specific audit tier |
| `/ship --audit full` | Run all audit tiers |
| `/ship --watch-ci` | Block until all CI checks complete after push |
| `/ship --no-ci` | Skip Phase 4.6 CI monitoring entirely |
| `/ship --skip-review` | Skip Phase 4.2 multi-agent code review |
| `/ship --skip-perf` | Skip Phase 4.3 web performance audit |
| `/ship --skip-visual` | Skip Phase 4.35 visual regression check |

## Examples

- `/ship` — Deploy to **production** with full verification
- `/ship the auth feature` — Deploy specific feature to **production**
- `/ship --staging` — Deploy to staging first, then promote to prod
- `/ship --allow-lint-errors` — Override lint failures (with audit trail)
- `/ship --audit` — Run safety audit only, no deployment
- `/ship --audit tier2` — Run Tier 2 investigation audit

## Tools Available

### osgrep — Code Search During Gates
```bash
osgrep query "throw.*module scope" --mode fulltext   # Find risky patterns
osgrep query "validateClientEnv" -n 20               # Find all validation calls
```

### qmd — Documentation Search
```bash
qmd query "deployment checklist"    # Search project docs
qmd query "rollback procedure"      # Find rollback docs
```

### bd — Task Tracking (MANDATORY)
```bash
bd create --title="Deploy: run quality gates" --type=task --priority=1   # Track deployment
bd update <id> --status=in_progress                                       # Claim
bd close <id> --reason="Deployed to production"                           # Close
```

**Before running /ship**: Create a beads issue for the deployment itself (`bd create --title="Deploy <feature>" --type=task`) if one doesn't already exist. Close it only after post-deploy verification passes.

**If `.beads/` does not exist** and this is a git repo:
```bash
git config beads.role maintainer && bd init --quiet --skip-hooks
```

If `bd` is not installed, warn the user once and continue (don't block the deploy).

## CRITICAL: NO TASK MANAGEMENT TOOLS

**DO NOT use TodoWrite, TaskCreate, or TaskUpdate tools.** Use `bd` (beads) for task tracking instead. This is a project-wide rule — see CLAUDE.md "Beads Task Tracking Rule".

Print a short status line when transitioning phases:
```
-- Phase 0 OK -> Phase 1: Build & Test --
```

Just execute the phases in order. Do the work, don't track the work in TodoWrite.

## DEPLOYMENT TARGET (DEFAULT: PRODUCTION)

**Default behavior**: Deploy directly to production. The `/ship` command deploys to production unless explicitly told otherwise.

**Staging-first workflow**: If user specifies "staging first", "to staging", or `--staging`:
1. Deploy to staging/preview environment first
2. Display staging URL and verification steps
3. Wait for explicit "promote to production" confirmation
4. Then run production deployment

**Flags**:
- (default): Deploy to production
- `--staging` or "to staging first": Deploy to staging, then prompt for production
- `--staging-only`: Deploy to staging only, skip production
- `--prod` or `--production`: Explicit production deploy (same as default)
- `--no-babysit`: Skip Phase 6 PR babysitter
- `--babysit`: Force Phase 6 even on default branch (monitor CI after direct push)

## EXECUTION PROTOCOL

### CODE SEARCH

Use standard tools (Grep, Glob, Read) for code discovery. Use `osgrep` if available for AST-aware search, but never block on it — fall back to Grep/Glob immediately if unavailable.

---

## Reference Files Index

All reference files are in `~/.claude/skills/ship/references/`. Read the relevant ones for each phase.

| File | Phases | Content |
|------|--------|---------|
| `pre-deploy-checks.md` | -1, -0, 0.5 | Repo context verification, merge conflict resolution, Vercel rate limit check |
| `code-quality.md` | 0 | Biome lint auto-setup/fixing, zero-tolerance policy, AI-powered fix loop, npm audit |
| `build-and-test.md` | 1, 1.1 | Build verification, smart test execution (timeout/pkill), API contract check |
| `security-audit.md` | 1.25, 1.26 | Security audit, Dependabot auto-fix, code scanning hygiene (OpenSSF, DevSkim) |
| `react-safety.md` | 1.3, 1.35 | React scope/env safety checks, useEffect abuse detection |
| `seo-and-session.md` | 1.4, 1.42 | SEO/sitemap consistency, FOUC prevention, session invalidation (chunk load recovery) |
| `infra-and-admin.md` | 1.45, 1.46, 1.5 | Third-party config, CSP audit, XSS checks, admin auth, infra protection, admin-user sync, risky change verification |
| `deployment.md` | 2, 3, 3.5, 4 | Override path, GitHub push, README/changelog, Vercel/Cloudflare/Docker deploy |
| `post-deploy.md` | 4.1-4.6, 5, 6 | Post-deploy verification, multi-agent review, web perf, visual regression, rollback, CI gate, monitoring, PR babysitter |
| `~/.claude/skills/shared/ant-verification-protocol.md` | 1.27, 1.28 | **Ant-level quality gates**: OWASP Top 10 sweep, supply chain audit, enhanced security review |

---

## Phase Execution Order

Read ALL reference files at the start of a `/ship` run. Execute phases in this exact order:

1. **Phase -1**: Repository context verification (from `pre-deploy-checks.md`)
2. **Phase -0**: Merge conflict auto-resolution (from `pre-deploy-checks.md`)
3. **Phase 0**: Code quality / lint auto-fixing (from `code-quality.md`)
4. **Phase 0.5**: Deployment rate limit check (from `pre-deploy-checks.md`)
5. **Phase 1**: Build & test (from `build-and-test.md`)
6. **Phase 1.1**: API contract verification (from `build-and-test.md`)
7. **Phase 1.25**: Security audit (from `security-audit.md`)
8. **Phase 1.26**: Code scanning hygiene (from `security-audit.md`)
9. **Phase 1.3**: React scope & env safety (from `react-safety.md`)
10. **Phase 1.35**: useEffect abuse check (from `react-safety.md`)
11. **Phase 1.4**: SEO & sitemap consistency (from `seo-and-session.md`)
12. **Phase 1.42**: Session invalidation check (from `seo-and-session.md`)
13. **Phase 1.45**: Third-party config & infra protection (from `infra-and-admin.md`)
13.5. **Phase 1.27**: OWASP Top 10 sweep on changed files (from `ant-verification-protocol.md` Section 1)
13.6. **Phase 1.28**: Supply chain & enhanced review on new deps (from `ant-verification-protocol.md` Section 5)
14. **Phase 1.46**: Admin-user sync verification (from `infra-and-admin.md`)
15. **Phase 1.5**: Deployment verification for risky changes (from `infra-and-admin.md`)
16. **Phase 2**: Manual override path (from `deployment.md`)
17. **Phase 3**: GitHub deployment (from `deployment.md`)
18. **Phase 3.5**: README & changelog auto-update (from `deployment.md`)
19. **Phase 4**: Downstream deployments (from `deployment.md`)
20. **Phase 4.1**: Post-deploy verification (from `post-deploy.md`)
21. **Phase 4.2**: Multi-agent code review (from `post-deploy.md`)
22. **Phase 4.3**: Web performance audit (from `post-deploy.md`)
23. **Phase 4.35**: Visual regression check (from `post-deploy.md`)
24. **Phase 4.5**: Deployment failure rollback (from `post-deploy.md`)
25. **Phase 4.6**: GitHub Actions CI gate (from `post-deploy.md`)
26. **Phase 5**: Post-deploy monitoring (from `post-deploy.md`)
27. **Phase 6**: PR babysitter (from `post-deploy.md`)

---

## Pre-Ship Verification Checklist (Non-Negotiable)

Before declaring ANY deploy complete, verify ALL of these:

1. **Bundle hash changed** — `curl -s <URL> | grep 'index-'` must show a NEW hash vs. previous deploy
2. **Page loads correctly** — curl the actual page, verify it returns 200 and contains expected content
3. **API endpoints work** — test at least one authenticated endpoint returns data, not "Unauthorized"
4. **New routes reachable** — if you added a route, verify it doesn't 404 or get swallowed by a catch-all
5. **No stale cache** — if `cf-cache-status: HIT`, verify it's serving the new content not old
6. **Clean build** — for Cloudflare Workers: `rm -rf dist && tsc -b && vite build && wrangler deploy` (never just `wrangler deploy`)
7. **Type definitions correct** — for CF Workers, edit `worker-configuration.d.ts` (ambient), not just `src/worker/env.d.ts` (module)

**If ANY check fails: do NOT say "deployed successfully". Fix it first.**

## Safety Audit Tiers

### Tier 1 — Critical (always runs on deploy)
- Silent failure detection — env vars without validation
- Silent React startup failures — env validation throwing before mount
- Security audit — vulnerabilities, exposed secrets
- Test execution verification

### Tier 2 — Investigation (`--audit tier2`)
Uses `systematic-debugging`:
- Blind spot auditor — edge cases missing test coverage
- Test quality gate — tests that pass but don't verify real behavior
- Rate limit protector — public endpoints missing rate limiting

### Tier 3 — Deep Analysis (`--audit tier3`)
Uses `carmack-mode-engineer`:
- Code archaeology — "old/legacy" code that's actually critical
- Critical systems guard — unprotected auth/payment/data-deletion paths
- Build reproduction harnesses for complex issues

### Full (`--audit full`)
Runs all three tiers in sequence.

---

## Cross-Platform CI Verification (Rust/Multi-Platform PRs)

**For PRs to open source Rust projects with multi-platform CI matrices:**

```bash
# 1. Format check (CI rejects ANY formatting diff)
cargo fmt --all -- --check

# 2. Clippy with warnings-as-errors
cargo clippy --all-targets --all-features

# 3. Check for conditional compilation blind spots
grep -n "let mut" src/**/*.rs | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  var=$(echo "$line" | grep -oP 'let mut \K\w+')
  if grep -A20 "let mut $var" "$file" | grep -q '#\[cfg(target_os'; then
    echo "WARNING: $file — $var may need #[allow(unused_mut)]"
  fi
done
```

After push: `gh pr checks <PR_NUMBER> --watch`

---

## OUTPUT REQUIREMENTS

- Always show clear phase headers marking current stage
- Use visual indicators for success, failure, warnings
- Display progress bars for multi-step operations
- Provide actionable error messages when builds or tests fail
- Show deployment summary table with service name, status, and live URL
- Include estimated time for each phase
- Display comprehensive banners at phase transitions

---

## SAFETY CONSTRAINTS

### Critical Rules:
- **FAIL FAST**: Terminate immediately on build errors or test failures
- **GitHub deployment ALWAYS happens before any other platform**
- **Multiple confirmation gates prevent accidental shipping**
- **All override actions are permanently logged**
- **Never silently skip tests or quality checks**
- **Refuse ambiguous commands that might bypass gates**
- **Data verification is mandatory for risky changes unless explicitly overridden**
- **NEVER execute destructive infrastructure commands** — these require human execution
- **NEVER modify or replace .tfstate files**
- **ALWAYS show terraform plan output to user** before any terraform apply

### Phase-Specific Rules:
- Phase -1: NEVER proceed if not in git repo or remote unreachable
- Phase 1: NEVER run `npm test` or full `npx vitest run` — always use `--changed` and `timeout`
- Phase 1: NEVER retry tests more than 3 times — stop and report failures
- Phase 1: ALWAYS run `pkill -f vitest 2>/dev/null` after every test invocation
- Phase -0: NEVER push or tag during merge conflict resolution
- Phase 0: NEVER deploy with lint errors unless explicit override
- Phase 0: After Biome auto-fix on inline-HTML projects (CF Workers, SSR), ALWAYS run embedded JS string safety check (Stage 1.7 in code-quality.md) — Biome's noUselessEscapeInString silently breaks JS inside HTML template strings
- Phase 0.5: BLOCK on 20+ deployments unless --force-override
- Phase 1: BLOCK on ANY test failure
- Phase 1.1: BLOCK if frontend calls API endpoints with no backend handler
- Phase 1.25: BLOCK on MODERATE+ vulnerabilities unless override
- Phase 1.26: WARN on TODO/FIXME/HACK comments in changed files (auto-fix to NOTE:)
- Phase 1.26: WARN on workflow files missing top-level permissions (auto-fix to read-only)
- Phase 1.26: BLOCK on `permissions: write-all` at workflow top level (must narrow to job-level)
- Phase 1.3: BLOCK if env validation throws at module scope without fallbacks
- Phase 1.4: BLOCK if noindex pages appear in sitemap or sitemaps are out of sync
- Phase 1.42: BLOCK if no vite:preloadError handler (deploy will log users out)
- Phase 1.42: BLOCK if no CDN-Cache-Control: no-store header on HTML responses
- Phase 4.2: Run multi-agent review when changes span 3+ files or touch security paths
- Phase 4.2: BLOCK if any reviewer finds CRITICAL security/performance issue
- Phase 4.3: WARN if Lighthouse score drops below 50 (severe perf regression)
- Phase 4.35: BLOCK if mobile screenshot shows blank page (broken rendering)
- Phase 4.35: WARN if mobile screenshot shows horizontal scroll (responsive bug)
- Phase 4: WARN if deployed version.json SHA doesn't match local HEAD (stale deploy)
- Phase 4: BLOCK if `CLOUDFLARE_API_TOKEN` in `.env.local` overrides wrangler OAuth (auth conflict)
- Phase 4: Verify `version.json` is in `.gitignore` and not git-tracked (prevents stale commits)
- Phase 4: Verify service worker has `version.json` in NETWORK_ONLY patterns (prevents SW caching)
- Phase 1.46: BLOCK if visibility refetch triggers loading spinner (full-screen flash on tab switch)
- Phase 1.46: WARN if user data hooks lack background refresh (admin changes invisible until reload)
- Phase 1.46: WARN if admin status-change endpoints don't clean up dependent fields
- Phase 1.46: WARN if optimistic updates don't re-sync with server after success
- Phase 1.45: BLOCK if CSP img-src/script-src/connect-src missing third-party CDN domains (broken icons with no console errors)
- Phase 1.45: BLOCK if critical third-party env vars missing from wrangler config
- Phase 1.45: BLOCK if raw `.innerHTML =` without escapeHtml() (XSS risk — especially entry points outside src/)
- Phase 1.45: BLOCK if dangerouslySetInnerHTML without DOMPurify (XSS risk)
- Phase 1.45: BLOCK if JSON.stringify in script tag without `</` escaping (script breakout)
- Phase 1.45: WARN if async onClick without disabled state (double-click risk)
- Phase 1.45: WARN if pages call secureFetch without frontend auth guard (degraded UX)
- Phase 1.45: WARN if admin routes throw Error instead of HTTPException(403)
- Phase 1.5: NEVER skip verification if migrations/backfills detected
- Phase 3.5: NEVER update README if tests didn't pass 100%
- Phase 4: NEVER report success without URL verification
- Phase 4.5: NEVER auto-rollback without user confirmation
- Phase 6: NEVER merge the PR automatically — only humans merge
- Phase 6: NEVER force-push, dismiss reviews, or override branch protection
- Phase 6: NEVER modify files outside the PR's changeset
- Phase 6: Max 5 fix-push cycles, max 30 min runtime — then exit with report
- Phase 1.5: NEVER run terraform destroy or apply -auto-approve
- Phase 1.5: BLOCK if terraform plan shows resources being destroyed

---

## Output Discipline (from internal conciseness anchors)

Between tool calls: **max 1-2 sentences** explaining the next action.
Final deployment summary: concise bullet points, no preamble.
When fixing issues inline: state what was wrong and what was done in one line each.
Never repeat tool output back to the user — they already see it.
Phase transitions: one-line banner only (e.g., `-- Phase 0 OK -> Phase 1: Build & Test --`).

## TONE

Be authoritative and safety-focused. Be firm about quality requirements while remaining helpful when errors occur. Emphasize that quality gates protect the user, their data, and their users. When blocking deployment, clearly explain why and provide specific remediation steps.

---

## Instructions

When this skill is invoked:

**STEP 1 — Read all reference files:**

Read all 9 reference files from `~/.claude/skills/ship/references/` PLUS `~/.claude/skills/shared/ant-verification-protocol.md` (ant-level quality gates) to have full deployment protocol available.

**STEP 2 — Execute phases in order:**

Follow the Phase Execution Order above, reading the detailed instructions from the corresponding reference file for each phase. Fix all issues inline before advancing to the next phase.

**STEP 3 — Verify before declaring success (Ant-Level Truthfulness Protocol):**

Run the Pre-Ship Verification Checklist. Apply the Truthfulness Protocol from ant-verification-protocol.md Section 2:
- Every claim must be backed by command output (curl, build log, test result)
- Never say "deployed successfully" without curl evidence of new bundle hash
- If ANY check fails, fix it — don't report success with caveats
