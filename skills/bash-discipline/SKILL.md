---
name: bash-discipline
description: Write bash that fails LOUDLY instead of returning a plausible wrong answer. Use when running sweeps/loops over many items, fetching files with curl, extracting fields from data files, or any time a command's output will become a factual claim. Provides the `bashguard` linter, a trap catalog, and the positive-control discipline.
---

# Bash Discipline

**The axiom: a command that fails loudly is cheap. A command that returns a plausible wrong number is expensive.**

Every rule in this skill comes from a command that exited 0 — or failed in a way that looked like someone else's fault — while the conclusion drawn from it was false. Loud failures self-correct in one round-trip. Silent ones get written into reports, memories, and recommendations.

## The tool

```bash
bashguard check '<command>'      # lint before running   (0 clean · 1 warn · 2 high)
bashguard check --brief --stdin  # what the PreToolUse hook uses
bashguard rules                  # list all rules
bashguard explain BG001          # rule + fix + the incident behind it
bashguard selftest               # NEGATIVE CONTROL — proves each rule fires AND stays quiet
```

`~/tools/bashguard`. The PreToolUse hook `pre-bash-guard.sh` runs it automatically and is **advisory only** — it never blocks. Silence one command with `BASHGUARD_OFF=1`.

**After ANY edit to the rules, run `bashguard selftest`.** A linter with a broken regex reports "clean" on everything, which is indistinguishable from clean code — the precise failure shape the tool exists to catch. The selftest caught a real false positive within a minute of the first rule being written.

## The three habits (do these regardless of the linter)

### 1. Positive control before you trust a sweep
Before running a loop over N items and reporting a tally, **run one item you KNOW is good and assert it passes.** If the control fails, the instrument is broken and the sweep result is void — do not report it.

An all-negative sweep is far more often a broken loop than a real finding. Reference: a 40-item PDF sweep returned 40/40 "unreadable"; the corpus was fine, the loop was concatenating its inputs.

### 2. Three outcomes, never two
Never collapse to pass/fail. Always distinguish:

| | meaning |
|---|---|
| `ok` | measured, and it is good |
| `bad` | measured, and it is genuinely bad |
| **`could not measure`** | the instrument did not run — **not** a finding |

Collapsing the third into the second is how "0 matches" becomes "not present" and how a parse failure becomes "clean."

### 3. Check the status, not the file
`curl -o out URL` writes 403 and 404 bodies to disk and exits 0. Anything that consumes `out` afterward is parsing an error page. Either capture `%{http_code}` or use `--fail`.

## Trap catalog

Eight rules, each with a real incident: `references/trap-catalog.md`, or `bashguard explain <ID>`.

| ID | Severity | Trap |
|---|---|---|
| BG001 | HIGH | `for X in $VAR` — **zsh does not word-split**; the loop runs once |
| BG002 | HIGH | field from a CRLF file carries `\r`, corrupting every URL built from it |
| BG003 | HIGH | `curl -o` with no status check — error pages written as data |
| BG004 | HIGH | counter mutated in a piped `while read` — lost to the subshell |
| BG005 | warn | relative script path with no `cd` — the harness resets cwd between calls |
| BG006 | warn | `2>/dev/null` on the command whose result you then count |
| BG007 | warn | pass/fail sweep with no positive control |
| BG008 | warn | pipeline exit status branched on without `pipefail` |

## Related, non-overlapping

- `pre-bash-negative-result-guard.sh` — `grep`/`rg` **pattern** traps (BSD `$` anchor, ambiguous match)
- `pre-bash-no-truncate-listing.sh` — `| head -N` on enumerations
- CLAUDE.md **Negative-Result Rule** — the judgment-level version of habit #1
- CLAUDE.md **"Compared to What?" Rule** — calibrating the result once you trust it

This skill covers the mechanical layer: loop, fetch, and data-integrity shapes that are detectable *before* the command runs.
