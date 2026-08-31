# Severity and Attack-Path Policy

**Provenance:** condensed from `openai/codex-security` (Apache-2.0, © OpenAI),
`_bundled_plugin/skills/attack-path-analysis/references/severity-policy.md`.

Apply **after** validation has established reachability and counterevidence — never
before. Severity assigned during discovery is a guess.

---

## The governing rule

For **HIGH or above**, the impact must be *materially security-relevant* — account
takeover, auth bypass, meaningful privilege escalation, significant sensitive-data
exposure, credible RCE, or comparable compromise — **not merely a bug or strange
behavior**.

And: *a professional security reviewer should not need a long speculative argument to
justify it.* If your justification is a chain of "and then if the operator also…", it is
not HIGH.

Corollaries:

- Do **not** promote ordinary bugs to high/critical because they are bugs.
- Do **not** keep `critical` on contrived or edge-case-only exploit stories unless the
  threat model explicitly puts those conditions in scope. **Critical means "demands
  attention now."**
- Do **not** rely on unusual operator mistakes, internal-only access, or
  non-attacker-reachable paths to justify severe external impact — unless the repo's
  threat model says those actors/paths are in scope.
- A real bug that is **not** a security vulnerability → `ignore`, not `low`.
- Provably not a bug at all (claim is wrong) → `ignore`, marked false positive.

---

## CRITICAL — typical qualifiers

Each requires *proof* that attacker input reaches it from an in-scope attack surface.

- Credible RCE / arbitrary code execution: command injection, LFI-exec, trivially
  exploitable memory corruption.
- Real XSS **with proven impact** — session/token theft, account compromise, privileged
  action execution.
- Account takeover or strong authentication bypass, especially 0-click.
- Missing authorization / authz bypass / tenant-boundary break — trivial IDOR, swappable
  org or object IDs with no authz.
- Severe sensitive-data leak (LFI, path traversal, unscoped file download) with proof the
  attacker reads secrets, PII, signing keys, credential stores, or private keys.
- SQL/NoSQL/query injection with a proven path from attacker input *and* proven impact.
- Sandbox, container, VM, browser, or interpreter escape breaking an isolation boundary.
- SSTI leading to RCE or secret disclosure, with proof the templating library is
  exploitable that way and is reachable.
- Arbitrary file write into executable, startup, config, or firmware paths with a
  realistic path to persistence or execution.
- Logic flaws enabling irreversible or broad integrity compromise at scale —
  unauthenticated deletion of others' data, cross-tenant tampering, unauthorized change
  of security-critical config.

**Escalators (plausible HIGH → CRITICAL):** unauthenticated or near-unauthenticated
reachability from the internet or another broad in-scope surface.

---

## HIGH — typical qualifiers

- **SSRF** where you can prove (a) the attacker controls the URL, bypassing protections,
  from an in-scope surface, *and* (b) reachable internal/LAN/cloud/metadata services exist.
  Careful with webhooks — but a product-intended webhook/callback is **not** suppression
  evidence when attacker-controlled destinations still reach internal, metadata,
  file-backed, redirect, or side-effecting targets.
- Exploitable memory corruption with clear major impact or easy exploitation.
- Arbitrary file read exposing less-sensitive user data or source. (If it reveals env
  secrets → critical.)
- **CSRF** enabling important state changes — credential, permission, payment/billing, or
  security-setting changes with realistic victim interaction. Evaluate actual browser
  request behavior, credential attachment, cookie policy, preflight, server parsing, and
  effective anti-CSRF controls. *An HTTP method or JSON content type alone is not a
  categorical defense.*
- Hardcoded or default credentials that are valid, reachable, and grant meaningful access.
- Cryptographic failures allowing signature/token/artifact forgery, secure-channel bypass,
  or decryption of highly sensitive data — with proof the attack is practical from an
  in-scope surface.
- Supply-chain or update-channel compromise — malicious code or artifacts delivered to
  users/servers/agents, signing bypass, package-source substitution. Focus on real CI and
  update-channel risk, **not** "npm reports outdated packages."
- Authorization bypass / IDOR / privilege escalation that is narrower than the critical
  cases — smaller object set, same-tenant boundary.
- XXE with proof the attacker controls the XML *and* the engine is XXE-vulnerable.
- Dangerous upload/file handling enabling stored active content, trusted-origin script
  execution, or meaningful content-type confusion — with both upload and access reachable.
- Deserialization / SSTI / plugin / macro / interpreter abuse where dangerous primitives
  are clearly reachable and impactful, but full RCE is not proven to critical's standard.

---

## MEDIUM

Requires specific conditions but has significant impact. Per the false-positive policy,
**report MEDIUM only when obvious and concrete.**

## LOW

Defense-in-depth or genuinely lower-impact issues. Prefer `ignore` if it is not actually a
security problem.

---

## Attack-path statement (required on every reported finding)

Write the path explicitly. If you cannot fill every arrow, the severity is too high or the
finding belongs in `probable`/`deferred`:

```
<in-scope attacker> → <entry point> → <control bypassed or absent> → <sink> → <impact>
```

**Counterevidence is mandatory.** Before finalizing, actively look for the thing that
would make this NOT exploitable — an upstream guard, a framework default, a deployment
constraint, a type restriction. Record what you looked for and what you found. A finding
where you never searched for counterevidence is not validated.
