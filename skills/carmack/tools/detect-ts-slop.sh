#!/usr/bin/env bash
# detect-ts-slop.sh — flag AI "vibe-coding" TypeScript slop:
#   generic isRecord/isObject guards, launder-casts, (x as any).prop reach-casts.
# Rule: ~/.claude/skills/shared/anti-slop-typescript.md
#
# Usage:
#   detect-ts-slop.sh [path]              # scan a dir/file (default: .)
#   detect-ts-slop.sh --diff [base]       # scan only changed *.ts/*.tsx vs base (default: HEAD)
#   detect-ts-slop.sh --threshold N path  # exit 1 if total hits > N (default: advisory, exit 0)
#
# Exit: 0 advisory/clean, 1 only when --threshold is set and exceeded.
set -uo pipefail

RG=$(command -v rg || true)
THRESH=""        # empty = advisory (never blocks)
DIFF_BASE=""
PATHS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESH="${2:-0}"; shift 2;;
    --diff) DIFF_BASE="${2:-HEAD}"; shift 2 2>/dev/null || { DIFF_BASE="HEAD"; shift; };;
    *) PATHS+=("$1"); shift;;
  esac
done
[ ${#PATHS[@]} -eq 0 ] && PATHS=(".")

# Build file list.
# NOTE: `mapfile`/`readarray` is bash 4+. macOS ships bash 3.2.57 as /bin/bash, where
# `mapfile` is not a builtin — it failed, left FILES/TARGET unbound, and every rg call
# silently scanned NOTHING while the script still printed "✅ no slop found". A gate that
# cannot read its input must fail loudly, never pass. Portable read-loop instead.
FILES=()
if [ -n "$DIFF_BASE" ]; then
  while IFS= read -r _f; do
    [ -n "$_f" ] && FILES+=("$_f")
  done < <(git diff --name-only --diff-filter=d "$DIFF_BASE" -- '*.ts' '*.tsx' 2>/dev/null \
    | grep -vE '\.(test|spec)\.tsx?$|\.d\.ts$')
  if [ ${#FILES[@]} -eq 0 ]; then
    echo "anti-slop: no changed .ts/.tsx vs $DIFF_BASE — clean."
    exit 0
  fi
  TARGET=("${FILES[@]}")
else
  TARGET=("${PATHS[@]}")
fi

# Anti-vacuous-pass guard: bash 3.2 treats an empty array as unbound under `set -u`, so a
# future refactor that leaves TARGET empty would resurrect the silent-pass bug. Refuse to
# report a verdict we did not actually compute.
if [ ${#TARGET[@]} -eq 0 ]; then
  echo "anti-slop: ERROR — empty scan target; refusing to report a pass." >&2
  exit 2
fi

# Patterns (PCRE). Each maps to a refactor hint.
declare -a PAT HINT
PAT+=('\bfunction\s+is(Record|Object)\b|:\s*\w+\s+is\s+Record<\s*string\s*,\s*(unknown|any)\s*>')
HINT+=('generic structural guard — define an interface / discriminated union / Zod schema instead')
PAT+=('\bas\s+unknown\s+as\s+\w')
HINT+=('launder-cast (as unknown as T) — narrow with a schema, not a double-cast')
PAT+=('\(\s*\w+\s+as\s+any\s*\)\s*[.\[]')
HINT+=('(x as any).field reach-cast — type the value or validate its shape')

run_rg() {  # $1=pattern
  if [ -n "$RG" ]; then
    "$RG" -nP --no-heading -g '!*.test.ts' -g '!*.test.tsx' -g '!*.spec.ts' -g '!*.d.ts' \
      -g '!node_modules' -g '!dist' "$1" "${TARGET[@]}" 2>/dev/null
  else
    grep -rnP --include='*.ts' --include='*.tsx' \
      --exclude='*.test.ts' --exclude='*.test.tsx' --exclude='*.d.ts' \
      --exclude-dir=node_modules --exclude-dir=dist "$1" "${TARGET[@]}" 2>/dev/null
  fi
}

TOTAL=0
echo "── anti-slop TypeScript scan (${#TARGET[@]} target(s)) ──"
for i in "${!PAT[@]}"; do
  OUT=$(run_rg "${PAT[$i]}")
  if [ -n "$OUT" ]; then
    N=$(printf '%s\n' "$OUT" | grep -c .)
    TOTAL=$((TOTAL + N))
    echo ""
    echo "⚠️  ${HINT[$i]}  ($N)"
    printf '%s\n' "$OUT" | sed 's/^/    /'
  fi
done

echo ""
if [ "$TOTAL" -eq 0 ]; then
  echo "✅ no TypeScript slop patterns found."
  exit 0
fi
echo "Σ $TOTAL slop hit(s). Refactor per ~/.claude/skills/shared/anti-slop-typescript.md (specific types / discriminated unions / Zod)."
if [ -n "$THRESH" ] && [ "$TOTAL" -gt "$THRESH" ]; then
  echo "BLOCK: $TOTAL > threshold $THRESH."
  exit 1
fi
exit 0
