# `/goal make` — brief → goal → parallel subgoals → synthesis

Absorbed from the former standalone `/makegoal` skill (merged 2026-08-26). That skill
had no code of its own — it filled a brief, then called `/goal set` and fanned out.
This is that same workflow, now a mode of the engine that was already doing the work.

Invoke as `/goal make <task>`, `/goal build <task>`, or `/goal parallel <task>`.
Everything after the mode word is the raw user task.

Ask the user a question only when a missing detail makes the task impossible or risky.
Otherwise infer conservatively from the current project context and keep moving.

---

## Step 1 — Fill the brief

Translate the request into this template. Replace **every** bracketed placeholder with
content from the request or a conservative inference from project context:

```text
Build [THING] in [TECH/FRAMEWORK]. It should include [MAIN FEATURES], with
[INTERACTION/ANIMATION/BEHAVIOR DETAILS]. Make it feel [MOOD/QUALITY], using
[VISUAL DETAILS], [ENVIRONMENT DETAILS], and [EXTRA EFFECTS]. Output as
[FORMAT/FILE TYPE].
```

Do not leave bracketed placeholders in the filled version. For non-visual tasks, adapt
the fields to their nearest equivalents: thing, implementation environment, core
deliverables, expected behavior, quality bar, surrounding constraints, finishing
touches, output artifact.

**The filled brief is the input to `goal set`, not a substitute for it.** Its job is to
stop a vague objective from becoming a vague ledger.

## Step 2 — Set the goal

```bash
bash ~/.claude/skills/goal/scripts/goal.sh set "<filled brief>"
```

Run `set` **from the directory the work actually lives in** (the cross-goal write guard
in SKILL.md explains why). If a goal is already active it is pushed onto the stack and
auto-resumes later — you never lose it, so there is no reason to skip this.

The objective you pass must carry: the filled brief, concrete finishing criteria, the
expected final artifact, and the verification that must happen before reporting back.

## Step 3 — Decompose into deliverables (the ledger IS the plan)

This is where the merge earns itself. The old `/makegoal` produced subgoals that lived
only in the prompt and evaporated. Record them in the ledger instead:

```bash
bash ~/.claude/skills/goal/scripts/goal.sh deliverable add "<subgoal>"
```

2–6 items, each independently verifiable, non-overlapping. The injector already steers
you to do this on the first turn after `set` — including the GROUND-TRUTH FIRST clause
(do not decompose an API/SDK/framework task from memory; verify the current capability
matrix first). Follow it.

Good decomposition axes, in rough order of how often they are genuinely independent:

- Requirements/product clarification from existing context
- Architecture, data model, or integration planning
- UI or interaction design
- Implementation of **separate** modules or files
- Test, verification, edge-case review
- Copy, content, examples, documentation

## Step 4 — Parallel dispatch (OPT-IN ONLY)

> ⚠️ **Gate:** the global rule in `~/.claude/CLAUDE.md` is *"Do not call the AgentTool
> unless the user requested it."* `/goal make` does **not** by itself authorize
> subagents. Dispatch only when the user asked for parallel agents, said "fan out",
> "use subagents", "in parallel", or answered yes when you offered. Otherwise do the
> deliverables directly, in sequence, in the main agent — which is faster and safer for
> most tasks anyway.

When dispatch IS authorized, use as many agents as genuinely helpful and no more. One
agent per ledger deliverable is the natural mapping. Prompt shape:

```text
Objective: [ONE CLEAR SUBGOAL — matches ledger item N verbatim]

Context:
[Filled brief and the constraints this agent actually needs.]

Deliverable:
[The specific artifact the main agent needs back.]

Boundaries:
[Files, modules, decisions this agent owns. State what to avoid — especially
files another agent owns.]

Verification:
[Checks this agent runs, or the reasoning it must show. Evidence, not assertion.]
```

Send all independent agents in a **single message** so they run concurrently.

Do **not** tell a subagent to run `/goal` commands. Goal state is keyed to
cwd + session; a subagent writing to the ledger is the exact shape that caused the two
documented evidence-loss incidents. The **main agent** records evidence as results
return.

## Step 5 — Synthesize (main agent keeps ownership)

As results come back:

- Compare each recommendation against the actual repository/source, not the agent's summary
- Resolve conflicts between agents explicitly — say which won and why
- Apply only what fits the request and project constraints; no unrelated refactors
- Run the smallest reliable verification that proves the result works
- Record proof per item:
  ```bash
  GOAL_EXPECT=<beads-id> bash ~/.claude/skills/goal/scripts/goal.sh deliverable done <n> "<evidence>"
  ```
  Pass `GOAL_EXPECT` on every scripted or batched write.

Verify any unverified claim before relying on it. A subagent's report is a hypothesis.

## Step 6 — Complete

Run the completion audit in SKILL.md, then:

```bash
bash ~/.claude/skills/goal/scripts/goal.sh complete "<evidence>"
```

It refuses while any ledger deliverable has empty evidence. That refusal is the feature —
it is what the old `/makegoal` had no way to enforce.

## Final response to the user

Report the completed result, what changed or was produced, and what verification
happened. Plain and user-facing unless implementation details were asked for.
