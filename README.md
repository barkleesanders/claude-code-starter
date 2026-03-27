# Claude Code Starter

Production-ready Claude Code configuration with battle-tested agents, skills, hooks, and commands.

---

## Quick Start

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/claude-code-starter.git

# Run the install script
./install.sh
```

## What's Included

### Core Agents (35)

| Agent | Purpose | Invoke |
|-------|---------|--------|
| `systematic-debugging` | 5-phase bug investigation with evidence checkpoints | `/debug [issue]` |
| `carmack-mode-engineer` | Deep debugging with repro harnesses & debugger | `/carmack [issue]` |
| `ship-working-code` | Safe deployment with quality gates | `/ship` |
| `git-safety` | Scan for secrets, clean git history, prevent leaks | `/git-safety` |
| `git-preflight` | Pre-flight checks before git commands | `/git-preflight` |
| `code-reviewer` | AI-powered code review | `/code-review` |
| + 29 more specialized agents | See `agents/` directory | |

### Skills (45+)

| Skill | Description |
|-------|-------------|
| `/debug` | Launch systematic-debugging for bug reports, test failures |
| `/carmack` | Launch carmack-mode for race conditions, perf issues |
| `/ship` | Deploy with lint, test, security checks |
| `/safety-audit` | Tiered production safety checks |
| `/git-safety` | Scan for secrets, clean history |
| `/git-preflight` | Pre-flight git checks |
| `/ralph` | Autonomous feature implementation |
| `/prd` | Product requirements document generation |
| `/brainstorming` | AI-assisted brainstorming |
| + many more | See `skills/` directory |

### Commands (21)

Slash commands for common workflows. See `commands/` directory.

### Hooks

- **SessionStart** - Initialize task tracking, run config backup
- **PreToolUse** - Bash command safety checks
- **SubagentStop** - Check for saved debug sessions

## Agent Details

### systematic-debugging

Enforces a disciplined 5-phase workflow:

1. **Root Cause Investigation** - Gather evidence, no assumptions
2. **Pattern Analysis** - Find similar issues, related code
3. **Hypothesis & Testing** - Form and test theories
4. **Implementation & Verification** - Fix with approval checkpoint
5. **Session Persistence** - Save state for resumability

**Best for:** Bug reports, test failures, "it worked before" issues

### carmack-mode-engineer

Empirical debugging in the style of John Carmack:

- Builds reproduction harnesses in `tools/repro/`
- Attaches debuggers autonomously (lldb)
- Instruments code without asking for logs
- Takes complete ownership of investigation
- Creates minimal, surgical fixes

**Best for:** Race conditions, memory leaks, performance issues, intermittent failures

### ship-working-code

Production deployment with comprehensive quality gates:

- Repository verification & merge conflict resolution
- Intelligent lint fixing (automatic + AI-powered)
- Security audits & test execution
- Multi-platform deployment with health checks
- Rollback capability

**Best for:** When you're ready to deploy

## Safety Audit Tiers

```
/safety-audit           # Tier 1 (default) - Critical checks
/safety-audit tier2     # Tier 2 - Investigation
/safety-audit tier3     # Tier 3 - Deep analysis
/safety-audit full      # All tiers
```

| Tier | Agent | Checks |
|------|-------|--------|
| 1 | ship-working-code | Silent failures, security, tests |
| 2 | systematic-debugging | Blind spots, test quality, rate limits |
| 3 | carmack-mode-engineer | Code archaeology, critical paths |

## Debug Session Persistence

Investigations are saved to `tools/debug-sessions/{issue-name}/`:

```
tools/debug-sessions/
  auth-timeout/
    auth-timeout-state.md       # Current phase, findings
    auth-timeout-evidence.md    # Logs, traces, data
    auth-timeout-hypothesis.md  # Tested theories
```

Resume any investigation: "Resume the auth-timeout investigation"

## Installation

### Automatic

```bash
./install.sh
```

### Manual

Copy to your Claude config directory:

```bash
# Agents
cp agents/*.md ~/.claude/agents/

# Skills
cp -r skills/* ~/.claude/skills/

# Commands
mkdir -p ~/.claude/commands
cp commands/*.md ~/.claude/commands/

# CLAUDE.md (merge with existing or replace)
cp CLAUDE.md ~/.claude/CLAUDE.md

# Settings (review and merge hooks/permissions into your settings.json)
cat settings.json
```

## File Structure

```
claude-code-starter/
├── README.md
├── install.sh
├── settings.json                    # Claude Code settings (permissions, hooks, plugins)
├── CLAUDE.md                        # Quick reference config
├── agents/                          # 35 specialized agent definitions
│   ├── systematic-debugging.md
│   ├── carmack-mode-engineer.md
│   ├── ship-working-code.md
│   └── ...
├── skills/                          # 45+ skill definitions
│   ├── debug/skill.md
│   ├── carmack/skill.md
│   ├── ship/skill.md
│   └── ...
├── commands/                        # 21 slash commands
│   ├── browser.md
│   ├── changelog.md
│   └── ...
├── scripts/
│   └── backup-claude-config.sh      # Auto-backup script
└── hooks-examples/
    └── settings-hooks.json          # Example hook configurations
```

## Customization

### Adding New Agents

Create `~/.claude/agents/your-agent.md`:

```markdown
# Your Agent Name

Your agent's system prompt and instructions here.

## When to Use
- Scenario 1
- Scenario 2

## Workflow
1. Step 1
2. Step 2
```

### Adding New Skills

Create `~/.claude/skills/your-skill/skill.md`:

```markdown
---
name: your-skill
description: "What this skill does"
---

# /your-skill - Skill Title

Instructions for when this skill is invoked.
```

## License

MIT
