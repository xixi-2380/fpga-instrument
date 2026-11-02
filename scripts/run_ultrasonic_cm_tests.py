"""Real echo-to-cm/pitch/BCD, legacy-unit reproduction and exact UI labels.
No synthesis, placement, routing or hardware access.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, time

ROOT=Path(__file__).resolve().parents[1]
BIN=Path('C:/Users/10939/Documents/Codex/2026-10-30/qin-2/work/sim-tools/mingw64/bin')

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-bin',type=Path,default=BIN);p.add_argument('--out-dir',type=Path,default=ROOT/'reports/ultrasonic_cm_20261101/chain');a=p.parse_args()
 b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
 def run(name,top,files):
  files=[ROOT/f for f in files];h={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files};start=time.monotonic()
  cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(ROOT/'src').as_posix(),'-I'+(ROOT/'sim').as_posix(),'-s',top,'-o',(o/(name+'.vvp')).as_posix()]+[f.as_posix() for f in files]
  c=subprocess.run(cmd,cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf8');(o/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf8');assert c.returncode==0,c.stderr
  v=subprocess.run([str(b/'vvp.exe'),(o/(name+'.vvp')).as_posix()],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf8',timeout=180);log=v.stdout+v.stderr;(o/(name+'.log')).write_text(log,encoding='utf8');print(log,flush=True)
  assert v.returncode==0 and 'PASS '+top in log,log
  assert all(hashlib.sha256(f.read_bytes()).hexdigest()==h[str(f)] for f in files),'Inputs changed during test'
  results.append(dict(name=name,passed=True,checks=int(re.search(r'checks=(\d+)',log)[1]),seconds=time.monotonic()-start,source_sha256=h,command=cmd,output=log))
 try:
  baseline=ROOT/'reports/ultrasonic_cm_20261101/baseline'
  for n in ('ultrasonic_range','ultrasonic_pitch'):
   raw=(baseline/(n+'.sv')).read_text();(o/('baseline_'+n+'.sv')).write_text(raw.replace('module '+n,'module baseline_'+n,1),encoding='utf8')
  run('old_unit_bug','tb_ultrasonic_mm_bug',[o/'baseline_ultrasonic_range.sv',o/'baseline_ultrasonic_pitch.sv','sim/integration/tb_ultrasonic_mm_bug.sv'])
  run('range_regression','tb_ultrasonic_range',['src/ultrasonic_range.sv','sim/tb_ultrasonic_range.sv'])
  run('physical_echo_chain','tb_ultrasonic_cm_echo',['src/ultrasonic_range.sv','src/ultrasonic_pitch.sv','sim/integration/tb_ultrasonic_cm_echo.sv'])
  run('production_clock_echo','tb_ultrasonic_cm_clock',['src/ultrasonic_range.sv','sim/integration/tb_ultrasonic_cm_clock.sv'])
  run('cm_screen_labels','tb_ultrasonic_cm_ui',['src/rgb_ui_renderer.sv','src/ui_theme_art.sv','src/lissajous_plot.sv','sim/integration/tb_ultrasonic_cm_ui.sv'])
 finally:
  (o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] for t in results),all_passed=len(results)==5,sta_passed=False,hardware_tested=False),indent=2)+'\n',encoding='utf8')

if __name__=='__main__':main()
