---
name: goal
description: >-
  Set, pause, resume, complete, or clear a persistent per-directory objective (port of Codex `/goal`).
  Use when the user types `/goal …` or asks to set/check/pause/clear "the goal", "my goal", "the
  objective", or to wrap up a focused session of work. While a goal is active, a UserPromptSubmit hook
  injects an anti-completion-bias steering prompt before every turn, and a beads issue mirrors the
  goal so it shows up in `bd list`. Also absorbs the former /makegoal skill as `/goal make <task>` —
  fill a build brief, set the goal, decompose into deliverables, optionally fan out parallel agents,
  synthesize. Triggers: "/goal", "/makegoal", "set a goal", "what's my goal", "pause the goal",
  "resume the goal", "clear the goal", "mark the goal complete", "is the goal done", "make a goal",
  "parallel goals", "parallel agents for this task", "build brief".
---

# /goal — persistent objective with completion-audit steering

Ported from OpenAI Codex CLI's built-in `/goal` slash command. The steering prompt text is reproduced verbatim from the Codex binary so the model gets the exact OpenAI-authored anti-completion-bias instructions, not a paraphrase.

## What a goal does

When a goal is set for the current directory:

1. A JSON state file is written at `~/.claude/state/goal/<sha-of-cwd>--<sha-of-session>.json` — **scoped to BOTH the directory and the session** (see “Session scoping” below).
2. A beads issue is created (`bd create --type=task --priority=1` with labels `workflow:goal` + `actor:agent`) and immediately claimed. The issue id is stored in the state file.
3. The `UserPromptSubmit` hook at `~/.claude/skills/hooks/goal-injector.sh` injects a steering `<system-reminder>` before every subsequent user message. The steering tells the model:
   - The objective (wrapped as untrusted data).
   - Elapsed time and (if set) token budget.
   - Don't repeat work already done.
   - **Before declaring achieved**, perform a completion audit: restate as deliverables, build a prompt-to-artifact checklist, inspect real evidence for each item, never accept proxy signals (passing tests, complete manifests, plausible final answers) as completion unless they cover every requirement.
   - Only run `goal complete` when the audit shows the objective is actually achieved.
4. `goal complete` closes the beads issue with the elapsed-time note. `goal clear` deletes the issue (`bd update --status=deleted`).

**Goal stack (multiple goals per directory).** `set` no longer rejects when a goal is already active — it **saves the current goal onto a LIFO stack** (`<sha>--<sess>.stack.json`, beside the active file) and makes the new one active. When the active goal is `complete`d or `clear`ed, the most-recently-stacked goal **auto-resumes** as active. The goal-injector hook only ever reads *your session's* active goal, so steering always reflects whatever is on top. This is the "save the other goal it sees and keep going" behavior — you never lose a goal by starting another. Use `goal list` to see the active goal + the whole stack.

To run two goals truly in *parallel* (both being actively worked at once), they need separate working directories/sessions — start the second in a detached **tmux** session pinned to another dir (`tmux new-session -d -s goal2 -c <other-dir>`) and set its goal there. Within one directory, the stack is the mechanism (sequential focus, nothing lost).

## Deliverable ledger + evidence gate (decompose the objective)

A goal may carry an OPTIONAL `deliverables` array in its state JSON — each entry is `{text, done:false, evidence:""}`. It's the concrete, per-item version of the completion audit: instead of one vague "is it done?", every deliverable is a line item that must cite its own proof.

- **Populating it is the model's job, steered by the hook.** On the first turn after a goal is set, while the ledger is still empty, the goal-injector tells you to **decompose the objective into 2-6 concrete, verifiable deliverables** and record them with `goal deliverable add "<text>"` (one call each). As you finish each, capture its proof with `goal deliverable done <n> "<evidence>"` (file:line, exit code, URL, msg id, count). The bash script cannot LLM-decompose — the model does it under the injector's steering.
- **`complete` enforces it.** Beyond the existing "one-line evidence note required" gate, `goal complete` now **refuses if any deliverable in the ledger has empty evidence** (listing the offenders). `--force` bypasses both gates and is recorded as forced.
- **Surfaced everywhere.** The ledger (with `[x]/[ ]` marks and per-item evidence) shows up in `goal status`, `goal list`, and `goal deliverable list`.
- **Fully backward-compatible.** A goal with NO `deliverables` array behaves exactly as before — no new required fields, every reader treats an absent/empty array as "no deliverables," and `complete` skips the ledger gate entirely.

## Injection taper (steering cadence)

Each time the goal-injector fires for the active goal it increments an `injection_count` in the state JSON. The steering **tapers**:

- **First ~3 fires:** the FULL verbatim Codex anti-completion-bias block (plus the deliverable-decompose/ledger line).
- **After that:** a TERSE one-liner (objective + elapsed + "run `goal status` for the full checklist").
- **Re-shows FULL** whenever the ledger is still empty (you haven't decomposed yet) or the goal is `budget_limited`.

The verbatim steering text is unchanged — only the cadence changes, so a long session isn't dominated by the same 25-line block on every turn while still hard-steering at the start and whenever decomposition is missing.

## Ground-truth decomposition (research before you decompose)

The decomposition steering (fired while the ledger is empty) now carries a **GROUND-TRUTH FIRST** clause: if the objective touches any code, API, SDK, library, provider, platform, framework, or CLI, the model must **not** decompose the deliverables from memory. It must first establish the *current* capability matrix — run `/deepsearch` (or the `websearch` CLI) on the topic **and** pull the provider's own current docs via **context7** (`resolve-library-id` → `query-docs`) or WebFetch the official docs — then write each deliverable grounded in the verified capabilities and cite the doc URL/version in the deliverable text or its evidence. This makes `/goal` decompose against real provider docs instead of assumptions, so it can't lock in a wrong premise (the premise-check + ground-truth standard, applied at goal-set time). The clause lives in `~/.claude/skills/hooks/goal-injector.sh` (the `DELIV_COUNT == 0` decompose branch).

## Anti-abandonment gate + stall escalation (2026-07-29)

The steering used to be **one-sided**: it gated the *exit* ("do not say done without
evidence") but left the *floor* wide open — declaring the objective impossible,
quietly swapping it for an easier one, or settling for a shallow version all cost
nothing. Anthropic's [Discovering cryptographic weaknesses](https://www.anthropic.com/research/discovering-cryptographic-weaknesses)
(2026-07-28) is direct evidence that on hard, long-horizon objectives the dominant
failure is the **opposite** of premature completion. Across three days of otherwise
autonomous work, the *only* human inputs were four short re-prompts, each correcting
one avoidance move:

| Observed failure | Researcher's actual correction (verbatim, typos theirs) |
|---|---|
| Learned helplessness — model said the target was impossible (*"AES-128 r5/r6 is just genuinely hard"*, *"there's nothing easy to find"*) | *"the models tend to think it is impossible to solve so they don't try they [sic] need a good amount of prompting."* |
| Aiming too low | *"why not do aes-128 r7? the whole point is to find something better than existing approaches."* |
| Still searching for easy wins | *"no again the goal is that we have highly inteligent [sic] model as good top researcher, we want to find new attacks"* |
| **Target substitution** — wanted to switch ciphers | *"no we don't want to change the targets [...] agian [sic] we need to find something that worth [sic] publishing"* |
| Low-hanging fruit | *"again we are not looking for low hanging fruit, we want proper research to find genuinly [sic] hard findings."* |

Two mechanisms now encode this, both in `~/.claude/skills/hooks/goal-injector.sh`:

**1. Abandonment gate (always in the FULL block).** Infeasibility is treated as a
*claim requiring evidence*, at the same standard as completion — name what was
attempted, the specific failure point, and the artifact proving the wall is real.
Plus: do not substitute the target; do not stop at the first workable answer if the
objective asked for better; **re-attempt your own best rejected idea once** (the HAWK
key insight came from a second worker re-examining what the first had "prematurely
rejected as infeasible"); never silently narrow scope.

**2. Stall escalation (`ESCALATE`).** The researcher had to *watch* for avoidance and
intervene. This does it mechanically. State carries `last_done_count` +
`last_progress_inj`; **progress is defined only as a deliverable gaining evidence** —
turns elapsed, tokens spent, and files touched deliberately do not count. When
`STALL_N >= 3` and any deliverable still lacks evidence, a hard block fires ("pick the
ONE deliverable closest to done and produce its evidence this turn"), forces FULL
steering, and resets the moment evidence is recorded.

⚠️ **Editing trap.** The state-loading heredoc at the top is nested inside
`eval "$(python3 ... <<'PY' ...)"`. Bash tracks quoting while scanning for the closing
paren, so **a single apostrophe anywhere in that heredoc breaks the entire file** with
a syntax error reported ~100 lines later. Write "the Anthropic research", never
"Anthropic's". Verify with `bash -n` after any edit.

## Session scoping (2026-07-29)

State is keyed by **cwd + session**, not cwd alone:

```
~/.claude/state/goal/<cwd16>--<sess8>.json        ← your goal
~/.claude/state/goal/<cwd16>.json                 ← legacy (pre-2026-07-29) goals
```

**Why.** Every session launched from the same directory — nearly always `$HOME` — used
to share one goal slot. Session A could set a goal on transit fares while session B
worked on something unrelated, and B's stop hook would refuse to let B finish until
A's goal was "complete". A first pass added `warn_concurrent_session` + session
stamping, which *detected* the collision but never prevented it. **Detection is not
isolation** — the warning told you another session owned the goal while the hook kept
gating you on it.

**Lookup order** (one shared resolver, `scripts/goal-state-path.sh`, sourced by
`goal.sh` and both hooks so they can never drift):

1. your session-scoped file, if it exists
2. the legacy file — **only if it is unowned or owned by you**
3. the same two checks walking up parent directories

Step 2 is the fix: a legacy goal owned by a *different* live session is skipped, so it
stops gating you, while staying fully visible to its owner and to everyone if it
predates stamping. Popped stack entries are stamped with the popping session so a
restored goal can never fall back into the shared slot ownerless.

**Fallback.** Scoping is only safe because `CLAUDE_CODE_SESSION_ID` is stable across
invocations. Where no session id is exported, the resolver deliberately uses **legacy
shared** behaviour rather than minting a new slot from an unstable PID.

**Testing without side effects.** `goal set` mirrors into a real beads issue. Set
`CLAUDE_GOAL_NO_BD=1`, or point `CLAUDE_GOAL_STATE_DIR` at a temp dir (which the guard
treats as a test run), and no beads issue is created/closed. This exists because the
scoping test itself leaked two fixture issues into the live tracker on 2026-07-29.

## 🛑 Cross-goal write guard — `cd` matters more than you think (2026-08-05)

**This has destroyed evidence twice** (2026-07-31, 2026-08-05), and neither loss was
recoverable — `~/.claude/state/goal/` is not tracked in the config repo.

The mechanism: `set` keys the goal to **the cwd you happened to be in**. If your shell
later moves (a `cd` into `node_modules` to check a citation is enough), a subsequent
`deliverable done` resolves to a *different* state file — often the legacy `$HOME`
goal — and **overwrites an unrelated goal's evidence in place**, silently, exit 0.

Two layers now guard it, both in `scripts/goal.sh` at the dispatch:

1. **Every mutating command announces its target** on stderr before writing:
   `[goal] target: <beads-id> — <objective…>`. Read that line. If it names a goal you
   are not working on, stop — you are one keystroke from the same data loss.
2. **`GOAL_EXPECT=<beads-id>` makes it a precondition.** On mismatch the command
   REFUSES with **exit 65** and writes nothing (verified: target evidence intact after
   a refused write). A matching expectation is exit 0.

```bash
GOAL_EXPECT=IBA-pmp bash ~/.claude/skills/goal/scripts/goal.sh deliverable done 2 "<evidence>"
```

**Use `GOAL_EXPECT` for every scripted or batched deliverable write.** The
announcement catches a human reading output; only the precondition catches a batch
that runs four writes in one command — which is exactly how both incidents happened.

Applies to: `deliverable`, `complete`, `pause`, `resume`, `clear`, `budget-limit`.
`set` is deliberately exempt — it defines the cwd rather than resolving one. **So run
`set` from the directory the work actually lives in**, never from a transient path.

### Snapshot-before-write (added 2026-08-05)

Both incidents were unrecoverable for one reason: **nothing kept a prior copy.**
`~/.claude/state/goal/` is NOT tracked in the config-backup repo, and Time Machine was
unmountable. Every mutating command now copies the state file to
`~/.claude/state/goal/.backups/<hash>.<UTC-timestamp>.bak` **before** writing, keeping
the newest 20 per goal. Files are 1–7 KB, so the cost is nil.

```bash
ls -t ~/.claude/state/goal/.backups/ | head          # find the snapshot
cp ~/.claude/state/goal/.backups/<hash>.<ts>.bak \
   ~/.claude/state/goal/<hash>.json                  # restore
```

### The real exposure: 52 of 78 goal files are LEGACY

Session-scoping (2026-07-29) keys *new* goals to cwd+session, but it never migrated the
files that already existed. **52 legacy files remain and ~18 are still active/paused** —
each one a shared, unowned slot that ANY concurrent session can resolve to and
overwrite. That is precisely how the 2026-07-31 loss happened (a different session
running case/OVS work).

Two habits until those are migrated:
- **Assume other sessions are live.** Six Claude CLI processes were running during the
  2026-08-05 incident. `~/.claude/skills/` and `~/.claude/state/goal/` have **no
  locking** — a co-edit is normal, not exceptional.
- **Read the `[goal] target:` line before every write**, and pass `GOAL_EXPECT` in any
  batched/scripted write. A batch is the dangerous shape: four writes land before a
  human ever sees the first line of output.

## Make mode — `/goal make <task>` (absorbed `/makegoal`, 2026-08-26)

`/makegoal` was a 92-line prompt pattern with no code of its own: it filled a build
brief, then called `/goal set` and fanned out subagents. It is now a mode of this skill.
The three things it contributed that the engine lacked:

1. **The filled build brief** — forces a vague ask into a concrete spec *before* the
   goal is set, so the deliverable ledger is not vague either.
2. **Parallel decomposition** with a per-agent prompt shape (deliverable / boundaries /
   verification).
3. **Synthesis discipline** — the main agent keeps ownership of the final result.

What changed in the merge: subgoals now land in the **deliverable ledger** instead of
evaporating with the prompt, so the evidence gate and stall escalation apply to them —
and parallel dispatch is **opt-in**, per the global rule against unrequested subagents.

Full workflow: **`references/make-mode.md`** — read it when the user invokes make mode.

## Subcommands

Always invoke via Bash:

```bash
bash ~/.claude/skills/goal/scripts/goal.sh <subcommand> [args]
```

| Subcommand | Effect | Beads side-effect |
|---|---|---|
| `make <task…>` | **Brief -> goal -> parallel subgoals -> synthesis.** Absorbed from the former `/makegoal` skill. Not a bash subcommand — a model workflow: read `references/make-mode.md`, fill the build brief, then `set` with it. Aliases: `build`, `parallel`. | via `set` |
| `set <objective…>` | Create a goal. If one is already active, **saves it to the stack** and makes the new one active (no longer rejects). | Creates issue, claims it; comments "stacked" on the saved goal |
| `status` | Human-readable summary (objective, status badge, elapsed, budget, bd id) | — |
| `list` (alias `ls`) | Active goal + the saved stack (newest first) | — |
| `show` | Raw JSON state (active goal) | — |
| `pause` | Stop hook injection without losing state | bd comment "Goal paused" |
| `resume` | Re-enable hook injection | bd comment "Goal resumed" |
| `budget-limit` | Switch to wrap-up steering (model is told to stop new substantive work) | bd comment |
| `deliverable add "<text>"` | Append a deliverable `{text, done:false, evidence:""}` to the ledger | — |
| `deliverable done <n> "<evidence>"` | Mark deliverable `n` done and record its evidence (refuses without evidence) | — |
| `deliverable list` (alias `dl`) | Show the deliverable ledger (also surfaced in `status` and `list`) | — |
| `complete "<evidence>"` | Mark achieved (only valid from `active` / `budget_limited`). **Requires a one-line evidence note** citing the artifact for each deliverable (file:line, exit code, URL, msg id, count); refuses if empty. **Also refuses if any ledger deliverable has empty evidence.** `--force` bypasses both gates (recorded as forced). | bd close with elapsed time + evidence |
| `clear` | Delete the state file entirely | bd update --status=deleted |
| `budget <tokens \| 0>` | Set / clear informational token budget (not enforced) | — |

The `goal-injector` hook is silent for any prompt that starts with `/goal`, `goal set …`, etc., so administering the goal doesn't re-inject the steering.

## How to invoke from `/goal …`

When the user types `/goal <something>`:

| User said | Run |
|---|---|
| `/goal make <task>` / `/goal build <task>` / `/goal parallel <task>` / `/makegoal <task>` | Read `references/make-mode.md` and follow it: fill the brief, `set` the goal with the filled brief, decompose into ledger deliverables, dispatch parallel agents **only if the user asked for them**, synthesize, record evidence. |
| `/goal <objective>` (anything that isn't a subcommand keyword) | `bash ~/.claude/skills/goal/scripts/goal.sh set <objective>` — if a goal is already active it is **saved to the stack** and the new one becomes active (report both: the new objective + that the prior was stacked). |
| `/goal status` or `/goal` (no args) | `bash ~/.claude/skills/goal/scripts/goal.sh status` |
| `/goal list` | `bash ~/.claude/skills/goal/scripts/goal.sh list` |
| `/goal pause` | `bash ~/.claude/skills/goal/scripts/goal.sh pause` |
| `/goal resume` | `bash ~/.claude/skills/goal/scripts/goal.sh resume` |
| `/goal clear` | `bash ~/.claude/skills/goal/scripts/goal.sh clear` |
| `/goal complete` | **First** do the completion audit described in the steering prompt. **Only then** run `bash ~/.claude/skills/goal/scripts/goal.sh complete`. |
| `/goal budget 50000` | `bash ~/.claude/skills/goal/scripts/goal.sh budget 50000` |
| `/goal deliverable add …` / `done …` / `list` | `bash ~/.claude/skills/goal/scripts/goal.sh deliverable <add\|done\|list> …` |
| `/goal follow the instructions in docs/goal.md` | This is the Codex idiom for "the goal is what's in this file". Set it as-is — the model will read the file when it sees the steering. |

Then report the script's stdout to the user in 1–2 sentences. For `set`, mention the beads id.

## Completion audit — non-negotiable

When the user (or the steering) asks "is the goal done?" or "/goal complete", DO NOT just run `goal complete`. The whole point of porting this from Codex is the audit step. Do this first:

1. Restate the objective from `bash ~/.claude/skills/goal/scripts/goal.sh show` as a numbered list of concrete deliverables.
2. For each deliverable, identify the artifact that proves it (file path + line, command exit code, test name, PR URL, etc.).
3. Inspect each artifact with Read / Bash / Grep — don't trust your memory of earlier work.
4. If any deliverable's evidence is missing, weak, or unverified: continue the work, do not mark complete.
5. Only after every deliverable has concrete evidence: run `goal complete`.

The beads issue's history will show whether you closed it after the audit or skipped straight to `goal complete` — keep yourself honest.

## What this is NOT

- Not a task tracker — `bd` is for that. The goal mirrors *into* bd so it shows up in `bd list`, but the goal is a higher-level objective, not a per-step todo.
- Not a token budget enforcer — Claude Code does not expose per-turn token counts to hooks. `goal budget <N>` is informational only; the steering prompt will display it but won't auto-trigger `budget_limited`. The user can do that manually with `goal budget-limit`.
- Not shared across sessions — the state file is keyed on resolved cwd **plus session id**, so your goal sticks while you work in the same directory in the same session, and is invisible to other sessions running in that same directory.

## Diverges from Codex (by design)

- Codex stores goals in a per-thread SQLite DB; we use a per-cwd-per-session JSON file. (An earlier version of this doc claimed Claude exposes no stable session handle — that is **false**: `CLAUDE_CODE_SESSION_ID` is a stable UUID for the life of a session, verified 2026-07-29, and is what the scoping now keys on.)
- Codex automatically transitions to `budget_limited` when the token budget is hit; we don't (see above).
- Codex has `get_goal` / `update_goal` tool calls; we use a bash script Claude runs via Bash.

The steering prompt itself (the high-value part) is verbatim.
