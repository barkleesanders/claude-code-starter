#!/usr/bin/env bash
# ghidra_decompiler_repair.sh — restore a Ghidra install's host natives +
# PyGhidra wheels, then re-run the functional probe.
#
# WHY TWO SOURCES: NSA's official Ghidra releases ship NO macOS natives
# (GettingStarted.md, "Building Native Components": macOS natives are
# user-built). So:
#   - Wheels restore from the verified official release zip directly (the zip
#     DOES contain them; they go missing from live installs silently).
#   - Natives restore from a natives cache (GHIDRA_NATIVES_CACHE) built once
#     from that verified zip's sources via `gradlew buildNatives`. If the
#     cache is missing, this script rebuilds it from a Ghidra build tree
#     (GHIDRA_BUILD_DIR) and populates the cache.
# On Linux the official zip ships its natives, so the wheel restore + probe
# are usually all that is needed; the natives leg no-ops when the cache and
# build tree are both absent AND the natives already exist.
#
# Env overrides:
#   GHIDRA_HOME               Ghidra install dir (default: auto-detect
#                             ~/tools/ghidra_*_PUBLIC, else $HOME/ghidra_*)
#   GHIDRA_RELEASE_ZIP        official release zip (wheel source + integrity)
#   GHIDRA_RELEASE_ZIP_SHA256 expected sha256; when set, a mismatch aborts
#   GHIDRA_NATIVES_CACHE      natives cache root
#                             (default: ~/.cache/ghidra-natives/<plat>)
#   GHIDRA_BUILD_DIR          extracted release tree used for the gradlew
#                             rebuild leg (must contain support/gradle)
#   JAVA21_HOME               JDK 21 home for gradlew (macOS default:
#                             Homebrew openjdk@21). Gradle dies on much newer
#                             JDKs ("Unsupported class file major version").
#   PROBE                     probe script to run at the end
#                             (default: ghidra_decompiler_probe.sh beside
#                             this script)
set -eu

OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS/$ARCH" in
  Darwin/arm64)  PLAT="mac_arm_64" ;;
  Darwin/x86_64) PLAT="mac_x86_64" ;;
  Linux/x86_64)  PLAT="linux_x86_64" ;;
  Linux/aarch64) PLAT="linux_arm_64" ;;
  *) echo "REPAIR-FAIL: unsupported platform $OS/$ARCH" >&2; exit 1 ;;
esac

if [ -z "${GHIDRA_HOME:-}" ]; then
  for cand in "$HOME"/tools/ghidra_*_PUBLIC "$HOME"/ghidra_*_PUBLIC; do
    [ -x "$cand/support/analyzeHeadless" ] && GHIDRA_HOME="$cand" && break
  done
fi
[ -n "${GHIDRA_HOME:-}" ] || { echo "REPAIR-FAIL: GHIDRA_HOME not set and no Ghidra install auto-detected" >&2; exit 1; }
echo "REPAIR: GHIDRA_HOME=$GHIDRA_HOME plat=$PLAT"

HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE="${PROBE:-$HERE/ghidra_decompiler_probe.sh}"
NATIVES_CACHE="${GHIDRA_NATIVES_CACHE:-$HOME/.cache/ghidra-natives/$PLAT}"

# --- wheels from the verified release zip ----------------------------------
if [ -n "${GHIDRA_RELEASE_ZIP:-}" ]; then
  [ -f "$GHIDRA_RELEASE_ZIP" ] || { echo "REPAIR-FAIL: release zip missing: $GHIDRA_RELEASE_ZIP" >&2; exit 1; }
  if [ -n "${GHIDRA_RELEASE_ZIP_SHA256:-}" ]; then
    echo "REPAIR: verifying release zip sha256..."
    if command -v shasum >/dev/null 2>&1; then ACTUAL="$(shasum -a 256 "$GHIDRA_RELEASE_ZIP" | awk '{print $1}')";
    else ACTUAL="$(sha256sum "$GHIDRA_RELEASE_ZIP" | awk '{print $1}')"; fi
    [ "$ACTUAL" = "$GHIDRA_RELEASE_ZIP_SHA256" ] || { echo "REPAIR-FAIL: zip sha256 mismatch: $ACTUAL" >&2; exit 1; }
  fi
  echo "REPAIR: restoring PyGhidra + debugger wheels from release zip..."
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  unzip -o -q "$GHIDRA_RELEASE_ZIP" "*/Ghidra/Features/PyGhidra/pypkg/dist/*" "*/Ghidra/Debug/*/pypkg/dist/*" -d "$TMP" || true
  SRC="$(find "$TMP" -type d -path "*/Ghidra/Features/PyGhidra/pypkg/dist" | head -1)"
  [ -n "$SRC" ] || { echo "REPAIR-FAIL: PyGhidra dist not found inside release zip" >&2; exit 1; }
  cp -R "$SRC" "$GHIDRA_HOME/Ghidra/Features/PyGhidra/pypkg/"
  find "$TMP" -type d -path "*/Ghidra/Debug/*/pypkg/dist" | while read -r d; do
    mod="$(basename "$(dirname "$(dirname "$d")")")"
    mkdir -p "$GHIDRA_HOME/Ghidra/Debug/$mod/pypkg"
    cp -R "$d" "$GHIDRA_HOME/Ghidra/Debug/$mod/pypkg/"
  done
  echo "REPAIR: wheels restored"
else
  echo "REPAIR: GHIDRA_RELEASE_ZIP not set — skipping wheel restore"
fi

# --- natives -----------------------------------------------------------------
natives_present() {
  [ -x "$GHIDRA_HOME/Ghidra/Features/Decompiler/os/$PLAT/decompile" ] || \
  [ -x "$GHIDRA_HOME/Ghidra/Features/Decompiler/build/os/$PLAT/decompile" ]
}

if [ ! -x "$NATIVES_CACHE/Decompiler/decompile" ]; then
  if [ -n "${GHIDRA_BUILD_DIR:-}" ] && [ -d "$GHIDRA_BUILD_DIR/support/gradle" ]; then
    echo "REPAIR: natives cache missing — rebuilding via gradlew buildNatives..."
    if [ "$OS" = "Darwin" ]; then
      export JAVA_HOME="${JAVA21_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
      BREW_PREFIX="$(command -v brew >/dev/null 2>&1 && brew --prefix || echo /opt/homebrew)"
      export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/opt/flex/bin:$PATH"
    fi
    ( cd "$GHIDRA_BUILD_DIR/support/gradle" && ./gradlew buildNatives )
    mkdir -p "$NATIVES_CACHE"
    for mod in Decompiler FileFormats; do
      src="$GHIDRA_BUILD_DIR/Ghidra/Features/$mod/build/os/$PLAT"
      [ -d "$src" ] && { mkdir -p "$NATIVES_CACHE/$mod"; cp -a "$src/." "$NATIVES_CACHE/$mod/"; }
    done
    src="$GHIDRA_BUILD_DIR/GPL/DemanglerGnu/build/os/$PLAT"
    [ -d "$src" ] && { mkdir -p "$NATIVES_CACHE/DemanglerGnu"; cp -a "$src/." "$NATIVES_CACHE/DemanglerGnu/"; }
  elif natives_present; then
    echo "REPAIR: natives already present and no cache/build tree configured — skipping natives leg"
  else
    echo "REPAIR-FAIL: natives missing, no cache at $NATIVES_CACHE, and no GHIDRA_BUILD_DIR to rebuild from." >&2
    echo "Build them once from the official release sources: extract the release zip, then" >&2
    echo "  cd <tree>/support/gradle && ./gradlew buildNatives   (JDK 21; macOS also needs bison/flex in PATH)" >&2
    echo "and re-run with GHIDRA_BUILD_DIR=<tree>, or populate GHIDRA_NATIVES_CACHE manually." >&2
    exit 1
  fi
fi

if [ -x "$NATIVES_CACHE/Decompiler/decompile" ]; then
  echo "REPAIR: installing natives from cache into live install (build/os + os)..."
  install_mod() {
    local src="$NATIVES_CACHE/$1" dstmod="$2"
    [ -d "$src" ] || { echo "REPAIR: no cached natives for $1 (skipped)"; return 0; }
    mkdir -p "$GHIDRA_HOME/$dstmod/build/os/$PLAT" "$GHIDRA_HOME/$dstmod/os/$PLAT"
    cp -a "$src/." "$GHIDRA_HOME/$dstmod/build/os/$PLAT/"
    cp -a "$src/." "$GHIDRA_HOME/$dstmod/os/$PLAT/"
    chmod +x "$GHIDRA_HOME/$dstmod/build/os/$PLAT/"* "$GHIDRA_HOME/$dstmod/os/$PLAT/"* 2>/dev/null || true
    echo "REPAIR: $1 natives installed"
  }
  install_mod Decompiler "Ghidra/Features/Decompiler"
  install_mod FileFormats "Ghidra/Features/FileFormats"
  install_mod DemanglerGnu "GPL/DemanglerGnu"
fi

# --- verify --------------------------------------------------------------------
echo "REPAIR: running probe..."
[ -x "$PROBE" ] || { echo "REPAIR-FAIL: probe not executable: $PROBE" >&2; exit 1; }
GHIDRA_HOME="$GHIDRA_HOME" "$PROBE"
echo "REPAIR-OK"
