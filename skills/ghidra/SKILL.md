---
name: ghidra
description: Reverse-engineer compiled binaries (.exe/.dll/.so/.dylib/.o/.ipa/.apk/firmware) using NSA's Ghidra. Use when the user asks to decompile, disassemble, triage malware, audit a binary for vulnerabilities, diff functions across versions, or run headless batch analysis. Ghidra is a binary RE tool — NOT a web pentest tool. Do not use it on remote websites; use it on binaries the user lawfully possesses.
---

# Ghidra Reverse Engineering

Local install: `~/tools/ghidra_12.0.4_PUBLIC/`

| Mode | Entrypoint | Use |
|---|---|---|
| GUI | `~/tools/ghidra_12.0.4_PUBLIC/ghidraRun` | Manual exploration, decompiler, listing |
| Headless | `~/tools/ghidra_12.0.4_PUBLIC/support/analyzeHeadless` | Agent-driven batch analysis, scripts, CI |
| BSim CLI | `~/tools/ghidra_12.0.4_PUBLIC/support/bsim` | Function-similarity DB across binaries |

## Scope rules (mandatory)

1. Ghidra runs on **binary files you possess locally**. It cannot fetch from a URL.
2. Refuse if the user asks you to RE software they don't have rights to (commercial DRM, bypass of license checks, malware-as-weapon). OK: their own builds, CTF binaries, malware samples for triage, signed installers, firmware they own, open-source projects.
3. Always work on a **copy** of the original binary — Ghidra writes a project DB alongside; never touch the source artifact.

## When the user says "/ghidra <thing>" but `<thing>` isn't a compiled binary

Don't refuse — route to the correct RE workflow and tell the user why. The /ghidra invocation is shorthand for "reverse-engineer this thing"; the user often doesn't know whether it's compiled or not. Common redirects:

| `<thing>` | What it actually is | Correct workflow |
|---|---|---|
| Chrome / Edge / Brave extension (`.crx`, store URL, extension ID) | Zipped JS + JSON | **See "Browser extension RE" below.** No Ghidra needed. |
| Firefox extension (`.xpi`) | Zipped JS + JSON | Same as Chrome — `unzip` → read source. |
| `.jar` / `.war` / Android `.apk` | Java/Kotlin bytecode | Prefer `jadx` / `cfr` / `procyon` for clean Java; Ghidra works but is overkill. APK native libs (`lib/*/lib*.so`) → Ghidra. |
| `.pyc` / `__pycache__` | Python bytecode | `decompyle3` / `uncompyle6`; Ghidra has no Python decompiler. |
| `.wasm` | WebAssembly | `wabt`'s `wasm2wat` → read WAT; or `wasm-decompile`. Ghidra has a WASM loader but the output is rough. |
| Source maps / minified JS | JavaScript text | `terser --beautify` or `prettier`; Ghidra is the wrong tool. |
| `.deb` / `.rpm` / `.dmg` / `.msi` | Installer archive | Unpack first (`dpkg-deb -x`, `rpm2cpio`, `7z x`, `pkgutil --expand`), then Ghidra-the-extracted-binary. |
| `.exe` that's actually a self-extractor | NSIS / Inno / UPX | Detect with `file` and `binwalk`; unpack with `7z x` or `upx -d` first. |
| Live remote website / web app | Not a binary | Use `chrome-devtools` MCP + DevTools; refer to `/debug` skill. |

If `<thing>` doesn't match any category above and isn't recognized by `file`, ask the user one short question to clarify.

## Browser extension RE (Chrome / Edge / Brave / Firefox)

Browser extensions are **always** JavaScript source (sometimes minified, never compiled to machine code). Ghidra has nothing to disassemble. The workflow:

```bash
# Chrome / Edge / Brave (Chromium-based): download .crx from Web Store
EXT_ID="cclelndahbckbenkjhflpdbgdldlbecc"   # from chromewebstore URL
mkdir -p ~/re/$EXT_ID && cd ~/re/$EXT_ID
curl -sL -o ext.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D${EXT_ID}%26uc"

# Strip CRX header → zip (CRX3 has variable-length header at offset 12)
python3 - <<'PY'
import struct
with open('ext.crx','rb') as f:
    assert f.read(4) == b'Cr24'
    version = struct.unpack('<I', f.read(4))[0]
    if version == 3:
        hdr_len = struct.unpack('<I', f.read(4))[0]
        f.read(hdr_len)
    else:  # CRX2
        pk, sk = struct.unpack('<II', f.read(8)); f.read(pk + sk)
    open('ext.zip','wb').write(f.read())
PY
unzip -q ext.zip -d unpacked && ls unpacked/
```

Firefox extensions (`.xpi`) are already zip — `unzip foo.xpi -d unpacked/` directly.

Then:
1. Read `manifest.json` first — tells you entry points (`background.service_worker`, `content_scripts[].js`, `action.default_popup`).
2. Many extensions are **open source** — check `homepage_url` in manifest or grep `github.com` in the source. Reading the upstream repo is faster than reading bundled JS.
3. If minified: `npx prettier --write '**/*.{js,mjs}'` or `terser --beautify` for readability.
4. For obfuscated extensions: `webcrack` (npm) handles common obfuscators; `de4js` for hand-rolled.

When the goal is to **port an extension to a CLI**, read these in order:
- `manifest.json` → permissions tell you what APIs it uses
- entry-point file (background script for MV3, popup for UI-driven)
- imported modules in order of use

A worked example lives at `~/re/cookies-txt-locally/` and produced `~/tools/cookies-txt` (Chrome cookie SQLite + Keychain decryption CLI ported from "Get cookies.txt LOCALLY").

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
  -scriptPath ~/.claude/skills/ghidra/scripts \
  -postScript decompile_all.py /tmp/sample-decomp.c

# 3) Triage many binaries in parallel (xargs)
find samples -type f -name '*.exe' -print0 | \
  xargs -0 -P 4 -I{} "$GHIDRA" "$PROJ_DIR" batch -import {} -overwrite
```

Key flags:
- `-import <file>` — add a binary
- `-process <name|pattern>` — operate on already-imported file
- `-overwrite` — replace if exists
- `-readOnly` — open without saving changes
- `-noanalysis` — skip auto-analysis (faster when running scripts)
- `-deleteProject` — wipe project after run (one-shot triage)
- `-recursive` — recurse into directories on import
- `-loader <name>` — force loader (`PeLoader`, `ElfLoader`, `MachoLoader`, `BinaryLoader` for raw)
- `-cspec <name> -processor <id>` — for raw firmware (e.g. `-processor ARM:LE:32:v8`)
- `-scriptPath <dir>` — extra script search path
- `-preScript / -postScript <name> [args...]` — run before / after analysis
- `-max-cpu <n>` — cap analyzer threads

## Writing Ghidra scripts

Scripts live in `~/.ghidra/.ghidra_*/Extensions/` or any `-scriptPath`. Use Python (Jython 2.7) `.py` or Java `.java`. The current program is exposed as the variable `currentProgram`; the FlatProgramAPI is implicit.

Two ready-to-use scripts ship with this skill in `scripts/`:

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

### Android
- `.apk` → unzip → `classes.dex` (Ghidra's DEX loader handles it)
- Native libs: `lib/<arch>/lib*.so` (ELF; ARM64/ARMv7/x86_64)

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

## Output for the user

When reporting findings to the user from a Ghidra run, include:
- file path + SHA-256
- file type (`file` / `lipo -info` / `otool -h`)
- imports of interest (network, crypto, exec, file I/O)
- suspicious string hits with the function they live in
- decompiled snippet (≤30 lines) for each finding, with the address

## Out of scope (route elsewhere, don't refuse)

- **Browser extensions** → see "Browser extension RE" section above (unpack JS, no Ghidra).
- Live remote websites, APIs, web apps → `chrome-devtools` MCP, `unbrowse`, `nuclei`, `nikto`, `zaproxy`.
- Network captures → `wireshark`, `tshark`.
- Source-code review of available source → ripgrep + `simplify` skill or `/carmack`.
- Anything requiring access to systems the user doesn't own → refuse.
