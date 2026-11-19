// Decompile all functions to a C file + count functions. Java GhidraScript (no PyGhidra needed).
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.io.FileWriter;
import java.io.PrintWriter;

public class DecompileAllJava extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        String outPath = args.length > 0 ? args[0] : "/tmp/decompiled.c";
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        PrintWriter out = new PrintWriter(new FileWriter(outPath));
        FunctionIterator funcs = currentProgram.getFunctionManager().getFunctions(true);
        int total = 0, ok = 0, fail = 0;
        while (funcs.hasNext() && !monitor.isCancelled()) {
            Function f = funcs.next();
            total++;
            try {
                DecompileResults res = decomp.decompileFunction(f, 60, monitor);
                if (res != null && res.decompileCompleted()) {
                    out.println("// ===== " + f.getName() + " @ " + f.getEntryPoint() + " =====");
                    out.println(res.getDecompiledFunction().getC());
                    ok++;
                } else { fail++; }
            } catch (Exception e) { fail++; }
        }
        out.println("// SUMMARY total=" + total + " decompiled=" + ok + " failed=" + fail);
        out.close();
        decomp.dispose();
        println("DECOMPILEALL total=" + total + " ok=" + ok + " fail=" + fail);
    }
}
