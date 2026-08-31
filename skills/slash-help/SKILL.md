---
name: slash-help
description: Reference for all slash commands and CLI tools available in the user's setup. Use when user asks "what slash commands do I have", "list my CLI tools", "/help", "show me commands", or wants a reference card of available automations.
---

# Slash Commands & CLI Tools Reference

> Extracted from `~/.claude/CLAUDE.md` on 2026-05-17 to reduce always-loaded context. The MANDATORY top-line rules remain in CLAUDE.md; this skill holds the slash-command and CLI-tool reference card.

## Skills (Slash Commands)

- `/carmack [issue]` - Universal engineering: build features, fix bugs, deep debugging
- `/ship` - Safe production deployment with quality gates and safety audits
- `/browser` - Browser automation docs
- `/ralph [feature]` - Autonomous feature implementation
- `/code-review` - AI-powered code review
- `/typescript-react-reviewer` - React 19 + TypeScript expert review
- `/git-safety [mode]` - Git security: scan, clean, prevent
- `/git-preflight` - **INTERNAL**: Pre-flight checks before git commands
- `/visualise` - Render inline interactive visuals — SVG diagrams, HTML widgets, charts, flowcharts, explainers
- a logged-in browser CLI - Inspect / fetch / capture / GET-replay / drive a site locally (Unbrowse replacement)

## CLI Tools (available to all agents)

**ogrep** — AST-aware code search (on PATH as `ogrep`, not a different name)
```bash
ogrep index .                                    # Index codebase (first time per project)
ogrep query "where is auth handled" --mode fulltext  # Keyword search
ogrep query "error handling" -n 10               # More results
```

**a logged-in browser CLI** — on PATH (_(not included)_). Prefer this over raw fcdp/fapi for new inspect/fetch/capture/replay/drive work:
```bash
a logged-in browser CLI doctor
a logged-in browser CLI inspect <url>
a logged-in browser CLI fetch <url> --json
a logged-in browser CLI capture <url> [--fcdp]
a logged-in browser CLI replay <domain>                      # GET only
a logged-in browser CLI drive <url>
```

**fcdp / fapi** — not on PATH in the agent shell. Use for deep click/type/js on an already-open tab, or the older capture path. Always the full path:
```bash
~/tools/fcdp/fcdp open <url>                     # logged-in Chrome
~/tools/fcdp-api/fapi capture <url> [secs]       # older XHR capture; prefer a logged-in browser CLI
```

**bd** — Task tracking with dependency graphs (beads)
```bash
bd create "task description" -p 1                 # Create task (priority 1)
bd list                                            # Show tasks
bd ready                                           # Show unblocked tasks
bd done <id>                                       # Complete task
bd dep add <child> <parent>                        # Add dependency
```

**hurl** — plain-text HTTP replay + jsonpath asserts (Aura/311 envelopes). `hurl --test file.hurl`
**gron** — flatten JSON so nested toast/`objCaseConfigWrapper` keys are greppable. `gron file.json | rg toastPayload`
**yq / xh** — YAML/JSON transform; rust httpie. Prefer `xh` over ad-hoc curl for readable agent HTTP.
**agnix** — lint SKILL.md / CLAUDE.md / hooks. `agnix --target claude-code ~/.claude/skills/<name>` (never `--fix-unsafe` here)
**lnav** — pager for `wrangler tail` pretty-printed JSON (Pattern #32). **hyperfine** — bench a command.
**fhar** — on PATH as `fhar` (`~/.local/bin/fhar` → `~/tools/fcdp-har/fhar`)
