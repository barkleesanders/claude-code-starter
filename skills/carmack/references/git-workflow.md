# Git Workflow, Security & Worktrees

## Pre-Flight Checks (MANDATORY before every git command)

**ALWAYS run `git status` before these commands:**

| Command | Why Check First |
|---------|-----------------|
| `git commit` | Verify what's staged, check for untracked files |
| `git push` | Ensure commits exist, check branch tracking |
| `git pull` | Check for uncommitted changes that could conflict |
| `git merge` | Verify clean working tree, correct branch |
| `git rebase` | Check for uncommitted changes, verify branch |
| `git checkout` | Check for uncommitted changes that would be lost |
| `git switch` | Same as checkout |
| `git stash` | Verify there are changes to stash |
| `git reset` | Understand what will be affected |
| `git cherry-pick` | Verify clean working tree |

### Command-Specific Checks

**Before `git commit`:**
```bash
git status
# Verify: correct files staged (green), no unintended files staged, untracked files
```

**Before `git push`:**
```bash
git status
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || echo "No upstream set"
# Verify: commits exist to push, branch has upstream tracking
```

**Before `git pull`:**
```bash
git status
# Verify: working tree is clean OR changes are stashed/committed
```

**Before `git checkout/switch`:**
```bash
git status
# Verify: no uncommitted changes OR changes are safe to carry over
```

**Before `git merge`:**
```bash
git status
git branch --show-current
# Verify: clean working tree, on correct target branch, source branch exists
```

**Before `git rebase`:**
```bash
git status
git log --oneline -5
# Verify: clean working tree, understand commits, not rebasing public history
```

### Safe Command Patterns

```bash
# Always check status first
git status && git add <files>
git status && git commit -m "message"
git status && git push
git status && git stash
git status && git checkout <branch>
```

### Recovery Commands

```bash
git reflog                    # See recent actions
git checkout <commit-hash>    # Recover lost commits
git merge --abort             # Abort failed merge
git rebase --abort            # Abort failed rebase
git restore --staged <file>   # Unstage files
```

### Common Git Errors & Solutions

| Error | Cause | Prevention |
|-------|-------|------------|
| "nothing to commit" | No staged changes | `git status` first, then `git add` |
| "Everything up-to-date" | No new commits | `git log origin/branch..HEAD` first |
| "Please commit or stash" | Uncommitted changes | `git status`, then stash/commit |
| "diverged" | Local/remote out of sync | Check `git status` + `git log` |
| "no upstream branch" | Branch not tracking remote | `git push -u origin branch` |

---

## Security Scanning

**CRITICAL WARNING:** Removing secrets from git history does NOT make them safe! GitHub is scraped by bots within seconds. Archive services may have snapshots. Forks retain original history.

**ALWAYS rotate leaked credentials immediately.** Cleaning history is NOT enough.

### Modes

- `/git-safety scan` -- Detect sensitive files in current state and history
- `/git-safety clean` -- Remove sensitive files using git-filter-repo or BFG
- `/git-safety prevent` -- Configure .gitignore and pre-commit hooks
- `/git-safety full` -- All three in sequence

### Sensitive File Patterns

```
.env, .env.*, credentials.json, service-account*.json
*.pem, *.key, id_rsa*, secrets.*, .npmrc, *.secret
```

### Quick Commands

**Scan for sensitive files in history:**
```bash
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -iE 'env|secret|credential|key'
```

**Remove .env from all history:**
```bash
git filter-repo --path .env --invert-paths --force
git push origin --force --all
```

**Add to .gitignore:**
```bash
echo -e "\n.env\n.env.*\n*.pem\n*.key\ncredentials.json" >> .gitignore
```

### Emergency Response (If Credentials Leaked)

1. **IMMEDIATELY rotate the credential**
2. Check access logs
3. Run `git filter-repo --path .env --invert-paths --force`
4. Force push cleaned history
5. Notify team to re-clone
6. Update .gitignore
7. Set up pre-commit hooks

---

## Worktree Management

Use worktrees for isolated parallel development -- reviewing PRs, working on multiple features simultaneously, or isolating risky changes.

**NEVER call `git worktree add` directly.** Always use the worktree-manager script:

```bash
# CORRECT - Always use the script
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-name

# WRONG - Never do this directly
git worktree add .worktrees/feature-name -b feature-name main
```

The script handles critical setup: copies `.env` files, ensures `.worktrees` is in `.gitignore`, creates consistent structure.

### Commands

```bash
# Create a new worktree (copies .env files automatically)
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# List all worktrees with status
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh list

# Switch to a worktree
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Copy .env files to an existing worktree
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-login

# Clean up completed worktrees
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### When to Use

- **Code Review**: If NOT already on the PR branch -> offer worktree for isolated review
- **Feature Work**: When working on multiple features simultaneously
- **Risky Changes**: When you want to experiment without affecting main branch

### Parallel Feature Development

```bash
# Start first feature (copies .env files)
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# Start second feature
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh create feature-notifications

# List what you have
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh list

# Switch between them
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Clean up when done
bash ~/.claude/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### Directory Structure

```
.worktrees/
├── feature-login/          # Worktree 1
├── feature-notifications/  # Worktree 2
└── ...

.gitignore (updated to include .worktrees)
```

### Troubleshooting

- **"Worktree already exists"**: Script asks to switch to it instead
- **"Cannot remove: current worktree"**: `cd $(git rev-parse --show-toplevel)` first
- **Missing .env files**: `copy-env feature-name` to copy them manually

---

## Fork Mass-Integration Strategy

When forking a stale OSS project to integrate pending community work:

### Workflow
1. **Audit**: `gh pr list --state open`, `gh issue list --state open` -- categorize into implementable vs can't-fix
2. **Merge PRs**: Start with bot/dependency PRs (clean), then simple features, then complex refactors
3. **Implement Issues**: Batch by theme (new features, bug fixes, platform improvements)
4. **CI Loop**: Push -> check CI -> fix failures -> push again. Budget 3-5 CI rounds.
5. **Local Test**: Install and run the tool with YOUR existing config. Backwards compat bugs hide here.

### Key Patterns
- **Hot files**: Some files (config, schema, routes) are touched by every PR. Merge these last.
- **Revert fast**: If a PR breaks the build (e.g., dependency major version bump), `git revert HEAD -m 1` immediately
- **Config compat**: Users have deprecated keys in config files. `deny_unknown_fields` + removed keys = crash at startup. Add ignored stubs instead.
- **i18n completeness**: Strict checkers require ALL locales for every new string -- not just English
