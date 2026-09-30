---
name: code
user-invocable: true
description: "Use when engineering work needs systematic debugging, implementation, or review. Apply a proportional fast lane for small local fixes and a deep lane only for genuinely complex or high-risk work; delegation is optional, never automatic."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - Skill
  - WebSearch
  - WebFetch
model: inherit
---

# /code - Engineering Agent

Universal engineering agent for building, debugging, fixing, reviewing, and shipping. It scales from a direct fast lane for small fixes to a systematic 5-phase investigation for complex work.

For missing DocuSeal defaults or signer-path mismatches, load
`~/.claude/skills/shared/docuseal-template-contract.md` before changing code.
Separate unique-submission payload state from live shared-template defaults, and
check whether multiple signing parties make the shared link ambiguous. AIVA's
HIPAA template must keep its shared link disabled. Hand any production template
mutation or deployment to `/ship`.

## Usage

```
/code [issue or feature description]
```

## Examples

- `/code intermittent 500 errors on /api/auth`
- `/code add email notification feature`
- `/code memory leak in background worker`
- `/code review this PR`
- `/code race condition causing data corruption`
- `/code build broke after dependency update`
- `/code research best AI tools last 30 days`

## Code Philosophy

1. Evidence over assumptions
2. Minimal reproduction cases
3. Debugger over print statements
4. Surgical fixes, not rewrites
5. Closed-loop verification
6. Know what NOT to build — use existing tools over custom implementations
7. Ship, measure, iterate — perfection is the enemy of validation

## Default Web Stack — Hono (2026-09-29)

When the work involves building a web frontend, UI, or HTTP API and the user
has not named a stack, build it in **Hono (TypeScript)**. This is the default,
not one option among equals.

- New web UIs/APIs: a Hono app (`hono` npm package). Server-rendered pages
  via `hono/jsx` + `c.html()` where the design calls for document-like pages.
- Every Hono-served HTML page MUST include the defensive CSS rules in
  `references/ux-patterns.md` ("Hono / Cloudflare Workers HTML — Text Overflow
  Prevention").
- Deviate only when the user explicitly names another framework, or the
  target repo already has an established stack. Adopting the repo's existing
  stack beats imposing Hono on it.

## Proportional Execution Lanes (MANDATORY — 2026-08-29)

**Code is a method, not a requirement to spawn another agent.** A user asking to “use Code” is asking for this method, not automatic delegation.

Choose one lane once the target and risk are known:

- **Fast lane** — one or a few files; a specific symptom, path, trace, or cheap reproduction exists; no unresolved architecture or migration; no new outward or production action.
- **Deep lane** — the root cause is unknown after a cheap reproduction, several systems interact, architecture or data migration is involved, or auth/security behavior is the actual bug.
- **Review lane** — read-only audit or review; do not change files unless the user separately authorizes fixes.

### Fast-lane budget

1. Use the paths and evidence already supplied. Read the target and run the cheapest live probe or failing test.
2. Within **two tool batches after reading the target**, either reproduce the fault or make the first smallest reversible edit. If a load-bearing premise is still unknown, state that specific gap instead of broadening the search silently.
3. Load at most **one mode reference and one directly relevant checklist**. Do not load the full Ant protocol, deep security material, or broad research guidance unless a concrete risk requires it.
4. Do not browse by default. Use upstream docs only when the fix depends on a disputed current API, SDK, or platform capability that local source and a live probe cannot settle.
5. If **five minutes or six tool calls** pass without a reproduction or edit, stop broad research. Record the current hypothesis, take the smallest reversible action, or report the concrete blocker.
6. Finish with targeted tests, the induced failure branch when safe, state/invariant checks, and a concise inline security review.

User authorization to fix a local, reversible artifact is the implementation approval. Ask again only for a newly discovered outward, irreversible, destructive, privileged, or paid action.

## Model-the-Real-System Gate (MANDATORY — 2026-07-03)

**Before you write, label, or estimate anything that describes a real system — a device's capabilities, an API's config, an equipment/hardware layout, a rate/limit/tier, "what channel carries X", any physical or account fact the code then models — you MUST read that system's OWN state live first. Never infer the ground truth from a name, a code comment, a variable label, a prior "Verified" note, a UI string, or plausibility.** This is the Ground-Truth Standard applied to *modeling*, not just to final reports: the model is a claim, and a claim isn't a fact until fetched from the primary source now.

The cheapest live probe almost always exists and almost always fits in one call:
- A device/integration exposes a **capability/settings object** — read it (ecobee `settings.hasHeatPump/hasBoiler/hasElectric/heatStages`, Stripe account caps, a printer's IPP attributes, a DB's `information_schema`, a feature-flag payload). One GET refutes a whole fabricated premise.
- "Which channel/field carries the real data" is answerable by **pulling a window that actually contains the event** and summing per-field (e.g. a winter runtimeReport to see heat lands on `auxHeat1`, not `compHeat1`). Don't assume the obvious-named field is the populated one.
- If the live value **can't be fetched right now** (stale token, no creds, offline), say so plainly and mark the model as *assumed pending verification* — do NOT assert it as fact, and default to the option that is wrong-safe (charges nothing you can't prove, hides no cost) while flagging the assumption in the UI/copy.

**Tripwire:** if the code's model rests on an equipment/config premise (a `// heat pump + aux backup` comment, a `auxKw` var, an "attisPro heat pump" identity string) and you have NOT this session read the system's own fields that would confirm it — STOP and read them before touching the model. **Reference incident (2026-07-03, ecobee-dashboard):** the entire cost model + savings tips assumed a heat pump with resistance "aux" backup (a 2.3×-cost-of-aux narrative, a phantom `compHeat1×coolKw` heating term). One live `GET /1/thermostat?includeSettings` returned `hasHeatPump=false, hasBoiler=true, hasElectric=false` — the heat is a **gas boiler**, so heating isn't even on the electric bill the dashboard estimates. Every "savings" number for heating was fiction. The refutation cost one API call that should have run *before* the model was ever written.

## No-Lie Final Report Gate (MANDATORY)

Before saying “done,” verify the state that matters now:

1. Read back the exact artifact or live target that was changed.
2. Run the narrowest test that proves the requested behavior, including the failure or trigger branch when safe.
3. Compare the result with the full objective, not merely the previous broken state.
4. Give a proof source for each numeric or stakes-bearing claim.
5. Never claim “pushed,” “deployed,” “sent,” or “live” without reading that exact external target back.

Use remote checks only when they apply:

- Run Git remote freshness and PR checks only for Git/PR work where remote state is load-bearing or an authorized push is next. Do not make every local fix fetch a remote.
- Check a live URL only after an authorized deployment actually occurred.
- For a skill or local configuration edit, reload the active skill/config and run its local validator. A backup script that pushes is a separate outward action: show its scope and get explicit approval before running it, then verify the remote result.
- For public causal claims, require a live observable, a direct success signal, and at least two interleaved runs per arm. Otherwise state the result as a hypothesis.

Read `~/.claude/skills/shared/no-lie-verification.md` in the deep lane or before any push, PR, deployment, or public report.

---

## Context Quality (how to see the codebase clearly)

The sequence matters more than any single tool choice.

**Default investigation loop:** `Grep` to find → `Read` to understand. Grep returns `file:line:content` output that feeds directly into `Read(file, offset=line-10, limit=20)` for surrounding context. Don't break this loop by routing through Bash.

**Before you write a helper, grep for one that already exists.** Re-implementing what lives a few files over is the most common form of slop and it is invisible in review — the new code is correct, it is just the second copy. Search for the *behavior*, not the name (`osgrep` finds the shape when the name differs), before adding a util, type, guard, formatter, or wrapper. This does NOT license shrinking a fix: reuse the existing helper, then still fix the whole call-site class (see the CALL-SITE CLASS rule below).

**Use `Read` — not Bash — for:**
- **Images, PDFs, notebooks** — `Read` renders visually so Claude actually *sees* the content. `cat screenshot.png` returns binary garbage; `cat file.pdf` returns gibberish. Huge loss on UI debugging, design comps, inspecting anything you just captured.
- **Any file you plan to Edit** — `Read` registers the file for safe edits. Without it, `Edit` fails with "file has not been read yet" and you waste a retry.
- **Files where line numbers matter** — `Read` prefixes them consistently for follow-up edits.

**Use `Bash` — freely — for:**
- **Git archaeology**: `git log -p`, `git blame`, `git diff A..B` — often the highest-signal context in a debug session. No native equivalent.
- **Executing code for evidence**: `node`, `python -c`, `curl`, `timeout 120 npx vitest run specific-test`. Evidence beats speculation.
- **Compound pipelines**: anything involving `sort`/`uniq`/`wc`/`awk`/`xargs`. Example: `grep -rn "TODO" --include="*.ts" | grep -v test | sort | uniq -c | sort -rn` for a ranked frequency table.
- **Running CLI tools**: `osgrep`, `qmd`, `bd`, `gh`, `wrangler`, `git`, `npm`.

**Don't use Bash as a `Read` substitute** (`cat`, `head`, `tail`, `sed -n '50,70p'`, `less`). You lose multimodal rendering, file-read tracking, and clean line-numbered output.

**Don't use Bash as a `Grep` substitute** for simple pattern searches. Native `Grep` returns structured output that feeds straight into the next `Read` call with offset/limit. Reserve `grep -rn | pipeline` for compound analysis Grep can't express.

---

## Mode Detection

Choose one primary mode before acting. Lane choice and domain mode are separate: a database bug can still be a **fast-lane debugging** task.

Common modes:

- **Bug, failing test, runtime error** → Debugging
- **New feature or refactor** → Implementation
- **Review request** → Review-only
- **Authentication, sessions, passkeys, OAuth** → Authentication
- **Database or migration** → Database
- **Deploy, release, CI/CD** → Ship
- **Browser or web interaction** → Browser automation
- **Research or API capability question** → Research
- **Performance, flaky tests, cost, simplification** → the matching specialist mode

Read `references/mode-routing-expanded.md` only when the request spans several specialist domains or routing is genuinely unclear. Never load it merely because Code was named.

## Hard Rules (NEVER VIOLATE)

These rules always apply:

1. **Ground truth first.** Treat memory, comments, cached files, and skill notes as hypotheses. Use the current primary source when a premise affects the fix or an outward action.
2. **No unapproved outward action.** Code does not deploy. Do not push, merge, send, submit, post, pay, delete, change production data/secrets, or run a backup that pushes without explicit approval for that exact action.
3. **Smallest reversible fix.** Preserve existing behavior outside the proved fault. Do not turn a bounded repair into a rewrite.
4. **Protect secrets and people.** Never print credentials, tokens, cookies, private message bodies, recipient data, or provider response bodies. Sanitize diagnostics.
5. **No destructive shortcuts.** Never force-push shared history, destroy infrastructure, drop databases, edit live state stores in place, or bypass safety prompts.
6. **No suppression as a fix.** Do not hide type, lint, test, or security failures. Fix the cause or report the concrete blocker.
7. **Verify the real branch.** Read the changed artifact back, run focused checks, induce triggered behavior on an isolated copy when safe, and confirm failure paths do not corrupt or advance state.
8. **Fix the bug class, proportionally.** Search sibling call sites that can reach the same sink. If unrelated cleanup would exceed ten times the original task, record it and ask before expanding scope.

### Semantic Security Review Gate — PROPORTIONAL

- **Git production code or high-risk auth/security work:** use the available semantic review workflow on a real reviewable diff, fix valid findings, and rerun it.
- **Fast-lane local script or non-git artifact:** review the changed code inline. Test relevant risks such as secret leakage, command injection, unsafe paths or symlinks, untrusted-input handling, failure atomicity, and state advancement. Run language-native checks.
- **Documentation/configuration:** check for leaked secrets, unsafe commands, and misleading claims.

Do not create a commit solely to run a reviewer. Do not load deep security material before the first edit unless security is the reported defect.

### Load detailed rules only when triggered

Read `references/hard-rules-expanded.md` when using the deep lane or when the task involves deployment/CI, auth or sessions, browser cookies, reverse engineering, public-site accessibility/CSP, TypeScript anti-slop, databases/infrastructure, or another high-risk domain. The core rules and proportional lane in this file outrank examples in that reference.

## Agent Spawning Rules (from internal Coordinator Mode)

Delegation is optional. **Do not delegate the sole critical path of a fast-lane, one-file fix.** Use an agent only for independent parallel work, a large review, or a clearly bounded specialist task.

1. “Use Code” does not mean “spawn a Code agent.” Apply the method in the current agent by default.
2. Give each child a fully self-contained prompt with exact paths, constraints, deliverables, and verification.
3. Before delegating, the parent must identify the concrete reproduction, question, or artifact the child owns.
4. The child must produce a first material artifact or verified finding within five minutes or six tool calls. If it does not, steer once, then stop it and continue locally. Do not wait on an unproductive child while the main path is idle.
5. Recover an interrupted child at most once and only when its work remains relevant and safe. Never retry an outward action with uncertain state.
6. Verify every child edit and every external side effect yourself before reporting success.
7. Avoid mutable state conflicts: never let two agents edit the same file or database concurrently.

## Search-Indexing Build Gate (public web properties — 2026-09-28)

When the work touches a public web property (Cloudflare Worker/Pages, any
served-HTML site), the build is not done until the indexing artifacts are
correct IN SOURCE — so that `/ship`'s Phase 4.10 post-deploy gate has
something true to verify. Check before reporting done:

1. **sitemap.xml exists and is valid.** Every `<loc>` absolute on the
   canonical domain; routes this change touched carry `lastmod` = today
   (or the generator computes it at build time — never a stale hardcoded
   date).
2. **robots.txt exists and points at the sitemap.** Contains
   `Sitemap: https://<domain>/sitemap.xml`. No crawl-wide `Disallow: /`
   on a public site. Preview/staging builds are the exception — and they
   must carry `X-Robots-Tag: noindex` (or equivalent) instead of shipping
   the public robots.txt.
3. **IndexNow key file present, byte-exact.** `<key>.txt` at the web root
   matches the domain's registered key (registry: the indexing goal's
   `hidden_files/evidence-table.md`). The key is NEVER regenerated per
   deploy — rotating it breaks verification.
4. **Redirect landers get nothing.** If the property only 301/302s to
   another domain, it gets no sitemap, no robots indexing lines, no GSC
   property, no IndexNow submission. Verify with no-follow status +
   `Location` probes — never by reading through the redirect (2026-09-28:
   eleven landers were mis-audited as live sites because checks followed
   their 301s).
5. **New domains get flagged, not silently shipped.** A domain with no GSC
   property and no entry in the indexing ledger is reported as a Phase
   4.10 action item — never deployed as "done" while undiscoverable.

Fast-lane note: for a small fix on an already-indexed site, this is a
60-second grep + curl of the three artifacts, not a research project.

## Reference Files Index

| File | Content |
|------|---------|
| `code-review-react.md` | TypeScript/React 19 review rules, useEffect ban, hook patterns, state management |
| `code-review-security.md` | XSS 10-vector audit, escapeHtml/isSafeUrl implementations, severity matrix |
| `code-review-general.md` | Performance, quality, testing, Rust, config compat, full review checklist (42 items) |
| `ux-patterns.md` | UX pre-checks, error handling patterns, WCAG 2.2 AA, iOS Safari, scope errors |
| `ui-duplicate-affordance.md` | Double-chevron / double-arrow / duplicate-icon detection. 5-step recipe for `<select>` + `<details>` + redundant badges. Forms-framework + native-control collision patterns. Reference incident: IBA-m69. |
| `responsive-design.md` | Responsive rules, mobile/desktop strategy, frontend design principles |
| `feature-implementation.md` | Build decision framework, brainstorming, PRD generation, Ralph mode |
| `browser-automation.md` | chrome-cdp (live session), agent-browser (headless), commands reference |
| `git-workflow.md` | Git pre-flight, security scanning, worktree management, fork mass-integration |
| `debug-patterns.md` | 5-phase workflow, code search tools, repro harnesses, React-specific checks |
| `deploy-patterns.md` | Session invalidation, CF Pages debugging, cross-platform CI, code scanning, GH Actions |
| `codex-integration.md` | Codex review (quality gate), adversarial review, rescue (escalation) |
| `research.md` | Last30days web research, Reddit/X/web synthesis, prompt generation |
| `skill-creation.md` | Creating & editing SKILL.md files, frontmatter, progressive disclosure |
| `task-tracking.md` | PRD to prd.json conversion, agent-testable tasks, beads tracking |
| `aiva-guidelines.md` | AIVA-specific: color ban, VA palette, OG/favicon standards, admin auth pattern |
| `preflight-checks.md` | Pre-flight: CDP warmup, codebase audit, code coverage, lint/security auto-fix |
| `legal-document-audit.md` | 5 hallucination patterns (fabricated citations, fake phones, invented people, name transposition, exhibit drift), audit procedure, sweep script |
| `lighthouse-optimization.md` | Lighthouse 100/100 playbook: 3-run median audit loop, 10 high-leverage patterns (defer third-party, kill CF Bot Fight JS, SSR hero, async CSS, preload LCP, bundle analysis, bf-cache headers, SEO fallback, a11y quick wins, CSP fixes), 4-stage fix order, known ceilings |
| `~/.claude/skills/shared/account-security-lifecycle.md` | Passkey/TOTP/passwordless lifecycle: alternate-login enforcement, fresh-session management, recovery, safe redirects, authoritative status, recovery-code custody, and leaked-token response |
| `~/.claude/skills/shared/observability-instrumentation.md` | **Observability standard**: instrument-on-build + instrument-on-fix (boy-scout), boundary/decision-point logging, structured-log shape, 4-part actionable error-message design, downgrade-noise-never-delete guardrail, stack log sources. Proactive counterpart: `/log-hygiene` skill. |
| `~/.claude/skills/shared/ant-verification-protocol.md` | **Ant-level quality gates**: OWASP Top 10 sweep, truthfulness protocol, closed-loop verification, enhanced review |
| `~/.claude/skills/shared/anti-slop-typescript.md` | **Anti-slop TypeScript**: ban generic `isRecord`/`isObject` guards, `as unknown as T` launder-casts, `(x as any).field` reach-casts; require named types / discriminated unions / Zod schemas (`z.infer`). Enforcers: vendored **dmmulroy/anti-slop Oxlint plugin** (15 rules; vendor into a repo with the `/install-anti-slop` skill, then `./node_modules/.bin/oxlint` is the gate) or the zero-dep fallback `~/.claude/skills/code/tools/detect-ts-slop.sh`. Runtime-guard sibling of the No-Suppression Rule. |

---

## Code Search Tools

**Start with native `Grep` / `Glob`** — they return structured `file:line:content` output that feeds directly into `Read`. Escalate to the CLI tools below only when keyword matching can't express the question (semantic search, cross-doc synthesis, AST patterns).

### osgrep — AST-Aware / Semantic Code Search (escalate from Grep)
Use when the thing you're looking for isn't a literal keyword — e.g. "where is auth handled" across varied naming.

```bash
osgrep index .                          # Build index (first time per project)
osgrep query "where is auth handled"    # Semantic search
osgrep query "error handling" --mode fulltext  # Keyword search
```

### qmd — Knowledge & Documentation Search
```bash
qmd collection add ~/project/docs --name docs   # Add docs collection
qmd embed                                        # Build embeddings
qmd query "how does authentication work"         # Hybrid search
```

### bd — Task Tracking
```bash
bd create --title="Investigate issue" --type=bug --priority=2
bd update <id> --status=in_progress
bd close <id> --reason="Root cause and fix summary"
```

---

## Cloudflare API Access (MCP)

The `cloudflare-api` MCP server provides full access to ~2,500 Cloudflare API endpoints:
- **`search`** — Query the OpenAPI spec to find endpoints
- **`execute`** — Call any Cloudflare API endpoint

Use for: Worker runtime logs, DNS/routing issues, KV/D1/R2 data, Worker bindings, firewall rules, zone analytics, cache behavior, SSL status, edge redirect rules.

---

## Instructions

When this skill is invoked:

**STEP 0 — Choose the lane and start work:**

1. Choose fast, deep, or review lane using the proportional rules above.
2. Send a brief status only when the task will take more than a quick action.
3. Inspect the exact target, local instructions, and existing verification path. Do not re-ask for context that is already present.

**STEP 1 — Load only the context the lane needs:**

- **Fast lane:** load at most one mode reference and one directly relevant cross-cutting checklist. Skip broad Ant, research, and security packs unless a concrete risk triggers them.
- **Deep lane:** load the relevant mode reference, `~/.claude/skills/shared/ant-verification-protocol.md`, `~/.claude/skills/shared/no-lie-verification.md`, and any directly relevant domain reference.
- **Review lane:** load `references/code-review-general.md` and the review rubric that matches the request.

**STEP 2 — Execute:**

- **Fast lane (default for bounded local fixes):** work in the current agent. Reproduce or inspect, make the smallest reversible edit, run focused checks, induce the failure path when safe, review security inline, and verify the final state.
- **Deep lane:** run the 5-phase method: characterize, investigate, synthesize, remediate, verify. Delegation is optional and must satisfy the Agent Spawning Rules.
- **Review lane:** report findings with file-and-line evidence. Do not edit unless separately authorized.

Do not pause at a generic approval checkpoint when the user already asked for a local reversible fix. Pause only before a new outward, irreversible, destructive, privileged, or paid action.

**STEP 3 — Verify and report:**

1. Run the narrowest real verification that proves the requested behavior, then the broader quality gate when the project defines one.
2. Compare the result with the full objective, not merely the previous broken state.
3. Report the artifact changed, tests or commands actually run, remaining uncertainty, and any blocked outward step.
4. Do not deploy or push without the required approval. Check CI only after an authorized push actually occurred.
