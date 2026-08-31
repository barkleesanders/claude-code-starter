# Ghidra headless script: dump strings, imports, exports, and functions as JSON.
# Usage:  analyzeHeadless ... -postScript dump_strings_imports.py /path/to/out.json
# @category  Skill.Ghidra
# @runtime  Jython
import json
from ghidra.program.model.data import StringDataInstance

args = getScriptArgs()
out_path = args[0] if args else "/tmp/ghidra-sa.json"

p = currentProgram
out = {
    "name": p.getName(),
    "language": str(p.getLanguageID()),
    "compiler": str(p.getCompiler()),
    "image_base": str(p.getImageBase()),
    "min_addr": str(p.getMinAddress()),
    "max_addr": str(p.getMaxAddress()),
    "imports": [],
    "exports": [],
    "functions": [],
    "strings": [],
}

st = p.getSymbolTable()

# Imports (external symbols)
for sym in st.getExternalSymbols():
    out["imports"].append({
        "name": sym.getName(),
        "library": sym.getParentNamespace().getName() if sym.getParentNamespace() else None,
    })

# Exports (entry points)
for sym in st.getSymbolIterator(True):
    if sym.isExternalEntryPoint():
        out["exports"].append({
            "name": sym.getName(),
            "address": str(sym.getAddress()),
        })

# Functions
for fn in p.getFunctionManager().getFunctions(True):
    out["functions"].append({
        "name": fn.getName(),
        "entry": str(fn.getEntryPoint()),
        "size": fn.getBody().getNumAddresses(),
        "is_thunk": fn.isThunk(),
        "is_external": fn.isExternal(),
        "params": fn.getParameterCount(),
    })

# Defined strings
listing = p.getListing()
data_iter = listing.getDefinedData(True)
while data_iter.hasNext():
    d = data_iter.next()
    if d.hasStringValue():
        try:
            s = d.getValue()
            if s is None:
                continue
            s = unicode(s)
            if len(s) < 4:
                continue
            out["strings"].append({"address": str(d.getAddress()), "value": s})
        except:
            pass

with open(out_path, "w") as f:
    json.dump(out, f, indent=2)
print("[dump_strings_imports] wrote %s (%d strings, %d funcs, %d imports)" %
      (out_path, len(out["strings"]), len(out["functions"]), len(out["imports"])))
