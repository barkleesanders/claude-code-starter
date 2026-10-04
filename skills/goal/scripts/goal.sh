#!/usr/bin/env bash
# goal.sh — manage a persistent objective per cwd, ported from Codex `/goal`.
#
# Subcommands:
#   set <objective...>   Create a new goal (one per cwd; rejects if one exists)
#   status               Human-readable summary
#   show                 Print raw JSON state
#   pause                Mark paused (stops hook injection)
#   resume               Mark active
#   budget-limit         Mark budget_limited (wrap-up steering kicks in)
#   deliverable add|done|list   Manage the {text,done,evidence} deliverable ledger
#   complete             Mark complete (only valid from active/budget_limited)
#   clear                Delete the goal entirely
#   budget <tokens>      Set/clear (0 = clear) informational token budget
#
# State file: ~/.claude/state/goal/<sha-of-cwd>.json
# Mirrors the goal in beads (bd) when available: creates an issue on `set`,
# closes it on `complete`, marks deleted on `clear`, comments on pause/resume.
#
# CWD-SCOPED stack (2026-06-24): `complete`/`clear` auto-resume ONLY a stacked
# goal whose own `cwd` matches the current directory. A goal stacked while a
# DIFFERENT directory was active never auto-resumes (or gets closed) here — it
# stays put until you're in its directory. Fixes cross-directory goal pickup.

set -euo pipefail

STATE_DIR="${CLAUDE_GOAL_STATE_DIR:-$HOME/.claude/state/goal}"
mkdir -p "$STATE_DIR"

# Session-scoped state resolution lives in ONE place so goal.sh and both hooks
# can never drift apart again (2026-07-29). See goal-state-path.sh for the bug.
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/goal-state-path.sh"

# ---- helpers ---------------------------------------------------------------

cwd_hash() {
  # Stable per-cwd key. Use the resolved cwd so /private/var vs /var don't drift.
  local cwd
  cwd="$(cd "${CLAUDE_GOAL_CWD_OVERRIDE:-$PWD}" 2>/dev/null && pwd -P || echo "${CLAUDE_GOAL_CWD_OVERRIDE:-$PWD}")"
  printf '%s' "$cwd" | shasum -a 256 | cut -c1-16
}

# state_file: return the closest matching state file by walking up parent dirs.
# This way a goal set in /repo applies to /repo/src/foo too — matching how
# Codex scopes a goal to the thread (== session, which has one cwd).
# For `set` we want the exact current cwd; for everything else (status, pause,
# resume, complete, clear, show, budget) the parent-walk is correct.
state_file() {
  # Delegates to the shared session-scoped resolver. Keeps the historical
  # "exact" mode (used by `set`) meaning: the slot for THIS cwd + THIS session.
  goal_state_file "${1:-lookup}"
}

# ---- beads mirroring guard (2026-07-29) ------------------------------------
# `goal set` mirrors into a REAL beads issue. During the session-scoping test on
# 2026-07-29 that leaked two fixture issues ("Goal belonging to session A/B")
# into the live tracker, which then blocked the stop hook. A harness must be
# able to exercise goal.sh without touching beads.
# Skip mirroring when: explicitly disabled, OR the state dir is overridden
# (which only ever happens in tests).
goal_bd_enabled() {
  [ "${CLAUDE_GOAL_NO_BD:-0}" = "1" ] && return 1
  [ -n "${CLAUDE_GOAL_STATE_DIR:-}" ] && return 1
  return 0
}

# ---- goal stack ------------------------------------------------------------
# Multiple goals per cwd: the ACTIVE goal lives in <sha>.json (what the
# goal-injector hook reads); any previously-active goals are saved (paused) in
# a LIFO stack at <sha>.stack.json. `set` pushes the current goal onto the
# stack instead of rejecting; `complete`/`clear` pop the most recent back to
# active. This is the "save the other goal it sees and keep going" behavior.
stack_file() {
  goal_stack_file "$(state_file)"
}

stack_count() {
  local stk; stk="$(stack_file)"
  [ -f "$stk" ] || { printf '0'; return 0; }
  python3 - "$stk" <<'PY' 2>/dev/null || printf '0'
import json,sys
try:
    with open(sys.argv[1]) as f: a=json.load(f)
    print(len(a) if isinstance(a,list) else 0, end="")
except Exception:
    print(0, end="")
PY
}

# Push the current active goal (marked paused) onto the LIFO stack.
stack_push_current() {
  local sf stk; sf="$(state_file exact)"; stk="${sf%.json}.stack.json"
  [ -f "$sf" ] || return 0
  python3 - "$sf" "$stk" <<'PY'
import json, os, sys, tempfile
sf, stk = sys.argv[1], sys.argv[2]
with open(sf) as f: g = json.load(f)
g["status"] = "paused"
# keep the owner stamp with the goal so it never becomes "unowned" (shared)
g.setdefault("session", os.environ.get("CLAUDE_CODE_SESSION_ID") or "")
arr = []
if os.path.exists(stk):
    try:
        with open(stk) as f: arr = json.load(f)
        if not isinstance(arr, list): arr = []
    except Exception: arr = []
arr.append(g)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(stk), prefix=".gstk.")
with os.fdopen(fd, "w") as f: json.dump(arr, f, indent=2)
os.replace(tmp, stk)
PY
}

# Pop the most-recent stacked goal back to active (overwrites <sha>.json).
# Echoes the popped objective on success; returns 1 if no eligible goal exists.
#
# CWD-SCOPED (2026-06-24): only restores a stacked goal whose own `cwd` matches
# the CURRENT resolved cwd. A goal that was stacked while a DIFFERENT directory
# was active (cross-contamination via the shared stack file) is NEVER
# auto-resumed here — it is left in place so it can only ever resume in its own
# directory. This prevents `complete`/`clear` in one repo from silently flipping
# an unrelated goal from another repo to active (and then closing the wrong one).
# Reference incident: an AIVA-Frontend `complete` auto-resumed + closed a
# `$HOME/Downloads` "Example Org nonprofit signups" goal that was not
# done.
stack_pop_to_active() {
  local sf stk cwd; sf="$(state_file exact)"; stk="${sf%.json}.stack.json"
  cwd="$(resolved_cwd)"
  [ -f "$stk" ] || return 1
  python3 - "$sf" "$stk" "$cwd" <<'PY' || exit 1
import json, os, sys, tempfile, datetime
sf, stk, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(stk) as f: arr = json.load(f)
    if not isinstance(arr, list): arr = []
except Exception: arr = []
if not arr:
    sys.exit(1)
# Find the LAST (most-recent) stacked goal whose cwd matches the current cwd.
# Goals with a different/missing cwd stay in the stack untouched.
idx = None
for i in range(len(arr) - 1, -1, -1):
    g = arr[i]
    if isinstance(g, dict) and g.get("cwd") == cwd:
        idx = i
        break
if idx is None:
    sys.exit(1)  # nothing belonging to THIS cwd to resume
g = arr.pop(idx)
# RESTORE AS *PAUSED*, NEVER ACTIVE (2026-07-28).
# Popping straight to "active" hijacked whatever session happened to run
# `complete`/`clear`: finishing goal A instantly made unrelated goal B start
# injecting steering into a session that never asked for it, and the Stop hook
# then blocked on B. The goal is still restored to the slot (so `goal status`,
# `goal list` and `goal resume` all find it) — it just does not steer until the
# user explicitly runs `goal resume`. Reference incident: completing a long-running case goal auto-activated a mac-mini migration goal mid-session
# while the user was working an unrelated VR&E matter.
g["status"] = "paused"
g["updated_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".goal.")
with os.fdopen(fd, "w") as f: json.dump(g, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
if arr:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(stk), prefix=".gstk.")
    with os.fdopen(fd, "w") as f: json.dump(arr, f, indent=2)
    os.replace(tmp, stk)
else:
    os.remove(stk)
print(g.get("objective", ""), end="")
PY
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

resolved_cwd() {
  cd "${CLAUDE_GOAL_CWD_OVERRIDE:-$PWD}" 2>/dev/null && pwd -P || echo "${CLAUDE_GOAL_CWD_OVERRIDE:-$PWD}"
}

have_bd() {
  command -v bd >/dev/null 2>&1
}

# Run bd in the goal's cwd (so it picks up the right per-repo state).
bd_in_cwd() {
  ( cd "$(jq_get cwd)" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd "$@" )
}

# Read a single top-level string field from the state file.
jq_get() {
  local key="$1" sf
  sf="$(state_file)"
  [ -f "$sf" ] || { printf '' ; return 0; }
  python3 - "$sf" "$key" <<'PY' 2>/dev/null || true
import json, sys
sf, key = sys.argv[1], sys.argv[2]
try:
    with open(sf) as f: d = json.load(f)
    v = d.get(key)
    if v is None: print("", end="")
    else: print(v, end="")
except Exception:
    pass
PY
}

# Write the state file from key=value pairs (string values). Numeric or null
# values are passed via @<value> sentinel (e.g. token_budget=@null, token_budget=@50000).
# Writes to whichever state file currently resolves (parent-walk match if any,
# else the exact-cwd path).
# Identity of the Claude session touching this goal. Multiple concurrent Claude
# sessions share one cwd-keyed state file, so without this they clobber each
# other silently. Reference incident (2026-07-28): two sessions each faxed the
# same 17-page packet to a Public Defender ~5 minutes apart because neither knew
# the other was acting on the same goal.
session_id() {
  printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_CODE_BRIDGE_SESSION_ID:-pid-${CLAUDE_PID:-$PPID}}}"
}

# Advisory: warn when a DIFFERENT live session touched this goal recently.
# Purely informational — never blocks. Window defaults to 30 min.
warn_concurrent_session() {
  local sf cur_sess last_sess last_seen
  sf="$(state_file)"; [ -f "$sf" ] || return 0
  cur_sess="$(session_id)"
  last_sess="$(jq_get session)"; last_seen="$(jq_get session_seen_at)"
  [ -z "$last_sess" ] && return 0
  [ "$last_sess" = "$cur_sess" ] && return 0
  local age; age="$(python3 -c "
import datetime,sys
try:
    t=datetime.datetime.strptime(sys.argv[1],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
    print(int((datetime.datetime.now(datetime.timezone.utc)-t).total_seconds()))
except Exception: print(-1)
" "$last_seen" 2>/dev/null)"
  [ -z "$age" ] && return 0
  [ "$age" -lt 0 ] 2>/dev/null && return 0
  if [ "$age" -lt "${GOAL_CONCURRENT_WINDOW:-1800}" ]; then
    echo "" >&2
    echo "⚠️  ANOTHER CLAUDE SESSION IS WORKING THIS SAME GOAL." >&2
    echo "    Last touched ${age}s ago by session ${last_sess:0:8}… (you are ${cur_sess:0:8}…)." >&2
    echo "    Before ANY outward/irreversible action (send, fax, file, pay, deploy)," >&2
    echo "    re-verify it has not already been done — check sent mail / fax status /" >&2
    echo "    the goal's deliverable evidence FIRST. Two sessions have duplicated a" >&2
    echo "    real outward send before." >&2
  fi
}

write_state() {
  local sf
  sf="$(state_file)"
  python3 - "$sf" "session=$(session_id)" "session_seen_at=$(now_iso)" "$@" <<'PY'
import json, os, sys, tempfile
sf = sys.argv[1]
d = {}
if os.path.exists(sf):
    try:
        with open(sf) as f: d = json.load(f)
    except Exception:
        d = {}
for kv in sys.argv[2:]:
    if "=" not in kv: continue
    k, v = kv.split("=", 1)
    if v.startswith("@"):
        token = v[1:]
        if token == "null":
            d[k] = None
        else:
            try: d[k] = int(token)
            except ValueError:
                try: d[k] = float(token)
                except ValueError: d[k] = token
    else:
        d[k] = v
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".goal.")
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
PY
}

# Pretty status — colorized status badge.
status_badge() {
  case "$1" in
    active)         printf '\033[32m●\033[0m active' ;;
    paused)         printf '\033[33m●\033[0m paused' ;;
    budget_limited) printf '\033[33m●\033[0m budget-limited' ;;
    complete)       printf '\033[36m✓\033[0m complete' ;;
    *)              printf '%s' "$1" ;;
  esac
}

require_state() {
  if [ ! -f "$(state_file)" ]; then
    echo "No goal set for $(resolved_cwd)" >&2
    echo "Use: goal set <objective>" >&2
    exit 2
  fi
}

elapsed_seconds() {
  local started="$1"
  if [ -z "$started" ]; then echo 0; return; fi
  python3 - "$started" <<'PY' 2>/dev/null || echo 0
import sys, datetime
s = sys.argv[1].rstrip("Z")
try:
    t0 = datetime.datetime.fromisoformat(s).replace(tzinfo=datetime.timezone.utc)
    now = datetime.datetime.now(datetime.timezone.utc)
    print(int((now - t0).total_seconds()))
except Exception:
    print(0)
PY
}

human_duration() {
  local s="$1"
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm %ds' $((s/60)) $((s%60))
  else printf '%dh %dm' $((s/3600)) $(( (s%3600)/60 ))
  fi
}

# ---- deliverables ledger ---------------------------------------------------
# A goal may carry a `deliverables` array in its state JSON. Each entry is
# {text, done:false, evidence:""}. The array is OPTIONAL — a goal without it
# behaves exactly as it did before this feature existed (every reader below
# treats an absent/empty array as "no deliverables"). The model populates the
# ledger (via `goal deliverable add`) on the first turn after a goal is set,
# steered by the goal-injector hook, and records evidence as work proceeds.

# Print the ledger for the active goal (empty output if none). Reused by
# `deliverable list`, `status`, and `list`.
render_deliverables() {
  local sf; sf="$(state_file)"
  [ -f "$sf" ] || return 0
  python3 - "$sf" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
except Exception:
    sys.exit(0)
dl = d.get("deliverables")
if not isinstance(dl, list) or not dl:
    sys.exit(0)
done = sum(1 for x in dl if isinstance(x, dict) and x.get("done"))
print("Deliverables (%d/%d done):" % (done, len(dl)))
for i, x in enumerate(dl, 1):
    if not isinstance(x, dict):
        continue
    mark = "[x]" if x.get("done") else "[ ]"
    print("  %s #%d %s" % (mark, i, (x.get("text") or "")))
    ev = (x.get("evidence") or "").strip()
    if ev:
        print("        └ evidence: %s" % ev[:200])
PY
}

# Print "#<n> <text>" for every deliverable whose evidence is empty (used to
# gate `complete`). Empty output = every deliverable has evidence (or none exist).
deliverables_missing_evidence() {
  local sf; sf="$(state_file)"
  [ -f "$sf" ] || return 0
  python3 - "$sf" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
except Exception:
    sys.exit(0)
dl = d.get("deliverables")
if not isinstance(dl, list):
    sys.exit(0)
for i, x in enumerate(dl, 1):
    if not isinstance(x, dict):
        continue
    if not (x.get("evidence") or "").strip():
        print("#%d %s" % (i, (x.get("text") or "")[:90]))
PY
}

# ---- bd integration --------------------------------------------------------

bd_create_for_goal() {
  # Create a bd issue mirroring this goal. Echo the id (or empty on failure).
  have_bd || { echo ""; return 0; }
  local cwd="$1" objective="$2"
  local title body id
  # Trim to a reasonable title length; keep full text in description.
  title="goal: $(printf '%s' "$objective" | head -c 120)"
  body=$(cat <<EOF
$objective

---
Tracked by the \`goal\` skill (ported from Codex \`/goal\`).
- cwd: $cwd
- state: $(state_file)
- created: $(now_iso)

Lifecycle is driven by \`~/.claude/skills/goal/scripts/goal.sh\`:
- \`goal pause\` / \`goal resume\` → bd comment
- \`goal complete\` → bd close
- \`goal clear\` → bd status=deleted
EOF
)
  if ! goal_bd_enabled; then printf '%s' ""; return 0; fi
  id=$(
    ( cd "$cwd" 2>/dev/null && \
      BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd create \
        --title="$title" \
        --description="$body" \
        --type=task \
        --priority=1 \
        --json 2>/dev/null \
    ) | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""), end="")' 2>/dev/null
  ) || id=""
  if [ -n "$id" ]; then
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd label add "$id" workflow:goal ) >/dev/null 2>&1 || true
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd label add "$id" actor:agent ) >/dev/null 2>&1 || true
    goal_bd_enabled && ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd update "$id" --claim ) >/dev/null 2>&1 || true
  fi
  printf '%s' "$id"
}

bd_note() {
  # Append a one-line note to the bd issue (if we have one and bd is installed).
  have_bd || return 0
  local id cwd
  id="$(jq_get bd_issue_id)"
  cwd="$(jq_get cwd)"
  [ -z "$id" ] && return 0
  [ -z "$cwd" ] && return 0
  goal_bd_enabled && ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd update "$id" --note "$1" ) >/dev/null 2>&1 || true
}

bd_close_for_goal() {
  have_bd || return 0
  local id cwd
  id="$(jq_get bd_issue_id)"
  cwd="$(jq_get cwd)"
  [ -z "$id" ] && return 0
  [ -z "$cwd" ] && return 0
  goal_bd_enabled && ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd close "$id" --reason "$1" ) >/dev/null 2>&1 || true
}

bd_delete_for_goal() {
  have_bd || return 0
  local id cwd
  id="$(jq_get bd_issue_id)"
  cwd="$(jq_get cwd)"
  [ -z "$id" ] && return 0
  [ -z "$cwd" ] && return 0
  goal_bd_enabled && ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-goal}" bd update "$id" --status=deleted ) >/dev/null 2>&1 || true
}

# ---- subcommands -----------------------------------------------------------

cmd_set() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: goal set <objective>" >&2
    echo "Example: goal set follow the instructions in docs/goal.md" >&2
    exit 64
  fi
  # `set` always operates on the exact cwd, not an ancestor's goal, so
  # subdirectories can legitimately have their own.
  local stacked_note=""
  if [ -f "$(state_file exact)" ]; then
    local cur_status cur_obj
    cur_status="$(jq_get status)"
    cur_obj="$(jq_get objective)"
    if [ "$cur_status" = "complete" ]; then
      # A finished goal in the slot — replace it (no point stacking the done one).
      :
    else
      # An ACTIVE/paused goal exists. Instead of rejecting, SAVE it onto the
      # stack and keep going — the new goal becomes active, the old one resumes
      # automatically when this one completes/clears.
      bd_note "Goal stacked (paused) — a newer goal took focus: $(printf '%s' "$*" | head -c 80)"
      stack_push_current
      local n; n="$(stack_count)"
      stacked_note="Saved previous goal to the stack (now $n stacked): $(printf '%s' "$cur_obj" | head -c 90)"
    fi
  fi
  local objective="$*" cwd now
  cwd="$(resolved_cwd)"
  now="$(now_iso)"
  local bd_id=""
  bd_id="$(bd_create_for_goal "$cwd" "$objective")"

  # write_state would walk-up and stomp a parent goal if one existed; for
  # `set` we always create the state at the exact cwd. Write directly with
  # python so we bypass the lookup helper.
  python3 - "$(state_file exact)" "$objective" "$now" "$cwd" "${bd_id:-}" "$(session_id)" <<'PY'
import json, os, sys, tempfile
sf, objective, now, cwd, bd_id, sess = sys.argv[1:7]
d = {
    "objective": objective,
    "status": "active",
    "created_at": now,
    "updated_at": now,
    "completed_at": None,
    "cwd": cwd,
    "token_budget": None,
    "bd_issue_id": bd_id,
    # Which Claude session last touched this goal (concurrency guard).
    "session": sess,
    "session_seen_at": now,
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".goal.")
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
PY

  echo "Goal set."
  echo "Objective: $objective"
  if [ -n "$bd_id" ]; then
    echo "Tracked in beads as: $bd_id"
  fi
  [ -n "$stacked_note" ] && echo "$stacked_note (it returns PAUSED when this goal completes/clears — run \`goal resume\` to work it; \`goal list\` to see all)."
  echo "Steering will be injected before every user prompt until you run \`goal complete\` or \`goal clear\`."
}

cmd_status() {
  require_state
  local obj status created updated budget bd_id elapsed
  obj="$(jq_get objective)"
  status="$(jq_get status)"
  created="$(jq_get created_at)"
  updated="$(jq_get updated_at)"
  budget="$(jq_get token_budget)"
  bd_id="$(jq_get bd_issue_id)"
  elapsed="$(elapsed_seconds "$created")"
  printf 'Goal: %s\n' "$obj"
  printf 'Status: '; status_badge "$status"; printf '\n'
  printf 'Created: %s   Elapsed: %s\n' "$created" "$(human_duration "$elapsed")"
  [ -n "$updated" ] && [ "$updated" != "$created" ] && printf 'Updated: %s\n' "$updated"
  [ -n "$budget" ] && printf 'Token budget: %s (informational; not enforced)\n' "$budget"
  [ -n "$bd_id" ] && printf 'Beads: %s\n' "$bd_id"
  local ledger; ledger="$(render_deliverables)"
  [ -n "$ledger" ] && printf '%s\n' "$ledger"
  warn_concurrent_session
}

cmd_show() {
  require_state
  cat "$(state_file)"
}

cmd_pause() {
  require_state
  local cur; cur="$(jq_get status)"
  if [ "$cur" = "complete" ]; then echo "Cannot pause a completed goal." >&2; exit 2; fi
  write_state status=paused updated_at="$(now_iso)"
  bd_note "Goal paused via \`goal pause\`."
  echo "Goal paused. Hook injection suspended. Resume with \`goal resume\`."
}

cmd_resume() {
  require_state
  local cur; cur="$(jq_get status)"
  if [ "$cur" = "complete" ]; then echo "Cannot resume a completed goal. Use \`goal set …\` for a new one." >&2; exit 2; fi
  write_state status=active updated_at="$(now_iso)"
  bd_note "Goal resumed via \`goal resume\`."
  echo "Goal resumed."
}

cmd_budget_limit() {
  require_state
  local cur; cur="$(jq_get status)"
  if [ "$cur" != "active" ]; then echo "budget-limit is only meaningful from status=active (current: $cur)." >&2; exit 2; fi
  write_state status=budget_limited updated_at="$(now_iso)"
  bd_note "Marked budget_limited; wrap-up steering activated."
  echo "Goal marked budget-limited. Wrap-up steering will fire on the next turn."
}

cmd_complete() {
  require_state
  # Evidence-gated completion: everything after `complete` (minus --force) is the
  # proof note. A goal cannot be flipped to complete without stating WHY it's done.
  local force=0 evidence=""
  for a in "$@"; do
    case "$a" in
      --force|-f) force=1 ;;
      *) evidence="${evidence:+$evidence }$a" ;;
    esac
  done
  local cur obj; cur="$(jq_get status)"; obj="$(jq_get objective)"
  if [ "$cur" = "complete" ]; then
    # A finished goal must NOT block the stack: pop the next stacked goal to active
    # so `complete` keeps draining the LIFO instead of dead-ending on a done slot.
    echo "Active goal already complete." >&2
    local popped
    if popped="$(stack_pop_to_active)"; then
      bd_note "Goal restored from the stack as PAUSED (prior active goal was already complete)."
      echo "↩︎  Restored previous goal from the stack — PAUSED, not steering: $popped"
      echo "    ($(stack_count) still stacked. Run \`goal resume\` to work it, or \`goal list\` to see all.)"
    else
      echo "No stacked goals remain."
    fi
    exit 0
  fi
  if [ "$cur" != "active" ] && [ "$cur" != "budget_limited" ]; then
    echo "Cannot complete from status=$cur. Resume first (\`goal resume\`) and re-audit before completing." >&2
    exit 2
  fi
  # Require an evidence note (the completion audit, in one line) unless --force.
  if [ -z "$evidence" ] && [ "$force" -ne 1 ]; then
    echo "Refusing to complete without evidence." >&2
    echo "Run:  goal complete \"<one-line proof every deliverable is actually done —" >&2
    echo "      cite the artifact for each: file:line, command exit, URL, msg id, count>\"" >&2
    echo "Bypass (discouraged, recorded as forced):  goal complete --force" >&2
    exit 3
  fi
  # Deliverable-ledger gate: if the goal carries deliverables, EVERY one must
  # have evidence before it can be marked complete. Backward-compatible — a goal
  # with no `deliverables` array skips this entirely (empty output = pass).
  if [ "$force" -ne 1 ]; then
    local missing; missing="$(deliverables_missing_evidence)"
    if [ -n "$missing" ]; then
      echo "Refusing to complete — these deliverables have no evidence:" >&2
      printf '%s\n' "$missing" | sed 's/^/    /' >&2
      echo "Record each:  goal deliverable done <n> \"<proof>\"" >&2
      echo "Bypass (discouraged, recorded as forced):  goal complete --force" >&2
      exit 3
    fi
  fi
  [ -z "$evidence" ] && evidence="(forced — no evidence recorded)"
  local now elapsed
  now="$(now_iso)"
  elapsed="$(elapsed_seconds "$(jq_get created_at)")"
  write_state status=complete updated_at="$now" completed_at="$now" evidence="$evidence"
  bd_close_for_goal "Goal achieved (elapsed: $(human_duration "$elapsed")). Evidence: $evidence"
  echo "Goal marked complete."
  echo "Elapsed: $(human_duration "$elapsed")"
  echo "Evidence: $evidence"
  echo "Objective was: $obj"
  # Auto-resume the most-recent stacked goal, if any.
  local popped
  if popped="$(stack_pop_to_active)"; then
    bd_note "Goal restored from the stack as PAUSED (previous goal completed)."
    echo ""
    echo "↩︎  Restored previous goal from the stack — PAUSED, not steering: $popped"
    echo "    ($(stack_count) still stacked. Steering stays OFF until you run \`goal resume\`.)"
  fi
}

cmd_clear() {
  require_state
  bd_delete_for_goal
  rm -f "$(state_file)"
  echo "Goal cleared."
  # Auto-resume the most-recent stacked goal, if any.
  local popped
  if popped="$(stack_pop_to_active)"; then
    bd_note "Goal restored from the stack as PAUSED (previous goal cleared)."
    echo "↩︎  Restored previous goal from the stack — PAUSED, not steering: $popped"
    echo "    ($(stack_count) still stacked. Run \`goal resume\` to work it.)"
  fi
}

cmd_budget() {
  require_state
  if [ "$#" -ne 1 ]; then echo "Usage: goal budget <tokens|0>" >&2; exit 64; fi
  local v="$1"
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then echo "Token budget must be a non-negative integer." >&2; exit 64; fi
  if [ "$v" -eq 0 ]; then
    write_state token_budget=@null updated_at="$(now_iso)"
    echo "Token budget cleared."
  else
    write_state "token_budget=@$v" updated_at="$(now_iso)"
    echo "Token budget set to $v (informational; not auto-enforced)."
  fi
}

cmd_deliverable() {
  require_state
  local action="${1:-list}"
  shift || true
  case "$action" in
    add)      deliverable_add "$@" ;;
    done)     deliverable_done "$@" ;;
    list|ls)  deliverable_list ;;
    *) echo "Usage: goal deliverable <add \"<text>\" | done <n> \"<evidence>\" | list>" >&2; exit 64 ;;
  esac
}

deliverable_add() {
  local text="$*"
  if [ -z "$text" ]; then
    echo "Usage: goal deliverable add \"<text>\"" >&2
    exit 64
  fi
  local sf; sf="$(state_file)"
  python3 - "$sf" "$(now_iso)" "$text" <<'PY'
import json, os, sys, tempfile
sf, now, text = sys.argv[1], sys.argv[2], sys.argv[3]
with open(sf) as f: d = json.load(f)
dl = d.get("deliverables")
if not isinstance(dl, list): dl = []
dl.append({"text": text, "done": False, "evidence": ""})
d["deliverables"] = dl
d["updated_at"] = now
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".goal.")
with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
print("Added deliverable #%d: %s" % (len(dl), text))
PY
}

deliverable_done() {
  local n="${1:-}"; shift || true
  local evidence="$*"
  if [ -z "$n" ] || ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "Usage: goal deliverable done <n> \"<evidence>\"" >&2
    exit 64
  fi
  if [ -z "$evidence" ]; then
    echo "Refusing to mark deliverable #$n done without evidence." >&2
    echo "Run:  goal deliverable done $n \"<artifact: file:line, exit code, URL, msg id, count>\"" >&2
    exit 3
  fi
  local sf; sf="$(state_file)"
  python3 - "$sf" "$(now_iso)" "$n" "$evidence" <<'PY' || exit $?
import json, os, sys, tempfile
sf, now, n, evidence = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
with open(sf) as f: d = json.load(f)
dl = d.get("deliverables")
have = len(dl) if isinstance(dl, list) else 0
if not isinstance(dl, list) or n < 1 or n > have:
    sys.stderr.write("No deliverable #%d (have %d). Run `goal deliverable list`.\n" % (n, have))
    sys.exit(2)
dl[n-1]["done"] = True
dl[n-1]["evidence"] = evidence
d["deliverables"] = dl
d["updated_at"] = now
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".goal.")
with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
print("Deliverable #%d marked done: %s" % (n, dl[n-1]["text"]))
print("  Evidence: %s" % evidence)
PY
}

deliverable_list() {
  local out; out="$(render_deliverables)"
  if [ -z "$out" ]; then
    echo "No deliverables recorded yet. Add with: goal deliverable add \"<text>\""
  else
    printf '%s\n' "$out"
  fi
}

cmd_list() {
  # Show the active goal plus the saved (stacked) goals, newest first.
  local sf; sf="$(state_file)"
  if [ ! -f "$sf" ] && [ "$(stack_count)" = "0" ]; then
    echo "No goal set for $(resolved_cwd)."
    return 0
  fi
  if [ -f "$sf" ]; then
    printf 'ACTIVE  '; status_badge "$(jq_get status)"
    printf '  %s\n' "$(jq_get objective | head -c 110)"
    local ledger; ledger="$(render_deliverables)"
    [ -n "$ledger" ] && printf '%s\n' "$ledger"
  else
    echo "ACTIVE  (none)"
  fi
  local stk; stk="$(stack_file)"
  if [ -f "$stk" ]; then
    python3 - "$stk" <<'PY'
import json,sys
try:
    with open(sys.argv[1]) as f: a=json.load(f)
except Exception: a=[]
# newest first (LIFO: last appended resumes first)
for i,g in enumerate(reversed(a), start=1):
    obj=(g.get("objective") or "")[:110]
    print(f"  #{i:<2} stacked  {obj}")
if a:
    print(f"\n{len(a)} stacked goal(s). The top one auto-resumes when the active goal completes/clears.")
PY
  fi
}

cmd_help() {
  cat <<'EOF'
goal — persistent per-cwd objective with anti-completion-bias steering.
Supports a per-cwd goal STACK: `set` saves the current goal and runs the new
one; `complete`/`clear` auto-resume the most recent saved goal.

Usage:
  goal set <objective...>     New goal; if one is active it is SAVED to the stack
  goal status                 Human-readable summary (active goal)
  goal list                   Active goal + the saved stack
  goal show                   Raw JSON state (active goal)
  goal pause                  Suspend hook injection
  goal resume                 Re-enable hook injection
  goal budget-limit           Switch to wrap-up steering
  goal deliverable add "<t>"  Append a deliverable to the ledger {text,done,evidence}
  goal deliverable done <n> "<ev>"  Mark deliverable n done + record its evidence
  goal deliverable list       Show the deliverable ledger (also shown in status/list)
  goal complete "<evidence>"  Mark achieved — REQUIRES a one-line proof note citing the
                              artifact for each deliverable (file:line, exit code, URL, msg
                              id, count). Refuses if empty OR if any ledger deliverable has
                              no evidence. \`--force\` bypasses (recorded).
                              Runs only after the completion audit; then pops the stack
  goal clear                  Delete the active goal; pops the stack
  goal budget <tokens|0>      Set / clear informational token budget

State:  $HOME/.claude/state/goal/<sha-of-cwd>.json   (active)
Stack:  $HOME/.claude/state/goal/<sha-of-cwd>.stack.json  (saved goals, LIFO)
Hook:   $HOME/.claude/skills/hooks/goal-injector.sh (UserPromptSubmit; reads the active goal only)
Beads:  an issue is created on \`set\`, closed on \`complete\`,
        marked deleted on \`clear\`, commented on pause/resume/stack.

Parallel goals (tmux): goals are keyed by working directory, so to pursue two
at once give each its own cwd/session — e.g. run the second in a detached tmux
session (\`tmux new-session -d -s goal2 -c <other-dir>\`) and set its goal there.
Within ONE directory, use the stack (above): `set` never loses the prior goal.
EOF
}

# ---- dispatch --------------------------------------------------------------

sub="${1:-help}"
shift || true

# ---- cross-goal write guard (2026-08-05) -----------------------------------
# TWO data-loss incidents (2026-07-31, 2026-08-05): a mutating call ran from a
# DIFFERENT cwd than the one `goal set` used, silently resolved to an unrelated
# goal state file, and overwrote that goal deliverable evidence. Neither was
# recoverable (state/goal is untracked in the config repo). The second incident
# was caused by a shell left inside node_modules when `set` ran, so the goal was
# keyed to a deep path while later calls ran from HOME and hit a legacy file.
#
# Fix has two layers: every mutating command now ANNOUNCES which goal it is
# about to touch (that alone makes a cross-goal write visible immediately), and
# GOAL_EXPECT=<beads-id> upgrades the announcement to a hard precondition.
case "$sub" in
  deliverable|deliverables|dl|complete|pause|resume|clear|budget-limit)
    _gf="$(state_file 2>/dev/null || true)"
    if [ -n "$_gf" ] && [ -f "$_gf" ]; then
      # FIELD NAME: the state file writes "bd_issue_id" (see set/complete/clear
      # above). This read said "beads_id" — a field that has never existed — so
      # _gid was ALWAYS "-", which silently disabled BOTH guard layers: the
      # announcement printed no id for a human to check, and GOAL_EXPECT could
      # never match, so every guarded write was REFUSED with exit 65. The guard
      # documented as the protection against two real data-loss incidents was
      # itself inert. Fallback kept for any pre-rename state file.
      _gid="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("bd_issue_id") or d.get("beads_id") or "-")' "$_gf" 2>/dev/null || echo '-')"
      _gobj="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("objective") or "")[:64])' "$_gf" 2>/dev/null || echo '?')"
      printf '\033[2m[goal] target: %s — %s\033[0m\n' "$_gid" "$_gobj" >&2

      # Snapshot BEFORE any mutating write. Both known incidents (2026-07-31,
      # 2026-08-05) were unrecoverable purely because nothing kept a prior copy —
      # state/goal is untracked in the config repo and TM was unmountable. This
      # is the difference between "evidence lost forever" and "restore from
      # .bak". Cheap: these files are ~1-7 KB. Keeps the 20 most recent.
      _gbak="$(dirname "$_gf")/.backups"
      mkdir -p "$_gbak" 2>/dev/null || true
      if [ -d "$_gbak" ]; then
        cp -p "$_gf" "$_gbak/$(basename "$_gf" .json).$(date -u +%Y%m%dT%H%M%SZ).bak" 2>/dev/null || true
        # prune: keep newest 20 per state file, delete the rest
        ls -t "$_gbak/$(basename "$_gf" .json)."*.bak 2>/dev/null | tail -n +21 \
          | while IFS= read -r _old; do rm -f "$_old"; done
      fi

      if [ -n "${GOAL_EXPECT:-}" ] && [ "$GOAL_EXPECT" != "$_gid" ]; then
        printf 'REFUSED: GOAL_EXPECT=%s but this cwd resolves to goal %s\n' "$GOAL_EXPECT" "$_gid" >&2
        printf '  state file: %s\n' "$_gf" >&2
        printf '  This would write to a DIFFERENT goal. cd to the correct directory, or fix GOAL_EXPECT.\n' >&2
        exit 65
      fi
    fi
    ;;
esac

case "$sub" in
  set)           cmd_set "$@" ;;
  status)        cmd_status ;;
  list|ls)       cmd_list ;;
  show)          cmd_show ;;
  pause)         cmd_pause ;;
  resume)        cmd_resume ;;
  budget-limit)  cmd_budget_limit ;;
  deliverable|deliverables|dl) cmd_deliverable "$@" ;;
  complete)      cmd_complete "$@" ;;
  clear)         cmd_clear ;;
  budget)        cmd_budget "$@" ;;
  help|-h|--help) cmd_help ;;
  *) echo "Unknown subcommand: $sub" >&2; cmd_help >&2; exit 64 ;;
esac
