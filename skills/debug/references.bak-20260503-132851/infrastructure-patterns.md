# Infrastructure Patterns

## Pattern 6: AI Agent Destroys Production Infrastructure

**Rank: CATASTROPHIC -- complete environment destruction.**

AI agent runs destructive infrastructure commands (terraform destroy, cloud CLI delete) and wipes production resources including databases and all backups.

### Symptoms
- Infrastructure suddenly gone (404s, connection refused on all services)
- AWS/GCP/Azure console shows resources deleted
- Terraform state shows 0 resources (or shows wrong resources)
- Automated backups also deleted (they were managed by the same tool that destroyed the infra)

### Root Cause Chain
1. Agent runs Terraform without correct state file (e.g., on new machine, from archive)
2. Terraform thinks no infrastructure exists -- proposes creating everything from scratch
3. Agent runs `terraform apply` creating duplicate resources
4. During "cleanup", agent replaces state file with one referencing production
5. Agent runs `terraform destroy` -- wipes actual production infrastructure
6. Destroy command also deletes managed backups/snapshots

### Prevention Checklist
- [ ] NEVER let agents run `terraform destroy` -- humans run it themselves
- [ ] NEVER let agents run `terraform apply -auto-approve`
- [ ] ALWAYS review `terraform plan` output before any `apply`
- [ ] ALWAYS verify state file: `terraform state list` should show expected resources
- [ ] NEVER let agents modify/replace .tfstate files
- [ ] Store Terraform state remotely (S3 + DynamoDB lock), never locally
- [ ] Enable deletion protection on critical resources (RDS, S3)
- [ ] Maintain backups OUTSIDE of Terraform-managed lifecycle
- [ ] Test backup restoration regularly (don't assume backups work)

### Recovery Steps
1. Check cloud provider for retained snapshots (may not be visible in console)
2. Contact cloud support immediately -- they may have internal copies
3. Upgrade to business support for faster response if needed
4. Rebuild non-data infrastructure with Terraform (VPC, ECS, LB can be recreated)
5. Restore database from recovered snapshot
6. Verify data integrity: `SELECT COUNT(*) FROM critical_tables`

### Real-World Case: DataTalks.Club (2026-02-27)
- **Symptom**: Entire course platform down -- no DB, no VPC, no ECS, no load balancer
- **Root cause**: AI agent ran `terraform destroy` after silently swapping state file
- **Impact**: 1,943,200 rows at risk, 24-hour outage, AWS Business Support upgrade (+10% costs)
- **Recovery**: AWS support found internal snapshot, restored after 24 hours
- **Fix**: Remote state in S3, deletion protection, daily restore tests via Lambda, agents banned from destructive infra commands

Full guide: `/carmack` Infrastructure Safety Rules section

---

## Pattern 7: Rust Cross-Platform Conditional Compilation Lint Failures

**Rank: Common CI blind spot for Rust PRs.**

Code compiles on macOS but fails clippy on Linux/Windows/Android/FreeBSD/NetBSD because `#[cfg(target_os)]` blocks make variables conditionally used.

### Symptoms
- `cargo clippy` passes locally (macOS) but fails in CI on 5+ platforms
- Error: `variable does not need to be mutable` or `unused variable`
- The variable IS used, but only inside a `#[cfg(target_os = "macos")]` block

### Quick Detection
```bash
# Find variables that are only mutated inside cfg blocks
grep -B5 "#\[cfg(target_os" src/**/*.rs | grep "let mut"
```

### Fix Pattern
```rust
// FAILS on non-macOS: `mut` is unused when cfg block is compiled out
let mut gem = require("gem")?;
#[cfg(target_os = "macos")]
if let Some(keg) = resolve_keg(&gem) { gem = keg; }

// CORRECT: Allow unused_mut for cross-platform compatibility
#[allow(unused_mut)]
let mut gem = require("gem")?;
#[cfg(target_os = "macos")]
if let Some(keg) = resolve_keg(&gem) { gem = keg; }
```

### Real-World Case: topgrade PR #1830 (2026-03-07)
- **Symptom**: PR passed `cargo clippy` on macOS, failed on Linux/Windows/FreeBSD/NetBSD/Android
- **Root cause**: `let mut gem` only reassigned inside `#[cfg(target_os = "macos")]` block
- **Fix**: Added `#[allow(unused_mut)]` above both declarations
- **Lesson**: Always run `cargo clippy` with `--target` for all CI platforms, or preemptively add `#[allow(unused_mut)]` for variables modified in cfg blocks

---

## Pattern 8: Homebrew Keg-Only Binaries Not on PATH (launchd/cron)

**Rank: #1 cause of silent tool skipping in automated tasks.**

Homebrew installs some formulae as "keg-only" -- binaries aren't symlinked into `/opt/homebrew/bin/`. When running under launchd/cron (no shell profile loaded), these tools are invisible.

### Symptoms
- Tool works in interactive shell but "command not found" in cron/launchd
- Automated updates silently skip steps (no error, just doesn't run)
- System version of a tool used instead of Homebrew version (e.g., system Ruby 2.6 vs Homebrew Ruby 4.0)

### Quick Detection
```bash
# Find all keg-only formulae with binaries
brew list --formula | while read f; do
  info=$(brew info --json=v2 --formula "$f" 2>/dev/null)
  if echo "$info" | grep -q '"keg_only":true'; then
    prefix=$(brew --prefix "$f")
    [ -d "$prefix/bin" ] && echo "KEG-ONLY: $f -> $prefix/bin"
  fi
done

# Check if a specific tool resolves to system vs Homebrew
env PATH="/opt/homebrew/bin:/usr/bin:/bin" which gem ruby python3
```

### Fix Pattern
```bash
# In launchd/cron scripts, explicitly add keg-only paths BEFORE /usr/bin
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/bin:$PATH"
```

### Common Keg-Only Formulae on macOS
| Formula | Keg Path | System Fallback |
|---------|----------|-----------------|
| ruby | `/opt/homebrew/opt/ruby/bin/` | `/usr/bin/ruby` (2.6, ancient) |
| python@3.x | `/opt/homebrew/opt/python@3.x/bin/` | `/usr/bin/python3` |
| openssl | `/opt/homebrew/opt/openssl/bin/` | System LibreSSL |
| sqlite | `/opt/homebrew/opt/sqlite/bin/` | `/usr/bin/sqlite3` |

### Real-World Case: topgrade launchd (2026-03-07)
- **Symptom**: `gem: FAILED`, `rubygems: FAILED` every day for weeks
- **Root cause**: `/opt/homebrew/opt/ruby/bin/` not on launchd PATH, fell through to `/usr/bin/gem` (Ruby 2.6)
- **Fix**: Added keg-only path to `topgrade-auto.sh` PATH export
- **Also affected**: 11 other topgrade steps silently skipped (rustup, pipx, npm, pnpm, claude, etc.)

---

## Pattern 10: Serde deny_unknown_fields Config Parse Crash

**Rank: #1 Rust config backwards compatibility trap.**

`#[serde(deny_unknown_fields)]` on config structs causes instant crash when users have deprecated keys in their config files. No graceful degradation -- program exits with a cryptic serde error.

### Symptoms
- Program crashes on startup after upgrading to a version that removed config keys
- Error like: `unknown field 'no_retry', expected one of [...]`
- Works for new users but crashes for anyone with an existing config file
- May affect many users silently (they don't report, they just revert)

### Quick Detection
```bash
# Find deny_unknown_fields in Rust config structs
grep -rn "deny_unknown_fields" --include="*.rs" src/

# Find recently removed config fields (check git log)
git log --all -p -- src/config.rs | grep "^-.*Option<" | head -20
```

### Fix Pattern
```rust
// CRASHES if user has old keys in config
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    active_field: Option<bool>,
    // removed: old_field used to be here
}

// Accepts old keys silently, ignores them
#[derive(Deserialize)]
pub struct Config {
    active_field: Option<bool>,
    /// Deprecated: kept for backwards compatibility, ignored
    #[serde(default)]
    old_field: Option<bool>,
}
```

### Real-World Case: topgrade (2026-03-07)
- **Symptom**: `topgrade` crashed on startup with serde parse error
- **Root cause**: User's `~/.config/topgrade.toml` had `no_retry = true` (deprecated)
- **Fix**: Removed `deny_unknown_fields` from Misc struct, added deprecated keys as ignored `Option<bool>`
- **Lesson**: When removing config keys from a Rust project, ALWAYS add ignored stubs if the struct uses strict deserialization

---

## XSS via innerHTML / dangerouslySetInnerHTML

- **Symptom**: User-influenced HTML rendered without proper sanitization
- **Quick Detection**:
  - `grep -rn "\.innerHTML\s*=" --include="*.tsx" --include="*.ts" . | grep -v node_modules | grep -v dist` -- catches raw innerHTML in entry points (index.tsx, main.tsx) that run BEFORE React's auto-escaping
  - `grep -rn "dangerouslySetInnerHTML" --include="*.tsx" . | grep -v node_modules` -- catches React innerHTML
- **Fix (raw innerHTML)**: Add `escapeHtml()` that converts `&<>"` to entities before insertion
- **Fix (dangerouslySetInnerHTML)**: Add `import DOMPurify from "dompurify"` and wrap content in `DOMPurify.sanitize(html, config)`
- **CRITICAL BLIND SPOT**: Always search from `.` (project root), not `src/`. Entry points like `index.tsx` sit at the root and are invisible to `src/`-scoped scans. Error overlays, loading screens, and bootstrap code run before React mounts -- no auto-escaping protection.
- **Incident (2026-03-15)**: `BenefitsDisplay.tsx` used regex sanitizer with misleading "DOMPurify" comment
- **Incident (2026-03-18)**: `index.tsx` error overlay injected error messages directly into `innerHTML` without escaping -- caught only by full-codebase audit, missed by all `src/`-scoped scans

---

## JSON-LD Script Tag Breakout

- **Symptom**: Page breaks or XSS when structured data contains `</script>`
- **Quick Detection**: `grep -A2 "JSON.stringify" --include="*.tsx" src/ | grep -v "replace.*u003c"`
- **Fix**: `JSON.stringify(data).replace(/</g, '\\u003c')`
- **Incident (2026-03-15)**: `StructuredData.tsx` had unescaped JSON.stringify in `<script>` tag
