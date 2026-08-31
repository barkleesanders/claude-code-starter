#!/usr/bin/env python3
"""Static regression guard for Carmack's proportional execution contract."""
from pathlib import Path
import re
import sys

skill = Path(__file__).resolve().parents[1] / "SKILL.md"
text = skill.read_text()
mode_text = (skill.parent / "references/mode-routing-expanded.md").read_text()
hard_text = (skill.parent / "references/hard-rules-expanded.md").read_text()
required = [
    "## Proportional Execution Lanes",
    "Carmack is a method, not a requirement to spawn another agent",
    "Do not delegate the sole critical path of a fast-lane, one-file fix",
    "Within **two tool batches after reading the target**",
    "five minutes or six tool calls",
    "work in the current agent",
    "Semantic Security Review Gate — PROPORTIONAL",
    "references/mode-routing-expanded.md",
    "references/hard-rules-expanded.md",
    "A backup script that pushes is a separate outward action",
]
forbidden = [
    "Use the Task tool with `subagent_type: carmack-mode-engineer`",
    "Launch `carmack-mode-engineer` agent",
    "Do not implement fixes in the main conversation",
    "run `~/claude-code-boilerplate/scripts/backup-claude-config.sh` and confirm its output shows a pushed commit URL",
]
missing = [item for item in required if item not in text]
present = [item for item in forbidden if item in text]
problems=[]
if missing: problems.append("missing required contract: " + "; ".join(missing))
if present: problems.append("forbidden unconditional workflow remains: " + "; ".join(present))
missing_refs = sorted({rel for rel in re.findall(r"`(references/[^`]+)`", text) if not (skill.parent / rel).exists()})
if missing_refs: problems.append("missing linked reference: " + "; ".join(missing_refs))
route_markers = [
    "**auth-security**", "**debug**", "**review**", "**feature**",
    "**provider-migration**", "**browser**", "**git**", "**deploy**",
]
missing_routes = [marker for marker in route_markers if marker not in mode_text]
route_rows = [line for line in mode_text.splitlines() if line.startswith("|") and not line.startswith("|---") and "User Intent Pattern" not in line]
if missing_routes: problems.append("missing specialist route: " + "; ".join(missing_routes))
if len(route_rows) < 55: problems.append(f"specialist route coverage shrank: {len(route_rows)} rows < 55")
hard_markers = [
    "### Deployment Prohibition", "### Premise-Check Before Debugging",
    "### Installed-Source Ground-Truth Guard", "### Semantic Security Review Gate",
    "### Instrument-Liveness", "### Fix the CALL-SITE CLASS",
]
missing_hard = [marker for marker in hard_markers if marker not in hard_text]
if missing_hard: problems.append("missing detailed hard-rule section: " + "; ".join(missing_hard))
if len(text) > 40000: problems.append(f"SKILL.md too large for fast loading: {len(text)} chars > 40000")
if text.count("\n") + 1 > 500: problems.append(f"SKILL.md too long for progressive disclosure: {text.count(chr(10))+1} lines > 500")
if problems:
    print("\n".join(problems))
    sys.exit(1)
print(f"PASS: proportional Carmack contract; {len(text)} chars; {text.count(chr(10))+1} lines")
