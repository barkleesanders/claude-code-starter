#!/bin/sh
# har2spec.sh — bridge a HAR capture into the CLI Printing Press.
#
# Converts a DevTools/website `.har` capture into an OpenAPI 3.x spec using
# jonluca/har-to-openapi, then you feed that spec to the press:
#
#     ./har2spec.sh capture.har openapi.json
#     cli-printing-press scorecard --dir ./my-pp-cli --spec ./openapi.json
#
# This serves the press's weakest input path (Sniff / `--har`): website-with-no-docs
# → spec. See ../references/augmentation-registry.md (Stage 2, jonluca/har-to-openapi).
#
# Usage:
#   har2spec.sh <capture.har> [output-spec] [-- <extra har-to-openapi flags>]
#
#   <capture.har>   Required. Path to a HAR export from Chrome/Firefox DevTools.
#   [output-spec]   Optional. Write spec here; format inferred from extension
#                   (.json -> json, .yaml/.yml -> yaml). If omitted, spec goes to stdout.
#   -- <flags>      Optional. Anything after `--` is passed straight to har-to-openapi
#                   (e.g. --multi-spec, --info-title MyAPI, --no-guess-authentication-headers).
#
# Env:
#   FORMAT=json|yaml   Override output format when writing to stdout (default: json,
#                      because the press's --spec examples use openapi.json).
#
# Exit codes: 0 ok · 2 usage/bad args · 3 har-to-openapi not found · other = converter error.
set -eu

usage() {
  cat >&2 <<'EOF'
Usage: har2spec.sh <capture.har> [output-spec] [-- <extra har-to-openapi flags>]

  <capture.har>   HAR export from DevTools (required).
  [output-spec]   Destination file; format inferred from extension. Omit for stdout.
  -- <flags>      Extra flags forwarded to har-to-openapi.

Example:
  har2spec.sh capture.har openapi.json
  cli-printing-press scorecard --dir ./my-pp-cli --spec ./openapi.json
EOF
  exit 2
}

# --- locate the converter (global install first, then pinned npx fallback) ---
if command -v har-to-openapi >/dev/null 2>&1; then
  HARCMD="har-to-openapi"
elif command -v npx >/dev/null 2>&1; then
  HARCMD="npx -y har-to-openapi@2"
else
  echo "har2spec: har-to-openapi not found and npx unavailable." >&2
  echo "          Install with: npm i -g har-to-openapi" >&2
  exit 3
fi

# --- args ---
[ "$#" -ge 1 ] || usage
HAR="$1"; shift

OUT=""
if [ "$#" -ge 1 ] && [ "$1" != "--" ]; then
  OUT="$1"; shift
fi

# Anything after a leading `--` is passthrough to har-to-openapi.
if [ "$#" -ge 1 ] && [ "$1" = "--" ]; then
  shift
fi

[ -f "$HAR" ] || { echo "har2spec: HAR file not found: $HAR" >&2; exit 2; }
[ -r "$HAR" ] || { echo "har2spec: HAR file not readable: $HAR" >&2; exit 2; }

# --- decide format ---
if [ -n "$OUT" ]; then
  case "$OUT" in
    *.json) FMT="json" ;;
    *.yaml|*.yml) FMT="yaml" ;;
    *) FMT="${FORMAT:-json}" ;;
  esac
else
  FMT="${FORMAT:-json}"
fi

# Press-friendly defaults: one spec for the whole capture + auth-header detection.
# Callers can override any of these via `-- <flags>` (later flags win).
set -- "$HAR" \
  --format "$FMT" \
  --force-all-requests-in-same-spec \
  --guess-authentication-headers \
  "$@"

if [ -n "$OUT" ]; then
  # shellcheck disable=SC2086
  exec $HARCMD "$@" --output "$OUT"
else
  # shellcheck disable=SC2086
  exec $HARCMD "$@"
fi
