"""Independent control/CDC/integer-reference checks, no EDA or hardware."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--suite',choices=['all','timbre','ultra','sensitivity','performance'],default='all');a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH'];results=[]
cases={'timbre':['src/timbre_control.sv'],'ultra':['src/ultrasonic_pitch.sv'],'sensitivity':['src/keyboard_sensitivity.sv','src/bt_event_cdc.sv','src/rgb_status_cdc.sv','src/reset_sync.sv'],'performance':['src/performance_control.sv']}
try:
 for name,dependencies in cases.items():
  if a.suite not in ['all',name]:continue
  top='tb_controls_'+name;files=[r/n for n in dependencies]+[r/'sim/integration'/(top+'.sv')];included=[r/'src/config/ui_layout.svh',r/'src/config/synth_config.svh',r/'src/config/keyboard_notes.svh'];hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files+included};start=time.monotonic()
  cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'src').as_posix(),'-I'+(r/'sim').as_posix(),'-s',top,'-o',(o/(name+'.vvp')).as_posix()]+[f.as_posix() for f in files]
  c=subprocess.run(cmd,cwd=r,env=env,text=True,capture_output=True,encoding='utf-8');(o/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
  v=subprocess.run([str(b/'vvp.exe'),(o/(name+'.vvp')).as_posix()],cwd=r,env=env,text=True,capture_output=True,encoding='utf-8',timeout=180);log=v.stdout+v.stderr;(o/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
  assert v.returncode==0 and 'PASS '+top in log,log
  assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),'Inputs changed; this run must be repeated'
  results.append(dict(name=name,passed=True,checks=int(re.search(r'checks=(\d+)',log)[1]),seconds=round(time.monotonic()-start,3),source_sha256=hashes,compile_command=cmd,output=log))
finally:(o/'validation.json').write_text(json.dumps(dict(tests=results,total_checks=sum(t['checks'] for t in results),sta_passed=False,hardware_tested=False),indent=2),encoding='utf-8')
