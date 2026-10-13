# Refactor mode — the structure changes, the behavior does not

Ported from cursor/plugins `pstack` (`playbooks/refactoring.md`, `e31650e`). Adopted 2026-09-17.
Distinct from **feature** (adds behavior) and **debug** (corrects it). This is the
focused-to-medium structural change: rename, extract, inline, dedupe, move, reshape.

## Steps (in order — the order IS the discipline)

1. **Pin the contract first.** Before any structure moves, capture current behavior in a
   form that fails when behavior changes: a characterization test (call the code the way
   its users do, assert literal outputs over a representative input set), a snapshot of
   real outputs, or an equivalence harness (old-vs-new output diff / a recorded baseline
   replayed). If the area has no coverage, write the pin before touching anything.
   **`tsc --noEmit` and lint are not a pin** — they prove it compiles, not that it
   behaves. Commit the pin as its own commit so the sequence reads red→green.
2. **Name the structure the code is missing.** A state machine over scattered booleans, a
   table/registry over branching, a typed model over repeated shape assumptions, the
   right collection. The reshape must *delete* branches or invalid states, not add
   indirection. Boring code that is already clear and local stays boring.
3. **Name the target shape** — what the module layout, types, and call graph would be if
   built today. If it crosses a function boundary, sketch signatures first.
4. **Subtract before you add.** Delete dead code, collapse one-caller wrappers, drop
   redundant validators, remove orphan references — *then* introduce the new shape on
   the simpler base. A speculative cleanup that "might help" gets reverted.
5. **Move in small behavior-preserving steps, each keeping the pin green.** For API
   reshapes, migrate every caller and delete the old API in the same wave — no
   compatibility shims, no parallel old-and-new paths. Spot-check every rename against
   the actual files: renames silently miss usages in strings, prose, tests, and
   back-references (`grep -rn '<old>'` must return only what you intend).
6. **Prove behavior is unchanged on the real artifact**, not "it compiles": run the pin,
   run the equivalence check, and for anything user-facing drive the real surface once.
   Own the verification yourself; a delegate's "looks good" summary is not proof.
7. **Confirm the change is worth keeping.** The acceptance criterion is *reduced reader
   load*: fewer layers between question and answer, less hidden state, fewer files to
   trace, collapsed one-caller wrappers. If the diff does not lower reader load
   somewhere, revert it — a refactor that only rearranges complexity is a net loss.
8. **Order the commits so the sequence proves itself:** pin → subtraction → reshape →
   follow-on cleanup. Each stands alone.

## Fences

- If the cleanup reveals a **bug**, split it out: ship the structural change first
  against the pinned contract, fix the bug in its own change with its own failing test.
- If it reveals a **missing feature**, same: name it, route to feature mode after.
- A redesign is allowed, but name it as one and route to feature mode.
- Large or cross-cutting structural work (many call sites, several subsystems) is a
  planned migration, not this playbook — plan it as verifiable units first.
- Fix-All-Issues still applies to what the diagnostics surface; No-Suppression still
  applies to every type or lint complaint the reshape produces.

**Reply:** the structure that changed, the pin you held it against, the equivalence proof
(command + output), the reader-load delta in concrete terms, what shipped and what got
reverted. No new behavior.
