# Decision Menu & Integration

## Decision Menu After Capture

After successful documentation, present options and WAIT for user response:

```
Solution documented

File created:
- docs/solutions/[category]/[filename].md

What's next?
1. Continue workflow (recommended)
2. Add to Required Reading - Promote to critical patterns (critical-patterns.md)
3. Link related issues - Connect to similar problems
4. Add to existing skill - Add to a learning skill (e.g., hotwire-native)
5. Create new skill - Extract into new learning skill
6. View documentation - See what was captured
7. Other
```

### Option 1: Continue workflow

- Return to calling skill/workflow
- Documentation is complete

### Option 2: Add to Required Reading (PRIMARY PATH FOR CRITICAL PATTERNS)

User selects this when:
- System made this mistake multiple times across different modules
- Solution is non-obvious but must be followed every time
- Foundational requirement (Rails, Rails API, threading, etc.)

Action:
1. Extract pattern from the documentation
2. Format as WRONG vs CORRECT with code examples
3. Add to `docs/solutions/patterns/critical-patterns.md`
4. Add cross-reference back to this doc
5. Confirm: "Added to Required Reading. All subagents will see this pattern before code generation."

### Option 3: Link related issues

- Prompt: "Which doc to link? (provide filename or describe)"
- Search docs/solutions/ for the doc
- Add cross-reference to both docs
- Confirm: "Cross-reference added"

### Option 4: Add to existing skill

User selects this when the documented solution relates to an existing learning skill:

Action:
1. Prompt: "Which skill? (hotwire-native, etc.)"
2. Determine which reference file to update (resources.md, patterns.md, or examples.md)
3. Add link and brief description to appropriate section
4. Confirm: "Added to [skill-name] skill in [file]"

Example: For Hotwire Native Tailwind variants solution:
- Add to `hotwire-native/references/resources.md` under "Project-Specific Resources"
- Add to `hotwire-native/references/examples.md` with link to solution doc

### Option 5: Create new skill

User selects this when the solution represents the start of a new learning domain:

Action:
1. Prompt: "What should the new skill be called? (e.g., stripe-billing, email-processing)"
2. Run `python3 .claude/skills/skill-creator/scripts/init_skill.py [skill-name]`
3. Create initial reference files with this solution as first example
4. Confirm: "Created new [skill-name] skill with this solution as first example"

### Option 6: View documentation

- Display the created documentation
- Present decision menu again

### Option 7: Other

- Ask what they'd like to do

---

## Integration Points

**Invoked by:**
- /compound command (primary interface)
- Manual invocation in conversation after solution confirmed
- Can be triggered by detecting confirmation phrases like "that worked", "it's fixed", etc.

**Invokes:**
- None (terminal skill -- does not delegate to other skills)

**Handoff expectations:**
All context needed for documentation should be present in conversation history before invocation.
