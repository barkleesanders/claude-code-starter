# Codex Integration

Use the Codex plugin for structured code review, adversarial security analysis, and rescue escalation. These replace the old `codex exec` file pipe.

## Codex Review (Quality Gate)

Run `/codex:review` for structured review with JSON findings (severity, file, line, confidence, recommendation).

**When carmack triggers it:**
- **Phase 4 (Implementation & Verification):** Before presenting a fix to the user, run:
  `/codex:review --wait --scope working-tree`
  Present findings alongside the fix. Never auto-apply Codex recommendations.
- **Ralph Mode (after story commit):** After quality checks pass, offer:
  `/codex:review --background --scope working-tree`
  Continue to next story; check `/codex:status` before marking the feature complete.

**Interpreting results:**
- `verdict: "approve"` -- No material issues. Proceed.
- `verdict: "needs-attention"` -- Present all findings to user by severity. Do NOT auto-fix.
- High-confidence findings (>0.8) on critical/high severity = strong signal to address before shipping.

## Adversarial Review (Security-Sensitive Changes)

Run `/codex:adversarial-review` when changes touch security-sensitive code. Always optional, never mandatory.

**Suggest adversarial review when changes touch:**
- Auth, permissions, tenant isolation
- Payment processing, billing logic
- Data deletion, migrations, schema changes
- Rate limiting, CORS, API keys
- Session handling, token validation

**Example:** `/codex:adversarial-review --background focus: auth bypass via publicMetadata race condition`

**Phase 0b integration:** After lint/security scan passes and before marking task complete, if changed files match security-sensitive patterns above, suggest running adversarial review.

## Codex Rescue (Escalation)

Use `/codex:rescue` when carmack is stuck. Delegates substantial work to a Codex subagent.

**Escalation triggers (offer, never auto-trigger):**
1. **3-failure limit:** After 3 failed fix attempts, offer: "Delegate to Codex rescue for independent investigation?"
2. **Stuck in Phase 1:** No root cause after extended investigation. Offer rescue with gathered evidence.

**Example:** `/codex:rescue Investigate intermittent 500 on /api/auth -- tried X, Y, Z. Evidence: [logs]. Root cause unknown.`

Codex rescue is write-capable by default. Review any changes it makes before accepting.
Use `--resume` to continue a previous rescue session, `--fresh` to start clean.

## Background Job Management

- `/codex:status` -- Check active/recent Codex jobs for this repo
- `/codex:result [job-id]` -- Get full output for a finished job (includes session ID for `codex resume`)
- `/codex:cancel [job-id]` -- Cancel an active job

## Review Gate (Optional Safety Net)

Enable stop-time review gate to have Codex automatically review the last turn before session end:
`/codex:setup --enable-review-gate`
Warning: Can create long-running Claude/Codex loops. Only enable when actively monitoring.
