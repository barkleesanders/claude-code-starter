#!/usr/bin/env bash
# loop.sh — run a Loop Library loop as a bounded, verifiable, ledgered cycle.
#
# A "loop" (from https://signals.forwardfuture.ai/loop-library/) ships as prose:
# a prompt, a {title,detail} verification, and steps. Prose can't loop on its
# own. This runner adds the machine contract the catalog lacks: an optional
# verify command, explicit stop predicates, a per-iteration JSONL ledger, and a
# lifecycle the injector + Stop-gate hooks enforce.
#
# Architecture mirrors ~/.claude/skills/goal/scripts/goal.sh (atomic python
# writes, per-cwd state hashing, bd mirroring, case dispatch).
#
# Subcommands:
#   start <slug> [--file f.json|--prompt "…"] [--verify "<cmd>"]
#               [--stop "max-iter=N,no-progress=M,target=<cmd>"] [--title "…"]
#   verify                 Run the verify cmd (machine) or print the criterion (self)
#   record "<action>" [--evidence "…"] [--verify-exit N] [--decision D]
#   check-stop             Print `continue` or `stop:<reason>`
#   continue               Print the next-cycle steering block
#   status | show | list | ledger
#   pause | resume | abort
#   complete               Refuses unless verify passed / a stop fired / self+evidence
#
# State:  ~/.claude/state/loop/<sha16-of-cwd>.json
# Ledger: ~/.claude/state/loop/<sha16-of-cwd>.jsonl

set -uo pipefail

STATE_DIR="${CLAUDE_LOOP_STATE_DIR:-$HOME/.claude/state/loop}"
CATALOG_URL="${LOOP_CATALOG_URL:-https://signals.forwardfuture.ai/loop-library/catalog.json}"
mkdir -p "$STATE_DIR"

# ---- helpers ---------------------------------------------------------------

resolved_cwd() {
  cd "${CLAUDE_LOOP_CWD_OVERRIDE:-$PWD}" 2>/dev/null && pwd -P || echo "${CLAUDE_LOOP_CWD_OVERRIDE:-$PWD}"
}

cwd_hash() {
  printf '%s' "$(resolved_cwd)" | shasum -a 256 | cut -c1-16
}

# state_file [exact]: exact-cwd path, or the nearest match walking up parents.
state_file() {
  local mode="${1:-lookup}"
  local exact="$STATE_DIR/$(cwd_hash).json"
  if [ "$mode" = "exact" ] || [ -f "$exact" ]; then
    printf '%s' "$exact"; return 0
  fi
  local d; d="$(resolved_cwd)"
  while [ -n "$d" ]; do
    local h sf
    h=$(printf '%s' "$d" | shasum -a 256 | cut -c1-16)
    sf="$STATE_DIR/$h.json"
    if [ -f "$sf" ]; then printf '%s' "$sf"; return 0; fi
    [ "$d" = "/" ] && break
    local parent; parent=$(dirname "$d")
    [ "$parent" = "$d" ] && break
    d="$parent"
  done
  printf '%s' "$exact"
}

ledger_file() {
  local sf; sf="$(state_file)"
  printf '%s' "${sf%.json}.jsonl"
}

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

have_bd() { [ "${LOOP_NO_BD:-0}" = "1" ] && return 1; command -v bd >/dev/null 2>&1; }

require_state() {
  if [ ! -f "$(state_file)" ]; then
    echo "No loop running for $(resolved_cwd)" >&2
    echo "Start one with: loop.sh start <slug|--prompt \"…\">" >&2
    exit 2
  fi
}

# jq_get <key>: read a top-level scalar from the state file.
jq_get() {
  local key="$1" sf; sf="$(state_file)"
  [ -f "$sf" ] || { printf ''; return 0; }
  python3 - "$sf" "$key" <<'PY' 2>/dev/null || true
import json, sys
sf, key = sys.argv[1], sys.argv[2]
try:
    with open(sf) as f: d = json.load(f)
    v = d.get(key)
    print("" if v is None else (v if isinstance(v, str) else json.dumps(v)), end="")
except Exception:
    pass
PY
}

# write_state key=value … ; numeric/null via @value sentinel (token_budget=@null).
write_state() {
  local sf; sf="$(state_file)"
  python3 - "$sf" "$@" <<'PY'
import json, os, sys, tempfile
sf = sys.argv[1]
d = {}
if os.path.exists(sf):
    try:
        with open(sf) as f: d = json.load(f)
    except Exception: d = {}
for kv in sys.argv[2:]:
    if "=" not in kv: continue
    k, v = kv.split("=", 1)
    if v.startswith("@"):
        tok = v[1:]
        if tok == "null": d[k] = None
        else:
            try: d[k] = int(tok)
            except ValueError:
                try: d[k] = float(tok)
                except ValueError: d[k] = tok
    else:
        d[k] = v
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".loop.")
with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
PY
}

ledger_append() {
  # ledger_append <iteration> <action> <evidence> <verify_exit> <decision> <note>
  local lf; lf="$(ledger_file)"
  python3 - "$lf" "$(now_iso)" "$@" <<'PY'
import json, sys
lf, ts, it, action, evidence, vexit, decision, note = sys.argv[1:9]
rec = {"ts": ts, "iteration": int(it) if it.isdigit() else it,
       "action": action, "evidence": evidence,
       "verify_exit": (int(vexit) if vexit.lstrip("-").isdigit() else None),
       "decision": decision, "note": note}
with open(lf, "a") as f: f.write(json.dumps(rec) + "\n")
PY
}

status_badge() {
  case "$1" in
    active)   printf '\033[32m●\033[0m active' ;;
    paused)   printf '\033[33m●\033[0m paused' ;;
    blocked)  printf '\033[33m●\033[0m blocked' ;;
    complete) printf '\033[36m✓\033[0m complete' ;;
    aborted)  printf '\033[31m✗\033[0m aborted' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# ---- bd integration (mirrors goal.sh) --------------------------------------

bd_create_for_loop() {
  have_bd || { echo ""; return 0; }
  local cwd="$1" title="$2" prompt="$3" id body
  body=$(cat <<EOF
$prompt

---
Tracked by the \`loop-runner\` skill — a running Loop Library loop.
- cwd: $cwd
- state: $(state_file exact)
- created: $(now_iso)

Lifecycle via \`~/.claude/skills/loop-runner/scripts/loop.sh\`:
\`pause\`/\`resume\` → bd comment · \`complete\` → bd close · \`abort\` → bd status=deleted
EOF
)
  id=$(
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd create \
        --title="loop: $(printf '%s' "$title" | head -c 110)" \
        --description="$body" --type=task --priority=2 --json 2>/dev/null \
    ) | python3 -c 'import json,sys;print(json.load(sys.stdin).get("id",""),end="")' 2>/dev/null
  ) || id=""
  if [ -n "$id" ]; then
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd label add "$id" workflow:loop ) >/dev/null 2>&1 || true
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd label add "$id" actor:agent ) >/dev/null 2>&1 || true
    ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd update "$id" --claim ) >/dev/null 2>&1 || true
  fi
  printf '%s' "$id"
}

bd_note()  { have_bd || return 0; local id cwd; id="$(jq_get bd_issue_id)"; cwd="$(jq_get cwd)"; [ -z "$id" ] && return 0; ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd update "$id" --note "$1" ) >/dev/null 2>&1 || true; }
bd_close() { have_bd || return 0; local id cwd; id="$(jq_get bd_issue_id)"; cwd="$(jq_get cwd)"; [ -z "$id" ] && return 0; ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd close "$id" --reason "$1" ) >/dev/null 2>&1 || true; }
bd_del()   { have_bd || return 0; local id cwd; id="$(jq_get bd_issue_id)"; cwd="$(jq_get cwd)"; [ -z "$id" ] && return 0; ( cd "$cwd" 2>/dev/null && BEADS_ACTOR="${BEADS_ACTOR:-claude-loop}" bd update "$id" --status=deleted ) >/dev/null 2>&1 || true; }

# ---- record resolution -----------------------------------------------------

# Emit shell assignments for PROMPT/TITLE/STEPS_JSON/VTITLE/VDETAIL from a
# catalog slug, a --file, or an inline --prompt. Reads $SRC, $SLUG, $FILE, $PROMPT_IN.
resolve_record() {
  python3 - "$SRC" "${SLUG:-}" "${FILE:-}" "${PROMPT_IN:-}" "$CATALOG_URL" <<'PY'
import json, sys, shlex, subprocess
src, slug, fpath, prompt_in, catalog = sys.argv[1:6]
rec = {}
if src == "inline":
    rec = {"prompt": prompt_in, "title": "(inline loop)", "steps": [], "verification": {}}
elif src == "file":
    with open(fpath) as f: rec = json.load(f)
elif src == "catalog":
    raw = subprocess.run(["curl", "-fsS", catalog], capture_output=True, text=True, timeout=20)
    if raw.returncode != 0:
        sys.stderr.write("catalog fetch failed\n"); sys.exit(3)
    data = json.loads(raw.stdout)
    loops = data["loops"] if isinstance(data, dict) and "loops" in data else (
        data if isinstance(data, list) else next((v for v in data.values() if isinstance(v, list)), []))
    rec = next((l for l in loops if l.get("slug") == slug), None)
    if rec is None:
        sys.stderr.write(f"no loop with slug '{slug}' in catalog\n"); sys.exit(4)
ver = rec.get("verification") or {}
if isinstance(ver, str): ver = {"title": ver, "detail": ""}
out = {
    "PROMPT": rec.get("prompt", ""),
    "TITLE": rec.get("title", slug or "(loop)"),
    "STEPS_JSON": json.dumps(rec.get("steps") or []),
    "VTITLE": ver.get("title", ""),
    "VDETAIL": ver.get("detail", ""),
}
for k, v in out.items():
    print(f"{k}={shlex.quote(str(v))}")
PY
}

# ---- subcommands -----------------------------------------------------------

cmd_start() {
  local SLUG="" FILE="" PROMPT_IN="" VERIFY="" STOP="" TITLE_OVERRIDE="" SRC=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --file)    FILE="$2"; SRC="file"; shift 2 ;;
      --prompt)  PROMPT_IN="$2"; SRC="inline"; shift 2 ;;
      --verify)  VERIFY="$2"; shift 2 ;;
      --stop)    STOP="$2"; shift 2 ;;
      --title)   TITLE_OVERRIDE="$2"; shift 2 ;;
      --*)       echo "Unknown flag: $1" >&2; exit 64 ;;
      *)         SLUG="$1"; [ -z "$SRC" ] && SRC="catalog"; shift ;;
    esac
  done
  [ -z "$SRC" ] && { echo "Usage: loop.sh start <slug> | --prompt \"…\" | --file f.json [--verify cmd] [--stop …]" >&2; exit 64; }

  if [ -f "$(state_file exact)" ]; then
    local cur; cur="$(jq_get status)"
    if [ "$cur" = "active" ] || [ "$cur" = "paused" ] || [ "$cur" = "blocked" ]; then
      echo "A loop is already $cur for this directory. Run \`loop.sh complete\` or \`loop.sh abort\` first." >&2
      echo "Current: $(jq_get title)" >&2
      exit 2
    fi
  fi

  local SRC_e="$SRC" SLUG_e="$SLUG" FILE_e="$FILE" PROMPT_e="$PROMPT_IN"
  export SRC="$SRC_e" SLUG="$SLUG_e" FILE="$FILE_e" PROMPT_IN="$PROMPT_e"
  local ASSIGN; ASSIGN="$(resolve_record)" || exit $?
  eval "$ASSIGN"
  [ -n "$TITLE_OVERRIDE" ] && TITLE="$TITLE_OVERRIDE"

  # Parse --stop into max_iterations / no_progress_for / target_cmd.
  local MAXIT=10 NOPROG=2 TARGET=""
  if [ -n "$STOP" ]; then
    eval "$(python3 - "$STOP" <<'PY'
import sys, shlex
spec = sys.argv[1]
mi, np_, tg = "10", "2", ""
for part in spec.split(","):
    part = part.strip()
    if not part or "=" not in part: continue
    k, v = part.split("=", 1)
    k = k.strip().replace("_", "-"); v = v.strip()
    if k in ("max-iter", "max-iterations", "iter"): mi = v
    elif k in ("no-progress", "no-progress-for", "stale"): np_ = v
    elif k == "target": tg = v
print(f"MAXIT={shlex.quote(mi)}")
print(f"NOPROG={shlex.quote(np_)}")
print(f"TARGET={shlex.quote(tg)}")
PY
)"
  fi

  local VERIFY_MODE="self"; [ -n "$VERIFY" ] && VERIFY_MODE="machine"
  local cwd now; cwd="$(resolved_cwd)"; now="$(now_iso)"
  local bd_id; bd_id="$(bd_create_for_loop "$cwd" "$TITLE" "$PROMPT")"

  python3 - "$(state_file exact)" "${SLUG:-}" "$SRC" "$TITLE" "$PROMPT" "$STEPS_JSON" \
    "$VTITLE" "$VDETAIL" "$VERIFY_MODE" "$VERIFY" "$MAXIT" "$NOPROG" "$TARGET" \
    "$now" "$cwd" "${bd_id:-}" <<'PY'
import json, os, sys, tempfile
(sf, slug, src, title, prompt, steps_json, vtitle, vdetail, vmode, vcmd,
 maxit, noprog, target, now, cwd, bd_id) = sys.argv[1:17]
try: steps = json.loads(steps_json)
except Exception: steps = []
d = {
  "slug": slug, "source": src, "title": title, "prompt": prompt, "steps": steps,
  "verification": {"title": vtitle, "detail": vdetail},
  "verify_mode": vmode, "verify_cmd": vcmd,
  "stop": {"max_iterations": int(maxit) if maxit.isdigit() else 10,
           "no_progress_for": int(noprog) if noprog.isdigit() else 2,
           "target_cmd": target},
  "status": "active", "iteration": 0, "no_progress_streak": 0, "last_verify_exit": None,
  "created_at": now, "updated_at": now, "cwd": cwd, "bd_issue_id": bd_id,
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(sf), prefix=".loop.")
with os.fdopen(fd, "w") as f: json.dump(d, f, indent=2, sort_keys=True)
os.replace(tmp, sf)
PY
  : > "$(ledger_file)"

  echo "Loop started: $TITLE"
  echo "Verify mode: $VERIFY_MODE$([ "$VERIFY_MODE" = machine ] && echo "  ($VERIFY)")"
  echo "Stop: max-iter=$MAXIT, no-progress=$NOPROG$([ -n "$TARGET" ] && echo ", target=$TARGET")"
  [ -n "$bd_id" ] && echo "Beads: $bd_id"
  echo "The loop-injector hook will drive each cycle; the Stop-gate enforces the bounds."
  if [ "$VERIFY_MODE" = self ]; then
    echo "NOTE: no --verify command → self-graded. 'complete' will require --evidence."
  fi
}

cmd_verify() {
  require_state
  local mode cmd; mode="$(jq_get verify_mode)"; cmd="$(jq_get verify_cmd)"
  if [ "$mode" = machine ] && [ -n "$cmd" ]; then
    echo "+ $cmd"
    local out ec
    out="$(bash -c "$cmd" 2>&1)"; ec=$?
    printf '%s\n' "$out" | tail -n 20
    write_state "last_verify_exit=@$ec" updated_at="$(now_iso)"
    if [ "$ec" -eq 0 ]; then echo "VERIFY: PASS (exit 0)"; else echo "VERIFY: FAIL (exit $ec)"; fi
    return 0
  fi
  echo "Self-graded loop — no command to run."
  echo "Criterion: $(jq_get verification | python3 -c 'import json,sys;
try:
 d=json.load(sys.stdin); print((d.get("title") or "")+(" — "+d.get("detail") if d.get("detail") else ""))
except Exception: print("")')"
  echo "Inspect real evidence, then: loop.sh record \"<what you did>\" --evidence \"<proof>\" --decision continue|stop"
}

cmd_record() {
  require_state
  local action="" evidence="" vexit="" decision="continue"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --evidence)    evidence="$2"; shift 2 ;;
      --verify-exit) vexit="$2"; shift 2 ;;
      --decision)    decision="$2"; shift 2 ;;
      --*)           echo "Unknown flag: $1" >&2; exit 64 ;;
      *)             [ -z "$action" ] && action="$1" || action="$action $1"; shift ;;
    esac
  done
  [ -z "$action" ] && { echo "Usage: loop.sh record \"<action>\" [--evidence …] [--verify-exit N] [--decision continue|stop|blocked]" >&2; exit 64; }

  local it streak last; it="$(jq_get iteration)"; streak="$(jq_get no_progress_streak)"
  it=$(( ${it:-0} + 1 ))
  # Progress = an explicit pass this turn (vexit 0) or the stored last_verify_exit==0.
  last="${vexit:-$(jq_get last_verify_exit)}"
  if [ "$last" = "0" ]; then streak=0; else streak=$(( ${streak:-0} + 1 )); fi

  ledger_append "$it" "$action" "$evidence" "${vexit:-}" "$decision" ""
  write_state "iteration=@$it" "no_progress_streak=@$streak" updated_at="$(now_iso)"
  [ -n "$vexit" ] && write_state "last_verify_exit=@$vexit"
  echo "Recorded iteration $it (no-progress streak: $streak, decision: $decision)."
}

# Pure evaluator — prints `continue` or `stop:<reason>`; no state mutation.
eval_stop() {
  local target it maxit streak noprog
  target="$(jq_get stop | python3 -c 'import json,sys;print(json.load(sys.stdin).get("target_cmd","") or "")' 2>/dev/null)"
  it="$(jq_get iteration)"; it="${it:-0}"
  maxit="$(jq_get stop | python3 -c 'import json,sys;print(json.load(sys.stdin).get("max_iterations",10))' 2>/dev/null)"; maxit="${maxit:-10}"
  streak="$(jq_get no_progress_streak)"; streak="${streak:-0}"
  noprog="$(jq_get stop | python3 -c 'import json,sys;print(json.load(sys.stdin).get("no_progress_for",2))' 2>/dev/null)"; noprog="${noprog:-2}"
  if [ -n "$target" ] && bash -c "$target" >/dev/null 2>&1; then echo "stop:target"; return 0; fi
  if [ "$it" -ge "$maxit" ]; then echo "stop:max-iter"; return 0; fi
  if [ "$streak" -ge "$noprog" ]; then echo "stop:no-progress"; return 0; fi
  echo "continue"
}

cmd_check_stop() { require_state; eval_stop; }

cmd_continue() {
  require_state
  local d; d="$(eval_stop)"
  if [ "$d" != continue ]; then
    echo "STOP (${d#stop:}). Run the completion audit, then: loop.sh complete (or abort)."
    return 0
  fi
  cat <<EOF
NEXT CYCLE — iteration $(( $(jq_get iteration) + 1 )) of max $(jq_get stop | python3 -c 'import json,sys;print(json.load(sys.stdin).get("max_iterations",10))' 2>/dev/null).
Loop: $(jq_get title)
Do ONE bounded, reversible action toward:
$(jq_get prompt)
Then: loop.sh verify  →  loop.sh record "<action>" --evidence "<proof>" [--verify-exit N]  →  loop.sh check-stop
EOF
}

cmd_status() {
  require_state
  printf 'Loop: %s\n' "$(jq_get title)"
  printf 'Status: '; status_badge "$(jq_get status)"; printf '\n'
  printf 'Verify: %s' "$(jq_get verify_mode)"; [ "$(jq_get verify_mode)" = machine ] && printf '  (%s)' "$(jq_get verify_cmd)"; printf '\n'
  printf 'Iteration: %s   No-progress streak: %s   Last verify exit: %s\n' "$(jq_get iteration)" "$(jq_get no_progress_streak)" "$(jq_get last_verify_exit)"
  printf 'Stop: %s\n' "$(jq_get stop)"
  local bd; bd="$(jq_get bd_issue_id)"; [ -n "$bd" ] && printf 'Beads: %s\n' "$bd"
  printf 'Next: '; eval_stop
}

cmd_show()   { require_state; cat "$(state_file)"; }
cmd_ledger() { require_state; local lf; lf="$(ledger_file)"; [ -f "$lf" ] && cat "$lf" || echo "(empty ledger)"; }

cmd_list() {
  local n=0
  shopt -s nullglob
  for sf in "$STATE_DIR"/*.json; do
    [ -f "$sf" ] || continue
    python3 - "$sf" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(f"{d.get('status','?'):9} {d.get('title','?')[:70]}  [{d.get('cwd','?')}]")
except Exception: pass
PY
    n=$((n+1))
  done
  [ "$n" -eq 0 ] && echo "No loops on record."
}

cmd_pause()  { require_state; [ "$(jq_get status)" = complete ] && { echo "Already complete." >&2; exit 2; }; write_state status=paused updated_at="$(now_iso)"; bd_note "Loop paused."; echo "Loop paused. Stop-gate quiet until resume."; }
cmd_resume() { require_state; [ "$(jq_get status)" = complete ] && { echo "Completed loop; start a new one." >&2; exit 2; }; write_state status=active updated_at="$(now_iso)"; bd_note "Loop resumed."; echo "Loop resumed."; }

cmd_abort() {
  require_state
  ledger_append "$(jq_get iteration)" "aborted" "" "" "abort" "$*"
  write_state status=aborted updated_at="$(now_iso)"
  bd_del
  echo "Loop aborted. State kept for the record; bd issue marked deleted. (\`loop.sh ledger\` to review, or rm the state file.)"
}

cmd_complete() {
  require_state
  local cur; cur="$(jq_get status)"
  [ "$cur" = complete ] && { echo "Already complete."; exit 0; }
  local mode last stop_d evidence="" force=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --evidence) evidence="$2"; shift 2 ;;
      --force)    force=1; shift ;;
      *)          shift ;;
    esac
  done
  mode="$(jq_get verify_mode)"; last="$(jq_get last_verify_exit)"; stop_d="$(eval_stop)"

  if [ "$force" -ne 1 ]; then
    if [ "$mode" = machine ]; then
      if [ "$last" != "0" ] && [ "$stop_d" = continue ]; then
        echo "Refusing to complete: last verify exit is '${last:-none}' (need 0) and no stop predicate fired." >&2
        echo "Run \`loop.sh verify\` until it passes, or let a stop predicate fire, or use --force with a written reason." >&2
        exit 2
      fi
    else
      if [ -z "$evidence" ] && [ "$stop_d" = continue ]; then
        echo "Self-graded loop: \`complete\` requires --evidence \"<proof the criterion is met>\" (or a stop predicate)." >&2
        echo "Criterion: $(jq_get verification)" >&2
        exit 2
      fi
    fi
  fi

  ledger_append "$(jq_get iteration)" "complete" "$evidence" "$last" "${stop_d}" "$([ "$force" -eq 1 ] && echo forced)"
  write_state status=complete updated_at="$(now_iso)" completed_at="$(now_iso)"
  bd_close "Loop complete (iter $(jq_get iteration), verify_exit=${last:-na}, ${stop_d})."
  echo "Loop complete. ($(jq_get iteration) iterations; ${stop_d})"
  [ -n "$evidence" ] && echo "Evidence: $evidence"
}

cmd_help() {
  cat <<'EOF'
loop.sh — run a Loop Library loop as a bounded, verifiable, ledgered cycle.

  start <slug> [--prompt "…"|--file f.json] [--verify "<cmd>"]
        [--stop "max-iter=N,no-progress=M,target=<cmd>"] [--title "…"]
  verify                 Run the verify cmd (machine) / print criterion (self)
  record "<action>" [--evidence "…"] [--verify-exit N] [--decision D]
  check-stop             Print `continue` or `stop:<reason>`
  continue               Print the next-cycle steering block
  status | show | list | ledger
  pause | resume | abort ["reason"]
  complete [--evidence "…"] [--force]

State:  ~/.claude/state/loop/<sha-of-cwd>.json   Ledger: same path .jsonl
Hooks:  ~/.claude/skills/hooks/loop-injector.sh (UserPromptSubmit)
        ~/.claude/skills/hooks/loop-stop-gate.sh (Stop; cap LOOP_STOP_MAX, 0=off)
EOF
}

sub="${1:-help}"; shift || true
case "$sub" in
  start)            cmd_start "$@" ;;
  verify)           cmd_verify ;;
  record)           cmd_record "$@" ;;
  check-stop)       cmd_check_stop ;;
  continue|next)    cmd_continue ;;
  status)           cmd_status ;;
  show)             cmd_show ;;
  list|ls)          cmd_list ;;
  ledger)           cmd_ledger ;;
  pause)            cmd_pause ;;
  resume)           cmd_resume ;;
  abort)            cmd_abort "$@" ;;
  complete)         cmd_complete "$@" ;;
  help|-h|--help)   cmd_help ;;
  *) echo "Unknown subcommand: $sub" >&2; cmd_help >&2; exit 64 ;;
esac
