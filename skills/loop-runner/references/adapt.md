# Binding a prose loop to a machine contract

Loop Library records ship as prose. The catalog gives the **shape** of a loop; you supply the **machine contract** that lets it actually run. Do this once, at `start`.

## 1. Read the record's prose

`bash …/loop.sh start <slug> …` pulls `prompt`, `verification {title, detail}`, and `steps[]` from the live catalog. Read `verification` — that English sentence is the success criterion you're about to make checkable (or knowingly leave self-graded).

## 2. Turn `verification` into a `--verify` command (when you can)

Look for a command that returns 0 ⇔ the criterion holds:

| Catalog verification (prose) | `--verify` command |
|---|---|
| "Documentation matches the implementation." | `git diff --quiet` after a docs pass, or a link-checker / `markdownlint` |
| "The suite is green." | `npm test` / `pytest -q` / `cargo test` |
| "No TODOs remain in the module." | `! grep -rq TODO src/module` |
| "The build passes." | `npm run build` / `tsc --noEmit` |
| "Bundle is under budget." | a script that exits non-zero over the threshold |

Pass it: `--verify "<cmd>"`. Now `complete` is gated on exit 0 — reproducible, not vibes.

## 3. When there is no clean command → self mode, openly

Fuzzy loops ("improve the copy", "tidy the docs", "make it feel more polished") often have no honest pass/fail command. **Don't fake one.** Start without `--verify`: the loop is tagged self-graded, the steering tells the model it has no exit code to lean on, and `complete` requires `--evidence "<proof>"`. The stop predicates still bound it.

Prefer machine mode whenever a real check exists — self mode is the fallback, not the default.

## 4. Choose stop predicates

`--stop "max-iter=N,no-progress=M,target=<cmd>"`:
- **target** = the whole-loop finish line as a command (often the same as `--verify`, but can be broader, e.g. verify = "this file lints" while target = "all files lint").
- **max-iter** / **no-progress** = the safety net. Always set these, even with a target, so an unreachable target can't run forever.

Rule of thumb: `target` = "are we done?", `verify` = "did this step help?", `max-iter`/`no-progress` = "when do we give up?".

## 5. Confirm consequential scope before starting

If running the loop could deploy, send, post, delete, or spend, say so to the user and get approval *before* `start` — and remember the per-turn steering still requires approval at the moment of any such action inside the loop.

## Example

Catalog loop `overnight-docs-sweep` (verification: "Documentation matches the current implementation. Finish with a reviewable pull request."):

```bash
bash ~/.claude/skills/loop-runner/scripts/loop.sh start overnight-docs-sweep \
  --verify "npm run docs:check" \
  --stop "max-iter=8,no-progress=2,target=git diff --quiet origin/main -- docs/"
```

Machine-verified each iteration, bounded at 8, stops when docs match main. The PR step (consequential) still asks for approval when the loop reaches it.
