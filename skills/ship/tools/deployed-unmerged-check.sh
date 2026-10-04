#!/usr/bin/env bash
# deployed-unmerged-check.sh — /ship Phase -1.6 + Phase 4.9 (added 2026-09-21)
#
# Catches the "deployed from a branch, never merged to main" regression on a
# repo whose main branch is AUTO-DEPLOYED (Cloudflare Workers Builds "Deploy
# default branch", a GitHub Action deploying on push to main, Vercel/Pages Git
# integration). On such a repo a branch deploy is a SCHEDULED REGRESSION: the
# next push to main rebuilds main and overwrites it, and nothing announces it.
#
# Real incidents this exists for (both AIVA-Frontend, Workers Builds):
#   - PR #276 codex/stop-retry-alert: commit 0367e4c7 deployed 2026-09-11 as
#     worker 7e00d346 ("Production is deployed; this PR remains unmerged").
#     main never received it; the 2026-09-14 consent reconciler shipped on top
#     and prod silently lost durable STOP handling for 10 days.
#   - PR #286 fix/hidden-sourcemaps: deployed 2026-09-21 00:26Z as 16f4a84e
#     from the PR branch; any push to main before the merge would have served
#     client source maps again.
#
# Three outcomes, never two: each line is OK / REGRESSION-RISK / UNMEASURED.
# Exit 0 = every measurable deploy is on main (or the repo does not auto-deploy
# main); exit 1 = at least one deployed SHA is NOT an ancestor of origin/main;
# exit 2 = could not measure (no ledger, no remote, gh unavailable) — never a
# pass; say so in the report.
#
# Usage: deployed-unmerged-check.sh [repo-root] [--sha <deployed-sha>]
#   --sha   also evaluate one SHA you just deployed (Phase 4.9), on top of the
#           ledger's entries.
# Inputs it reads (all optional, each reported when absent):
#   deploy-log.jsonl   one JSON object per deploy with git_sha (AIVA's ledger)
#   gh pr list         open PRs: mergeability, age, and whether a deployed SHA
#                      belongs to an open (unmerged) PR branch
set -uo pipefail

ROOT="${1:-.}"; [ "$ROOT" = "--sha" ] && ROOT="."
EXTRA_SHA=""
while [ $# -gt 0 ]; do
  case "$1" in --sha) EXTRA_SHA="${2:-}"; shift 2;; *) shift;; esac
done
cd "$ROOT" 2>/dev/null || { echo "UNMEASURED: $ROOT is not a directory"; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "UNMEASURED: not a git repo"; exit 2; }

LEDGER_N=$(git ls-remote --exit-code origin >/dev/null 2>&1 && echo yes || echo no)
git fetch -q origin main 2>/dev/null || true
git rev-parse --verify -q origin/main >/dev/null || { echo "UNMEASURED: no origin/main (fetch failed or no remote)"; exit 2; }

# --- 1. Does main auto-deploy? Strongest evidence first, three outcomes.
#   (a) Cloudflare Workers Builds: the check-run on the latest main commit named
#       "Workers Builds" carries a details_url ending in the build uuid;
#       GET /accounts/<acct>/builds/builds/<uuid> -> result.trigger.deploy_command
#       ("npx wrangler deploy" on branch_includes [main] == auto-deploy).
#       The list filters (?worker_name=, ?external_script_id=) are rejected by
#       the API ("Invalid query parameter") — go via the check-run. Measured
#       2026-09-14: AIVA main -> built+deployed to 100% in ~2.5 min.
#   (b) a GitHub Actions workflow that deploys on push to main.
#   (c) otherwise UNKNOWN — treated as auto-deploy for the verdict below,
#       because a wrong "no" is the expensive error (a failing auto-deploy
#       looks identical to no auto-deploy — see reference-aiva-deploy-is-manual).
AUTO="unknown"; AUTO_DETAIL=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  MAIN_SHA=$(git rev-parse origin/main)
  CR_JSON=$(gh api "repos/{owner}/{repo}/commits/$MAIN_SHA/check-runs" 2>/dev/null || echo "")
  if [ -n "$CR_JSON" ]; then
    BUILD_URL=$(printf '%s' "$CR_JSON" | python3 -c 'import json,sys
d=json.load(sys.stdin)
for c in d.get("check_runs",[]):
    if "workers builds" in (c.get("name","")+" "+c.get("app",{}).get("name","")).lower():
        print(c.get("details_url","")); break' 2>/dev/null)
    BUILD_UUID=$(printf '%s' "$BUILD_URL" | grep -oE '[0-9a-f-]{36}' | tail -1)
    CREDS="$HOME/.cloudflared/cf-global-api-key.json"
    if [ -n "$BUILD_UUID" ] && [ -f "$CREDS" ]; then
      CF_KEY=$(python3 -c "import json;print(json.load(open('$CREDS'))['global_api_key'])" 2>/dev/null)
      CF_EMAIL=$(python3 -c "import json;print(json.load(open('$CREDS'))['email'])" 2>/dev/null)
      CF_ACCT=$(python3 -c "import json;print(json.load(open('$CREDS')).get('account_id','<CLOUDFLARE_ACCOUNT_ID>'))" 2>/dev/null)
      TRIG=$(curl -s --max-time 20 -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY"         "https://api.cloudflare.com/client/v4/accounts/$CF_ACCT/builds/builds/$BUILD_UUID"         | python3 -c 'import json,sys
d=json.load(sys.stdin).get("result",{}).get("trigger",{}) or {}
print(d.get("trigger_name",""),"|",",".join(d.get("branch_includes",[]) or []),"|",d.get("deploy_command",""))' 2>/dev/null)
      if [ -n "$TRIG" ]; then
        AUTO_DETAIL="workers-builds trigger: $TRIG"
        case "$TRIG" in *"wrangler deploy"*) AUTO="yes";; *"versions upload"*) AUTO="no (versions upload only)";; *) AUTO="unknown";; esac
      fi
    fi
  fi
fi
if [ "$AUTO" = "unknown" ] && [ -d .github/workflows ] && grep -rlE "wrangler (deploy|versions upload)|vercel .*--prod|netlify deploy --prod|npm run deploy" .github/workflows 2>/dev/null | grep -q .; then
  AUTO="yes"; AUTO_DETAIL="github-actions workflow deploys on push"
fi
echo "auto-deploy-on-main: $AUTO ${AUTO_DETAIL:+($AUTO_DETAIL)}"
[ "$AUTO" = "unknown" ] && echo "  (unknown => treated as auto-deploy; a wrong 'no' is the expensive error)"

# --- 2. Deployed SHAs that main never received
RC=0; CHECKED=0
check_sha() {
  local sha="$1" label="$2"
  [ -z "$sha" ] && return
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "UNMEASURED  $label ${sha:0:8}  (commit not in local clone — fetch it or the branch was deleted with the commit unmerged)"
    RC=$(( RC == 1 ? 1 : 2 )); return
  fi
  CHECKED=$((CHECKED+1))
  if git merge-base --is-ancestor "$sha" origin/main; then
    echo "OK          $label ${sha:0:8}  is on origin/main"
  else
    local branches; branches=$(git branch -r --contains "$sha" 2>/dev/null | tr -d ' ' | grep -v '^origin/HEAD' | paste -sd, - )
    echo "REGRESSION-RISK  $label ${sha:0:8}  deployed but NOT on origin/main (branches: ${branches:-none}) — next push to main overwrites it"
    RC=1
  fi
}
if [ -f deploy-log.jsonl ]; then
  # Only the newest N entries matter (older ones have been superseded by later deploys).
  # ceiling: the ledger is append-only; corpus: AIVA has ~1 deploy/day, 5 covers a week.
  python3 - <<'PY' > /tmp/.deployed-shas.$$ 2>/dev/null || true
import json,sys
rows=[]
for line in open('deploy-log.jsonl',encoding='utf-8'):
    line=line.strip()
    if not line: continue
    try: rows.append(json.loads(line))
    except Exception: pass
for r in rows[-5:]:
    print(r.get('git_sha',''), r.get('deployed_at',''), (r.get('subject','') or '')[:60].replace('\n',' '))
PY
  while read -r sha at subj; do check_sha "$sha" "ledger@$at"; done < /tmp/.deployed-shas.$$
  rm -f /tmp/.deployed-shas.$$
else
  echo "UNMEASURED  no deploy-log.jsonl ledger — cannot enumerate past deploys; check the platform's deployment list by hand"
  RC=$(( RC == 1 ? 1 : 2 ))
fi
[ -n "$EXTRA_SHA" ] && check_sha "$EXTRA_SHA" "just-deployed"

# --- 3. Stale / unmergeable open PRs (informational unless a deployed SHA lives on one)
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "open PRs:"
  gh pr list --state open --limit 50 --json number,title,headRefName,headRefOid,mergeable,mergeStateStatus,isDraft,updatedAt \
    --jq '.[] | "  #\(.number)  \(.mergeable)/\(.mergeStateStatus)\(if .isDraft then " DRAFT" else "" end)  updated \(.updatedAt[0:10])  \(.headRefName)  \(.title[0:60])"' 2>/dev/null \
    || echo "  UNMEASURED: gh pr list failed"
  # A deployed SHA sitting on an open PR branch is the exact #276 shape.
  while read -r num oid ref; do
    [ -z "$oid" ] && continue
    if git cat-file -e "$oid^{commit}" 2>/dev/null && ! git merge-base --is-ancestor "$oid" origin/main 2>/dev/null; then
      if [ -f deploy-log.jsonl ] && grep -q "\"git_sha\": \"$oid\"" deploy-log.jsonl; then
        echo "REGRESSION-RISK  PR #$num ($ref) head $oid was DEPLOYED per the ledger and is still open/unmerged"
        RC=1
      fi
    fi
  done < <(gh pr list --state open --limit 50 --json number,headRefOid,headRefName --jq '.[] | "\(.number) \(.headRefOid) \(.headRefName)"' 2>/dev/null)
else
  echo "UNMEASURED  gh not authenticated — open-PR sweep skipped"
  RC=$(( RC == 1 ? 1 : 2 ))
fi

case $RC in
  0) echo "RESULT: OK — $CHECKED deployed SHA(s) all on origin/main";;
  1) echo "RESULT: REGRESSION-RISK — a deployed commit is not on main. Merge it (with authorization) or record the decision to leave it unmerged before any push to main.";;
  2) echo "RESULT: UNMEASURED — not a pass; report what could not be checked";;
esac
exit $RC
