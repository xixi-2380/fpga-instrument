"""Prove old/new limiter rounding for every representable sample/gain product.
Requires z3-solver. The bound is wider than signed24 * unsigned17 can reach.
"""
import json,time
from pathlib import Path
from z3 import BitVec,BitVecVal,Extract,If,ZeroExt,Solver,unsat
start=time.monotonic();p=BitVec('product',42)
magnitude=If(Extract(41,41,p)==1,-p,p)
old_mag=ZeroExt(1,Extract(40,16,magnitude)) # 26-bit positive integer
old=If(Extract(41,41,p)==1,-old_mag,old_mag)
floor=Extract(41,16,p)
correction=If((Extract(41,41,p)==1)&(Extract(15,0,p)!=0),BitVecVal(1,26),BitVecVal(0,26))
new=floor+correction
s=Solver();s.set(timeout=60000)
s.add(p>=-(1<<40),p<=(1<<40));s.add(old!=new)
result=s.check();assert result==unsat,str(result)
# Mathematical range: abs(signed24)*max(unsigned17) < 2**40.
assert (1<<23)*((1<<17)-1)<(1<<40)
print(json.dumps(dict(proof='UNSAT: old != new',product_interval=[-(1<<40),1<<40],seconds=round(time.monotonic()-start,4),note='All signed24*unsigned17 products; output saturation and registers unchanged')))
