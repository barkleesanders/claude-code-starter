#!/usr/bin/env python3
"""Read a Mercury transactions API response on stdin, print per-vendor summary.
Used by mercury-pull.sh summary. Keeps formatting out of the shell script."""
import json
import sys
from collections import defaultdict

d = json.load(sys.stdin)
txns = d.get("transactions", [])
by_vendor = defaultdict(lambda: {"amt": 0.0, "count": 0, "cat": ""})
for tx in txns:
    v = tx.get("counterpartyName") or tx.get("description") or "?"
    a = float(tx.get("amount") or 0)
    by_vendor[v]["amt"] += a
    by_vendor[v]["count"] += 1
    by_vendor[v]["cat"] = tx.get("category") or ""

if not txns:
    print("0 transactions")
    sys.exit(0)

first = min((t.get("postedAt") or "") for t in txns if t.get("postedAt"))
last = max((t.get("postedAt") or "") for t in txns if t.get("postedAt"))
print(f"{len(txns)} transactions, {first[:10]} -> {last[:10]}")
print()
print(f"{'Vendor':<40} {'Category':<24} {'Total':>12} {'N':>4}")
print("-" * 85)
for v, info in sorted(by_vendor.items(), key=lambda x: x[1]["amt"]):
    print(f"  {v[:38]:<40} {(info['cat'] or '')[:22]:<24} ${info['amt']:>10,.2f} {info['count']:>4}x")

total_out = sum(i["amt"] for i in by_vendor.values() if i["amt"] < 0)
total_in = sum(i["amt"] for i in by_vendor.values() if i["amt"] > 0)
print("-" * 85)
print(f"  {'OUT':<40} {'':<24} ${total_out:>10,.2f}")
print(f"  {'IN':<40} {'':<24} ${total_in:>10,.2f}")
print(f"  {'NET':<40} {'':<24} ${total_in + total_out:>10,.2f}")
