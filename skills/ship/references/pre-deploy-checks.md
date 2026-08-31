# Pre-Deploy Checks

Covers Phase -1 (repository context verification), Phase -0 (merge conflict resolution), and Phase 0.5 (deployment rate limit check).

---

## Phase -1: REPOSITORY CONTEXT VERIFICATION (ALWAYS FIRST)

**Purpose**: Verify you're in the correct repository and establish baseline information.
**Execution**: MUST run before any other phase.

1. **Verify Git Repository**:
   - Run: `git rev-parse --is-inside-work-tree 2>/dev/null`
   - If not in git repo: **STOP** - Display error: "Not in a git repository. Navigate to your project directory first."
   - If in git repo: Continue

2. **Identify Repository Context**:
   - Extract repository information:
     - REPO_URL: `git config --get remote.origin.url`
     - REPO_NAME: `basename -s .git "$REPO_URL"` or extract from URL
     - CURRENT_BRANCH: `git rev-parse --abbrev-ref HEAD`
     - WORKING_DIR: `pwd`
     - LAST_COMMIT: `git log -1 --oneline`
     - UPSTREAM: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`

3. **Display Repository Context Banner**:
   ```
   ════════════════════════════════════════════════════════════
   SHIP WORKING CODE - Repository Context
   ════════════════════════════════════════════════════════════

   Repository: $REPO_NAME
   Remote URL: $REPO_URL
   Branch: $CURRENT_BRANCH
   Directory: $WORKING_DIR

   ════════════════════════════════════════════════════════════
   ```

4. **Verify Remote Repository Accessibility**:
   - Run: `git ls-remote --exit-code origin HEAD >/dev/null 2>&1`
   - If successful: "Remote repository accessible"
   - If failed: **STOP** - Display error: "Cannot reach remote repository."

5. **Check Working Directory State**:
   - Run: `git status --porcelain`
   - If output is empty: "Working directory clean"
   - If output exists: Display uncommitted changes and offer options:
     1. Stage all changes and continue (git add -A)
     2. Cancel deployment
   - Execute user's choice accordingly

6. **Protected Branch Detection**:
   - Check if current branch matches protected patterns: `main|master|production|prod|release`
   - If on protected branch: Display warning and require explicit YES/NO confirmation
   - If NO: **STOP** deployment
   - If YES: Log warning and continue

7. **Verify Branch Tracking**:
   - Run: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
   - If no upstream: Offer options to set upstream or continue without
   - If upstream exists: Check ahead/behind status

7.5. **Deploy-Target Collision Check (Cloudflare Workers — added 2026-07-06)**:
   **Purpose**: never let this checkout's `wrangler deploy` silently clobber a DIFFERENT project's production worker, and never deploy a repo whose domain is actually served by another checkout.
   - **Same-name collision**: grep the fleet for other checkouts declaring this worker `name`:
     `grep -rl "name = \"<name>\"\|\"name\": \"<name>\"" ~/ --include='wrangler.*' 2>/dev/null | grep -v node_modules` — two checkouts with one name means a deploy from the wrong one overwrites the other's prod (found live 2026-07-06: `oak311-doge/wrangler.toml` had `name = "improvebayarea"`; a naive deploy from the oak311 checkout would have clobbered improvebayarea.com). Deploy only from the canonical checkout; env-scoped deploys must pass `--env` explicitly.
   - **Same-domain claim**: if another local repo's config claims the same routes/domains, resolve which worker ACTUALLY serves the domain before deploying either — `GET zones/{id}/workers/routes` + `GET accounts/{id}/workers/domains?zone_id=` (found live 2026-07-06: `example.com` and `example.com-1` both claimed example.com/*; the live zone showed custom domains → `example-com`, making `-1`'s `cache-buster` stale — deploying it would have been a no-op-at-best config trap). The API answer wins over both configs.

8. **Auto-Deploy Surface — detect & DISPLAY (MANDATORY — added 2026-06-25)**:
   **Purpose**: tell the user, up front, whether a push to the production branch **auto-deploys**, and whether this checkout is safe to deploy from. **Verify — never assert** the deploy path (the 2026-06-25 session asserted a CF Workers-Builds auto-deploy that did NOT exist; ground-truth showed example has no platform auto-deploy and ships via manual CLI `wrangler deploy`).
   - **GitHub Actions:** read **`origin/main`**, not the local checkout (a behind worktree shows stale/deleted workflows). `git fetch -q origin; for f in $(git ls-tree -r --name-only origin/main .github/workflows/); do git show "origin/main:$f" | grep -qiE 'wrangler-action|pages-action|wrangler (deploy|pages)|CLOUDFLARE_API_TOKEN|command:\s*(deploy|pages)|run deploy|vercel|netlify deploy|actions/deploy-pages' && echo "$f"; done` then confirm a hit's `on:`/`branches:` includes the prod branch. Cross-check empirically with `gh workflow list` + `gh run list --limit 10` (a `workflow_run: ["Deploy"]` ref can be orphaned).
   - **Cloudflare Pages / Workers Builds (query the API):** with `~/.cloudflared/cf-global-api-key.json`. **Match the prod DOMAIN, not a project name** (red-herring `*.pages.dev` projects exist). Pages auto-deploys only if `GET .../pages/projects/<name>` shows `source.type` github/gitlab + a `production_branch` (null `source`/`ad_hoc` = not auto). Workers Builds: live worker's latest version annotation `workers/triggered_by` == `build` (Build) vs `version_upload` (plain `wrangler deploy`); `builds/triggers` 404 ⇒ no Build.
   - **Blind spot:** these find only *platform* auto-deploy. Manual/CLI `wrangler deploy` or an off-platform cron can ship `main` invisibly to the APIs. "No auto-deploy detected" = the push won't itself deploy; it does NOT mean main is decoupled from prod. If unsure, ASK the user.
   - **Vercel** (`.vercel/project.json`) / **Netlify** (`netlify.toml` + linked site) / other CI (Render/Fly/Railway/Amplify) with a prod-branch deploy hook.
   - **Stale-checkout guard:** `git fetch -q origin && git rev-list --left-right --count origin/<prodbranch>...HEAD` — if HEAD is **BEHIND** origin's prod branch, deploying from here would **REGRESS production**. **STOP** and require deploying from a current checkout (the 375-commits-behind worktree trap, 2026-06-25).
   - **DISPLAY** a banner before proceeding, e.g.:
     ```
     AUTO-DEPLOY: ⚠️ YES — <mechanism> deploys <branch> on push (a push to <branch> = a prod deploy)
                  — or —  none detected — deploy is manual (this skill performs it)
     CHECKOUT:    ✅ current with origin/<branch>   — or —  ⛔ BEHIND by N commits → DO NOT deploy from here
     ```
   - If AUTO-DEPLOY is YES, make sure the user understands a push itself ships. If CHECKOUT is BEHIND, **STOP** (do not deploy stale code).

9. **Display Repository Summary** with all verification results before proceeding to Phase -0

---

## Phase -0.5: WORKTREE SAFETY GATE (MANDATORY — 2026-05-10)

**Right-branch check (2026-07-21):** before deploying, confirm the change being shipped is on **main**, not stranded on a divergent feature branch. If `git branch --show-current` is a feature branch that is ahead of / behind `origin/main`, reconcile FIRST (cherry-pick the shippable change onto main, or merge the branch) — do not deploy a feature branch to prod to work around a mis-placed commit. Enforced at commit time by the PreToolUse hook `pre-bash-commit-branch-guard.sh`. Reference incident: a robots.txt hotfix landed on `feat/explain-gap-and-close-it` (11 ahead of main) and could only ship after a cherry-pick + full branch reconciliation.

**Purpose**: Never deploy work that exists only on a local worktree branch with no remote backup. Prevents the silent-loss class that wiped the trust pages on 2026-05-10.

**When this fires**: ALWAYS, even on the main checkout. The check is fast (sub-second) and is no-op when there's nothing at risk.

**Logic**:

1. Walk every worktree via `git worktree list --porcelain`.
2. For each non-main worktree, check:
   - `git status --porcelain` — uncommitted changes
   - `git rev-list --count @{u}..HEAD` — commits ahead of upstream
   - Branch has no upstream → all commits are local-only
3. If ANY worktree has uncommitted or unpushed work:
   - **BLOCK** the deploy
   - List each worktree + its specific risk
   - Print the recovery commands the user / agent should run

**Recovery (per worktree)**:
```bash
cd <worktree-path>
git status                                    # confirm what's loose
git add -A && git commit -m "wip: pre-ship snapshot"   # if dirty
git push -u origin HEAD                       # always
```

**Override**: `--allow-unpushed-worktree` flag, plus the destructive-op env override `CLAUDE_ALLOW_WORKTREE_LOSS=1` for the post-deploy cleanup commands. Both are logged to the audit trail.

**Trusts the hooks but verifies**: the `post-bash-worktree-autopush.sh` PostToolUse hook should have already pushed every commit. This phase is the last line of defense — if it fires, something failed silently (network, auth, conflict) and `~/.claude/logs/worktree-autopush.log` will explain.

---

## Phase -0.4: WORKERS CACHE SAFETY GATE (MANDATORY for CF Workers — added 2026-07-06)

**Purpose**: A Worker with `cache.enabled: true` (the [Workers Cache](https://developers.cloudflare.com/workers/cache/configuration/) feature) must be enabled *correctly and safely* before it ships. The dangerous class: Workers Cache **heuristically caches any `200` response with no `Cache-Control` for 2 hours** — so a cookie/session-authed GET returning `200` with no `Set-Cookie` and no `Cache-Control` on that response gets cached and served **cross-user** (data leak). The 2026-07-06 audit nearly blanket-enabled it on AIVA (135 Clerk-cookie-authed no-header GET routes) — the gate exists to stop exactly that.

**When this fires**: any repo whose wrangler config sets `cache.enabled: true`. No-op otherwise.

**Run**: `~/.claude/skills/ship/tools/workers-cache-check.sh <repo-dir>` — checks:
1. `cache.enabled` is actually true (skips cleanly if absent/false).
2. **wrangler ≥ 4.69** — below that the flag is silently IGNORED at deploy (feature inert). WARN.
3. Only `enabled` / `cross_version_cache` keys under `cache` (others → wrangler validation error). BLOCK.
4. **The leak class**: if a cookie/session **auth surface** exists (`getAuth`/`clerk`/`getCookie`/`session*`/`userId`…) AND there is **no global `no-store` default** (a middleware defaulting responses to `no-store`, or the per-entrypoint gateway pattern), it **BLOCKS** (exit 2). Fix = default every response to `Cache-Control: private, no-store` and have public routes explicitly opt in to `public, max-age=…` (reference: `improvebayarea/src/cache_headers.ts`), or disable cache on the `default` entrypoint via the `exports` map.

**Re-verify against LIVE docs (do not trust the cached assumptions in the script)**: `WebFetch https://developers.cloudflare.com/workers/cache/configuration/` and confirm the min wrangler version, the "no-Cache-Control ⇒ heuristically cached" rule, and the allowed `cache` keys still hold. The config surface is new (shipped 2026-07) and may change.

**Full pattern + safe-enable recipe:** `~/.claude/skills/shared/workers-cache-safety.md` (shared with /carmack and /debug).

**BLOCK on exit 2.** Override only with explicit user acknowledgement that no cookie-authed route can return an uncacheable-but-unmarked `200`.

---

## Phase -0: MERGE CONFLICT AUTO-RESOLUTION

**Purpose**: Ensure the working tree is conflict-free, validated, and committed before linting or testing begins.
**Execution**: Always operate from repository root. Skip automatically if no conflicts detected.

1. **Detect Conflicts**:
   - Run: `git status --porcelain | cat` and collect paths with `U` status codes
   - Scan files for merge markers using `rg -l "<<<<<<<"`
   - If no conflicts found: Display "No merge conflicts found" and continue to Phase 0

2. **Resolve Conflicts (Non-interactive)**:
   - Manifest/lock files: Regenerate via package manager instead of manual edits
   - Generated artifacts: Re-run the generator to avoid hand-merging
   - Configuration files: Merge both sides' safe keys, prefer stricter rules
   - Source/text content: Preserve both logical intents where possible
   - Binary files: Default to current branch (ours)
   - Delete all conflict markers before moving on
   - Never prompt the user - choose sensible defaults

3. **Validate Builds & Tests**:
   - Detect ecosystem and run appropriate install/build/test commands
   - If validation fails, iterate on merges or revert until tests pass

4. **Finalize**:
   - Stage everything: `git add -A`
   - Commit locally: `git commit -m "chore: resolve merge conflicts"`
   - Never push or tag in this phase
   - Output concise summary of decisions made
   - Only proceed to Phase 0 when `git status --porcelain` is clean

---

## Phase 0.5: DEPLOYMENT RATE LIMIT CHECK (VERCEL PROTECTION)

- Check if project has Vercel deployment (vercel.json exists)
- If Vercel project detected:
  - Check deployment count from last 4 hours
  - Categorize risk level:
    - < 5 deployments: SAFE
    - 5-10 deployments: CAUTION - Warn, ask confirmation
    - 10-20 deployments: WARNING - Strong warning, ask confirmation
    - 20+ deployments: CRITICAL - **BLOCK** deployment
  - If rate limited: Display bypass URL, estimated wait time, offer --force-override
- If not Vercel project: Skip to Phase 1


## Remote CLI / agent-runtime deploy verification (Mac mini · Hermes · launchd) — MANDATORY (2026-06-19)

When a deploy installs a CLI/tool/script on a **remote runner** (Mac mini, Hermes host) for
unattended/agent use, "files copied" is NOT "works on the runner". Before declaring done:

1. **Pin absolute interpreter paths** in the shim AND the launchd plist / Hermes script —
   non-interactive ssh, launchd, and cron run with a bare PATH (no Homebrew, no `~/.local/bin`); a
   `#!/usr/bin/env node` shebang fails there. Put node at `/opt/homebrew/bin/node`; set plist `PATH`.
2. **Verify via the REAL invocation path, not an interactive shell.** Run the actual launchd-/Hermes-
   invoked command: `launchctl kickstart gui/$(id -u)/<job>` then read the log;
   `hermes cron list`/run the tracker script directly; `ssh host 'PATH=… <tool> --json'`. Confirm real
   output (live data), exit code, and that the job appears loaded.
3. **A `which`/`grep` over `ssh host 'cmd'` (BatchMode) false-negatives** (bare PATH) — never conclude
   "not installed / job missing" from it; probe absolute paths. (See the matching blind-spots entry.)
4. **Secrets / session state**: gitignore captured cookies/tokens; give the remote a refresh path
   (a capture host pushes fresh state; a keepalive timer keeps a session warm). Split work per the
   cron-routing rule: deterministic ping → launchd timer; interpret-and-notify → Hermes cron
   (`--no-agent --deliver origin`).

Reference incident: 2026-06-19 caltrans-pra → mac-mini — node + hermes both "not found" via BatchMode
ssh but present; verified only after running the real launchd keepalive (HTTP 200 log) + `hermes cron
list` with an explicit PATH + the tracker script (rc=0, state written with live request data).
