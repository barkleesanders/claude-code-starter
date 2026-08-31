---
name: security-deep
description: Deep security review of a git diff with proof-of-exploitability and auditable coverage. Use when the built-in /security-review is not enough — when you need evidence a vulnerability is real (PoC, not vibes), proof that EVERY changed file was reviewed, or expansion to sibling instances of the same flawed pattern. Triggers on "deep security review", "security audit this branch", "prove this vuln is exploitable", "did you check every file", "security-deep", "/security-deep". For a fast PR-noise-filtered pass, use the built-in /security-review instead.
allowed-tools: Bash, Read, Glob, Grep, LS, Task, Write, Edit
---

# Deep Security Review

The built-in `/security-review` is a single read-only pass: find vulns, filter false
positives at confidence ≥ 8, emit markdown. It is well-tuned and fast. It has three
structural gaps, and this skill exists **only** to close them:

| Gap in `/security-review` | What this skill adds |
|---|---|
| Never executes anything — "confidence 8" is an assertion | **Validation**: build a PoC, or record an explicit *proof gap* |
| No record of what was reviewed | **Coverage ledger**: every changed file gets a receipt or a stated deferral |
| Reports one representative sink | **Sibling expansion**: the same changed pattern usually has more instances |

Everything else — the vulnerability taxonomy, the exclusion list, the confidence bar —
is inherited unchanged, because it is already good.

**Route to the built-in `/security-review` instead when:** the diff is small, the user
wants a quick PR pass, or nothing in the diff touches a trust boundary. Do not run this
skill by default. It is slower and writes files.

> **This skill requests unrestricted `Bash`, unlike `/security-review`, which is read-only
> by design.** That is inherent to Phase 3 — you cannot prove exploitability without
> running something. Expect permission prompts for builds, tests, and PoCs; approving each
> one is the intended friction, not a bug. If you want a review that never executes
> anything, use `/security-review`.

---

## Hard rules

1. **A finding without evidence is a hypothesis.** Every reported finding carries either
   reproduction evidence or an explicit, named proof gap. Never present an untested
   inference as a confirmed vulnerability.
2. **Coverage is a claim that must be provable.** Do not say "reviewed the diff" until
   every row in the worklist has a receipt. A file you skipped is `deferred` *with a
   reason*, never silently absent.
3. **Never write a PoC that attacks a third party.** PoCs run against the local
   repo/build only. No network targets you do not own.
4. **PoCs are throwaway.** Write them under `<scan_dir>/poc/`. Never commit them, never
   leave them in the source tree.
5. **Phases stay separate and in order.** Do not let discovery bias validation, or
   validation bias severity. Complete each phase before reading the next.
6. **Suppression needs evidence too.** Dropping a candidate requires a stated reason
   (unreachable / already-guarded / not-attacker-controlled) — not silence.

---

## Setup

```bash
LEDGER=~/.claude/skills/security-deep/scripts/ledger.sh
BASE=$(git merge-base origin/HEAD HEAD)                  # or user-specified base
SCAN_DIR=".security-scan/$(git rev-parse --short HEAD)"

"$LEDGER" init "$SCAN_DIR" "$BASE"    # builds worklist.txt = files that MUST get a receipt
```

Add `.security-scan/` to `.gitignore` if it is not already ignored. If the user names a
different base, PR, or commit range, use theirs.

Ledger commands (full reference: `ledger.sh` header comment):

| Command | Use |
|---|---|
| `"$LEDGER" review  "$SCAN_DIR" <file> [note]` | file reviewed, nothing found |
| `"$LEDGER" defer   "$SCAN_DIR" <file> <reason>` | could not review — reason is mandatory |
| `"$LEDGER" add     "$SCAN_DIR" <file> <line> <category> "<claim>"` | new candidate → prints its id |
| `"$LEDGER" validate "$SCAN_DIR" <id> <disposition> "<evidence>"` | record Phase 3 result |
| `"$LEDGER" status  "$SCAN_DIR"` | progress |
| `"$LEDGER" check   "$SCAN_DIR"` | **gate** — exit 1 if incomplete |

---

## Phase 1 — Threat model (repository scope, not diff scope)

Before reading the diff, answer these about the **repository**:

- Who are the in-scope attackers? (unauthenticated internet, authenticated tenant,
  co-tenant, local operator, CI, supply chain)
- What are the trust boundaries the code enforces?
- What is worth stealing here? (credentials, PII, tenant data, signing keys, money)
- What security frameworks/helpers already exist, and what is the established safe pattern?

Write it to `$SCAN_DIR/threat-model.md`. Keep it ~15 lines.

**Do not let the diff narrow this.** A threat model derived from the changed subsystem is
worthless for the next diff, and it makes you miss the impact of what changed. This
asymmetry is deliberate: Phase 1 is repo-scope, Phases 2+ are diff-scope.

---

## Phase 2 — Discovery (diff scope, with sibling expansion)

Read every file in `worklist.txt`. For each, look for the categories in
`references/vulnerability-taxonomy.md`.

**Then expand to siblings.** This is the highest-value step in the skill and the one the
built-in review has no equivalent for. When the diff changes a *shared* thing:

> a route handler · a guard/middleware · a query builder · a serializer or deserializer ·
> a path/filesystem helper · an archive utility · an auth/authz helper · a template
> pattern · a wrapper around any of the above

…then the same flaw almost always exists at the other call sites that the change also
reaches. Enumerate them:

```bash
git diff "$BASE"...HEAD | rg '^\+' | rg -oE '\b(function|def|fn|const)\s+\w+' | awk '{print \$2}' | sort -u
rg -n 'changedHelperName' -g '!*.test.*' -g '!*.spec.*'    # every call site
```

Rules for expansion:
- Carry each sibling as its **own candidate**, with its own source → control → sink → impact.
- An **unchanged** sibling is context and a negative control. Report it **only** if the
  diff makes it newly reachable, or changes the guard/sink it depends on.
- When a changed wrapper delegates to a shared sink, keep **both** addressable — do not
  let wrapper-only evidence replace the root sink.
- Stop when the pattern family is exhausted. Do **not** drift into a repo-wide scan.

Record each candidate in the ledger:

```bash
"$LEDGER" add "$SCAN_DIR" <file> <line> <category> "<one-line claim>"    # prints candidate id
```

If discovery yields no technically plausible candidate: mark every worklist row reviewed,
skip Phases 3–4, and report clean. That is a legitimate outcome — say so plainly.

---

## Phase 3 — Validation (prove it, or name the gap)

For each candidate, pick the **strongest method that is proportionate** — read
`references/validation-protocol.md` for the full ladder. Summary, best first:

1. **End-to-end through the real interface** — HTTP request, CLI invocation, file parse,
   RPC, queue message. Craft input that reaches the sink. This is the gold standard.
2. **Focused test** — if a harness already covers the path, add the smallest test that
   asserts the *vulnerable* behavior.
3. **Debugger / sanitizer** (native code) — `gdb -q -batch -ex run -ex bt -ex quit`,
   `lldb -b -o run -o bt -o quit`, ASan, valgrind.
4. **Static trace** — when dynamic execution needs services, secrets, or infra you do not
   have. Trace source → control → sink → reachability and record **counterevidence** and
   the **exact proof gap**.

Missing internal infrastructure is a **proof gap, not suppression evidence**. "I could not
run it" ≠ "it is not exploitable."

Every candidate exits with exactly one disposition:

| Disposition | Meaning |
|---|---|
| `confirmed` | Reproduced. PoC or trace artifact saved under `$SCAN_DIR/poc/`. |
| `probable` | Static trace is complete and sound, but unreproduced. Proof gap named. |
| `suppressed` | Not exploitable, **with the evidence that shows why**. |
| `deferred` | Could not assess. States exactly what is blocking. |

```bash
"$LEDGER" validate "$SCAN_DIR" <candidate_id> <disposition> "<evidence or proof gap>"
```

---

## Phase 4 — Severity and attack path

Only now assign severity, using `references/severity-policy.md`.

The rule that matters most: **for HIGH or above, the impact must be materially
security-relevant** — account takeover, auth bypass, real privilege escalation, meaningful
data exposure, credible RCE — *and* reachable by an in-scope attacker from the threat
model. A real bug that is not a security vulnerability is `ignore`, not `low`. If
justifying HIGH takes a long speculative argument, it is not HIGH.

Apply `references/false-positive-policy.md` last, as a final adjustment pass. Anything it
excludes is dropped regardless of how interesting it is.

---

## Phase 5 — Report

**Gate before writing anything:**

```bash
"$LEDGER" check "$SCAN_DIR"     # non-zero exit = coverage incomplete
```

If it fails, you are not done. Go finish the rows or mark them `deferred` with reasons.

Report format:

```markdown
# Security Review — <base>...<head>

**Coverage:** N/N changed files reviewed · M candidates · C confirmed · P probable · S suppressed
<if any deferred: **Deferred:** file — reason>

## Vuln 1: <category>: `path/to/file.py:42`
* **Severity:** High
* **Status:** Confirmed — PoC at `.security-scan/<sha>/poc/vuln1.py`
* **Description:** …
* **Attack path:** <in-scope attacker> → <entry point> → <control bypassed> → <sink> → <impact>
* **Evidence:** <what reproduced, or the exact proof gap>
* **Siblings:** `other/file.py:88` (same changed helper, also confirmed)
* **Recommendation:** …
```

State coverage honestly in the first line. A review of 12 of 30 files that says so is
useful; one that implies 30 is a lie.

---

## References

| File | Load when |
|---|---|
| `references/vulnerability-taxonomy.md` | Phase 2 — what to look for |
| `references/validation-protocol.md` | Phase 3 — the full method ladder |
| `references/severity-policy.md` | Phase 4 — severity calibration |
| `references/false-positive-policy.md` | Phase 4 — final exclusion pass |
| `scripts/ledger.sh` | Phases 2–5 — coverage receipts |

## Attribution

Sibling-expansion, the validation ladder, proof-gap recording, the ledger-receipt model,
and the severity policy are adapted from **`openai/codex-security`** (Apache-2.0,
© OpenAI) — specifically `_bundled_plugin/skills/{security-diff-scan,validation,
attack-path-analysis}` and `references/shared-hard-rules.md`. Condensed and retargeted
from Codex's MCP/goal plumbing to Claude Code's tools.

The vulnerability taxonomy and false-positive policy are Anthropic's, from the built-in
`/security-review` skill (see `references/false-positive-policy.md` for provenance).
