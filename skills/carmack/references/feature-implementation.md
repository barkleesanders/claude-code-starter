# Feature Implementation & Planning

## Build Decision Framework

Before building ANYTHING, run this checklist. The best engineers aren't the ones who know the most — they're the ones who know what NOT to build.

### Step 1: Should You Build This?

Ask: **Does a production-grade solution already exist?**

| Domain | DON'T Build | USE Instead |
|--------|------------|-------------|
| Auth | Custom login/sessions/OAuth | Clerk, Supabase Auth, Auth.js |
| Payments | Custom payment processing | Stripe (45 min to integrate) |
| UI Components | Raw CSS, custom primitives | Tailwind + shadcn/ui + Radix |
| Forms + Validation | Custom validators | Zod + React Hook Form |
| State Management | Redux, deep Context trees | Zustand (client), Server Components (server) |
| APIs (MVP stage) | Custom REST from scratch | tRPC, Server Actions |
| Database | Raw SQL, self-hosted DB | Prisma + managed Postgres (Supabase/Neon) |
| File Uploads | Custom storage/CDN | UploadThing, Cloudinary |
| Search | Custom full-text search | Algolia, Typesense, Meilisearch |
| Realtime | Custom WebSocket infra | Supabase Realtime, Pusher, PartyKit |
| Deployment | Manual SSH/deploy scripts | Vercel one-click, Railway, Render |
| Error Monitoring | Manual log checking | Sentry (set up day 1, free tier) |
| Analytics | Custom tracking | PostHog, Plausible (set up before launch) |

### Step 2: Red Flag Detection

Before implementing a feature, check for these time sinks:

```bash
# STOP if you're about to:
# - Spend >2 hours on auth for an unvalidated MVP
# - Write raw CSS when Tailwind covers it
# - Build a custom API layer before you have 10 users
# - Deploy manually instead of push-to-deploy
# - Skip error monitoring ("I'll add it later")
# - Build custom file upload handling
# - Roll your own search engine
# - Hardcode API keys anywhere (use .env + .gitignore)
```

### Step 3: Time Budget Rule

If a feature takes >1 day and a service solves it in <1 hour, use the service. Your energy is worth more than your custom implementation. Migrate later IF real usage data justifies it.

---

## Planning & Discovery

### Brainstorming

Use before implementing features when requirements are unclear or multiple approaches exist.

**Skip brainstorming when**: Requirements are explicit, user knows exactly what they want, or it's a straightforward bug fix.

**Use brainstorming when**: Vague terms ("make it better"), multiple valid interpretations, trade-offs need exploring.

#### Phase 0: Assess Requirement Clarity

**Signals requirements are clear**: Specific acceptance criteria given, exact behavior described, scope constrained.

**Signals brainstorming needed**: Vague terms used, multiple interpretations exist, trade-offs undiscussed.

#### Phase 1: Understand the Idea

Ask questions **one at a time**. Prefer multiple choice when natural options exist.

**Question techniques:**
- Prefer: "Should notifications be: (a) email only, (b) in-app only, or (c) both?"
- Avoid: "How should users be notified?"
- Start broad → narrow (purpose → users → constraints)
- Validate assumptions explicitly: "I'm assuming users are logged in. Correct?"
- Ask about success criteria early

**Key topics to explore:**

| Topic | Example Questions |
|-------|-------------------|
| Purpose | What problem does this solve? Motivation? |
| Users | Who uses this? What's their context? |
| Constraints | Technical limitations? Timeline? Dependencies? |
| Success | How measure success? What's the happy path? |
| Edge Cases | What shouldn't happen? Error states? |
| Existing Patterns | Similar features in codebase to follow? |

**Exit**: Continue until idea is clear OR user says "proceed" or "let's move on"

#### Phase 2: Explore Approaches

Propose 2-3 concrete approaches:

```markdown
### Approach A: [Name]

[2-3 sentence description]

**Pros:**
- [Benefit 1]

**Cons:**
- [Drawback 1]

**Best when:** [Circumstances where this approach shines]
```

Guidelines: Lead with recommendation, be honest about trade-offs, consider YAGNI, reference codebase patterns.

#### Phase 3: Capture the Design

```markdown
---
date: YYYY-MM-DD
topic: <kebab-case-topic>
---

# <Topic Title>

## What We're Building
[1-2 paragraphs max]

## Why This Approach
[Why chosen over alternatives]

## Key Decisions
- [Decision 1]: [Rationale]

## Open Questions
- [Unresolved for planning phase]

## Next Steps
→ `/workflows:plan` for implementation details
```

**Output:** `docs/brainstorms/YYYY-MM-DD-<topic>-brainstorm.md`

#### YAGNI Principles

- Don't design for hypothetical future requirements
- Choose the simplest approach that solves the stated problem
- Prefer boring, proven patterns over clever solutions
- Ask "Do we really need this?" when complexity emerges
- Defer decisions that don't need to be made now

#### Anti-Patterns to Avoid

| Anti-Pattern | Better Approach |
|--------------|-----------------|
| Asking 5 questions at once | Ask one at a time |
| Jumping to implementation details | Stay focused on WHAT, not HOW |
| Proposing overly complex solutions | Start simple, add complexity only if needed |
| Ignoring existing codebase patterns | Research what exists first |
| Making assumptions without validating | State assumptions explicitly and confirm |
| Creating lengthy design documents | Keep it concise — details go in the plan |

---

### PRD Generation

Create Product Requirements Documents when planning a feature, starting a new project, or asked to spec out requirements.

**Important:** Do NOT start implementing. Just create the PRD.

#### Step 1: Ask Clarifying Questions

Ask only critical questions where prompt is ambiguous. Use lettered options for quick answers:

```
1. What is the primary goal of this feature?
   A. Improve user onboarding experience
   B. Increase user retention
   C. Reduce support burden
   D. Other: [please specify]

2. Who is the target user?
   A. New users only
   B. Existing users only
   C. All users
   D. Admin users only

3. What is the scope?
   A. Minimal viable version
   B. Full-featured implementation
   C. Just the backend/API
   D. Just the UI
```

Users can respond "1A, 2C, 3B" for fast iteration. Focus on: Problem/Goal, Core Functionality, Scope/Boundaries, Success Criteria.

#### Step 2: PRD Structure

```markdown
# PRD: [Feature Name]

## Introduction
Brief description and problem it solves.

## Goals
Specific, measurable objectives (bullet list).

## User Stories

### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Specific verifiable criterion (not "works correctly")
- [ ] Another verifiable criterion
- [ ] Typecheck/lint passes
- [ ] **[UI stories only]** Verify in browser using agent-browser

## Functional Requirements
- FR-1: The system must allow users to...
- FR-2: When a user clicks X, the system must...

## Non-Goals (Out of Scope)
What this feature will NOT include.

## Design Considerations (Optional)
UI/UX requirements, mockup links, existing components to reuse.

## Technical Considerations (Optional)
Known constraints, dependencies, performance requirements.

## Success Metrics
- "Reduce time to complete X by 50%"
- "Increase conversion rate by 10%"

## Open Questions
Remaining questions or areas needing clarification.
```

**Good acceptance criteria**: "Button shows confirmation dialog before deleting"
**Bad acceptance criteria**: "Works correctly"

**Output:** Save to `tasks/prd-[feature-name].md` (kebab-case).

---

## Ralph Mode: Autonomous Feature Build

Ralph is an autonomous loop that implements features by breaking them into small user stories and completing them one at a time.

**When to use**: When asked to "use ralph", "ralph this", or to implement a feature end-to-end.

#### Step 1: Understand the Feature

Ask clarifying questions if needed:
- What problem does this solve?
- What are the key user actions?
- What's out of scope?
- How do we know it's done?

#### Step 2: Create prd.json

Generate in the project root:

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "description": "[Feature description]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

#### Step 3: Execute the Loop (on the loop-runner substrate)

Ralph IS a loop, so run it on **loop-runner** — it bounds the iterations,
machine-verifies each story, keeps a JSONL ledger + a beads issue, and its
Stop-gate keeps the build going turn-to-turn and **refuses a premature "done"**
until the real finish line (all stories pass) is met. The prd.json `passes`
flags and progress.txt stay exactly as before — loop-runner wraps them.
(If `~/.claude/skills/loop-runner/scripts/loop.sh` is missing, fall back to the
bare loop: same 9 steps, manually.)

**Start the loop ONCE, right after prd.json exists:**

```bash
L=~/.claude/skills/loop-runner/scripts/loop.sh
bash "$L" start \
  --title "ralph: <feature>" \
  --prompt "Ralph: implement each highest-priority userStory in prd.json with passes:false — ONE per iteration — running the project quality checks after each, committing only when they pass." \
  --verify "<project quality check — e.g. npm run typecheck && npm test, or pytest -q, or cargo test>" \
  --stop "max-iter=<#stories + 3>,no-progress=2,target=bash ~/.claude/skills/carmack/tools/ralph-prd-status.sh"
```

- `--verify` = the SAME quality checks Step 5 already runs (typecheck/lint/test). Exit 0 ⇒ this story holds. Use the real project command; only omit `--verify` (self-graded) if the repo genuinely has no check — and say so to the user.
- `--stop target=…` = the finish line: `ralph-prd-status.sh` exits 0 only when **every** userStory has `passes:true`.
- `max-iter` caps runaway; `no-progress=2` catches a story that won't go green.

**Each iteration = one user story:**
1. Read `prd.json` and `progress.txt` (Codebase Patterns first); confirm the branch from PRD `branchName` (check out / create from main if needed).
2. Pick the **highest-priority** story with `passes:false`; implement that ONE story.
3. Verify and capture the exit:  `bash "$L" verify; ve=$?`
4. If `ve` = 0: commit `feat: [Story ID] - [Story Title]`, set `passes:true` in prd.json, append to progress.txt. If `ve` ≠ 0: leave `passes:false`, note the failure, plan a different approach next cycle (do **not** commit a red story).
5. Record one ledger line, then check the bounds:
   ```bash
   bash "$L" record "US-XXX <title>" --evidence "<commit sha / check output>" --verify-exit "$ve"
   bash "$L" check-stop      # prints `continue` or `stop:<reason>`
   ```
6. **`stop:target`** (all stories green) → run the completion audit, then `bash "$L" complete`. **`stop:max-iter` / `stop:no-progress`** → stop and report which stories are still red — never fake completion. Otherwise take the next story.

Across turns the Stop-gate enforces this: it won't let the session end while stories are red and the bounds still hold, and it points you at `complete`/`abort` when a predicate fires.

#### Story Size Rules

Each story MUST be completable in ONE iteration. If you can't describe it in 2-3 sentences, it's too big.

**Right-sized:**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

**Too big (split these):**
- "Build the entire dashboard" → schema, queries, UI components, filters
- "Add authentication" → schema, middleware, login UI, session handling

#### Story Order: Dependencies First

1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views

#### Progress Report Format

APPEND to progress.txt (never replace):

```
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

If you discover a reusable pattern, add it to `## Codebase Patterns` at the TOP of progress.txt.

---

## Engineering Discipline (Non-Negotiable)

**1. Verification Before Done**
- Never mark a task complete without proving it works
- After deploy: curl the page, verify bundle hash changed, test the endpoint
- Ask yourself: "Would a staff engineer approve this?"
- Diff behavior between main and your changes when relevant
- Run tests, check logs, demonstrate correctness

**2. Self-Improvement Loop**
- After ANY correction from the user: write a lesson to memory
- Write rules for yourself that prevent the same mistake
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Review lessons at session start for the relevant project

**2b. Systematic Debugging (Iron Law from obra/superpowers)**
- **NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST** — if you haven't completed Phase 1, you cannot propose fixes
- Phase 1: Root Cause Investigation (reproduce, trace data flow, gather evidence)
- Phase 2: Pattern Analysis (find working examples, compare, identify differences)
- Phase 3: Hypothesis Testing (single hypothesis, test minimally, verify)
- Phase 4: Implementation (failing test first, single fix, verify)
- **Red flags — STOP and return to Phase 1:** "Quick fix for now", "Just try changing X", "I don't fully understand but this might work", "One more fix attempt" (after 2+ failures)
- 3-failure limit: if 3 fixes fail, force architectural reassessment — the approach is wrong
  - Offer Codex rescue as an alternative: `/codex:rescue [issue + evidence gathered]`
- **"Data appears stale" shortcut:** If the bug is "admin changed X but user still sees old X", skip generic debugging and go straight to the admin-user sync decision tree:
  1. Does the user hook have `visibilitychange` refresh? → If no, that's the bug
  2. Does the admin endpoint clean up dependent fields? → If no, dirty write
  3. Does the admin UI re-sync after optimistic update? → If no, split-brain
  4. Is the user's navigation state URL-persisted and not recalculating? → If yes, stale pointer
  5. Are data indicators (progress %) and navigation indicators (Step X) using different sources? → If yes, split-brain
- Reference: `/debug` skill for full methodology, patterns, and techniques

**3. Autonomous Bug Fixing**
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

**4. Dual-Portal Sync Checklist (MANDATORY when feature touches admin + user views)**

When building ANY feature where admin writes data that users read, complete this before marking the story done:

- [ ] Every user-facing data hook has `silentFetch` + `visibilitychange` listener (no spinner on tab switch)
- [ ] Admin write endpoint clears dependent fields on status change (e.g., `flag_message = NULL` when completing)
- [ ] Admin optimistic update calls `fetchData()` after successful API response
- [ ] URL-persisted navigation state (`?step=`, `?tab=`) auto-advances when data changes
- [ ] Multi-view displays use data-derived values (`useMemo`), not navigation state
- [ ] Admin write endpoint uses correct audit action (not `VIEW` for a `PUT`)
- [ ] Data-driven indicators (progress bar, counts) and navigation indicators (Step X of Y) use the same source of truth

If ANY checkbox is unchecked, the story is not done.

**4b. Municipal / Experience Cloud catalog (MANDATORY when building a 311/civic submitter)**

"File every listed type" is not a plan. Load Pattern #36 (`~/.claude/skills/debug/references/error-handling-patterns.md`) **before** writing catalog JSON or a submit envelope.

- Persist official form models. A SUCCESS response with empty `sId` / `sCaseType` / questions is `captureFailure` — never dummy `modelFlags`.
- Classify on field API names (`sFieldtoUpdate`), not question text. Refuse naming the official field (`Permit_Number__c`), not a class stub.
- Never invent session-encrypted IDs; remint at submit. Unwrap toast/`objCaseConfigWrapper` before sending.
- Proof = two live files of one pin-only type, then `/ship`. Not 77 tickets. `/carmack` does not `wrangler deploy`.

**5. Demand Elegance (Balanced)**
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

**5. Subagent Strategy**
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- One task per subagent for focused execution
- For complex problems, throw more compute at it via subagents

**6. Context Optimization (from muratcankoylan/agent-skills-for-context-engineering)**
- Use file-search skill (`rg` + `ast-grep`) for targeted code searches — count results first, then narrow
- KV-cache: keep static prompt sections stable (no timestamps, no whitespace changes)
- Observation masking: replace verbose tool outputs with compact references when context is >70% utilized
- Context partitioning: split work across sub-agents when task exceeds 60% of window
- Reference: `~/.claude/skills/context-optimization/` and `~/.claude/skills/file-search/`

---

## Quality Requirements

- ALL commits must pass quality checks (typecheck, lint, test)
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns

**Language-specific quality gates:**
- **TypeScript/React**: `npm run build && timeout 120 npx vitest run --changed`
- **Rust**: `cargo fmt --all -- --check && cargo clippy --all-targets && cargo check`
- **Python**: `ruff check . && mypy . && pytest`

**Optional Codex review gate:**
After quality checks pass, offer `/codex:review --background` for cross-model validation. Check `/codex:status` before marking the entire feature complete.

---

## Browser Testing (Required for Frontend Stories)

For any story that changes UI:
1. **If page is open in Chrome**: use `fcdp` (`~/tools/fcdp/fcdp read [tab]`) — live session, real data, the user's REAL logged-in Chrome
2. **If testing fresh**: use `agent-browser` (see Browser Automation section)
3. Verify UI changes work as expected
4. Take a screenshot: `~/tools/fcdp/fcdp shot [tab] [file.png]`

**Visual Regression Check (MANDATORY for UI changes):**
After deploying any UI change, verify at both viewports:
```bash
# Desktop verification
agent-browser open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-desktop.png --full
agent-browser close

# Mobile verification (375px iPhone SE)
agent-browser --viewport 375x812 open "$DEPLOY_URL"
agent-browser screenshot --path /tmp/deploy-mobile.png --full
agent-browser close
```
Check for: blank areas, horizontal overflow, overlapping elements, broken images. If mobile shows horizontal scroll or blank content — the change is not done.
