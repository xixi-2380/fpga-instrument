from z3 import *
current,target=BitVecs('current target',17)
old=If(UGT(current,target),If(UGT(current-target,BitVecVal(256,17)),current-BitVecVal(256,17),target),If(UGT(target-current,BitVecVal(256,17)),current+BitVecVal(256,17),target))
error=ZeroExt(1,target)-ZeroExt(1,current)
new=If(error>BitVecVal(256,18),current+BitVecVal(256,17),If(error < BitVecVal(-256,18),current-BitVecVal(256,17),target))
s=Solver();s.add(old!=new)
r=s.check();assert r==unsat,(r,s.model())
print('PASS all 2^34 unsigned17-bit current/target pairs proven equivalent (Z3 UNSAT for any mismatch)')
