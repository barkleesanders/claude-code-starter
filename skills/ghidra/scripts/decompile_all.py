# Ghidra headless script: dump decompiled C for every function.
# Usage:  analyzeHeadless ... -postScript decompile_all.py /path/to/out.c
# @category  Skill.Ghidra
# @runtime  Jython
import sys
from ghidra.app.decompiler import DecompInterface
from ghidra.util.task import ConsoleTaskMonitor

args = getScriptArgs()
out_path = args[0] if args else "/tmp/ghidra-decomp.c"

decomp = DecompInterface()
decomp.openProgram(currentProgram)
monitor = ConsoleTaskMonitor()

fm = currentProgram.getFunctionManager()
funcs = list(fm.getFunctions(True))
print("[decompile_all] %d functions -> %s" % (len(funcs), out_path))

with open(out_path, "w") as f:
    f.write("// Program: %s\n" % currentProgram.getName())
    f.write("// Compiler: %s\n" % currentProgram.getCompiler())
    f.write("// Language: %s\n\n" % currentProgram.getLanguageID())
    for fn in funcs:
        if fn.isThunk() or fn.isExternal():
            continue
        res = decomp.decompileFunction(fn, 60, monitor)
        if res and res.decompileCompleted():
            code = res.getDecompiledFunction().getC()
            f.write("// ---- %s @ %s ----\n" % (fn.getName(), fn.getEntryPoint()))
            f.write(code)
            f.write("\n")
print("[decompile_all] done")
