# Performance Ceiling Discipline — "compared to what?"

> Loaded by the `performance-oracle` agent (ceiling-first gate), the `perf-ceiling-check.sh`
> Stop hook, and any `/carmack` perf work. The one rule: **a delta-from-start is not a result.
> A gap-to-floor is.** This is the **optimization instance** of the general "Compared to What?"
> principle — `~/.claude/skills/shared/ground-truth-calibration.md`.

## Why this exists (the renderer-psychosis incident)

2026-05-29: A Ralph loop spent ~4 hours and ~$350 optimizing a naive Go renderer (a port of
Ghostty's core render state, identical data layout + validation tests). It drove:

- frame time **88 ms → 1.5 ms** (~60×)
- allocations **150,000 → ~500** (~300×)

Spectacular-looking. **Wrong.** The hand-written reference renderer hits **~20 µs (0.020 ms)
and ZERO allocations** in the update path — the loop landed **~75× short** and never knew it.

Root cause: nothing in the loop ever computed a *denominator*. Every number was framed against
the 88 ms / 150K starting point — the one reference guaranteed to flatter any result. The loop
is a hill-climber; its `stall` counter (no improvement for N rounds) is a **local-optimum
detector being misread as a victory signal**. 1.5 ms was the top of the hill *inside the naive
architecture*. The loop had no concept of a second hill, so it could not see it was 75× short.

The achievable target was knowable two ways the loop ignored: (a) a **known-good reference impl
existed** (the hand-written port), and (b) the **physical floor** for allocations in an update
path is *zero*, and for frame time is computable from working-set bytes ÷ memory bandwidth.

## The gate — run BEFORE reporting any optimization result as "good"

State all four, explicitly, in the output. If you skip one, you have not finished.

1. **Physical floor (roofline).** Estimate the lower bound from first principles:
   - Compute/time: `working-set bytes ÷ memory bandwidth` (or FLOPs ÷ peak FLOP/s, or
     `irreducible work × cost-per-unit`). A few hundred KB at ~50 GB/s ≈ low single-digit µs.
   - **Allocations in a hot / per-frame / update path: the floor is ZERO**, not "lower".
     Any nonzero count is a smell to *justify or eliminate*, never a number to merely shrink.
     500 is not "great" — 500 is "why not 0?"
2. **Known-good reference.** Ask out loud: *does a correct reference implementation of this
   exist?* (Another language, an upstream lib, a hand-written version, a sibling module, the
   prior commit before a regression.) If yes, that — not the starting point — is the denominator.
3. **The gap, stated as `X now / Y floor / N× off`.** Not "N× faster than start." If you are
   **> ~5–10× off the floor, the result is NOT converged** — suspect the architecture / data
   layout / algorithm, not the loop. Report it that way regardless of how good the delta looks.
4. **Micro vs. architectural verdict.** Did you change the *algorithm or data layout*, or just
   tighten the existing one? If only micro-optimizations and you are far from the floor, say so
   plainly: **the architectural ceiling is untested.**

## When you cannot compute the floor

Say so. **"This is faster than where we started, but I don't know if it's actually good"** is
the honest, calibrated report — and it is the sentence that prompts a human to look. The
psychosis failure mode is *local wins reported with global confidence*. The fix is not a better
number; it is making the uncertainty visible. Silent overconfidence is the bug.

## Plateau handling (loops: Ralph / evo / iterative)

A stalled benchmark means you reached a **local** optimum, not *the* optimum. When the stall
counter trips, the correct action is **step back to the architecture and re-derive the floor**,
not "report best path." Re-ask: is the data layout the constraint? Is there a fundamentally
different approach (dirty-region tracking, preallocated/pooled buffers, zero-copy, SoA vs AoS,
batching, a different algorithm class) that changes the ceiling rather than the constant factor?

## Generalizes beyond rendering

Same discipline for DB latency, bundle size, API p50/p99, cron runtime, token/$ cost, throughput:
**establish the reference frame before reporting the result, and prefer the floor or a known-good
over the starting point.** "60% faster than before" is seductive and nearly meaningless on its own.
