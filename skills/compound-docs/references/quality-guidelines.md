# Quality Guidelines & Error Handling

## Success Criteria

Documentation is successful when ALL of the following are true:

- YAML frontmatter validated (all required fields, correct formats)
- File created in docs/solutions/[category]/[filename].md
- Enum values match schema.yaml exactly
- Code examples included in solution section
- Cross-references added if related issues found
- User presented with decision menu and action confirmed

## Error Handling

**Missing context:**

- Ask user for missing details
- Don't proceed until critical info provided

**YAML validation failure:**

- Show specific errors
- Present retry with corrected values
- BLOCK until valid

**Similar issue ambiguity:**

- Present multiple matches
- Let user choose: new doc, update existing, or link as duplicate

**Module not in modules documentation:**

- Warn but don't block
- Proceed with documentation
- Suggest: "Add [Module] to modules documentation if not there"

## Execution Guidelines

**MUST do:**
- Validate YAML frontmatter (BLOCK if invalid per Step 5 validation gate)
- Extract exact error messages from conversation
- Include code examples in solution section
- Create directories before writing files (`mkdir -p`)
- Ask user and WAIT if critical context missing

**MUST NOT do:**
- Skip YAML validation (validation gate is blocking)
- Use vague descriptions (not searchable)
- Omit code examples or cross-references

## Quality Checklist

**Good documentation has:**

- Exact error messages (copy-paste from output)
- Specific file:line references
- Observable symptoms (what you saw, not interpretations)
- Failed attempts documented (helps avoid wrong paths)
- Technical explanation (not just "what" but "why")
- Code examples (before/after if applicable)
- Prevention guidance (how to catch early)
- Cross-references (related issues)

**Avoid:**

- Vague descriptions ("something was wrong")
- Missing technical details ("fixed the code")
- No context (which version? which file?)
- Just code dumps (explain why it works)
- No prevention guidance
- No cross-references

## Example Scenario

**User:** "That worked! The N+1 query is fixed."

**Skill activates:**

1. **Detect confirmation:** "That worked!" triggers auto-invoke
2. **Gather context:**
   - Module: Brief System
   - Symptom: Brief generation taking >5 seconds, N+1 query when loading email threads
   - Failed attempts: Added pagination (didn't help), checked background job performance
   - Solution: Added eager loading with `includes(:emails)` on Brief model
   - Root cause: Missing eager loading causing separate database query per email thread
3. **Check existing:** No similar issue found
4. **Generate filename:** `n-plus-one-brief-generation-BriefSystem-20251110.md`
5. **Validate YAML:**
   ```yaml
   module: Brief System
   date: 2025-11-10
   problem_type: performance_issue
   component: rails_model
   symptoms:
     - "N+1 query when loading email threads"
     - "Brief generation taking >5 seconds"
   root_cause: missing_include
   severity: high
   tags: [n-plus-one, eager-loading, performance]
   ```
   Valid.
6. **Create documentation:**
   - `docs/solutions/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md`
7. **Cross-reference:** None needed (no similar issues)

**Output:**

```
Solution documented

File created:
- docs/solutions/performance-issues/n-plus-one-brief-generation-BriefSystem-20251110.md

What's next?
1. Continue workflow (recommended)
2. Add to Required Reading - Promote to critical patterns (critical-patterns.md)
3. Link related issues - Connect to similar problems
4. Add to existing skill - Add to a learning skill (e.g., hotwire-native)
5. Create new skill - Extract into new learning skill
6. View documentation - See what was captured
7. Other
```
