#!/usr/bin/env bash
# pre-compact-sync.sh — PreCompact hook for exec-plan
# Persists a bounded emergency checkpoint before context compaction.
set -u

# Prefer the stable python.org build on hosts where it is installed.
PYTHON="${PYTHON:-python3}"
if [ -x /Library/Frameworks/Python.framework/Versions/3.13/bin/python3 ]; then
  PYTHON=/Library/Frameworks/Python.framework/Versions/3.13/bin/python3
fi

PLANS_DIR="$HOME/tools/exec-plans"

# Fast exit: no exec-plans directory
[ -d "$PLANS_DIR" ] || exit 0

# Find plans with an open sprint. Only Status lines inside a sprint section
# count; this avoids reviving a completed plan because an old section mentions
# IN_PROGRESS.
has_open_sprint() {
  awk '
    /^## Sprint:/ { in_sprint = 1; found = 0; next }
    in_sprint && /^Status:/ { found = ($0 ~ /^Status:[[:space:]]*IN_PROGRESS([[:space:]]|$)/) }
    END { exit(found ? 0 : 1) }
  ' "$1" >/dev/null 2>&1
}

ACTIVE_PLANS=""
for plan_dir in "$PLANS_DIR"/*/; do
  [ -d "$plan_dir" ] || continue
  plan_name=$(basename "$plan_dir")
  sprint_log="${plan_dir}sprint-log.md"

  if [ -f "$sprint_log" ] && has_open_sprint "$sprint_log"; then
    ACTIVE_PLANS="${ACTIVE_PLANS}${plan_name} "
  fi
done

# Fast exit: no active plans
[ -n "$ACTIVE_PLANS" ] || exit 0

# Trim trailing space without spawning a command that can hide an error.
ACTIVE_PLANS="${ACTIVE_PLANS% }"

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || timestamp='unknown-time'
checkpoint_count=0
write_failures=""

for plan_dir in "$PLANS_DIR"/*/; do
  [ -d "$plan_dir" ] || continue
  plan_name=$(basename "$plan_dir")
  sprint_log="${plan_dir}sprint-log.md"
  handoff="${plan_dir}handoff.md"
  [ -f "$sprint_log" ] || continue
  has_open_sprint "$sprint_log" || continue

  # The hook cannot see the model's private working context. It records that
  # boundary explicitly instead of fabricating milestone or blocker details.
  # The latest handoff and sprint log remain the source of truth on resume.
  if [ ! -f "$handoff" ]; then
    write_failures="${write_failures}${plan_name} (handoff missing)\n"
    continue
  fi

  if "$PYTHON" - "$handoff" "$timestamp" <<'PYUPDATE'
import fcntl
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

path = Path(sys.argv[1])
begin = "<!-- agent-precompact-checkpoint:begin -->"
end = "<!-- agent-precompact-checkpoint:end -->"
# Serialize concurrent compactors, and never follow a replaced lock symlink.
fd = os.open(str(path) + ".precompact.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
with os.fdopen(fd, "r+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    if path.is_symlink() or not path.is_file():
        raise SystemExit("handoff must be a regular file")
    original = path.read_text()
    body = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "", original, flags=re.S).rstrip()
    checkpoint = f"""{begin}
## Automatic PreCompact checkpoint — {sys.argv[2]}

- **Current milestone state:** The latest sprint is IN_PROGRESS; use its recorded state.
- **What was accomplished:** Not observable to this hook; preserve the handoff above and Beads history.
- **Next action:** Continue the latest unfinished action in this handoff. Read `plan.md`, `sprint-log.md`, or the relevant Beads issue only if needed to resolve missing context.
{end}
"""
    fd, temporary = tempfile.mkstemp(prefix=".precompact-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(body + "\n\n" + checkpoint)
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode) & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
PYUPDATE
  then
    checkpoint_count=$((checkpoint_count + 1))
  else
    write_failures="${write_failures}${plan_name} (write failed)\n"
  fi

done

ctx="[exec-plan] CONTEXT COMPACTION IMMINENT. Active plans: ${ACTIVE_PLANS}. Automatic emergency checkpoints written: ${checkpoint_count}. The checkpoint records what this hook can verify and marks model-only fields for resume review."
if [ -n "$write_failures" ]; then
  ctx="${ctx} Checkpoint failures: ${write_failures}"
fi

# Encode filesystem names and failures as data; never interpolate them into JSON.
"$PYTHON" - "$ctx" <<'PYOUTPUT'
import json
import sys
print(json.dumps({"additionalContext": sys.argv[1]}))
PYOUTPUT
