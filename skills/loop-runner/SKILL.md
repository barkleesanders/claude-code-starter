---
name: loop-runner
description: Run a Loop Library loop as a real, bounded, verifiable cycle — not just a pasted prompt. Use when the user says "/loop-run", "run a loop", "start a loop", "run this loop-library loop", "loop until X", or wants a repeatable agent workflow that measures, learns, and stops on its own. Fetches a loop from the live Loop Library catalog (or a local/inline prompt), then enforces it with a verify check, stop predicates, a JSONL ledger, and two hooks that drive each cycle and refuse premature "done". Triggers: "/loop-run", "run a loop", "start a loop", "loop library", "loop until", "keep iterating until".
---

# /loop-run — execute a Loop Library loop

Loop Library (`https://signals.forwardfuture.ai/loop-library/`) publishes loops as **prose** — a prompt, an English `verification`, and steps. Prose can't loop on its own. This skill adds the machine contract the catalog lacks and actually runs the six-step cycle (Observe → Choose → Act → Verify → Record → Repeat/stop), enforced by hooks. It's the execution layer to the catalog's design layer. Architecturally it's the `/goal` skill specialized for *bounded, verifiable* loops.

## What a running loop does

When you `start` a loop in a directory:
1. A state file is written at `~/.claude/state/loop/<sha-of-cwd>.json` and a JSONL ledger beside it (`.jsonl`).
2. A beads issue is created (`bd create --type=task --priority=2`, labels `workflow:loop` + `actor:agent`) and claimed; its id is stored in state.
3. The **`UserPromptSubmit` hook** `~/.claude/skills/hooks/loop-injector.sh` injects a `<system-reminder>` each turn: the loop prompt (as untrusted data), current iteration vs. max, no-progress streak, the exact verify step, the stop predicates, and the rule "don't `complete` until verify passes or a stop fires."
4. The **`Stop` hook** `~/.claude/skills/hooks/loop-stop-gate.sh` runs `check-stop` when you try to end the turn: if a stop predicate fired it lets you stop (and points you at `complete`); otherwise it blocks and feeds the next cycle back — so the loop *actually loops across turns*. Capped at `LOOP_STOP_MAX` (default 6) per session, fails open, kill switch `LOOP_STOP_MAX=0`.

## Verification is hybrid-but-honest

- **Machine mode** (`--verify "<cmd>"`): the only road to `complete` is the command exiting 0, or a stop predicate firing. Reproducible; this is what makes a loop trustworthy.
- **Self mode** (no `--verify`): the agent judges the prose criterion. The steering says so out loud, `complete` requires `--evidence "<proof>"`, and the stop predicates still bound it — a self-graded loop can never run forever or silently fake rigor.

`verify` (did *this iteration* succeed?) and the optional `--stop "target=<cmd>"` (is the *whole loop* done?) are different axes — set both when they differ.

## Subcommands

Always invoke via Bash:

```bash
bash ~/.claude/skills/loop-runner/scripts/loop.sh <subcommand> [args]
```

| Subcommand | Effect |
|---|---|
| `start <slug> [--prompt "…"\|--file f.json] [--verify "<cmd>"] [--stop "max-iter=N,no-progress=M,target=<cmd>"] [--title …]` | Pull a loop from the live catalog by `slug` (or load `--file`/`--prompt`); write state + ledger; open the bd issue. No `--verify` ⇒ self mode. Stop defaults: `max-iter=10,no-progress=2`. |
| `verify` | Machine: run the verify cmd, log exit + output tail. Self: print the criterion + how to record evidence. |
| `record "<action>" [--evidence …] [--verify-exit N] [--decision continue\|stop\|blocked]` | Append one ledger line; bump iteration; update the no-progress streak (resets on a verify pass). |
| `check-stop` | Print `continue` or `stop:<reason>` (`target` met / `max-iter` / `no-progress`). |
| `continue` | Print the next-cycle steering block (the seam for the future `/loop` / `ScheduleWakeup` bridge). |
| `status` / `show` / `list` / `ledger` | Inspect the active loop, raw state, all loops on record, or the run trajectory. |
| `pause` / `resume` | Suspend / re-enable the gate without losing state. |
| `abort ["reason"]` | End the loop unfinished; keep the ledger; mark the bd issue deleted. |
| `complete [--evidence …] [--force]` | Mark done — **refused** unless machine-verify last exited 0, OR a stop predicate fired, OR (self) `--evidence` was given. Closes the bd issue. |

## How to invoke from `/loop-run …`

| User said | Run |
|---|---|
| `/loop-run <slug>` | `start <slug>` — if the loop is fuzzy (docs/copy/cleanup) it's fine to run self mode; if it has a natural test/build, propose a `--verify` command and confirm with the user before starting. |
| `/loop-run <slug> --verify "<cmd>"` / with `--stop …` | pass through to `start`. |
| "run this loop until the tests pass" | `start … --verify "<test cmd>" --stop "target=<test cmd>"`. |
| `/loop-run status` / `ledger` / `pause` / `resume` / `abort` / `complete` | the matching subcommand (for `complete`, do the completion audit first). |
| find a loop first | the loop-library *catalog* is the discovery layer; resolve a slug there (or `curl …/catalog.json`), then `start` it here. |

Report the script's stdout to the user in 1–2 sentences; for `start`, mention the bd id and verify mode.

## Binding a prose loop to a machine contract

Catalog loops carry no runnable check. Before `start`, decide the machine contract — see `references/adapt.md`. The six-step cycle the injector enforces is in `references/run-protocol.md`.

## What this is NOT

- Not the catalog/discovery/audit tool — that's Loop Library itself (find/adapt/Loop-Doctor). This skill *runs* a loop you've already chosen.
- Not an unattended scheduler (yet). v1 loops in-session via the Stop-gate; the `continue` verb exists so bridging to `/loop` or `ScheduleWakeup` is a one-liner later.
- Not a way to skip approval — destructive/external/consequential actions inside a loop still need user sign-off; the steering says so every turn.
