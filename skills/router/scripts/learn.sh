#!/usr/bin/env bash
# Self-improvement report: summarize the routing decision log so the router (and
# the human) can see which routes work, which misfire, and where the catalog or
# routing-rules.md need editing. This is the INPUT to the improvement step — the
# model reads this, then edits references/routing-rules.md accordingly.
set -euo pipefail
STATE="$HOME/.claude/state/router"
LOG="$STATE/decisions.jsonl"
[ -f "$LOG" ] || { echo "router: no decisions logged yet ($LOG)"; exit 0; }

python3 - "$LOG" <<'PY'
import json,sys,collections
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(f"# Router learning report — {len(rows)} decisions\n")
by_out=collections.Counter(r.get("outcome","unknown") for r in rows)
print("## Outcomes")
for k,v in by_out.most_common(): print(f"- {k}: {v}")
print("\n## Skills chosen (freq)")
sk=collections.Counter()
for r in rows:
    for s in str(r.get("skills","")).replace(",", " ").split():
        sk[s]+=1
for k,v in sk.most_common(20): print(f"- {k}: {v}")
print("\n## Misfires (wrong/partial) — candidates for a routing-rule fix")
for r in rows:
    if r.get("outcome") in ("wrong","partial"):
        print(f"- [{r.get('outcome')}] task={r.get('task','')[:80]!r} -> {r.get('skills','')}  note={r.get('note','')[:80]}")
print("\n## Recent decisions (last 10)")
for r in rows[-10:]:
    print(f"- {r.get('ts','')[:16]}  {r.get('outcome','?'):7}  {r.get('skills','')}  | {r.get('task','')[:70]}")
PY
