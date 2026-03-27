---
name: git-worktree
user-invocable: true
description: "Merged into /carmack. Use /carmack instead."
---

# This skill has been merged into /carmack

All content from this skill is now built into `/carmack`.

**Use `/carmack` for all engineering work** — it includes:
- Worktree creation with automatic .env file copying
- Commands: create, list, switch, copy-env, cleanup
- When to use: code review isolation, parallel feature development
- Opinionated defaults: always from main, stored in .worktrees/
- Safety: confirms before create/cleanup, won't remove current worktree

```
/carmack [parallel branch or PR review task]
```
