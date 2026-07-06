# The loop cycle (what the injector enforces)

Every turn a loop is active, run exactly **one** cycle. Don't batch many actions; the point is to measure between each one.

1. **Observe** — read fresh state (the relevant files / command output / test results), not your memory of earlier turns. `bash …/loop.sh status` shows the iteration, no-progress streak, and stop bounds.
2. **Choose** — pick the single highest-value, in-scope action toward the loop's prompt. One bounded, reversible change or candidate. If the best next action is destructive, external, or consequential (deploy, send, delete, pay, post), get the user's approval first.
3. **Act** — make that one change.
4. **Verify** — `bash …/loop.sh verify`.
   - *Machine mode:* it runs your `--verify` command; exit 0 means this iteration improved/holds. A non-zero exit is data, not failure of the loop — record it and try a different action next cycle.
   - *Self mode:* inspect real evidence against the criterion. State plainly whether it's met; treat uncertainty as not-met.
5. **Record** — `bash …/loop.sh record "<what you did>" --evidence "<proof>" [--verify-exit N] --decision continue|stop|blocked`. This appends one ledger line and updates the no-progress streak. The ledger is the run's memory: it survives context resets and is the evidence a Loop-Doctor audit needs.
6. **Repeat or stop** — `bash …/loop.sh check-stop`.
   - Prints `continue` → take the next cycle (the Stop-gate will also block a premature exit).
   - Prints `stop:<reason>` (`target` met / `max-iter` / `no-progress`) → stop iterating. Do the completion audit, then `bash …/loop.sh complete` (or `abort` if blocked, `pause` to park it).

## Stop predicates

Set at `start` via `--stop "max-iter=N,no-progress=M,target=<cmd>"`:
- **target** — a command that, when it exits 0, means the *whole loop* is done (e.g. `npm test`, `git diff --quiet`, a grep that finds zero remaining cases). Distinct from per-iteration `verify`.
- **max-iter** — hard ceiling on iterations (default 10). Prevents runaway.
- **no-progress** — stop after this many consecutive iterations with no verify pass (default 2). Catches "spinning without improving."

A good loop usually wants *both* a `target` (the real finish line) and `max-iter`/`no-progress` (the safety net for when the target proves unreachable).

## Honesty rules (non-negotiable)

- Never record an error as success. A failing verify is a failing verify.
- Never `complete` on intent, partial progress, or elapsed effort — only on a real verify pass or a fired stop predicate.
- One action per cycle; verify before recording; record before deciding.
