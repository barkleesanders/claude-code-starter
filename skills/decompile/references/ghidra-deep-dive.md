# Ghidra deep-dive

Reference loaded by `/decompile` when the artifact is a native binary that benefits from Ghidra (PE/.NET, complex ELF/Mach-O, firmware blob, anything needing function-level cross-references).

Local install: `~/tools/ghidra_12.0.4_PUBLIC/`

| Mode | Entrypoint | Use |
|---|---|---|
| GUI | `~/tools/ghidra_12.0.4_PUBLIC/ghidraRun` | Manual exploration, decompiler, listing |
| Headless | `~/tools/ghidra_12.0.4_PUBLIC/support/analyzeHeadless` | Agent-driven batch analysis, scripts, CI |
| BSim CLI | `~/tools/ghidra_12.0.4_PUBLIC/support/bsim` | Function-similarity DB across binaries |

## Pre-flight

```bash
# Java — Ghidra 12.x officially wants JDK 21+ but 17 works headless for most projects
java -version
/usr/libexec/java_home -V 2>&1 | head

# If Ghidra wants a specific JDK:
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home -v 17)
```

## Headless analysis (the agent workhorse)

`analyzeHeadless <project_dir> <project_name> [-import file] [-process pattern] [-postScript ...] [options]`

```bash
GHIDRA=~/tools/ghidra_12.0.4_PUBLIC/support/analyzeHeadless
PROJ_DIR=~/ghidra-projects
PROJ_NAME=triage
mkdir -p "$PROJ_DIR"

# 1) Import + auto-analyze a binary
"$GHIDRA" "$PROJ_DIR" "$PROJ_NAME" \
  -import /path/to/sample.exe \
  -overwrite \
  -analysisTimeoutPerFile 600

# 2) Re-run a script over an already-imported binary (no re-analysis)
"$GHIDRA" "$PROJ_DIR" "$PROJ_NAME" \
  -process "sample.exe" -noanalysis \
  -scriptPath ~/.claude/skills/decompile/scripts \
  -postScript decompile_all.py /tmp/sample-decomp.c

# 3) Triage many binaries in parallel (xargs)
find samples -type f -name '*.exe' -print0 | \
  xargs -0 -P 4 -I{} "$GHIDRA" "$PROJ_DIR" batch -import {} -overwrite
```

### Key flags

| Flag | Meaning |
|---|---|
| `-import <file>` | Add a binary |
| `-process <name\|pattern>` | Operate on already-imported file |
| `-overwrite` | Replace if exists |
| `-readOnly` | Open without saving changes |
| `-noanalysis` | Skip auto-analysis (faster when running scripts) |
| `-deleteProject` | Wipe project after run (one-shot triage) |
| `-recursive` | Recurse into directories on import |
| `-loader <name>` | Force loader (`PeLoader`, `ElfLoader`, `MachoLoader`, `BinaryLoader` for raw) |
| `-cspec <name> -processor <id>` | For raw firmware (e.g. `-processor ARM:LE:32:v8`) |
| `-scriptPath <dir>` | Extra script search path |
| `-preScript / -postScript <name> [args...]` | Run before / after analysis |
| `-max-cpu <n>` | Cap analyzer threads |

## Writing Ghidra scripts

Scripts live in `~/.ghidra/.ghidra_*/Extensions/` or any `-scriptPath`. Use Python (Jython 2.7) `.py` or Java `.java`. The current program is exposed as the variable `currentProgram`; the FlatProgramAPI is implicit.

Two ready-to-use scripts ship with `/decompile` in `scripts/`:
- `decompile_all.py <out.c>` — dump decompiled C for every function
- `dump_strings_imports.py <out.json>` — list strings, imports, exports as JSON

Run with `-postScript decompile_all.py /tmp/out.c`.

## Common workflows

### Decompile-and-grep audit
```bash
"$GHIDRA" "$PROJ_DIR" audit -import bin -overwrite \
  -postScript decompile_all.py /tmp/decomp.c
rg -n 'strcpy|sprintf|gets|memcpy.*user|system\(|popen\(|setuid|exec[lv]' /tmp/decomp.c
```

### Locate hardcoded secrets / URLs / regexes
```bash
"$GHIDRA" "$PROJ_DIR" strings -import bin -overwrite \
  -postScript dump_strings_imports.py /tmp/sa.json
jq -r '.strings[] | select(test("https?://|sk_live_|AKIA|-----BEGIN|password|api[_-]?key";"i"))' /tmp/sa.json
```

### Diff two binary versions (BSim)
```bash
BSIM=~/tools/ghidra_12.0.4_PUBLIC/support/bsim
$BSIM createdatabase ~/bsim-db medium_nosize
# generate signatures for both, then:
$BSIM commitsigs ~/bsim-db /path/to/sigs/v1
$BSIM commitsigs ~/bsim-db /path/to/sigs/v2
# query similar functions via the GUI BSim search or CLI tools
```

### macOS / iOS apps
- `.app` bundles: point at `Contents/MacOS/<binary>` (Mach-O)
- `.ipa`: unzip → `Payload/*.app/<binary>`; signature is a thin or fat Mach-O
- `.dylib` / `.framework` work directly
- For Swift mangled names: turn on the **Swift demangler** analyzer

### Android native libs
- `.apk` → unzip → `lib/<arch>/lib*.so` (ELF; ARM64/ARMv7/x86_64) — these are the Ghidra targets
- Standalone `.dex` → Ghidra's DEX loader handles it (but jadx is usually nicer)

### Firmware / raw blobs
```bash
# Need to know architecture; pass cspec/processor explicitly.
"$GHIDRA" "$PROJ_DIR" fw -import firmware.bin -overwrite \
  -loader BinaryLoader \
  -processor ARM:LE:32:v8 \
  -cspec default \
  -loader-param baseAddr=0x08000000
```

## Gotchas

- **Project locks**: a stale `*.lock` or `*.lock~` in the project dir blocks reopen. Delete if no Ghidra is running.
- **JDK mismatch**: `Failed to load JNI library` → set `JAVA_HOME` to the right major version.
- **Big binaries**: bump `MAXMEM` in `~/tools/ghidra_12.0.4_PUBLIC/support/launch.properties` (e.g. `MAXMEM=8G`).
- **PDB symbols** for Windows binaries dramatically improve decompilation. Drop the `.pdb` next to the `.exe` before import; Ghidra picks it up.
- **`-readOnly` + `-overwrite`** are mutually exclusive — pick one.
- Don't `-import` and `-process` in the same invocation; pick one phase per call.
- Headless writes a lot to stdout — pipe to a file (`>~/ghidra.log 2>&1`) when scripting.

## Output for the user (when reporting Ghidra findings)

- file path + SHA-256
- file type (`file` / `lipo -info` / `otool -h`)
- imports of interest (network, crypto, exec, file I/O)
- suspicious string hits with the function they live in
- decompiled snippet (≤30 lines) for each finding, with the address
