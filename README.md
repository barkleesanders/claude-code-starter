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
Clone https://github.com/barkleesanders/claude-code-starter.git and run the install script to set up all the agents, skills, commands, and CLI tools
```

Claude will clone the repo and run `./install.sh`. The script:
- Copies all agents/skills/commands to `~/.claude/`
- Bootstraps Homebrew if missing (prompts once for your password)
- Installs every CLI tool the skills depend on (`gh`, `node`, `ogrep`, `agent-browser`, `wrangler`, etc.)
- Asks once about merging `CLAUDE.md` and `settings.json` — choose option 1 or 3.

Or run it directly in your terminal:

```bash
git clone https://github.com/barkleesanders/claude-code-starter.git && cd claude-code-starter && ./install.sh
```

### Step 3: Verify It Works

After installation, restart Claude Code and type:

```
/carmack verify that the claude-code-starter installation is working correctly — check that the agents, skills, and commands are all loaded
```

Carmack will scan your `~/.claude/` directory and confirm everything is installed. If anything is missing, it will fix it for you.

That's it. You now have **35 agents, 51 skills, and 26 commands** ready to use, plus an idempotent CLI installer (`install-tools.sh`) that brings in `bd`, `gh`, `node`, `ogrep`, `agent-browser`, `wrangler`, `vercel`, `rclone`, `ffmpeg`, and more. See [Installation](#installation) below for details.

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

## Self-Improvement System

Claude Code gets smarter every session through five feedback loops that capture mistakes and surface them as reviewable patterns on the next `/carmack` invocation.

### What gets captured automatically

| Hook | Captures | Log file |
|------|----------|----------|
| `PostToolUse` | Tool errors (any `is_error:true`) | `~/.claude/tool-errors.jsonl` |
| `UserPromptSubmit` | Correction ("don't do X") and success ("perfect") phrases | `~/.claude/feedback-pending.jsonl` |
| `PostToolUse Skill\|Agent` | Skill and subagent invocations + outcome | `~/.claude/skill-usage.jsonl` |

### What gets surfaced

On every `/carmack` invocation, a single scanner (`~/.claude/skills/carmack/tools/auto-improve.sh`) runs all five checks and prints a compact summary:

- **Novel tool errors** → `tool-errors-pending.md` — Claude classifies each into `shared/tool-error-recovery.md`
- **User behavioral feedback** → `feedback-pending.md` — Claude saves as memory entries (feedback type)
- **Skill usage report** — flags skills with >30% error rate (weekly, needs 5+ invocations)
- **Skill drift** — validates commands/paths in every `skill.md` still resolve (weekly, allowlist-backed)
- **Memory search** — `memory-search.sh <topic>` greps both `MEMORY.md` and `bd memories` before starting work

### Token & efficiency gains

Measured against a real VPS long-session workload before/after today's changes:

| Metric | Before | After | Gain |
|--------|-------:|------:|------|
| Context ceiling (featherless GLM-4.7) | 32,768 | 48,000 | +46% |
| Tokens sent to model at turn 5 | ~44K (near ceiling, compaction deferred) | 46,752 with 231,863 of history compressed in | **5x effective context** |
| LCM mode default | `deferred` (no-op boundary writes) | `inline` (real summarization before next prompt) | compaction actually shrinks |
| Tool-error recovery catalog | 9 patterns | 20 patterns | +11 from scanning 1,141 transcripts (3,256 errors classified) |
| Blind-spot reference | — | 10 patterns | covers schema-validate-before-restart, self-upgrade traps, adjacent-system breakage |
| Stop-hook checks | 3 (tasks, errors, request coverage) | 5 (adds real-traffic verification, fix-all-issues rule) | catches silent infra "done" |

**Per-session savings** on long debugging workloads: typical 50-turn session now stays under the 48K ceiling indefinitely; previously would crash at turn 2-3 with "context exceeded." For shorter sessions, the tool-error catalog saves roughly 2–5K tokens per known failure pattern (no re-diagnosis needed).

### Safe JSON config mutation

New helper replaces hand-rolled python-heredoc patches:

```bash
~/.claude/skills/carmack/tools/json-patch.sh <config> '<jq-expr>' \
  --validate-cmd "<cmd>" --restart <systemd-service>
```

Auto-backup + jq patch + JSON validate + optional validate-cmd + optional systemd restart + **auto-rollback** on any failure.

### Usage

```bash
# See what's accumulated since last review
~/.claude/skills/carmack/tools/auto-improve.sh

# After classifying pending items into the catalog, archive the logs
~/.claude/skills/carmack/tools/auto-improve.sh --clear

# Skill-specific
~/.claude/skills/carmack/tools/skill-drift-check.sh
~/.claude/skills/carmack/tools/memory-search.sh openclaw
```

The system is agent-native: every learning loop compounds into Claude's next session without manual curation.

---

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

### One-line install (recommended)

```bash
git clone https://github.com/barkleesanders/claude-code-starter.git && cd claude-code-starter && ./install.sh
```

That single command:

1. **Copies** 35 agents, 51 skills, 26 commands to `~/.claude/`
2. **Installs/merges** `CLAUDE.md` and `settings.json`
3. **Bootstraps Homebrew** if missing (you'll be prompted for your macOS password once)
4. **Installs all 13 CLI tools** in dependency order: `bd`, `jq`, `node`, `gh`, `ripgrep`, `rust`, `ogrep`, `agent-browser`, `wrangler`, `vercel`, `rclone`, `ffmpeg`, `eas-cli`
5. **Adds Homebrew to your shell rc** (zsh/bash) for future sessions
6. **Auto-inits `.beads/`** in the current repo if it's a git repo

Skip the CLI tool install with `./install.sh --no-tools`.

The script is idempotent — safe to re-run. It detects what's already installed and only runs the missing pieces.

### CLI Tools Installer

The agents and skills reference ~14 external CLIs. `install-tools.sh` installs them all by tier:

```bash
./install-tools.sh              # Install everything (default)
./install-tools.sh --check      # Report what's missing, install nothing
./install-tools.sh --core       # Just the mandatory ones (bd, gh, jq, node)
./install-tools.sh --search     # Code/doc search (ripgrep, ogrep)
./install-tools.sh --browser    # Browser automation (agent-browser)
./install-tools.sh --deploy     # Cloud clients (wrangler, vercel, rclone)
./install-tools.sh --media      # Media tools (ffmpeg)
./install-tools.sh --optional   # eas-cli, codex, asc
```

Idempotent — safe to re-run. Detects what's already installed via `command -v` and only runs the missing installs.

#### What gets installed

| Tier | Tool | Source | Used by |
|------|------|--------|---------|
| **core** | `bd` (beads) | `brew install steveyegge/tap/beads` | Mandatory task tracking (CLAUDE.md rule) |
| **core** | `gh` | `brew install gh` | GitHub API rate-limit rule |
| **core** | `jq` | `brew install jq` | JSON in many skill scripts |
| **core** | `node` | `brew install node` | Provides `npm` for the rest |
| **search** | `rg` (ripgrep) | `brew install ripgrep` | Fast code search |
| **search** | `ogrep` | `cargo install osgrep` | AST-aware code search (CLAUDE.md) |
| **search** | `qmd` | manual — see upstream | Local semantic doc search (no public install identified) |
| **browser** | `agent-browser` | `npm i -g agent-browser` | Headless browser skill |
| **deploy** | `wrangler` | `npm i -g wrangler` | Cloudflare Workers deploys |
| **deploy** | `vercel` | `npm i -g vercel` | Vercel deploys |
| **deploy** | `rclone` | `brew install rclone` | Cloud storage skill |
| **media** | `ffmpeg` | `brew install ffmpeg` | avatar-video, video skills |
| **optional** | `eas-cli` | `npm i -g eas-cli` | Expo builds |
| **optional** | `codex` | per `skills/codex/SKILL.md` | codex-chat / codex-rescue skills |
| **optional** | `asc` | per `skills/ios-ship/SKILL.md` | App Store Connect (iOS shipping) |

> **Homebrew bootstrap**: macOS users without `brew` will see one-liner instructions on first run. Install Homebrew once interactively, then re-run `./install-tools.sh`.

### Manual

Copy to your Claude config directory:

```bash
# Agents
cp agents/*.md ~/.claude/agents/

# Skills
cp -r skills/* ~/.claude/skills/

# Commands (top-level + workflows subdirectory)
mkdir -p ~/.claude/commands
cp commands/*.md ~/.claude/commands/
cp -r commands/workflows ~/.claude/commands/

# CLAUDE.md (merge with existing or replace)
cp CLAUDE.md ~/.claude/CLAUDE.md

# Settings (review and merge hooks/permissions into your settings.json)
cat settings.json

# CLI tools (do this last)
./install-tools.sh
```

## File Structure

```
claude-code-starter/
├── README.md
├── install.sh                       # Installs agents/skills/commands + offers CLI tools
├── install-tools.sh                 # Installs the ~14 external CLIs (idempotent, tiered)
├── settings.json                    # Claude Code settings (permissions, hooks, plugins)
├── CLAUDE.md                        # Quick reference config
├── agents/                          # 35 specialized agent definitions
│   ├── systematic-debugging.md
│   ├── carmack-mode-engineer.md
│   ├── ship-working-code.md
│   └── ...
├── skills/                          # 51 skill definitions
│   ├── debug/skill.md
│   ├── carmack/skill.md
│   ├── ship/skill.md
│   └── ...
├── commands/                        # 26 slash commands (incl. workflows/)
│   ├── browser.md
│   ├── changelog.md
│   └── workflows/                   # work, plan, review, brainstorm, compound
├── beads-formulas/                  # Workflow templates (records-request, ship-deploy, …)
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
