"""Test pulse widths including actual 50 MHz/1 ms and every keyboard bank."""
from pathlib import Path
import argparse, os, subprocess, json, hashlib, re
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[1];o=r/'reports/adjustments_20261101/key_probe';o.mkdir(parents=True,exist_ok=True)
b=a.tool_bin.resolve();env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH']
files=[r/'src/key_input_probe.sv',r/'sim/integration/tb_key_input_probe.sv']
hashes={f.relative_to(r).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
cmd=[str(b/'iverilog.exe'),'-g2012','-s','tb_key_input_probe','-o',(o/'test.vvp').as_posix()]+[f.as_posix() for f in files]
c=subprocess.run(cmd,env=env,capture_output=True,text=True);(o/'compile.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stderr
v=subprocess.run([str(b/'vvp.exe'),(o/'test.vvp').as_posix()],env=env,capture_output=True,text=True,timeout=60)
log=v.stdout+v.stderr;(o/'run.log').write_text(log);print(log);assert v.returncode==0 and 'PASS tb_key_input_probe' in log
assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
(o/'validation.json').write_text(json.dumps(dict(passed=True,checks=int(re.search(r'checks=(\d+)',log)[1]),source_sha256=hashes,hardware_tested=False),indent=2))
