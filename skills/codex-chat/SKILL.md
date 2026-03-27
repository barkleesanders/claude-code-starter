---
name: codex-chat
description: Talk to OpenAI Codex CLI from Claude Code. Send prompts, delegate tasks, get second opinions, and run parallel investigations. Use when the user says "ask codex", "codex chat", "talk to codex", "get codex opinion", "codex-chat", or wants to delegate work to Codex for a second perspective.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# Codex Chat — Inter-Agent Communication Bridge

Talk to OpenAI Codex CLI directly from Claude Code. Two modes:

1. **Exec mode** (default) — One-shot: send a prompt, get a response. Clean and reliable.
2. **Tmux mode** — Persistent interactive session for multi-turn conversations.

## Quick Reference

```bash
CX="bash ~/.claude/skills/codex-chat/scripts/codex-tmux.sh"

# One-shot (recommended for most tasks)
$CX exec "What's the best way to implement rate limiting in a Hono Worker?"

# One-shot with file output
$CX exec "Review this code for bugs" -o /tmp/codex-review.txt

# One-shot with specific model
$CX exec "Analyze this algorithm" -m gpt-5.4

# One-shot in a specific directory
$CX exec "Find security issues in this codebase" -C ~/projects/myapp

# Interactive session
$CX start                         # Start Codex in tmux
$CX ask "Explain this error"      # Send + wait + read response
$CX ask "What about edge cases?"  # Follow-up (same session context)
$CX stop                          # End session
```

## When to Use

| Situation | Mode | Why |
|-----------|------|-----|
| Get a second opinion on a bug fix | exec | Quick, isolated, no state needed |
| Code review from a different perspective | exec | One prompt, one response |
| Multi-turn debugging conversation | tmux | Context preserved between turns |
| Parallel investigation (Claude + Codex) | exec | Can run while Claude continues working |
| Delegate a research task | exec | Fire and forget, read result later |
| Compare approaches (Claude vs Codex) | exec | Get both opinions, user picks |

## Instructions

### Mode 1: Exec (One-Shot) — Recommended

Use exec mode for most tasks. It runs `codex exec --full-auto` under the hood.

```bash
CX="bash ~/.claude/skills/codex-chat/scripts/codex-tmux.sh"

# Basic question
$CX exec "What causes CORS errors in Cloudflare Workers and how to fix them?"

# With output file (for large responses)
$CX exec "Review the auth flow in src/worker/routes/ for security issues" -o /tmp/review.txt

# With specific model
$CX exec "Deep analysis of this race condition" -m gpt-5.4

# With working directory (Codex runs in that project)
$CX exec "Run the tests and fix any failures" -C ~/AIVA-Frontend

# Read the response (if using -o flag)
cat /tmp/review.txt
```

**Crafting good prompts for Codex:**

```bash
# Be specific about what you want
$CX exec "I have a Hono Worker that returns 403 on /api/admin/* routes. The admin check uses Clerk publicMetadata.role but the admin user has is_admin=1 in the DB, not Clerk metadata. Write a requireAdmin() function that checks both sources. Output just the function."

# Ask for code review with context
$CX exec "Review this function for bugs. It's supposed to escape HTML for safe injection into <script> tags:

function escapeJsonLd(json) {
  return json.replace(/</g, '\\\\u003c');
}

What's missing?"

# Delegate a research question
$CX exec "What are the current best practices for Vitest configuration to prevent memory leaks from fork workers? Include specific config options."
```

### Mode 2: Tmux (Interactive Session)

Use tmux mode when you need multi-turn conversations with preserved context.

```bash
CX="bash ~/.claude/skills/codex-chat/scripts/codex-tmux.sh"

# Start a session
$CX start
$CX start --model gpt-5.4              # Specific model
$CX start --cd ~/AIVA-Frontend          # Specific directory

# Send a prompt and read the response
$CX ask "Look at src/worker/routes/admin.ts — is the auth check correct?"

# Follow-up (Codex remembers the conversation)
$CX ask "What about the DB fallback? Show me how to add it"

# Another follow-up
$CX ask "Now write a test for that function"

# Check session status
$CX status

# Read the full pane output (all conversation history)
$CX read

# Granular control: send without waiting
$CX send "Start analyzing all the test files"
# ... do other work ...
$CX wait 180   # Wait up to 3 minutes for output to stabilize
$CX read        # Read what it said

# Done
$CX stop
```

### Mode 3: File-Based (For Complex/Long Prompts)

For prompts that are too long for command line, use file-based:

```bash
# Write the question to a file
cat > /tmp/codex-question.txt << 'PROMPT'
I have a React app where the SEO fallback HTML flashes before React mounts.

Here's the current approach in index.html:
<style>body[data-app-loaded="true"] .seo-fallback { display: none; }</style>

The problem: JS loads after HTML renders, causing a flash.

1. What's the correct CSS-only approach?
2. How to handle the no-JS case for accessibility?
3. Show me the complete fix.
PROMPT

# Send it
cat /tmp/codex-question.txt | codex exec --full-auto -o /tmp/codex-reply.txt

# Read the response
cat /tmp/codex-reply.txt
```

## Common Workflows

### Get a Second Opinion on a Bug Fix

```bash
CX="bash ~/.claude/skills/codex-chat/scripts/codex-tmux.sh"

# Claude has proposed a fix — ask Codex to validate
$CX exec "I'm fixing a bug where React fails to mount silently. The root cause is validateClientEnv() throwing at module scope before the hardcoded fallback is reached. My proposed fix: make validateClientEnv() accept a fallbacks parameter and warn instead of throw when a fallback exists. Is this the right approach? Any edge cases I'm missing?"
```

### Parallel Investigation

```bash
# Run Codex investigation in background while Claude continues
bash ~/.claude/skills/codex-chat/scripts/codex-tmux.sh exec \
  "Investigate all useEffect calls in src/react-app/ — which ones are anti-patterns that should be refactored? List file:line for each." \
  -o /tmp/codex-useeffect-audit.txt \
  -C ~/AIVA-Frontend &

# Claude continues working...
# Later, read the result:
cat /tmp/codex-useeffect-audit.txt
```

### Code Review Handoff

```bash
# Send diff to Codex for review
git diff HEAD~1 > /tmp/changes.diff
$CX exec "Review this git diff for security issues, performance problems, and React anti-patterns. Be specific about file:line for each issue found.

$(cat /tmp/changes.diff)"
```

### Ask Codex to Implement Something

```bash
# Codex can write code in its sandbox
$CX exec "Create a rate limiter middleware for Hono that uses Cloudflare KV for storage. It should support per-IP and per-user limits with sliding window. Write the complete implementation." -C ~/AIVA-Frontend -o /tmp/rate-limiter.txt
```

## Tips

1. **Exec mode is almost always better** — tmux adds complexity. Only use tmux for genuine multi-turn conversations.
2. **Be explicit** — Codex doesn't have your conversation context. Include relevant code, error messages, and constraints.
3. **Use `-o` for long responses** — stdout can get noisy. File output is cleaner.
4. **Use `-C` for project context** — Codex can read files in the specified directory.
5. **Timeouts** — Exec mode inherits codex defaults. Tmux wait defaults to 120s.
6. **Model** — Default is gpt-5.4 (from your config). Override with `-m`.

## Auth Management

Codex auth tokens expire. Run `codex login` to re-authenticate when needed.

**When to run**: If you see `refresh_token_reused` or `401 Unauthorized` errors from Codex.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "stdin is not a terminal" | Use `codex exec` not bare `codex` |
| `refresh_token_reused` / 401 | Run `codex login` to refresh tokens |
| Tmux session already exists | `$CX stop` then `$CX start` |
| Output empty | Check `-o` path exists and is writable |
| Codex hung/unresponsive | `$CX stop` and try exec mode instead |
| Broken skill symlinks in stderr | `find ~/.codex/skills/ -type l ! -exec test -e {} \; -delete` |
