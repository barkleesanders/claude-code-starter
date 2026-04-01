# Code Review: General, Performance & Quality

#### 2. Performance Review
Check for:
- N+1 queries
- Missing database indexes
- Unnecessary re-renders (React)
- Memory leaks
- Blocking operations in async code
- Missing caching opportunities
- Large bundle sizes

```javascript
// BAD: N+1 query
users.forEach(async user => {
  const posts = await getPosts(user.id);
});

// GOOD: Batch query
const userIds = users.map(u => u.id);
const posts = await getPostsForUsers(userIds);
```

#### 3. Code Quality Review
Check for:
- Code duplication (DRY violations)
- Functions doing too much (SRP violations)
- Deep nesting / complex conditionals
- Magic numbers/strings
- Poor naming
- Missing error handling
- Incomplete type coverage
- `alert()` calls (should be inline error state)
- Async event handlers missing loading/disabled state
- `catch` blocks with only `console.error` (silent to user)
- `flex items-center` with text child missing `min-w-0` (mobile text overflow)
- `grid-cols-N` without responsive breakpoint on mobile (375px overflow)
- Hono HTML missing global `overflow-wrap: break-word` + `* { min-width: 0 }` in CSS
- `<table>` in Hono/Worker HTML without `overflow-x: auto` wrapper
- Rigid `min-w-[Npx]` on flex children instead of `shrink-0` (mobile overflow trap)
- Fixed-width columns (`w-28`, `w-20`) without `sm:` responsive breakpoint
- `localStorage.setItem` in component without matching App.tsx restore

```javascript
// BAD: Swallowing errors
try {
  await riskyOperation();
} catch (e) {}

// GOOD: Handle or propagate
try {
  await riskyOperation();
} catch (e) {
  logger.error('Operation failed', { error: e });
  throw new AppError('Operation failed', { cause: e });
}
```

#### 4. Testing Review
Check for:
- Missing test coverage for new code
- Tests that don't test behavior
- Flaky test patterns
- Missing edge cases
- Mocked external dependencies

#### 5. Rust-Specific Review
Check for:
- `#[serde(deny_unknown_fields)]` on config structs (breaks backwards compat when keys are removed)
- Variables mutated only inside `#[cfg(target_os)]` blocks (need `#[allow(unused_mut)]`)
- Functions called only from `#[cfg]` blocks (need matching `#[cfg]` or `#[allow(dead_code)]`)
- Missing i18n translations (new strings need ALL locales, not just English)
- `cargo fmt` violations (chained `||`/`&&` line wrapping)
- Collapsible `if` nesting (`if a { if b { ... } }` → `if a && b { ... }`)
- Missing enum variants in exhaustive match/dispatch/default functions
- `cargo audit` advisories (RUSTSEC-*) — update affected crates or document exceptions
- TODO/FIXME/HACK comments — resolve or convert to NOTE/issue references (code scanners flag these)

#### 6. Config & Schema Backwards Compatibility
Check for:
- Removed config keys that will break existing users (add ignored stubs instead of deleting)
- Changed field types that aren't backwards compatible (e.g., `bool` → `Vec<String>`)
- Missing default values for new required fields
- Strict deserialization (`deny_unknown_fields`, `additionalProperties: false`) on user-facing configs

#### Code Review Output Format

```markdown
## Code Review Summary

### Red Critical (Must Fix)
- **[File:Line]** [Issue description]
  - **Why:** [Explanation]
  - **Fix:** [Suggested fix]

### Yellow Suggestions (Should Consider)
- **[File:Line]** [Issue description]
  - **Why:** [Explanation]
  - **Fix:** [Suggested fix]

### Green Nits (Optional)
- **[File:Line]** [Minor suggestion]

### What's Good
- [Positive feedback on good patterns]
```

#### Full Review Checklist

- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] Error handling complete
- [ ] Types/interfaces defined
- [ ] Tests added for new code
- [ ] No obvious performance issues
- [ ] Code is readable and documented
- [ ] Breaking changes documented
- [ ] Config changes are backwards compatible (no removed keys without stubs)
- [ ] Cross-platform: `#[cfg]` blocks don't create unused variable warnings
- [ ] i18n: New user-facing strings have all required translations
- [ ] React: No `alert()` calls — use inline `useState` error display
- [ ] React: Async buttons have `disabled={isLoading}` + loading indicator
- [ ] React: `catch` blocks surface errors to user (not just `console.error`)
- [ ] React: Flex rows with text have `min-w-0` (test at 375px mobile)
- [ ] React: User preferences saved to `localStorage` also restored in App.tsx on mount
- [ ] Child components ONLY use: props, local state, imports, context (no parent scope)
- [ ] All nullable values have optional chaining (`?.`)
- [ ] XSS: `dangerouslySetInnerHTML` guarded by DOMPurify (not regex sanitizer)
- [ ] XSS: Raw `.innerHTML =` guarded by escapeHtml() — search ALL files (`.` not `src/`), entry points are blind spots
- [ ] XSS: `JSON.stringify` in `<script>` escapes ALL 5 chars (`< > & U+2028 U+2029`), not just `<`
- [ ] XSS: Template `${var}` in server HTML attributes wrapped in escapeHtml() (href, content, src)
- [ ] XSS: `href={dynamicUrl}` has isSafeUrl() guard blocking `javascript:` and `data:` URIs
- [ ] XSS: escapeHtml() covers all 6 chars: `& < > " ' \`` (backtick = IE attribute delimiter)
- [ ] XSS: No `eval()`, `new Function()`, or `setTimeout/setInterval` with string args
- [ ] XSS: `postMessage` listeners validate `event.origin`; senders don't use `*` target
- [ ] Pages calling `secureFetch` have frontend auth guard or redirect
- [ ] Admin route errors use `HTTPException(403)` not plain `Error`
- [ ] `grid-cols-N` (N>1) has responsive breakpoints (`sm:`, `md:`)
- [ ] No `<iframe>` with blob URLs for PDFs (breaks on iOS Safari — use Open/Download fallback)
- [ ] Modal heights use `dvh` not `vh` (iOS address bar changes viewport height)
- [ ] Hover-only UI (`opacity-0 group-hover:opacity-100`) has always-visible alternative for touch
- [ ] No `TODO`/`FIXME`/`HACK` comments in changed files (convert to `NOTE:` or resolve)
- [ ] GitHub Actions workflows have top-level `permissions: read-all` (no `write-all`)
- [ ] Workflow write permissions are at job level only, not top level
- [ ] No open RUSTSEC/npm audit advisories with available fixes (run `cargo audit` / `npm audit`)
- [ ] Hono HTML: Global `overflow-wrap: break-word` + `* { min-width: 0 }` in CSS
- [ ] Hono HTML: `<table>` elements have `overflow-x: auto` (via CSS or wrapper div)
- [ ] Hono HTML: Flex layouts use `shrink-0` on icons and `min-w-0` on text wrappers
- [ ] Hono HTML: No rigid `min-w-[Npx]` on flex children (use `shrink-0` instead)
- [ ] Hono HTML: Fixed-width columns (`w-28`, `w-20`) use `sm:` breakpoint or stack on mobile
- [ ] CSP: Every third-party service's CDN domains are in `img-src`/`script-src`/`connect-src` (missing = broken icons with NO console errors)
- [ ] CSP: When adding a new third-party integration, trace its actual asset CDN domains (often different from API domain — e.g., Clerk API is `*.clerk.com` but icons are `img.clerk.com`)
