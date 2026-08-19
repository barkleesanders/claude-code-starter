# Advanced workflows

Use this reference after initial triage identifies a concrete question that broad static analysis
cannot answer. Keep project annotations and derived artifacts reproducible.

## Contents

- [Recover symbols and types](#recover-symbols-and-types)
- [Compare versions with Version Tracking and BSim](#compare-versions-with-version-tracking-and-bsim)
- [Trace data and indirect control flow](#trace-data-and-indirect-control-flow)
- [Emulate or debug](#emulate-or-debug)
- [Patch an authorized copy](#patch-an-authorized-copy)
- [Triage malware defensively](#triage-malware-defensively)
- [Scale headless analysis](#scale-headless-analysis)

## Recover symbols and types

1. Load matching PDB, DWARF, dSYM, map files, headers, type libraries, or vendor SDK definitions.
2. Identify compiler/runtime artifacts and apply known function signatures before renaming user code.
3. Create structures and enums from repeated offsets, access widths, constructors, serializers, and
   bounds checks. Apply them at both readers and writers.
4. Fix calling conventions, parameter storage, return types, noreturn functions, and variadic
   signatures before trusting decompiler output.
5. Re-run analysis and decompile after material type changes; stale decompilation can preserve a bad
   earlier interpretation.

For stripped programs, combine strings, imports, constants, call shape, control-flow shape, and
cross-version similarity. Record inferred names as inferences, not recovered ground truth.

## Compare versions with Version Tracking and BSim

Normalize both programs first: same processor/compiler choices, analyzers, symbols, types, and
function-boundary corrections. Hash both source artifacts and keep separate projects or folders.

Use Version Tracking for a focused two-version mapping with address and symbol correlation. Use BSim
for function similarity across many binaries or when addresses and names changed substantially.

The Ghidra 12 BSim CLI uses URL forms, not plain directories:

```bash
BSIM="$GHIDRA_HOME/support/bsim"
DB_URL='file:/absolute/path/to/bsim-db'

"$BSIM" createdatabase "$DB_URL" medium_nosize --name 'version-comparison'
"$BSIM" generatesigs 'ghidra:/absolute/path/to/projects/project-name' \
  /absolute/path/to/signatures --bsim "$DB_URL"
"$BSIM" commitsigs "$DB_URL" /absolute/path/to/signatures
"$BSIM" listexes "$DB_URL" --limit 100
```

Confirm command forms against `"$BSIM"` help for the installed version. BSim similarity is a lead:
inspect mapped functions and explain semantic changes rather than equating score with identity.

## Trace data and indirect control flow

- Begin at a concrete source or sink and traverse references in both directions.
- Recover jump tables, vtables, interface tables, callbacks, Objective-C selectors, Swift metadata,
  JNI registrations, and dynamically resolved imports before declaring an indirect edge unreachable.
- Use backward slicing to identify values that influence a branch, allocation size, copy length,
  command, path, destination, permission, or cryptographic decision.
- Use forward slicing to identify where user-controlled or untrusted values reach parsers, memory
  operations, interpreters, file systems, network APIs, or privilege boundaries.
- Confirm the decompiler's expression against p-code or disassembly when integer width, signedness,
  aliasing, undefined behavior, or stack recovery matters.

## Emulate or debug

Use emulation for small deterministic regions such as decoders, checksums, state machines, or a path
whose inputs and memory map can be modeled. Use Ghidra's p-code emulator and, where installed, the
symbolic-summary/Z3 extension to explore constraints. Experimental symbolic results require manual
validation.

Use debugging only when static evidence cannot establish runtime values or reachability:

1. Choose an isolated VM, emulator, simulator, sacrificial device, or malware sandbox suitable for
   the artifact. Never run untrusted code directly on the workstation.
2. Snapshot the environment and constrain network, credentials, mounts, shared folders, clipboard,
   and host integrations.
3. Map the dynamic module to the static program and verify relocation/base addresses.
4. Break at a specific source, branch, sink, or boundary; record inputs and state needed to reproduce.
5. Reconcile runtime evidence with the static project through comments, labels, types, and bookmarks.

## Patch an authorized copy

Patch only a disposable analysis copy and keep a byte-level record:

1. State the intended semantic change and the instruction/data bytes that implement it.
2. Check instruction width, delay slots, branch reach, relocations, checksums, signatures, code
   directories, and file-layout constraints.
3. Use Patch Instruction or Patch Data, then export in the correct original format.
4. Record original and patched SHA-256 values plus every changed file offset and virtual address.
5. Re-import or disassemble the output to prove the intended bytes and control flow survived export.
6. Re-sign only with the user's authorized identity when required, then test in an isolated setting.

Do not use patching to bypass licensing, DRM, authentication, authorization, payment, or another
access-control decision.

## Triage malware defensively

Static triage may cover unpacking indicators, configuration recovery, capability mapping, persistence,
command-and-control clues, anti-analysis behavior, and detection opportunities. Keep conclusions
behavior-focused and do not turn the analysis into a deployable payload or evasion guide.

- Hash and classify the sample without launching it.
- Identify packers, high-entropy regions, overlays, resources, embedded payloads, and configuration.
- Map imports and resolved APIs into capabilities, then validate interesting paths in code.
- Extract indicators with provenance: address, containing function, decoding path, and confidence.
- Prefer YARA or behavioral detections that avoid fragile, victim-specific, or secret material.
- Move to dynamic analysis only in a dedicated malware sandbox with controlled egress and no valuable
  credentials.

## Scale headless analysis

- Separate import/analysis from export scripts so failed reporting does not discard expensive work.
- Give each concurrent job a distinct project. Do not let workers contend on one local project.
- Cap CPUs and timeouts; record analyzer timeouts as missing evidence, not a clean result.
- Import adjacent libraries with `-librarySearchPaths` or directory mirroring when cross-library flow
  matters.
- Use focused function-name or address filters for repeated decompilation. Store full exports on disk
  and summarize only relevant functions in the agent context.
- Preserve logs and script versions with every batch so results can be reproduced after Ghidra
  upgrades.

