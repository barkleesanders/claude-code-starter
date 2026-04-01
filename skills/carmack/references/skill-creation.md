# Creating & Editing Skills

Use this guidance when working with SKILL.md files, authoring new skills, or improving existing ones.

## Core Principles

**1. Skills Are Prompts** -- All prompting best practices apply. Be clear, be direct. Assume Claude is smart -- only add context Claude doesn't have.

**2. Standard Markdown Format** -- YAML frontmatter + markdown body. No XML tags.

```markdown
---
name: my-skill-name
description: What it does and when to use it
---

# My Skill Name

## Quick Start
Immediate actionable guidance...

## Instructions
Step-by-step procedures...

## Examples
Concrete usage examples...
```

**3. Progressive Disclosure** -- Keep SKILL.md under 500 lines. Split detailed content into reference files. Load only what's needed.

```
my-skill/
├── SKILL.md              # Entry point (required)
├── reference.md          # Detailed docs (loaded when needed)
├── examples.md           # Usage examples
└── scripts/              # Utility scripts (executed, not loaded)
```

**4. Effective Descriptions** -- Include both what the skill does AND when to use it. Write in third person.

```yaml
# Good:
description: Extracts text and tables from PDF files, fills forms, merges documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.

# Bad:
description: Helps with documents
```

## Required Frontmatter

| Field | Required | Max Length | Description |
|-------|----------|------------|-------------|
| `name` | Yes | 64 chars | Lowercase letters, numbers, hyphens only |
| `description` | Yes | 1024 chars | What it does AND when to use it |
| `allowed-tools` | No | - | Tools Claude can use without asking |
| `model` | No | - | Specific model to use |

## Naming Conventions

Use **gerund form** (verb + -ing):
- `processing-pdfs`
- `reviewing-code`
- `generating-commit-messages`

Avoid: `helper`, `utils`, `tools`, `anthropic-*`, `claude-*`

## Creating a New Skill

**Step 1:** Choose type -- Simple (single SKILL.md under 500 lines) or Progressive (SKILL.md + reference files).

**Step 2:** Create SKILL.md:

```markdown
---
name: your-skill-name
description: [What it does]. Use when [trigger conditions].
---

# Your Skill Name

## Quick Start

[Immediate actionable example]

## Instructions

[Core guidance]

## Examples

**Example 1:**
Input: [description]
Output:
```
[result]
```

## Guidelines

- [Constraint 1]
- [Constraint 2]
```

**Step 3:** Add reference files if needed (keep one level deep from SKILL.md).

**Step 4:** Test with real usage. Observe where Claude struggles. Refine. Test with Haiku, Sonnet, and Opus.

## Audit Checklist

- [ ] Valid YAML frontmatter (name + description)
- [ ] Description includes trigger keywords
- [ ] Uses standard markdown headings (not XML tags)
- [ ] SKILL.md under 500 lines
- [ ] References one level deep
- [ ] Examples are concrete, not abstract
- [ ] Consistent terminology
- [ ] No time-sensitive information
- [ ] Scripts handle errors explicitly

## Anti-Patterns to Avoid

- **XML tags in body** -- Use markdown headings instead
- **Vague descriptions** -- Be specific with trigger keywords
- **Deep nesting** -- Keep references one level from SKILL.md
- **Too many options** -- Provide a default with escape hatch
- **Windows paths** -- Always use forward slashes
- **Punting to Claude** -- Scripts should handle errors
- **Time-sensitive info** -- Use "old patterns" section instead

For extended reference docs, see `~/.claude/skills/create-agent-skills/references/`.
