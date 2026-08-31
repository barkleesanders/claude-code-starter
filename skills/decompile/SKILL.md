---
name: decompile
description: Reverse-engineer ANY binary, bundle, distributable, OR the private API of a website you're logged into. Binaries — compiled native (.exe/.dll/.so/.dylib/Mach-O), JVM (.jar/.apk/.dex), .NET (.dll/.exe IL), iOS (.ipa), browser extensions (.crx/.xpi), WebAssembly (.wasm), Python bytecode (.pyc), React Native Hermes (.hbc), JS bundles, firmware blobs, installers (.deb/.rpm/.dmg/.msi). Websites — record a real logged-in session to HAR (incl. the log-out/log-in auth handshake), distill it, and generate a typed TypeScript client + MCP server. Routes to the correct tool per artifact class — Ghidra is just one tool in the kit. Use when the user says decompile, disassemble, reverse-engineer, RE, "look inside this binary/app/extension/firmware", "make an API/MCP server for this website", "capture the network calls this site makes", HAR, triage malware, audit a binary for vulns, diff functions across versions, or port a closed-source thing to a CLI. Does NOT debug or pentest live websites — for debugging route to /debug or /chrome.
---

# /decompile — universal binary reverse-engineering kit

Successor to the old `/ghidra` skill. Ghidra is one tool here, not the default. The skill's job is to **route the artifact to the right tool** — for most modern artifacts (Android apps, browser extensions, JS bundles, .NET, Python bytecode, React Native Hermes), Ghidra is the wrong tool.

**Beyond decompilers, the kit now carries capability + vuln + diff tooling** (installed: `capa`, `floss`, `ghidriff`, `ropper`; install-on-demand: `angr`, `cwe_checker`, `rizin`/Cutter, `retdec`, `BinDiff`, `Ghidrathon`, `qiling`, + dogbolt.org). For an unknown native binary or malware sample, the fast first pass is **`capa` (what it does) + `floss` (hidden strings)** *before* opening a decompiler — see [Common audits](#common-audits-paste-and-run) step 0.

## Scope rules (mandatory)

1. **Always work on a copy.** Many tools write project DBs alongside (Ghidra) or modify in place (apktool patch). Never touch the source artifact directly.
2. **DMCA §1201(f) posture:** working on devices the user owns for interoperability (e.g. talking to their own wearable over BLE without the official app) is the default Whoop/Garmin/Polar use case.
3. **Web / URL / logged-in SPA / `.har` → `fhar` + `fcdp` first when they fit; a logged-in browser CLI when it fits.** Logged-in tab already open, HAR with bodies, logout→login handshake, or click/type/js on a real Chrome tab → `~/tools/fcdp/fcdp` and `~/tools/fcdp-har/fhar` immediately. Then load a logged-in browser CLI (not included in this starter) for published-surface inspect, anonymous fetch, GET-only capture/replay, or when fcdp/fhar is the wrong shape. Do not invent a mandatory a logged-in browser CLI-first gate. Skip all of this when the input is already a local binary or bundle.

---

## STEP 1 — Identify the artifact

Always run these first. The answer determines every subsequent tool choice.

```bash
file <artifact>                                  # magic-number classification
sha256sum <artifact>                             # provenance / change-tracking
ls -la <artifact>                                # size + perms
hexyl --length 256 <artifact>                    # first 256 bytes — most formats self-reveal
strings <artifact> | head -50                    # quick string skim
binwalk <artifact>                               # embedded archives / firmware signatures
binwalk -E <artifact>                            # ENTROPY — sustained ~8.0 == packed/encrypted
```

**Check for packing before importing anything into a decompiler.** A packed or
obfuscated binary decompiles to garbage, and Ghidra will happily produce 40k lines of
it without ever warning you. Sustained ~8.0 entropy, a tiny `.text` next to one huge
high-entropy section, or `capa` firing packer/anti-analysis rules all mean **stop** —
route to [Dynamic native](#dynamic-native-lldb) and unpack at runtime first.

For uncertainty between "compiled binary" and "archive/installer": `binwalk` finds embedded formats; `7z l` lists archive contents non-destructively.

---

## STEP 2 — Route by artifact class

The routing table is the centerpiece of this skill. Match the artifact to a row, then follow the linked workflow. **Do not default to Ghidra.**

| `file` says / extension | Class | Primary tool | Fallback / deeper | Workflow |
|---|---|---|---|---|
| **a live website** (URL, no file) | Web app / private API | `fcdp` + `fhar rec` (logged-in tab, HAR bodies) | a logged-in browser CLI `inspect`/`fetch`/`capture`/`replay` when those fit | [Session capture](#session-capture--typed-client--mcp-server) |
| `.har` | Captured HTTP session | `fhar distill` | `fhar gen` → Bun/TS scaffold; a logged-in browser CLI's `distill` if you already have the CLI up | [Session capture](#session-capture--typed-client--mcp-server) |
| `Mach-O 64-bit executable arm64` / `x86_64` | macOS/iOS native | `otool` + `nm` + `radare2` | Ghidra (Mach-O loader + Swift demangler) | [Native Mach-O](#native-mach-o) |
| `ELF 64-bit LSB executable` / `shared object` | Linux native | `radare2` or Ghidra | `nm`, `objdump -d`, `readelf -a` | [Native ELF](#native-elf) |
| `PE32+ executable for MS Windows` | Windows native | Ghidra (PDB if present) | `radare2`, `dnSpy`/`ilspycmd` if .NET | [Native PE](#native-pe) |
| `Java archive` / `.jar` / `.war` | JVM bytecode | `cfr-decompiler` | `jadx` (Kotlin-friendly) | [JVM](#jvm) |
| Android `.apk` / `.aab` / xapk bundle | Android | `jadx --no-res -d out app.apk` | `apktool d` (resources), `apkeep` (download from store) | [Android](#android) |
| `.dex` standalone | Dalvik bytecode | `jadx` | Ghidra DEX loader | [Android](#android) |
| iOS `.ipa` | Mach-O Fat/Slim inside zip | `ipsw extract`, `ipsw class-dump` | `otool`, `lipo`, radare2, Ghidra | [iOS](#ios) |
| `.framework` / `.dylib` | Mach-O lib | `otool -L`, `radare2` | Ghidra | [Native Mach-O](#native-mach-o) |
| `.crx` / Chrome store URL / extension ID | Zipped JS+JSON | Strip CRX header → `unzip` | `prettier`, `terser`, `webcrack` | [Browser extension](#browser-extension) |
| `.xpi` / Firefox extension | Zip JS+JSON | `unzip foo.xpi` | same JS toolkit | [Browser extension](#browser-extension) |
| `.wasm` | WebAssembly | `wasm2wat foo.wasm > foo.wat` | `wasm-decompile`, Ghidra WASM loader | [WebAssembly](#webassembly) |
| `.pyc` / `__pycache__/*.pyc` | Python bytecode | `decompyle3` | `uncompyle6` for older Pythons | [Python bytecode](#python-bytecode) |
| `.hbc` / React-Native Hermes bundle | Hermes bytecode | `hbc-decompiler` / `hbc-disassembler` | hbctool | [Hermes](#hermes) |
| `.dll`/`.exe` that's actually .NET CIL | MSIL | `ilspycmd` (or Rider GUI) | Ghidra | [.NET](#net) |
| `.deb` | Debian package | `dpkg-deb -x foo.deb out/` | route on `out/usr/bin/*` | [Installer](#installer) |
| `.rpm` | RPM package | `rpm2cpio foo.rpm \| cpio -idmv` | route on extracted | [Installer](#installer) |
| `.dmg` | macOS disk image | `hdiutil attach` or `7z x` | route on `.app/Contents/MacOS/<bin>` | [Installer](#installer) |
| `.pkg` / `.mpkg` | macOS installer | `pkgutil --expand foo.pkg out/` | route on payload | [Installer](#installer) |
| `.msi` | Windows installer | `7z x foo.msi` | route on extracted `.exe` | [Installer](#installer) |
| NSIS / Inno / UPX self-extractor | Packed `.exe` | `7z x`; `upx -d` (⚠️ **upx not installed** — `brew install upx`) | then Ghidra on unpacked | [Installer](#installer) |
| Minified / source-mapped JS | JavaScript text | `prettier --write '**/*.js'` | `terser --beautify`, `webcrack` | [Browser extension](#browser-extension) |
| **packed / obfuscated** native (high entropy, tiny import table, UPX/custom stub) | Packed native | **LLDB unpack-and-dump** | `upx -d` if plain UPX; `capa` to confirm packer | [Dynamic native](#dynamic-native-lldb) |
| **running / hung process** (no file — a live PID) | Live process | `lldb -p <pid>` → `bt all` | macOS `sample <pid>` (no attach, beats SIP) | [Dynamic native](#dynamic-native-lldb) |
| `.ips` / `.crash` / core dump | Crash report | `lldb -c <core> <binary>` → `bt all` | read `.ips` JSON directly | [Dynamic native](#dynamic-native-lldb) |
| Firmware blob / `.bin` / `.fw` | Raw binary | `binwalk -Me` | Ghidra with `-loader BinaryLoader -processor ARM:LE:32:v8` | [Firmware](#firmware) |
| `.app` bundle | macOS app | route on `Contents/MacOS/<binary>` | — | [Native Mach-O](#native-mach-o) |
| Unknown / `data` | depends | `binwalk` to find embedded formats | hex inspection, entropy analysis | — |

**When in doubt:** run `file` and `binwalk`, paste both outputs, route from there. If still unrecognized, ask one short question.

---

## Tool inventory (verified installs)

| Tool | Path | Purpose |
|---|---|---|
| `ghidra` | `~/tools/ghidra_12.0.4_PUBLIC/ghidraRun` (GUI) + `support/analyzeHeadless` | Decompile native binaries; Java + Python scriptable |
| `radare2` / `r2` | `/opt/homebrew/bin/radare2` | Open-source Ghidra alternative; shell-scriptable |
| `jadx` | `/opt/homebrew/bin/jadx` | Java/Kotlin/DEX → readable Java |
| `apktool` | `/opt/homebrew/bin/apktool` | APK resource decode + smali, repack |
| `apkeep` | `~/.cargo/bin/apkeep` | Pull APKs from APKPure / Google Play / F-Droid / Huawei |
| `cfr-decompiler` | `/opt/homebrew/bin/cfr-decompiler` | Java decompiler — catches things jadx misses |
| `ipsw` | `/opt/homebrew/bin/ipsw` | iOS firmware, IPA class-dump, dyld_shared_cache extract |
| `lldb` | `/usr/bin/lldb` (Xcode CLT, `lldb-2100.0.17.203`) | **Dynamic native debugging** — breakpoints, watchpoints, memory dump, attach-to-PID, core dumps, `gdb-remote` to QEMU. The runtime counterpart to Ghidra's static view. ⚠️ Pass `--no-lldbinit` in scripts (`~/.lldbinit` here registers phantom breakpoints) and scope name-breakpoints with `--shlib` (a bare `--name` collides with system libs). Hardened-runtime apps refuse attach — see [lldb-dynamic.md](references/lldb-dynamic.md). |
| `rabin2` | `/opt/homebrew/bin/rabin2` (radare2 suite) | Header/arch/symbols/security-flags — the **`readelf` replacement**, since no `readelf` exists on macOS. |
| `frida` | `~/.local/bin/frida` | Dynamic instrumentation (hook funcs at runtime). Often works where `lldb -p` is blocked by the hardened runtime. |
| `objection` | `~/.local/bin/objection` | Frida-based mobile pentest, SSL pinning bypass |
| `mitmproxy` | `~/.local/bin/mitmproxy` | TLS-intercepting proxy; reveal API calls from any app |
| `hbc-decompiler` / `hbc-disassembler` | `~/.local/bin/` (pipx pkg `hermes-dec`) | React Native Hermes bytecode → JS. Binaries are `hbc-*`, not `hermes-dec <verb>`. |
| `hbctool` | `~/.local/bin/hbctool` | Hermes `disasm`/`asm` round-trip (patch + repack .hbc) |
| `decompyle3` | `~/.local/bin/decompyle3` | Python 3.7–3.9 bytecode → source |
| `uncompyle6` | `~/.local/bin/uncompyle6` | Python 2.7 / 3.0–3.8 bytecode → source (older-Python fallback to decompyle3) |
| `androguard` | `~/.local/bin/androguard` (pipx) | APK static analysis CLI + Python API (manifest, perms, certs) |
| `capa` | `~/.local/bin/capa` (pipx `flare-capa` 9.4.0) | FLARE capability detector — tells you WHAT a binary *does* (C2, persistence, anti-debug, crypto, injection) via rule-matching over disasm. PE/ELF/Mach-O/.NET/sc. First pass on any unknown native binary or malware sample. ⚠️ PyPI `capa` is a squatted stub — the real package is `flare-capa`. |
| `floss` | `~/.local/bin/floss` (pipx `flare-floss` 3.1.1) | FLARE Obfuscated String Solver — extracts *stack / tight / decoded / encoded* strings that plain `strings` misses (emulates the binary to recover runtime-built strings). Run alongside `strings` on any malware / packed native binary. |
| `ghidriff` | `~/.local/bin/ghidriff` (pipx 1.0.0) | Headless **Ghidra binary-diffing** engine → Markdown diff of which functions changed between two versions. CLI wrapper over Ghidra's decompiler; better signal than raw `bsdiff` for "what changed in this update". |
| `ropper` | `~/.local/bin/ropper` (pipx 1.13.13, **Python 3.12 venv**) | ROP/JOP gadget finder + binary info (arch, NX/PIE/canary, sections). Exploit-dev and hardening audit. ⚠️ installed under `--python python3.12` because its `filebytes` dep uses the removed `ast.Str` and won't build on the 3.14 pipx host. |
| `ilspycmd` | `~/.dotnet/tools/ilspycmd` | .NET/MSIL decompiler. Needs `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec` (set in `~/.zshrc`) |
| `webcrack` | `/opt/homebrew/bin/webcrack` (npm global) | JS deobfuscator/unminifier. Installed `--ignore-scripts` (no `isolated-vm`); core deobf works, VM-sandbox bundle-unpack unavailable |
| `binwalk` | `/opt/homebrew/bin/binwalk` | Extract embedded archives + filesystems in firmware |
| `tshark` / `dumpcap` / `capinfos` / `editcap` | `/opt/homebrew/bin/` (Wireshark 4.6.7, CLI-only formula) | Read/dissect pcap + **btsnoop BLE** captures (3160 protocol dissectors incl. `btatt`/`btle`/`bthci_acl`); `-T fields` = scriptable output. The analysis half of BLE/non-HTTP RE that `mitmproxy` (HTTP-only) can't cover. GUI is the separate `wireshark-app` cask (not installed); live-interface capture needs `--cask wireshark-chmodbpf` (not needed to read existing files). |
| `yara` | `/opt/homebrew/bin/yara` | Pattern-match across binaries (malware sigs, crypto, regex) |
| `wasm2wat` | `/opt/homebrew/bin/wasm2wat` (wabt suite) | WebAssembly → readable WAT text |
| `bsdiff` | `/opt/homebrew/bin/bsdiff` | Binary patch generator (firmware version diffing) |
| `vbindiff` | `/opt/homebrew/bin/vbindiff` | Visual side-by-side hex diff |
| `hexyl` | `/opt/homebrew/bin/hexyl` | Colorful hex viewer |
| `prettier` | `/opt/homebrew/bin/prettier` | JS/TS beautifier for minified bundles |
| `terser` | `/opt/homebrew/bin/terser` | JS minifier — `--beautify` to unminify |
| `babel` | `/opt/homebrew/bin/babel` | JS transformer; helpful for AST-level deobf |
| `7z` | `/opt/homebrew/bin/7z` | Universal extractor (NSIS, MSI, ISO, DMG, …) |
| `otool` / `nm` / `lipo` | `/usr/bin/` | Mach-O native tools (Xcode CLT) |
| `fcdp` | `~/tools/fcdp/fcdp` | Default for a live logged-in tab: open / js / intercept / network. See [Acquisition](#acquisition-get-the-artifact-first). |
| `fhar` | `~/tools/fcdp-har/fhar` | Default for HAR bodies + logout→login + `distill` / `gen`. See [Session capture](#session-capture--typed-client--mcp-server). |
| a logged-in browser CLI | _(not included)_ | Call when inspect / anonymous fetch / GET-only capture+replay is the job. Commands live in that skill. Fallback: _(not included)_. |
| `mimic` | `~/.local/bin/mimic` (uv tool `mimic-client`, from `git+https://github.com/littledivy/mimic`) | Capture an iOS app's traffic → **AI-generate a Python client** for its private API. Automates the manual "capture → extract → build a CLI" flow: `mimic record` (proxy + iPhone setup) → `mimic hosts` → `mimic learn <host>` → `mimic gen <host>`; `mimic unpin <ipa\|id>` defeats cert-pinning via Frida; `mimic doctor` checks setup. Deps already present (mitmproxy, `claude` CLI, frida, objection). See [App-API client generation](#app-api-client-generation-mimic). |

**Tool notes / gotchas:**
- `ilspycmd` (.NET) — installed, but the Homebrew `dotnet` puts its runtime in a Cellar path the tool's apphost can't find, so it needs `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec`. This is exported in `~/.zshrc` (line ~434), so it Just Works in a login shell. If you ever see "You must install .NET to run this application," that env var is missing.
- `webcrack` — installed globally with `--ignore-scripts`, which skips the `isolated-vm` native build (it fails to compile under Node 26 — no prebuilt binary yet). Core deobfuscation (unminify, string-array decode, control-flow unflatten, prettify) all work. The ONLY thing missing is the VM-sandbox unpacker for some webpack bundles; if you hit a bundle that needs it, fall back to the `de4js` web UI.
- `uncompyle6` / `decompyle3` / `hbctool` — all run on a Python 3.14 pipx host, which is newer than these tools officially target. They launch and work for the common case; if one chokes on a specific bytecode version, that's the host-version mismatch, not a missing install.

**Heavier / deeper tools (NOT installed — verified install commands, pull on demand).** These are the "make it more capable" tier — reach for them when the four installed decompilers + capa/floss aren't enough. Install commands verified against Homebrew / PyPI / the upstream repo on 2026-08-01.

| Tool | Install (verified) | When it's the right tool |
|---|---|---|
| **angr** | `pipx install angr` (PyPI 9.2.213; pulls capstone/unicorn/z3 — ~2–3 min build) | Symbolic execution + automated path exploration on a native binary: solve for the input that reaches a branch, recover a CFG, auto-find buffer-overflow/auth-bypass paths. The heavy-artillery complement to Ghidra's static view. `angr/angr` ⭐9k. |
| **cwe_checker** | `container pull ghcr.io/fkie-cad/cwe_checker:stable` then `container run --rm -v "$PWD":/in ghcr.io/fkie-cad/cwe_checker:stable /in/binary` (docker→`container` per global rule; uses a Ghidra backend inside the image) | **Automated vuln pattern detection** — flags CWE-119/-134/-190/-416/-787 etc. (buffer overflow, format string, use-after-free, integer overflow) across any arch Ghidra can disassemble. Turns "read all the decompiled C by hand" into a triaged findings list. `fkie-cad/cwe_checker` ⭐1.3k. |
| **rizin + Cutter** | `brew install rizin` (0.9.1) + `brew install --cask cutter` (2.5.0, GUI w/ bundled Ghidra decompiler via rz-ghidra) | Maintained radare2 fork + a real GUI that shows Ghidra-decompiler output side-by-side with disasm and a graph view. Use when r2's CLI is too raw and you want to *see* the CFG. |
| **retdec** | `brew install retdec` (5.0) | Avast's retargetable decompiler — a **second decompiler opinion** to cross-check Ghidra on a gnarly function. `retdec-decompiler binary -o out.c`. |
| **BinDiff** | `brew install --cask bindiff` (8, Google/Zynamics, free) + BinExport plugin for Ghidra | GUI **binary diffing** with function matching + similarity scoring — the gold standard for "which functions changed between firmware v1 and v2" and porting symbols across versions. Pairs with `ghidriff` (CLI) for headless diffs. |
| **Ghidrathon** | download release zip (`>=4.0.0`) from `mandiant/Ghidrathon/releases` → Ghidra *File▸Install Extensions* (our Ghidra 12.0.4 ✓ meets the `>=10.3.2` req) | Replaces Ghidra's Python-2/Jython with **Python 3** scripting — required to drive capa/angr/unicorn *inside* Ghidra's headless analyzer. `mandiant/Ghidrathon` ⭐0.8k. |
| **qiling** | `pipx install qiling` (1.4.6) | Cross-arch **emulation sandbox** (built on Unicorn) — actually *run* a firmware blob or a single function to observe behavior/syscalls when static reading stalls. Great for firmware where you have the code but not the device. |
| **BAM** (NSA) | `git clone https://github.com/nsacyber/BAM` — PowerShell + .NET, **Windows-only** | NSA-nsacyber's Binary Analysis Metadata tool: gathers imports/exports/compiler/hardening metadata on *Windows* binaries to prioritize what to reverse. Note: won't run natively on macOS (documented for completeness — it's the "other NSA tool" beyond Ghidra). |

**Zero-install cross-check:** **[dogbolt.org](https://dogbolt.org)** (Decompiler Explorer) — upload one binary, get Ghidra + angr + RetDec + Binary Ninja + Hex-Rays + reko + Boomerang decompiling it side-by-side in the browser. Fastest way to get a *second decompiler's* take on a confusing function without installing anything. (Godbolt-for-decompilers.)

**Genuinely blocked on macOS (don't retry the obvious install):**
- `class-dump` — no working install path on modern Xcode: the Homebrew formula was removed and the upstream `nygard/class-dump` source no longer builds against current SDKs. **Use `ipsw class-dump <ipa>` instead** — it's installed and produces the same ObjC header output. Only build from source (`git clone https://github.com/nygard/class-dump && cd class-dump && xcodebuild`) if you specifically need nygard's output format and are willing to patch the build.
- `dnSpy` (.NET GUI) — Windows-only; not portable to macOS. Use the installed `ilspycmd` for CLI decompilation, or open the `.dll` in JetBrains Rider for a GUI.

---

## Pre-flight (do once per machine)

```bash
# Java for Ghidra + cfr-decompiler. Ghidra 12.0.4 needs Java 21+; verified working on Java 26.
# NOTE: macOS `java_home -v 21` means "21 OR HIGHER", so it resolves to the newest JDK ≥21
# (here Java 26) — that's fine, Ghidra 12 runs clean on it (only a harmless sun.misc.Unsafe warning).
java -version
/usr/libexec/java_home -V 2>&1 | head
export JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home -v 17)

# Ghidra MAXMEM for big binaries
grep MAXMEM ~/tools/ghidra_12.0.4_PUBLIC/support/launch.properties
# Bump to 8G+ for anything over ~100MB

# adb (Android dynamic work) / Xcode CLT (iOS)
adb --version
xcode-select -p
```

---

## Workflows

### Acquisition (get the artifact first)

Most artifacts are already local files — route them directly. Two cases need your
**logged-in Chrome** — use `~/tools/fcdp/fcdp` (`fcdp --help`). Reach for a logged-in browser CLI after that if you need inspect / fetch / GET-only replay.

**Already-installed browser extension → read it from disk, no download.**
Installed Chrome extensions are already unpacked JS+JSON — route straight as a
[Browser extension](#browser-extension):
```bash
ls "$HOME/Library/Application Support/Google/Chrome/Default/Extensions"   # installed ids
# → route ~/Library/.../Extensions/<id>/<version>/  (manifest.json + bundles, already unpacked)
```
Match the id by name in each `manifest.json`, or read it off `chrome://extensions`
(Developer mode on).

**Artifact behind a login (store / vendor portal / private build) → capture the real URL.**
```bash
FCDP=~/tools/fcdp/fcdp
$FCDP open "<page-with-the-download>"          # drives your REAL, already-logged-in Chrome
$FCDP intercept | rg -iE '\.(crx|apk|aab|ipa|wasm|jar|zip|dmg|pkg|exe|bin|fw)(\?|$)|download'
curl -L -o artifact "<captured-url>"           # session cookies make auth'd downloads work
```
If the download lives under a different Chrome profile, switch to that
Chrome profile/window first, then re-run `$FCDP tabs` to confirm you're pointed at it.

**Auth'd download with a plain `curl`/`yt-dlp` (no browser drive needed) → export your real Chrome cookies, LOCAL-only.**
```bash
~/tools/cookies-txt <domain> -o <domain>.cookies.txt   # chmod 600; prints path+count, NEVER values
curl -b <domain>.cookies.txt -L -o artifact "<url>"    # session cookies authenticate the fetch
yt-dlp --cookies <domain>.cookies.txt "<url>"          # same file works for yt-dlp
```
`~/tools/cookies-txt` reads the real Chrome profile's cookie DB + decrypts via macOS Keychain. Cookies never leave this machine.

### Live web-app / API endpoint discovery (find the endpoint that "does the thing")

When the goal is *"what API call does this logged-in web app make to do X"* (so you can drive it from a CLI), do NOT Ghidra anything and do NOT start by scraping minified JS. Climb this ladder — stop at the first rung that answers it:

1. **Open-source backend routes (authoritative — read it first).** If the backend is open source (e.g. VA = `department-of-veterans-affairs/vets-api`), the route table IS the endpoint map — better than any frontend scrape. Read `config/routes.rb`. **Critically, grep for `mount <X>::Engine, at: '/path'`** and read each engine's own `routes.rb` — mounted engines hide entire route families a top-level grep misses. (2026-06-21: the VA 20-10206 submit endpoint `POST /simple_forms_api/v1/simple_forms` lived in a mounted `SimpleFormsApi::Engine`; a `/v0`-only grep "proved" no submit API existed — wrongly. The engine route was the answer.) Then read the controller + any `spec/fixtures/*.json` for the exact request-body shape.
   ```bash
   gh api repos/<org>/<repo>/contents/config/routes.rb --jq '.content' | base64 -d | grep -nE 'mount .*Engine|<keyword>'
   gh api repos/<org>/<repo>/contents/modules/<engine>/config/routes.rb --jq '.content' | base64 -d
   ```
2. **Deployed frontend bundle (when backend isn't open source).** The SPA's JS references its own API paths. Capture the bundle URL via CDP, `prettier`/`webcrack` it, then `rg -oiE '"/api/[^"]+"|fetch\(|axios\.(get|post)'` for endpoint strings + method.
3. **Live capture (ground-truth confirmation — always do this before building a mutation).** A route listed in `routes.rb` or scraped from a bundle is *capability*; a captured call is *proof of the real contract* (which params the server actually requires, header shape, CSRF, auth carriage).
   - **`fcdp` then `fhar rec` — first** when a logged-in tab, HAR bodies, or logout→login is what you need. See [Session capture](#session-capture--typed-client--mcp-server).
   - **`fcdp intercept` — a quick look only.** `{method, url}` and nothing else. Never write a client from it. `--secs N` is mandatory: a bare number is a **tabId**.
   - **a logged-in browser CLI next** when inspect / anonymous fetch / GET-only capture+replay is the better tool. Load the skill and use a logged-in browser CLI's `doctor` then `inspect`/`fetch`/`capture`/`replay`.
4. **Reuse with the user's own session.** Read-only endpoints → replay with the session cookie/token (see the cookies/`vatp` patterns). **Mutations (submit/file/pay/delete) are outward, irreversible actions → dry-run, show the exact body, get explicit per-action approval.** Never auto-fire a state-changing endpoint, and never populate a legal e-signature field (`statement_of_truth_signature` etc.) on the user's behalf.

Worked example: `~/tools/example-api-cli/excli` (VA benefits read commands + the 20-10206 submit contract) was built entirely from rungs 1+3 against `vets-api` — zero binary RE.

**Salesforce Experience Cloud (MyLA311 and siblings).** Transport is `POST /s/sfsites/aura` + `aura://ApexActionController/ACTION$execute`. Decompile the LWC (`auraCmpDef` → `c/laCaseCreationFlow.submitRequest`), do not guess Apex param names — unknown names arrive as null and NPE. Official Android/iOS MyCommunity EXPERIENCE shells (`facade.textproto` `servers.url` = the site) have **no native submit API** — decompile the site LWC, not jadx smali. A successful insert is not a complete filing: MyLA311's GIS bind is `addressDetails` from `LA_AddressController.validateAddress`, not the form wrapper's `caseLocation`. Lat/lng-only cases (C-04342632) stay Status=New with `caseAddress: ", , CA."`. Lookup is `X11_ViewServiceRequestsController.getSearchRequests`; Socrata 2026 is `2cy6-i7zn` with the **unprefixed** casenumber. Cookie-jar replay without the live Aura CSRF is `invalid_csrf` — `fhar rec` the real tab. Catalog/submit design rules (listed ≠ fileable, empty SUCCESS = `captureFailure`, unwrap toast/`objCaseConfigWrapper`, remint IDs, named refuse) live in Pattern 36 in `/debug`.

### Session capture → typed client + MCP server

**The web analog of `mimic`.** Start with `fcdp` + `fhar rec` on the real logged-in Chrome (logout→login handshake, HAR bodies, `fhar gen`). If that is the wrong shape — published files, anonymous fetch, GET-only replay — load a logged-in browser CLI and use `inspect` / `fetch` / `capture` / `replay` / `distill`.

```bash
FHAR=~/tools/fcdp-har/fhar
~/tools/fcdp/fcdp open "https://app.example.com"   # your real, already-logged-in Chrome

$FHAR rec --secs 300          # then, BY HAND in Chrome:
                              #   1. log OUT        <- captures the session teardown
                              #   2. log back IN    <- captures the auth handshake (the whole point)
                              #   3. visit every page whose data you want
                              # Ctrl-C when done; capture survives navigation.

$FHAR distill session.har --md    # -> one representative call per endpoint, secrets redacted
$FHAR distill session.har --md --host api.example.com   # scope to ONE host (see below)
$FHAR gen     session.har         # -> ~/re/<name>-api/ : digest + HAR + PROMPT.md + Bun/TS scaffold
```

Then point Claude at the scaffold's `PROMPT.md` and have it write `src/client.ts`,
`src/types.ts`, and `src/mcp.ts` from `api-digest.md`.

**Read the digest's `## Replay hints` block before writing a single line of client
code.** It carries the two things that decide whether your client gets data or a 403,
and neither is visible in the per-endpoint listing:

- **User-Agent** — the browser's own UA string. `requests`/`httpx`/`curl` send their
  own default UA, and a lot of sites 403 it outright. Send the captured one.
- **How auth actually rode** — `Cookie` header vs `Authorization`/API-key header.
  That decides the whole auth strategy: carry a cookie jar forward
  (`~/tools/cookies-txt <host>` pulls it from your real Chrome) versus extract and
  resend one header. Secret *values* stay redacted; the key *names* survive, so you
  know exactly which header to set.

**`--host SUBSTR` when the capture is multi-host.** A real session pulls in analytics,
CDNs, auth providers, and feature-flag services alongside the API you actually want.
Scoping to the API host cuts the digest to the endpoints you'll implement. The digest
records the filter and flags in the Markdown that other hosts were excluded, so a
scoped digest can't be mistaken for a complete one.

**Why not just hand over the raw HAR:** a real session HAR is megabytes of
base64'd bodies and hundreds of duplicate requests — it blows the context window
and buries the signal. `distill` collapses `/projects/11` and `/projects/12` into
one `GET /projects/{id}` entry with an inferred body schema, drops static assets,
and strips noise headers. Read `api-digest.md`; `grep` the HAR only when the digest
is ambiguous about a specific request.

> 🔐 **A HAR of a login contains the real password and live session cookies.**
> `fhar` chmod 600s every capture and redacts secret *values* from the digest while
> keeping the field *names* (so you still know an `Authorization` header is required).
> Never commit, paste, share, or upload a raw `.har` — the generated `.gitignore`
> excludes them. `--keep-secrets` exists for local debugging only.

**Why `fhar` and not `fcdp intercept`:** `intercept` records `{method, url}` and
nothing else. You cannot write a client from a URL list — you need headers, request
bodies, response shapes, and status codes, which is what `fhar` records.

Full playbook (multi-host sessions, SPA quirks, GraphQL, WebSocket, evicted bodies,
what to do when the digest is thin): [`references/har-capture.md`](references/har-capture.md).

### App-API client generation (mimic)

When the goal is *"talk to a mobile app's private API from a CLI"* and the backend is **not** open source (so the endpoint-discovery ladder above can't just read `routes.rb`), `mimic` automates the whole capture→client loop. It runs the mitmproxy capture, lets you pick the API host, shows the endpoints it saw, and has `claude` write a typed Python client for that host. This is the tool version of the manual iOS/Android mitmproxy workflows below.

```bash
mimic doctor                 # verify setup (proxy, claude CLI, frida/objection); prints your LAN proxy IP
mimic record                 # starts the proxy + prints iPhone Wi-Fi-proxy + CA-trust setup steps
#   → on the iPhone: set HTTP proxy to <LAN-IP>:8080, install+trust the mitm CA, exercise the app
mimic hosts                  # list captured hosts — pick the API host (not analytics/CDN)
mimic learn api.example.com  # show the endpoints (method + path + params) mimic saw for that host
mimic gen  api.example.com   # claude AI-writes a Python client for that host's API
mimic unpin <app.ipa|bundle-id>   # cert-pinning apps: Frida-defeat pinning so capture works first
```

**Notes:** `mimic gen` sends captured endpoint shapes to Claude to synthesize the client. **Cert-pinning / DPoP-bound tokens** block plain capture — `mimic unpin` handles pinning; DPoP-bound apps still won't replay. If `mimic doctor` shows `[MISSING] mitmweb running`, that's expected until you start `mimic record` in another terminal.

### Native Mach-O

```bash
file binary; otool -h binary; otool -L binary; lipo -info binary
nm -gU binary | head -40
strings binary | rg -iE 'https?://|key|secret|sk_|api[_-]?key' | head -30
capa binary                                          # capabilities first — orients you before you read disasm
floss binary | rg -iE 'https?://|key|token'          # strings `strings` misses (obfuscated/stack-built)

r2 -A binary
[0x100003a40]> afl                                   # list functions
[0x100003a40]> pdf @ sym._main                       # disassemble main

# Or Ghidra headless decompile-all
GHIDRA=~/tools/ghidra_12.0.4_PUBLIC/support/analyzeHeadless
"$GHIDRA" ~/ghidra-projects audit -import binary -overwrite \
  -scriptPath ~/.claude/skills/decompile/scripts \
  -postScript decompile_all.py /tmp/decomp.c
```

Swift binaries: enable **Swift demangler** in Ghidra, or `xcrun swift-demangle <symbol>` on CLI.

**If the decompiled output looks like garbage, or you need to confirm what a function
actually receives at runtime → [Dynamic native (LLDB)](#dynamic-native-lldb).**

### Native ELF

```bash
file binary
rabin2 -I binary                                     # header/arch/security — readelf -h equivalent
rabin2 -s binary | head -40                          # symbols
objdump -d binary | less
r2 -A binary
```

> ⚠️ **`readelf` is NOT installed on macOS** (no `readelf`, `greadelf`, or
> `llvm-readelf` on this machine — verified 2026-08-20). Use `rabin2` from the
> radare2 suite, which is installed and covers the same ground cross-platform.

Ghidra uses ElfLoader automatically. If the decompiled output is nonsense, check
entropy — see [Dynamic native](#dynamic-native-lldb).

### Native PE

```bash
file binary.exe
# CRITICAL: drop binary.pdb next to binary.exe before Ghidra import — symbol quality jumps 10x
"$GHIDRA" ~/ghidra-projects pe -import binary.exe -overwrite
# If `file` says "Mono/.Net assembly" — route to .NET workflow instead
```

### JVM

```bash
cfr-decompiler foo.jar --outputdir out/             # cleaner Java
# Or
jadx -d out/ foo.jar                                # Kotlin-friendly
# `.war` is the same — zip of class files
```

### Android

Most common path. **Full runtime-capture playbook (verified working on this machine, with the exact emulator/mitmproxy/CA commands + gotchas): [`references/android-re.md`](references/android-re.md) — READ IT when the task is "prove what the app sends" or "does endpoint X return data".**

⛔ **MANDATORY DYNAMIC-CAPTURE GATE.** If the goal is to prove a request/endpoint (not just enumerate it), you MUST capture the **real app issuing it** (emulator + mitmproxy), not just reconstruct it with `curl`. A decompiled endpoint is *capability*; the captured request+response is *proof*. Reporting "endpoint dead / returns Y" from `curl` alone — without having captured the live app — is a known overclaim trap (2026-08-01: an inmate endpoint was wrongly called "dead" because the `curl` used the app's global `app_id` instead of the **feature-level** appID the app actually passes; only reading the arg-construction + a live capture reveals that). Stop before the capture ONLY if (a) you captured it, or (b) a hard external blocker you name explicitly (can't obtain an APK of the provisioning app; cert-pinning+DPoP that objection/mimic can't defeat). See android-re.md §"MANDATORY-STEP RULE".

Quick version:

```bash
# 1) Get the APK
apkeep -a com.example.app -d apk-pure ~/re/example/
#   Google Play directly:
#   apkeep -a com.example.app -d google-play -e <gmail> -t <aas-token>

# 2) Unpack xapk (split APK bundle) if needed
cd ~/re/example/
unzip com.example.app.xapk -d unpacked/
ls unpacked/                                         # base.apk + config.*.apk + manifest.json

# 3) Decompile Java/Kotlin (40k+ files typical)
jadx --no-res -d ~/re/example/jadx-out unpacked/com.example.app.apk

# 4) Resources (XML, strings, AndroidManifest)
apktool d unpacked/com.example.app.apk -o ~/re/example/apktool-out/

# 5) Native libs (Ghidra here)
unzip unpacked/config.arm64_v8a.apk -d ~/re/example/native/
# → Ghidra on lib/arm64-v8a/lib*.so

# 6) DYNAMIC CAPTURE (mandatory to PROVE a request — see references/android-re.md for the full rig)
#    Rooted google_apis AVD + mitmproxy CA in the SYSTEM store + emulator -http-proxy flag,
#    then drive the UI to the feature and read flows.mitm with the mitmproxy venv python.
export ANDROID_HOME="$HOME/Library/Android/sdk"; ADB="$ANDROID_HOME/platform-tools/adb"
"$ANDROID_HOME/emulator/emulator" -avd sf311_root -writable-system -http-proxy 127.0.0.1:8080 &
HASH=$(openssl x509 -subject_hash_old -in ~/.mitmproxy/mitmproxy-ca-cert.pem -noout)
$ADB root && $ADB remount && $ADB push ~/.mitmproxy/mitmproxy-ca-cert.pem /system/etc/security/cacerts/$HASH.0
~/.local/bin/mitmdump -w ~/re/cap/flows.mitm -p 8080 &
$ADB install-multiple -r ~/re/app/*.apk          # ⚠️ need arm64-v8a or universal split, NOT armeabi_v7a
frida -U -n com.example.app -l hook.js           # (optional) hook funcs at runtime
objection -g com.example.app explore -c 'android sslpinning disable'   # if TLS-pinned
```

### iOS

```bash
unzip foo.ipa -d ipa-extracted/
ls ipa-extracted/Payload/*.app/                      # executable is here

# class-dump replacement using ipsw
ipsw class-dump ipa-extracted/Payload/Foo.app/Foo > classes.h

# Fat binary? slim first
lipo -info ipa-extracted/Payload/Foo.app/Foo
lipo ipa-extracted/Payload/Foo.app/Foo -thin arm64 -output Foo.arm64
# → otool / nm / r2 / Ghidra on Foo.arm64

# Strings reveal endpoints + keys
strings ipa-extracted/Payload/Foo.app/Foo | rg -iE 'https?://|api\.|sk_|AIza'
```

### Browser extension

Browser extensions are **always** JavaScript source. Ghidra has nothing to disassemble.

> **Already installed in your Chrome?** Skip the download — read it unpacked from disk ([Acquisition](#acquisition-get-the-artifact-first)). **Behind a login / enterprise / unlisted?** Use `fcdp` (`~/tools/fcdp/fcdp`) to drive your REAL logged-in Chrome and capture the `.crx` URL, then continue below.

```bash
# Chrome / Edge / Brave: download .crx by extension ID
EXT_ID="cclelndahbckbenkjhflpdbgdldlbecc"
mkdir -p ~/re/$EXT_ID && cd ~/re/$EXT_ID
curl -sL -o ext.crx \
  "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D${EXT_ID}%26uc"

# Strip CRX header → zip
python3 - <<'PY'
import struct
with open('ext.crx','rb') as f:
    assert f.read(4) == b'Cr24'
    version = struct.unpack('<I', f.read(4))[0]
    if version == 3:
        hdr_len = struct.unpack('<I', f.read(4))[0]; f.read(hdr_len)
    else:
        pk, sk = struct.unpack('<II', f.read(8)); f.read(pk+sk)
    open('ext.zip','wb').write(f.read())
PY
unzip -q ext.zip -d unpacked && cat unpacked/manifest.json | jq .

# Firefox .xpi is already zip:
unzip foo.xpi -d unpacked/

# Beautify
cd unpacked && prettier --write '**/*.{js,mjs}'

# Obfuscated bundles → webcrack (installed globally)
webcrack ~/re/$EXT_ID/unpacked/bg.js -o decoded/
# (webpack bundle that needs the isolated-vm sandbox unpacker? that build is skipped — use the de4js web UI)
```

**Reading order**: `manifest.json` (permissions reveal API surface) → entry-point file (background worker for MV3, content_scripts[].js, popup) → imported modules.

Many extensions are **open-source**. Check `homepage_url` in manifest; reading upstream GitHub is faster than the bundle.

Worked example: `~/re/cookies-txt-locally/` → ported into `~/tools/cookies-txt` (Chrome cookie SQLite + Keychain decryption CLI).

### WebAssembly

```bash
wasm2wat foo.wasm > foo.wat                          # readable text format
wasm-decompile foo.wasm > foo.dc                     # higher-level pseudo-C
wasm-objdump -x foo.wasm | less                      # sections, imports, exports
```

Ghidra has a WASM loader but the output is rough — prefer wabt unless you need cross-references.

### Python bytecode

```bash
decompyle3 foo.pyc                                   # 3.7–3.9
# Python 3.10+: no reliable open-source decompiler. Read disassembly instead.
# SAFE: marshal.load() returns a code object; dis.dis() walks bytecode statically.
# Neither executes the code. DO NOT exec() / eval() / FunctionType() the loaded object.
python3 -c "import dis,marshal; print(dis.dis(marshal.load(open('foo.pyc','rb').read()[16:])))"
```

### Hermes

```bash
# React Native apps bundle JS as Hermes bytecode (.hbc)
# In an APK: assets/index.android.bundle is usually the Hermes file
# NOTE: the hermes-dec pipx package installs binaries named hbc-* (NOT `hermes-dec <verb>`).
hbc-disassembler index.android.bundle > disasm.txt
hbc-decompiler   index.android.bundle > decompiled.js       # imperfect but readable
hbc-file-parser  index.android.bundle                        # header/section inspection
```

### .NET

```bash
# ilspycmd is installed (~/.dotnet/tools). ~/.zshrc exports DOTNET_ROOT so it works in a
# login shell; if invoking from a bare env, prefix: DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec
ilspycmd -o out/ foo.dll                             # full decompilation
ilspycmd --list foo.dll                              # list types only
# Or open in JetBrains Rider / Visual Studio for GUI exploration
```

### Installer

```bash
# Strategy: unpack first, then route on the executable inside.
file foo.<ext>
# ⚠️ `dpkg-deb` and `rpm2cpio` are NOT installed on macOS (verified 2026-08-20).
#    `7z` handles deb, rpm, cpio and ar natively — use it for both.
case "$ext" in
  deb)  7z x foo.deb -oout/ && 7z x out/data.tar* -oout/ ;;   # 7z, not dpkg-deb
  rpm)  7z x foo.rpm -oout/ && 7z x out/*.cpio -oout/ ;;      # 7z, not rpm2cpio
  dmg)  hdiutil attach foo.dmg ;;                    # or: 7z x foo.dmg
  pkg)  pkgutil --expand foo.pkg out/ ;;
  msi)  7z x foo.msi -oout/ ;;
  *)    7z x foo.<ext> -oout/ ;;
esac
find out/ -type f -exec file {} \; | head            # find the .exe / Mach-O / .app inside, then route
```

### Dynamic native (LLDB)

Static tools say what a binary *might* do; LLDB says what it *actually did*, with real
values. Reach for it in four situations: **static output is garbage** (packed),
**you have a hypothesis to confirm**, **you need to know what writes a value**, or
**the target is a live/hung process**.

⚠️ **Check attachability first — it decides whether this is viable at all.** macOS
refuses to attach to hardened-runtime binaries and anything under SIP:

```bash
codesign -d --entitlements - /path/to/Binary 2>&1 | grep -i get-task-allow
```
No `get-task-allow` → re-sign a **copy** with the entitlement, use `frida` instead, or
say plainly that dynamic analysis is blocked. Never disable SIP to force it.

```bash
# Confirm a static hypothesis — real argument values beat decompiler guesses
lldb --no-lldbinit -b -o 'breakpoint set --shlib target --name suspicious_func' \
     -o 'run' -o 'frame variable' -o 'bt' -o 'continue' ./target
#   → frame #0: target`add(a=2, b=40) at probe.c:2:29     <- ground truth

# Packed binary: let it unpack itself, then dump the real code for Ghidra
binwalk -E target                                    # sustained ~8.0 == packed
lldb --no-lldbinit ./target
(lldb) breakpoint set --name main                    # or an address past the stub
(lldb) run
(lldb) image list                                    # loaded base address
(lldb) memory read --binary --outfile /tmp/dumped.bin --count 0x200000 0x100000000
#   → Ghidra -loader BinaryLoader on /tmp/dumped.bin

# "What is writing to this?" — the question prints are worst at
(lldb) watchpoint set variable -w write g_license_valid
(lldb) continue
(lldb) bt                                            # the stack IS the answer

# Hung / spinning process — no source or symbols needed
lldb --no-lldbinit -p $(pgrep -n <name>) -b -o 'bt all' -o 'detach'

# Firmware with no device: QEMU gdbstub + LLDB's gdb-remote
qemu-system-arm -M <machine> -kernel firmware.bin -S -s   # -s == gdbstub on :1234
lldb --no-lldbinit -o 'gdb-remote localhost:1234' -o 'register read'
```

**Two verified traps** (both hit while testing this section): always pass
`--no-lldbinit` in scripts — `~/.lldbinit` here registers phantom pending breakpoints;
and always scope name-breakpoints, because a bare `--name add` also matched
`objc::SafeRanges::add` in `libobjc` and stopped in dyld init before reaching user
code. Run `breakpoint list` and check the location count before trusting a stop.

**Label your findings.** *Observed at runtime* is a finding; *inferred from
decompilation* is a hypothesis; *could not attach* is neither — say so rather than
presenting static-only results as confirmed.

Full playbook (re-signing, memory regions, watchpoint limits, QEMU, when LLDB is the
wrong tool): [`references/lldb-dynamic.md`](references/lldb-dynamic.md).

### Firmware

```bash
# Most firmware blobs contain an embedded filesystem (squashfs, jffs2, cramfs, ubifs)
binwalk -Me firmware.bin                             # extract recursively
find _firmware.bin.extracted -type f                 # see what came out

# If binwalk finds nothing useful: it's a raw blob. Need architecture + base address.
# Sources: vendor docs, FCC filings, similar-product datasheets.
"$GHIDRA" ~/ghidra-projects fw -import firmware.bin -overwrite \
  -loader BinaryLoader \
  -processor ARM:LE:32:v8 \
  -cspec default \
  -loader-param baseAddr=0x08000000

# yara across firmware (crypto / strings / known sigs)
# ⚠️ ~/yara-rules/ is NOT present — clone a rule set first (see Common audits #3),
#    or use `capa` / `floss`, which are installed and need no rule corpus.
yara -r ~/yara-rules/ firmware.bin

# Static reading stalled? EMULATE it instead of guessing (install on demand):
#   pipx install qiling   →  run the blob / a single function in a cross-arch sandbox, watch syscalls
#   pipx install angr     →  symbolically solve for the input that reaches a target branch
```

---

## Ghidra deep-dive

For the full Ghidra reference (headless flags, BSim function-similarity, script writing, big-binary memory tuning, gotchas), see [`references/ghidra-deep-dive.md`](references/ghidra-deep-dive.md).

Two ready-to-use Ghidra scripts ship with this skill in `scripts/`:
- `decompile_all.py <out.c>` — dump decompiled C for every function
- `dump_strings_imports.py <out.json>` — strings + imports + exports as JSON

```bash
GHIDRA=~/tools/ghidra_12.0.4_PUBLIC/support/analyzeHeadless
"$GHIDRA" ~/ghidra-projects audit -import binary -overwrite \
  -scriptPath ~/.claude/skills/decompile/scripts \
  -postScript decompile_all.py /tmp/decomp.c
```

---

## Common audits (paste-and-run)

```bash
# 0) FIRST PASS on any unknown native binary / malware sample — what does it DO + hidden strings
capa binary                                          # capabilities: C2, persistence, anti-debug, crypto, injection
capa -vv binary | rg -iE 'ATT&CK|C2|persistence'     # verbose: rule → address, mapped to MITRE ATT&CK
floss binary                                         # stack/tight/decoded strings that plain `strings` can't see

# 1) Hardcoded secrets / URLs / regexes in any binary
strings binary | rg -iE 'https?://|sk_live_|AKIA|-----BEGIN|password|api[_-]?key|bearer|token=|wss?://'

# 2) Suspicious sinks in decompiled C (Ghidra output)
rg -n 'strcpy|sprintf|gets|memcpy.*user|system\(|popen\(|setuid|exec[lv]' /tmp/decomp.c
#    …then let a tool find them automatically (install on demand — see tool table):
#    container run --rm -v "$PWD":/in ghcr.io/fkie-cad/cwe_checker:stable /in/binary   # CWE vuln patterns
#    ropper --file binary --console                  # ROP gadgets + NX/PIE/canary hardening flags

# 3) Crypto / interesting constants via YARA
#    NOTE: ~/yara-rules/ does NOT exist on this machine (verified 2026-08-20).
#    `yara` the binary IS installed; you must supply rules. Get a rule set first:
#      git clone --depth 1 https://github.com/Yara-Rules/rules ~/yara-rules
#    …or skip yara entirely — `capa` (installed) covers capability detection better.
yara -r ~/yara-rules/ binary                         # only after cloning a rule set

# 4) Diff two versions (which functions changed) — pick by depth needed
ghidriff old.bin new.bin                             # headless Ghidra diff → Markdown report (installed)
#    heavier: brew install --cask bindiff → GUI function-matching + similarity scoring
BSIM=~/tools/ghidra_12.0.4_PUBLIC/support/bsim       # or Ghidra's own BSim similarity DB
$BSIM createdatabase ~/bsim-db medium_nosize
# generate signatures for both, commit, query similar via Ghidra GUI

# 5) BLE / network captures from an Android app
adb shell settings put secure bluetooth_hci_log 1
adb shell svc bluetooth disable && adb shell svc bluetooth enable
# … exercise the feature, then …
adb bugreport bugreport.zip
unzip bugreport.zip -d br/ && find br/ -name '*.cfa' -o -name '*.btsnoop' 2>/dev/null
# Read the btsnoop capture with tshark (installed 4.6.7 — all BLE dissectors present):
tshark -r br/FS/data/misc/bluetooth/logs/btsnoop_hci.log -Y btatt \
  -T fields -e btatt.handle -e btatt.uuid128 -e btatt.value | sort -u   # GATT handles + values
tshark -r <file>.btsnoop -q -z io,phs                                   # protocol hierarchy summary

# 6) Mitm an Android app's HTTPS (rooted emulator)
mitmproxy --mode regular@8080
# On the emulator: set proxy to <host-ip>:8080, install mitm CA cert into system trust store
```

---

## Integration with /carmack

`/carmack` invokes this skill when its mode detection matches RE patterns:
- "decompile that APK", "open this .so in Ghidra", "what's inside this firmware blob", "RE this browser extension to port it to a CLI"
- carmack-mode-engineer **loads this SKILL.md** when the task involves any artifact in the routing table.
- After RE phase completes, carmack returns to its normal flow (closed-loop verification, fix-all-issues rule, no-suppression rule). RE outputs (decompiled source, extracted strings, BLE UUIDs, etc.) feed the engineering work.

**Reference incident (Whoop RE, 2026-05-28):** /goal kicked off "find software on a Whoop watch + decompile + probe my watch". The skill correctly routed to `jadx` (not Ghidra) because Whoop's app is Java/Kotlin, not native. Result in ~22 min: 3 GATT service families found in `~/re/whoop/jadx-out/sources/zo0/p.java`, including a previously-undocumented Whoop 5.0/MG family (`11500001-6215-11ee-8c99-0242ac120002`). This skill rename + reorg captures the lesson: **default to the routing table, not to Ghidra.** See `~/Downloads/whoop-re-findings-2026-05-28.html` for the worked example.

---

## Output template for the user

When reporting RE findings, include:
- **File**: path + SHA-256 + `file` output
- **Class**: which row in the routing table fired
- **Tools used**: ordered (e.g. `apkeep → unzip → jadx → grep → cfr-decompiler`)
- **Key findings**: file:line citations into decompiled output for each claim
- **Strings of interest**: URLs / API keys / version constants
- **Next-step proposal**: the one concrete next move (btsnoop capture, frida hook, etc.)

---

## Out of scope (route elsewhere, don't refuse)

- **Debugging a live website** (why is this page broken/slow/erroring) → `/debug`, `/chrome`, or `chrome-devtools` MCP. Not an RE problem.
  **But** *reverse-engineering a site's private API into a client or MCP server* **is in scope** — `fcdp`/`fhar` first, a logged-in browser CLI when inspect/fetch/replay fits, then [Session capture](#session-capture--typed-client--mcp-server).
- **Pentesting / attacking a site you don't control** → out of scope. `fhar` / `fcdp` / a logged-in browser CLI drive *your own* logged-in session against services you already have an account on, for interoperability.
- **Network captures from a non-mobile app** → `tshark`/`dumpcap` (installed, Wireshark 4.6.7 CLI — GUI is the separate `wireshark-app` cask), or `mitmproxy` for HTTP(S).
- **Source-code review of available source** → ripgrep + `/carmack` review mode.

---

## See also

- a logged-in browser CLI skill — call **after** `fcdp`/`fhar` when inspect / fetch / GET-only replay is the better tool
- `references/har-capture.md` — **session capture playbook**: logout→login HAR, distill, typed client + MCP server; GraphQL/WebSocket/multi-host gotchas
- `references/lldb-dynamic.md` — **dynamic native playbook**: attachability gate, unpack-and-dump, watchpoints, attach-to-PID, QEMU `gdb-remote`, and when LLDB is the wrong tool
- `references/ghidra-deep-dive.md` — Ghidra headless flags, BSim, script writing, gotchas
- `references/android-re.md` — Android deep-dive: **mandatory dynamic-capture playbook** (emulator + mitmproxy CA + frida unpinning + btsnoop), APK-acquisition + ABI gotchas
- `scripts/decompile_all.py` — Ghidra post-script: dump all decompiled functions
- `scripts/dump_strings_imports.py` — Ghidra post-script: strings + imports + exports → JSON
- `/carmack` skill — calls into this skill for RE tasks; for a website use `fcdp`/`fhar` first, then a logged-in browser CLI if that fits
- `~/.beads/AGENTS.md` — task tracking conventions (use `bd` for multi-session RE projects)
