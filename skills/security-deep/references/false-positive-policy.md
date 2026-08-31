# False-Positive Policy

**Provenance:** transcribed from Anthropic's built-in `/security-review` skill (extracted
from the `claude` binary v2.1.220). This list is the most battle-tested part of that skill
and is inherited here unchanged — `openai/codex-security` has no equivalent, because it
suppresses false positives by attempting exploitation instead. Using both is strictly
better than either alone: validate first (Phase 3), then apply this list (Phase 4).

Apply as a **final adjustment pass**. A finding that survives validation but matches a
hard exclusion is still dropped.

---

## Hard exclusions — drop automatically

1. Denial of Service (DoS) or resource-exhaustion attacks.
2. Secrets or credentials stored on disk, if otherwise secured.
3. Rate limiting or service-overload scenarios.
4. Memory consumption or CPU exhaustion.
5. Lack of input validation on non-security-critical fields without proven security impact.
6. Input-sanitization concerns in GitHub Action workflows, unless clearly triggerable by untrusted input.
7. Lack of hardening measures. Code is not expected to implement every best practice — flag concrete vulnerabilities only.
8. Race conditions or timing attacks that are theoretical rather than practical. Report only if concretely problematic.
9. Vulnerabilities from outdated third-party libraries — managed separately.
10. Memory-safety issues (buffer overflow, use-after-free) in memory-safe languages. These are impossible in Rust; do not report them there or in any other memory-safe language.
11. Files that are only unit tests, or only used when running tests.
12. Log spoofing. Writing unsanitized user input to logs is not a vulnerability.
13. SSRF that only controls the **path**. SSRF matters only if it controls host or protocol.
14. Including user-controlled content in AI system prompts.
15. Regex injection — injecting untrusted content into a regex.
16. Regex DoS (ReDoS).
17. Insecure documentation. Do not report findings in markdown or other docs files.
18. Lack of audit logs.

---

## Precedents — resolved judgment calls

1. Logging high-value secrets in plaintext **is** a vulnerability. Logging URLs is assumed safe.
2. UUIDs may be assumed unguessable and need no validation.
3. Environment variables and CLI flags are **trusted** values. Any attack requiring control of an env var is invalid.
4. Resource-management issues (memory/FD leaks) are not valid findings.
5. Subtle, low-impact web issues — tabnabbing, XS-Leaks, prototype pollution, open redirects — only at extremely high confidence.
6. React and Angular are generally XSS-safe. Do not report XSS in React/Angular components or `.tsx` files unless they use `dangerouslySetInnerHTML`, `bypassSecurityTrustHtml`, or similar.
7. Most GitHub Action workflow vulnerabilities are not exploitable in practice. Require a concrete, specific attack path.
8. **Missing authorization or authentication in client-side JS/TS is not a vulnerability.** Client-side code is untrusted; the backend is responsible for validating and sanitizing all inputs. Same for any flow that sends untrusted data to a backend.
9. Include MEDIUM findings only when they are obvious and concrete.
10. Most vulnerabilities in Jupyter/IPython notebooks (`*.ipynb`) are not exploitable in practice. Require a specific path from untrusted input.
11. Logging non-PII data is not a vulnerability even if the data seems sensitive. Report only if it exposes secrets, passwords, or PII.
12. Command injection in **shell scripts** is generally not exploitable, since shell scripts rarely run on untrusted input. Require a concrete attack path.

---

## Signal-quality criteria

For each surviving finding:

1. Is there a concrete, exploitable vulnerability with a clear attack path?
2. Is this a real security risk, or a theoretical best practice?
3. Are there specific code locations and reproduction steps?
4. Would this be actionable for a security team?

**Confidence bar.** The built-in skill drops anything below 8/10. Keep that bar for
`probable` findings (static trace only). A `confirmed` finding with a working PoC has
already cleared it by construction — reproduction *is* the confidence.

---

## Interaction with validation (important)

Do not use this list to skip Phase 3. The exclusions describe **classes of finding that do
not matter**; validation determines **whether a finding is real**. Applying exclusions
first will cause you to never test the thing that would have proven the bug.

Order: discover → validate → severity → **then** exclude.
