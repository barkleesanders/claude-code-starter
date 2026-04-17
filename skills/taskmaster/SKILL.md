---
name: taskmaster
user-invocable: true
description: |
  Stop hook that keeps the agent working until all plans and user requests are
  100% complete. Fires when the agent tries to stop, re-examines the plan and
  task list, and forces continuation if anything is unfinished. Prevents
  premature stopping on multi-step tasks.
author: blader
version: 1.0.0
---

# Taskmaster

A stop hook that prevents the agent from stopping prematurely. When a response
finishes and the agent is about to stop, this hook intercepts and prompts it
to re-examine whether all work is truly done.

## How It Works

1. **Agent tries to stop** — the stop hook fires.
2. **The hook checks** for incomplete signals (pending tasks, recent errors, blind spots in infra/config work — see reason text in check-completion.sh).
3. **Agent is prompted** to verify: original requests addressed, plan steps
   completed, tasks resolved, errors fixed, no loose ends.
4. **If work remains**, the agent continues. If truly done, it confirms and
   the hook allows the stop on the next cycle.

## Loop Protection

A session-scoped counter limits continuations to **10 by default**. Set
`TASKMASTER_MAX` environment variable to change:

```bash
export TASKMASTER_MAX=20  # allow up to 20 continuations
export TASKMASTER_MAX=0   # infinite — never cap (relies on stop_hook_active check only)
```

## Setup

The hook must be registered in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/skills/taskmaster/hooks/check-completion.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Disabling

To temporarily disable, either:
- Remove or comment out the Stop hook in `~/.claude/settings.json`
- Set `TASKMASTER_MAX=1` to allow only one continuation check
