#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") <binary> [empty-output-directory]" >&2
  echo "Environment: GHIDRA_HOME GHIDRA_TIMEOUT GHIDRA_MAX_CPU GHIDRA_DECOMPILE_TIMEOUT" >&2
}

fail() {
  echo "ghidra_triage: $*" >&2
  exit 1
}

require_positive_integer() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$label must be a positive integer (got: $value)"
}

discover_ghidra_home() {
  local executable
  local candidate
  local selected=""

  if [[ -n "${GHIDRA_HOME:-}" ]]; then
    [[ -x "$GHIDRA_HOME/support/analyzeHeadless" ]] ||
      fail "GHIDRA_HOME does not contain executable support/analyzeHeadless: $GHIDRA_HOME"
    echo "$GHIDRA_HOME"
    return
  fi

  executable="$(command -v analyzeHeadless 2>/dev/null || true)"
  if [[ -n "$executable" ]]; then
    cd "$(dirname "$executable")/.." && pwd -P
    return
  fi

  for candidate in \
    /Applications/ghidra* \
    /Applications/Ghidra.app/Contents/Resources/ghidra \
    /opt/ghidra* \
    "$HOME"/tools/ghidra_*_PUBLIC; do
    if [[ -x "$candidate/support/analyzeHeadless" ]]; then
      selected="$candidate"
    fi
  done

  [[ -n "$selected" ]] ||
    fail "could not find Ghidra; install it or set GHIDRA_HOME to its installation directory"
  cd "$selected" && pwd -P
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    fail "neither shasum nor sha256sum is available"
  fi
}

[[ $# -ge 1 && $# -le 2 ]] || {
  usage
  exit 2
}

input="$1"
[[ -f "$input" ]] || fail "input is not a regular file: $input"
[[ -r "$input" ]] || fail "input is not readable: $input"

input_directory="$(cd "$(dirname "$input")" && pwd -P)"
input_path="$input_directory/$(basename "$input")"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ghidra_home="$(discover_ghidra_home)"
analyze_headless="$ghidra_home/support/analyzeHeadless"

analysis_timeout="${GHIDRA_TIMEOUT:-600}"
max_cpu="${GHIDRA_MAX_CPU:-4}"
decompile_timeout="${GHIDRA_DECOMPILE_TIMEOUT:-60}"
require_positive_integer "GHIDRA_TIMEOUT" "$analysis_timeout"
require_positive_integer "GHIDRA_MAX_CPU" "$max_cpu"
require_positive_integer "GHIDRA_DECOMPILE_TIMEOUT" "$decompile_timeout"

if [[ $# -eq 2 ]]; then
  output_directory="$2"
  if [[ -e "$output_directory" ]]; then
    [[ -d "$output_directory" ]] || fail "output path exists and is not a directory: $output_directory"
    [[ -z "$(find "$output_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      fail "explicit output directory must be empty: $output_directory"
  else
    mkdir -p "$output_directory"
  fi
  output_directory="$(cd "$output_directory" && pwd -P)"
else
  temporary_root="${TMPDIR:-/tmp}"
  output_directory="$(mktemp -d "${temporary_root%/}/ghidra-triage.XXXXXX")"
fi

mkdir -p "$output_directory/input" "$output_directory/project"
safe_name="$(printf '%s' "$(basename "$input_path")" | tr -cs 'A-Za-z0-9._-' '_')"
[[ -n "$safe_name" ]] || safe_name="artifact.bin"
copied_input="$output_directory/input/$safe_name"
cp "$input_path" "$copied_input"

source_sha256="$(sha256_file "$input_path")"
copied_sha256="$(sha256_file "$copied_input")"
[[ "$source_sha256" == "$copied_sha256" ]] || fail "analysis copy hash does not match the source"

metadata="$output_directory/metadata.txt"
inventory="$output_directory/inventory.json"
decompiled="$output_directory/decompiled.c"
application_log="$output_directory/application.log"
script_log="$output_directory/script.log"
console_log="$output_directory/console.log"

{
  echo "source_path=$input_path"
  echo "copied_path=$copied_input"
  echo "sha256=$source_sha256"
  echo "size_bytes=$(wc -c < "$copied_input" | tr -d ' ')"
  echo "file=$(file -b "$copied_input")"
  echo "ghidra_home=$ghidra_home"
  if [[ -f "$ghidra_home/Ghidra/application.properties" ]]; then
    grep '^application.version=' "$ghidra_home/Ghidra/application.properties" || true
  fi
  echo "analysis_timeout_seconds=$analysis_timeout"
  echo "decompile_timeout_seconds=$decompile_timeout"
  echo "max_cpu=$max_cpu"
} > "$metadata"

if command -v lipo >/dev/null 2>&1; then
  lipo -info "$copied_input" >> "$metadata" 2>&1 || true
fi
if command -v codesign >/dev/null 2>&1; then
  codesign -dv --verbose=4 "$copied_input" >> "$metadata" 2>&1 || true
  codesign --verify --deep --strict "$copied_input" >> "$metadata" 2>&1 || true
fi

echo "Analysis copy: $copied_input"
echo "SHA-256: $source_sha256"
echo "Output: $output_directory"

"$analyze_headless" "$output_directory/project" triage \
  -import "$copied_input" \
  -analysisTimeoutPerFile "$analysis_timeout" \
  -max-cpu "$max_cpu" \
  -scriptPath "$script_directory" \
  -postScript dump_strings_imports.py "$inventory" 64 256 \
  -postScript decompile_all.py "$decompiled" '.*' "$decompile_timeout" \
  -log "$application_log" \
  -scriptlog "$script_log" 2>&1 | tee "$console_log"

{
  echo "analysis_status=success"
  echo "inventory_path=$inventory"
  echo "decompiled_path=$decompiled"
  echo "project_path=$output_directory/project"
  echo "application_log=$application_log"
  echo "script_log=$script_log"
} >> "$metadata"

echo "Triage complete: $output_directory"
if command -v jq >/dev/null 2>&1; then
  jq '{program: .program, counts: {blocks: (.memory_blocks | length), imports: (.imports | length), exports: (.exports | length), functions: (.functions | length), strings: (.strings | length)}, capabilities: .capabilities}' "$inventory"
fi

