"""Icarus simulation of an EXISTING netlist only. Never invokes Gowin tools."""
from pathlib import Path
import os,subprocess,hashlib,json
r=Path(__file__).resolve().parents[1]
out=r/'reports/keyboard/netlist_check';out.mkdir(exist_ok=True)
vg=r/'impl/gwsynthesis/D2_keyboard_adsr.vg'
env=os.environ.copy();bin=r/'tools/mingw64/bin';env['PATH']=str(bin)+os.pathsep+env['PATH']
cmd=[str(bin/'iverilog.exe'),'-g2012','-Isim','-s','tb_keyboard_netlist','-o',str(out/'netlist.vvp'),
     str(vg),'C:/Gowin/Gowin_V1.9.12.04_x64/IDE/simlib/gw5a/prim_sim.v',str(r/'sim/keyboard_netlist_tb.v')]
p=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace')
(out/'compile.log').write_text(p.stdout+p.stderr,encoding='utf8')
if p.returncode:print(p.stdout+p.stderr);raise SystemExit(p.returncode)
print('RUN existing synthesized netlist with behavioral audio clock/reset bypass',flush=True)
p=subprocess.run([str(bin/'vvp.exe'),str(out/'netlist.vvp')],cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=600)
log=p.stdout+p.stderr;(out/'result.log').write_text(log,encoding='utf8');print(log)
ok=p.returncode==0 and 'PASS tb_keyboard_netlist' in log and 'FAIL' not in log
(out/'status.json').write_text(json.dumps(dict(passed=ok,netlist_sha256=hashlib.sha256(vg.read_bytes()).hexdigest(),pll_bypassed=True,hardware_verified=False),indent=2),encoding='utf8')
raise SystemExit(0 if ok else 1)
