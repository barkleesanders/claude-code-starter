# Dynamic native analysis with LLDB

The static half of this skill (Ghidra, radare2, capa) tells you what a binary *might*
do. LLDB tells you what it *actually did* on this run, with real values. Reach for it
when static reading has stalled, produced garbage, or produced a hypothesis you need to
confirm.

`lldb` is at `/usr/bin/lldb` (ships with Xcode CLT). Verified working 2026-08-20 —
`lldb-2100.0.17.203`.

---

## The macOS attach constraint — read this before planning a session

macOS restricts debugger attach far more than Linux. **Check this first**, because it
decides whether a dynamic approach is viable at all:

| Target | Attachable? |
|---|---|
| Binary you compiled | Yes |
| Unsigned / ad-hoc-signed third-party binary | Usually yes |
| Signed app **with** `com.apple.security.get-task-allow` | Yes |
| Signed app **without** `get-task-allow` (hardened runtime — most shipped apps) | **No** |
| Apple system binaries under SIP | **No** |

```bash
codesign -d --entitlements - /path/to/Binary 2>&1 | grep -i get-task-allow
```

No `get-task-allow` → you have three options, in order of preference:

1. **Re-sign locally with the entitlement** (works on your own machine, on apps whose
   signature you're allowed to replace):
   ```bash
   /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' /tmp/ent.plist
   codesign -f -s - --entitlements /tmp/ent.plist /path/to/Binary
   ```
   This breaks the original signature — work on a **copy**, and expect anything doing
   its own integrity check to notice.
2. **Use frida instead** (`frida -f <bundle-id>`) — different injection path, often
   works where `lldb -p` bounces, and it's already the tool of record for mobile here.
3. **Give up on dynamic for that target** and say so explicitly rather than silently
   reporting static-only findings as if they were confirmed.

> Do not disable SIP to make a debugging session work. If the analysis genuinely
> requires it, say so and let the user decide.

---

## Gotcha: `.lldbinit` pollution (hit while verifying this file)

`~/.lldbinit` on this machine is ~10 KB and registers a pile of breakpoints at
startup. In a scripted run they surface as `Breakpoint 10..19: no locations (pending)`
noise and the process stops somewhere you never asked for.

**Always pass `--no-lldbinit` for scripted/batch runs.** Interactive exploration can
keep it.

## Gotcha: symbol-name breakpoints collide with system libraries

`breakpoint set --name add` on a trivial test binary matched **2 locations** — the
second being `objc::SafeRanges::add` inside `libobjc.A.dylib`. The process stopped in
dyld's initializer long before reaching user code, which reads exactly like "my
breakpoint fired" if you aren't watching the frame.

Scope every name breakpoint:
```bash
breakpoint set --shlib <YourBinary> --name <func>     # restrict to one image
breakpoint set --file <src.c> --line <N>              # or use file:line
breakpoint list                                        # ALWAYS confirm location count
```
If `breakpoint list` shows more locations than you expect, you are about to debug the
wrong code.

---

## Recipe 1 — verify a static hypothesis (the cheapest win)

Ghidra's decompiler *guesses* types and semantics. A breakpoint settles it.

```bash
lldb --no-lldbinit -b \
  -o 'breakpoint set --shlib target --name suspicious_func' \
  -o 'run' \
  -o 'frame variable' \
  -o 'bt' \
  -o 'continue' \
  ./target
```

Proven output shape (real run):
```
frame #0: 0x000000010000046c probe`add(a=2, b=40) at probe.c:2:29
```
Real argument values, source line, call stack. That is ground truth; the decompiled
pseudo-C was a hypothesis.

## Recipe 2 — unpack a packed/obfuscated binary (the biggest win)

Static decompilation of packed code yields garbage. But packed code **must** decrypt
itself into memory to execute. Let it, then dump.

```bash
# 1) Confirm it's packed before wasting a Ghidra import
binwalk -E target                       # entropy plot: sustained ~8.0 == packed/encrypted
rabin2 -I target                        # radare2's readelf/otool equivalent
capa target                             # capa flags packer/anti-analysis rules

# 2) Break after the unpack stub, then dump the region
lldb --no-lldbinit ./target
(lldb) breakpoint set --name main       # or an address just past the stub
(lldb) run
(lldb) image list                        # find the loaded base address
(lldb) memory region 0x100000000         # confirm the mapped range
(lldb) memory read --binary --outfile /tmp/dumped.bin \
         --count 0x200000 0x100000000
```

Then feed `/tmp/dumped.bin` to Ghidra with `-loader BinaryLoader` and the right
processor. You now have real code instead of a packer stub.

For UPX specifically, try the trivial path first — `brew install upx && upx -d target`
(upx is **not** currently installed here). Custom packers need the dump route above.

## Recipe 3 — watchpoints: "what is writing to this?"

The question print-debugging is worst at, because you don't know where to put the print.

```bash
(lldb) watchpoint set expression -w write -s 8 -- 0x100200abc   # by address
(lldb) watchpoint set variable   -w write g_license_valid       # by symbol
(lldb) continue
(lldb) bt        # when it fires: the stack IS the answer
```

Hardware watchpoints are limited (typically 4 on arm64) and sized 1/2/4/8 bytes.
`watchpoint list` to check what you've used.

## Recipe 4 — attach to something hung or spinning

No source, no symbols needed. Highest value-per-second in the whole file.

```bash
lldb --no-lldbinit -p $(pgrep -n <name>) -b -o 'bt all' -o 'detach'
```
`bt all` dumps every thread's stack — deadlocks and spin loops are usually obvious on
sight. macOS `sample <pid>` is a lighter no-attach alternative that also beats SIP in
some cases.

## Recipe 5 — firmware you can't run natively (QEMU + gdb-remote)

LLDB speaks the gdb remote protocol, so it attaches to an emulated target. This is the
escape hatch for the [Firmware](../SKILL.md#firmware) workflow when the blob is
ARM/MIPS and you have no device.

```bash
qemu-system-arm -M <machine> -kernel firmware.bin -S -s     # -S halt, -s gdbstub :1234
lldb --no-lldbinit
(lldb) gdb-remote localhost:1234
(lldb) register read
(lldb) stepi
```
Pairs with `qiling` (emulation sandbox, `pipx install qiling`) when you want scripted
syscall tracing instead of manual stepping.

---

## When LLDB is the WRONG tool

- **JVM / .NET / Python bytecode / JS / WASM** — wrong runtime entirely. Use
  `cfr-decompiler`, `ilspycmd`, `decompyle3`, `webcrack`, `wasm2wat`. Attaching LLDB to
  the interpreter shows you the *interpreter's* C stack, not your program.
- **Python specifically** — LLDB on `python3` shows CPython internals. Use `pdb` /
  `breakpoint()`.
- **Android native** — `lldb-server` works but frida is more ergonomic and already
  wired into [`android-re.md`](android-re.md).
- **Anything a diff, log, or `capa` run answers faster.** A debugger is for state you
  cannot otherwise reach.

## Reporting rule

A dynamic finding outranks a static one, so label which you have. Distinguish:
- **observed at runtime** (breakpoint hit, value read) — a finding
- **inferred from decompilation** — a hypothesis
- **could not attach** (hardened runtime / SIP) — neither; say so explicitly rather
  than presenting static-only results as confirmed
