#!/usr/bin/env bash
#
# Weekly drift validator — walks every ~/.claude/skills/*/skill.md and
# SKILL.md, extracts backticked commands and path references, verifies they
# still resolve. Writes findings to ~/.claude/skill-drift.md.
#
# Usage:
#   skill-drift-check.sh            # run + write report
#   skill-drift-check.sh --quiet    # no stdout unless issues found

set -e
QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

OUT="$HOME/.claude/skill-drift.md"
SKILLS_DIR="$HOME/.claude/skills"

python3 - "$SKILLS_DIR" "$OUT" "$QUIET" <<'PY'
import os, re, sys, shutil, subprocess
from pathlib import Path

skills_dir, out_path, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

# Commands we know are safe to probe
SAFE_PROBES = {
    # binary: test command
    "bd": ["bd", "--help"],
    "gh": ["gh", "--version"],
    "jq": ["jq", "--version"],
    "osgrep": ["osgrep", "--version"],
    "qmd": ["qmd", "--version"],
    "wrangler": ["wrangler", "--version"],
    "git": ["git", "--version"],
    "gcloud": ["gcloud", "--version"],
    "rclone": ["rclone", "version"],
    "openclaw": ["openclaw", "--version"],
    "asc": ["asc", "--version"],
    "gpd": ["gpd", "--version"],
    "composio": [os.path.expanduser("~/tools/composio/composio-client.cjs"), "status"],
}

findings = []
seen_bins = set()

# Load allowlist early so both path and binary branches can consult it
allow_path = Path.home() / ".claude" / "skill-drift-allowlist.txt"
global_allowlist = set()
if allow_path.exists():
    global_allowlist = set(allow_path.read_text().splitlines())

for skill_md in Path(skills_dir).rglob("*"):
    if skill_md.name.lower() not in ("skill.md",):
        continue
    try:
        text = skill_md.read_text(errors="ignore")
    except Exception:
        continue

    # Extract first-token of any `backticked command`
    for m in re.finditer(r"`([^`\n]{2,80})`", text):
        snippet = m.group(1).strip()
        # skip pure paths, flags, filenames
        if snippet.startswith(("/", "~", "-", ".")) or "/" not in snippet and " " not in snippet and not snippet.isalnum():
            # single word — could be a binary
            cand = snippet
        else:
            cand = snippet.split()[0]
        cand = cand.strip("'\"()[],.")
        if not cand or cand in seen_bins or len(cand) > 30:
            continue
        if cand in global_allowlist:
            seen_bins.add(cand)
            continue
        if re.match(r"^[a-zA-Z][\w-]{1,29}$", cand) and cand in SAFE_PROBES:
            seen_bins.add(cand)
            try:
                r = subprocess.run(
                    SAFE_PROBES[cand],
                    capture_output=True, timeout=4,
                    env={**os.environ, "PATH": os.environ.get("PATH", "")},
                )
                if r.returncode not in (0, 1, 2):  # 0=ok, 1/2 often = help-shown
                    findings.append(f"- {cand} (referenced in {skill_md.relative_to(Path.home())}) returned exit {r.returncode}")
            except FileNotFoundError:
                findings.append(f"- {cand} NOT FOUND on PATH (referenced in {skill_md.relative_to(Path.home())})")
            except subprocess.TimeoutExpired:
                findings.append(f"- {cand} timed out (referenced in {skill_md.relative_to(Path.home())})")
            except Exception as e:
                findings.append(f"- {cand} error: {e} (referenced in {skill_md.relative_to(Path.home())})")

    # Detect referenced local paths (starting with ~/ or /Users or ./skills)
    on_mac = sys.platform == "darwin"
    allowlist = set()
    allow_path = Path.home() / ".claude" / "skill-drift-allowlist.txt"
    if allow_path.exists():
        allowlist = set(allow_path.read_text().splitlines())
    for m in re.finditer(r"`((?:~|/Users|/root|\./skills|\./references|\./tools)[^`\n]{2,200})`", text):
        p = os.path.expanduser(m.group(1).strip())
        p_only = p.split()[0]
        # Skip template placeholders
        if any(c in p_only for c in "<>{}") or any(ch in p_only for ch in "*?["):
            continue
        # Skip VPS-only paths when running on mac
        if on_mac and p_only.startswith("/root/"):
            continue
        # Skip user-acknowledged paths
        if p_only in allowlist:
            continue
        if p_only and not Path(p_only).exists():
            findings.append(f"- path missing: {p_only} (referenced in {skill_md.relative_to(Path.home())})")

# Dedup findings
unique = []
seen = set()
for f in findings:
    if f not in seen:
        unique.append(f); seen.add(f)

if unique:
    header = [
        "# Skill drift report",
        "",
        f"Found {len(unique)} issue(s) across skills. Review and fix — either update the skill to reflect new reality, or install the missing tool.",
        "",
    ]
    Path(out_path).write_text("\n".join(header + unique) + "\n")
    if not quiet:
        print(f"wrote {len(unique)} drift issue(s) to {out_path}")
else:
    try:
        Path(out_path).unlink()
    except FileNotFoundError:
        pass
    if not quiet:
        print("no drift issues")
PY
