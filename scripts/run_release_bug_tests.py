"""Release-drain reproduction and end-to-end key/envelope checks, no EDA."""
from pathlib import Path
import argparse,subprocess,os,json,hashlib,time,re,shutil
p=argparse.ArgumentParser();p.add_argument('--tool-bin',type=Path,required=True);p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--baseline-only',action='store_true');p.add_argument('--admission-only',action='store_true');a=p.parse_args()
r=Path(__file__).resolve().parents[1];b=a.tool_bin.resolve();o=a.out_dir.resolve();o.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env['PATH']=str(b)+os.pathsep+env['PATH']
names=['src/key_note_events.sv','src/touch_keyboard_router.sv','src/manual_event_arbiter.sv','src/voice_allocator.sv','src/adsr_envelope.sv','src/instrument_envelope.sv','src/sustain_envelope.sv','src/config/ui_layout.svh','src/config/keyboard_notes.svh','src/config/synth_config.svh','sim/integration/tb_release_drain.sv']
files=[r/n for n in names];before={n:hashlib.sha256((r/n).read_bytes()).hexdigest() for n in names};results=[]
for voices in ([] if a.admission_only else [4] if a.baseline_only else [1,4,32]):
 top='tb_release_drain';stem='voices'+str(voices);start=time.monotonic()
 cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'src').as_posix(),'-I'+(r/'sim').as_posix(),'-s',top,'-P'+top+'.VOICES='+str(voices),'-o',(o/(stem+'.vvp')).as_posix()]+[f.as_posix() for f in files if f.suffix=='.sv']
 c=subprocess.run(cmd,cwd=r,env=env,text=True,capture_output=True,encoding='utf-8');(o/(stem+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 v=subprocess.run([str(b/'vvp.exe'),(o/(stem+'.vvp')).as_posix()],cwd=r,env=env,text=True,capture_output=True,encoding='utf-8',timeout=180);log=v.stdout+v.stderr;(o/(stem+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 if a.baseline_only:
  assert v.returncode!=0 and 'release stranded while admission disabled' in log,'Baseline did not reproduce the intended failure'
  shutil.copyfile(r/'src/key_note_events.sv',o/'key_note_events_before.sv')
 else:assert v.returncode==0 and 'PASS '+top in log,log
 m=re.search(r'checks=(\d+)',log)
 results.append(dict(voices=voices,baseline_reproduced=a.baseline_only,passed=not a.baseline_only,checks=int(m[1]) if m else 0,seconds=round(time.monotonic()-start,3),output=log))
 assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==digest for n,digest in before.items()),'Inputs changed during test'
 (o/'validation.json').write_text(json.dumps(dict(tests=results,source_sha256=before,baseline_only=a.baseline_only,sta_passed=False,hardware_tested=False),indent=2),encoding='utf-8')
if not a.baseline_only:
 top='tb_release_admission';selected=[r/'src/key_note_events.sv',r/'sim/integration/tb_release_admission.sv'];hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in selected}
 cmd=[str(b/'iverilog.exe'),'-g2012','-grelative-include','-I'+(r/'src').as_posix(),'-s',top,'-o',(o/'admission.vvp').as_posix()]+[f.as_posix() for f in selected]
 c=subprocess.run(cmd,cwd=r,env=env,text=True,capture_output=True,encoding='utf-8');(o/'admission_compile.log').write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 v=subprocess.run([str(b/'vvp.exe'),(o/'admission.vvp').as_posix()],cwd=r,env=env,text=True,capture_output=True,encoding='utf-8',timeout=180);log=v.stdout+v.stderr;(o/'admission.log').write_text(log,encoding='utf-8');print(log,flush=True)
 assert v.returncode==0 and 'PASS '+top in log,log
 assert all(hashlib.sha256((r/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
 results.append(dict(name=top,passed=True,checks=int(re.search(r'checks=(\d+)',log)[1]),source_sha256=hashes,output=log))
 (o/'validation.json').write_text(json.dumps(dict(tests=results,source_sha256=before,baseline_only=False,sta_passed=False,hardware_tested=False),indent=2),encoding='utf-8')
