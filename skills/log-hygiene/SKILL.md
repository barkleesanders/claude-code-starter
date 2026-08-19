---
name: log-hygiene
user-invocable: true
description: "Proactive log/observability hygiene loop. Assesses recent logs from a real source (wrangler tail, CF Logpush, cron/watcher logfiles, D1), clusters errors, then improves ambiguous error messages, downgrades noise (never deletes), and adds debugging attributes at silent failure points. Runs manually or as a scheduled cron (the Phase-2 Hermes job). Triggers: 'assess the logs', 'clean up the logs', 'improve log output', 'log hygiene', 'why are these errors so vague', '/log-hygiene'."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebFetch
model: inherit
---

# /log-hygiene — Log & Observability Hygiene Loop

Turns a window of real logs into concrete code improvements: ambiguous errors → actionable, noise → quieter (recoverable), silent gaps → instrumented. The compounding investment that makes every *future* debugging session in the same subsystem faster.

**Read `~/.claude/skills/shared/observability-instrumentation.md` first** — it is the standard this skill enforces (boundary-logging, the 4-part error-message design, the downgrade-never-delete guardrail, the stack's log sources).

## Usage

```
/log-hygiene [source] [--repo <path>] [--hours N] [--apply|--report-only]
```

- `source` — a worker name (`wrangler tail`), a logfile/dir path, or "ask" to pick from the stack's known sources.
- Default window: last 24h. Default mode: `--report-only` (propose edits, don't apply) when run interactively; `--report-only` is also the safe default for the first cron run.

## Examples

- `/log-hygiene improvebayarea --hours 24` — assess the last day of a Worker's logs.
- `/log-hygiene ~/.claude/logs/worktree-autopush.log` — assess a local cron logfile.
- `/log-hygiene --repo ~/AIVA-Frontend --apply` — assess + apply safe log improvements in a repo.

## The loop

1. **Ingest (ground truth, never fabricated).** Pull last-N hours from the real source — `npx wrangler tail <worker> --format json` (let it collect, or read retained Workers Logs / Logpush), or `Read`/`grep` the logfile, or the cron's own log. **Count from the source; never estimate volume.** If the source is empty or unreachable, say so and stop — do not invent log lines.
2. **Cluster.** Group by stable event name / normalized message (strip ids, timestamps, numbers). Produce a frequency table: `count × message × first/last seen`. Rank by `frequency × ambiguity` (a vague error firing 200×/day is the top target).
3. **Triage each top cluster** into exactly one bucket:
   - **Ambiguous error** → locate the emit site (`grep` the message), rewrite to the 4-part standard (what was attempted + actual values + likely cause/branch + disambiguation). Split if two root causes share one string.
   - **Noise** (high-volume, no signal) → **downgrade its level** (`info`→`debug`), never delete. Recoverable by raising log level.
   - **Silent gap** (you can tell a failure happened but not *why*, or a code path has no log at all) → add a boundary log / the one attribute that would name the cause.
4. **Report.** Emit findings: per cluster, the count, the verdict, and the exact before→after. (Per the HTML-default rule, a multi-cluster assessment is a good candidate for an HTML report to `~/Downloads/log-hygiene-<source>-YYYY-MM-DD.html`; a short one-or-two-finding result can stay inline / be a code diff.)
5. **Apply (only if `--apply`).** Make the in-scope edits, rebuild (`tsc --noEmit` / `wrangler deploy --dry-run` / project build), confirm exit 0. Open a PR or commit per the repo's workflow — **never deploy** (that's `/ship`).

## Hard rules

- **Never delete a log line to reduce noise — downgrade its level.** A line that looks like noise may be load-bearing for a different debug path. Deleting is only for genuinely wrong (logs a stale/incorrect value) or verbatim-duplicate lines, and must be called out explicitly in the report.
- **Never fabricate log volume, error counts, or messages.** Every number in the report cites the source (file:line of the grep, the tail capture, the row count). If you didn't see it in the source, it doesn't go in the report. (Ground-Truth + No-Lie standard.)
- **Never log secrets/PII/tokens.** When adding/rewriting a log line, redact (`tok_***`, last-4 only). Flag any *existing* line that leaks them as a finding.
- **Stay in scope.** Improve observability; don't refactor business logic. If a cluster reveals an actual bug (not just a vague message), file a beads issue (`bd create`) and note it — don't silently fix unrelated logic under cover of "log hygiene." (Exception: a one-line obvious fix at the same site is fine; say so.)
- **No deploy.** This skill prepares edits; deployment is `/ship`.

## Cron mode (the Phase-2 Hermes job — `bd: HOME-w1xq`)

When run headless on a schedule (Mac mini, host `mac-mini`):
- Default to `--report-only`; route the report by **actor** per the cron-output-routing rule — findings needing a human decision → Asana; auto-applicable log improvements → a PR or a beads issue, not a silent push.
- LLM assessment (clustering, rewriting messages) is the openclaw-cron part; pure log *tailing/rotation* should be a systemd timer, not agent tokens (openclaw-native-first rule).
- Idempotent: dedupe findings against the prior run so the same vague-error cluster isn't re-filed every cycle.

## Why this exists

Origin (2026-06-17, user meta-practice): the user's standing prompt — "assess logs from the last 24h, improve output for ambiguous errors, clean up superfluous entries, add attributes to help future debugging" — is a high-leverage recurring task. It belongs as a deliberate, schedulable loop (not buried inside reactive debugging), with the downgrade-never-delete and no-fabrication guardrails baked in so it's safe to run unattended. The `/carmack` and `/debug` skills carry the *reactive* half (instrument-on-build, instrument-on-fix); this skill is the *proactive* half.
