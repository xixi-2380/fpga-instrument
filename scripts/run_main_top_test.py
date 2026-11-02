from pathlib import Path
import os,subprocess,xml.etree.ElementTree as ET,json,hashlib,re,time
r=Path(__file__).resolve().parents[1];o=r/'reports/adjustments_20261101/main_top';o.mkdir(parents=True,exist_ok=True)
b=Path('C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin');env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH']
files=[r/f.get('path') for f in ET.parse(r/'keyboard_adsr.gprj').getroot().findall('./FileList/File') if f.get('type')=='file.verilog' and f.get('enable')=='1' and f.get('path')!='src/pll_pair.sv']
files += [r/'sim'/n for n in ['pll_pair_behavioral.sv','pixel_pll_behavioral.sv','io_behavioral.sv','integration/tb_main_top.sv']]
inputs=set(files)|set((r/'src').rglob('*.svh'))|set((r/'src').rglob('*.hex'))
hashes={p.relative_to(r).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs)};start=time.monotonic()
cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'src').as_posix(),'-I'+(r/'sim').as_posix(),'-s','tb_main_top','-o',(o/'test.vvp').as_posix()]+[p.as_posix() for p in files]
c=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf-8');(o/'compile.log').write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
v=subprocess.run([str(b/'vvp.exe'),(o/'test.vvp').as_posix()],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=900);log=v.stdout+v.stderr;(o/'run.log').write_text(log,encoding='utf-8');print(log,flush=True)
assert v.returncode==0 and 'PASS tb_main_top' in log,log
assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),'Source changed during test'
(o/'validation.json').write_text(json.dumps(dict(passed=True,seconds=time.monotonic()-start,source_sha256=hashes,checks=int(re.search(r'checks=(\d+)',log)[1]),behavioral_pll=True,sta_passed=False),indent=2),encoding='utf-8')
