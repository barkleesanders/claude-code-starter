#!/usr/bin/env bash
# ghidra_decompiler_probe.sh — FUNCTIONAL probe for a Ghidra install's decompiler.
#
# An existence check is NOT a probe: headless Ghidra analysis exits 0 even when
# every decompile fails (the missing-native error is buried in the log and the
# post-script's own ok/fail count is the only signal). This script EXECUTES the
# host-arch decompile+sleigh natives, optionally verifies a cached official
# release zip, optionally exercises capa with its rules, and runs a real
# headless decompile of a fixture binary, asserting pseudo-C output.
# Any failure exits non-zero LOUDLY (PROBE-FAIL); success prints PROBE-OK.
#
# Background: NSA's official Ghidra releases ship NO macOS natives
# (GettingStarted.md, "Building Native Components" — the macOS decompile/sleigh
# binaries are user-built via `gradlew buildNatives`). A from-zip reinstall on
# macOS therefore looks healthy and decompiles nothing. This probe exists so
# that failure can never pass silently again.
#
# Sabotage validation (do this once after installing the guard — a guard that
# has never been observed firing is indistinguishable from a vacuous one):
#   1. Move the host decompile binary away:
#        mv "$GHIDRA_HOME/Ghidra/Features/Decompiler/os/<plat>/decompile" /tmp/
#      Re-run this probe -> it MUST exit non-zero with PROBE-FAIL.
#   2. Run ghidra_decompiler_repair.sh (or move the binary back) and re-run
#      this probe -> it MUST print PROBE-OK.
#
# Env overrides:
#   GHIDRA_HOME               Ghidra install dir (default: auto-detect
#                             ~/tools/ghidra_*_PUBLIC, else $HOME/ghidra_*)
#   PROBE_FIXTURE             binary to headless-decompile (default: the
#                             install's own decompile native)
#   PROBE_MIN_FUNCS           minimum decompiled functions to accept (default 1)
#   PROBE_EXPECT_REGEX        optional regex that must appear in the pseudo-C
#   PROBE_WORK                scratch dir (default: mktemp -d; removed on exit
#                             unless PROBE_KEEP_WORK=1)
#   GHIDRA_RELEASE_ZIP        optional cached official release zip to verify
#   GHIDRA_RELEASE_ZIP_SHA256 expected sha256 (required when the zip is set)
#   CAPA_BIN                  optional capa executable; when set, capa is run
#                             with its rules against CAPA_FIXTURE
#   CAPA_RULES_DIR            rules dir for capa (default: capa's own default)
#   CAPA_FIXTURE              ELF/PE fixture for capa (default: PROBE_FIXTURE).
#                             NOTE: capa's default vivisect backend cannot read
#                             Mach-O — point this at an ELF or PE file.
#   SCRIPT_DIR                dir holding DecompileAllJava.java
#                             (default: this script's directory)
set -u

fail() { echo "PROBE-FAIL: $*" >&2; exit 1; }
note() { echo "PROBE-CHECK: $*"; }

# --- platform -------------------------------------------------------------
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS/$ARCH" in
  Darwin/arm64)  PLAT="mac_arm_64" ;;
  Darwin/x86_64) PLAT="mac_x86_64" ;;
  Linux/x86_64)  PLAT="linux_x86_64" ;;
  Linux/aarch64) PLAT="linux_arm_64" ;;
  *) fail "unsupported platform $OS/$ARCH" ;;
esac
note "host $OS/$ARCH -> platform dir $PLAT"

# --- locate Ghidra ----------------------------------------------------------
if [ -z "${GHIDRA_HOME:-}" ]; then
  for cand in "$HOME"/tools/ghidra_*_PUBLIC "$HOME"/ghidra_*_PUBLIC; do
    [ -x "$cand/support/analyzeHeadless" ] && GHIDRA_HOME="$cand" && break
  done
fi
[ -n "${GHIDRA_HOME:-}" ] || fail "GHIDRA_HOME not set and no Ghidra install auto-detected under ~/tools or ~"
[ -x "$GHIDRA_HOME/support/analyzeHeadless" ] || fail "analyzeHeadless missing/not executable: $GHIDRA_HOME/support/analyzeHeadless"
note "GHIDRA_HOME=$GHIDRA_HOME"

SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
[ -f "$SCRIPT_DIR/DecompileAllJava.java" ] || fail "DecompileAllJava.java not found in SCRIPT_DIR=$SCRIPT_DIR (it ships beside this script in the decompile skill)"

WORK="${PROBE_WORK:-$(mktemp -d)}"
mkdir -p "$WORK"
if [ -z "${PROBE_WORK:-}" ] && [ "${PROBE_KEEP_WORK:-0}" != "1" ]; then
  trap 'rm -rf "$WORK"' EXIT
fi

# Run a command under a wall-clock alarm (perl is present on macOS + Linux);
# rc 142 means the alarm fired.
timed() { local secs="$1"; shift; perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" "$@"; }

# 1. Host-arch natives exist (canonical os/ or build/os/) and are executables.
DECOMP=""; SLEIGH=""
for base in "$GHIDRA_HOME/Ghidra/Features/Decompiler/build/os/$PLAT" "$GHIDRA_HOME/Ghidra/Features/Decompiler/os/$PLAT"; do
  [ -x "$base/decompile" ] && DECOMP="$base/decompile"
  [ -x "$base/sleigh" ] && SLEIGH="$base/sleigh"
done
[ -n "$DECOMP" ] || fail "decompile binary missing/not executable for $PLAT under $GHIDRA_HOME (checked build/os and os) — on macOS this is the classic from-zip install: run ghidra_decompiler_repair.sh"
[ -n "$SLEIGH" ] || fail "sleigh binary missing/not executable for $PLAT under $GHIDRA_HOME"
note "natives present: $DECOMP ; $SLEIGH"

# 2. Natives EXECUTE: feed EOF on stdin under a 10s alarm; a healthy
#    decompile/sleigh process exits promptly on EOF instead of hanging.
timed 10 "$DECOMP" </dev/null >/dev/null 2>&1; rc=$?
[ $rc -eq 142 ] && fail "decompile hung on EOF stdin (alarm fired)"
note "decompile executes (EOF exit rc=$rc)"
timed 10 "$SLEIGH" </dev/null >/dev/null 2>&1; rc=$?
[ $rc -eq 142 ] && fail "sleigh hung on EOF stdin (alarm fired)"
note "sleigh executes (EOF exit rc=$rc)"

# 3. Optional: cached official release zip integrity (the repair source).
if [ -n "${GHIDRA_RELEASE_ZIP:-}" ]; then
  [ -n "${GHIDRA_RELEASE_ZIP_SHA256:-}" ] || fail "GHIDRA_RELEASE_ZIP set but GHIDRA_RELEASE_ZIP_SHA256 is not"
  [ -f "$GHIDRA_RELEASE_ZIP" ] || fail "cached release zip missing: $GHIDRA_RELEASE_ZIP"
  if command -v shasum >/dev/null 2>&1; then ACTUAL="$(shasum -a 256 "$GHIDRA_RELEASE_ZIP" | awk '{print $1}')";
  else ACTUAL="$(sha256sum "$GHIDRA_RELEASE_ZIP" | awk '{print $1}')"; fi
  [ "$ACTUAL" = "$GHIDRA_RELEASE_ZIP_SHA256" ] || fail "cached release zip sha256 mismatch: got $ACTUAL want $GHIDRA_RELEASE_ZIP_SHA256"
  note "cached release zip sha256 OK"
fi

# 4. PyGhidra wheels present (their absence silently kills pyghidraRun).
ls "$GHIDRA_HOME/Ghidra/Features/PyGhidra/pypkg/dist/"pyghidra-*.whl >/dev/null 2>&1 \
  || fail "PyGhidra wheel missing from Ghidra/Features/PyGhidra/pypkg/dist (restore via ghidra_decompiler_repair.sh)"
note "PyGhidra wheel present"

# 5. Optional: capa runs WITH rules. capa's default vivisect backend has NO
#    Mach-O format (upstream limitation, same class as floss) — the fixture
#    for this step must be ELF or PE.
if [ -n "${CAPA_BIN:-}" ]; then
  CFIX="${CAPA_FIXTURE:-${PROBE_FIXTURE:-$DECOMP}}"
  [ -f "$CFIX" ] || fail "capa fixture missing: $CFIX"
  CAPA_JSON="$WORK/capa-fixture.json"
  CARGS=(-j "$CFIX")
  [ -n "${CAPA_RULES_DIR:-}" ] && CARGS=(-r "$CAPA_RULES_DIR" "${CARGS[@]}")
  timed 600 "$CAPA_BIN" "${CARGS[@]}" > "$CAPA_JSON" 2>"$WORK/capa.err" || trc=$?
  trc="${trc:-0}"
  [ $trc -eq 142 ] && fail "capa timed out (600s) on fixture"
  grep -q '"rules"' "$CAPA_JSON" || fail "capa produced no rules JSON on fixture (rc=$trc; see $WORK/capa.err)"
  note "capa + rules OK on fixture"
fi

# 6. End-to-end headless decompile of the fixture; assert pseudo-C output.
FIXTURE="${PROBE_FIXTURE:-$DECOMP}"
[ -f "$FIXTURE" ] || fail "probe fixture missing: $FIXTURE"
PROJ="$WORK/proj"; rm -rf "$PROJ"; mkdir -p "$PROJ"
cp "$FIXTURE" "$WORK/fixture.bin"
timed 900 "$GHIDRA_HOME/support/analyzeHeadless" "$PROJ" probe -import "$WORK/fixture.bin" -overwrite \
  -scriptPath "$SCRIPT_DIR" -postScript DecompileAllJava.java "$WORK/fixture-decompiled.c" \
  > "$WORK/headless.log" 2>&1
rc=$?
[ $rc -eq 142 ] && fail "headless decompile timed out (900s)"
[ -s "$WORK/fixture-decompiled.c" ] || fail "headless decompile produced no output (see $WORK/headless.log)"
grep -q "DECOMPILEALL" "$WORK/headless.log" || fail "DecompileAllJava did not run (see $WORK/headless.log)"
grep -q "does not exist" "$WORK/headless.log" && grep -q "decompile" "$WORK/headless.log" \
  && fail "headless log shows a missing-native ERROR (see $WORK/headless.log)"
OKN="$(grep -o 'ok=[0-9]*' "$WORK/headless.log" | tail -1 | cut -d= -f2)"
[ "${OKN:-0}" -ge "${PROBE_MIN_FUNCS:-1}" ] || fail "decompiled function count too low: ok=${OKN:-none} (want >= ${PROBE_MIN_FUNCS:-1})"
if [ -n "${PROBE_EXPECT_REGEX:-}" ]; then
  grep -Eq "$PROBE_EXPECT_REGEX" "$WORK/fixture-decompiled.c" \
    || fail "pseudo-C lacks expected marker regex: $PROBE_EXPECT_REGEX"
fi
LINES="$(wc -l < "$WORK/fixture-decompiled.c")"
note "headless decompile OK: ok=$OKN functions, $LINES lines of pseudo-C"

echo "PROBE-OK ghidra decompiler functional ($PLAT)"
exit 0
