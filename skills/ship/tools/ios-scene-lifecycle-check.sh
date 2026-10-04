#!/usr/bin/env bash
# ios-scene-lifecycle-check.sh [repo]  — static gate for the iOS 27 UIScene mandate.
#
# WHY (incident 2026-09-28, ImproveBayArea build 14): an app linked against the
# iOS 26+ SDK (Xcode 27) that does not adopt the UIScene lifecycle HARD-CRASHES AT
# LAUNCH on iOS 27 — EXC_BREAKPOINT in
# UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption. Build 14 passed every
# gate: it archived, uploaded, went VALID in TestFlight, and launched fine on the
# iOS 26.5 simulator. It died on the first real iOS 27 phone. Capacitor 8.4 ships NO
# SceneDelegate, so every Capacitor app is exposed.
#
# Checks each app-target Info.plist:
#   1. UIApplicationSceneManifest with a UISceneDelegateClassName
#   2. that delegate class exists in Swift/ObjC source and adopts UIWindowSceneDelegate
#   3. if the app declares URL schemes (CFBundleURLTypes — e.g. Google sign-in) or
#      associated domains, the scene delegate implements openURLContexts / continue
#      userActivity. Under scenes UIKit delivers URLs to the SCENE delegate, not
#      application(_:open:) — missing forwards silently break OAuth return and
#      universal links with no crash and no error.
#
# Exit: 0 PASS · 1 FAIL · 2 UNMEASURED (could not read) · 4 NOT APPLICABLE (no iOS
# app project found). 4 is never a pass for a release that includes a native build.
set -uo pipefail
REPO="${1:-$PWD}"
cd "$REPO" 2>/dev/null || { echo "UNMEASURED: cannot cd to $REPO"; exit 2; }

# bash 3.2 (macOS /bin/bash) has no mapfile, and "${arr[@]}" on an empty array trips set -u.
LIST="$(find . \( -name node_modules -o -name Pods -o -name build -o -name DerivedData \
  -o -name '*.xcarchive' -o -name .git -o -name .claude -o -name vendor \) -prune -o -name Info.plist -print 2>/dev/null \
  | while read -r p; do
      # app targets only: must declare UIApplication-style keys
      grep -qE 'LSRequiresIPhoneOS|UILaunchStoryboardName|UIMainStoryboardFile' "$p" 2>/dev/null && echo "$p"
    done)"
if [ -z "$LIST" ]; then
  echo "NOT APPLICABLE: no iOS app Info.plist under $REPO"; exit 4
fi

rc=0
while IFS= read -r P; do
  echo "== $P"
  JSON="$(plutil -convert json -o - "$P" 2>/dev/null)" || { echo "  UNMEASURED: plutil could not parse"; rc=$(( rc > 2 ? rc : 2 )); continue; }
  DELEGATE="$(printf '%s' "$JSON" | python3 -c '
import sys,json
d=json.load(sys.stdin)
m=d.get("UIApplicationSceneManifest") or {}
for role in (m.get("UISceneConfigurations") or {}).values():
    for c in role or []:
        n=c.get("UISceneDelegateClassName")
        if n: print(n.split(".")[-1]); sys.exit()
')"
  if [ -z "$DELEGATE" ]; then
    echo "  FAIL: no UIApplicationSceneManifest / UISceneDelegateClassName — app crashes at launch on iOS 27"
    echo "        (EXC_BREAKPOINT UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption)."
    echo "        Fix: ~/.claude/skills/shared/ios-app-dev-release-traps.md §1"
    rc=1; continue
  fi
  DIR="$(dirname "$P")"
  SRC="$(grep -rlE "class[[:space:]]+${DELEGATE}\b|@interface[[:space:]]+${DELEGATE}\b" "$DIR" --include='*.swift' --include='*.m' --include='*.h' 2>/dev/null | head -1)"
  if [ -z "$SRC" ]; then
    echo "  FAIL: manifest names '$DELEGATE' but no such class exists under $DIR"; rc=1; continue
  fi
  if ! grep -qE "class[[:space:]]+${DELEGATE}[^{]*UIWindowSceneDelegate" "$SRC"; then
    echo "  FAIL: $DELEGATE ($SRC) does not adopt UIWindowSceneDelegate"; rc=1; continue
  fi
  echo "  ok: scene manifest -> $DELEGATE ($SRC)"
  NEEDS_URL=$(printf '%s' "$JSON" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(1 if d.get("CFBundleURLTypes") else 0)')
  ENT="$(find "$DIR" -maxdepth 2 -name '*.entitlements' 2>/dev/null | head -1)"
  [ -n "$ENT" ] && grep -q 'associated-domains' "$ENT" && NEEDS_URL=1
  if [ "$NEEDS_URL" = 1 ]; then
    miss=""
    grep -qE 'func[[:space:]]+scene\([^)]*openURLContexts[[:space:]]' "$SRC" || miss="$miss scene(_:openURLContexts:)"
    grep -qE 'connectionOptions\.urlContexts|connectionOptions\.userActivities' "$SRC" || miss="$miss cold-launch connectionOptions forwarding"
    if [ -n "$ENT" ] && grep -q 'associated-domains' "$ENT"; then
      grep -qE 'func[[:space:]]+scene\([^)]*continue[[:space:]]+userActivity' "$SRC" || miss="$miss scene(_:continue:)"
    fi
    if [ -n "$miss" ]; then
      echo "  FAIL: app declares URL schemes/associated domains but $DELEGATE lacks:$miss"
      echo "        (OAuth return / universal links silently dead under scenes)"; rc=1; continue
    fi
    echo "  ok: URL / universal-link forwarding present"
  fi
done <<< "$LIST"
case $rc in 0) echo "PASS";; 1) echo "FAIL";; *) echo "UNMEASURED";; esac
exit $rc
