#!/usr/bin/env bash
#
# Scan ~/.claude/tool-errors.jsonl for NOVEL error signatures (not already
# present in shared/tool-error-recovery.md), group by signature, and write
# a human-readable review file at ~/.claude/tool-errors-pending.md.
#
# When /carmack is invoked and that file exists non-empty, Claude should
# offer to classify the pending patterns and append them to the catalog.
#
# Usage:
#   scan-tool-errors.sh            # scan + write pending file
#   scan-tool-errors.sh --clear    # after classifying, archive the log
#   scan-tool-errors.sh --status   # summary only

set -e
LOG="${HOME}/.claude/tool-errors.jsonl"
CATALOG="${HOME}/.claude/skills/shared/tool-error-recovery.md"
PENDING="${HOME}/.claude/tool-errors-pending.md"

if [ ! -f "$LOG" ]; then
  echo "No error log at $LOG — nothing to scan."
  exit 0
fi

case "${1:-}" in
  --clear)
    mv "$LOG" "${LOG}.archived-$(date +%Y%m%d-%H%M%S)"
    rm -f "$PENDING"
    echo "archived $LOG and removed $PENDING"
    exit 0
    ;;
  --status)
    total=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    echo "tool-errors.jsonl: $total entries"
    [ -f "$PENDING" ] && echo "pending review: $(wc -l < "$PENDING") lines" || echo "no pending file"
    exit 0
    ;;
esac

python3 - "$LOG" "$CATALOG" "$PENDING" <<'PY'
import json, sys, os, collections, re
from pathlib import Path

log_path, catalog_path, pending_path = sys.argv[1], sys.argv[2], sys.argv[3]
catalog = Path(catalog_path).read_text(errors='ignore') if os.path.exists(catalog_path) else ''

# Collect entries grouped by signature
groups = collections.defaultdict(list)
for line in Path(log_path).read_text(errors='ignore').splitlines():
    try:
        d = json.loads(line)
    except Exception:
        continue
    groups[d['sig']].append(d)

# For each signature, decide novel-vs-known by keyword match against catalog
# We look for distinctive substrings from first_line in the catalog
def looks_known(first_line: str) -> bool:
    # pull a few 4+-char word tokens
    tokens = re.findall(r'[A-Za-z][A-Za-z0-9_]{3,}', first_line)
    if not tokens:
        return False
    # require at least 2 distinct tokens present in catalog
    hits = sum(1 for t in set(tokens[:8]) if t.lower() in catalog.lower())
    return hits >= 2

novel = []
for sig, entries in groups.items():
    first = entries[0]['first_line']
    if looks_known(first):
        continue
    novel.append({
        'sig': sig,
        'count': len(entries),
        'tools': sorted(set(e['tool'] for e in entries)),
        'first_line': first,
        'excerpt': entries[0]['excerpt'],
    })

novel.sort(key=lambda e: -e['count'])

if not novel:
    try: os.remove(pending_path)
    except FileNotFoundError: pass
    print("No novel tool-error patterns found; catalog is current.")
    sys.exit(0)

lines = [
    "# Pending tool-error patterns for classification",
    "",
    f"Scan of `{log_path}` found {len(novel)} signature(s) not yet documented in `{catalog_path}`.",
    "",
    "When /carmack loads, review each entry below and either:",
    "- Append a new numbered section to tool-error-recovery.md (What it means / How to recover / Prevention)",
    "- If already covered under a different wording, just note it and move on",
    "",
    "After classifying, run `~/.claude/skills/carmack/tools/scan-tool-errors.sh --clear` to archive the log.",
    "",
    "---",
    "",
]
for i, e in enumerate(novel[:40], 1):
    lines += [
        f"## {i}. [{e['count']}x via {','.join(e['tools'])}] {e['first_line']}",
        "",
        "```",
        e['excerpt'],
        "```",
        "",
    ]
Path(pending_path).write_text("\n".join(lines))
print(f"wrote {len(novel)} novel pattern(s) to {pending_path}")
PY
