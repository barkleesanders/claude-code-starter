# Session Archaeology & Tooling Gaps

Patterns learned from tasks where I wasted tool calls discovering things that should have been documented.

## 1. Safe JSON config mutation — use `json-patch.sh`

When editing a JSON config owned by a running service, do NOT hand-roll `python3 -c` heredocs. Use the helper:

```bash
~/.claude/skills/carmack/tools/json-patch.sh <config-path> '<jq-expression>' [--validate-cmd "<cmd>"] [--restart "<svc>"]
```

It auto-backs up to `<path>.bak-<timestamp>`, applies the patch via `jq`, validates JSON, optionally runs a schema-validate command, optionally restarts a systemd service, and auto-rolls back if validation fails.

**Real incident (2026-04-17):** added `maxOutputTokens` via inline python patch, hit schema-rejection restart loop. The helper would have validated and reverted automatically.

## 2. Sleep / wait patterns (CRITICAL — harness blocks shortcuts)

- **NEVER** chain `sleep N && <cmd>` for waits > ~30s — the harness blocks it
- For "wait until X is done": use `run_in_background: true` on the long command, then `TaskOutput` with `block: true`
- For "notify me when a condition flips": use `Monitor` with an `until-loop` command (streams events as notifications)
- For a fixed short pause after a restart: `sleep 5 && <check>` is fine (under the threshold)

## 3. OpenClaw filesystem map (VPS)

When debugging OpenClaw, know where state lives before grepping:

| State | Path | Notes |
|-------|------|-------|
| Main config | `/root/.openclaw/openclaw.json` | ALWAYS backup before patching |
| Agent approval list | `/root/.openclaw/APPROVED_AGENTS` | One name per line |
| Agent sessions | `/root/.openclaw/agents/<id>/sessions/*.jsonl` | Event-sourced log (type=message/compaction/custom/etc) |
| Session checkpoints | same dir, `*.checkpoint.<uuid>.jsonl` | Snapshots at compaction boundaries |
| LCM database | `/root/.openclaw/lcm.db` | SQLite — only populated if `proactiveThresholdCompactionMode=inline` |
| Cron definitions | `/root/.openclaw/cron/jobs.json` | NOT in openclaw.json |
| Cron run history | `openclaw cron runs --id <uuid> --limit N` | JSON with usage/errors |
| Live log | `/tmp/openclaw/openclaw-YYYY-MM-DD.log` | JSONL, newest entries at bottom |
| Systemd logs | `journalctl -u openclaw-gateway` | Cleaner than tmp log for startup/errors |
| Guardrail alerts | `/root/.openclaw/GUARDRAIL_ALERT` | Written by audit scripts — read tail for recent violations |
| Plugin source (inspect) | `/root/.openclaw/extensions/<plugin>/dist/*.js` | Grep compiled JS for enum values |

## 4. Finding plugin enum values when docs are thin

Plugins often accept string enums for config keys, but those values aren't listed in `plugins inspect`. Pattern:

```bash
# Find all uses of the config key in compiled plugin JS
grep -oE 'proactiveThresholdCompactionMode[^,;"}]{0,80}' ~/.openclaw/extensions/lossless-claw/dist/*.js | sort -u

# Find the parser function (usually named toXxx or parseXxx)
grep -oE 'toProactiveThresholdCompactionMode[^}]{0,400}' ~/.openclaw/extensions/lossless-claw/dist/*.js | head -2
# Look for `normalized==="foo"||normalized==="bar"` — those are the valid values
```

General form: `grep -oE '<KeyName>[^,;"}]{0,80}'` then `grep -oE 'to<KeyName>[^}]{0,400}'`.

## 5. Session event type map (JSONL archaeology)

An OpenClaw session JSONL file contains these event types (from a real 194-event session):

| type | Meaning | Keys to inspect |
|------|---------|----------------|
| `session` | Session header | id, model, createdAt |
| `model_change` | Model switched mid-session | from, to |
| `thinking_level_change` | Thinking level change | level |
| `message` | User / assistant / toolResult | role, content (role-specific shape) |
| `compaction` | Compaction boundary | tokensBefore, tokensAfter, summary, reason |
| `custom` | Plugin-emitted | plugin, payload |

Quick inventory script:

```bash
python3 -c "
import json, collections
c = collections.Counter()
for line in open('/path/session.jsonl'):
    try: c[json.loads(line).get('type','?')] += 1
    except: pass
print(dict(c))
"
```

## 6. Compaction health diagnostics (3-query smoke test)

```bash
# 1) Are compactions actually reducing tokens?
python3 -c "
import json
tb=ta=0; n=0
for l in open('/path/session.jsonl'):
    try:
        d=json.loads(l)
        if d.get('type')=='compaction':
            n+=1; tb+=d.get('tokensBefore',0) or 0; ta+=(d.get('tokensAfter') or 0)
    except: pass
print(f'{n} compactions, avg before={tb//max(n,1)}, avg after={ta//max(n,1)} ({\"OK\" if ta<tb else \"NO-OP — check LCM mode\"})')
"

# 2) Is LCM in the right mode?
journalctl -u openclaw-gateway --since '5 minutes ago' --no-pager | grep -i 'proactiveThresholdCompactionMode'
# Should say 'mode=inline' after config fix; 'mode=deferred' means compaction boundary writes only (no actual shrinking)

# 3) Does the next turn see compressed context?
openclaw agent --session-id <id> --message 'token check' --json 2>&1 | grep -oE '"input":[0-9]+,"output":[0-9]+,"total":[0-9]+'
# 'input' should be much smaller than the cumulative history tokens — if not, LCM isn't helping
```

## 7. Auto-load relevant memory entries

Before any OpenClaw / infra fix, search `bd memories` for the tool name:

```bash
bd memories openclaw | head -20
bd memories lcm | head -10
bd memories <service-name> | head -10
```

This surfaces past incidents (self-upgrade failure, ghost agent guardrail, dual-service incident, etc.) without waiting to trip them again.

## 8. Service-restart observability trio

After any restart of a service you changed:

```bash
# 1. is it active?
systemctl is-active <svc>

# 2. any errors in the last 2 minutes?
journalctl -u <svc> --since '2 minutes ago' --no-pager | grep -iE 'error|fail|invalid|exit-code' | grep -v 'Config was last'

# 3. real-traffic test (service-specific)
<real-command-that-exercises-the-change> | grep -i 'error\|ok'
```

If any of the three fails, rollback the config change before moving on. Do NOT declare "done" on a config change if only step 1 passed.
