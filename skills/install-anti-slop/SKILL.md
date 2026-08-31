---
name: install-anti-slop
description: Install and configure the anti-slop Oxlint plugin in a local TypeScript or JavaScript repository. Use whenever a user asks to add anti-slop lint rules, copy the anti-slop plugin, configure opinionated Oxlint rules, or migrate an existing local anti-slop setup.
---

# Install anti-slop

Install the bundled Oxlint plugin into the current repository and integrate it with the repository's existing lint setup. Preserve unrelated work and adapt to the project's package manager and configuration style.

## Procedure

1. Inspect the repository before changing it:
   - Read its agent instructions.
   - Check `git status` and preserve unrelated changes.
   - Identify the package manager from `packageManager` and lockfiles.
   - Find Oxlint configuration (`oxlint.config.*`, `.oxlintrc*`, or a Vite+ config).
   - Check whether anti-slop files or rules already exist. Do not overwrite them without reviewing the diff.

2. Copy the bundled plugin from this skill. Run from the target repository:

   ```bash
   node <skill-directory>/scripts/install.mjs
   ```

   This creates `tools/oxlint/anti-slop/`. Pass another relative destination as the first argument when the repository has an established tooling layout. The script refuses to replace an existing destination; only use `--force` after backing up and reviewing existing files.

3. Install current compatible dependencies rather than trusting versions remembered by the agent:
   - Query `npm view oxlint version` and `npm view @oxlint/plugins version`.
   - Install the same current version of both packages with the repository's package manager.
   - `oxlint` is a development dependency. The copied source imports `@oxlint/plugins`, so install it as a development dependency for a local-only plugin.
   - Do not replace the package manager or rewrite unrelated dependency ranges.
   - **Record the resolved oxlint version** — step 4's `complexity` rule needs **>= 1.37.0**, and the two failure modes below are version-dependent.

4. Register the plugin, configure ignores, and enable all rules. For `oxlint.config.ts` or `.oxlintrc.json`, merge these fields with the existing configuration:

   ```ts
   ignorePatterns: [
     ".agent/**",
     ".agents/**",
     ".claude/**",
     ".codex/**",
     ".continue/**",
     ".cursor/**",
     ".gemini/**",
     ".opencode/**",
     ".pi/**",
     ".roo/**",
     ".windsurf/**",
     "tools/oxlint/anti-slop/**",
   ],
   jsPlugins: [
     { name: "anti-slop", specifier: "./tools/oxlint/anti-slop/index.ts" },
   ],
   ```

   Keep every existing ignore. Adjust the final pattern when the plugin was copied elsewhere. Inspect the repository for other project-local agent tooling directories and add them rather than linting installed skills, hooks, or generated agent configuration as application source. Do not broadly ignore all dot-directories, because some repositories keep owned source or checks in them.

   For Vite+, add these fields to `lint.ignorePatterns` and `lint.jsPlugins`. Also merge the same patterns into `fmt.ignorePatterns` so `vp check` does not reformat installed agent assets or the vendored plugin. Merge existing entries instead of replacing them.

   Enable these rules at `"error"`:

   ```json
   {
     "anti-slop/no-chained-type-assertions": "error",
     "anti-slop/no-conditional-empty-object-spread": "error",
     "anti-slop/no-known-value-widening": "error",
     "anti-slop/no-module-mocking": "error",
     "anti-slop/no-object-parameters": "error",
     "anti-slop/no-reflect-apply": "error",
     "anti-slop/no-reflect-get": "error",
     "anti-slop/no-runtime-typeof": "error",
     "anti-slop/no-shape-in-symbol-names": "error",
     "anti-slop/no-unknown-parameters": "error",
     "anti-slop/no-unknown-returns": "error",
     "anti-slop/no-unknown-type-aliases": "error",
     "anti-slop/no-unsafe-dictionary-type": "error",
     "anti-slop/no-widen-then-assert": "error",
     "anti-slop/require-safety-comment-for-type-assertion": "error"
   }
   ```

   **Also enable `eslint/complexity`** (oxlint core, Restriction category, off by default) in the same `rules` block. It is cheap, needs no plugin, and catches functions that are genuinely unreadable regardless of how well-typed they are — the one axis the 15 anti-slop rules do not measure:

   ```json
   { "complexity": ["error", { "max": 15, "variant": "modified" }] }
   ```

   - **Use the array form.** The bare `"complexity": "error"` applies oxlint's default `max: 20`, which is far too permissive — verified 2026-08-26 on oxlint 1.80.0, a function with 14 independent paths passed silently at the default. 15 is the house threshold; raise or lower it per repo, but state a number rather than inheriting 20.
   - `variant: "modified"` counts a `switch` as +1 total instead of +1 per `case`, so a wide dispatch table is not punished for being a dispatch table.
   - Requires **oxlint >= 1.37.0** (the release that added the rule). On older oxlint the rule name is simply **ignored, silently, exit 0** — verified on 1.36.0, which still applied every other rule in the same file while `complexity` did nothing. You get no error and no gate. If step 3 resolved an older version, either upgrade or leave `complexity` out; do not add it and assume it is working.

4b. **Prove the config is armed before moving on.** Two measured failure modes make this mandatory, and they point in opposite directions:

   | Situation | oxlint's behavior | Why it is dangerous |
   |---|---|---|
   | Rule name unknown to this oxlint (typo, or a rule newer than the installed binary on a strict version) | `Failed to parse oxlint configuration file`, **exit 1, lints NOTHING AT ALL** | Not a weakened gate — a *deleted* one. Verified: a file with `debugger;` and `no-debugger: error` reported no finding because a sibling rule name in the same config was bad. |
   | jsPlugins specifier missing/unloadable | `Failed to load JS plugin: ...`, **exit 1, lints nothing** | Same. All 15 anti-slop rules go dark. |
   | Rule name unknown on oxlint < 1.37.0 | silently ignored, **exit 0**, everything else lints | The rule you just added is doing nothing and says so nowhere. |

   So run both checks and read the exit code **unpiped** (`cmd > /tmp/log 2>&1; RC=$?` — piping through `grep`/`tail` replaces `$?` with the pipe's last stage):

   ```bash
   # 1. config loads at all — any "Failed to" means the whole gate is dead
   ./node_modules/.bin/oxlint <one-owned-file> > /tmp/ox.log 2>&1; echo "rc=$?"
   grep -E 'Failed to (parse|load)' /tmp/ox.log && echo "CONFIG DEAD — fix before continuing"

   # 2. rules actually fire — write a throwaway file that breaks them on purpose
   #    (an `unknown` return + an unjustified assertion + a >max-branch function)
   #    and confirm >=1 anti-slop(...) AND >=1 eslint(complexity) diagnostic.
   ```

   "0 errors" from a disarmed linter is indistinguishable from "0 errors" from clean code. Delete the throwaway file afterward.

5. Run the repository's lint command and typecheck. For Vite+, run the repository's full `vp check` command after adding both lint and format ignores. **[Local override 2026-08-16 — upstream says fix-only-on-request; the user's standing directive is AUTO-FIX LOOP UNTIL 0.]** If findings appear in owned project source, fix every one in source by adding evidence — inference, `as const`, `satisfies`, named owner contracts, discriminated unions, Zod boundary parsing at trust boundaries, or a genuinely-checked `// SAFETY: <invariant>` comment on a necessary assertion — then re-run lint AND typecheck, and repeat until lint reports 0 findings and typecheck passes. Loop guard: the same finding surviving 5 fix attempts → stop and surface it to the user with why the fix isn't landing. Do not suppress rules, weaken rule severity, add unsafe casts, mechanically launder types, or write hollow SAFETY comments to make lint pass. Full loop protocol: `~/.claude/skills/shared/anti-slop-typescript.md` (Auto-fix loop section).

   **`eslint(complexity)` findings are OUTSIDE the fix-to-zero loop.** The 15 anti-slop rules describe a defect with one correct repair — add the missing evidence — so looping to 0 always converges. A high-complexity function is not a defect with a mechanical repair; splitting it is a design decision that can be wrong, and forcing it to zero invites exactly the laundering this skill bans (extracting six one-line helpers to move branches around scores better and reads worse). Report complexity findings, fix the ones you are already editing, and leave the rest for the user's call. Set the threshold so it fires on genuinely tangled functions, not as a running to-do list.

6. Review the final diff and clearly report:
   - copied path,
   - dependency versions installed,
   - configuration changed,
   - checks run and any remaining findings.

## Migration guidance

When replacing an older local copy, compare its rules and diagnostics before overwriting. Keep project-specific rules in their own plugin; anti-slop is intentionally generic. Prefer inference, `as const`, `satisfies`, named owner contracts, and boundary parsing when resolving findings.
