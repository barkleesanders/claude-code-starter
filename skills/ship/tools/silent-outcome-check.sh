#!/usr/bin/env bash
# Silent-outcome gate for /ship (Pattern 43, added 2026-09-18).
#
# A primary action (submit / file / send / checkout) must never end in
# "nothing happened". Two halves:
#   A. STRUCTURAL (always): the changeset must not ADD a native
#      alert(/confirm(/prompt( to client code. Automation auto-dismisses them,
#      some webviews block them, and they were tap #3 of the reference incident.
#      Pre-existing ones are reported, never blocked (that is a repo backlog).
#   B. PROBE (when declared): run the repo's `probe:constrained` npm script — a
#      headless browser with no WebGL, no geolocation, dialogs dismissed, every
#      POST /api/* intercepted — which must assert per tap: posted OR a visible
#      hold, never neither. With --live <url> the probe is pointed at production.
#      A repo that renders a primary-action control but declares no probe is
#      UNMEASURED, which is never a pass.
#
# Usage: silent-outcome-check.sh <repo-dir> [--live <url>] [--base <ref>]
# Env:   PLAYWRIGHT_NODE_MODULES=<dir>  if the repo does not depend on playwright,
#        a tests/node_modules symlink to this dir lets an ESM `import 'playwright'`
#        resolve (NODE_PATH does NOT apply to ESM imports).
# Exit:  0 pass / skip (stated), 1 BLOCK, 2 UNMEASURED (never a pass).
set -uo pipefail
DIR="${1:-$PWD}"; shift || true
LIVE=""; BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE="${2:-}"; shift 2;;
    --base) BASE="${2:-}"; shift 2;;
    *) echo "silent-outcome-check: unknown arg $1"; exit 2;;
  esac
done
cd "$DIR" 2>/dev/null || { echo "silent-outcome-check: not a directory: $DIR"; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "silent-outcome-check: not a git repo — UNMEASURED"; exit 2; }

rc=0
# ---------- A. structural: newly added native dialogs in client code ----------
if [ -z "$BASE" ]; then
  for cand in origin/HEAD origin/main origin/master main master; do
    if git rev-parse --verify -q "$cand" >/dev/null 2>&1; then
      mb=$(git merge-base HEAD "$cand" 2>/dev/null) && BASE="$mb" && break
    fi
  done
fi
if [ -z "$BASE" ]; then
  echo "silent-outcome-check: A. no base ref resolvable — structural half UNMEASURED"
  rc=2
else
  # client-ish files only; tests and captured fixtures excluded
  added=$(git diff -U0 "$BASE"..HEAD -- . ':(exclude)**/*.test.*' ':(exclude)**/__fixtures__/**' ':(exclude)tests/**' ':(exclude)**/node_modules/**' \
    | awk '/^\+\+\+ /{f=$2; sub(/^b\//,"",f)} /^\+[^+]/{ if (f ~ /\.(ts|tsx|js|jsx|mjs|html|astro|svelte|vue)$/) print f": "substr($0,2)}' \
    | grep -E '(^|[^A-Za-z0-9_.$])(window\.)?(alert|confirm|prompt)\(' \
    | grep -vE '^\S+:\s*(//|\*|/\*|#)' || true)
  if [ -n "$added" ]; then
    echo "silent-outcome-check: A. BLOCK — the changeset ADDS a native dialog on client code:"
    echo "$added" | sed 's/^/    /' | head -20
    echo "    Ask in the page (Pattern 43: holdSubmit/askInlineChoice or equivalent). Automation dismisses these; some webviews block them."
    rc=1
  else
    echo "silent-outcome-check: A. ok — no native dialog added ($(git rev-parse --short "$BASE")..$(git rev-parse --short HEAD))"
  fi
  pre=$(grep -rnE '(^|[^A-Za-z0-9_.$])(window\.)?(alert|confirm|prompt)\(' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.mjs' --include='*.html' src public app components 2>/dev/null \
    | grep -vE '\.test\.|__fixtures__|^\S+:\s*[0-9]+:\s*(//|\*|/\*)' | wc -l | tr -d ' ')
  [ "${pre:-0}" != "0" ] && echo "silent-outcome-check: A. info — $pre pre-existing native dialog call(s) in client code (backlog, not blocking)"
fi

# ---------- B. constrained-browser probe ----------
has_script=$(node -e 'try{const p=require("./package.json");process.stdout.write(p.scripts&&p.scripts["probe:constrained"]?"y":"n")}catch{process.stdout.write("n")}' 2>/dev/null)
if [ "$has_script" = "y" ]; then
  # The probe lives in tests/, so resolve from THERE, not only from the repo root:
  # a checkout under ~/projects finds ~/node_modules/playwright by the ancestor walk,
  # a worktree under /tmp or .claude/worktrees does not (2026-09-20, improvecortland +
  # diy-fax worktrees reported "unresolvable" with a valid tests/node_modules symlink).
  # "Resolves" is not enough: ~/node_modules/playwright resolved fine and then died
  # with "run npx playwright install" — the check must prove the browser is present.
  pw_launchable() { node -e 'import("playwright").then(m=>{require("fs").accessSync(m.chromium.executablePath());process.exit(0)}).catch(()=>process.exit(1))' >/dev/null 2>&1; }
  if ! pw_launchable && ! { [ -d tests ] && (cd tests && pw_launchable); }; then
    cand="${PLAYWRIGHT_NODE_MODULES:-}"
    if [ -z "$cand" ]; then
      # First node_modules on this machine whose playwright has its chromium installed.
      for c in "$HOME"/node_modules "$HOME"/projects/*/node_modules "$HOME"/projects/*/tests/node_modules "$HOME"/*/node_modules; do
        [ -d "$c/playwright" ] || continue
        (cd "$c/.." && pw_launchable) && cand="$(cd "$c" && pwd -P)" && break
      done
    fi
    if [ -n "$cand" ] && [ -d "$cand/playwright" ]; then
      mkdir -p tests
      # -L catches a dangling symlink left by a removed source dir; replace it.
      if [ -L tests/node_modules ] && [ ! -e tests/node_modules ]; then rm -f tests/node_modules; fi
      [ -e tests/node_modules ] || ln -s "$cand" tests/node_modules
      echo "silent-outcome-check: B. playwright not a repo dependency — using tests/node_modules -> $cand"
    else
      echo "silent-outcome-check: B. UNMEASURED — probe:constrained declared but no launchable playwright (from . or tests/, and no node_modules on this machine has its chromium installed). Set PLAYWRIGHT_NODE_MODULES=<dir> or run npx playwright install."
      [ $rc -eq 0 ] && rc=2
      exit $rc
    fi
  fi
  echo "silent-outcome-check: B. running probe:constrained${LIVE:+ against $LIVE}"
  PROBE_URL="${LIVE}" ASSERT=1 npm run -s probe:constrained > .silent-outcome-probe.log 2>&1; prc=$?
  if [ $prc -eq 0 ]; then
    echo "silent-outcome-check: B. ok — probe passed (see .silent-outcome-probe.log)"
  else
    echo "silent-outcome-check: B. BLOCK — probe exit $prc:"
    tail -25 .silent-outcome-probe.log | sed 's/^/    /'
    rc=1
  fi
else
  ui=$(grep -rlE 'id="btn-submit"|type="submit"|addEventListener\(.submit.|data-submit' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' --include='*.html' --include='*.astro' --include='*.svelte' src public app components 2>/dev/null | grep -v '\.test\.' | head -3)
  if [ -n "$ui" ]; then
    echo "silent-outcome-check: B. UNMEASURED — a primary-action control exists ($(echo "$ui" | head -1)) but package.json has no probe:constrained script."
    echo "    Add one (Pattern 43): a headless run with no WebGL/no geolocation/dialogs dismissed, POSTs intercepted, ASSERT per tap: posted OR visible hold. Never report this as a pass."
    [ $rc -eq 0 ] && rc=2
  else
    echo "silent-outcome-check: B. skip — no primary-action control detected in client code (stated, not silent)"
  fi
fi
exit $rc
