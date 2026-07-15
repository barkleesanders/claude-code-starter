---
name: decompile
description: Reverse-engineer ANY binary, bundle, or distributable — compiled native (.exe/.dll/.so/.dylib/Mach-O), JVM (.jar/.apk/.dex), .NET (.dll/.exe IL), iOS (.ipa), browser extensions (.crx/.xpi), WebAssembly (.wasm), Python bytecode (.pyc), React Native Hermes (.hbc), JS bundles, firmware blobs, installers (.deb/.rpm/.dmg/.msi). Routes to the correct tool per file class — Ghidra is just one tool in the kit. Use when the user says decompile, disassemble, reverse-engineer, RE, "look inside this binary/app/extension/firmware", triage malware, audit a binary for vulns, diff functions across versions, or port a closed-source thing to a CLI. Does NOT pentest live websites — for that route to /carmack with browser-automation patterns.
---

# /decompile — universal binary reverse-engineering kit

Successor to the old `/ghidra` skill. Ghidra is one tool here, not the default. The skill's job is to **route the artifact to the right tool** — for most modern artifacts (Android apps, browser extensions, JS bundles, .NET, Python bytecode, React Native Hermes), Ghidra is the wrong tool.

## Scope rules (mandatory)

1. Operates only on artifacts the user **lawfully possesses locally**. Never fetches from a URL the user doesn't have rights to.
2. Refuse if the user asks you to RE software they don't have rights to (commercial DRM bypass, license-check removal, weaponizing malware against third parties). OK: their own builds/devices, CTF binaries, malware samples for triage, signed installers they downloaded, firmware from a device they own, open-source projects, security research on systems they own or have written authorization to test.
3. **Always work on a copy.** Many tools write project DBs alongside (Ghidra) or modify in place (apktool patch). Never touch the source artifact directly.
4. **DMCA §1201(f) posture:** working on devices the user owns for interoperability (e.g. talking to their own wearable over BLE without the official app) is the default Whoop/Garmin/Polar use case.

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
```

For uncertainty between "compiled binary" and "archive/installer": `binwalk` finds embedded formats; `7z l` lists archive contents non-destructively.

---

## STEP 2 — Route by artifact class

The routing table is the centerpiece of this skill. Match the artifact to a row, then follow the linked workflow. **Do not default to Ghidra.**

| `file` says / extension | Class | Primary tool | Fallback / deeper | Workflow |
|---|---|---|---|---|
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
| NSIS / Inno / UPX self-extractor | Packed `.exe` | `7z x`, `upx -d` | then Ghidra on unpacked | [Installer](#installer) |
| Minified / source-mapped JS | JavaScript text | `prettier --write '**/*.js'` | `terser --beautify`, `webcrack` | [Browser extension](#browser-extension) |
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
| `frida` | `~/.local/bin/frida` | Dynamic instrumentation (hook funcs at runtime) |
| `objection` | `~/.local/bin/objection` | Frida-based mobile pentest, SSL pinning bypass |
| `mitmproxy` | `~/.local/bin/mitmproxy` | TLS-intercepting proxy; reveal API calls from any app |
| `hbc-decompiler` / `hbc-disassembler` | `~/.local/bin/` (pipx pkg `hermes-dec`) | React Native Hermes bytecode → JS. Binaries are `hbc-*`, not `hermes-dec <verb>`. |
| `hbctool` | `~/.local/bin/hbctool` | Hermes `disasm`/`asm` round-trip (patch + repack .hbc) |
| `decompyle3` | `~/.local/bin/decompyle3` | Python 3.7–3.9 bytecode → source |
| `uncompyle6` | `~/.local/bin/uncompyle6` | Python 2.7 / 3.0–3.8 bytecode → source (older-Python fallback to decompyle3) |
| `androguard` | `~/.local/bin/androguard` (pipx) | APK static analysis CLI + Python API (manifest, perms, certs) |
| `ilspycmd` | `~/.dotnet/tools/ilspycmd` | .NET/MSIL decompiler. Needs `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec` (set in `~/.zshrc`) |
| `webcrack` | `/opt/homebrew/bin/webcrack` (npm global) | JS deobfuscator/unminifier. Installed `--ignore-scripts` (no `isolated-vm`); core deobf works, VM-sandbox bundle-unpack unavailable |
| `binwalk` | `/opt/homebrew/bin/binwalk` | Extract embedded archives + filesystems in firmware |
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
| `fcdp` | `~/tools/fcdp/fcdp` | Drive your REAL LOGGED-IN Chrome (via its own extension+bridge, full CDP) to **acquire** artifacts behind auth: open pages, capture real download URLs (`fcdp intercept`), reach store/portal downloads. See [Acquisition](#acquisition-get-the-artifact-first). |
| `mimic` | `~/.local/bin/mimic` (uv tool `mimic-client`, from `git+https://github.com/littledivy/mimic`) | Capture an iOS app's traffic → **AI-generate a Python client** for its private API. Automates the manual "capture → extract → build a CLI" flow: `mimic record` (proxy + iPhone setup) → `mimic hosts` → `mimic learn <host>` → `mimic gen <host>`; `mimic unpin <ipa\|id>` defeats cert-pinning via Frida; `mimic doctor` checks setup. Deps already present (mitmproxy, `claude` CLI, frida, objection). See [App-API client generation](#app-api-client-generation-mimic). |

**Tool notes / gotchas:**
- `ilspycmd` (.NET) — installed, but the Homebrew `dotnet` puts its runtime in a Cellar path the tool's apphost can't find, so it needs `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec`. This is exported in `~/.zshrc` (line ~434), so it Just Works in a login shell. If you ever see "You must install .NET to run this application," that env var is missing.
- `webcrack` — installed globally with `--ignore-scripts`, which skips the `isolated-vm` native build (it fails to compile under Node 26 — no prebuilt binary yet). Core deobfuscation (unminify, string-array decode, control-flow unflatten, prettify) all work. The ONLY thing missing is the VM-sandbox unpacker for some webpack bundles; if you hit a bundle that needs it, fall back to the `de4js` web UI.
- `uncompyle6` / `decompyle3` / `hbctool` — all run on a Python 3.14 pipx host, which is newer than these tools officially target. They launch and work for the common case; if one chokes on a specific bytecode version, that's the host-version mismatch, not a missing install.

**Known-gap tools** (genuinely not installed — install on demand):
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
**logged-in Chrome**; use `fcdp` (`~/tools/fcdp/fcdp`, full CDP on your REAL session — `fcdp --help`).

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
If the download lives in another account (Profile 4 = hello@example.com), switch to that
Chrome profile/window first, then re-run `$FCDP tabs` to confirm you're pointed at it.

**Auth'd download with a plain `curl`/`yt-dlp` (no browser drive needed) → export your real Chrome cookies, LOCAL-only.**
```bash
~/tools/cookies-txt <domain> -o <domain>.cookies.txt   # chmod 600; prints path+count, NEVER values
curl -b <domain>.cookies.txt -L -o artifact "<url>"    # session cookies authenticate the fetch
yt-dlp --cookies <domain>.cookies.txt "<url>"          # same file works for yt-dlp
```
`~/tools/cookies-txt` reads the real Chrome profile's cookie DB + decrypts via macOS Keychain. Cookies never leave this machine.

> Scope still applies (see top): only acquire artifacts you lawfully possess — your
> own builds/devices, CTF, samples for triage, things you have rights to. Don't drive
> the browser to grab software you have no right to.

### Live web-app / API endpoint discovery (find the endpoint that "does the thing")

When the goal is *"what API call does this logged-in web app make to do X"* (so you can drive it from a CLI), do NOT Ghidra anything and do NOT start by scraping minified JS. Climb this ladder — stop at the first rung that answers it:

1. **Open-source backend routes (authoritative — read it first).** If the backend is open source (e.g. VA = `department-of-veterans-affairs/vets-api`), the route table IS the endpoint map — better than any frontend scrape. Read `config/routes.rb`. **Critically, grep for `mount <X>::Engine, at: '/path'`** and read each engine's own `routes.rb` — mounted engines hide entire route families a top-level grep misses. (2026-06-21: the VA 20-10206 submit endpoint `POST /simple_forms_api/v1/simple_forms` lived in a mounted `SimpleFormsApi::Engine`; a `/v0`-only grep "proved" no submit API existed — wrongly. The engine route was the answer.) Then read the controller + any `spec/fixtures/*.json` for the exact request-body shape.
   ```bash
   gh api repos/<org>/<repo>/contents/config/routes.rb --jq '.content' | base64 -d | grep -nE 'mount .*Engine|<keyword>'
   gh api repos/<org>/<repo>/contents/modules/<engine>/config/routes.rb --jq '.content' | base64 -d
   ```
2. **Deployed frontend bundle (when backend isn't open source).** The SPA's JS references its own API paths. Capture the bundle URL via CDP, `prettier`/`webcrack` it, then `rg -oiE '"/api/[^"]+"|fetch\(|axios\.(get|post)'` for endpoint strings + method.
3. **Live CDP network capture (ground-truth confirmation — always do this before building a mutation).** Drive the **REAL logged-in Chrome via `fcdp`** (`~/tools/fcdp/fcdp intercept`), perform the action by hand once, and read the network log for the EXACT request: method, full path, headers, and request body. A decompiled/route-listed endpoint is *capability*; the captured call is *proof of the real contract* (params the server actually requires, header shape, CSRF). 
   ```bash
   ~/tools/fcdp/fcdp open "<the page that does X>"; # …click the button by hand…
   ~/tools/fcdp/fcdp intercept | rg -iE 'POST|PUT|/api/|/v[0-9]+/'   # find the call; then inspect its body
   ```
4. **Reuse with the user's own session.** Read-only endpoints → replay with the session cookie/token (see the cookies/`vatp` patterns). **Mutations (submit/file/pay/delete) are outward, irreversible actions → dry-run, show the exact body, get explicit per-action approval.** Never auto-fire a state-changing endpoint, and never populate a legal e-signature field (`statement_of_truth_signature` etc.) on the user's behalf.

Worked example: `~/tools/va-travel-cli/vatp` (VA benefits read commands + the 20-10206 submit contract) was built entirely from rungs 1+3 against `vets-api` — zero binary RE.

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

**Scope + safety (same as the rest of this skill):** only capture apps on **your own device** for interoperability with **your own** account/data (DMCA §1201(f) posture). `mimic gen` sends captured endpoint shapes to Claude to synthesize the client — don't run it on traffic containing third-party PII or another party's secrets. **Cert-pinning / DPoP-bound tokens** block plain capture — `mimic unpin` handles pinning; DPoP-bound apps still won't replay. If `mimic doctor` shows `[MISSING] mitmweb running`, that's expected until you start `mimic record` in another terminal.

### Native Mach-O

```bash
file binary; otool -h binary; otool -L binary; lipo -info binary
nm -gU binary | head -40
strings binary | rg -iE 'https?://|key|secret|sk_|api[_-]?key' | head -30

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

### Native ELF

```bash
file binary; readelf -a binary | head -40
objdump -d binary | less
r2 -A binary
```

Ghidra uses ElfLoader automatically.

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

Most common path. Standalone reference deep-dive: see `references/android-re.md` (full APK download paths, native libs, frida hooks, btsnoop capture, mitmproxy on rooted emulator). Quick version:

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

# 6) Dynamic
frida -U -n com.example.app -l hook.js
objection -g com.example.app explore
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
case "$ext" in
  deb)  dpkg-deb -x foo.deb out/ ;;
  rpm)  rpm2cpio foo.rpm | cpio -idmv ;;
  dmg)  hdiutil attach foo.dmg ;;                    # or: 7z x foo.dmg
  pkg)  pkgutil --expand foo.pkg out/ ;;
  msi)  7z x foo.msi -oout/ ;;
  *)    7z x foo.<ext> -oout/ ;;
esac
find out/ -type f -exec file {} \; | head            # find the .exe / Mach-O / .app inside, then route
```

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
yara -r ~/yara-rules/ firmware.bin
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
# 1) Hardcoded secrets / URLs / regexes in any binary
strings binary | rg -iE 'https?://|sk_live_|AKIA|-----BEGIN|password|api[_-]?key|bearer|token=|wss?://'

# 2) Suspicious sinks in decompiled C (Ghidra output)
rg -n 'strcpy|sprintf|gets|memcpy.*user|system\(|popen\(|setuid|exec[lv]' /tmp/decomp.c

# 3) Crypto / interesting constants via YARA
yara -r ~/yara-rules/crypto_signatures.yar binary

# 4) Diff two firmware versions (which functions changed)
BSIM=~/tools/ghidra_12.0.4_PUBLIC/support/bsim
$BSIM createdatabase ~/bsim-db medium_nosize
# generate signatures for both, commit, query similar via Ghidra GUI

# 5) BLE / network captures from an Android app
adb shell settings put secure bluetooth_hci_log 1
adb shell svc bluetooth disable && adb shell svc bluetooth enable
# … exercise the feature, then …
adb bugreport bugreport.zip
unzip bugreport.zip -d br/ && find br/ -name '*.cfa' -o -name '*.btsnoop' 2>/dev/null
# Open in Wireshark → filter by service UUID

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
- **Strings of interest**: URLs / API keys / version constants (redact secrets if not the user's own asset)
- **Next-step proposal**: the one concrete next move (btsnoop capture, frida hook, etc.)

---

## Out of scope (route elsewhere, don't refuse)

- **Live remote websites / web apps** → `chrome-devtools` MCP, `unbrowse`, or `/debug` skill. Not a binary-RE problem.
- **Network captures from a non-mobile app** → `wireshark`, `tshark`, `mitmproxy`.
- **Source-code review of available source** → ripgrep + `/carmack` review mode.
- **Anything requiring access to systems the user doesn't own or have written authorization to test** → refuse with a brief explanation.

---

## See also

- `references/ghidra-deep-dive.md` — Ghidra headless flags, BSim, script writing, gotchas
- `references/android-re.md` — Android deep-dive (planned: APK sources, native libs, frida, mitm)
- `scripts/decompile_all.py` — Ghidra post-script: dump all decompiled functions
- `scripts/dump_strings_imports.py` — Ghidra post-script: strings + imports + exports → JSON
- `/carmack` skill — calls into this skill for RE tasks; resumes engineering flow afterward
- `~/.beads/AGENTS.md` — task tracking conventions (use `bd` for multi-session RE projects)
