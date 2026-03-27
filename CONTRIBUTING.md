# Contributing

## Adding a New Agent

Create `agents/your-agent.md` with the agent's system prompt:

```markdown
# Your Agent Name

Your agent's instructions and workflow.

## When to Use
- Scenario 1
- Scenario 2

## Workflow
1. Step 1
2. Step 2
```

## Adding a New Skill

Create `skills/your-skill/SKILL.md`:

```markdown
---
name: your-skill
description: "What this skill does"
---

# /your-skill - Skill Title

Instructions for when this skill is invoked.
```

## Adding a New Command

Create `commands/your-command.md` with the slash command definition.

## Guidelines

- Keep skills focused on a single purpose
- Include usage examples in skill descriptions
- Test your agent/skill locally before submitting
- Do not include API keys, tokens, or personal information
