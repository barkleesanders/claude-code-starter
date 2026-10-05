# Deployed-but-unmerged branches, stale PRs, and client source-map exposure

Three related failure classes, all measured on AIVA-Frontend in Sept 2026, all
invisible to a diff-conditioned gate. Tools:

- `~/.claude/skills/ship/tools/deployed-unmerged-check.sh [repo] [--sha <deployed>]`
- `~/.claude/skills/ship/tools/sourcemap-exposure-check.sh [repo] [--live <origin>] [--live-path <p>]`

Both: exit 0 ok · 1 finding · 2 UNMEASURED (never a pass).

## 1. Deployed-but-unmerged (the regression-in-waiting)

**Shape.** A PR branch passes every gate and is deployed straight from the
branch (`wrangler deploy` from `fix/…`). The PR is never merged. The repo's
`main` is auto-deployed on every push (Cloudflare Workers Builds "Deploy default
branch", GitHub Actions, Vercel/Netlify production branch…). The next push to
main — anyone's, any time — rebuilds from main and **silently removes the fix
from production**, with a green build and no error anywhere.

**Measured instances (AIVA-Frontend):**
| PR | Deployed from branch | Merged to main | Exposure |
|---|---|---|---|
| #276 durable SMS STOP | 0367e4c7 → 7e00d346 on 2026-09-11 | 2026-09-20 (this fix) | **9 days**; every main push in between (there were several) regressed STOP durability |
| #286 hidden sourcemaps | 5cc34865 → 16f4a84e on 2026-09-20 | 2026-09-20, same day | hours — caught by this gate's first run: `REGRESSION-RISK 5cc34865 (origin/fix/hidden-sourcemaps-no-map-serving)` |

**Why the old rule produced it.** `/ship` Phase 6 said *"NEVER merge a remote PR
automatically"* and the code policy said *"merge to main only when NO
auto-deploy is detected"* — so on exactly the repos where an unmerged deploy is
dangerous (auto-deploy-on-main), the agent was told to deploy the branch and
walk away. The two rules composed into the failure.

**Rule (replaces the line-989 absolute):**
1. **Phase -1.6 (pre-deploy, every ship, unconditioned on the diff):** run
   `deployed-unmerged-check.sh`. Any `REGRESSION-RISK` line = a prior deploy
   that main would undo. Resolve it in THIS ship (merge that PR under the
   existing authorization, or record the user's explicit decision to drop it)
   before adding a new branch deploy on top.
2. **Phase 4.9 (post-deploy):** when `auto-deploy-on-main: yes` and the deploy
   was from a non-main ref, **the same authorization that covered the deploy
   covers merging that PR to main** — do it in-session (`gh pr merge N --merge`,
   never bypassing branch protection; if protection requires a human review,
   that is the blocker to report, not a reason to leave it unmerged). Then let
   the auto-deploy rebuild main, re-verify the served artifact, and record the
   SHA-pinned ledger line. A branch deploy that ends the session unmerged on an
   auto-deploy repo is an incomplete ship and must be stated as such in the
   final report.
3. **Detection is real, not inferred:** the check reads the Workers Builds
   trigger via the commit's check-run → build uuid →
   `GET /accounts/<acct>/builds/builds/<uuid>` → `result.trigger.deploy_command`
   ("npx wrangler deploy" on `main` = auto-deploy; "versions upload" = not).
   Falls back to grepping `.github/workflows`; `unknown` is treated as
   auto-deploy because a wrong "no" is the expensive error. (`?worker_name=`
   list filters are rejected by that API — always go through the check-run.)
4. **`ls a b c` is not a file test.** The first version printed `unknown` on
   AIVA because `ls wrangler.json* wrangler.toml` exits 2 when any glob misses.
   Loop over candidates with `[ -f ]`.

## 2. Stale open PRs

Every ship sweeps `gh pr list` (the same script prints number / mergeable /
mergeStateStatus / DRAFT / updatedAt / branch / title). Report every non-draft
PR older than 7 days with its state; a `CONFLICTING` PR whose branch was
deployed is class 1 above and blocks. Drafts are listed, never merged.

## 3. Client source-map exposure (audit item #11)

**Shape.** `vite.config.ts` `build.sourcemap: true` (or `'inline'`, or Next's
`productionBrowserSourceMaps: true`) → every served bundle carries
`//# sourceMappingURL=` and the host serves the `.map` (AIVA: 1.55 MB, full
`sourcesContent`, 17 first-party files — the entire unminified SPA).

**Fix shape (two independent controls, both required):**
- bundler: `sourcemap: "hidden"` — maps still emitted for the Worker's
  `upload_source_maps` stack traces, no browser-visible pointer.
- host: `public/.assetsignore` with `*.map` — `@cloudflare/vite-plugin` merges
  it into `dist/client/.assetsignore`; wrangler applies gitignore rules to the
  asset walk (`WRANGLER_LOG=debug wrangler deploy --dry-run | grep 'Ignoring asset:'`).
- lock both with a test (AIVA: `tests/client-sourcemaps-not-served.test.ts`).

**Gate:** Phase 1.4s pre-deploy `sourcemap-exposure-check.sh <repo>` (config +
built artifact); Phase 4.1 post-deploy `--live https://<origin>` (every script
bundle on `/`, `/dashboard`, `/app` + `--live-path`: no `sourceMappingURL=`,
`.map` → 404/410; 200 = FAIL; 403/000 = UNMEASURED). Positive control verified
2026-09-20: re-injecting `sourcemap: true` + a pointing bundle + a bare
`wrangler.toml` → 3 FAIL lines, rc=1.
