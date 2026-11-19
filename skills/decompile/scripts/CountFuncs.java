import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.FunctionIterator;
public class CountFuncs extends GhidraScript {
    @Override public void run() throws Exception {
        int n = 0; FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext()) { it.next(); n++; }
        println("FUNCTIONCOUNT " + n);
    }
}
