---
name: debug
user-invocable: true
description: "Quick debugging patterns and known production failure traps. Reference guide for common issues."
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
model: inherit
---

# /debug - Debugging Quick Reference

Fast reference for known production failure patterns. For deep debugging, use `/carmack`.

## Usage

```
/debug [pattern name or symptom]
```

## Examples

- `/debug catch-all` -- Catch-all error handling masking root cause
- `/debug react undefined` -- React "X is not defined" scope bug
- `/debug silent startup` -- React silently fails to mount
- `/debug auth failed` -- Generic auth error hiding real cause
- `/debug broken icons` -- Third-party icons/images missing (CSP blocking)
- `/debug text overflow` -- Text escaping card boundaries on mobile
- `/debug stale data` -- Admin changes not visible to users
- `/debug deploy logout` -- Users logged out after every deploy

---

## Pattern Routing

Match the user's symptom to the right reference file, then load ONLY that file.

| Symptom / Keyword | Pattern | Reference File |
|--------------------|---------|----------------|
| catch-all, generic error, wrong status code, misleading error | Catch-All Error Masking (#1) | `error-handling-patterns.md` |
| CI false positive, grep wrong, CI still fails | CI False Positives (#11) | `error-handling-patterns.md` |
| admin 403, requireAdmin, metadata-only | Admin Auth Missing DB Fallback (#14) | `error-handling-patterns.md` |
| admin 500 instead of 403 | Admin Route Wrong Status | `error-handling-patterns.md` |
| react undefined, scope bug, not defined | React Scope Bug (#2) | `react-patterns.md` |
| silent startup, blank page, no console errors, module-level throw | Silent React Startup (#3) | `react-patterns.md` |
| useEffect, renders twice, state lags, derived state | useEffect Abuse (#15) | `react-patterns.md` |
| localStorage, preference lost, resets on refresh | Preference Lost on Reload (#13) | `react-patterns.md` |
| double click, duplicate API call, async button | Async Button Double-Click | `react-patterns.md` |
| auth guard, unauthenticated error, no redirect | Missing Frontend Auth Guard | `react-patterns.md` |
| text overflow, min-w-0, flex escape, card boundary | Text Overflow Flex+Grid (#12) | `css-layout-patterns.md` |
| grid mobile, grid-cols, responsive breakpoint | Fixed Grid Breaks Mobile | `css-layout-patterns.md` |
| iOS Safari, blank iPhone, PDF iframe, vh units | iOS Safari Rendering | `css-layout-patterns.md` |
| og image, twitter card, social cache, stale card | Social Card Cache (#5) | `csp-cache-patterns.md` |
| CSP, embed blank, frame-src, img-src, broken icons | CSP Blocking (#9) | `csp-cache-patterns.md` |
| www redirect, cookies lost, auth break | WWW Redirect Auth Break (#4) | `csp-cache-patterns.md` |
| deploy logout, chunk hash, preloadError | Deploy Logs Users Out | `csp-cache-patterns.md` |
| stale version, failed deploy, CF Pages | CF Pages Stale Deploy | `csp-cache-patterns.md` |
| terraform destroy, infra deleted, catastrophic | AI Agent Destroys Infra (#6) | `infrastructure-patterns.md` |
| rust clippy, cross-platform, cfg, unused_mut | Rust Cross-Platform Lint (#7) | `infrastructure-patterns.md` |
| homebrew, keg-only, launchd, cron PATH | Homebrew Keg-Only PATH (#8) | `infrastructure-patterns.md` |
| serde, deny_unknown_fields, config crash | Serde Config Crash (#10) | `infrastructure-patterns.md` |
| innerHTML, XSS, dangerouslySetInnerHTML | XSS via innerHTML | `infrastructure-patterns.md` |
| JSON-LD, script breakout | JSON-LD Breakout | `infrastructure-patterns.md` |
| stale data, admin user sync, visibilitychange | Data Stale Admin/User (#16) | `debugging-discipline.md` |
| systematic, 4-phase, root cause, discipline | Debugging Discipline | `debugging-discipline.md` |
| lint, biome, npm audit, security cleanup | Lint & Security Cleanup | `debugging-discipline.md` |

All reference files are in `~/.claude/skills/debug/references/`.

---

## Reference Files Index

| File | Content |
|------|---------|
| `error-handling-patterns.md` | Catch-all masking (#1), CI false positives (#11), admin auth DB fallback (#14), admin 500 vs 403 |
| `react-patterns.md` | Scope bug (#2), silent startup (#3), useEffect abuse (#15), localStorage persistence (#13), async double-click, missing auth guard |
| `css-layout-patterns.md` | Text overflow flex+grid (#12), fixed grid mobile, iOS Safari rendering (PDF, vh, fixed) |
| `csp-cache-patterns.md` | Social card cache (#5), CSP multi-layer blocking (#9), www redirect (#4), deploy chunk invalidation, CF Pages stale deploy |
| `infrastructure-patterns.md` | Infra destruction (#6), Rust cross-platform lint (#7), Homebrew keg-only (#8), serde config crash (#10), XSS innerHTML, JSON-LD breakout |
| `debugging-discipline.md` | 4-phase workflow, diagnostic checklist (20 items), lint/security cleanup, data stale admin/user (#16) |
| `~/.claude/skills/shared/ant-verification-protocol.md` | **Ant-level quality gates**: OWASP sweep, truthfulness protocol, closed-loop verification |

---

## Quick Diagnostic Checklist

When debugging any production error, check in order:

1. Is the error message accurate? (catch-all masking?)
2. Check runtime logs: `wrangler tail` or Cloudflare dashboard
3. Reproduce locally with same endpoint + token
4. Check external services (Clerk/Stripe/DB responding?)
5. Check env vars in deployment environment
6. Check www redirect (losing cookies?)
7. Check third-party IDs (stale template/product IDs?)
8. Check CSP (all six directives for embeds?)
9. Text overflow on mobile? (`min-w-0` missing, `grid-cols-2` without `sm:`)
10. Preference not persisting? (localStorage writer without App.tsx reader)

For the full 20-item checklist, load `debugging-discipline.md`.

---

## Hard Rules

### Deployment Prohibition (MANDATORY)

NEVER deploy to production. NEVER run `wrangler deploy`, `npm run deploy`, `vercel deploy --prod`, or any production deployment command. If a fix is implemented and committed, STOP and tell the user: "Fix is committed and ready. Run `/ship` to deploy to production." Wait for explicit user approval. Do NOT invoke `/ship` autonomously.

### Test Safety (CRITICAL)

Vitest fork workers leak ~5GB memory each when they hang:
1. ALWAYS wrap test commands: `timeout 120 npx vitest run src/specific/test.ts 2>&1`
2. NEVER run full test suite (`npm test`, `npx vitest run` with no args)
3. Maximum 3 test runs per investigation phase
4. Clean up: `pgrep -f vitest | xargs kill 2>/dev/null`

### Infrastructure Safety

- NEVER execute `terraform destroy`, `terraform apply -auto-approve`, `DROP TABLE/DATABASE`, or cloud CLI delete/terminate commands
- NEVER modify .tfstate files
- ALWAYS show `terraform plan` output and get approval before any `apply`

---

## Instructions

When this skill is invoked:

1. Parse the user's symptom or pattern name against the **Pattern Routing** table above
2. Read ONLY the matching reference file from `~/.claude/skills/debug/references/`
3. **Load `~/.claude/skills/shared/ant-verification-protocol.md`** and apply:
   - Truthfulness Protocol (Section 2): never guess root causes — gather evidence first
   - Closed-Loop Verification (Section 3): reproduce failure BEFORE and AFTER fix
   - Security Review Gate (Section 1): if symptom touches auth/input/data handling
4. Show the relevant pattern section to the user
5. If the symptom doesn't match any pattern, show the **Quick Diagnostic Checklist** and recommend `/carmack` for deep investigation
6. If a fix is needed, follow the 4-phase debugging discipline (load `debugging-discipline.md`)
7. After any fix: run lint + security cleanup (load `debugging-discipline.md` for the commands)
8. **Ant verification**: never say "fixed" without running the verification checklist from Section 2

```
Load the matching reference file and show the relevant pattern.
If the issue needs deep investigation beyond known patterns, recommend /carmack.
CRITICAL: Do NOT deploy to production. Do NOT run wrangler deploy, npm run deploy, vercel deploy --prod, or any production deployment command.
```
