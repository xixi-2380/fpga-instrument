from pathlib import Path
import random, json
import pyslang
from pyslang.syntax import SyntaxTree
from pyslang.ast import Compilation
root=Path(__file__).resolve().parents[2]
c=Compilation();c.addSyntaxTree(SyntaxTree.fromFile(str(root/'src/pcb_debug_ui.sv')))
errors=[d for d in c.getAllDiagnostics() if d.isError()]
assert not errors,pyslang.DiagnosticEngine.reportAll(c.sourceManager,errors)
def convert(value):
 n=min(value,99999);bcd=0
 for bit in range(16,-1,-1):
  a=bcd
  for digit in range(5):
   if ((bcd>>(digit*4))&15)>=5:a+=3<<(digit*4)
  bcd=((a<<1)|((n>>bit)&1))&0xfffff
 digits=[(bcd>>s)&15 for s in (16,12,8,4,0)]
 return ''.join(' ' if i<4 and all(x==0 for x in digits[:i+1]) else str(d) for i,d in enumerate(digits))
r=random.Random(2380)
values=list(range(131072))+[r.randrange(2**32) for _ in range(20000)]+[2**32-1]
for v in values:assert convert(v)==str(min(v,99999)).rjust(5)
for n in range(32):
 t=3 if n>=30 else 2 if n>=20 else 1 if n>=10 else 0
 assert str(t)+str(n-10*t)==str(n).zfill(2)
result=dict(syntax_elaboration_errors=0,decimal5_reference_checks=len(values),decimal2_reference_checks=32,hdl_simulation=False,gowin_synthesis_and_pnr=False,base_commit='89af23fa1b6954c174fc00d9862e6b15420f8cbf')
(Path(__file__).resolve().parent/'validation.json').write_text(json.dumps(result,indent=2))
print(result)
