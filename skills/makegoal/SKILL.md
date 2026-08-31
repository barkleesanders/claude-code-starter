---
name: makegoal
description: >-
  MERGED into /goal (2026-08-26) — kept as a redirect for muscle memory and for the openai.yaml
  implicit invocation. The brief-fill + parallel-subgoal + synthesis workflow is now `/goal make
  <task>` (aliases `/goal build`, `/goal parallel`). Invoking /makegoal routes there. Use when the
  user types /makegoal, asks for parallel goals for a task, asks to fill the build-task template, or
  asks to solve a task with parallel goals or parallel agents.
---

# /makegoal → merged into `/goal make` (2026-08-26)

**This skill no longer holds the workflow.** It was 92 lines of prompt pattern with no
code of its own, and its own Goal Setup section already said *"In Claude, use `/goal`"* —
it was a front-end for the `/goal` engine, not an alternative to it.

Everything it did now lives in the `/goal` skill:

| Was | Now |
|---|---|
| `/makegoal <task>` | `/goal make <task>` (also `/goal build`, `/goal parallel`) |
| The filled build brief template | `~/.claude/skills/goal/references/make-mode.md` § Step 1 |
| Parallel subgoal dispatch + agent prompt shape | same file, § Step 4 — now **opt-in**, see below |
| Synthesis + final response | same file, §§ 5–6 |

**What the merge improved:** subgoals now land in the `/goal` **deliverable ledger**, so
the evidence gate, stall escalation, and anti-abandonment steering apply to them. Under
the old skill they lived only in the prompt and evaporated. Also, parallel dispatch is
now explicitly gated on the user asking for agents (per the global "do not call the
AgentTool unless the user requested it" rule), instead of being the unconditional
default.

## What to do when this skill is invoked

1. Read `~/.claude/skills/goal/references/make-mode.md`.
2. Follow it, treating everything after `/makegoal` as the raw task.

Do not re-implement the old flow from this file — it is a stub. The pre-merge original
is preserved beside it as `SKILL.md.pre-merge-20260826.bak` for reference only.
