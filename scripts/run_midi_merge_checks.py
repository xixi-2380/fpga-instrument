"""MIDI/Flash checks for the merged sustain release; no hardware programming."""
import argparse,concurrent.futures,hashlib,json,os,pathlib,subprocess,sys,time
p=argparse.ArgumentParser();p.add_argument('--out-dir',required=True);p.add_argument('--jobs',type=int,default=3);a=p.parse_args()
r=pathlib.Path(__file__).resolve().parents[1];out=r/a.out_dir;out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs={f.relative_to(r).as_posix():sha(f) for folder in ['src','sim','android/app/src/main','android/tests'] for f in sorted((r/folder).rglob('*')) if f.is_file()}
(out/'source_manifest.json').write_text(json.dumps(inputs,indent=2),encoding='utf8')
jdk=r/'android/build-local/jdk17/jdk-17.0.21.0.2+1/bin';assert (jdk/'java.exe').exists()
env=os.environ.copy();env['PATH']=str(jdk)+os.pathsep+env['PATH']
v=subprocess.run([sys.executable,'android/run_core_tests.py','--out-dir',str(out/'android')],cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace')
(out/'android_runner.log').write_text(v.stdout+v.stderr,encoding='utf8');assert v.returncode==0,v.stdout+v.stderr
print('PASS Android core groups4',flush=True)
tests=[('midi_protocol','tb_midi_protocol',[],False),('midi_flash','tb_midi_flash',[],False),('midi_top','tb_midi_top',[],True),('midi_menu','tb_midi_menu',[],True),('midi_audio26','tb_midi_audio',[],False),('multitimbral','tb_multitimbral',[],False),('flash4096_fast','tb_midi_flash_production',['COUNT=4096','HALF=4','PROGRAM_BUSY=100','ERASE_BUSY=200'],False),('flash4096_1mhz','tb_midi_flash_production',['COUNT=4096','HALF=25'],False)]
def run(c):
 name,test,params,pll=c;d=out/name;d.mkdir(exist_ok=True);cmd=[sys.executable,'scripts/run_sim.py','--test',test,'--out-dir',str(d)]
 if pll:cmd+=['--behavioral-pll']
 for x in params:cmd+=['--param',x]
 start=time.monotonic();v=subprocess.run(cmd,cwd=r,env=env,capture_output=True,text=True,encoding='utf8',errors='replace',timeout=15000)
 (d/'runner.log').write_text(v.stdout+v.stderr,encoding='utf8');result=dict(name=name,test=test,parameters=params,passed=v.returncode==0,seconds=round(time.monotonic()-start,2));(d/'result.json').write_text(json.dumps(result,indent=2),encoding='utf8');print(('PASS ' if result['passed'] else 'FAIL ')+name,flush=True)
 if not result['passed']:print((v.stdout+v.stderr)[-2000:],flush=True)
 return result
with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,tests))
same=all(sha(r/f)==v for f,v in inputs.items());android=json.loads((out/'android/summary.json').read_text(encoding='utf8'))
(out/'validation.json').write_text(json.dumps(dict(passed=all(x['passed'] for x in results) and same and android['passed'],sources_unchanged=same,results=results,android=android),indent=2),encoding='utf8')
raise SystemExit(0 if all(x['passed'] for x in results) and same and android['passed'] else 1)
