---
name: install-anti-slop
description: Install, configure, update, or upgrade the vendored anti-slop Oxlint plugins (dmmulroy/anti-slop) in a local TypeScript or JavaScript repository. Use when adding anti-slop lint rules, picking up upstream rules or fixes, migrating an existing installation while preserving local customizations, or when an oxlint anti-slop gate reports UNMEASURED and the setup needs repair.
---

# Install or update anti-slop

Anti-slop is vendored code: the target repository owns its rules, diagnostics, tests, and configuration. Preserve those choices when bringing in upstream changes. Preserve unrelated work and adapt to the project's package manager and configuration style.

**Bundle identity (this skill's `assets/anti-slop/`):** upstream `dmmulroy/anti-slop` commit `c44ef22ca116d0ba62a3ff663a0bd13a3f3fa40b` (2026-09-10, package version 0.1.2) — recorded in `.upstream-commit` beside this file. 18 generic rules + 5 opt-in Effect rules. Verified armed 2026-09-10 on oxlint 1.82.0 (26 diagnostics on a known-bad file spanning every new rule, 0 on a clean control). An installed bundle can be older than upstream HEAD; `gh api repos/dmmulroy/anti-slop/compare/<.upstream-commit>...HEAD --jq .ahead_by` tells you by how much.

## Choose the path

Read the repository's agent instructions and `git status`. Identify its package manager, Oxlint/Vite+ configuration, and any existing anti-slop entry points, including renamed or relocated copies referenced by `jsPlugins`.

- **Existing installation — update, upgrade, migrate, or reconfigure:** read [Update a vendored installation](references/update.md) and follow that procedure instead of the fresh-install steps below. An update is a reviewed three-way merge (base → local, base → incoming), never a directory replacement; the repo's `UPSTREAM.md` names the base.
- **No installation — fresh install:** follow the procedure below. If the user requested an update but no installation can be found, confirm the target before installing.

Complete when the operation and target path are established and pre-existing work is identified.

## Fresh install

1. Copy the bundled plugin from this skill. Run from the target repository:

   ```bash
   node <skill-directory>/scripts/install.mjs
   ```

   This creates `tools/oxlint/anti-slop/`. Pass another relative destination as the first argument when the repository has an established tooling layout. The script refuses to replace an existing destination; route existing copies through the update procedure rather than `--force`.

   Preserve the nested `vendor/eslint-stylistic/LICENSE` and `UPSTREAM.md`; they travel with the copied rule. Readability enforcement is self-contained and requires no Stylistic plugin dependency.

   Complete when the files, including vendored license and provenance, exist at the agreed destination without replacing an existing copy.

2. Install current compatible dependencies rather than trusting versions remembered by the agent:
   - If the repository already depends on `oxlint`, read its installed version from the package manager or lockfile and install `@oxlint/plugins` at exactly that version. Pin it exactly rather than by range so future upgrades move both packages together.
   - Only when the repository has no `oxlint` dependency, query `npm view oxlint version` and `npm view @oxlint/plugins version`, then install the same current version of both packages.
   - `oxlint` is a development dependency. The copied source imports `@oxlint/plugins`, so install it as a development dependency for a local-only plugin.
   - Do not replace the package manager or rewrite unrelated dependency ranges.
   - **Record the resolved oxlint version** — step 3's `complexity` rule needs **>= 1.37.0**, and the failure modes in 3b are version-dependent.
   - **The vendored plugin is ESM with `.ts` import specifiers.** The nearest `package.json` above `tools/oxlint/anti-slop/` must carry `"type": "module"`, or oxlint's plugin loader refuses every rule: `Failed to load the ES module ... set "type": "module"` followed by `Failed to load JS plugin` — exit 1, zero diagnostics, nothing linted (measured 2026-09-10, oxlint 1.82.0). If the repo is CommonJS at the root and must stay so, add a minimal `{ "type": "module" }` `package.json` inside `tools/oxlint/anti-slop/` instead of flipping the root.

   Complete when matching compatible versions are installed and unrelated dependency ranges are preserved.

3. Register the generic plugin, configure ignores, and enable all generic rules. For `oxlint.config.ts` or `.oxlintrc.json`, merge these fields with the existing configuration:

   ```ts
   ignorePatterns: [
     ".agent/**",
     ".agents/**",
     ".claude/**",
     ".codex/**",
     ".continue/**",
     ".cursor/**",
     ".gemini/**",
     ".grok/**",
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

   Enable these rules at `"error"`, including the native Oxlint companion rule:

   ```json
   {
     "oxc/no-accumulating-spread": "error",
     "anti-slop/no-array-filter-map": "error",
     "anti-slop/no-reduce-accumulator-copy": "error",
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
     "anti-slop/require-readable-spacing": "error",
     "anti-slop/require-safety-comment-for-type-assertion": "error"
   }
   ```

   For `no-array-filter-map`, prefer lazy `.values().filter(...).map(...).toArray()` pipelines only when the target runtime supports iterator helpers; otherwise use an appropriate single `flatMap` or locally mutating reducer. Review callback order, indexes, sparse arrays, `thisArg`, and filtering semantics rather than mechanically rewriting chains. Unknown receiver types are deliberately not inferred by this AST/scope rule.

   Pair `no-reduce-accumulator-copy` with native `oxc/no-accumulating-spread`: the custom rule catches supported non-spread copies such as `Object.assign({}, acc, item)`, `Array.from(acc)`, and array accumulator `concat`/`slice` calls. Mutating a fresh local accumulator is allowed; copying individual input items is also allowed. Named callbacks, indirect helpers, and nested accumulator properties are not fully analyzed, so do not claim all quadratic reducers are ruled out.

   `require-readable-spacing` is the one rule with an autofix (it inserts blank lines only). Apply it with `oxlint --fix`, then run the repository's formatter, then lint again; a second fix/format pass must leave files unchanged.

   **Also enable `eslint/complexity`** (oxlint core, Restriction category, off by default) in the same `rules` block. It is cheap, needs no plugin, and catches functions that are genuinely unreadable regardless of how well-typed they are — the one axis the anti-slop rules do not measure:

   ```json
   { "complexity": ["error", { "max": 15, "variant": "modified" }] }
   ```

   - **Use the array form.** The bare `"complexity": "error"` applies oxlint's default `max: 20`, which is far too permissive — verified 2026-08-26 on oxlint 1.80.0, a function with 14 independent paths passed silently at the default. 15 is the house threshold; raise or lower it per repo, but state a number rather than inheriting 20.
   - `variant: "modified"` counts a `switch` as +1 total instead of +1 per `case`, so a wide dispatch table is not punished for being a dispatch table.
   - Requires **oxlint >= 1.37.0** (the release that added the rule). On older oxlint the rule name is simply **ignored, silently, exit 0** — verified on 1.36.0, which still applied every other rule in the same file while `complexity` did nothing. You get no error and no gate. If step 2 resolved an older version, either upgrade or leave `complexity` out; do not add it and assume it is working.

   **Opt-in Effect rules.** If the repository declares `effect` in a package manifest, or the user explicitly requests Effect rules, also register the Effect plugin:

   ```ts
   jsPlugins: [
     {
       name: "anti-slop-effect",
       specifier: "./tools/oxlint/anti-slop/effect/index.ts",
     },
   ],
   rules: {
     "anti-slop-effect/no-manual-effect-error-tag": "error",
     "anti-slop-effect/no-manual-tag-comparison": "error",
     "anti-slop-effect/no-manual-tagged-construction": "error",
     "anti-slop-effect/no-service-constructor-imports": "error",
     "anti-slop-effect/prefer-effect-match": "error",
   },
   ```

   Merge these entries with the generic plugin configuration rather than replacing it. Do not enable the Effect plugin merely because Effect appears transitively in a lockfile; require a direct package-manifest dependency or an explicit user request. `no-service-constructor-imports` covers relative project imports; report package-alias imports as a current limitation rather than pretending they are enforced.

   Complete when the generic rules, `complexity`, and eligible Effect rules are registered and existing configuration is preserved.

3b. **Prove the config is armed before moving on.** Three measured failure modes make this mandatory, and they point in opposite directions:

   | Situation | oxlint's behavior | Why it is dangerous |
   |---|---|---|
   | Rule name unknown to this oxlint (typo, or a rule newer than the installed binary on a strict version) | `Failed to parse oxlint configuration file`, **exit 1, lints NOTHING AT ALL** | Not a weakened gate — a *deleted* one. Verified: a file with `debugger;` and `no-debugger: error` reported no finding because a sibling rule name in the same config was bad. |
   | jsPlugins specifier missing/unloadable — including the ESM `"type": "module"` omission from step 2 | `Failed to load JS plugin: ...`, **exit 1, lints nothing** | Same. All 18 anti-slop rules (and the 5 Effect rules) go dark. Measured 2026-09-10 on 1.82.0: a known-bad file returned rc=1 with 0 diagnostics until `"type": "module"` was added. |
   | Rule name unknown on oxlint < 1.37.0 | silently ignored, **exit 0**, everything else lints | The rule you just added is doing nothing and says so nowhere. |

   So run both checks and read the exit code **unpiped** (`cmd > /tmp/log 2>&1; RC=$?` — piping through `grep`/`tail` replaces `$?` with the pipe's last stage):

   ```bash
   # 1. config loads at all — any "Failed to" means the whole gate is dead
   ./node_modules/.bin/oxlint <one-owned-file> > /tmp/ox.log 2>&1; echo "rc=$?"
   grep -E 'Failed to (parse|load)' /tmp/ox.log && echo "CONFIG DEAD — fix before continuing"

   # 2. rules actually fire — write a throwaway file that breaks them on purpose:
   #    an `unknown` parameter, an unjustified `as` assertion, an adjacent
   #    users.filter(...).map(...) chain, two `export const` lines with no blank
   #    line between them, and a >max-branch function. Confirm >=1 diagnostic
   #    from EACH of anti-slop(no-unknown-parameters),
   #    anti-slop(require-safety-comment-for-type-assertion),
   #    anti-slop(no-array-filter-map), anti-slop(require-readable-spacing),
   #    and eslint(complexity). If the Effect plugin is registered, add
   #    `if (x._tag === "A") {}` and confirm anti-slop-effect(no-manual-tag-comparison).
   #    Count with: grep -oE '(anti-slop(-effect)?|eslint)\([a-z-]+\)' /tmp/ox.log | sort | uniq -c
   ```

   "0 errors" from a disarmed linter is indistinguishable from "0 errors" from clean code. Delete the throwaway file afterward.

4. Run the repository's lint command and typecheck. For Vite+, run the repository's full `vp check` command after adding both lint and format ignores. **[Local override 2026-08-16 — upstream says fix-only-on-request; the user's standing directive is AUTO-FIX LOOP UNTIL 0.]** If findings appear in owned project source:
   - First apply the one mechanical fix: `oxlint --fix` for `require-readable-spacing`, then the repository's formatter, then lint again. Keep those whitespace commits separate from semantic edits; preserve documentation attachment and overload groups; do not enable a competing formatting preset.
   - Then fix every remaining finding in source by adding evidence — inference, `as const`, `satisfies`, named owner contracts, discriminated unions, Zod boundary parsing at trust boundaries, a lazy iterator pipeline or single `flatMap` for `no-array-filter-map`, a locally-owned mutated accumulator for `no-reduce-accumulator-copy`, or a genuinely-checked `// SAFETY: <invariant>` comment on a necessary assertion — then re-run lint AND typecheck, and repeat until lint reports 0 findings and typecheck passes. Loop guard: the same finding surviving 5 fix attempts → stop and surface it to the user with why the fix isn't landing. Do not suppress rules, weaken rule severity, add unsafe casts, mechanically launder types, or write hollow SAFETY comments to make lint pass. Full loop protocol: `~/.claude/skills/shared/anti-slop-typescript.md` (Auto-fix loop section).

   **`eslint(complexity)` findings are OUTSIDE the fix-to-zero loop.** Each anti-slop rule describes a defect with one correct repair — add the missing evidence — so looping to 0 always converges. A high-complexity function is not a defect with a mechanical repair; splitting it is a design decision that can be wrong, and forcing it to zero invites exactly the laundering this skill bans (extracting six one-line helpers to move branches around scores better and reads worse). Report complexity findings, fix the ones you are already editing, and leave the rest for the user's call. Set the threshold so it fires on genuinely tangled functions, not as a running to-do list.

   Complete when checks have run, fix/format stability has been verified, and every failure is resolved or reported with its diagnostics.

5. Record provenance in `UPSTREAM.md` beside the vendored entry point (`tools/oxlint/anti-slop/UPSTREAM.md` — distinct from the nested `vendor/eslint-stylistic/UPSTREAM.md`, which documents the Stylistic engine's own origin): source repository, the exact source commit copied (this bundle's identity is in `<skill-directory>/.upstream-commit`; verify it names the assets actually copied — a package version or the current upstream HEAD alone is insufficient), installed plugin paths, and intentional deviations. If provenance cannot be established, record it as unknown rather than guessing. This file is what the next update's three-way merge uses as its base.

   Review the final diff and report the installed path, source identity, dependency/configuration changes, and check results. Complete when the record and report describe the files actually installed and any remaining findings.

## Migration guidance

When replacing an older local copy, follow [references/update.md](references/update.md): compare rule behavior and diagnostics before overwriting, keep local-only rules, and treat local edits as owned policy rather than drift. Keep project-specific rules in their own plugin; anti-slop is intentionally generic. Prefer inference, `as const`, `satisfies`, named owner contracts, and boundary parsing when resolving findings.

## Refreshing this skill's bundle from upstream

The bundle in `assets/` is itself a vendored copy. To advance it: `gh api repos/dmmulroy/anti-slop/compare/$(head -1 .upstream-commit)...HEAD` to see what changed; download the target commit's tarball; `diff -r` the current `assets/` against the *base* commit's `skills/install-anti-slop/assets/` — if identical, the update is a pure fast-forward and `assets/` can be replaced outright; otherwise three-way merge per `references/update.md`. Then rewrite `.upstream-commit` with the full 40-char SHA, re-run the 3b arming test in a scratch repo, and propagate to the Codex tree (`~/.agents/skills/install-anti-slop/`, which is a physical copy with no automation — `cp -R` then `cd ~/codex-config-backup && python3 libexec/codex-sync --skip-repo-to-live`). Grok reads `~/.claude/skills/` directly and needs no copy.
