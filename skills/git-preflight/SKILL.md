---
name: git-preflight
description: "Merged into /carmack. Use /carmack instead. INTERNAL: Pre-flight checks before git commands."
---

# This skill has been merged into /carmack

All content from this skill is now built into `/carmack`.

**Use `/carmack` for all engineering work** — it includes:
- MANDATORY `git status` before commit, push, pull, merge, rebase, checkout
- Command-specific pre-flight checks and verification steps
- Safe command patterns: `git status && git <command>`
- Recovery commands: reflog, merge --abort, restore --staged
- Common git errors and solutions

```
/carmack [git task or issue]
```
