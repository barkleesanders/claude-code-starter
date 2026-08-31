---
name: prd
user-invocable: true
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
---

# PRD Generator

Create detailed Product Requirements Documents that are clear, actionable, and suitable for implementation.

---

## The Job

1. Receive a feature description
2. **Self-clarify:** Ask yourself 3-5 critical questions and answer them based on context
3. Generate a structured PRD based on your answers
4. Save to `/tasks/prd-[feature-name].md`

**Important:** 
- Do NOT ask the user questions. Answer them yourself using available context.
- Do NOT start implementing. Just create the PRD.

---

## Step 1: Self-Clarification

Before generating the PRD, ask yourself these questions and write your answers. This ensures you've thought through the problem:

1. **Problem/Goal:** What problem does this solve? Why now?
2. **Core Functionality:** What are the 2-3 key actions this enables?
3. **Scope/Boundaries:** What should this explicitly NOT do?
4. **Success Criteria:** How do we verify it's working?
5. **Constraints:** What technical/time constraints exist?

### Format Your Thinking:

```
## Self-Clarification

1. **Problem/Goal:** [Your answer based on the request and codebase context]
2. **Core Functionality:** [Your answer]
3. **Scope/Boundaries:** [Your answer - be conservative, prefer smaller scope]
4. **Success Criteria:** [Your answer - must be verifiable]
5. **Constraints:** [Your answer - note any mentioned constraints like "no DB migrations"]
```

Use context from: the request, AGENTS.md, existing code patterns, and any reports/analysis provided.

---

## Step 2: PRD Structure

Generate the PRD with these sections:

### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

### 2. Goals
Specific, measurable objectives (bullet list).

### 3. Tasks
Each task needs:
- **Title:** Short descriptive name
- **Description:** What needs to be done
- **Acceptance Criteria:** Verifiable checklist of what "done" means

Each task should be small enough to implement in one focused session.

**Format:**
```markdown
### T-001: [Title]
**Description:** [What to implement]

**Acceptance Criteria:**
- [ ] Specific verifiable criterion
- [ ] Another criterion
- [ ] Quality checks pass
- [ ] **[UI tasks only]** Verify in browser
```

**Important:** 
- Acceptance criteria must be verifiable, not vague. "Works correctly" is bad. "Button shows confirmation dialog before deleting" is good.
- **For any task with UI changes:** Always include browser verification as acceptance criteria.

### 4. Functional Requirements
Numbered list of specific functionalities:
- "FR-1: The system must allow users to..."
- "FR-2: When a user clicks X, the system must..."

Be explicit and unambiguous.

### 5. Non-Goals (Out of Scope)
What this feature will NOT include. Critical for managing scope.

### 6. Technical Considerations (Optional)
- Known constraints or dependencies
- Integration points with existing systems
- Performance requirements

### 7. Success Metrics
How will success be measured?

### 8. Open Questions
Remaining questions or areas needing clarification.

---

## Writing for Agents

The PRD reader may be an AI agent. Therefore:

- Be explicit and unambiguous
- Avoid jargon or explain it
- Provide enough detail to understand purpose and core logic
- Number requirements for easy reference
- Use concrete examples where helpful

---

## Output

- **Format:** Markdown (`.md`)
- **Location:** `/tasks/`
- **Filename:** `prd-[feature-name].md` (kebab-case)

---

## Example PRD

```markdown
# PRD: Task Priority System

## Introduction

Add priority levels to tasks so users can focus on what matters most.

## Goals

- Allow assigning priority (high/medium/low) to any task
- Provide clear visual differentiation between priority levels
- Enable filtering by priority

## Tasks

### T-001: Add priority field to database
**Description:** Add priority column to tasks table for persistence.

**Acceptance Criteria:**
- [ ] Add priority column: 'high' | 'medium' | 'low' (default 'medium')
- [ ] Generate and run migration successfully
- [ ] Quality checks pass

### T-002: Display priority indicator on task cards
**Description:** Show colored priority badge on each task card.

**Acceptance Criteria:**
- [ ] Each task card shows colored badge (red=high, yellow=medium, gray=low)
- [ ] Priority visible without hovering
- [ ] Quality checks pass
- [ ] Verify in browser

### T-003: Add priority selector to task edit
**Description:** Allow changing task priority in edit modal.

**Acceptance Criteria:**
- [ ] Priority dropdown in task edit modal
- [ ] Shows current priority as selected
- [ ] Saves on selection change
- [ ] Quality checks pass
- [ ] Verify in browser

## Functional Requirements

- FR-1: Add `priority` field to tasks table
- FR-2: Display colored priority badge on each task card
- FR-3: Include priority selector in task edit modal

## Non-Goals

- No priority-based notifications
- No automatic priority assignment

## Success Metrics

- Users can change priority in <2 clicks
- High-priority tasks immediately visible
```

---

## Checklist

Before saving the PRD:

- [ ] Completed self-clarification (answered all 5 questions)
- [ ] Tasks are small and specific (completable in one session each)
- [ ] Acceptance criteria are verifiable (not vague)
- [ ] Functional requirements are numbered and unambiguous
- [ ] Non-goals section defines clear boundaries
- [ ] Saved to `/tasks/prd-[feature-name].md`
