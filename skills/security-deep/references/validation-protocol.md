# Validation Protocol

**Provenance:** adapted from `openai/codex-security` (Apache-2.0, © OpenAI),
`_bundled_plugin/skills/validation/SKILL.md` and
`references/static-finding-assessment.md`.

The built-in `/security-review` is explicitly barred from running anything — its
confidence score is an inference about code it read. This phase replaces inference with
evidence where evidence is obtainable, and **names the gap** where it is not.

---

## Before you start

Write a short rubric — up to five criteria — for what would make *this specific candidate*
real. Do it **before** testing, so you cannot rationalize a result afterward.

Then state three things explicitly:

- **Attacker input** — what value the attacker controls, and where it enters.
- **Sink** — the exact line where it becomes dangerous.
- **Preconditions** — auth state, config, feature flags, deploy shape.

If you cannot name all three, the candidate is under-specified. Go back to discovery.

---

## Method ladder — strongest feasible, proportionate to the candidate

### 1. Realistic interface reproduction (gold standard)

The code exposes a genuine user-reachable interface: HTTP, CLI, file parser, RPC, message
queue, plugin hook, package API. Craft minimal input that reaches the sink and observe the
vulnerable behavior.

Trigger it **the way an attacker would** — against the actual application or library, not
by calling the private function directly. Calling the sink in isolation proves the sink is
dangerous; it does not prove it is *reachable*, which is the actual question.

### 2. Focused test

The vulnerable path is already covered by a test harness. Add or adapt the **smallest**
test that exercises the path and asserts the vulnerable behavior. Cheap, reproducible,
reviewable — and it can be handed to the fix as a regression test.

### 3. Crash / sanitizer / debugger (native code)

For crash, memory-corruption, or parser-confusion candidates, when the project builds with
bounded effort:

```bash
# debug build → minimal crashing PoC
# then, if it does not reproduce immediately:
valgrind --error-exitcode=1 ./target poc_input
clang -fsanitize=address,undefined -g …            # ASan/UBSan build

# non-interactive only — never leave an interactive debugger open
gdb  -q -batch -ex run -ex bt -ex quit --args ./target poc_input
lldb -b -o run -o bt -o quit -- ./target poc_input
```

### 4. Static trace (fallback — and legitimate)

Use when dynamic execution is blocked by missing services, unavailable infrastructure,
secrets you do not have, or setup effort disproportionate to the candidate. Also the
correct default for large internal repos where runtime needs cloud accounts, service
meshes, or production data.

A static assessment is complete only when it records **all** of:

| Element | Question |
|---|---|
| **Source** | Where exactly does attacker-controlled data enter? |
| **Control** | What is the closest guard/validation, and why is it insufficient or absent? |
| **Sink** | The exact file:line where it becomes dangerous. |
| **Reachability** | Is there a real call path from an in-scope entry point? Show it. |
| **Boundary** | Which trust boundary is crossed? |
| **Counterevidence** | What did you look for that would *disprove* this? What did you find? |
| **Proof gap** | Precisely what remains unproven, and what would close it. |

**Missing internal infrastructure is a proof gap, not suppression evidence.** Write
`deferred: requires staging Postgres to confirm the injection executes`, not `suppressed`.

---

## Guardrails

- Prefer short, bounded commands. Avoid interactive editors and unbounded repo-wide scans.
- **No network access to anything you do not own.** Local build, local service, localhost.
  A PoC that fires at a third-party host is out of scope for this skill, always.
- Save every PoC, crafted input, and log under `<scan_dir>/poc/<candidate_id>/`.
- PoCs are throwaway artifacts. Never commit them. Never leave them in the source tree.
- If a PoC would be destructive (drops data, writes outside a temp dir, mutates shared
  state), do **not** run it — demonstrate the primitive at the smallest safe scope and
  record the rest as a proof gap.

---

## Dispositions — exactly one per candidate

| Disposition | Bar |
|---|---|
| `confirmed` | Reproduced. Artifact saved. Attack path fully instantiated. |
| `probable` | Static trace complete — all seven elements above filled — but unreproduced. Proof gap named. |
| `suppressed` | Not exploitable, **with the evidence**: the guard that stops it, the type that constrains it, the deployment fact that makes it unreachable. |
| `deferred` | Could not assess. States exactly what blocked it and what would unblock it. |

`suppressed` requires evidence in the same way `confirmed` does. "I did not find a way to
exploit it" is `deferred`, not `suppressed` — the difference matters, because `suppressed`
tells the next reviewer to stop looking.

---

## Preserve instances

If discovery found the same flaw at several call sites (sibling expansion), validate each
one. **Do not collapse siblings into a single representative finding** — one may be
reachable while another is guarded, and merging them loses exactly that distinction.

Each sibling carries its own source, control, sink, impact, and disposition.
