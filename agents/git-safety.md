# Git Safety Agent

Comprehensive security scanning, cleaning, and prevention for git repositories.

## CRITICAL WARNING

**Removing secrets from git history does NOT make them safe!**

Even after cleaning git history:
- GitHub is scraped by bots within seconds of a push
- Archive services may have captured snapshots
- Forks retain the original history
- CI/CD logs may contain the values

**ALWAYS rotate leaked credentials immediately.** Cleaning history is NOT enough.

## When to Use This Agent

Use this agent when:
- Checking for secrets/credentials in git history
- Cleaning leaked credentials from repository
- Setting up prevention measures (.gitignore, pre-commit hooks)
- Auditing repository security
- Emergency response to credential leaks

## Modes of Operation

### 1. `scan` - Detect Sensitive Files

Scan repository for sensitive files in current state and git history.

```bash
# Check current directory for sensitive files
find . -type f \( \
  -name ".env" -o \
  -name ".env.*" -o \
  -name "credentials.json" -o \
  -name "*.pem" -o \
  -name "*.key" -o \
  -name "id_rsa*" -o \
  -name "secrets.*" \
\) 2>/dev/null | grep -v node_modules | grep -v .git

# Check git history
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -iE 'env|secret|credential|key'
```

### 2. `clean` - Remove from History

Remove sensitive files using git-filter-repo or BFG.

```bash
# Install git-filter-repo
pip install git-filter-repo

# Remove .env from all history
git filter-repo --path .env --invert-paths --force

# Force push (DANGEROUS - rewrites history)
git push origin --force --all
```

### 3. `prevent` - Set Up Prevention

Configure .gitignore and pre-commit hooks.

**Essential .gitignore entries:**
```gitignore
.env
.env.*
*.pem
*.key
credentials.json
secrets.*
.npmrc
id_rsa*
```

### 4. `full` - Complete Audit

Run all three operations in sequence.

## Sensitive File Patterns

```
.env, .env.*, credentials.json, service-account*.json
*.pem, *.key, id_rsa*, secrets.*, .npmrc, *.secret
```

## Emergency Response

If you've leaked credentials:

1. **IMMEDIATELY rotate the credential**
2. Check access logs for unauthorized usage
3. Run `scan` to identify all leaked files
4. Run `clean` to remove from history
5. Force push cleaned history
6. Notify team to re-clone
7. Update .gitignore
8. Set up pre-commit hooks

## Quick Commands

**Scan for sensitive files in history:**
```bash
git log --all --pretty=format: --name-only --diff-filter=A | sort -u | grep -iE 'env|secret|credential|key'
```

**Check .gitignore coverage:**
```bash
for pattern in ".env" ".env.*" "*.pem" "*.key" "credentials.json" "secrets.*"; do
  if ! grep -q "$pattern" .gitignore 2>/dev/null; then
    echo "Missing from .gitignore: $pattern"
  fi
done
```

**Search for hardcoded secrets:**
```bash
git grep -E "(api[_-]?key|apikey|secret[_-]?key|password|token)" --cached -- ':!*.lock' ':!package-lock.json' 2>/dev/null | head -50
```

## Pre-commit Hook

Create `.git/hooks/pre-commit` to prevent committing secrets:

```bash
#!/bin/bash
FORBIDDEN_FILES=(".env" "credentials.json" "*.pem" "*.key" "id_rsa" ".npmrc")

for pattern in "${FORBIDDEN_FILES[@]}"; do
  files=$(git diff --cached --name-only | grep -E "$pattern" || true)
  if [ -n "$files" ]; then
    echo "ERROR: Attempting to commit forbidden file matching '$pattern':"
    echo "$files"
    exit 1
  fi
done
```

## Reference

Full guide: `~/.agents/skills/git-safety/references/full-guide.md`
