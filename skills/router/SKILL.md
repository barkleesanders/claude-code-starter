---
name: router
description: Meta-skill that inspects ALL installed skills and picks the best skill(s) for a task, then invokes them — so you don't have to remember which skill to call. Use when the user says "/router", "route this", "which skill for…", "pick the best skill", "just get this done", or hands you a task without naming a skill and you want the strongest tool for it. Self-improves: an auto-refreshing catalog of every skill + a decision log the /router learn step mines to fix mis-routes. You can still call any skill directly (router is optional, never a gate).
---

# /router — pick the best skill(s) for any task

**You (the model) are the router.** This skill gives you three things so you route well and get better over time:
1. `references/skill-catalog.md` — an **auto-generated list of every installed skill** (personal + plugins), refreshed by the SessionStart hook and `scripts/catalog.sh`. This is ground truth for *what exists*.
2. `references/routing-rules.md` — **curated fast-path rules** mapping common intents → the winning skill. This is *what wins*, and it's the part that learns.
3. `scripts/log-decision.sh` + `scripts/learn.sh` — a **decision log + learning report** so mis-routes get corrected, not repeated.

## When invoked (`/router <task>` or "route this")

1. **Fast path:** read `references/routing-rules.md`, match the task top-to-bottom, first strong match wins.
2. **Fallback:** if no rule matches, grep `references/skill-catalog.md` for domain keywords; pick the closest 1–3 skills. Prefer the **most specific** skill over a general one.
3. **Chain** when the task spans domains (research→report = `deepsearch` then `html-report`; stalled agency→records = `doge-service` then `sf-nextrequest`/email/fax).
4. **Announce** the pick in one line ("Routing to `carmack` (bug fix) → then `ship`"), then **invoke** the chosen skill(s) via the `Skill` tool (or the right non-skill tool — email/fax/Drive/Asana per routing-rules "Non-skill tools").
5. **Log it** so the router learns:
   ```bash
   bash ~/.claude/skills/router/scripts/log-decision.sh "<task summary>" "<skill(s)>" "<worked|partial|wrong|unknown>" "<optional note>"
   ```
   Log `unknown` at route time; if you later see it worked or misfired, log again with the real outcome.

## Subcommands

| Invocation | Action |
|---|---|
| `/router <task>` | Route + act (the main path above). |
| `/router refresh` | `bash ~/.claude/skills/router/scripts/catalog.sh` — regenerate the catalog now (also runs each session via the hook). |
| `/router learn` | `bash ~/.claude/skills/router/scripts/learn.sh` — print the learning report (outcomes, skill freq, **misfires**). Then **edit `references/routing-rules.md`** to fix any mis-route (add/correct a row + a dated line under "Learned corrections"). This is the self-improvement act. |
| `/router list` | Show `references/skill-catalog.md` (all skills). |

## Self-improvement loop (how it gets better)
- **Catalog stays current automatically** — the SessionStart hook `router-catalog-refresh.sh` reruns `catalog.sh`, so new/removed skills are reflected without anyone maintaining a list. Routing never goes stale.
- **Rules improve from real usage** — every route is logged; `/router learn` surfaces `wrong`/`partial` decisions; you encode the fix into `routing-rules.md`. Over time the fast-path table converges on what actually works for *this* user's tasks.
- **Config backup** — after editing any router file under `~/.claude/skills/router/`, run `~/claude-code-boilerplate/scripts/backup-claude-config.sh` so the improvement is captured on GitHub.

## Hard rules
- **Never a gate.** The user can (and should) call any skill directly — router is a convenience, not a checkpoint. If they typed a specific `/skill`, that binds; don't override it.
- **Prefer specific over general** (sf-nextrequest > doge-service for an SF CPRA; va-travel > va-claims for mileage).
- **Not everything is a skill** — email=gogcli, fax=DIY worker, Drive=`gog drive`, tasks=`bd`, Asana=MCP. Route to the right *tool*, per routing-rules.
- **Don't fabricate a skill name.** Only route to entries that appear in `skill-catalog.md` (or a real tool). If nothing fits, say so and do the task directly.
