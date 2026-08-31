#!/usr/bin/env bash
# ledger.sh — coverage receipts for /security-deep
#
# Makes "I reviewed the diff" a provable claim instead of an assertion.
# Pure bash + python3 stdlib. No deps.
#
#   ledger.sh init     <scan_dir> <base>            # build worklist from the diff
#   ledger.sh review   <scan_dir> <file> [note]     # mark a changed file reviewed
#   ledger.sh defer    <scan_dir> <file> <reason>   # mark it NOT reviewed, with a reason
#   ledger.sh add      <scan_dir> <file> <line> <category> <claim>
#   ledger.sh validate <scan_dir> <id> <disposition> <evidence>
#   ledger.sh status   <scan_dir>                   # human-readable progress
#   ledger.sh check    <scan_dir>                   # GATE: exit 1 if coverage incomplete
#
# Dispositions: confirmed | probable | suppressed | deferred

set -euo pipefail

die() { printf 'ledger: %s\n' "$1" >&2; exit 2; }
[ $# -ge 2 ] || die "usage: ledger.sh <command> <scan_dir> [args...]"

CMD=$1; SCAN_DIR=$2; shift 2
COVERAGE="$SCAN_DIR/coverage.jsonl"
CANDIDATES="$SCAN_DIR/candidates.jsonl"
WORKLIST="$SCAN_DIR/worklist.txt"

# append one JSON object; args are alternating key value
jappend() {
  local out=$1; shift
  python3 -c '
import json,sys
path=sys.argv[1]; kv=sys.argv[2:]
row={kv[i]: kv[i+1] for i in range(0,len(kv),2)}
with open(path,"a",encoding="utf-8") as f:
    f.write(json.dumps(row,ensure_ascii=False)+"\n")
' "$out" "$@"
}

case "$CMD" in
  init)
    [ $# -ge 1 ] || die "init needs <base>"
    mkdir -p "$SCAN_DIR/poc" "$SCAN_DIR/findings"
    git diff --name-only "$1"...HEAD > "$WORKLIST"
    : > "$COVERAGE"; : > "$CANDIDATES"
    printf 'worklist: %s changed files -> %s\n' "$(wc -l < "$WORKLIST" | tr -d ' ')" "$WORKLIST"
    ;;

  review)
    [ $# -ge 1 ] || die "review needs <file>"
    jappend "$COVERAGE" file "$1" status reviewed note "${2:-}"
    ;;

  defer)
    [ $# -ge 2 ] || die "defer needs <file> <reason>"
    jappend "$COVERAGE" file "$1" status deferred note "$2"
    ;;

  add)
    [ $# -ge 4 ] || die "add needs <file> <line> <category> <claim>"
    n=$( [ -f "$CANDIDATES" ] && wc -l < "$CANDIDATES" || echo 0 )
    id="c$(( n + 1 ))"
    jappend "$CANDIDATES" id "$id" file "$1" line "$2" category "$3" claim "$4" disposition "" evidence ""
    mkdir -p "$SCAN_DIR/poc/$id"
    printf '%s\n' "$id"
    ;;

  validate)
    [ $# -ge 3 ] || die "validate needs <id> <disposition> <evidence>"
    case "$2" in
      confirmed|probable|suppressed|deferred) ;;
      *) die "disposition must be: confirmed|probable|suppressed|deferred (got '$2')" ;;
    esac
    python3 -c '
import json,sys
path,cid,disp,ev=sys.argv[1:5]
rows=[json.loads(l) for l in open(path,encoding="utf-8") if l.strip()]
hit=False
for r in rows:
    if r.get("id")==cid:
        r["disposition"]=disp; r["evidence"]=ev; hit=True
if not hit:
    sys.exit(f"ledger: no candidate with id {cid}")
with open(path,"w",encoding="utf-8") as f:
    for r in rows: f.write(json.dumps(r,ensure_ascii=False)+"\n")
' "$CANDIDATES" "$1" "$2" "$3"
    ;;

  status|check)
    python3 -c '
import json,os,sys
scan,mode=sys.argv[1],sys.argv[2]
wl=os.path.join(scan,"worklist.txt")
if not os.path.exists(wl): sys.exit("ledger: no worklist.txt — run `ledger.sh init` first")
files=[l.strip() for l in open(wl,encoding="utf-8") if l.strip()]

def load(p):
    if not os.path.exists(p): return []
    return [json.loads(l) for l in open(p,encoding="utf-8") if l.strip()]

cov={r["file"]: r for r in load(os.path.join(scan,"coverage.jsonl"))}
cands=load(os.path.join(scan,"candidates.jsonl"))

missing=[f for f in files if f not in cov]
deferred=[f for f in files if cov.get(f,{}).get("status")=="deferred"]
unvalidated=[c["id"] for c in cands if not c.get("disposition")]
by={}
for c in cands:
    if c.get("disposition"): by[c["disposition"]]=by.get(c["disposition"],0)+1

reviewed=len(files)-len(missing)
print(f"coverage : {reviewed}/{len(files)} changed files have a receipt "
      f"({len(deferred)} deferred)")
print(f"candidates: {len(cands)} total -> " +
      (", ".join(f"{k} {v}" for k,v in sorted(by.items())) if by else "none dispositioned"))
if missing:
    print(f"\nNO RECEIPT ({len(missing)}):")
    for f in missing[:25]: print("  -", f)
    if len(missing)>25: print(f"  ... and {len(missing)-25} more")
if unvalidated:
    print("\nUNVALIDATED CANDIDATES: " + ", ".join(unvalidated))
if deferred:
    print("\nDEFERRED (must appear in the report):")
    for f in deferred:
        note = cov[f].get("note") or "(no reason given)"
        print("  - " + f + ": " + note)

if mode=="check":
    if missing or unvalidated:
        print("\nFAIL: coverage incomplete. Finish the rows, or `defer` them with a reason.")
        sys.exit(1)
    print("\nOK: every changed file has a receipt and every candidate has a disposition.")
' "$SCAN_DIR" "$CMD"
    ;;

  *) die "unknown command: $CMD" ;;
esac
