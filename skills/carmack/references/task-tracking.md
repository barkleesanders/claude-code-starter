# Task Tracking (PRD -> prd.json)

The `tasks` workflow converts PRD markdown documents into machine-executable `prd.json` format for the ralph execution loop.

## The Job

1. Read the PRD markdown file
2. Extract tasks (from Tasks section or User Stories)
3. **Explode each task into granular, machine-verifiable sub-tasks**
4. Order by dependencies (schema -> backend -> UI -> tests)
5. Output to `prd.json`

**Autonomous mode:** Do not ask questions. Generate prd.json immediately.

## Critical: Agent-Testable Tasks

Every task must be **autonomously verifiable** by an AI agent without human intervention.

**BAD - Vague/subjective:**
- "Works correctly"
- "Review the configuration"
- "Document the findings"
- "Verify it looks good"

**GOOD - Machine-verifiable:**
- "Run `npm run typecheck` - exits with code 0"
- "Navigate to /signup - page loads without console errors"
- "Click submit button - form submits and redirects to /dashboard"
- "File `src/auth/config.ts` contains `redirectUrl: '/onboarding'`"
- "API response status is 200 and body contains `{ success: true }`"

## Acceptance Criteria Patterns

| Type | Pattern | Example |
|------|---------|---------|
| Command | "Run `[cmd]` - exits with code 0" | "Run `timeout 120 npx vitest run src/path/test.ts` - exits with code 0" |
| File check | "File `[path]` contains `[string]`" | "File `middleware.ts` contains `clerkMiddleware`" |
| Browser nav | "agent-browser: open `[url]` - [expected result]" | "agent-browser: open /login - SignIn component renders" |
| Browser action | "agent-browser: click `[element]` - [expected result]" | "agent-browser: click 'Submit' - redirects to /dashboard" |
| Console check | "agent-browser: console shows no errors" | |
| API check | "GET/POST `[url]` returns `[status]` with `[body]`" | "POST /api/signup returns 200" |
| Screenshot | "agent-browser: screenshot shows `[element]` visible" | |

## prd.json Output Format

```json
{
  "project": "Project Name",
  "branchName": "compound/[feature-name]",
  "description": "[One-line description from PRD]",
  "tasks": [
    {
      "id": "T-001",
      "title": "[Specific action verb] [specific target]",
      "description": "[1-2 sentences: what to do and why]",
      "acceptanceCriteria": [
        "Specific machine-verifiable criterion with expected outcome",
        "Another criterion with pass/fail condition",
        "Run `npm run typecheck` - exits with code 0"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Task Granularity Rules

**Target: 8-15 tasks per PRD.** If you have fewer than 6, split further.

**One concern per task:**

| Concern | Separate Task |
|---------|---------------|
| Navigate to page | T-001 |
| Check for errors | T-002 |
| Test input validation | T-003 |
| Test form submission | T-004 |
| Verify redirect | T-005 |
| Test mobile viewport | T-006 |
| Implement fix | T-007 |
| Verify fix on desktop | T-008 |
| Verify fix on mobile | T-009 |

**Never combine "find the problem" with "fix the problem"** in one task.

## Priority Ordering

1. **Investigation tasks** -- priority 1-3 (understand before changing)
2. **Schema/database changes** -- priority 4-5
3. **Backend logic changes** -- priority 6-7
4. **UI component changes** -- priority 8-9
5. **Verification tasks** -- priority 10+

Lower priority number = executed first.

## Process

1. Read the PRD file
2. Extract high-level tasks (T-001, US-001, FR-1, etc.)
3. Explode each into granular tasks with boolean pass/fail criteria
4. Order by dependencies
5. Generate prd.json -- **do NOT wait for user confirmation, save immediately**

## prd.json Checklist

- [ ] **8-15 tasks** generated (not 3-5)
- [ ] Each task does **ONE thing**
- [ ] Investigation separated from implementation
- [ ] Every criterion is **boolean pass/fail**
- [ ] No vague words: "review", "identify", "document", "verify it works"
- [ ] Commands specify expected exit code
- [ ] Browser actions specify expected result
- [ ] All tasks have `passes: false`
- [ ] Priority order reflects dependencies

## bd -- Beads Task Tracking

For ongoing project-level task tracking (not feature execution loops), use `bd`:

```bash
bd create "Investigate auth timeout" -p 1   # Create priority-1 task
bd list                                      # Show all tasks
bd ready                                     # Show unblocked tasks
bd update <id> --status=in_progress          # Claim a task
bd close <id>                                # Complete a task
bd close <id1> <id2> ...                     # Close multiple at once
bd dep add <child> <parent>                  # Add dependency
bd show <id>                                 # Detailed view with deps
bd stats                                     # Project statistics
```
