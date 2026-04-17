# Blind-Spot Checklist (Infra / Config Work)

When fixing infra, configs, plugin settings, or anything touching a running service, run these checks before declaring done. Each pattern below was learned from a real incident.

## 1. Config-schema validation BEFORE restart

Adding a new field to a JSON config and restarting the service can restart-loop if the field isn't in the schema. Always:

```bash
# dry-run validate if the tool supports it
openclaw doctor 2>&1 | grep -i 'invalid\|unknown'
# then restart
systemctl restart <service>
sleep 5 && systemctl is-active <service>
```

**Real incident (2026-04-17):** Added `maxOutputTokens: 8000` to featherless model configs. Schema rejected it with "Unrecognized key", gateway restart-looped. Had to revert.

## 2. Self-upgrade failures (OpenClaw pattern)

**NEVER run `openclaw update` from a chat session** — it kills its own process mid-install, destroys `/usr/bin/openclaw` symlink, orphans chrome processes, and aborts mid-telegram-bundle-rebuild.

Safe pattern: run it as a separate shell session the user controls, or via a standalone script that stops the gateway first.

**Real incident (2026-04-17):** `openclaw update --yes --channel stable` broke telegram channel bundle, left openclaw command gone for ~90s during restart cycle.

## 3. "Gateway started" is NOT "gateway working"

A ready-log line only proves the process booted. Must verify with real traffic:

```bash
openclaw agent --agent main --message 'test' --json --timeout 60 | grep -i 'error\|usage'
# check token usage actually changed
```

**Real incident (2026-04-17):** LCM plugin loaded fine (`threshold=0.75, mode=deferred`), but compaction wasn't actually reducing tokens — summaries were empty stubs. Only real traffic revealed this.

## 4. Compaction telemetry — always check tokensAfter

When testing a summarizer, look at the telemetry row, not just "compaction event fired":

- `tokens_before`: should be > threshold
- `tokens_after`: should be < `tokens_before` — **if null, compaction isn't actually compressing**
- `summary_len`: high is fine, but read the summary — boilerplate template ("No prior history. None.") means the summarizer isn't being given real content

## 5. Adjacent systems that can break

When changing config A, check adjacent systems B/C/D:

| Changed | Could Break |
|---------|-------------|
| Model config | Cron jobs using that model |
| Plugin config | Other plugins depending on its output |
| Channel config | Bot bundles, sidecars |
| Binary version | Symlinks, global npm/cargo bins |
| Context window | Compaction math downstream |

**Real incident (2026-04-17):** Bumped `contextWindow` from 32768 to 48000 without checking if `maxOutputTokens`, `reserveTokensFloor`, or cron job prompt budgets assumed the smaller number.

## 6. Guardrail alerts vs. guardrail enforcement

"Audit script detected X" ≠ "X was removed". Read the actual script:

```bash
# check if it's purely alerting or also cleaning
grep -E 'rm|unlink|delete|mv.*bak' <guardrail-script>
```

**Real incident (2026-04-17):** `APPROVED_AGENTS` guardrail detected ghost `voice` agent dir at 10:54:04 and wrote `GUARDRAIL_ALERT` file — but never removed the dir. Kept alerting every 10min.

## 7. Cron failure status ≠ context overflow

"Failing cron" can look like context overflow but often isn't. Pull the actual error:

```bash
openclaw cron runs --id <id> --limit 2 | grep -E 'error|status'
```

**Real incident (2026-04-17):** 3 crons marked `status=error`. Assumed compaction problem. Real cause: `⚠️ API rate limit reached` from the model provider.

## 8. Lossless-claw deferred mode is a no-op

Default `proactiveThresholdCompactionMode: "deferred"` means LCM defers compaction to background — never actually shrinks the context the next turn sees. For agents hitting context overflow every turn, set `"inline"`:

```json
"plugins": {
  "entries": {
    "lossless-claw": {
      "config": { "proactiveThresholdCompactionMode": "inline" }
    }
  }
}
```

Verify with a turn showing `input >> context_window` → `input sent to model < context_window`.

## 9. System prompt size budget

Before tuning compaction, measure the system prompt. If the system prompt alone exceeds the model's context, no amount of compaction helps. Check:

```bash
# from a real turn's JSON output
agentMeta.usage.input  # turn 1 input == approx system prompt size
```

Plugins (browser, exa, active-memory, etc.) each add to system prompt. Disable unused ones before fighting compaction.

## 10. Measurement-first rule (MANDATORY for any config/removal decision)

**NEVER remove, disable, or resize something because you assume it's "unused" or "too big." Measure first.** Saying "disable unused plugins" without reading tool-use events is a guess, not a fix.

### Pattern — measure BEFORE touching config

| Decision | Measurement to run first |
|---|---|
| "Disable plugin X" | Grep session JSONL for `tool_use` / `toolCall` events naming X's tools over last 14 days |
| "System prompt is too big" | `openclaw agent --message 'size check' --json \| grep '"input"'` — record before/after each config change |
| "This skill isn't used" | Check `~/.claude/skill-usage.jsonl` or run `skill-usage-report.py` |
| "This command rotted" | `skill-drift-check.sh` — don't delete a reference without evidence |
| "This compaction knob turns left" | Read the plugin source: `grep -oE 'toKnobName[^}]+' /root/.openclaw/extensions/<plugin>/dist/*.js` to see the enum / direction |

### Real incident (2026-04-17)

Lowered `reserveTokensFloor` from 20000 → 12000 to "trigger compaction earlier." OpenClaw's own error message later said "set it to 20000 or higher." The knob turned the opposite direction of what I assumed. Fixed by measuring first next time.

Then proposed "disable browser + exa plugins (unused)." Tool-usage scan showed browser had 8 calls + exa had 13 calls in 14 days — both used. Only `anthropic` plugin (0 calls) was safe to disable. Saved 440 tokens per turn.

### Pre-decision checklist

Before committing to a config change:
1. What is the baseline number? (tokens, errors, latency — whatever the change claims to affect)
2. How will I re-measure the SAME number after the change?
3. If the number didn't improve, will I revert or double down?

If step 3 is "double down," you're about to make a mistake. Revert.

---

## 11. JSON config backups before every patch

```bash
cp <config>.json <config>.json.bak-$(date +%Y%m%d-%H%M%S)
```

Makes post-incident rollback trivial. Already a memory rule; include it in every infra fix commit.
