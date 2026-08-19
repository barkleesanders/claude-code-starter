#!/usr/bin/env bash
#
# Stop hook: keep the agent working until the plan and user requests are 100% done.
#
# LOGIC:
#   1. First stop attempt with real incomplete signals → block (ask agent to finish)
#   2. Second stop attempt (stop_hook_active=true) → always allow (agent reviewed and confirmed)
#   3. First stop attempt with NO signals → allow (nothing to check)
#   4. Max counter reached → always allow (safety valve)
#
# Incomplete signals:
#   - TaskCreate/TaskUpdate tool calls in transcript with pending/in_progress status
#   - Recent tool errors (is_error=true)
#   - Beads issues with status=in_progress updated within the last BEADS_WINDOW_MIN
#     minutes (default 120) — i.e., issues claimed in this working session.
#
# Env:
#   TASKMASTER_MAX       Max continuations (default: 3, 0 = infinite)
#   BEADS_WINDOW_MIN     Lookback window for in_progress beads issues (default: 120)
#   TASKMASTER_NO_BEADS  If set to "1", skip beads check entirely
#
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# --- If the hook already fired and the agent still wants to stop, let it. ---
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
  COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
  rm -f "$COUNTER_FILE"
  exit 0
fi

# --- loop guard ---
COUNTER_DIR="${TMPDIR:-/tmp}/taskmaster"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SESSION_ID}"
MAX=${TASKMASTER_MAX:-3}

COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE")
fi

if [ "$MAX" -gt 0 ] && [ "$COUNT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

# --- transcript analysis ---
HAS_INCOMPLETE_SIGNALS=false

if [ -f "$TRANSCRIPT" ]; then
  TAIL=$(tail -30 "$TRANSCRIPT" 2>/dev/null || true)
  if echo "$TAIL" | grep -q '"tool_name".*[Tt]ask' 2>/dev/null && \
     echo "$TAIL" | grep -q '"status".*"in_progress"\|"status".*"pending"' 2>/dev/null; then
    HAS_INCOMPLETE_SIGNALS=true
  fi
  if echo "$TAIL" | grep -q '"is_error".*true' 2>/dev/null; then
    HAS_INCOMPLETE_SIGNALS=true
  fi
fi

# --- beads analysis (in_progress issues touched in this session) ---
BEADS_BLOCK=""
BEADS_INFO=""
WINDOW_MIN=${BEADS_WINDOW_MIN:-120}

if [ "${TASKMASTER_NO_BEADS:-0}" != "1" ] && command -v bd >/dev/null 2>&1; then
  # Query each candidate beads DB and merge. Set TASKMASTER_BEADS_DIRS to
  # override (colon-separated). Default covers common layouts on Mac (~)
  # and on the VPS (~/clawd is the main OpenClaw work dir).
  DIRS="${TASKMASTER_BEADS_DIRS:-${HOME}:${HOME}/clawd}"
  BD_JSON="[]"
  OLD_IFS="$IFS"; IFS=":"
  for d in $DIRS; do
    [ -d "$d/.beads" ] || continue
    CHUNK=$(cd "$d" 2>/dev/null && bd list --status=in_progress --json 2>/dev/null || echo "[]")
    BD_JSON=$(jq -s 'add' <(echo "$BD_JSON") <(echo "$CHUNK") 2>/dev/null || echo "$BD_JSON")
  done
  IFS="$OLD_IFS"

  # Use python3 for portable ISO-8601 parsing with timezone offsets.
  # (jq's fromdateiso8601/strptime don't handle "+07:00" offsets consistently
  # across macOS jq 1.8 and Linux jq 1.7.)
  BEADS_RESULT=$(printf '%s' "$BD_JSON" | python3 -c '
import sys, json
from datetime import datetime, timezone, timedelta

window_min = int(sys.argv[1])
cutoff = datetime.now(timezone.utc) - timedelta(minutes=window_min)

try:
    raw = sys.stdin.read()
    items = json.loads(raw) if raw.strip() else []
except Exception:
    items = []

fresh, stale_count = [], 0
for it in items:
    ts = (it.get("updated_at") or "").strip()
    if not ts:
        continue
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        continue
    if dt.astimezone(timezone.utc) >= cutoff:
        fresh.append("  - " + str(it.get("id", "?")) + ": " + str(it.get("title", "")))
    else:
        stale_count += 1

print("FRESH_START")
print("\n".join(fresh))
print("FRESH_END")
print(f"STALE_COUNT={stale_count}")
' "$WINDOW_MIN")
  FRESH=$(echo "$BEADS_RESULT" | sed -n '/FRESH_START/,/FRESH_END/p' | sed '1d;$d')
  STALE_COUNT=$(echo "$BEADS_RESULT" | sed -n 's/^STALE_COUNT=//p')
  STALE_COUNT=${STALE_COUNT:-0}

  if [ -n "$FRESH" ]; then
    HAS_INCOMPLETE_SIGNALS=true
    BEADS_BLOCK=$'\n\nBeads issues still in_progress (touched in last '"$WINDOW_MIN"$' min):\n'"$FRESH"$'\n\nResolve options:\n  bd close <id>                       — mark complete\n  bd update <id> --status=open        — unclaim (put back on ready queue)\n  bd defer <id>                       — park for later (restore with bd undefer)\n  bd update <id> --status=blocked     — mark blocked'
  fi

  if [ "$STALE_COUNT" -gt 0 ]; then
    BEADS_INFO=$'\n\nNote: '"$STALE_COUNT"$' older in_progress beads issue(s) from prior sessions (run `bd list --status=in_progress` to review).'
  fi
fi

# --- worktree safety: never let a session end with unpushed commits in a
# worktree. Lost-work incident 2026-05-10 — trust pages worktree was wiped
# before push reached origin. The post-bash autopush hook covers the happy
# path; this stop check is the last line of defense.
WORKTREE_BLOCK=""
if command -v git >/dev/null 2>&1 && [ -n "${CLAUDE_PROJECT_DIR:-${PWD:-}}" ]; then
  ROOT="${CLAUDE_PROJECT_DIR:-${PWD}}"
  if [ -d "$ROOT/.git" ] || timeout 2 git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Walk every worktree and flag any with unpushed commits OR uncommitted changes.
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      wt="$line"
      # Skip the main checkout — only worktrees are at risk of silent removal.
      common=$(timeout 2 git -C "$wt" rev-parse --git-common-dir 2>/dev/null || true)
      gdir=$(timeout 2 git -C "$wt" rev-parse --git-dir 2>/dev/null || true)
      [ -z "$common" ] || [ -z "$gdir" ] && continue
      [ -d "$common" ] && common=$(cd "$common" && pwd)
      [ -d "$gdir" ] && gdir=$(cd "$gdir" && pwd)
      [ "$common" = "$gdir" ] && continue
      # Check uncommitted
      dirty=$(timeout 2 git -C "$wt" status --porcelain 2>/dev/null | head -5 || true)
      # Check unpushed
      branch=$(timeout 2 git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
      ahead=""
      if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
        upstream=$(timeout 2 git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
        if [ -z "$upstream" ]; then
          # Branch never pushed — every commit since branch creation is at risk
          local_count=$(timeout 2 git -C "$wt" rev-list --count HEAD ^"$(timeout 2 git -C "$wt" merge-base HEAD origin/HEAD 2>/dev/null || echo HEAD)" 2>/dev/null || echo 0)
          if [ -n "$local_count" ] && [ "$local_count" != "0" ]; then
            ahead="branch '$branch' has no upstream — $local_count commit(s) only on disk"
          fi
        else
          n=$(timeout 2 git -C "$wt" rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
          [ "$n" != "0" ] && [ -n "$n" ] && ahead="$n commit(s) ahead of $upstream"
        fi
      fi
      if [ -n "$dirty" ] || [ -n "$ahead" ]; then
        WORKTREE_BLOCK+=$'\n  '"$wt"
        [ -n "$ahead" ] && WORKTREE_BLOCK+=$'\n    unpushed: '"$ahead"
        if [ -n "$dirty" ]; then
          WORKTREE_BLOCK+=$'\n    uncommitted:'
          WORKTREE_BLOCK+=$'\n'"$(echo "$dirty" | sed 's/^/      /')"
        fi
      fi
    done < <(timeout 3 git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}')
  fi
fi
if [ -n "$WORKTREE_BLOCK" ]; then
  HAS_INCOMPLETE_SIGNALS=true
fi

# --- AI prompt edits pending live-API verification ---
# Companion to pre-bash-block-deploy-without-ai-verify.sh (warn-only) and
# post-bash-clear-ai-verification.sh. The Stop hook is the actual gate:
# session can't end until a real cache-busted curl clears pending entries.
# See memory: feedback_ai_verify_hook_chicken_egg.md
AI_VERIFY_BLOCK=""
AI_VERIFY_FILE="$HOME/.claude/ai-edits-pending-verification.jsonl"

# Auto-sweep false positives BEFORE the gate check. Two rules:
#   1. file matches the doc/plan/test/config skiplist → auto-verify
#      (false positives from the pre-fix loose content regex that flagged any
#      markdown mentioning "gemma" or "gpt-oss" — 2026-05-13 incident)
#   2. entry is >24h old AND the file hasn't been touched since → user moved
#      on; auto-verify with reason='auto-stale-24h'
# The skiplist lives in ~/.claude/skills/hooks/lib/ai-verify-classify.sh so
# both the producer and this consumer share the same definition.
if [ -f "$AI_VERIFY_FILE" ] && [ -f "$HOME/.claude/skills/hooks/lib/ai-verify-classify.sh" ]; then
  python3 - "$AI_VERIFY_FILE" <<'PY' 2>/dev/null
import json, os, subprocess, sys, time
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)
try:
    with open(path) as f:
        entries = [json.loads(l) for l in f if l.strip()]
except Exception:
    sys.exit(0)

lib = os.path.expandvars('$HOME/.claude/skills/hooks/lib/ai-verify-classify.sh')

def is_doc(fp):
    if not fp:
        return True
    r = subprocess.run(
        ['bash', '-c', f'. "{lib}"; ai_verify_should_skip "$1"', '_', fp],
        capture_output=True,
    )
    return r.returncode == 0

now = int(time.time())
changed = False
for e in entries:
    if e.get('verified'):
        continue
    fp = e.get('file', '')
    if is_doc(fp):
        e.update(verified=True, verified_at=now, verified_by='auto-doc-skip')
        changed = True
        continue
    try:
        exists = bool(fp) and os.path.exists(fp)
        mtime = int(os.path.getmtime(fp)) if exists else 0
    except Exception:
        exists, mtime = False, 0
    age = now - int(e.get('ts', 0))
    if age > 24 * 3600:
        # File deleted/moved since the entry was logged — verification target is
        # unreachable, so block-forever doesn't help anyone.
        if not exists:
            e.update(verified=True, verified_at=now, verified_by='auto-stale-file-gone')
            changed = True
            continue
        # File still there, but untouched since the entry — user moved on.
        if mtime and mtime <= int(e.get('ts', 0)):
            e.update(verified=True, verified_at=now, verified_by='auto-stale-24h')
            changed = True
if changed:
    with open(path, 'w') as f:
        for e in entries:
            f.write(json.dumps(e) + '\n')
PY
fi

if [ -f "$AI_VERIFY_FILE" ] && [ "${CLAUDE_ALLOW_UNVERIFIED_AI_EDIT:-0}" != "1" ]; then
  PENDING=$(python3 -c "
import json
try:
    with open('$AI_VERIFY_FILE') as f:
        entries = [json.loads(l) for l in f if l.strip()]
    pending = sorted(set(e.get('file', '?') for e in entries if not e.get('verified')))
    for p in pending:
        print('  - ' + p)
except Exception:
    pass
" 2>/dev/null)
  if [ -n "$PENDING" ]; then
    HAS_INCOMPLETE_SIGNALS=true
    AI_VERIFY_BLOCK=$'\n\nAI-VERIFY (LLM prompt edits pending live-API confirmation):\n'"$PENDING"$'\n\nRun a cache-busted curl against the deployed endpoint to confirm the model\noutput matches intent. Example:\n  curl -X POST <endpoint> -F "user_notes=<scenario> (cb-$(date +%s))" ...\n\nResolve options:\n  (A) Run the curl; post-bash-clear-ai-verification.sh auto-clears entries\n  (B) Manually mark verified:\n        python3 -c "import json; p=\'$AI_VERIFY_FILE\'; \\\n          es=[json.loads(l) for l in open(p) if l.strip()]; \\\n          [e.update(verified=True, verified_by=\'manual\') for e in es]; \\\n          open(p,\'w\').writelines(json.dumps(e)+\'\\n\' for e in es)"\n  (C) Override (logs to ~/.claude/logs/ai-verify-overrides.log):\n        CLAUDE_ALLOW_UNVERIFIED_AI_EDIT=1 (next session start)\n\n2026-05-10 incident: 3 broken iterations of /api/rewrite-text shipped before\nuser reported the same bug shape three times.'
  fi
fi

# --- decide ---
if [ "$HAS_INCOMPLETE_SIGNALS" = false ]; then
  rm -f "$COUNTER_FILE"
  exit 0
fi

NEXT=$((COUNT + 1))
echo "$NEXT" > "$COUNTER_FILE"

if [ "$MAX" -gt 0 ]; then
  LABEL="TASKMASTER (${NEXT}/${MAX})"
else
  LABEL="TASKMASTER (${NEXT})"
fi

WORKTREE_REASON=""
if [ -n "$WORKTREE_BLOCK" ]; then
  WORKTREE_REASON=$'\n\nWORKTREE SAFETY (unpushed work — could be lost if the worktree is removed):'"$WORKTREE_BLOCK"$'\n\nFor each worktree above:\n  cd <worktree-path>\n  git add -A && git commit -m "wip: snapshot"   # if uncommitted\n  git push -u origin HEAD                       # always\n\n2026-05-10 incident: trust pages worktree was wiped before push reached origin — 232 passing tests + 3 trust pages lost. Push to remote within ONE commit of any worktree work.'
fi

REASON="${LABEL}: Incomplete tasks or recent errors detected.

Before stopping, quickly check:
1. Any tasks still pending/in_progress? Finish or close them.
2. Any tool errors in the last few actions? Fix them.
3. Did the user's request get fully addressed?
4. BLIND SPOTS: for infra/config work, did you verify with real traffic
   (not just 'gateway started' logs)? Did adjacent systems break
   (binaries, symlinks, channel bundles, related services)? Check
   systemctl status, version string, log errors in last 2 min.
5. Did surfaced issues get fixed, not just reported? (fix-all-issues rule)

If everything is done, confirm completion briefly.${WORKTREE_REASON}${AI_VERIFY_BLOCK}${BEADS_BLOCK}${BEADS_INFO}"

jq -n --arg reason "$REASON" '{ decision: "block", reason: $reason }'
