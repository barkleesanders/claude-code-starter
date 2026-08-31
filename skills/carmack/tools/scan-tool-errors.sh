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

# For each signature, decide novel-vs-known by keyword match against catalog.
# Scan both first_line AND excerpt so aggregated/generic first_lines don't bypass the check.
def looks_known(first_line: str, excerpt: str = '') -> bool:
    text = (first_line + ' ' + excerpt).lower()
    tokens = re.findall(r'[A-Za-z][A-Za-z0-9_]{3,}', text)
    if not tokens:
        return False
    hits = sum(1 for t in set(tokens[:10]) if t in catalog.lower())
    return hits >= 2

# Native-guidance extraction — many tools embed the fix in their error text.
# Surfacing these hints alongside the signature cuts re-diagnosis to zero.
REMEDIATION_PATTERNS = [
    r"(?:set|setting)\s+([`'\"]?[a-zA-Z][a-zA-Z0-9_.]*[`'\"]?)\s+(?:to|=)\s+([0-9a-zA-Z.\"_-]+|\"[^\"]+\")",
    r"(?:try|run|use)\s+(?:running\s+)?[`']([^`']{3,80})[`']",
    r"Fix:\s*(?:run\s+)?[`']?([^`'\n]{3,120})[`']?",
    r"Run:\s*[`']?([^`'\n]{3,120})[`']?",
    r"(?:increase|raise|lower)\s+(?:your\s+)?([`'\"]?[a-zA-Z][a-zA-Z0-9_.]*[`'\"]?)\s+(?:to|by)\s+([0-9a-zA-Z.]+)",
    r"Did you mean\s+([`'\"]?[a-zA-Z][a-zA-Z0-9_.-]*[`'\"]?)",
    r"See\s+(https?://[^\s]+)",
    r"Read it first before",  # Edit tool's "File has not been read yet"
]

def extract_hints(text: str) -> list:
    hints = []
    for pat in REMEDIATION_PATTERNS:
        for m in re.finditer(pat, text, re.IGNORECASE):
            full = m.group(0)[:140]
            g = ' '.join(x for x in m.groups() if x)
            if full not in [h['full'] for h in hints]:
                hints.append({'full': full, 'captured': g[:80] if g else full[:80]})
    return hints[:5]

novel = []
for sig, entries in groups.items():
    first = entries[0]['first_line']
    excerpt = entries[0].get('excerpt', '')
    if looks_known(first, excerpt):
        continue
    novel.append({
        'sig': sig,
        'count': len(entries),
        'tools': sorted(set(e['tool'] for e in entries)),
        'first_line': first,
        'excerpt': excerpt,
        'hints': extract_hints(excerpt or first),
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
    lines.append(f"## {i}. [{e['count']}x via {','.join(e['tools'])}] {e['first_line']}")
    lines.append("")
    if e.get('hints'):
        lines.append("**🧭 Native remediation hints extracted from error text:**")
        for h in e['hints']:
            lines.append(f"- `{h['captured']}` (context: {h['full'][:100]})")
        lines.append("")
    lines.append("```")
    lines.append(e['excerpt'])
    lines.append("```")
    lines.append("")
Path(pending_path).write_text("\n".join(lines))
print(f"wrote {len(novel)} novel pattern(s) to {pending_path}")
PY
