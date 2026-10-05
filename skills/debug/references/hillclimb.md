# Hillclimb mode — one change, one measurement, keep or revert

Ported from cursor/plugins `pstack` (`playbooks/hillclimb.md`, `e31650e`). Adopted 2026-09-17.
For **sustained** improvement of one metric against a target. A one-off fix is debug or
`/code optimize`; this is the loop. The denominator still comes from
`performance-ceiling.md` — report the final number as a **gap to the floor**, never as a
delta from the start.

Core discipline: never stack untested changes, never claim a win from code inspection.

## Steps

1. **Ground the workload before choosing the metric.** Understand the target's
   architecture, name the realistic workload dimensions that can move the result (data
   size, history, state, concurrency), and pick a case that *reproduces the user's
   complaint*. If no case reproduces it, fix the repro instead of hillclimbing. Then fix
   one metric, the direction that counts as better, and a **stop predicate that pairs a
   target with a floor on attempts** ("≥50% better than baseline AND ≥10 iterations") so a
   lucky early win cannot end the run. Use the user's numbers when given.
2. **Build the measurement harness, prove its sensitivity, then freeze it.** Run
   contrasting realistic workloads: the target case must show the symptom and easier cases
   must separate as expected. If the harness cannot distinguish them, revise the workload
   or the metric — an insensitive harness makes every later "win" noise. Once frozen, one
   repeatable command emits the metric, sampled enough to clear the noise (**median of N,
   never a single run**; state N and the observed spread). Record the baseline and a green
   run of the regression gate (the tests that must keep passing) before any change.
3. **Open the decision log.** `decisions.tsv` in the work dir (gitignored), one row per
   attempt: `id, hypothesis, change, before, after, delta, tests, verdict(kept|reverted),
   note`. Read it before each attempt so you do not retry a rejected idea.
4. **Ground each hypothesis in a mechanism** from step 1 — "defer X off the boot path
   because it blocks first paint", not "try memoizing something". The eight strategy
   families are generators, not a checklist, and a family earns an attempt only when the
   measurement shows the signal it names: elimination, divide-and-conquer, caching (name
   what invalidates it), indirection (index / queue / handle), batching, redundancy
   (hedged requests — only with headroom), lazy evaluation, scheduling (measure the
   interactive path, not total work).
5. **Loop, one hypothesis per iteration.** Measure before and after with the frozen
   harness; run the regression gate. **Accept only when the metric moves past noise and
   the gate stays green; otherwise revert the change in full.** A tweak that "might help"
   is not kept. One commit per accepted fix, staging only the files you changed
   (`git add <files>`, never `-A`). Log the row either way. When several independent
   hypotheses are live, run them in separate worktrees, never on one branch.
6. **Push past the first plateau.** On a stall (several rejects in a row) pivot the
   strategy family, combine near-misses, re-read the source, or try something more
   radical before concluding the hill is climbed. Correctness and simplicity outrank the
   number: revert a win that breaks behavior; keep a simplification that holds the number.
7. **Stop when the predicate is met**, or when the remaining ideas are marginal and not
   worth their cost. Never relax the predicate to meet it; never quit while cheap untried
   hypotheses remain. If stuck, surface it instead of spinning.
8. Deliver the accepted commits in the order they landed.

## Traps this loop exists to catch

- A single-run "win" inside the noise band (hence median-of-N and a stated spread).
- Two changes measured together, then the wrong one credited (hence one per iteration).
- A harness that was never shown to separate a good case from a bad one (hence step 2).
- Declaring convergence from a plateau (Compared-to-What: >~5–10× off the floor is not
  converged; suspect the approach, not the tuning).

**Reply:** metric and target; baseline → final with % delta *and* the floor it is measured
against; iterations run (kept vs reverted); each accepted fix on one line; the
`decisions.tsv` path; the best untried idea if pushed further.
