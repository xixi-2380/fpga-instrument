"""Focused equivalence/regression checks; never launches Gowin or programs hardware."""
import os,argparse,hashlib,importlib.util,json,random,re,shutil,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--out-dir',type=Path,required=True);p.add_argument('--iverilog',default=shutil.which('iverilog'));p.add_argument('--vvp',default=shutil.which('vvp'));p.add_argument('--ivl-base');a=p.parse_args()
r=Path(__file__).resolve().parents[1];out=a.out_dir.resolve();out.mkdir(parents=True,exist_ok=True)
assert a.iverilog and a.vvp,'Install Icarus Verilog or provide --iverilog and --vvp'
env=os.environ.copy();env['PATH']=str(Path(a.iverilog).resolve().parent)+os.pathsep+env.get('PATH','')
results=[]
def run(top,sources,params=None,extra=None):
 name=top+''.join('_'+k+str(v) for k,v in (params or {}).items());start=time.monotonic()
 files=[r/f for f in sources];hashes={str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 cmd=[a.iverilog]+(['-B',a.ivl_base] if a.ivl_base else [])+['-g2012','-Wall','-grelative-include','-I'+(r/'src').as_posix(),'-I'+(r/'sim').as_posix(),'-s',top,'-o',str(out/(name+'.vvp'))]
 for k,v in (params or {}).items():cmd+=['-P',top+'.'+k+'='+str(v)]
 c=subprocess.run(cmd+[f.as_posix() for f in files],cwd=r,env=env,capture_output=True,text=True,encoding='utf-8')
 (out/(name+'_compile.log')).write_text(c.stdout+c.stderr);assert c.returncode==0,c.stderr
 v=subprocess.run([a.vvp,str(out/(name+'.vvp'))]+(extra or []),cwd=r,env=env,capture_output=True,text=True,encoding='utf-8',timeout=180)
 log=v.stdout+v.stderr;(out/(name+'.log')).write_text(log)
 assert v.returncode==0 and 'PASS '+top in log,log
 assert all(hashlib.sha256((r/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
 n=re.search(r'checks=(\d+)',log)
 results.append(dict(name=name,passed=True,checks=int(n[1]) if n else None,seconds=round(time.monotonic()-start,3),source_sha256=hashes,output=log))
 print(log.splitlines()[0],flush=True)
try:
 for fixed,hold in [(0,0),(1,0),(1,240)]:
  run('tb_pnr_limiter_equivalence',['src/audio_limiter.sv','sim/reference_audio_limiter_c6352fa.sv','sim/tb_pnr_limiter_equivalence.sv'],dict(FIXED=fixed,HOLD=hold))
 run('tb_pnr_pcb_equivalence',['src/pcb_debug_ui.sv','sim/reference_pcb_debug_ui_c6352fa.sv','sim/tb_pnr_pcb_equivalence.sv'])
 for top in ['tb_pcb_debug_ui','tb_pcb_readable']:
  run(top,['src/pcb_debug_ui.sv','sim/'+top+'.sv'])
 # Reuse the independent Python window model, without its WAV-rendering main.
 spec=importlib.util.spec_from_file_location('limiter_model',r/'scripts/reference_audio_limiter.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 for fixed,hold in [(0,0),(1,0),(1,240)]:
  rng=random.Random(143);model=m.Limiter(release_hold=hold);packed=[]
  values=[0]*80+[32767,-32768,1,-1,0]*250+[rng.randrange(-32768,32768) for _ in range(900)]+[0]*600
  for i,value in enumerate(values):
   reset=i in (0,323,1000,1800)
   if reset:model=m.Limiter(release_hold=hold)
   y,g=model.step(value);packed.append((int(reset)<<49)|((value&65535)<<33)|(g<<16)|(y&65535))
  vec=out/('independent_hold'+str(hold)+'.hex');vec.write_text(f'{len(packed):016x}\n'+''.join(f'{x:016x}\n' for x in packed))
  run('tb_audio_limiter',['src/audio_limiter.sv','sim/tb_audio_limiter.sv'],dict(FIXED=fixed,HOLD=hold),['+LIMITER_VECTORS='+str(vec)])
finally:
 config=r/'src/config/ui_layout.svh'
 report=dict(baseline_commit='c6352faf09e1e110291e24130079fdd3ae94acdd',tests=results,all_tests_completed=len(results)==9,checks=sum(x['checks'] or 0 for x in results),config_sha256=hashlib.sha256(config.read_bytes()).hexdigest(),gowin_synthesis_run=False,pnr_run=False,hardware_tested=False)
 (out/'validation.json').write_text(json.dumps(report,indent=2))
