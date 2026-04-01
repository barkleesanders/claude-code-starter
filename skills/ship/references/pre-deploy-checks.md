# Pre-Deploy Checks

Covers Phase -1 (repository context verification), Phase -0 (merge conflict resolution), and Phase 0.5 (deployment rate limit check).

---

## Phase -1: REPOSITORY CONTEXT VERIFICATION (ALWAYS FIRST)

**Purpose**: Verify you're in the correct repository and establish baseline information.
**Execution**: MUST run before any other phase.

1. **Verify Git Repository**:
   - Run: `git rev-parse --is-inside-work-tree 2>/dev/null`
   - If not in git repo: **STOP** - Display error: "Not in a git repository. Navigate to your project directory first."
   - If in git repo: Continue

2. **Identify Repository Context**:
   - Extract repository information:
     - REPO_URL: `git config --get remote.origin.url`
     - REPO_NAME: `basename -s .git "$REPO_URL"` or extract from URL
     - CURRENT_BRANCH: `git rev-parse --abbrev-ref HEAD`
     - WORKING_DIR: `pwd`
     - LAST_COMMIT: `git log -1 --oneline`
     - UPSTREAM: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`

3. **Display Repository Context Banner**:
   ```
   ════════════════════════════════════════════════════════════
   SHIP WORKING CODE - Repository Context
   ════════════════════════════════════════════════════════════

   Repository: $REPO_NAME
   Remote URL: $REPO_URL
   Branch: $CURRENT_BRANCH
   Directory: $WORKING_DIR

   ════════════════════════════════════════════════════════════
   ```

4. **Verify Remote Repository Accessibility**:
   - Run: `git ls-remote --exit-code origin HEAD >/dev/null 2>&1`
   - If successful: "Remote repository accessible"
   - If failed: **STOP** - Display error: "Cannot reach remote repository."

5. **Check Working Directory State**:
   - Run: `git status --porcelain`
   - If output is empty: "Working directory clean"
   - If output exists: Display uncommitted changes and offer options:
     1. Stage all changes and continue (git add -A)
     2. Cancel deployment
   - Execute user's choice accordingly

6. **Protected Branch Detection**:
   - Check if current branch matches protected patterns: `main|master|production|prod|release`
   - If on protected branch: Display warning and require explicit YES/NO confirmation
   - If NO: **STOP** deployment
   - If YES: Log warning and continue

7. **Verify Branch Tracking**:
   - Run: `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null`
   - If no upstream: Offer options to set upstream or continue without
   - If upstream exists: Check ahead/behind status

8. **Display Repository Summary** with all verification results before proceeding to Phase -0

---

## Phase -0: MERGE CONFLICT AUTO-RESOLUTION

**Purpose**: Ensure the working tree is conflict-free, validated, and committed before linting or testing begins.
**Execution**: Always operate from repository root. Skip automatically if no conflicts detected.

1. **Detect Conflicts**:
   - Run: `git status --porcelain | cat` and collect paths with `U` status codes
   - Scan files for merge markers using `rg -l "<<<<<<<"`
   - If no conflicts found: Display "No merge conflicts found" and continue to Phase 0

2. **Resolve Conflicts (Non-interactive)**:
   - Manifest/lock files: Regenerate via package manager instead of manual edits
   - Generated artifacts: Re-run the generator to avoid hand-merging
   - Configuration files: Merge both sides' safe keys, prefer stricter rules
   - Source/text content: Preserve both logical intents where possible
   - Binary files: Default to current branch (ours)
   - Delete all conflict markers before moving on
   - Never prompt the user - choose sensible defaults

3. **Validate Builds & Tests**:
   - Detect ecosystem and run appropriate install/build/test commands
   - If validation fails, iterate on merges or revert until tests pass

4. **Finalize**:
   - Stage everything: `git add -A`
   - Commit locally: `git commit -m "chore: resolve merge conflicts"`
   - Never push or tag in this phase
   - Output concise summary of decisions made
   - Only proceed to Phase 0 when `git status --porcelain` is clean

---

## Phase 0.5: DEPLOYMENT RATE LIMIT CHECK (VERCEL PROTECTION)

- Check if project has Vercel deployment (vercel.json exists)
- If Vercel project detected:
  - Check deployment count from last 4 hours
  - Categorize risk level:
    - < 5 deployments: SAFE
    - 5-10 deployments: CAUTION - Warn, ask confirmation
    - 10-20 deployments: WARNING - Strong warning, ask confirmation
    - 20+ deployments: CRITICAL - **BLOCK** deployment
  - If rate limited: Display bypass URL, estimated wait time, offer --force-override
- If not Vercel project: Skip to Phase 1
