#!/usr/bin/env bash
# Remote OpenClaw diagnostic — runs from Mac, queries VPS bsclaudebot.
# Triggers: any task that touches VPS, openclaw, bsclaudebot.
# Captures native diagnostic output + extracts remediation hints locally,
# so the agent on Mac sees the same "native-guidance-first" signals the
# VPS scanner sees.
#
# Usage:
#   openclaw-remote-doctor.sh                 # full scan (doctor + tool-usage + errors)
#   openclaw-remote-doctor.sh doctor          # doctor only
#   openclaw-remote-doctor.sh tokens          # measure main-agent turn-1 tokens
#   openclaw-remote-doctor.sh tools [days]    # tool-usage scan (default 14 days)
#   openclaw-remote-doctor.sh errors [days]   # cron error scan (default 1 day)

set -euo pipefail

VPS="root@<YOUR_VPS_IP>"
SSH_OPTS="-p 2222 -o ConnectTimeout=10 -o ServerAliveInterval=30"

mode="${1:-all}"
shift || true

run_remote() {
  ssh $SSH_OPTS "$VPS" "$@" 2>&1 | grep -v 'Config was' || true
}

case "$mode" in
  doctor)
    echo "=== openclaw doctor (VPS) ==="
    run_remote "openclaw doctor"
    ;;
  tokens)
    echo "=== main-agent turn-1 tokens (VPS) ==="
    run_remote "openclaw agent --agent main --message 'size check' --json --timeout 60" | \
      python3 -c "
import json, sys, re
raw = sys.stdin.read()
i = raw.find('{')
if i < 0: print('no JSON in response'); sys.exit()
j = json.loads(raw[i:])
def walk(o, p=''):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'usage':
                print(f'{p}.usage = {json.dumps(v)}')
            walk(v, f'{p}.{k}')
    elif isinstance(o, list):
        for i, v in enumerate(o): walk(v, f'{p}[{i}]')
walk(j)
"
    ;;
  tools)
    days="${1:-14}"
    echo "=== VPS tool-usage scan (last $days days) ==="
    run_remote "/root/.openclaw/scripts/tool-usage-scan.sh $days"
    ;;
  errors)
    days="${1:-1}"
    echo "=== VPS cron errors (last $days day[s]) ==="
    run_remote "openclaw cron list | grep -v 'Config was' | grep error"
    ;;
  all|*)
    echo "################## VPS OpenClaw snapshot ##################"
    echo
    echo "--- gateway status ---"
    run_remote "systemctl is-active openclaw-gateway"
    echo
    echo "--- openclaw doctor (native diagnostic) ---"
    run_remote "openclaw doctor" | head -80
    echo
    echo "--- main-agent turn-1 tokens ---"
    run_remote "openclaw agent --agent main --message 'snapshot' --json --timeout 60" | \
      python3 -c "
import json, sys
raw = sys.stdin.read()
i = raw.find('{')
if i >= 0:
    j = json.loads(raw[i:])
    def walk(o, p=''):
        if isinstance(o, dict):
            for k, v in o.items():
                if k in ('usage', 'stopReason'):
                    print(f'{p}.{k} = {json.dumps(v)}')
                walk(v, f'{p}.{k}')
        elif isinstance(o, list):
            for i, v in enumerate(o): walk(v, f'{p}[{i}]')
    walk(j)
" 2>/dev/null || echo "(agent call failed)"
    echo
    echo "--- tool usage (14d) ---"
    run_remote "/root/.openclaw/scripts/tool-usage-scan.sh 14"
    echo
    echo "--- latest self-improve log ---"
    run_remote "tail -15 /root/.openclaw/logs/self-improve.log"
    echo
    echo "--- pending-review file on VPS ---"
    run_remote "[ -f /root/.openclaw/improvement-pending.md ] && cat /root/.openclaw/improvement-pending.md || echo '(no pending review)'"
    echo
    echo "################## extracted remediation hints ##################"
    # Extract hints from doctor output locally so the agent sees them inline
    run_remote "cat /root/.openclaw/logs/doctor-latest.txt 2>/dev/null" | \
      python3 -c "
import re, sys
text = sys.stdin.read()
PATTERNS = [
    r'(?:set|setting)\s+([\`\\'\"]?[a-zA-Z][a-zA-Z0-9_.]*[\`\\'\"]?)\s+(?:to|=)\s+([0-9a-zA-Z.\\\"_-]+)',
    r'Fix:\s*(?:run\s+)?[\`\\'\"]?([^\`\\'\"\n]{3,120})[\`\\'\"]?',
    r'Run:\s*[\`\\'\"]?([^\`\\'\"\n]{3,120})[\`\\'\"]?',
    r'(?:try|run|use)\s+(?:running\s+)?[\`\\'\"]?([^\`\\'\"\n]{3,120})[\`\\'\"]?',
    r'Did you mean\s+([\`\\'\"]?[a-zA-Z][a-zA-Z0-9_.-]*[\`\\'\"]?)',
    r'See\s+(https?://[^\s]+)',
]
hints = []
for pat in PATTERNS:
    for m in re.finditer(pat, text, re.IGNORECASE):
        full = m.group(0)[:140].strip()
        if full not in hints:
            hints.append(full)
if hints:
    for h in hints[:15]:
        print(f'  🧭 {h}')
else:
    print('  (no actionable hints found)')
" 2>/dev/null
    echo
    echo "####################################################"
    echo "Apply the 🧭 hints FIRST before inventing fixes."
    ;;
esac
