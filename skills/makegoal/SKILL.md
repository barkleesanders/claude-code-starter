---
name: makegoal
description: Convert a raw task request into a filled build brief, create a concrete top-level goal, split the work into independent parallel agent goals, and synthesize the results. This skill should be used when the user types /makegoal, asks for parallel goals for a task, asks to fill the build-task template, or asks Codex/Claude to solve a task with parallel goals or parallel agents.
---

# /makegoal - Parallel Goals For A Task

## Overview

Turn a raw task into an actionable build brief and run the work through a goal-first, parallelizable workflow. Use this skill to define done, divide the task into independent subgoals, dispatch or emulate parallel work where available, and synthesize the final result.

When invoked as `/makegoal <task>`, treat everything after `/makegoal` as the raw user task. Ask the user a question only when a missing detail makes the task impossible or risky to execute; otherwise infer conservatively from the current project context and keep moving.

## Filled Brief

Start by translating the user's request into this template. Replace every bracketed placeholder with relevant content from the request or conservative inferences from the current project context:

```text
Build [THING] in [TECH/FRAMEWORK]. It should include [MAIN FEATURES], with [INTERACTION/ANIMATION/BEHAVIOR DETAILS]. Make it feel [MOOD/QUALITY], using [VISUAL DETAILS], [ENVIRONMENT DETAILS], and [EXTRA EFFECTS]. Output as [FORMAT/FILE TYPE].
```

Do not leave bracketed placeholders in the filled version. If the task is not a visual build, adapt the fields to the nearest useful equivalents: thing, implementation environment, core deliverables, expected behavior, quality bar, surrounding constraints, helpful finishing touches, and output artifact.

## Goal Setup

Before dispatching work, define what done means for the task.

Create a new top-level goal from the filled brief before starting when a goal workflow is available:

- In Codex, use the goal tool if available.
- In Claude, use `/goal` or `bash ~/.claude/skills/goal/scripts/goal.sh set <objective>`.
- If the platform already has an active goal and cannot create another one, continue under the active goal and write the new objective into the working plan instead of blocking.

The top-level goal must include:

- The filled brief.
- Concrete finishing criteria.
- The expected final artifact or answer.
- Verification that should happen before reporting back.

## Parallel Dispatch

Split the work into independent pieces that can run concurrently. Use as many agents as genuinely helpful, but do not create extra agents for work that is faster or safer to do directly.

Good parallel workstreams include:

- Product or requirements clarification from existing context.
- Architecture, data model, or integration planning.
- UI or interaction design.
- Implementation of separate modules or files.
- Test, verification, and edge-case review.
- Copy, content, examples, or documentation.

Give each agent its own dedicated `/goal` in the task prompt. Keep each subgoal self-contained and non-overlapping where possible.

Use this shape for each agent prompt:

```text
/goal [ONE CLEAR SUBGOAL]

Context:
[Filled brief and relevant constraints.]

Deliverable:
[Specific output the main agent needs back.]

Boundaries:
[Files, modules, or decisions this agent owns. State any areas to avoid.]

Verification:
[Checks this agent should run or reasoning it should provide.]
```

When multi-agent tools are available, dispatch the subagents concurrently and synthesize their results as they return. When multi-agent tools are not available, parallelize available local inspection commands and do the remaining work directly.

## Synthesis

Keep ownership of the final result in the main agent.

As agent results come back:

- Compare recommendations against the repository or source context.
- Resolve conflicts explicitly.
- Apply only the parts that fit the user's request and project constraints.
- Keep final edits focused and avoid unrelated refactors.
- Run the smallest reliable verification that proves the result works.

Verify any unverified claim before relying on it.

## Final Response

Report back with the completed result, what changed or was produced, and what verification happened. Keep the answer plain and user-facing unless the user asks for implementation details.
