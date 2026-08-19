---
name: compound-docs
user-invocable: true
description: Capture solved problems as categorized documentation with YAML frontmatter for fast lookup
allowed-tools:
  - Read
  - Write
  - Bash
  - Grep
model: inherit
preconditions:
  - Problem has been solved (not in-progress)
  - Solution has been verified working
---

# compound-docs Skill

**Purpose:** Automatically document solved problems to build searchable institutional knowledge with category-based organization (enum-validated problem types).

**Organization:** Single-file architecture -- each problem documented as one markdown file in its symptom category directory (e.g., `docs/solutions/performance-issues/n-plus-one-briefs.md`). Files use YAML frontmatter for metadata and searchability.

## Process Overview

Execute the 7-step capture process. Read `capture-process.md` for full step details.

| Step | What | Blocking? |
|------|------|-----------|
| 1 | Detect confirmation ("that worked", "it's fixed", `/doc-fix`) | Yes |
| 2 | Gather context (module, symptom, root cause, solution) | Yes -- ask user if missing |
| 3 | Check existing docs for similar issues | No |
| 4 | Generate filename (`[symptom]-[module]-[YYYYMMDD].md`) | Yes |
| 5 | Validate YAML schema against `yaml-schema.md` enums | **BLOCKING GATE** |
| 6 | Create documentation file in category directory | Yes |
| 7 | Cross-reference and critical pattern detection | No |

**After capture**: Present decision menu from `decision-menu.md` and WAIT for user response.

## Reference Files

Read the relevant reference file for each phase. All files are in `~/.claude/skills/compound-docs/references/`.

| File | Content |
|------|---------|
| `capture-process.md` | Full 7-step process with examples, blocking requirements, and bash commands |
| `yaml-schema.md` | YAML frontmatter schema -- required fields, enum values, validation rules, category mapping |
| `decision-menu.md` | Post-capture decision menu (7 options), integration points, skill handoff rules |
| `quality-guidelines.md` | Success criteria, error handling, execution guidelines, quality checklist, example scenario |

## Key Rules

**MUST do:**
- Validate YAML frontmatter (BLOCK if invalid per Step 5)
- Extract exact error messages from conversation
- Include code examples in solution section
- Create directories before writing files (`mkdir -p`)
- Ask user and WAIT if critical context missing

**MUST NOT do:**
- Skip YAML validation (blocking gate)
- Use vague descriptions (not searchable)
- Omit code examples or cross-references
- Auto-promote to Required Reading (user decides)

## Triggers

- `/compound-docs` or `/doc-fix` command
- Auto-invoke after: "that worked", "it's fixed", "working now", "problem solved", "that did it"
- Only for non-trivial problems (multiple attempts, tricky debugging, non-obvious solution)

## Integration

- **Invoked by**: /compound command, manual invocation, confirmation phrase detection
- **Invokes**: None (terminal skill)
- **Context**: All needed context should be in conversation history before invocation
