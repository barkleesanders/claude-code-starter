---
name: exec-plan
user-invocable: true
description: "Execution plan management for long-running coding sessions. Combines self-contained living plans (restartable from file alone) with generator-evaluator separation, sprint contracts, and structured context handoffs. Use when: building a multi-milestone feature, running a multi-session refactor, any task too large for one context window, or when the user says 'exec-plan', 'execution plan', 'create a plan', 'resume plan', 'eval my work', or 'plan status'. Commands: /exec-plan create, /exec-plan resume, /exec-plan status, /exec-plan eval, /exec-plan close, /exec-plan list."
---

# /exec-plan — Long-Running Execution Plans

Manage persistent coding sessions with self-contained plans, sprint contracts, and generator-evaluator separation. Plans survive context resets — any new session resumes by reading the plan files.

Based on Anthropic's harness design patterns: the agent doing work (generator) must NOT evaluate its own work. A separate skeptical evaluator subagent grades against concrete criteria.

## Commands

| Command | Action |
|---------|--------|
| `/exec-plan "description"` | Create new plan from brief description |
| `/exec-plan create "description"` | Same as above (explicit) |
| `/exec-plan resume [name]` | Resume active plan from handoff.md or plan.md |
| `/exec-plan status` | Show milestone progress + eval verdicts |
| `/exec-plan eval` | Spawn evaluator subagent to grade current milestone |
| `/exec-plan close` | Retrospective, capture memories, close beads |
| `/exec-plan list` | List all plans in ~/tools/exec-plans/ |

## Storage

Plans live at `~/tools/exec-plans/{plan-name}/` with five files:
- **plan.md** — The living execution plan. Self-contained. Any session can restart from ONLY this file.
- **sprint-log.md** — Sprint contracts (success criteria) + evaluator verdicts
- **evidence.md** — Test results, command outputs, measurements
- **decisions.md** — Architecture decisions with rationale
- **handoff.md** — Context reset document. Written before compaction or session end.

## Task Tracking

Use `bd` (beads) for tracking. Do NOT use TodoWrite or TaskCreate.

```bash
bd create --title="exec-plan: {plan-name}" --type=epic --priority=1
bd create --title="M1: {milestone}" --type=task --priority=2
bd dep add <milestone-id> <plan-id>
bd close <id> --reason="Evaluator verdict: PASS"
```

---

## Phase 1: CREATE — Planner Expands Brief into Spec

When the user invokes `/exec-plan "Build auth system"`:

### Step 1: Initialize plan directory

```bash
bash ~/.claude/skills/exec-plan/scripts/init-plan.sh "{plan-name}"
```

### Step 2: Act as Planner

Expand the brief into a full plan.md. Stay high-level to avoid cascading errors.

**Planner rules:**
1. Break work into 3-7 milestones. Each = independently testable deliverable.
2. Each milestone has concrete acceptance criteria (testable commands, not vague).
3. Order milestones by dependency.
4. First milestone = smallest thing that proves the approach works.
5. Describe WHAT each milestone delivers, not HOW to implement it.
6. Identify risks and unknowns in the Surprises section.

### Step 3: Write plan.md using template

```markdown
# Execution Plan: {Plan Name}

## Purpose
{2-3 sentences. What is being built and why. A stranger should understand the goal.}

## Context
- **Repository:** {repo path}
- **Branch:** exec-plan/{plan-name-kebab}
- **Key files:** {3-5 entry points relevant to this work}
- **Dependencies:** {external services, APIs, libraries}
- **Constraints:** {deadlines, backward compat, resource limits}

## Progress
- [ ] **M1: {Title}** — {one-line description}
  - Acceptance: {comma-separated testable criteria}
  - [ ] {substep 1}
  - [ ] {substep 2}
- [ ] **M2: {Title}** — {one-line description}
  - Acceptance: {testable criteria}
  - [ ] {substep 1}
- [ ] **M3: {Title}** — {one-line description}
  - Acceptance: {testable criteria}

## Surprises
{Things discovered during execution that were not anticipated.}

## Decision Log
See decisions.md for full log.

## Retrospective
{Filled at close.}

## Self-Contained Recovery Instructions
{If an agent reads ONLY this file with zero other context, what does it need?}

- Navigate: `cd {repo-path}`
- Branch: `git checkout exec-plan/{plan-name}`
- Install: `{install command}`
- Test: `{test command}`
- Current milestone: M{N}
- Sprint contract: See ~/tools/exec-plans/{plan-name}/sprint-log.md
- Evidence: See ~/tools/exec-plans/{plan-name}/evidence.md
```

### Step 4: Create beads

```bash
bd create --title="exec-plan: {plan-name}" --type=epic --priority=1
# For each milestone:
bd create --title="M{N}: {title}" --type=task --priority=2
bd dep add <milestone-bead> <plan-bead>
```

### Step 5: Confirm with user

Display milestone list and ask user to confirm before proceeding to build.

---

## Phase 2: SPRINT CONTRACT — Before Each Milestone

Before starting ANY milestone, write a sprint contract to sprint-log.md.

### Sprint Contract Template

Append to sprint-log.md:

```markdown
---
## Sprint: M{N} - {Milestone Title}
Started: {ISO timestamp}
Status: IN_PROGRESS

### What "Done" Looks Like
- {Bullet 1 — independently verifiable}
- {Bullet 2}
- {Bullet 3}

### Acceptance Tests
- [ ] `{command}` — expected: {description}
- [ ] File `{path}` exists and contains {what}
- [ ] `curl {endpoint}` returns {expected}

### Out of Scope
- {What this milestone does NOT include}

### Generator Commitment
I will deliver the above. If scope is wrong, I will update this contract BEFORE continuing.
---
```

The generator and evaluator must agree on these criteria. The contract is the single source of truth.

---

## Phase 3: BUILD — Generator Implements

The main agent acts as generator. During build:

1. Work on the current milestone ONLY
2. Log significant outputs to evidence.md
3. Log architecture decisions to decisions.md
4. Update plan.md progress checkboxes as substeps complete
5. If scope changes, update the sprint contract FIRST

### Evidence format (append to evidence.md)

```markdown
---
## {ISO timestamp} - M{N}: {what was tested}
### Command
`{command}`
### Output
{output, truncated to relevant portions}
### Interpretation
{1-2 sentences}
---
```

### Decision format (append to decisions.md)

```markdown
---
## D{N}: {Title} ({ISO date})
**Context:** {What prompted this}
**Options:** 1. {A} — {pro/con} | 2. {B} — {pro/con}
**Decision:** {Which and why}
**Consequences:** {Impact on future milestones}
---
```

---

## Phase 4: EVAL — Evaluator Grades the Sprint

When `/exec-plan eval` is invoked or generator believes milestone is complete:

### Step 1: Spawn evaluator subagent

Use the Agent tool to spawn a SEPARATE subagent. This is critical — the generator must NOT evaluate its own work.

**Agent prompt:**

```
You are a skeptical code evaluator. Your job is to grade milestone M{N} of exec-plan "{plan-name}".

1. Read ~/tools/exec-plans/{plan-name}/sprint-log.md for the sprint contract
2. Read ~/tools/exec-plans/{plan-name}/evidence.md for test results
3. Read ~/.claude/skills/exec-plan/references/evaluator-prompt.md for your evaluation rules
4. Run EVERY acceptance test listed in the sprint contract
5. Grade each criterion as PASS or FAIL with specific evidence
6. Write your verdict to ~/tools/exec-plans/{plan-name}/sprint-log.md

Verdict format — append after the sprint contract:

### Evaluator Verdict ({ISO timestamp})
**Overall: {PASS|PARTIAL|FAIL}**

| Criterion | Result | Evidence |
|-----------|--------|----------|
| {criterion} | PASS/FAIL | {specific evidence} |

**Feedback:** {If PARTIAL/FAIL: specific, actionable items}
```

### Step 2: Process verdict

- **PASS**: Check off milestone in plan.md. Close milestone bead. Move to next milestone (Phase 2).
- **PARTIAL**: Address specific feedback. Re-eval without restarting sprint.
- **FAIL**: Address feedback. Iterate same sprint contract. Max 3 eval attempts before escalating to user.

---

## Phase 5: CONTEXT RESET — Structured Handoff

When context fills or session ends, write handoff.md BEFORE compaction.

The PreCompact hook (`scripts/pre-compact-sync.sh`) auto-reminds you. Also write proactively when context usage exceeds ~70%.

### Handoff template (write to handoff.md)

```markdown
# Handoff: {plan-name}
Written: {ISO timestamp}

## Current State
- **Active milestone:** M{N} - {title}
- **Sprint status:** {IN_PROGRESS|AWAITING_EVAL|ITERATING}
- **Eval attempts:** {N}/3

## Accomplished This Session
- {Concrete deliverable with file path}

## In Progress (Unfinished)
- {Started-but-incomplete work with file path and status}

## Blockers
- {Anything next session must resolve}

## Key Context
{3-5 sentences of critical context that would be lost. "What would I need to know if I had amnesia?"}

## Files Modified
- {List grouped by milestone}

## Next Action
{Single most important next step. Be specific.}
```

---

## Phase 6: RESUME — Pick Up Where Left Off

When `/exec-plan resume` is invoked:

1. **Find active plan**: `ls ~/tools/exec-plans/` — if multiple, ask user to choose
2. **Read in priority order**: handoff.md (most context) > plan.md (self-contained fallback) > sprint-log.md (contract status)
3. **Check beads**: `bd list` to see milestone status
4. **Display state**: Print current milestone, progress, last verdict
5. **Continue from "Next Action"** in handoff.md

---

## Phase 7: CLOSE — Retrospective and Memory

When `/exec-plan close` or all milestones PASS:

### Step 1: Write retrospective in plan.md

```markdown
## Retrospective
Completed: {ISO timestamp}
Duration: {first} to {last timestamp}

### What Went Well
- {bullet}

### What Was Harder Than Expected
- {bullet}

### Patterns Worth Remembering
- {bullet}
```

### Step 2: Capture memories

```bash
bd remember "{insight}"
```

### Step 3: Close all beads

```bash
bd close <plan-bead> --reason="Plan complete. {N}/{total} milestones passed."
```

---

## STATUS Command

When `/exec-plan status` is invoked, read plan.md and sprint-log.md and display:

```
Execution Plan: {name}
Branch: exec-plan/{name}

Milestones:
  [x] M1: {title} — PASS (eval 1/1)
  [x] M2: {title} — PASS (eval 2/3)
  [ ] M3: {title} — IN_PROGRESS
  [ ] M4: {title} — NOT STARTED

Current Sprint: M3 - {title}
  Contract: {N} acceptance criteria
  Eval attempts: 0/3

Decisions: {N} logged | Surprises: {N} | Evidence: {N} entries
```

## LIST Command

```bash
ls ~/tools/exec-plans/
# For each, check sprint-log.md for latest status
```
