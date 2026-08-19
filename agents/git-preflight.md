# Git Preflight Agent

**CORE RULE: Always run `git status` before state-changing git commands.**

This agent enforces pre-flight checks to prevent common git errors.

## When This Agent Activates

This agent should be used internally BEFORE running any of these git commands:

| Command | Pre-Flight Check |
|---------|------------------|
| `git commit` | Verify correct files are staged |
| `git push` | Verify commits exist, branch tracking set |
| `git pull` | Check for uncommitted changes |
| `git checkout` | Check for uncommitted changes |
| `git switch` | Check for uncommitted changes |
| `git merge` | Verify clean working tree, correct branch |
| `git rebase` | Verify clean working tree |
| `git reset` | Understand what will be affected |
| `git stash` | Verify there are changes to stash |
| `git cherry-pick` | Verify clean working tree |

## Pre-Flight Checklist

Before running git commands:

```bash
# 1. ALWAYS run this first
git status

# 2. Check current branch
git branch --show-current

# 3. Check remote tracking (before push/pull)
git branch -vv
```

## Command-Specific Checks

### Before Commit
```bash
git status
# Verify: correct files staged, no unintended files
```

### Before Push
```bash
git status
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null
# Verify: commits exist, upstream set
```

### Before Pull/Merge/Rebase
```bash
git status
# Verify: working tree clean or changes stashed
```

### Before Checkout/Switch
```bash
git status
# Verify: no uncommitted changes OR safe to carry over
```

## Common Errors Prevented

| Error | Cause | How Preflight Prevents |
|-------|-------|------------------------|
| "nothing to commit" | No staged changes | `git status` shows nothing staged |
| "Everything up-to-date" | No commits to push | `git log origin..HEAD` shows empty |
| "Please commit or stash" | Uncommitted changes | `git status` shows dirty tree |
| "diverged" | Out of sync | `git status` shows divergence |
| "no upstream branch" | Not tracking remote | `git branch -vv` shows no upstream |

## Recovery Commands

If something goes wrong:

```bash
git reflog                    # See recent actions
git merge --abort             # Abort failed merge
git rebase --abort            # Abort failed rebase
git restore --staged <file>   # Unstage files
git restore <file>            # Discard local changes
```

## Integration

This agent should be consulted automatically before ANY git operation. It does not need to be explicitly invoked - Claude should internalize this behavior.
