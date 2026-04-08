# Claude Code Starter

Turn Claude Code from a smart assistant into a full engineering team. This repo gives you 35 specialized AI agents, 48 skills, and 21 commands that handle everything from deep debugging to production deployment — out of the box.

## Why This Repo Is Powerful

Out of the box, Claude Code is a single AI that responds to what you type. With this starter kit installed, it becomes a **team of specialists**:

- **`/carmack`** — A debugging agent modeled after John Carmack. It doesn't ask you for logs — it builds reproduction harnesses, attaches debuggers, instruments code, and finds root causes autonomously. It writes the fix AND the regression test.
- **`/ship`** — A deployment agent that runs 12+ quality gates before your code hits production: lint, tests, security audit, bundle verification, health checks, and rollback preparation. It catches the bugs you'd find at 2am.
- **`/debug`** — A 5-phase systematic debugging agent that refuses to guess. It gathers evidence, forms hypotheses, tests them, and only implements fixes after proving the root cause.
- **35 agents total** — Code reviewers (Rails, Python, TypeScript), security auditors, architecture strategists, performance oracles, design iterators, and more. Each one is a specialist that knows its domain deeply.
- **Safety hooks** — Pre-commit checks that prevent you from pushing secrets, destructive bash commands that require confirmation, and automatic task tracking across sessions.
- **Session persistence** — Debug investigations survive across conversations. Start debugging today, resume tomorrow with full context.

This isn't a collection of prompts. It's a battle-tested engineering workflow that catches real production bugs, prevents real security issues, and ships real code safely.

---

## Getting Started (First-Time Setup)

You don't need to know the terminal. Just follow these 3 steps:

### Step 1: Open Claude Code

Open **Claude Code** in your terminal, VS Code, or the desktop app. If you don't have it yet, install it from [claude.ai/code](https://claude.ai/code).

### Step 2: Tell Claude to Install It

Paste this into Claude Code:

```
Clone https://github.com/barkleesanders/claude-code-starter.git and run the install script to set up all the agents, skills, and commands
```

Claude will clone the repo, run `./install.sh`, and walk you through the setup. When it asks about CLAUDE.md and settings.json, choose to install them (option 1 or 3).

### Step 3: Verify It Works

After installation, restart Claude Code and type:

```
/carmack verify that the claude-code-starter installation is working correctly — check that the agents, skills, and commands are all loaded
```

Carmack will scan your `~/.claude/` directory and confirm everything is installed. If anything is missing, it will fix it for you.

That's it. You now have 35 agents, 48 skills, and 21 commands ready to use.

### Your First Real Command

Navigate to any project and try:

```
/carmack what are the top 3 bugs or issues in this codebase?
```

Or if you're ready to deploy:

```
/ship
```

---

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
| `/token-usage` | Analyze token usage across all projects and sessions |
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

## Token Usage Tracking

Track how many tokens your Claude Code sessions consume across all projects:

```
/token-usage              # All time usage
/token-usage 7            # Last 7 days
/token-usage 2025-01-15   # Since specific date
```

Or run the script directly:

```bash
python3 ~/.claude/skills/token-usage/token-usage.py
SINCE_DAYS=7 python3 ~/.claude/skills/token-usage/token-usage.py
```

Generates a report at `~/.claude/usage/token_report.md` with:
- Total tokens across all projects and sessions
- Per-project breakdown (input, cache, output)
- Top 25 costliest sessions with first prompt context
- Subagent token consumption analysis

All data stays local — nothing is sent anywhere.

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
